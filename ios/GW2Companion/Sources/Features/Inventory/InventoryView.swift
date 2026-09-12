import SwiftUI

struct InventoryView: View {
    let api: GW2APIClient
    @State private var source: InventorySource = .character
    @State private var characterNames: [String] = []
    @State private var selectedCharacter = ""
    @State private var items: [DisplayInventoryItem] = []
    @State private var search = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var filteredItems: [DisplayInventoryItem] {
        search.isEmpty ? items : items.filter { $0.metadata.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && items.isEmpty { ProgressView("Loading inventory…") }
                else if let errorMessage, items.isEmpty { ContentUnavailableView("Inventory unavailable", systemImage: "shippingbox", description: Text(errorMessage)) }
                else {
                    List(filteredItems) { item in
                        HStack(spacing: 12) {
                            AsyncImage(url: item.metadata.icon) { image in image.resizable().scaledToFit() } placeholder: {
                                RoundedRectangle(cornerRadius: 5).fill(.quaternary).overlay(Image(systemName: "shippingbox"))
                            }
                            .frame(width: 38, height: 38)
                            VStack(alignment: .leading) {
                                Text(item.metadata.name)
                                Text(item.metadata.rarity).font(.caption).foregroundStyle(rarityColor(item.metadata.rarity))
                            }
                            Spacer()
                            Text(item.quantity.formatted()).monospacedDigit().bold()
                        }
                    }
                    .refreshable { await loadItems() }
                }
            }
            .navigationTitle("Inventory")
            .searchable(text: $search)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu(source.rawValue) {
                        Picker("Source", selection: $source) {
                            ForEach(InventorySource.allCases) { Text($0.rawValue).tag($0) }
                        }
                    }
                }
                if source == .character && !characterNames.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu(selectedCharacter.isEmpty ? "Character" : selectedCharacter) {
                            Picker("Character", selection: $selectedCharacter) {
                                ForEach(characterNames, id: \.self) { Text($0).tag($0) }
                            }
                        }
                    }
                }
            }
            .task { await loadCharactersThenItems() }
            .task(id: source) { if !characterNames.isEmpty { await loadItems() } }
            .task(id: selectedCharacter) { if source == .character && !selectedCharacter.isEmpty { await loadItems() } }
        }
    }

    private func loadCharactersThenItems() async {
        do {
            characterNames = try await api.characters().map(\.name)
            selectedCharacter = characterNames.first ?? ""
            await loadItems()
        } catch { errorMessage = error.localizedDescription }
    }

    private func loadItems() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let slots: [InventorySlot]
            switch source {
            case .character:
                guard !selectedCharacter.isEmpty else { return }
                slots = try await api.characterInventory(name: selectedCharacter)
            case .bank: slots = try await api.bank()
            case .shared: slots = try await api.sharedInventory()
            case .materials: slots = try await api.materials()
            }
            items = try await api.displayItems(slots)
            errorMessage = nil
        } catch { items = []; errorMessage = error.localizedDescription }
    }

    private func rarityColor(_ rarity: String) -> Color {
        switch rarity.lowercased() {
        case "legendary": .purple
        case "ascended": .pink
        case "exotic": .orange
        case "rare": .yellow
        case "masterwork": .green
        default: .secondary
        }
    }
}
