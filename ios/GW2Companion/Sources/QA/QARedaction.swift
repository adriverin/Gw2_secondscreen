import Foundation

struct QARedactionSecrets: Equatable, Sendable {
    var apiKey: String?
    var pairingToken: String?
    var accountName: String?
    var characterNames: [String]
    var portraitURLs: [String]

    static let empty = QARedactionSecrets(
        apiKey: nil, pairingToken: nil, accountName: nil, characterNames: [], portraitURLs: [])
}

enum QARedaction {
    static let redacted = "redacted"
    static let omitted = "[redacted]"

    static func name(_ value: String?, reveal: Bool) -> String {
        guard let value, !value.isEmpty else { return "—" }
        return reveal ? value : redacted
    }

    static func apiPath(_ path: String) -> String {
        var result = path
        let marker = "characters/"
        if let start = result.range(of: marker) {
            let after = start.upperBound
            let remainder = result[after...]
            let end = remainder.firstIndex(where: { $0 == "/" || $0 == "?" }) ?? result.endIndex
            if after < end {
                result.replaceSubrange(after..<end, with: "{name}")
            }
        }
        return result
    }

    static func scrub(_ text: String, secrets: QARedactionSecrets) -> String {
        var result = text
        let replacements: [String] = {
            var values: [String] = []
            if let apiKey = secrets.apiKey, apiKey.count >= 8 { values.append(apiKey) }
            if let token = secrets.pairingToken, token.count >= 8 { values.append(token) }
            if let account = secrets.accountName, account.count >= 3 { values.append(account) }
            values.append(contentsOf: secrets.characterNames.filter { $0.count >= 2 })
            values.append(contentsOf: secrets.portraitURLs.filter { !$0.isEmpty })
            return values.sorted { $0.count > $1.count }
        }()
        for secret in replacements {
            result = result.replacingOccurrences(of: secret, with: omitted)
        }
        return result
    }

    static func containsUnredactedSecrets(_ text: String, secrets: QARedactionSecrets) -> Bool {
        if let apiKey = secrets.apiKey, apiKey.count >= 8, text.contains(apiKey) { return true }
        if let token = secrets.pairingToken, token.count >= 8, text.contains(token) { return true }
        return false
    }
}
