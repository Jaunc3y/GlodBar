import Foundation
import GoldCore
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { print("FAIL: \(message)"); exit(1) }
    print("PASS: \(message)")
}
let html = "<td id='regprice_080020000521'>888.00</td><td id='activeprice_080020000521'> 862.86 </td><td id='sellprice_080020000521'>860.00</td>"
if CommandLine.arguments.contains("--live") {
    let live = try await QuoteClient().fetch()
    expect(live.price > 0, "live HTTPS quote fetched")
    print("LIVE_PRICE=\(live.priceText) FETCHED_AT=\(live.fetchedAt)")
}
let quote = try QuoteParser.parse(Data(html.utf8))
expect(quote.priceText == "862.86", "extract active price, not regular or redemption price")
let settings = try Settings(interval: 15, lowerEnabled: true, lowerText: "860.50", upperEnabled: true, upperText: "900")
expect(settings.interval == 15 && settings.limits.lower == Decimal(string: "860.50"), "validate refresh and decimal thresholds")
for interval in [10, 15, 20, 30, 60] { _ = try Settings(interval: interval) }
func rejects(_ label: String, _ body: () throws -> Void) {
    do { try body(); expect(false, label) } catch { print("PASS: \(label)") }
}
rejects("invalid refresh rejected") { _ = try Settings(interval: 11) }
rejects("reversed thresholds rejected") { _ = try Settings(lowerEnabled: true, lowerText: "900", upperEnabled: true, upperText: "800") }
for bad in ["", "abc", "0", "-1", "NaN", "123abc", "8.888"] {
    rejects("invalid threshold \(bad)") { _ = try Settings(lowerEnabled: true, lowerText: bad) }
}
for bad in ["<html>维护中</html>", "<td id='sellprice_080020000521'>862.86</td>", "<td id='activeprice_080020000521'>0.00</td>", "<td id='activeprice_080020000521'>NaN</td>", "<td id='activeprice_080020000521'>862.861</td>", "<td id='activeprice_999999999999'>862.86</td>"] {
    rejects("malformed, missing or wrong-product quote rejected") { _ = try QuoteParser.parse(Data(bad.utf8)) }
}
let store = UserDefaults(suiteName: "GoldBar.Tests.\(UUID().uuidString)")!
settings.save(to: store)
expect(Settings.load(from: store) == settings, "settings persist across reload")
var engine = AlertEngine()
let limits = AlertLimits(lower: 860, upper: 870)
expect(engine.evaluate(859, limits: limits) == [.below], "first sample below lower limit alerts")
expect(engine.evaluate(858, limits: limits).isEmpty, "sustained breach does not repeat")
expect(engine.evaluate(860, limits: limits).isEmpty, "equal lower limit does not alert")
expect(engine.evaluate(859, limits: limits) == [.below], "return then cross rearms lower alert")
expect(engine.evaluate(871, limits: limits) == [.above], "jump across to upper limit alerts")
expect(engine.evaluate(872, limits: limits).isEmpty, "sustained upper breach does not repeat")
expect(engine.evaluate(870, limits: limits).isEmpty, "equal upper limit rearms")
expect(engine.evaluate(871, limits: limits) == [.above], "upper recross alerts")
expect(engine.evaluate(1, limits: AlertLimits()).isEmpty, "disabled thresholds never alert")
