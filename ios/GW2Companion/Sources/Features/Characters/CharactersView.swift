import SwiftUI

struct CharactersView: View {
    let api: GW2APIClient
    @EnvironmentObject private var telemetry: TelemetryStore
    @State private var characters: [GW2Character] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && characters.isEmpty { ProgressView("Loading characters…") }
                else if let errorMessage, characters.isEmpty { ContentUnavailableView("Characters unavailable", systemImage: "person.crop.circle.badge.exclamationmark", description: Text(errorMessage)) }
                else {
                    List(characters) { character in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(character.name).font(.headline)
                                Spacer()
                                if character.name == telemetry.latest?.character?.name {
                                    Text("● CURRENTLY PLAYING").font(.caption2.bold()).foregroundStyle(.green)
                                }
                            }
                            Text("\(character.profession) • Level \(character.level)").foregroundStyle(.secondary)
                            Text("Age: \(formattedAge(character.age))").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 5)
                    }
                    .refreshable { await load() }
                }
            }
            .navigationTitle("Characters")
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do { characters = try await api.characters(); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }

    private func formattedAge(_ seconds: Int) -> String {
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        return "\(days)d \(hours)h"
    }
}
