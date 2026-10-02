import CryptoKit
import os
import SwiftUI
import UIKit

enum GWPalette {
    static let accent = Color(red: 0.93, green: 0.43, blue: 0.16)
    static let background = adaptive(light: 0xF5F3F0, dark: 0x101418)
    static let secondaryBackground = adaptive(light: 0xECEAE7, dark: 0x171D23)
    static let card = adaptive(light: 0xFFFFFF, dark: 0x1E252C)
    static let interactive = adaptive(light: 0xE5E7E9, dark: 0x29323B)
    static let text = Color.primary
    static let secondaryText = Color.secondary
    static let mutedText = Color(uiColor: .tertiaryLabel)
    static let success = Color(uiColor: .systemGreen)
    static let warning = Color(uiColor: .systemYellow)
    static let danger = Color(uiColor: .systemRed)
    static let info = Color(uiColor: .systemCyan)
    static let mapOverlay = adaptive(light: 0xF5F3F0, dark: 0x171D23).opacity(0.94)
    static let mapOverlayBorder = Color.primary.opacity(0.12)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            let base = UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                               green: CGFloat((hex >> 8) & 255) / 255,
                               blue: CGFloat(hex & 255) / 255, alpha: 1)
            return traits.accessibilityContrast == .high
                ? (traits.userInterfaceStyle == .dark ? base.withAlphaComponent(1) : .white) : base
        })
    }

    static func profession(_ name: String) -> Color {
        switch name.lowercased() {
        case "guardian": Color(red: 0.36, green: 0.75, blue: 0.91)
        case "warrior": Color(red: 0.96, green: 0.75, blue: 0.30)
        case "engineer": Color(red: 0.78, green: 0.47, blue: 0.30)
        case "ranger": Color(red: 0.55, green: 0.78, blue: 0.31)
        case "thief": Color(red: 0.76, green: 0.45, blue: 0.48)
        case "elementalist": Color(red: 0.91, green: 0.31, blue: 0.25)
        case "mesmer": Color(red: 0.68, green: 0.40, blue: 0.80)
        case "necromancer": Color(red: 0.31, green: 0.68, blue: 0.50)
        case "revenant": Color(red: 0.78, green: 0.28, blue: 0.29)
        default: .orange
        }
    }

    static func rarity(_ rarity: String) -> Color {
        switch rarity.lowercased() {
        case "legendary": .purple
        case "ascended": .pink
        case "exotic": .orange
        case "rare": .yellow
        case "masterwork": .green
        case "fine": .blue
        default: .secondary
        }
    }
}

enum GWSpacing {
    static let xSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let section: CGFloat = 24
    static let screen: CGFloat = 32
}

enum GWTypography {
    static let hero = Font.largeTitle.weight(.bold)
    static let screen = Font.title2.weight(.bold)
    static let section = Font.title3.weight(.semibold)
    static let row = Font.headline
    static let body = Font.body
    static let secondary = Font.subheadline
    static let caption = Font.caption
    static let numeric = Font.title2.weight(.semibold).monospacedDigit()
}

enum GWAppearance: String, CaseIterable {
    case dark, light, system
    var colorScheme: ColorScheme? { self == .system ? nil : (self == .dark ? .dark : .light) }
}

enum GWPresentation {
    /// UI-only gate: Release cannot expose development tools through saved defaults.
    static var developerToolsAvailable: Bool {
#if DEBUG
        true
#else
        false
#endif
    }
    static var isDesignReview: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--phase7-preview")
#else
        false
#endif
    }
    static func itemName(_ item: ItemMetadata) -> String {
        item.name == "Item \(item.id)" ? "Item details unavailable" : item.name
    }
    static func motion(reduced: Bool) -> Animation? { reduced ? nil : .easeInOut(duration: 0.2) }
}

struct GWCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: GWSpacing.medium) { content }
            .padding(GWSpacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GWPalette.card, in: RoundedRectangle(cornerRadius: GWSpacing.large, style: .continuous))
    }
}

struct GWPlainSection<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: GWSpacing.medium) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GWSectionHeader: View {
    let title: String
    var subtitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: GWSpacing.xSmall) {
            Text(title).font(GWTypography.section).foregroundStyle(.primary)
            if let subtitle { Text(subtitle).font(GWTypography.caption).foregroundStyle(.secondary) }
        }.accessibilityElement(children: .combine)
    }
}

