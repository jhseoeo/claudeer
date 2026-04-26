import Foundation

struct SpeakiEvent: Codable {
    let state: MascotState
    let sessionId: String
    let pid: Int?
    let cwd: String?

    enum CodingKeys: String, CodingKey {
        case state
        case sessionId = "session_id"
        case pid
        case cwd
    }
}

class EventServer {
    static let socketPath = "/tmp/claudeer.sock"

    private let lock = NSLock()
    private var _serverFD: Int32 = -1
    private var _running = false
    var onEvent: ((SpeakiEvent) -> Void)?

    private var serverFD: Int32 {
        get { lock.withLock { _serverFD } }
        set { lock.withLock { _serverFD = newValue } }
    }

    private var running: Bool {
        get { lock.withLock { _running } }
        set { lock.withLock { _running = newValue } }
    }

    func start() {
        unlink(EventServer.socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            print("Failed to create socket")
            return
        }
        serverFD = fd

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = EventServer.socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let raw = UnsafeMutableRawPointer(ptr)
            pathBytes.withUnsafeBufferPointer { buf in
                raw.copyMemory(from: buf.baseAddress!, byteCount: buf.count)
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(fd, sockPtr, addrLen)
            }
        }
        guard bindResult == 0 else {
            print("Failed to bind socket")
            close(fd)
            return
        }

        listen(fd, 5)
        running = true

        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.acceptLoop()
        }
        print("Event server listening on \(EventServer.socketPath)")
    }

    func stop() {
        running = false
        let fd = serverFD
        if fd >= 0 {
            serverFD = -1
            close(fd)
        }
        unlink(EventServer.socketPath)
    }

    private func acceptLoop() {
        while running {
            let fd = serverFD
            guard fd >= 0 else { break }
            let clientFD = accept(fd, nil, nil)
            guard clientFD >= 0 else {
                if !running { break }
                continue
            }
            DispatchQueue.global().async { [weak self] in
                self?.handleClient(fd: clientFD)
            }
        }
    }

    private func handleClient(fd: Int32) {
        defer { close(fd) }

        var buffer = [UInt8](repeating: 0, count: 4096)
        var accumulated = Data()

        while true {
            let bytesRead = read(fd, &buffer, buffer.count)
            guard bytesRead > 0 else { break }
            accumulated.append(contentsOf: buffer[..<bytesRead])
            if accumulated.contains(UInt8(ascii: "\n")) {
                break
            }
        }

        guard !accumulated.isEmpty else { return }

        if accumulated.last == UInt8(ascii: "\n") {
            accumulated.removeLast()
        }

        do {
            let event = try JSONDecoder().decode(SpeakiEvent.self, from: accumulated)
            DispatchQueue.main.async { [weak self] in
                self?.onEvent?(event)
            }
        } catch {
            print("Failed to parse event: \(error)")
        }

        let response = Data("{\"ok\":true}\n".utf8)
        response.withUnsafeBytes { ptr in
            _ = write(fd, ptr.baseAddress!, response.count)
        }
    }
}
