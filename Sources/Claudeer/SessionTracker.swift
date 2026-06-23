import Combine
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

    func record(_ event: SpeakiEvent, at date: Date = Date()) {
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
        publishSessions()
    }

    @discardableResult
    func pruneDeadProcesses(isAlive: (Int) -> Bool = { kill(Int32($0), 0) == 0 }) -> [SessionInfo] {
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
