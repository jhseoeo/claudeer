import Combine
import Foundation

struct SessionInfo: Identifiable, Equatable {
    let id: String
    var pid: Int?
    var cwd: String?
    var state: MascotState
    var lastSeen: Date
}

class SessionTracker: ObservableObject {
    @Published private(set) var sessions: [SessionInfo] = []
    private var sessionMap: [String: SessionInfo] = [:]

    func record(_ event: SpeakiEvent, at date: Date = Date()) {
        var info = sessionMap[event.sessionId] ?? SessionInfo(
            id: event.sessionId,
            pid: nil,
            cwd: nil,
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

    private func publishSessions() {
        sessions = sessionMap.values.sorted { $0.lastSeen > $1.lastSeen }
    }
}
