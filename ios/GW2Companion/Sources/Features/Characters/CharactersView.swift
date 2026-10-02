import PhotosUI
import SwiftUI

struct CharactersView: View {
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var navigation: AppNavigation
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var availableWidth: CGFloat = 0

    private var usesRoster: Bool { sizeClass == .regular && (availableWidth == 0 || availableWidth >= 740) }
    private var characterPath: Binding<[CharacterRoute]> {
        Binding(get: { usesRoster ? [] : navigation.characterPath }, set: { if !usesRoster { navigation.characterPath = $0 } })
    }

    var body: some View {
        NavigationStack(path: characterPath) {
            Group {
                if account.connectionState == .loading && account.characters.isEmpty {
                    GWLoadingRows()
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
                    GeometryReader { geometry in
                        if sizeClass == .regular && geometry.size.width >= 740 {
                            HStack(spacing: 0) {
                                characterRoster.frame(width: 300)
                                Divider()
                                if let route = navigation.characterPath.last,
                                   let character = account.characters.first(where: { $0.name == route.name }) {
                                    CharacterDetailView(character: character, initialSection: route.section).id(route)
                                } else {
                                    GWEmptyState(title: "Your characters", message: "Choose a character to view equipment, build, inventory and stats.", symbol: "person.2")
                                }
                            }
                        } else { characterGrid }
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
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

    private var characterRoster: some View {
        ScrollView {
            LazyVStack(spacing: GWSpacing.medium) {
                ForEach(account.characters) { character in
                    Button { navigation.characterPath = [CharacterRoute(name: character.name, section: .equipment)] } label: {
                        CharacterCard(character: character, profession: account.professions[character.profession],
                                      specialization: account.eliteSpecializationName(for: character),
                                      isCurrent: account.currentCharacter?.name == character.name)
                    }.buttonStyle(.plain)
                        .accessibilityIdentifier("character.roster.\(character.name)")
                        .task { if !GWPresentation.isDesignReview { await account.loadCharacterDetails(character) } }
                }
            }.padding(GWSpacing.medium)
        }.background(GWPalette.background).refreshable { await account.refresh() }
    }

    private var characterGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 310, maximum: 520), spacing: 16)], spacing: 16) {
            ForEach(account.characters) { character in
                    NavigationLink(value: CharacterRoute(name: character.name, section: .equipment)) {
                        CharacterCard(
                            character: character,
                            profession: account.professions[character.profession],
                            specialization: account.eliteSpecializationName(for: character),
                            isCurrent: account.currentCharacter?.name == character.name)
                    }
                    .buttonStyle(.plain)
                    .task { if !GWPresentation.isDesignReview { await account.loadCharacterDetails(character) } }
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
                .frame(width: 44, height: 44)
                .padding(8)
                .background(GWPalette.profession(character.profession).opacity(0.16), in: RoundedRectangle(cornerRadius: GWSpacing.large))

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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedEquipmentTabID: Int?
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
                sectionPicker

                if let error = detail.buildError, section == .build {
                    GWErrorBanner(message: error, stale: !detail.buildTabs.isEmpty) {
                        Task { await account.loadCharacterDetails(character, force: true) }
                    }
                }
                if let error = detail.equipmentError, section == .equipment {
                    GWErrorBanner(message: error, stale: !detail.equipmentTabs.isEmpty) {
                        Task { await account.loadCharacterDetails(character, force: true) }
                    }
                }
                if let error = detail.inventoryError, section == .inventory {
                    GWErrorBanner(message: error, stale: detail.inventory != nil) {
                        Task { await account.loadCharacterDetails(character, force: true) }
                    }
                }
                if detail.source == .cached, let updated = detail.updatedAt {
                    GWFreshnessLabel(updated: updated, saved: true)
                }

                Group {
                    switch section {
                    case .equipment:
                        EquipmentSection(character: character, detail: detail, selectedTabID: $selectedEquipmentTabID)
                    case .build:
                        BuildSection(detail: detail)
                    case .inventory:
                        CharacterInventorySection(detail: detail, fallbackItems: account.itemMetadata)
                    case .stats:
                        if let tab = detail.equipmentTabs.first(where: { $0.id == selectedEquipmentTabID }) ?? detail.equipmentTabs.first(where: \.isActive) ?? detail.equipmentTabs.first {
                            EquipmentStatsView(character: character, equipment: tab.equipment, items: detail.items,
                                build: detail.buildTabs.first(where: \.isActive)?.build ?? detail.buildTabs.first?.build,
                                traits: detail.traits, specializations: detail.specializations, equipmentTabName: tab.name,
                                source: detail.source, updatedAt: detail.updatedAt, itemStats: detail.itemStats ?? [:], equipmentTabID: tab.tab)
                        } else { GWLoadingRows() }
                    }
                }
            }
            .frame(maxWidth: 920)
            .padding()
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("character.profile")
        .accessibilityValue(section.rawValue)
        .background(GWPalette.background)
        .navigationTitle(character.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await account.loadCharacterDetails(character, force: true) }
        .task {
            if !GWPresentation.isDesignReview { await account.loadCharacterDetails(character) }
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

    private var sectionPicker: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                Picker("Section", selection: $section) {
                    ForEach(CharacterSection.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }.pickerStyle(.menu).frame(minHeight: 44)
                    .accessibilityIdentifier("character.sections")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: GWSpacing.xSmall) {
                        ForEach(CharacterSection.allCases, id: \.self) { value in
                            Button { section = value } label: {
                                Text(value.rawValue.capitalized)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .foregroundStyle(section == value ? Color.primary : Color.secondary)
                            }
                            .buttonStyle(GWSelectionButtonStyle(selected: section == value))
                            .accessibilityAddTraits(section == value ? .isSelected : [])
                            .accessibilityIdentifier("character.section.\(value.rawValue)")
                        }
                    }.padding(GWSpacing.xSmall)
                }
                    .background(GWPalette.card, in: RoundedRectangle(cornerRadius: GWSpacing.large))
            }
        }
    }

    private var characterHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: GWSpacing.section) { portrait; characterIdentity }
            VStack(alignment: .leading, spacing: GWSpacing.large) { portrait; characterIdentity }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, GWSpacing.medium)
        .accessibilityElement(children: .combine)
    }

    private var portrait: some View {
        Group {
            if let portraitData, let image = UIImage(data: portraitData) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                CachedAsyncImage(url: account.professions[character.profession]?.iconBig) {
                    Image(systemName: "person.crop.circle.fill").resizable().scaledToFit().padding(GWSpacing.large)
                }
            }
        }.frame(width: 88, height: 104)
            .background(GWPalette.profession(character.profession).opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: GWSpacing.large))
            .accessibilityHidden(true)
    }

    private var characterIdentity: some View {
        VStack(alignment: .leading, spacing: GWSpacing.small) {
            Text(character.name).font(GWTypography.hero)
            Text("\(account.eliteSpecializationName(for: character) ?? character.profession) · Level \(character.level)")
                .font(.subheadline).foregroundStyle(.secondary)
            if account.currentCharacter?.name == character.name {
                GWBadge(text: "CURRENTLY PLAYING", color: GWPalette.success, symbol: "circle.fill")
            }
            Text("\(character.race) · \(formattedHours(character.age)) played").font(.caption).foregroundStyle(.secondary)
        }
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
    @Binding var selectedTabID: Int?
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
                            .buttonStyle(GWSelectionButtonStyle(selected: tab.id == selectedTab?.id))
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
            } else if detail.errorMessage == nil {
                GWLoadingRows()
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
                    Text(GWPresentation.itemName(item)).font(.subheadline.bold()).lineLimit(2)
                    Text(item.rarity).font(.caption).foregroundStyle(GWPalette.rarity(item.rarity))
                    if let upgrade = equipment.upgrades?.compactMap({ metadata[$0]?.name }).first {
                        Text(upgrade).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(displaySlot(slot)): \(GWPresentation.itemName(item)), \(item.rarity)")
    }

    private func displaySlot(_ value: String) -> String {
        value.replacingOccurrences(of: "Weapon", with: "Weapon ")
            .replacingOccurrences(of: "Ring", with: "Ring ")
            .replacingOccurrences(of: "Accessory", with: "Accessory ")
    }
}

