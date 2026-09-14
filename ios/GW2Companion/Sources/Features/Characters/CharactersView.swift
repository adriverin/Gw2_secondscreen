import PhotosUI
import SwiftUI

struct CharactersView: View {
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var navigation: AppNavigation

    var body: some View {
        NavigationStack(path: $navigation.characterPath) {
            Group {
                if account.connectionState == .loading && account.characters.isEmpty {
                    ProgressView("Loading characters…")
                } else if account.connectionState == .disconnected {
                    GWEmptyState(
                        title: "Connect your Guild Wars 2 account",
                        message: "View your characters, equipment, builds and inventory.",
                        symbol: "person.crop.circle.badge.plus",
                        actionTitle: "Connect Account",
                        action: { navigation.selectedTab = .account })
                } else if !account.permissions.contains(.characters) {
                    GWEmptyState(
                        title: "Character access isn't enabled",
                        message: "Create an API key with the characters permission.",
                        symbol: "person.crop.circle.badge.exclamationmark")
                } else if account.characters.isEmpty && account.errorMessage != nil {
                    GWEmptyState(
                        title: "Characters unavailable",
                        message: account.errorMessage ?? "Couldn't load your characters.",
                        symbol: "wifi.exclamationmark",
                        actionTitle: "Try Again") { Task { await account.refresh() } }
                } else {
                    characterGrid
                }
            }
            .navigationTitle("Characters")
            .navigationDestination(for: CharacterRoute.self) { route in
                if let character = account.characters.first(where: { $0.name == route.name }) {
                    CharacterDetailView(character: character, initialSection: route.section)
                } else {
                    GWEmptyState(title: "Character unavailable", message: "Refresh your account data and try again.", symbol: "person.slash")
                }
            }
            .toolbar {
                if account.isStale { ToolbarItem(placement: .topBarTrailing) { GWBadge(text: "SAVED", color: .orange, symbol: "clock") } }
            }
        }
    }

    private var characterGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 310, maximum: 520), spacing: 16)], spacing: 16) {
                if let error = account.errorMessage {
                    GWErrorBanner(message: error, stale: account.isStale) { Task { await account.refresh() } }
                        .gridCellColumns(2)
                }
                ForEach(account.characters) { character in
                    NavigationLink(value: CharacterRoute(name: character.name, section: .equipment)) {
                        CharacterCard(
                            character: character,
                            profession: account.professions[character.profession],
                            specialization: account.eliteSpecializationName(for: character),
                            isCurrent: account.currentCharacter?.name == character.name)
                    }
                    .buttonStyle(.plain)
                    .task { await account.loadCharacterDetails(character) }
                }
            }
            .padding()
        }
        .refreshable { await account.refresh() }
    }
}

private struct CharacterCard: View {
    let character: GW2Character
    let profession: ProfessionMetadata?
    let specialization: String?
    let isCurrent: Bool

