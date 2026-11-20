import Foundation
import CoreFoundation

public struct Quote: Sendable {
    public let price: Decimal
    public let fetchedAt: Date
    public var priceText: String { String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), NSDecimalNumber(decimal: price).doubleValue) }
}
public enum QuoteError: LocalizedError {
    case invalidPage
    case http(Int)
    public var errorDescription: String? {
        switch self {
        case .invalidPage: return "未找到有效的工行积存金报价，网页可能已变更或暂时无行情。"
        case .http(let code): return "工行服务器返回 HTTP \(code)。"
        }
    }
}
public enum QuoteParser {
    public static func parse(_ data: Data, at date: Date = Date()) throws -> Quote {
        let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: gb),
              let regex = try? NSRegularExpression(pattern: #"<td\b[^>]*\bid\s*=\s*["']activeprice_080020000521["'][^>]*>\s*([0-9]+(?:\.[0-9]{1,2})?)\s*</td>"#, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html),
              let price = Decimal(string: String(html[range]), locale: Locale(identifier: "en_US_POSIX")), price > 0 else { throw QuoteError.invalidPage }
        return Quote(price: price, fetchedAt: date)
    }
}