struct GWBadge: View {
    let text: String
    var color: Color = GWPalette.info
    var symbol: String?
    var body: some View {
        HStack(spacing: GWSpacing.xSmall) {
            if let symbol { Image(systemName: symbol).accessibilityHidden(true) }
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, GWSpacing.small).padding(.vertical, GWSpacing.xSmall)
        .background(color.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

struct GWPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline)
            .padding(.horizontal, GWSpacing.large).padding(.vertical, GWSpacing.medium)
            .frame(minHeight: 44)
            .foregroundStyle(.black)
            .background(GWPalette.accent, in: RoundedRectangle(cornerRadius: GWSpacing.medium))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
    }
}

struct GWSelectionButtonStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(selected ? .semibold : .regular))
            .padding(.horizontal, GWSpacing.medium).frame(minHeight: 44)
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .background(selected ? GWPalette.interactive : .clear, in: RoundedRectangle(cornerRadius: GWSpacing.medium))
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct GWSearchField: View {
    let prompt: String
    @Binding var text: String
    var body: some View {
        HStack(spacing: GWSpacing.small) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField(prompt, text: $text).textInputAutocapitalization(.never).autocorrectionDisabled()
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .frame(minWidth: 44, minHeight: 44).foregroundStyle(.secondary)
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, GWSpacing.medium).frame(minHeight: 44)
        .background(GWPalette.interactive, in: RoundedRectangle(cornerRadius: GWSpacing.medium))
    }
}

struct GWFreshnessLabel: View {
    let updated: Date
    var saved = false
    var body: some View {
        HStack(spacing: GWSpacing.xSmall) {
            if saved { Image(systemName: "clock.arrow.circlepath").accessibilityHidden(true) }
            Text(saved ? "Saved · updated" : "Updated")
            Text(updated, style: .relative)
        }.font(.caption).foregroundStyle(.secondary)
    }
}

struct GWLoadingRows: View {
    var count = 4
    var body: some View {
        VStack(spacing: GWSpacing.large) {
            ForEach(0..<count, id: \.self) { _ in
                HStack(spacing: GWSpacing.medium) {
                    RoundedRectangle(cornerRadius: GWSpacing.small).fill(GWPalette.interactive).frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: GWSpacing.small) {
                        Capsule().fill(GWPalette.interactive).frame(maxWidth: 220).frame(height: 12)
                        Capsule().fill(GWPalette.interactive).frame(maxWidth: 140).frame(height: 8)
                    }
                    Spacer()
                }
            }
        }.padding(GWSpacing.large)
            .accessibilityElement(children: .ignore).accessibilityLabel("Loading content")
    }
}

struct GWProgressSummary: View {
    let title: String
    let current: Int
    let total: Int
    var body: some View {
        VStack(alignment: .leading, spacing: GWSpacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text("\(current) / \(total)").font(GWTypography.numeric)
            }
            ProgressView(value: Double(current), total: Double(max(1, total)))
                .tint(current >= total && total > 0 ? GWPalette.success : GWPalette.accent)
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title), \(current) of \(total) complete")
    }
}

struct GWUIGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GWSpacing.section) {
                GWSectionHeader(title: "Your second screen for Tyria", subtitle: "Component gallery")
                GWCard {
                    HStack { GWBadge(text: "LIVE", color: GWPalette.success, symbol: "circle.fill"); GWBadge(text: "READY", color: GWPalette.success); GWBadge(text: "SAVED", symbol: "clock") }
                    HStack { GWBadge(text: "ACCOUNT-BOUND", color: .secondary, symbol: "lock"); GWBadge(text: "MISSING", color: GWPalette.warning) }
                    GWProgressSummary(title: "Daily", current: 3, total: 4)
                    CoinAmountView(value: 124218)
                    Button("Plan My Session") {}.buttonStyle(GWPrimaryButtonStyle())
                }
                GWLoadingRows()
                GWErrorBanner(message: "Some item details aren't available yet", stale: false)
                GWEmptyState(title: "No active goals", message: "Choose something to work toward.", symbol: "target", actionTitle: "Add Goal", action: {})
            }.padding(GWSpacing.section).frame(maxWidth: 720)
        }.navigationTitle("UI Gallery")
    }
}

