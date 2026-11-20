import Foundation
public struct AlertLimits: Equatable, Sendable {
    public var lower: Decimal?
    public var upper: Decimal?
    public init(lower: Decimal? = nil, upper: Decimal? = nil) { self.lower = lower; self.upper = upper }
}
public enum AlertDirection: String, Sendable { case below, above }
public struct AlertEngine: Sendable {
    private var below = false
    private var above = false
    public init() {}
    public mutating func evaluate(_ price: Decimal, limits: AlertLimits) -> [AlertDirection] {
        let newBelow = limits.lower.map { price < $0 } ?? false
        let newAbove = limits.upper.map { price > $0 } ?? false
        var result: [AlertDirection] = []
        if newBelow && !below { result.append(.below) }
        if newAbove && !above { result.append(.above) }
        below = newBelow; above = newAbove
        return result
    }
}
