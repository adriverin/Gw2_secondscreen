import SwiftUI

enum AppTab: Hashable, CaseIterable, Identifiable {
    case map, goals, session, characters, inventory, account
    var id: Self { self }
    var title: String {
        switch self { case .map: "Map"; case .goals: "Goals"; case .session: "Session"; case .characters: "Characters"; case .inventory: "Inventory"; case .account: "Account" }
    }
    var symbol: String {
        switch self { case .map: "map.fill"; case .goals: "target"; case .session: "checklist"; case .characters: "person.2.fill"; case .inventory: "shippingbox.fill"; case .account: "person.crop.circle" }
    }
}
enum CharacterSection: String, CaseIterable, Hashable { case equipment, build, inventory }

struct CharacterRoute: Hashable {
    let name: String
    let section: CharacterSection
}

@MainActor
final class AppNavigation: ObservableObject {
    @Published var selectedTab: AppTab = .map
    @Published var characterPath: [CharacterRoute] = []

    func showCharacter(_ name: String, section: CharacterSection = .equipment) {
        characterPath = [CharacterRoute(name: name, section: section)]
        selectedTab = .characters
    }
}
