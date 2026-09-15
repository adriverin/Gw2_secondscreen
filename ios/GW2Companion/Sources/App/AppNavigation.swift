import SwiftUI

enum AppTab: Hashable, CaseIterable, Identifiable {
    case session, map, goals, inventory, characters, account, settings
    var id: Self { self }
    var title: String {
        switch self {
        case .map: "Map"
        case .goals: "Goals"
        case .session: "Today"
        case .characters: "Characters"
        case .inventory: "Inventory"
        case .account: "Account"
        case .settings: "Settings"
        }
    }
    var symbol: String {
        switch self {
        case .map: "map.fill"
        case .goals: "target"
        case .session: "checklist"
        case .characters: "person.2.fill"
        case .inventory: "shippingbox.fill"
        case .account: "person.crop.circle"
        case .settings: "gearshape.fill"
        }
    }

    static var iPhonePrimary: [AppTab] { [.session, .map, .goals, .inventory] }
    static var iPhoneMore: [AppTab] { [.characters, .account, .settings] }
    static var iPadSidebar: [AppTab] { [.session, .map, .goals, .characters, .inventory, .account, .settings] }
}

enum CharacterSection: String, CaseIterable, Hashable { case equipment, build, inventory }

struct CharacterRoute: Hashable {
    let name: String
    let section: CharacterSection
}

enum InventoryHubSection: String, CaseIterable, Identifiable, Hashable {
    case all, characters, bank, materials, shared
    var id: Self { self }
    var title: String {
        switch self {
        case .all: "All"
        case .characters: "Characters"
        case .bank: "Bank"
        case .materials: "Materials"
        case .shared: "Shared"
        }
    }
}

enum PhoneRootTab: Hashable {
    case session, map, goals, inventory, more
}

@MainActor
final class AppNavigation: ObservableObject {
    @Published var selectedTab: AppTab = .map {
        didSet {
            if AppTab.iPhoneMore.contains(selectedTab) { moreShowsList = false }
        }
    }
    @Published var moreShowsList = false
    @Published var characterPath: [CharacterRoute] = []
    @Published var inventorySection: InventoryHubSection = .all
    @Published var inventoryCharacterName: String?
    @Published var sidebarHidden = false
    @Published var navigatorHidden = false

    var splitColumnVisibility: NavigationSplitViewVisibility {
        get { sidebarHidden ? .detailOnly : .all }
        set { sidebarHidden = newValue == .detailOnly }
    }

    var mapChromeHidden: Bool { sidebarHidden && navigatorHidden }

    func toggleSidebar() { sidebarHidden.toggle() }
    func toggleNavigator() { navigatorHidden.toggle() }
    func toggleMapChrome() {
        let hide = !mapChromeHidden
        sidebarHidden = hide
        navigatorHidden = hide
    }

    var phoneRootTab: PhoneRootTab {
        get {
            if moreShowsList { return .more }
            switch selectedTab {
            case .session: return .session
            case .map: return .map
            case .goals: return .goals
            case .inventory: return .inventory
            case .characters, .account, .settings: return .more
            }
        }
        set {
            switch newValue {
            case .session: selectedTab = .session; moreShowsList = false
            case .map: selectedTab = .map; moreShowsList = false
            case .goals: selectedTab = .goals; moreShowsList = false
            case .inventory: selectedTab = .inventory; moreShowsList = false
            case .more: moreShowsList = true
            }
        }
    }

    func show(_ tab: AppTab) { selectedTab = tab }

    func showCharacter(_ name: String, section: CharacterSection = .equipment) {
        characterPath = [CharacterRoute(name: name, section: section)]
        selectedTab = .characters
    }

    func showInventory(_ section: InventoryHubSection, characterName: String? = nil) {
        inventorySection = section
        inventoryCharacterName = characterName
        selectedTab = .inventory
    }
}
