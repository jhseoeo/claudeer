import Foundation

/// Sends a push to ntfy.sh (or a self-hosted ntfy server) on idle transitions.
/// Uses ntfy's JSON publishing mode so non-ASCII titles/messages survive
/// (HTTP headers are latin-1, JSON bodies are UTF-8). Fire-and-forget: network
/// errors are ignored, matching the app's "fail silently" philosophy.
final class NtfyNotifier {
    typealias Transport = (URLRequest) -> Void

    var settings: NtfySettings
    private let transport: Transport

    init(settings: NtfySettings, transport: @escaping Transport = NtfyNotifier.defaultTransport) {
        self.settings = settings
        self.transport = transport
    }

    func notify(title: String, body: String) {
        guard settings.enabled else { return }
        let topic = settings.topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !topic.isEmpty, let url = URL(string: settings.server) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = settings.token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let payload = ["topic": topic, "title": title, "message": body]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        transport(request)
    }

    static let defaultTransport: Transport = { request in
        URLSession.shared.dataTask(with: request).resume()
    }
}