    var body: some View {
        GWCard {
            HStack(alignment: .top, spacing: 14) {
                CachedAsyncImage(url: profession?.iconBig ?? profession?.icon) {
                    Image(systemName: "person.crop.circle.fill").resizable().scaledToFit().foregroundStyle(.secondary)
                }
                .frame(width: 62, height: 62)
                .padding(8)
                .background(GWPalette.profession(character.profession).opacity(0.16), in: RoundedRectangle(cornerRadius: 15))

                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(character.name).font(.headline)
                        Spacer()
                        if isCurrent { GWBadge(text: "LIVE", color: .green, symbol: "circle.fill") }
                    }
                    Text("\(specialization ?? character.profession) • \(character.race) • Level \(character.level)")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("\(formattedHours(character.age)) played")
                        .font(.subheadline.bold()).monospacedDigit()
                    if let crafting = character.crafting?.filter(\.active), !crafting.isEmpty {
                        Text(crafting.prefix(2).map { "\($0.discipline) \($0.rating)" }.joined(separator: " • "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(character.name), \(specialization ?? character.profession), level \(character.level)\(isCurrent ? ", currently playing" : "")")
    }
}

struct CharacterDetailView: View {
    let character: GW2Character
    @State private var section: CharacterSection
    @EnvironmentObject private var account: AccountStore
    @State private var portraitData: Data?
    @State private var selectedPhoto: PhotosPickerItem?

    init(character: GW2Character, initialSection: CharacterSection) {
        self.character = character
        _section = State(initialValue: initialSection)
    }

    private var detail: CharacterDetailData { account.characterDetails[character.name] ?? CharacterDetailData() }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                characterHeader
                Picker("Character section", selection: $section) {
                    ForEach(CharacterSection.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)

                if let error = detail.errorMessage {
                    GWErrorBanner(message: error, stale: !detail.equipmentTabs.isEmpty) {
                        Task { await account.loadCharacterDetails(character, force: true) }
                    }
                }

                Group {
                    switch section {
                    case .equipment:
                        EquipmentSection(character: character, detail: detail)
                    case .build:
                        BuildSection(detail: detail)
                    case .inventory:
                        CharacterInventorySection(detail: detail, fallbackItems: account.itemMetadata)
                    }
                }
            }
            .frame(maxWidth: 920)
            .padding()
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(character.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await account.loadCharacterDetails(character, force: true) }
        .task {
            await account.loadCharacterDetails(character)
            portraitData = await CharacterPortraitStore.shared.data(account: account.account?.name, character: character.name)
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                try? await CharacterPortraitStore.shared.save(data, account: account.account?.name, character: character.name)
                portraitData = await CharacterPortraitStore.shared.data(account: account.account?.name, character: character.name)
            }
        }
        .toolbar { portraitMenu }
    }

    private var characterHeader: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [GWPalette.profession(character.profession).opacity(0.68), .black.opacity(0.78)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(alignment: .bottom, spacing: 18) {
                Group {
                    if let portraitData, let image = UIImage(data: portraitData) {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        CachedAsyncImage(url: account.professions[character.profession]?.iconBig) {
                            Image(systemName: "person.crop.circle.fill").resizable().scaledToFit().padding(22)
                        }
                    }
                }
                .frame(width: 128, height: 150)
                .background(.black.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 7) {
                    if account.currentCharacter?.name == character.name {
                        GWBadge(text: "CURRENTLY PLAYING", color: .green, symbol: "circle.fill")
                    }
                    Text(character.name).font(.largeTitle.bold()).minimumScaleFactor(0.7)
                    Text("\(account.eliteSpecializationName(for: character) ?? character.profession) • \(character.race) • Level \(character.level)")
                        .foregroundStyle(.white.opacity(0.82))
                    Text(headerFacts).font(.caption).foregroundStyle(.white.opacity(0.72))
                }
                .padding(.bottom, 8)
            }
            .padding(18)
        }
        .foregroundStyle(.white)
        .frame(minHeight: 205)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var headerFacts: String {
        var facts = ["\(formattedHours(character.age)) played"]
        if let year = character.created?.prefix(4) { facts.append("Created \(year)") }
        if let deaths = character.deaths { facts.append("\(deaths.formatted()) deaths") }
        return facts.joined(separator: " • ")
    }

    @ToolbarContentBuilder private var portraitMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Set Character Portrait", systemImage: "photo")
                }
                if portraitData != nil {
                    Button("Remove Portrait", systemImage: "trash", role: .destructive) {
                        Task {
                            try? await CharacterPortraitStore.shared.remove(account: account.account?.name, character: character.name)
                            portraitData = nil
                        }
                    }
                }
            } label: { Label("Edit", systemImage: "ellipsis.circle") }
        }
    }
}

private struct EquipmentSection: View {
    let character: GW2Character
    let detail: CharacterDetailData
    @State private var selectedTabID: Int?
    @State private var inspected: InspectedItem?

