import Foundation
public struct Settings: Codable, Equatable, Sendable {
    public static let intervals = [10, 15, 20, 30, 60]
    public let interval: Int
    public let lowerEnabled: Bool
    public let lowerText: String
    public let upperEnabled: Bool
    public let upperText: String
    public var limits: AlertLimits {
        AlertLimits(lower: lowerEnabled ? Decimal(string: lowerText) : nil, upper: upperEnabled ? Decimal(string: upperText) : nil)
    }
    public init(interval: Int = 30, lowerEnabled: Bool = false, lowerText: String = "", upperEnabled: Bool = false, upperText: String = "") throws {
        guard Self.intervals.contains(interval) else { throw SettingsError.invalidInterval }
        self.interval = interval; self.lowerEnabled = lowerEnabled; self.upperEnabled = upperEnabled
        self.lowerText = lowerText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.upperText = upperText.trimmingCharacters(in: .whitespacesAndNewlines)
        for (enabled, text) in [(lowerEnabled, self.lowerText), (upperEnabled, self.upperText)] where enabled {
            guard text.range(of: #"^[0-9]+(?:\.[0-9]{1,2})?$"#, options: .regularExpression) != nil,
                  let value = Decimal(string: text), value > 0, value < 1000000 else { throw SettingsError.invalidPrice }
        }
        if let lower = limits.lower, let upper = limits.upper, lower >= upper { throw SettingsError.invalidRange }
    }
    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: "settings.v1") }
    }
    public static func load(from defaults: UserDefaults = .standard) -> Settings {
        if let data = defaults.data(forKey: "settings.v1"), let s = try? JSONDecoder().decode(Self.self, from: data),
           let validated = try? Settings(interval: s.interval, lowerEnabled: s.lowerEnabled, lowerText: s.lowerText, upperEnabled: s.upperEnabled, upperText: s.upperText) { return validated }
        return try! Settings()
    }
}
public enum SettingsError: LocalizedError {
    case invalidInterval, invalidPrice, invalidRange
    public var errorDescription: String? {
        switch self {
        case .invalidInterval: return "请选择 10、15、20、30 或 60 秒。"
        case .invalidPrice: return "请输入有效价格：大于 0、小于 1000000，最多两位小数。"
        case .invalidRange: return "低价提醒的阈值必须小于高价提醒的阈值。"
        }
    }
}
