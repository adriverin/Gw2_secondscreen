import SwiftUI

struct AddGoalView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                NavigationLink { AchievementBrowserView() } label: {
                    Label("Achievement", systemImage: "trophy.fill")
                }
                NavigationLink { CraftableItemBrowserView() } label: {
                    Label("Craft Item", systemImage: "hammer.fill")
                }
                NavigationLink { CustomGoalEditorView() } label: {
                    Label("Custom Goal", systemImage: "checklist")
                }
            }
            .navigationTitle("Add Goal")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}

private struct AchievementBrowserView: View {
    @EnvironmentObject private var store: GoalStore
    @EnvironmentObject private var account: AccountStore
    @State private var query = ""

    var body: some View {
        Group {
            if !query.isEmpty {
                List(store.searchAchievements(query)) { achievement in
                    NavigationLink { AchievementPreviewView(achievementID: achievement.id) } label: {
                        achievementRow(achievement)
                    }
                }
            } else {
                List {
                    if case let .loading(message) = store.achievementState {
                        Section { ProgressView(message) }
                    }
                    let tracked = trackedAchievements
                    if !tracked.isEmpty {
                        Section("Favorites / Goals") {
                            ForEach(tracked) { achievement in
                                NavigationLink { AchievementPreviewView(achievementID: achievement.id) } label: {
                                    achievementRow(achievement)
                                }
                            }
                        }
                    }
                    ForEach(store.achievementGroups) { group in
                        let categories = group.categories.compactMap { id in
                            store.achievementCategories.first { $0.id == id }
                        }.sorted { $0.order < $1.order }
                        if !categories.isEmpty {
                            Section(group.name) {
                                ForEach(categories) { category in
                                    NavigationLink { AchievementCategoryView(category: category) } label: {
                                        Label(category.name, systemImage: "folder")
                                    }
                                }
                            }
                        }
                    }
                    if case let .unavailable(message) = store.achievementState {
                        Section { Label(message, systemImage: "exclamationmark.triangle") }
                    }
                }
            }
        }
        .navigationTitle("Achievements")
        .searchable(text: $query, prompt: "Name, description, requirement, category")
        .task { await store.prepareAchievements() }
        .task(id: query.isEmpty) {
            guard !query.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, !query.isEmpty else { return }
            await store.prepareAchievementSearchIndex()
        }
    }

    private var trackedAchievements: [AchievementDefinition] {
        store.goals.compactMap { goal in
            guard case let .achievement(id) = goal.type else { return nil }
            return store.achievements[id]
        }
    }

    private func achievementRow(_ achievement: AchievementDefinition) -> some View {
        HStack {
            CachedAsyncImage(url: achievement.icon) {
                Image(systemName: "trophy.fill").foregroundStyle(GWPalette.accent)
            }.frame(width: 38, height: 38)
            VStack(alignment: .leading) {
                Text(achievement.name)
                if let progress = account.achievementProgress[achievement.id] {
                    Text(progress.done ? "Completed" : "In progress")
                        .font(.caption).foregroundStyle(progress.done ? .green : .secondary)
                }
            }
        }
    }
}

private struct AchievementCategoryView: View {
    let category: AchievementCategory
    @EnvironmentObject private var store: GoalStore