    private var selectedTab: EquipmentTab? {
        detail.equipmentTabs.first(where: { $0.id == selectedTabID })
            ?? detail.equipmentTabs.first(where: \.isActive) ?? detail.equipmentTabs.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { GWSectionHeader(title: "Equipment", subtitle: "Tap an item for complete details"); Spacer() }
            if detail.equipmentTabs.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(detail.equipmentTabs) { tab in
                            Button {
                                selectedTabID = tab.id
                            } label: {
                                HStack(spacing: 5) {
                                    if tab.isActive { Image(systemName: "checkmark.circle.fill") }
                                    Text(tab.name)
                                }
                            }
                            .buttonStyle(.bordered).tint(tab.id == selectedTab?.id ? GWPalette.accent : .secondary)
                        }
                    }
                }
            }
            if let selectedTab {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 245), spacing: 12)], spacing: 12) {
                    ForEach(selectedTab.equipment) { equipment in
                        if let item = detail.items[equipment.itemID] {
                            Button { inspected = InspectedItem(item: item, equipment: equipment) } label: {
                                EquipmentRow(slot: equipment.slot, item: item, equipment: equipment, metadata: detail.items)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                EquipmentStatsView(equipment: selectedTab.equipment, items: detail.items)
            } else if detail.errorMessage == nil {
                ProgressView("Loading equipment…").frame(maxWidth: .infinity).padding(30)
            }
        }
        .sheet(item: $inspected) { ItemDetailView(inspected: $0, metadata: detail.items, skins: detail.skins) }
    }
}

private struct EquipmentRow: View {
    let slot: String
    let item: ItemMetadata
    let equipment: CharacterEquipment
    let metadata: [Int: ItemMetadata]

    var body: some View {
        GWCard {
            HStack(spacing: 12) {
                GWItemIcon(item: item)
                VStack(alignment: .leading, spacing: 3) {
                    Text(displaySlot(slot)).font(.caption.bold()).foregroundStyle(.secondary)
                    Text(item.name).font(.subheadline.bold()).lineLimit(2)
                    if let upgrade = equipment.upgrades?.compactMap({ metadata[$0]?.name }).first {
                        Text(upgrade).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(displaySlot(slot)): \(item.name), \(item.rarity)")
    }

    private func displaySlot(_ value: String) -> String {
        value.replacingOccurrences(of: "Weapon", with: "Weapon ")
            .replacingOccurrences(of: "Ring", with: "Ring ")
            .replacingOccurrences(of: "Accessory", with: "Accessory ")
    }
}

private struct EquipmentStatsView: View {
    let equipment: [CharacterEquipment]
    let items: [Int: ItemMetadata]
    private var stats: CharacterEquipmentStats {
        CharacterStatEngine.equipmentAttributes(equipment: equipment, items: items, upgrades: items)
    }

    var body: some View {
        if !stats.attributes.isEmpty {
            GWCard {
                GWSectionHeader(title: "Equipment Attributes", subtitle: "Deterministic bonuses from resolved equipment data")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 135))], alignment: .leading, spacing: 10) {
                    ForEach(CharacterStatEngine.displayOrder.filter { stats.attributes[$0] != nil }, id: \.self) { key in
                        LabeledContent(display(key), value: "+\(stats.attributes[key] ?? 0)").font(.subheadline)
                    }
                }
                .padding(.top, 12)
                Text("These values use account and equipment data and may differ from the in-game Hero Panel because temporary and conditional effects are unavailable through the API.")
                    .font(.caption2).foregroundStyle(.secondary).padding(.top, 10)
            }
        }
    }

    private func display(_ key: String) -> String {
        key.replacingOccurrences(of: "ConditionDamage", with: "Condition")
            .replacingOccurrences(of: "HealingPower", with: "Healing")
    }
}

private enum BuildInspection: Identifiable {
    case trait(TraitMetadata)
    case skill(SkillMetadata)
    var id: String {
        switch self { case let .trait(v): "trait-\(v.id)"; case let .skill(v): "skill-\(v.id)" }
    }
}

