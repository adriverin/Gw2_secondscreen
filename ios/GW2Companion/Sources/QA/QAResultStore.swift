import Foundation

@MainActor
final class QAResultStore: ObservableObject {
    static let persistenceKey = "qa.hardware.results.v1"
    static let revealIdentityKey = "qa.reveal.identity"

    @Published private(set) var results: [String: QACheckResult]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.persistenceKey),
           let decoded = try? JSONDecoder().decode([String: QACheckResult].self, from: data) {
            results = decoded
        } else {
            results = [:]
        }
    }

    func result(for id: String) -> QACheckResult {
        results[id] ?? QACheckResult(id: id)
    }

    func record(
        id: String,
        state: QAResultState,
        note: String? = nil,
        severity: QASeverity? = nil,
        now: Date = Date()
    ) {
        var value = result(for: id)
        value.state = state
        value.note = note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true ? nil : note
        value.testedAt = state == .notTested ? nil : now
        value.severity = state == .failed ? severity : nil
        results[id] = value
        persist()
    }

    func reset() {
        results = [:]
        persist()
    }

    var failedResults: [QACheckResult] {
        results.values.filter { $0.state == .failed }.sorted { $0.id < $1.id }
    }

    var counts: (passed: Int, failed: Int, notTested: Int) {
        var passed = 0
        var failed = 0
        var notTested = 0
        for check in QACatalog.checks {
            switch result(for: check.id).state {
            case .passed: passed += 1
            case .failed: failed += 1
            case .notTested: notTested += 1
            }
        }
        return (passed, failed, notTested)
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(results), forKey: Self.persistenceKey)
    }
}
