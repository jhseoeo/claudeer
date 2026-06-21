import AppKit
import Carbon  // ProcessSerialNumber

/// Focuses a specific window — including one on another Space — the way a real
/// click does, WITHOUT disabling SIP. This is the technique AltTab/yabai use:
///
///  1. `_SLPSSetFrontProcessWithOptions(psn, wid, userGenerated)` fronts the
///     process and that one window.
///  2. `makeKeyWindow` posts a synthetic mouse down/up (aimed just outside the
///     window) so it becomes key without clicking any content.
///  3. `AXUIElementPerformAction(window, kAXRaise)` raises it.
///
/// All three together make macOS perform its OWN clean Space switch to the
/// window's Space (unlike `CGSManagedDisplaySetCurrentSpace`, which leaves a
/// jumbled half-switched state). The window is never moved between Spaces.
///
/// To target a window on another Space we need its AX element, which
/// `kAXWindowsAttribute` won't return for off-Space windows — so we brute-force
/// `_AXUIElementCreateWithRemoteToken` (matching by `_AXUIElementGetWindow`),
/// reading titles via AX (needs only Accessibility, not Screen Recording).
///
/// Every symbol is resolved with dlsym; if any is missing on a future macOS the
/// whole thing reports unavailable and callers fall back to plain app activation.
enum PrivateWindowApi {
    private typealias SetFrontFn = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UInt32, UInt32) -> Int32
    private typealias PostEventFn = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> Int32
    private typealias RemoteTokenFn = @convention(c) (CFData) -> Unmanaged<AXUIElement>?
    private typealias GetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<UInt32>) -> Int32
    private typealias GetProcessFn = @convention(c) (Int32, UnsafeMutablePointer<ProcessSerialNumber>) -> Int32

    private static func load<T>(_ handle: UnsafeMutableRawPointer?, _ name: String, _ type: T.Type) -> T? {
        guard let handle = handle, let ptr = dlsym(handle, name) else { return nil }
        return unsafeBitCast(ptr, to: type)
    }

    private static let skylight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private static let defaultImage = dlopen(nil, RTLD_LAZY)  // ApplicationServices: private AX + GetProcessForPID

    private static let setFrontProcess = load(skylight, "_SLPSSetFrontProcessWithOptions", SetFrontFn.self)
    private static let postEvent = load(skylight, "SLPSPostEventRecordTo", PostEventFn.self)
    private static let createWithRemoteToken = load(defaultImage, "_AXUIElementCreateWithRemoteToken", RemoteTokenFn.self)
    private static let getWindow = load(defaultImage, "_AXUIElementGetWindow", GetWindowFn.self)
    private static let getProcessForPID = load(defaultImage, "GetProcessForPID", GetProcessFn.self)

    /// True if every private symbol resolved.
    static var isAvailable: Bool {
        setFrontProcess != nil && postEvent != nil && createWithRemoteToken != nil
            && getWindow != nil && getProcessForPID != nil
    }

    private static let userGeneratedFront: UInt32 = 0x200  // SLPSMode.userGenerated

    /// Focus the app `pid`'s window whose AX title contains `needle`, switching to
    /// its Space if needed. Returns true if the window was found and focused.
    /// `searchBudget` caps the off-Space brute-force search.
    @discardableResult
    static func focusWindow(pid: pid_t, titleContains needle: String, searchBudget: TimeInterval = 0.3) -> Bool {
        guard isAvailable, let (element, wid) = findWindow(pid: pid, titleContains: needle, budget: searchBudget) else {
            return false
        }
        guard let getProcessForPID, let setFrontProcess else { return false }
        var psn = ProcessSerialNumber()
        guard getProcessForPID(Int32(pid), &psn) == 0 else { return false }
        _ = setFrontProcess(&psn, wid, userGeneratedFront)
        makeKeyWindow(&psn, wid)
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        return true
    }

    /// Locate (AX element, window id) for the matching window: current-Space
    /// windows first (fast), then all Spaces via remote tokens.
    private static func findWindow(pid: pid_t, titleContains needle: String, budget: TimeInterval) -> (AXUIElement, CGWindowID)? {
        let lower = needle.lowercased()
        guard let getWindow else { return nil }

        // 1. Current-Space windows via the normal AX API.
        let appElement = AXUIElementCreateApplication(pid)
        var windowsValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
           let windows = windowsValue as? [AXUIElement] {
            for window in windows where title(of: window)?.lowercased().contains(lower) == true {
                var wid: CGWindowID = 0
                if getWindow(window, &wid) == 0, wid != 0 { return (window, wid) }
            }
        }

        // 2. All Spaces via remote tokens (covers other Spaces). 20-byte token:
        //    pid(4) + 0(4) + magic 0x636f636f(4) + axUiElementId(8).
        guard let createWithRemoteToken else { return nil }
        var token = Data(count: 20)
        var pidValue = pid
        var magic = Int32(0x636f636f)
        token.replaceSubrange(0..<4, with: withUnsafeBytes(of: &pidValue) { Data($0) })
        token.replaceSubrange(8..<12, with: withUnsafeBytes(of: &magic) { Data($0) })
        let deadline = Date().addingTimeInterval(budget)
        var axid: UInt64 = 0
        while Date() < deadline {
            withUnsafeBytes(of: &axid) { token.replaceSubrange(12..<20, with: $0) }
            axid += 1
            guard let element = createWithRemoteToken(token as CFData)?.takeRetainedValue() else { continue }
            var wid: CGWindowID = 0
            guard getWindow(element, &wid) == 0, wid != 0 else { continue }
            if title(of: element)?.lowercased().contains(lower) == true { return (element, wid) }
        }
        return nil
    }

    private static func title(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    /// Make `wid` the key window of its app by posting a synthetic left click
    /// (down then up) aimed just outside the window, so it becomes key without
    /// hitting any content. Byte layout reverse-engineered from CGSEvent.h (same
    /// as yabai/AltTab/Hammerspoon).
    private static func makeKeyWindow(_ psn: inout ProcessSerialNumber, _ wid: CGWindowID) {
        guard let postEvent else { return }
        var widValue = wid
        var point = CGPoint(x: -1, y: -1)
        var bytes = [UInt8](repeating: 0, count: 0x100)
        bytes[0x04] = 0xf8            // record length
        bytes[0x3a] = 0x10            // undocumented flag (yabai/Hammerspoon set 0x10)
        memcpy(&bytes[0x3c], &widValue, MemoryLayout<CGWindowID>.size)  // target window id
        memcpy(&bytes[0x20], &point, MemoryLayout<CGPoint>.size)        // off-content click point
        bytes[0x08] = 0x01           // kCGEventLeftMouseDown
        _ = postEvent(&psn, &bytes)
        bytes[0x08] = 0x02           // kCGEventLeftMouseUp
        _ = postEvent(&psn, &bytes)
    }
}
