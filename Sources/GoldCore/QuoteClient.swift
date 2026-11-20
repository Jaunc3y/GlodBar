import Foundation
public struct QuoteClient: Sendable {
    public static let sourceURL = URL(string: "https://mybank.icbc.com.cn/icbc/newperbank/perbank3/gold/goldaccrual_query_out.jsp")!
    public init() {}
    public func fetch() async throws -> Quote {
        var parts = URLComponents(url: Self.sourceURL, resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "_", value: String(Int(Date().timeIntervalSince1970)))]
        var request = URLRequest(url: parts.url!, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 8)
        request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("Mozilla/5.0 (Macintosh; Mac OS X 15_0) GoldBar/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw QuoteError.invalidPage }
        guard response.statusCode == 200 else { throw QuoteError.http(response.statusCode) }
        return try QuoteParser.parse(data)
    }
}
