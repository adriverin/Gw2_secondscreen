import Foundation

enum InventoryPricePreference: String, CaseIterable, Identifiable, Sendable {
    case off
    case sellNow
    case buyNow

    static let storageKey = "inventory.prices.preference.v1"
    var id: Self { self }

    var title: String {
        switch self {
        case .off: "Off"
        case .sellNow: "Sell-now"
        case .buyNow: "Buy-now"
        }
    }
}

struct OwnedItemMarketValues: Equatable, Sendable {
    let sellNow: MarketEstimate?
    let buyNow: MarketEstimate?
    let sellState: MarketDataState
    let buyState: MarketDataState
    let updatedAt: Date?

    init(item: ItemMetadata, quantity: Int, price: TimedCommercePrice?, now: Date = Date()) {
        sellNow = MarketCalculator.sellNow(price: price, quantity: quantity, now: now)
        buyNow = MarketCalculator.buyNow(price: price, quantity: quantity, now: now)
        sellState = MarketCalculator.sellState(price: price, item: item, now: now)
        buyState = MarketCalculator.buyState(price: price, item: item, now: now)
        updatedAt = price?.fetchedAt
    }

    func rowValue(for preference: InventoryPricePreference) -> MarketEstimate? {
        switch preference {
        case .off: nil
        case .sellNow: sellNow
        case .buyNow: buyNow
        }
    }

    func rowLabel(for preference: InventoryPricePreference) -> String? {
        guard let value = rowValue(for: preference) else { return nil }
        let prefix = preference == .sellNow ? "Sell now" : "Buy now"
        return "\(prefix)  \(value.amount.compactFormatted) stack"
    }
}

enum InventoryPriceBatchPlanner {
    static func batch(visibleItemIDs: [Int], selectedItemID: Int? = nil, limit: Int = 200) -> [Int] {
        var seen = Set<Int>()
        var values: [Int] = []
        if let selectedItemID, selectedItemID > 0, seen.insert(selectedItemID).inserted {
            values.append(selectedItemID)
        }
        for id in visibleItemIDs where id > 0 && seen.insert(id).inserted {
            guard values.count < max(1, limit) else { break }
            values.append(id)
        }
        return values
    }
}

extension CoinAmount {
    var compactFormatted: String {
        var parts: [String] = []
        if gold > 0 { parts.append("\(gold)g") }
        if silver > 0 || gold > 0 { parts.append("\(silver)s") }
        if copper > 0 || parts.isEmpty { parts.append("\(copper)c") }
        return parts.joined(separator: " ")
    }
}
