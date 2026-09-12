import Foundation

@main
struct WebSocketSmoke {
    static func main() async throws {
        guard CommandLine.arguments.count == 2, let url = URL(string: CommandLine.arguments[1]) else {
            throw SmokeError.usage
        }
        let socket = URLSession.shared.webSocketTask(with: url)
        socket.resume()
        defer { socket.cancel(with: .normalClosure, reason: nil) }

        var xValues: [Double] = []
        for _ in 0..<3 {
            let message = try await socket.receive()
            let data: Data
            switch message {
            case let .string(text): data = Data(text.utf8)
            case let .data(value): data = value
            @unknown default: continue
            }
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let player = object?["player"] as? [String: Any]
            if let x = player?["continentX"] as? Double { xValues.append(x) }
        }
        guard xValues.count >= 2, Set(xValues).count > 1 else { throw SmokeError.staticTelemetry }
        print("received changing telemetry: \(xValues.count) samples")
    }
}

enum SmokeError: Error { case usage, staticTelemetry }
