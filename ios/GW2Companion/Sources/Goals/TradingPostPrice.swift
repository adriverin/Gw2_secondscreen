import Foundation

enum TradingPostPriceState: Equatable, Sendable {
    case loading
    case available(TimedCommercePrice)
    case noSellListings(TimedCommercePrice?)
    case notTradable
    case unavailable
    case stale(TimedCommercePrice)
    case failed(String)

    var isResolved: Bool {
        switch self {
        case .loading: false
        default: true
        }
    }
}

struct TradingPostPricePresentation: Equatable, Sendable {
    let itemID: Int
    let itemName: String
    let missingQuantity: Int
    let state: TradingPostPriceState
    let unitCopper: Int64?
    let buyNowCopper: Int64?
    let updatedAt: Date?

    var actionTitle: String {
        switch state {
        case .loading:
            return "Check Trading Post price"
        case let .available(price):
            if let buyNowCopper {
                return "Buy \(missingQuantity)\n≈ \(CoinAmount(copperValue: buyNowCopper).formatted)"
            }
            return "Lowest sell \(CoinAmount(copperValue: Int64(price.price.sells.unitPrice)).formatted)"
        case .noSellListings:
            return "No current sell listings"
        case .notTradable:
            return "Not tradable on the Trading Post"
        case .unavailable:
            return "Trading Post price unavailable"
        case let .stale(price):
            if let buyNowCopper {
                return "Buy \(missingQuantity)\n≈ \(CoinAmount(copperValue: buyNowCopper).formatted) (stale)"
            }
            return "Stale lowest sell \(CoinAmount(copperValue: Int64(price.price.sells.unitPrice)).formatted)"
        case .failed:
            return "Trading Post price failed"
        }
    }

    var canAttemptLookup: Bool {
        switch state {
        case .notTradable: false
        default: true
        }
    }

    var detailStatus: String {
        switch state {
        case .loading: "Loading current sell listings…"
        case .available: "Lowest sell offer"
        case .noSellListings: "No current sell listings"
        case .notTradable: "This item is not tradable on the Trading Post."
        case .unavailable: "A Trading Post price is not available."
        case .stale: "Stale Trading Post price"
        case let .failed(message): message
        }
    }
}

enum TradingPostPriceResolver {
    static func state(
        price: TimedCommercePrice?, item: ItemMetadata? = nil,
        now: Date = Date(), ttl: TimeInterval = 300,
        failed: String? = nil, loading: Bool = false
    ) -> TradingPostPriceState {
        if loading { return .loading }
        if item?.flags?.contains(where: { ["AccountBound", "SoulbindOnAcquire"].contains($0) }) == true {
            return .notTradable
        }
        if let failed { return .failed(failed) }
        guard let price else { return .unavailable }
        if now.timeIntervalSince(price.fetchedAt) > ttl {
            if price.price.sells.quantity > 0 && price.price.sells.unitPrice > 0 {
                return .stale(price)
            }
            return .stale(price)
        }
        if price.price.sells.quantity > 0 && price.price.sells.unitPrice > 0 {
            return .available(price)
        }
        return .noSellListings(price)
    }

    static func presentation(
        itemID: Int, itemName: String, missingQuantity: Int, state: TradingPostPriceState
    ) -> TradingPostPricePresentation {
        let timed: TimedCommercePrice? = switch state {
        case let .available(price), let .stale(price): price
        case let .noSellListings(price): price
        default: nil
        }
        let unit = timed.flatMap { value -> Int64? in
            guard value.price.sells.unitPrice > 0 else { return nil }
            return Int64(value.price.sells.unitPrice)
        }
        let buyNow = unit.flatMap { value in
            MarketCalculator.buyNow(price: timed, quantity: missingQuantity)?.copper
        }
        return TradingPostPricePresentation(
            itemID: itemID, itemName: itemName, missingQuantity: missingQuantity, state: state,
            unitCopper: unit, buyNowCopper: buyNow, updatedAt: timed?.fetchedAt)
    }

    static func suggestedActionTitle(
        name: String, missingQuantity: Int, state: TradingPostPriceState
    ) -> String? {
        switch state {
        case .notTradable:
            return nil
        case .loading, .unavailable, .failed:
            return "Check Trading Post price"
        case .noSellListings:
            return "Check Trading Post price"
        case .available, .stale:
            let presentation = presentation(
                itemID: 0, itemName: name, missingQuantity: missingQuantity, state: state)
            if let buyNow = presentation.buyNowCopper {
                return "Buy \(missingQuantity) • \(CoinAmount(copperValue: buyNow).formatted)"
            }
            return "Check Trading Post price"
        }
    }
}