private struct BuildSection: View {
    let detail: CharacterDetailData
    @State private var selectedTabID: Int?
    @State private var inspected: BuildInspection?

    private var selectedTab: BuildTab? {
        detail.buildTabs.first(where: { $0.id == selectedTabID })
            ?? detail.buildTabs.first(where: \.isActive) ?? detail.buildTabs.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GWSectionHeader(title: "Build", subtitle: "View-only character templates")
            if detail.buildTabs.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(detail.buildTabs) { tab in
                            Button {
                                selectedTabID = tab.id
                            } label: {
                                HStack(spacing: 5) {
                                    if tab.isActive { Image(systemName: "checkmark.circle.fill") }
                                    Text(tab.name)
                                }
                            }
                            .buttonStyle(.bordered).tint(tab.id == selectedTab?.id ? GWPalette.accent : .secondary)
                        }
                    }
                }
            }
            if let build = selectedTab?.build {
                ForEach(Array(build.specializations.enumerated()), id: \.offset) { _, selected in
                    if let id = selected.id, let specialization = detail.specializations[id] {
                        specializationCard(specialization, selected: selected)
                    }
                }
                if let skills = build.skills.terrestrial ?? build.skills.pve ?? build.skills.wvw ?? build.skills.pvp {
                    skillCard(skills)
                }
            } else if detail.errorMessage == nil {
                ProgressView("Loading build…").frame(maxWidth: .infinity).padding(30)
            }
        }
        .sheet(item: $inspected) { inspection in
            MetadataDetailView(inspection: inspection)
        }
    }

    private func specializationCard(_ specialization: SpecializationMetadata, selected: BuildSpecialization) -> some View {
        GWCard {
            HStack(spacing: 10) {
                CachedAsyncImage(url: specialization.icon) { Circle().fill(.quaternary) }
                    .frame(width: 42, height: 42)
                VStack(alignment: .leading) {
                    Text(specialization.name).font(.headline)
                    if specialization.elite { Text("Elite specialization").font(.caption).foregroundStyle(GWPalette.accent) }
                }
            }
            HStack(spacing: 18) {
                ForEach(Array(selected.traits.enumerated()), id: \.offset) { tier, id in
                    if let id, let trait = detail.traits[id] {
                        Button { inspected = .trait(trait) } label: {
                            VStack {
                                GWItemLikeIcon(url: trait.icon, selected: true, size: 48)
                                Text("Tier \(tier + 1)").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Selected trait, tier \(tier + 1), \(trait.name)")
                    } else {
                        GWItemLikeIcon(url: nil, selected: false, size: 48)
                            .accessibilityLabel("No trait selected")
                    }
                }
                Spacer()
            }
            .padding(.top, 12)
        }
    }

    private func skillCard(_ skills: BuildSkills) -> some View {
        let values = ([skills.heal] + skills.utilities + [skills.elite]).compactMap { $0 }
        return GWCard {
            GWSectionHeader(title: "Skills")
            HStack(spacing: 12) {
                ForEach(values, id: \.self) { id in
                    if let skill = detail.skills[id] {
                        Button { inspected = .skill(skill) } label: {
                            GWItemLikeIcon(url: skill.icon, selected: true, size: 50)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(skill.slot ?? skill.type ?? "Skill"): \(skill.name)")
                    }
                }
            }
            .padding(.top, 12)
        }
    }
}

private struct GWItemLikeIcon: View {
    let url: URL?
    let selected: Bool
    let size: CGFloat
    var body: some View {
        CachedAsyncImage(url: url) { RoundedRectangle(cornerRadius: 8).fill(.quaternary) }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).stroke(selected ? GWPalette.accent : .secondary, lineWidth: selected ? 2 : 1) }
    }
}