    var body: some View {
        List {
            if !category.description.isEmpty {
                Section { Text(category.description.gwPlainText).foregroundStyle(.secondary) }
            }
            ForEach(category.achievements.compactMap { store.achievements[$0] }) { achievement in
                NavigationLink { AchievementPreviewView(achievementID: achievement.id) } label: {
                    HStack {
                        CachedAsyncImage(url: achievement.icon) {
                            Image(systemName: "trophy.fill").foregroundStyle(GWPalette.accent)
                        }.frame(width: 34, height: 34)
                        VStack(alignment: .leading) {
                            Text(achievement.name)
                            Text(achievement.requirement.gwPlainText).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
            }
            if case let .loading(message) = store.achievementState { ProgressView(message) }
        }
        .navigationTitle(category.name)
        .task(id: category.id) { await store.loadAchievements(in: category) }
    }
}

private struct AchievementPreviewView: View {
    let achievementID: Int
    @EnvironmentObject private var store: GoalStore
    @EnvironmentObject private var account: AccountStore

    var body: some View {
        ScrollView {
            if let definition = store.achievements[achievementID] {
                let tracking = AchievementTrackingEngine.merge(
                    definition: definition, progress: account.achievementProgress[achievementID],
                    progressPermissionAvailable: account.permissions.contains(.progression),
                    items: store.achievementItems, skins: store.achievementSkins,
                    minis: store.achievementMinis, unlockedSkinIDs: account.unlockedSkinIDs,
                    unlockedMiniIDs: account.unlockedMiniIDs,
                    unlockPermissionAvailable: account.permissions.contains(.unlocks))
                VStack(alignment: .leading, spacing: 16) {
                    GWCard {
                        HStack {
                            CachedAsyncImage(url: definition.icon) {
                                Image(systemName: "trophy.fill").font(.largeTitle).foregroundStyle(GWPalette.accent)
                            }.frame(width: 64, height: 64)
                            VStack(alignment: .leading) {
                                Text(definition.name).font(.title2.bold())
                                Text("\(definition.totalPoints) achievement points")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if !definition.description.isEmpty { Text(definition.description.gwPlainText) }
                        Text(definition.requirement.gwPlainText).foregroundStyle(.secondary)
                    }
                    if !tracking.progressAvailable {
                        GWErrorBanner(message: "Connect a key with progression permission to see account progress.", stale: false)
                    } else {
                        GWCard {
                            Label(tracking.goalProgress.label, systemImage: tracking.isComplete == true ? "checkmark.circle.fill" : "chart.bar")
                                .foregroundStyle(tracking.isComplete == true ? .green : .primary)
                        }
                    }
                    if !tracking.bits.isEmpty {
                        GWSectionHeader(title: "Objectives")
                        ForEach(tracking.bits) { bit in
                            GWCard {
                                Label(bit.title, systemImage: bit.isComplete == true ? "checkmark.circle.fill" : "circle")
                            }
                        }
                    }
                    Button {
                        store.trackAchievement(definition)
                    } label: {
                        Label(isTracked ? "Tracked" : "Track Goal", systemImage: isTracked ? "checkmark" : "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(GWPalette.accent).disabled(isTracked)
                }.padding()
            } else {
                ProgressView("Loading achievement…").padding()
            }
        }
        .navigationTitle("Achievement")
        .task { await store.loadAchievement(id: achievementID) }
    }

    private var isTracked: Bool { store.goals.contains { $0.type == .achievement(achievementID) && $0.status != .archived } }
}

private struct CraftableItemBrowserView: View {
    @EnvironmentObject private var store: GoalStore
    @State private var query = ""

    var body: some View {
        List {
            switch store.recipeState {
            case let .loading(message):
                Section {
                    ProgressView(message)
                    if store.recipeIndex != nil {
                        Text("Crafting catalog ready").font(.caption).foregroundStyle(.secondary)
                    }
                }
            case let .unavailable(message):
                Section { Label(message, systemImage: "exclamationmark.triangle") }
            case let .cached(message):
                Section { Label(message, systemImage: "clock.arrow.circlepath") }
            case .ready:
                Section { Label("Crafting catalog ready", systemImage: "checkmark.circle") }
            case .idle:
                EmptyView()
            }
            ForEach(store.searchCraftableItems(query)) { item in
                NavigationLink { CraftingGoalEditorView(item: item) } label: {
                    HStack {
                        GWItemIcon(item: item, size: 40)
                        VStack(alignment: .leading) {
                            Text(item.name)
                            Text("\(store.recipeIndex?.recipesProducing(itemID: item.id).count ?? 0) recipe option(s)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if query.isEmpty, store.recipeIndex != nil {
                ContentUnavailableView(
                    "Search Craftable Items", systemImage: "magnifyingglass",
                    description: Text("Search runs locally over recipe-backed item metadata."))
            }
            if !query.isEmpty, store.searchCraftableItems(query).isEmpty, store.recipeIndex != nil {
                ContentUnavailableView.search(text: query)
            }
        }
        .navigationTitle("Craft Item")
        .searchable(text: $query, prompt: "Ascended sword")
        .task { await store.prepareRecipes() }
    }
}

private struct CraftingGoalEditorView: View {
    let item: ItemMetadata
    @EnvironmentObject private var store: GoalStore
    @Environment(\.dismiss) private var dismiss
    @State private var quantity = 1
    @State private var priority = GoalPriority.normal

    var body: some View {
        Form {
            Section {
                HStack { GWItemIcon(item: item, size: 54); Text(item.name).font(.headline) }
            }
            Section("Target") {
                Stepper("Quantity: \(quantity)", value: $quantity, in: 1...10_000)
                Picker("Priority", selection: $priority) {
                    ForEach(GoalPriority.allCases) { Text($0.title).tag($0) }
                }
            }
            Section {
                Button("Create Crafting Goal") {
                    store.addCraftingGoal(item: item, quantity: quantity, priority: priority)
                    dismiss()
                }.frame(maxWidth: .infinity)
            }
        }.navigationTitle("Craft Goal")
    }
}

private struct CustomGoalEditorView: View {
    @EnvironmentObject private var store: GoalStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var notes = ""
    @State private var priority = GoalPriority.normal
    @State private var checklist = ""

    var body: some View {
        Form {
            Section("Goal") {
                TextField("Title", text: $title)
                TextField("Notes", text: $notes, axis: .vertical).lineLimit(3...8)
                Picker("Priority", selection: $priority) {
                    ForEach(GoalPriority.allCases) { Text($0.title).tag($0) }
                }
            }
            Section("Checklist") {
                TextField("One item per line", text: $checklist, axis: .vertical).lineLimit(4...12)
                Text("Manual progress is stored as user-declared data.").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("Create Custom Goal") {
                    store.addCustomGoal(
                        title: title.trimmingCharacters(in: .whitespacesAndNewlines), notes: notes,
                        priority: priority, checklistTitles: checklist.components(separatedBy: .newlines))
                    dismiss()
                }.frame(maxWidth: .infinity).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.navigationTitle("Custom Goal")
    }
}
