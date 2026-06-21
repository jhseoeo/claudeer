import AppKit
import ApplicationServices

/// Brings the host of a Claude Code session to the front when its mascot is
/// double-clicked.
///
/// `notify.py` sends the Claude Code process pid (its `os.getppid()`) and the
/// session `cwd`. That process runs inside a terminal/IDE (Terminal, iTerm2,
/// Ghostty, VS Code, …), so we walk up the process tree from the pid until we
/// hit a regular GUI application.
///
/// Multiple sessions can live inside ONE app (e.g. several project windows in
/// the same IDE), possibly spread across macOS Spaces. We focus the EXACT window
/// whose title contains the session's `cwd` folder name — switching to its Space
/// if needed — via `PrivateWindowApi`. Falls back to plain app activation when
/// the window can't be found or Accessibility isn't granted.
enum WindowFocuser {
    /// Focus a session's host window (any Space), or fall back to its app.
    /// Expected to be called off the main thread: the off-Space window search can
    /// take a few hundred ms.
    static func focus(pid: Int, cwd: String?) {
        guard let appPID = hostAppPID(of: pid) else { return }
        if let needle = folderName(cwd) {
            if AXIsProcessTrusted() {
                if PrivateWindowApi.focusWindow(pid: pid_t(appPID), titleContains: needle) {
                    return
                }
            } else {
                requestAccessibilityPrompt()
            }
        }
        // Fallback: bring the whole app forward (activation must run on main).
        DispatchQueue.main.async {
            NSRunningApplication(processIdentifier: pid_t(appPID))?.activate(options: [.activateAllWindows])
        }
    }

    /// The GUI application pid hosting `pid`, found by walking the process tree.
    static func hostAppPID(of pid: Int) -> Int? {
        let appPIDs = runningAppPIDs()
        return ancestorPID(startPID: pid, parentOf: parentPID(of:), isApp: { appPIDs.contains($0) })
    }

    /// The last path component of a directory path (the project folder name).
    static func folderName(_ path: String?) -> String? {
        guard let path = path else { return nil }
        var trimmed = path
        while trimmed.count > 1 && trimmed.hasSuffix("/") { trimmed.removeLast() }
        let base = (trimmed as NSString).lastPathComponent
        return (base.isEmpty || base == "/") ? nil : base
    }

    // MARK: - Process tree

    /// Walk the parent chain from `startPID` and return the first pid (including
    /// `startPID`) for which `isApp` is true. launchd (pid 1) is never considered.
    /// Pure + injectable so the traversal is unit-testable.
    static func ancestorPID(
        startPID: Int,
        parentOf: (Int) -> Int?,
        isApp: (Int) -> Bool,
        maxDepth: Int = 40
    ) -> Int? {
        var current: Int? = startPID
        var depth = 0
        while let pid = current, pid > 1, depth < maxDepth {
            if isApp(pid) { return pid }
            current = parentOf(pid)
            depth += 1
        }
        return nil
    }

    /// Parent pid of `pid` via sysctl, or nil if it can't be resolved.
    static func parentPID(of pid: Int) -> Int? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, Int32(pid)]
        let result = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        guard result == 0, size > 0 else { return nil }
        let ppid = Int(info.kp_eproc.e_ppid)
        return ppid > 0 ? ppid : nil
    }

    private static func runningAppPIDs() -> Set<Int> {
        Set(
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .map { Int($0.processIdentifier) }
        )
    }

    // MARK: - Accessibility

    private static var didPromptAccessibility = false

    /// Show the system Accessibility permission prompt once. The option key is the
    /// documented literal value of `kAXTrustedCheckOptionPrompt` (used directly to
    /// avoid CFString-import ambiguity across SDKs).
    private static func requestAccessibilityPrompt() {
        guard !didPromptAccessibility else { return }
        didPromptAccessibility = true
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