private struct MetadataDetailView: View {
    let inspection: BuildInspection
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 12) {
                        GWItemLikeIcon(url: icon, selected: true, size: 88)
                        Text(name).font(.title3.bold()).multilineTextAlignment(.center)
                        Text(kind).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                if !description.isEmpty { Section("Description") { Text(description.gwPlainText) } }
            }
            .navigationTitle(kind)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private var name: String { switch inspection { case let .trait(v): v.name; case let .skill(v): v.name } }
    private var icon: URL? { switch inspection { case let .trait(v): v.icon; case let .skill(v): v.icon } }
    private var description: String { switch inspection { case let .trait(v): v.description; case let .skill(v): v.description } }
    private var kind: String { switch inspection { case .trait: "Trait"; case .skill: "Skill" } }
}

struct CharacterInventorySection: View {
    enum Layout: String, CaseIterable { case grid = "Grid"; case list = "List" }
    let detail: CharacterDetailData
    var fallbackItems: [Int: ItemMetadata] = [:]
    @State private var layout: Layout = .grid
    @State private var inspected: InspectedItem?

    private var items: [Int: ItemMetadata] {
        fallbackItems.merging(detail.items) { _, new in new }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                GWSectionHeader(title: "Inventory")
                Spacer()
                Picker("Layout", selection: $layout) {
                    ForEach(Layout.allCases, id: \.self) { Image(systemName: $0 == .grid ? "square.grid.3x3" : "list.bullet").tag($0) }
                }
                .pickerStyle(.segmented).frame(width: 110)
            }
            if let inventory = detail.inventory {
                ForEach(Array(inventory.bags.enumerated()), id: \.offset) { index, bag in
                    if let bag { bagView(bag, index: index) }
                }
            } else if detail.errorMessage == nil {
                ProgressView("Loading inventory…").frame(maxWidth: .infinity).padding(30)
            }
        }
        .sheet(item: $inspected) { ItemDetailView(inspected: $0, metadata: items) }
    }

    private func bagView(_ bag: InventoryBag, index: Int) -> some View {
        let slots = bag.inventory ?? []
        let used = slots.compactMap { $0 }.count
        let bagItem = bag.id.flatMap { items[$0] }
        return GWCard {
            HStack(spacing: 10) {
                if let bagItem { GWItemIcon(item: bagItem, size: 36) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(bagItem?.name ?? "Bag \(index + 1)").font(.headline)
                    Text("\(used) / \(bag.size ?? slots.count) slots").font(.caption).foregroundStyle(.secondary)
                }
            }
            if layout == .grid {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 52, maximum: 62), spacing: 9)], spacing: 9) {
                    ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in inventorySlot(slot) }
                }
                .padding(.top, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                        if let slot, let item = items[slot.id] {
                            Button { inspected = InspectedItem(item: item, quantity: slot.count, slot: slot) } label: {
                                HStack { GWItemIcon(item: item, size: 38); Text(item.name); Spacer(); Text(slot.count.formatted()).bold() }
                                    .padding(.vertical, 7)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func inventorySlot(_ slot: InventorySlot?) -> some View {
        if let slot, let item = items[slot.id] {
            Button { inspected = InspectedItem(item: item, quantity: slot.count, slot: slot) } label: {
                ZStack(alignment: .bottomTrailing) {
                    GWItemIcon(item: item, size: 52)
                    if slot.count > 1 { Text(slot.count.formatted()).font(.caption2.bold()).padding(3).background(.black.opacity(0.8), in: Capsule()) }
                }
            }
            .buttonStyle(.plain).accessibilityLabel("\(item.name), quantity \(slot.count)")
            .accessibilityIdentifier("inventory.item.\(item.name)")
        } else {
            RoundedRectangle(cornerRadius: 9).fill(.quaternary.opacity(0.45)).frame(width: 52, height: 52)
                .accessibilityHidden(true)
        }
    }
}

private func formattedHours(_ seconds: Int) -> String {
    let hours = Double(seconds) / 3_600
    return hours.formatted(.number.precision(.fractionLength(hours < 10 ? 1 : 0))) + " h"
}