struct GWEmptyState: View {
    let title: String
    let message: String
    let symbol: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action { Button(actionTitle, action: action).buttonStyle(.borderedProminent) }
        }
    }
}

struct GWErrorBanner: View {
    let message: String
    let stale: Bool
    var retry: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: stale ? "clock.arrow.circlepath" : "exclamationmark.triangle.fill")
            Text(stale ? "Using saved data. Pull to refresh when you’re connected." : message)
                .font(.caption).frame(maxWidth: .infinity, alignment: .leading)
            if let retry { Button("Try Again", action: retry).font(.caption.bold()) }
        }
        .padding(12)
        .background(GWPalette.secondaryBackground, in: RoundedRectangle(cornerRadius: GWSpacing.medium))
        .accessibilityElement(children: .combine)
    }
}

struct GWItemIcon: View {
    let item: ItemMetadata
    var size: CGFloat = 46

    var body: some View {
        CachedAsyncImage(url: item.icon) {
            RoundedRectangle(cornerRadius: 9).fill(.quaternary)
                .overlay(Image(systemName: "shippingbox.fill").foregroundStyle(.secondary))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay { RoundedRectangle(cornerRadius: 9).stroke(GWPalette.rarity(item.rarity).opacity(0.7), lineWidth: 1) }
        .accessibilityLabel("\(GWPresentation.itemName(item)), \(item.rarity)")
    }
}

actor RemoteImagePipeline {
    static let shared = RemoteImagePipeline()
    static let memoryCountLimit = 400
    static let memoryCostLimit = 64 * 1_024 * 1_024
    static let diskFileLimit = 2_000

    private let session: URLSession
    private let directory: URL
    private var memory = BoundedMemoryCache<URL, UIImage>(
        countLimit: memoryCountLimit, totalCostLimit: memoryCostLimit)
    private var inFlight: [URL: Task<UIImage, Error>] = [:]
    private let countState = OSAllocatedUnfairLock(initialState: 0)
    nonisolated var memoryCount: Int { countState.withLock { $0 } }

    init(session: URLSession = .shared, directory: URL? = nil) {
        self.session = session
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.directory = directory ?? caches.appending(path: "GW2CompanionImages", directoryHint: .isDirectory)
    }

    func image(for url: URL) async throws -> UIImage {
        if let cached = memory.value(for: url) { return cached }
        let file = directory.appending(path: Self.hash(url.absoluteString))
        if let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
            memory.set(image, for: url, cost: data.count)
            let count = memory.count
            countState.withLock { $0 = count }
            return image
        }
        if let task = inFlight[url] { return try await task.value }
        let task = Task { [session, directory] in
            let (data, response) = try await session.data(from: url)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let image = UIImage(data: data) else { throw URLError(.badServerResponse) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: directory.appending(path: Self.hash(url.absoluteString)), options: .atomic)
            DiskCachePruner.prune(directory: directory, maxFiles: Self.diskFileLimit)
            return image
        }
        inFlight[url] = task
        defer { inFlight[url] = nil }
        let image = try await task.value
        memory.set(image, for: url, cost: Int(image.size.width * image.size.height * 4))
        let count = memory.count
        countState.withLock { $0 = count }
        return image
    }

    func handleMemoryPressure() {
        memory.removeAll()
        countState.withLock { $0 = 0 }
    }

    private static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct CachedAsyncImage<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let placeholder: Placeholder
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else { placeholder }
        }
        .task(id: url) {
            image = nil
            guard let url else { return }
            image = try? await RemoteImagePipeline.shared.image(for: url)
        }
    }
}

extension String {
    var gwPlainText: String {
        guard contains("<"), let data = data(using: .utf8),
              let value = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil) else { return self }
        return value.string.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Display-only conversion through the existing map transformer; navigation thresholds stay in continent units.
enum GWMapDistancePresentation {
    static func text(from: ContinentPoint, to: ContinentPoint, metadata: GW2MapMetadata?) -> String {
        guard let metadata else { return "Distance unavailable" }
        let transformer = GW2CoordinateTransformer(metadata: metadata)
        guard let start = try? transformer.mapPoint(from: from),
              let end = try? transformer.mapPoint(from: to) else { return "Distance unavailable" }
        let meters = hypot(end.x - start.x, end.y - start.y) / 39.370_078_740_157_48
        return "\(meters.formatted(.number.precision(.fractionLength(0)))) m"
    }
}
