import CryptoKit
import os
import SwiftUI
import UIKit

enum GWPalette {
    static let accent = Color(red: 0.93, green: 0.43, blue: 0.16)
    static let card = Color.primary.opacity(0.055)

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

struct GWCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GWPalette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.primary.opacity(0.08), lineWidth: 1)
            }
    }
}

struct GWSectionHeader: View {
    let title: String
    var subtitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased()).font(.caption.bold()).tracking(1.1).foregroundStyle(.secondary)
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.tertiary) }
        }
        .accessibilityElement(children: .combine)
    }
}

struct GWBadge: View {
    let text: String
    var color: Color = GWPalette.accent
    var symbol: String?

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.caption2.bold())
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.14), in: Capsule())
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
            Text(stale ? "Couldn't refresh. Showing saved account data." : message)
                .font(.caption).frame(maxWidth: .infinity, alignment: .leading)
            if let retry { Button("Try Again", action: retry).font(.caption.bold()) }
        }
        .padding(12)
        .background(.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
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
        .overlay { RoundedRectangle(cornerRadius: 9).stroke(GWPalette.rarity(item.rarity), lineWidth: 2) }
        .accessibilityLabel("\(item.name), \(item.rarity)")
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
