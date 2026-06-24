import Combine
import Darwin
import Foundation

struct SessionInfo: Identifiable, Equatable {
    let id: String
    var pid: Int?
    var cwd: String?
    var name: String?
    var state: MascotState
    var lastSeen: Date
}

class SessionTracker: ObservableObject {
    @Published private(set) var sessions: [SessionInfo] = []
    @Published private(set) var hiddenSessionIDs: Set<String> = []
    @Published private(set) var customNames: [String: String] = [:]
    private var sessionMap: [String: SessionInfo] = [:]

    /// Record an incoming event. Returns sessions evicted because this event's
    /// pid now belongs to a different session_id (so callers can drop their mascots).
    @discardableResult
    func record(_ event: SpeakiEvent, at date: Date = Date()) -> [SessionInfo] {
        var info = sessionMap[event.sessionId] ?? SessionInfo(
            id: event.sessionId,
            pid: nil,
            cwd: nil,
            name: nil,
            state: event.state,
            lastSeen: date
        )
        info.state = event.state
        info.lastSeen = date
        if let pid = event.pid {
            info.pid = pid
        }
        if let cwd = event.cwd {
            info.cwd = cwd
        }
        if let name = event.name {
            info.name = name
        }
        sessionMap[event.sessionId] = info

        // A single Claude process hosts one session at a time. If this pid is now
        // associated with a new session_id, the previous session on that pid has
        // ended (/clear, resume, …) — evict it so its mascot doesn't linger as a
        // ghost. Pid-liveness alone never reaps it: the pid stays alive under the
        // new session.
        var evicted: [SessionInfo] = []
        if let pid = info.pid {
            let stale = sessionMap.filter { $0.key != event.sessionId && $0.value.pid == pid }
            for (id, other) in stale {
                sessionMap.removeValue(forKey: id)
                hiddenSessionIDs.remove(id)
                customNames.removeValue(forKey: id)
                evicted.append(other)
            }
        }

        publishSessions()
        return evicted
    }

    @discardableResult
    func pruneDeadProcesses(isAlive: (Int) -> Bool = { SessionTracker.isLiveClaudeProcess($0) }) -> [SessionInfo] {
        var pruned: [SessionInfo] = []
        for (id, info) in sessionMap {
            if let pid = info.pid, !isAlive(pid) {
                pruned.append(info)
                sessionMap.removeValue(forKey: id)
            }
        }
        if !pruned.isEmpty {
            for info in pruned {
                hiddenSessionIDs.remove(info.id)
                customNames.removeValue(forKey: info.id)
            }
            publishSessions()
        }
        return pruned
    }

    var anyWorking: Bool {
        sessionMap.values.contains { $0.state == .working }
    }

    // MARK: - Process liveness

    /// True if `pid` is alive *and* still a Claude Code process. Guards against
    /// pid reuse: when a finished session's pid is recycled by an unrelated
    /// process, `kill(pid, 0)` alone would keep the ghost mascot alive forever.
    static func isLiveClaudeProcess(_ pid: Int) -> Bool {
        isLiveClaude(alive: kill(Int32(pid), 0) == 0, identity: processIdentity(pid))
    }

    /// Pure decision seam (testable): given liveness and the process's executable
    /// path, should we keep the session? Conservative — an unreadable identity
    /// (nil) is treated as still-Claude, so we never reap a session we can't
    /// positively disprove.
    static func isLiveClaude(alive: Bool, identity: String?) -> Bool {
        guard alive else { return false }
        guard let identity = identity else { return true }
        return identity.lowercased().contains("claude")
    }

    /// The executable path for `pid` (e.g. …/share/claude/versions/X), or nil if
    /// it can't be read (no such process / insufficient privilege).
    private static func processIdentity(_ pid: Int) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(Int32(pid), &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    /// The Claude Code process pid for a session, used to focus its terminal.
    func pid(for sessionID: String) -> Int? {
        sessionMap[sessionID]?.pid
    }

    /// The working directory for a session, used to match its window by title.
    func cwd(for sessionID: String) -> String? {
        sessionMap[sessionID]?.cwd
    }

    func hide(_ id: String) {
        hiddenSessionIDs.insert(id)
    }

    func show(_ id: String) {
        hiddenSessionIDs.remove(id)
    }

    func toggleHidden(_ id: String) {
        if hiddenSessionIDs.contains(id) {
            hiddenSessionIDs.remove(id)
        } else {
            hiddenSessionIDs.insert(id)
        }
    }

    func isHidden(_ id: String) -> Bool {
        hiddenSessionIDs.contains(id)
    }

    /// Set a custom label for a session. Empty/whitespace clears it (reverts to auto).
    func setCustomName(_ name: String?, for id: String) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            customNames.removeValue(forKey: id)
        } else {
            customNames[id] = trimmed
        }
    }

    func customName(for id: String) -> String? {
        customNames[id]
    }

    /// The label to show for a session: custom name if set, else the last auto name.
    func displayName(for id: String) -> String? {
        customNames[id] ?? sessionMap[id]?.name
    }

    private func publishSessions() {
        sessions = sessionMap.values.sorted { $0.lastSeen > $1.lastSeen }
    }
}