private struct EquipmentStatsView: View {
    let character: GW2Character
    let equipment: [CharacterEquipment]
    let items: [Int: ItemMetadata]
    let build: CharacterBuild?
    let traits: [Int: TraitMetadata]
    let specializations: [Int: SpecializationMetadata]
    let equipmentTabName: String
    let source: AccountDataSource?
    let updatedAt: Date?
    var itemStats: [Int: ItemStatMetadata] = [:]
    var equipmentTabID: Int? = nil
    @State private var inspectedStat: String?
    @AppStorage("developer.mode.enabled") private var developerMode = false

    private var stats: CharacterStaticStats {
        CharacterStatEngine.calculate(
            character: character, equipment: equipment, items: items,
            build: build, traits: traits, specializations: specializations, itemStats: itemStats)
    }

    var body: some View {
        GWCard {
            GWSectionHeader(
                title: "Estimated static stats",
                subtitle: source == .cached
                    ? "Saved data\(updatedAt.map { " • Updated \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "")"
                    : "Calculated from your character and equipment data")
            VStack(spacing: GWSpacing.medium) {
                ForEach(CharacterStatEngine.displayOrder, id: \.self) { key in
                    let total = stats.total(for: key)
                    Button { inspectedStat = key } label: {
                        LabeledContent(CharacterStatEngine.displayName(key), value: total.formatted())
                            .font(.subheadline)
                    }
                    .buttonStyle(.plain).frame(minHeight: 44)
                }
            }
            .monospacedDigit()
            .padding(.top, 12)
            if stats.derived.availableForLevel {
                Divider().padding(.vertical, 8)
                GWSectionHeader(title: "Combat stats")
                if let value = stats.derived.criticalChancePercent {
                    LabeledContent("Critical Chance", value: percent(value))
                }
                if let value = stats.derived.criticalDamagePercent {
                    LabeledContent("Critical Damage", value: percent(value))
                }
                if let value = stats.derived.boonDurationPercent {
                    LabeledContent("Boon Duration", value: percent(value))
                }
                if let value = stats.derived.conditionDurationPercent {
                    LabeledContent("Condition Duration", value: percent(value))
                }
                if let armor = stats.derived.armor {
                    LabeledContent("Armor", value: armor.formatted())
                }
                if let health = stats.derived.health {
                    LabeledContent("Health", value: health.formatted())
                }
            } else {
                Text("Derived stats currently available for level 80 characters.")
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
            }
            Divider().padding(.vertical, 8)
            let coverage = StatCoverageReport(stats: stats, build: build, traits: traits, specializations: specializations)
            let missingEquipment = stats.equipmentSources.filter { $0.included && $0.equipment.slot != "Relic" && $0.baseAttributes.isEmpty }.count
            if missingEquipment > 0 {
                Label("\(missingEquipment) equipment sources unavailable", systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup("View calculation details") {
                Text("A level-80 PvE estimate from equipment and selected static traits. Combat effects and downscaling can change your in-game values.")
                    .font(.caption).foregroundStyle(.secondary)
                Text(coverage.summary).font(.caption)
                ForEach(stats.excludedSources, id: \.self) { reason in
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                }
            }.accessibilityIdentifier("stats.calculationDetails")
            if GWPresentation.developerToolsAvailable && developerMode {
                NavigationLink("Character Stat Audit") {
                    CharacterStatAuditView(character: character, equipment: equipment, items: items,
                        build: build, traits: traits, specializations: specializations,
                        equipmentTabName: equipmentTabName, equipmentTabID: equipmentTabID)
                }.buttonStyle(.bordered)
            }
        }
        .sheet(item: Binding(
            get: { inspectedStat.map { StatInspection(id: $0) } },
            set: { inspectedStat = $0?.id }
        )) { inspection in
            StatSourceSheet(name: inspection.id, breakdown: stats.attributes[inspection.id] ?? CharacterStatBreakdown())
        }
    }

    private func percent(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1))))%"
    }
}

