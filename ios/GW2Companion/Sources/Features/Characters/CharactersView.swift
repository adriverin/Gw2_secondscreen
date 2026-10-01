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
                    GWErrorBanner(
                        message: "Saved data. Updated \(updated.formatted(date: .abbreviated, time: .shortened)). Not current.",
                        stale: true)
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
                EquipmentStatsView(
                    character: character, equipment: selectedTab.equipment, items: detail.items,
                    build: detail.buildTabs.first(where: \.isActive)?.build ?? detail.buildTabs.first?.build,
                    traits: detail.traits, specializations: detail.specializations,
                    equipmentTabName: selectedTab.name,
                    source: detail.source, updatedAt: detail.updatedAt)
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
    let character: GW2Character
    let equipment: [CharacterEquipment]
    let items: [Int: ItemMetadata]
    let build: CharacterBuild?
    let traits: [Int: TraitMetadata]
    let specializations: [Int: SpecializationMetadata]
    let equipmentTabName: String
    let source: AccountDataSource?
    let updatedAt: Date?
    @State private var inspectedStat: String?

    private var stats: CharacterStaticStats {
        CharacterStatEngine.calculate(
            character: character, equipment: equipment, items: items,
            build: build, traits: traits, specializations: specializations)
    }

    var body: some View {
        GWCard {
            GWSectionHeader(
                title: "Level-80 PvE Static Estimate",
                subtitle: source == .cached
                    ? "Saved data\(updatedAt.map { " • Updated \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "")"
                    : "Calculated from your character and equipment data")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145))], alignment: .leading, spacing: 10) {
                ForEach(CharacterStatEngine.displayOrder, id: \.self) { key in
                    let total = stats.total(for: key)
                    Button { inspectedStat = key } label: {
                        LabeledContent(CharacterStatEngine.displayName(key), value: total.formatted())
                            .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 12)
            if stats.derived.availableForLevel {
                Divider().padding(.vertical, 8)
                GWSectionHeader(title: "Derived", subtitle: "Level 80 formulas")
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
            HStack {
                Text("STAT COVERAGE").font(.caption2.bold()).foregroundStyle(.secondary)
                Spacer()
                GWBadge(
                    text: stats.coverage.rawValue.uppercased(),
                    color: stats.coverage == .high ? .green : .orange,
                    symbol: stats.coverage == .high ? "checkmark.circle" : "exclamationmark.circle")
            }
            Text("\(stats.modeledTraitCount) trait modifiers modeled • \(stats.excludedTraitCount) excluded/conditional")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(stats.excludedSources, id: \.self) { reason in
                Text("• \(reason)").font(.caption2).foregroundStyle(.secondary)
            }
            NavigationLink("Character Stat Audit") {
                CharacterStatAuditView(
                    character: character, equipment: equipment, items: items,
                    build: build, traits: traits, specializations: specializations,
                    equipmentTabName: equipmentTabName)
            }
            .buttonStyle(.bordered)
            .padding(.top, 6)
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
    let character: GW2Character
    let equipment: [CharacterEquipment]
    let items: [Int: ItemMetadata]
    let build: CharacterBuild?
    let traits: [Int: TraitMetadata]
    let specializations: [Int: SpecializationMetadata]
    let equipmentTabName: String
    @State private var observed: [String: String] = [:]
    @State private var weaponSet = "A"

    private var stats: CharacterStaticStats {
        CharacterStatEngine.calculate(
            character: character, equipment: equipment, items: items,
            build: build, traits: traits, specializations: specializations, weaponSet: weaponSet)
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
                LabeledContent("Coverage", value: stats.coverage.rawValue)
                LabeledContent("Trait modifiers modeled", value: "\(stats.modeledTraitCount)")
                LabeledContent("Trait modifiers excluded/conditional", value: "\(stats.excludedTraitCount)")
                LabeledContent("Defense sum", value: "\(stats.defense.total)")
                LabeledContent("Rune catalog", value: StaticRuneAttributeCatalog.version)
                LabeledContent("Trait catalog", value: StaticTraitModifierCatalog.version)
                ForEach(stats.excludedSources, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
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
                        components: [
                            ("Toughness", stats.total(for: "Toughness")),
                            ("Armor defense", stats.defense.armorPieces),
                            ("Shield defense", stats.defense.shield),
                            ("Other defense", stats.defense.other)
                        ])
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
                    LabeledContent("Base from Precision", value: formatted(precisionChance, suffix: "%"))
                    LabeledContent("Deterministic build modifiers", value: formatted(stats.derived.criticalChanceBuildModifier, suffix: "%"))
                    if let value = observedValue("CriticalChance") {
                        LabeledContent("Unexplained observed remainder", value: formatted(
                            value - (stats.derived.criticalChancePercent ?? 0), suffix: "%"))
                    }
                }
                derivedPercentRow("CriticalDamage", "Critical Damage", stats.derived.criticalDamagePercent)
                derivedPercentRow("BoonDuration", "Boon Duration", stats.derived.boonDurationPercent)
                derivedPercentRow("ConditionDuration", "Condition Duration", stats.derived.conditionDurationPercent)
            }
            Section("Not modeled in static total") {
                ForEach(stats.excludedSources, id: \.self) { reason in
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
                            equipmentTabName: equipmentTab.name)
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
                                        Text(item.name)
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
            .accessibilityLabel("\(item.name), quantity \(slot.count)")
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
