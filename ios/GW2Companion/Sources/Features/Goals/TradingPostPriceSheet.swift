import SwiftUI

struct PriceInspection: Identifiable {
    var id: Int { item.id }
    let item: ItemMetadata
    let quantity: Int
}

struct TradingPostPriceSheet: View {
    let item: ItemMetadata
    let quantity: Int
    @EnvironmentObject private var store: GoalStore
    @Environment(\.dismiss) private var dismiss
    @State private var metadataLoading = true
    @State private var priceLoading = true

    private var checkingPrice: Bool { priceLoading || store.priceLookups[item.id]?.isLoading == true }

    private var resolvedItem: ItemMetadata? {
        store.priceDetailItems[item.id] ?? (item.isPlaceholder ? nil : item)
    }

    private var presentation: TradingPostPricePresentation {
        let timed = store.marketPrices[item.id]
        let state = TradingPostPriceResolver.state(
            price: timed, item: resolvedItem, failed: store.priceLookups[item.id]?.error, loading: checkingPrice)
        return TradingPostPriceResolver.presentation(
            itemID: item.id, itemName: PriceItemHeader.title(item: resolvedItem, loading: metadataLoading),
            missingQuantity: quantity, state: state)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 10) {
                        if let resolvedItem { GWItemIcon(item: resolvedItem, size: 72) }
                        else if metadataLoading { RoundedRectangle(cornerRadius: GWSpacing.medium).fill(GWPalette.interactive).frame(width: 72, height: 72) }
                        Text(PriceItemHeader.title(item: resolvedItem, loading: metadataLoading))
                            .font(.title3.bold()).multilineTextAlignment(.center)
                        LabeledContent("Missing", value: quantity.formatted())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                Section("Trading Post") {
                    switch presentation.state {
                    case .loading:
                        ProgressView("Checking Trading Post…")
                    case .available, .stale:
                        if checkingPrice { Text("Last known price").font(.caption).foregroundStyle(.secondary) }
                        if let unit = presentation.unitCopper {
                            LabeledContent("Buy now · each", value: "\(CoinAmount(copperValue: unit).compactFormatted) each")
                        }
                        if let buyNow = presentation.buyNowCopper {
                            LabeledContent("Estimated stack", value: CoinAmount(copperValue: buyNow).compactFormatted)
                        }
                        if checkingPrice { ProgressView("Refreshing…") }
                        else if case .stale = presentation.state {
                            Text(store.priceLookups[item.id]?.error.map { "Showing last known price. \($0)" }
                                 ?? "This listing is older than five minutes.")
                                .font(.caption).foregroundStyle(GWPalette.warning)
                        }
                    case .noSellListings:
                        Text("No current sell listings")
                    case .notTradable:
                        Text("This item is not tradable on the Trading Post.")
                    case .unavailable:
                        Text("Trading Post price unavailable")
                    case let .failed(message):
                        Text(message)
                    }
                    if let updated = presentation.updatedAt {
                        LabeledContent("Updated", value: relative(updated))
                    }
                }
            }
            .navigationTitle("Trading Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .task(id: item.id) {
                metadataLoading = true
                priceLoading = true
                _ = await store.loadPriceItemMetadata(itemID: item.id)
                guard !Task.isCancelled else { return }
                metadataLoading = false
                await store.refreshPrice(itemID: item.id, force: true)
                priceLoading = false
            }
        }
        .accessibilityIdentifier("tradingpost.price.sheet")
    }

    private func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