private struct StatInspection: Identifiable {
    let id: String
}

private struct StatSourceSheet: View {
    let name: String
    let breakdown: CharacterStatBreakdown
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent(CharacterStatEngine.displayName(name), value: breakdown.total.formatted())
                        .font(.headline)
                }
                ForEach(breakdown.components, id: \.0) { component in
                    if component.1 != 0 {
                        LabeledContent(component.0, value: component.1 > 0 ? "+\(component.1.formatted())" : component.1.formatted())
                    }
                }
            }
            .navigationTitle(CharacterStatEngine.displayName(name))
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}

struct CharacterStatAuditView: View {
    @EnvironmentObject private var account: AccountStore
    @AppStorage(EarlyBeta.developerModeKey) private var developerMode = false
    let character: GW2Character
    let equipment: [CharacterEquipment]
    let items: [Int: ItemMetadata]
    let build: CharacterBuild?
    let traits: [Int: TraitMetadata]
    let specializations: [Int: SpecializationMetadata]
    let equipmentTabName: String
    var equipmentTabID: Int? = nil
    @State private var observed: [String: String] = [:]
    @State private var weaponSet = "A"

    private var currentDetail: CharacterDetailData? { account.characterDetails[character.name] }
    private var currentTab: EquipmentTab? { currentDetail?.equipmentTabs.first { tab in
        if let equipmentTabID { return tab.tab == equipmentTabID }
        return tab.name == equipmentTabName && tab.equipment.map(\.id) == equipment.map(\.id)
    } }
    private var currentBuild: CharacterBuild? { (currentDetail?.buildTabs.first(where: \.isActive) ?? currentDetail?.buildTabs.first)?.build ?? build }
    private var currentTraits: [Int: TraitMetadata] { currentDetail?.traits ?? traits }
    private var currentSpecializations: [Int: SpecializationMetadata] { currentDetail?.specializations ?? specializations }
    private var coverage: StatCoverageReport {
        StatCoverageReport(stats: stats, build: currentBuild, traits: currentTraits, specializations: currentSpecializations)
    }

