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

    private var presentation: TradingPostPricePresentation {
        let timed = store.marketPrices[item.id]
        let state = TradingPostPriceResolver.state(
            price: timed, item: item, failed: store.priceError)
        return TradingPostPriceResolver.presentation(
            itemID: item.id, itemName: item.name, missingQuantity: quantity, state: state)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 10) {
                        GWItemIcon(item: item, size: 72)
                        Text(item.name.uppercased()).font(.title3.bold()).multilineTextAlignment(.center)
                        LabeledContent("Missing", value: quantity.formatted())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                Section("Trading Post") {
                    switch presentation.state {
                    case .loading:
                        Label("Loading current sell listings…", systemImage: "arrow.triangle.2.circlepath")
                    case .available, .stale:
                        if let unit = presentation.unitCopper {
                            LabeledContent("Lowest sell offer", value: "\(CoinAmount(copperValue: unit).formatted) each")
                        }
                        if let buyNow = presentation.buyNowCopper {
                            LabeledContent("Estimated buy-now", value: CoinAmount(copperValue: buyNow).formatted)
                        }
                        if case .stale = presentation.state {
                            Text("This listing is older than five minutes.")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    case .noSellListings:
                        Text("No current sell listings")
                    case .notTradable:
                        Text("This item is not tradable on the Trading Post.")
                    case .unavailable:
                        Text("A Trading Post price is not available.")
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
            .task {
                await store.refreshPrice(itemID: item.id, force: true)
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