    private var stats: CharacterStaticStats {
        CharacterStatEngine.calculate(
            character: character, equipment: currentTab?.equipment ?? equipment, items: currentDetail?.items ?? items,
            build: currentBuild, traits: currentTraits, specializations: currentSpecializations,
            itemStats: currentDetail?.itemStats ?? [:], weaponSet: weaponSet)
    }

    private var observationKey: String {
        StatAuditObservationStore.key(character: character.name, equipmentTab: equipmentTabName)
            + (weaponSet == "A" ? "" : ".weaponB")
    }

    var body: some View {
        List {
            Section("Context") {
                LabeledContent("Character", value: character.name)
                LabeledContent("Equipment tab", value: equipmentTabName)
                LabeledContent("Game mode", value: "PvE level 80")
                Picker("Terrestrial weapon set", selection: $weaponSet) {
                    Text("A").tag("A")
                    Text("B").tag("B")
                }
                Text("The account API does not report the live weapon swap. Choose the set shown in the Hero Panel. Aquatic equipment is excluded.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Compare while the character is not dynamically downscaled. Observations stay on this device and are QA notes, not account data.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Stat coverage") {
                Text(coverage.isComplete ? "Static Stats complete" : "Static Stats incomplete")
                    .foregroundStyle(coverage.isComplete ? .green : .orange)
                Text(coverage.summary)
                LabeledContent("Local rules", value: coverage.localRules.summary)
                LabeledContent("Account data", value: coverage.accountData.summary)
                LabeledContent("Public metadata", value: coverage.publicMetadata.summary)
                LabeledContent("Network required", value: "\(coverage.networkRequired)")
                ForEach(coverage.diagnostics, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                Text("Account freshness and static metadata completeness are independent.").font(.caption)
                if GWPresentation.developerToolsAvailable && developerMode {
                    Button("Resolve Missing Stat Sources") {
                        guard let tab = currentTab else { return }
                        Task { await account.resolveMissingStatSources(character: character, equipmentTab: tab.tab, weaponSet: weaponSet) }
                    }
                    .disabled(currentTab == nil || account.resolvingStatCharacters.contains(character.name))
                    .accessibilityIdentifier("audit.resolveMissingSources")
                }
                if account.resolvingStatCharacters.contains(character.name) { ProgressView("Resolving targeted sources…") }
                ForEach(account.statSourceProgress[character.name] ?? []) { progress in
                    LabeledContent(progress.label, value: progress.status).font(.caption)
                }
                if let message = account.statResolutionMessages[character.name] { Text(message).font(.caption) }
                LabeledContent("Trait modifiers modeled", value: "\(stats.modeledTraitCount)")
                LabeledContent("Trait modifiers excluded/conditional", value: "\(stats.excludedTraitCount)")
                LabeledContent("Defense sum", value: "\(stats.defense.total)")
                LabeledContent("Rune catalog", value: StaticRuneAttributeCatalog.version)
                LabeledContent("Trait catalog", value: StaticTraitModifierCatalog.version)
            }
            Section("Still missing deterministic sources") {
                if coverage.missing.isEmpty { Text("None") }
                ForEach(coverage.missing, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            }
            Section("Active build IDs") {
                ForEach(Array((currentBuild?.specializations ?? []).enumerated()), id: \.offset) { _, selected in
                    Text("Specialization \(selected.id.map(String.init) ?? "none") • selected major IDs \(selected.traits.compactMap { $0 }.map(String.init).joined(separator: ", "))")
                        .font(.caption)
                }
                Text("Great Fortitude (1449): \(currentBuild?.specializations.contains(where: { $0.id == 4 && $0.traits.contains(1449) }) == true ? "selected" : "not selected / build unavailable")")
                if GWPresentation.developerToolsAvailable && developerMode, let trait = currentTraits[1449] {
                    ForEach(Array(trait.facts.enumerated()), id: \.offset) { _, fact in
                        Text("1449 fact: \(fact.type) • \(fact.source ?? "none") → \(fact.target ?? "none") • \(fact.percent.map { String($0) } ?? "no percent")%")
                            .font(.caption)
                    }
                }
            }
            if GWPresentation.developerToolsAvailable && developerMode, let diagnostics = account.statEquipmentDiagnostics[character.name], !diagnostics.isEmpty {
                Section("Raw equipment DTO shape (no credentials)") {
                    ForEach(Array(diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                        Text(diagnostic.summary).font(.caption)
                    }
                }
            }
            Section("Equipment stat sources") {
                ForEach(stats.equipmentSources) { entry in
                    DisclosureGroup("\(entry.equipment.slot) — \(entry.itemName)") {
                        LabeledContent("Item ID", value: "\(entry.equipment.itemID)")
                        LabeledContent("Record location", value: entry.equipment.location ?? "Not supplied")
                        LabeledContent("stats.id", value: entry.equipment.stats?.id.map(String.init) ?? "Not supplied")
                        if let reason = entry.exclusionReason { Text("IGNORED • \(reason)").font(.caption) }
                        forSourceRows(entry)
                    }
                }
            }
            Section("Active armor/shield defense") {
                ForEach(stats.equipmentSources.filter { $0.included && $0.sources.contains { $0.label == "Defense" && $0.state != .ignored } }) { entry in
                    LabeledContent("\(entry.equipment.slot) • \(entry.itemName) • \(entry.equipment.itemID)",
                        value: entry.sources.first(where: { $0.label == "Defense" })?.state == .used ? String(entry.defense) : "Unresolved")
                        .font(.caption)
                }
                LabeledContent("Total Defense", value: String(stats.defense.total))
            }
            Section("Attributes") {
                ForEach(CharacterStatEngine.displayOrder, id: \.self) { key in
                    auditRow(
                        id: key, title: CharacterStatEngine.displayName(key),
                        calculated: Double(stats.total(for: key)), suffix: nil,
                        components: stats.attributes[key]?.components ?? [])
                }
            }
            Section("Derived") {
                if let armor = stats.derived.armor {
                    auditRow(
                        id: "Armor", title: "Armor", calculated: Double(armor), suffix: nil,
                        components: [("Toughness", stats.total(for: "Toughness"))]
                            + stats.equipmentSources.filter { $0.included && $0.sources.contains { $0.label == "Defense" && $0.state != .ignored } }
                                .map { ("\($0.equipment.slot) defense • item \($0.equipment.itemID)", $0.defense) }
                            + [("Total Defense", stats.defense.total)])
                }
                if let health = stats.derived.health {
                    auditRow(
                        id: "Health", title: "Health", calculated: Double(health), suffix: nil,
                        components: [
                            ("Profession base health", CharacterStatEngine.professionBaseHealth(character.profession)),
                            ("Vitality × 10", stats.total(for: "Vitality") * 10)
                        ])
                }
                derivedPercentRow("CriticalChance", "Critical Chance", stats.derived.criticalChancePercent)
                if let precisionChance = stats.derived.criticalChanceFromPrecision {
                    LabeledContent("Base critical chance", value: "5%")
                    LabeledContent("Precision contribution", value: formatted(precisionChance - 5, suffix: "%"))
                    LabeledContent("Pinnacle of Strength (1453)", value: formatted(stats.derived.criticalChanceBuildModifier, suffix: "%"))
                    LabeledContent("Other deterministic critical chance", value: "0%")
                    Text("Conditional critical chance effects excluded").font(.caption)
                    if let value = observedValue("CriticalChance") {
                        LabeledContent("Unexplained observed remainder", value: formatted(
                            value - (stats.derived.criticalChancePercent ?? 0), suffix: "%"))
                    }
                }
                derivedPercentRow("CriticalDamage", "Critical Damage", stats.derived.criticalDamagePercent)
                derivedPercentRow("BoonDuration", "Boon Duration", stats.derived.boonDurationPercent)
                derivedPercentRow("ConditionDuration", "Condition Duration", stats.derived.conditionDurationPercent)
            }
            Section("Intentionally excluded dynamic effects") {
                ForEach(coverage.dynamic, id: \.self) { reason in
                    Label(reason, systemImage: "minus.circle").font(.caption)
                }
            }
        }
        .navigationTitle("Character Stat Audit")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: observationKey) {
            observed = StatAuditObservationStore.load(key: observationKey)
                .mapValues { StatAuditNumber.editable($0) }
        }
        .accessibilityIdentifier("qa.characterStatAudit")
    }

    @ViewBuilder
    private func derivedPercentRow(_ id: String, _ title: String, _ value: Double?) -> some View {
        if let value {
            auditRow(id: id, title: title, calculated: value, suffix: "%", components: [])
        }
    }

    private func auditRow(
        id: String, title: String, calculated: Double, suffix: String?, components: [(String, Int)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.headline)
            LabeledContent("Calculated", value: formatted(calculated, suffix: suffix))
            HStack {
                Text("Observed")
                Spacer()
                TextField("Enter Hero Panel", text: observationBinding(id))
                    .accessibilityIdentifier("audit.observed.\(id)")
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 150)
            }
            if let value = observedValue(id) {
                let difference = StatAuditNumber.difference(calculated: calculated, observed: value)
                LabeledContent("Difference", value: formatted(difference, suffix: suffix))
                    .foregroundStyle(abs(difference) < 0.01 ? .green : .orange)
                    .accessibilityIdentifier("audit.difference.\(id)")
            }
            ForEach(components.filter { $0.1 != 0 }, id: \.0) { component in
                LabeledContent(component.0, value: component.1.formatted())
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .id(id)
        .padding(.vertical, 4)
    }

    private func observedValue(_ id: String) -> Double? {
        StatAuditNumber.parse(observed[id] ?? "", fractional: isPercent(id))
    }

    private func isPercent(_ id: String) -> Bool {
        ["CriticalChance", "CriticalDamage", "BoonDuration", "ConditionDuration"].contains(id)
    }

    private func forSourceRows(_ entry: EquipmentStatAuditEntry) -> some View {
        ForEach(entry.sources) { source in
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent(source.label, value: source.state.rawValue).font(.caption.bold())
                if let value = source.value { Text("\(value)").font(.caption).monospacedDigit() }
                ForEach(source.attributes.keys.sorted(), id: \.self) { key in
                    LabeledContent(key, value: "+\(source.attributes[key] ?? 0)").font(.caption)
                }
                Text(source.explanation).font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.vertical, 3)
        }
    }

    private func observationBinding(_ id: String) -> Binding<String> {
        Binding(
            get: { observed[id] ?? "" },
            set: { value in
                observed[id] = value
                var numeric: [String: Double] = [:]
                for key in observed.keys { numeric[key] = observedValue(key) }
                StatAuditObservationStore.save(numeric, key: observationKey)
            })
    }

    private func formatted(_ value: Double, suffix: String?) -> String {
        let number = value.formatted(.number.precision(.fractionLength(suffix == nil ? 0 : 2)))
        return number + (suffix ?? "")
    }
}

struct QACharacterStatAuditPickerView: View {
    @EnvironmentObject private var account: AccountStore
    @State private var characterName: String?
    @State private var equipmentTabID: Int?

    private var character: GW2Character? {
        account.characters.first { $0.name == characterName } ?? account.characters.first
    }

    private var detail: CharacterDetailData {
        character.flatMap { account.characterDetails[$0.name] } ?? CharacterDetailData()
    }

    private var equipmentTab: EquipmentTab? {
        detail.equipmentTabs.first { $0.id == equipmentTabID }
            ?? detail.equipmentTabs.first(where: \.isActive) ?? detail.equipmentTabs.first
    }

    var body: some View {
        List {
            Section("Selection") {
                Picker("Character", selection: $characterName) {
                    ForEach(account.characters) { character in
                        Text(character.name).tag(character.name as String?)
                    }
                }
                if detail.equipmentTabs.count > 1 {
                    Picker("Equipment tab", selection: $equipmentTabID) {
                        ForEach(detail.equipmentTabs) { tab in Text(tab.name).tag(tab.id as Int?) }
                    }
                }
            }
            Section {
                if let character, let equipmentTab {
                    NavigationLink("Open Stat Audit") {
                        CharacterStatAuditView(
                            character: character, equipment: equipmentTab.equipment, items: detail.items,
                            build: detail.buildTabs.first(where: \.isActive)?.build ?? detail.buildTabs.first?.build,
                            traits: detail.traits, specializations: detail.specializations,
                            equipmentTabName: equipmentTab.name, equipmentTabID: equipmentTab.tab)
                    }
                } else {
                    ProgressView("Load a character and equipment tab…")
                }
            }
        }
        .navigationTitle("Character Stat Audit")
        .task(id: character?.name) {
            guard let character else { return }
            characterName = character.name
            await account.loadCharacterDetails(character)
            equipmentTabID = account.characterDetails[character.name]?.equipmentTabs.first(where: \.isActive)?.id
        }
    }
}

enum StatAuditObservationStore {
    private static let prefix = "qa.statAudit.v1."

    static func key(character: String, equipmentTab: String) -> String {
        let raw = character + "." + equipmentTab
        let safe = raw.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "_" }
        return prefix + String(safe)
    }

    static func load(key: String, defaults: UserDefaults = .standard) -> [String: Double] {
        guard let data = defaults.data(forKey: key),
              let values = try? JSONDecoder().decode([String: Double].self, from: data) else { return [:] }
        return values
    }

    static func save(_ values: [String: Double], key: String, defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(values), forKey: key)
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
            GWSectionHeader(title: "Build", subtitle: "Selected specializations and skills")
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
                            .buttonStyle(GWSelectionButtonStyle(selected: tab.id == selectedTab?.id))
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
                GWLoadingRows(count: 3)
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
                                Text(trait.name).font(.caption).foregroundStyle(.primary).lineLimit(2)
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
            ScrollView(.horizontal, showsIndicators: false) {
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
    @AppStorage(InventoryPricePreference.storageKey) private var preferenceRaw = InventoryPricePreference.sellNow.rawValue

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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76, maximum: 86), spacing: 9)], spacing: 9) {
                    ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in inventorySlot(slot) }
                }
                .padding(.top, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                        if let slot, let item = items[slot.id] {
                            Button { inspected = InspectedItem(item: item, quantity: slot.count, slot: slot) } label: {
                                HStack {
                                    GWItemIcon(item: item, size: 38)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(GWPresentation.itemName(item))
                                        if pricePreference != .off {
                                            OwnedItemPriceLine(item: item, quantity: slot.count, compact: false)
                                        }
                                    }
                                    Spacer()
                                    Text(slot.count.formatted()).bold()
                                }
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
            VStack(spacing: 3) {
                Button { inspected = InspectedItem(item: item, quantity: slot.count, slot: slot) } label: {
                    ZStack(alignment: .bottomTrailing) {
                        GWItemIcon(item: item, size: 52)
                        if slot.count > 1 { Text(slot.count.formatted()).font(.caption2.bold()).padding(3).background(.black.opacity(0.8), in: Capsule()) }
                    }
                }
                .buttonStyle(.plain)
                if pricePreference != .off {
                    OwnedItemPriceLine(item: item, quantity: slot.count, compact: true)
                        .frame(maxWidth: 76)
                }
            }
            .accessibilityLabel("\(GWPresentation.itemName(item)), quantity \(slot.count)")
            .accessibilityIdentifier("inventory.item.\(item.name)")
        } else {
            RoundedRectangle(cornerRadius: 9).fill(.quaternary.opacity(0.45)).frame(width: 52, height: 52)
                .accessibilityHidden(true)
        }
    }

    private var pricePreference: InventoryPricePreference {
        InventoryPricePreference(rawValue: preferenceRaw) ?? .sellNow
    }
}

private func formattedHours(_ seconds: Int) -> String {
    let hours = Double(seconds) / 3_600
    return hours.formatted(.number.precision(.fractionLength(hours < 10 ? 1 : 0))) + " h"
}
