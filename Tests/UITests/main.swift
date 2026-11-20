import AppKit
import GoldUI
import GoldCore
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
func expect(_ value: @autoclosure () -> Bool, _ label: String) {
    if !value() { print("FAIL: \(label)"); exit(1) }; print("PASS: \(label)")
}
let defaults = UserDefaults(suiteName: "GoldBar.UITests.\(UUID().uuidString)")!
let controller = AppController(defaults: defaults)
controller.setup(startPolling: false)
expect(controller.statusItem?.menu?.items.map(\.title) == ["设置…", "", "退出"], "menu contains settings and quit")
let quote = try QuoteParser.parse(Data("<td id='activeprice_080020000521'>862.86</td>".utf8))
controller.display(quote: quote)
expect(controller.statusItem?.button?.title == "862.86", "menubar displays only two-decimal price")
controller.display(error: QuoteError.invalidPage)
expect(controller.statusItem?.button?.title == "862.86 !", "failed refresh marks old quote, never presents it as fresh")
let window = controller.settingsWindow
window.loadWindowIfNeeded()
expect(window.intervalPicker.numberOfItems == 5, "all five refresh options present")
window.intervalPicker.selectItem(at: 0)
window.lowerToggle.state = .on; window.lowerField.stringValue = "900"
window.upperToggle.state = .on; window.upperField.stringValue = "800"
window.save(nil)
expect(!window.errorLabel.stringValue.isEmpty, "invalid threshold range shows inline error")
expect(controller.settings.interval == 30, "invalid save leaves settings unchanged")
window.lowerField.stringValue = "800"
window.upperField.stringValue = "900"
window.save(nil)
expect(controller.settings.interval == 10, "settings save applies selected interval")
expect(Settings.load(from: defaults).upperText == "900", "UI save persists thresholds")
let content = AppController.alertContent(quote: quote, direction: .below, threshold: 870)
expect(content.body.contains("862.86") && content.body.contains("870"), "notification contains actual price and threshold")
window.window?.contentView?.layoutSubtreeIfNeeded()
let view = window.window!.contentView!
@MainActor func verifyBounds(_ view: NSView, root: NSView) {
    if let button = view as? NSButton {
        let rect = button.convert(button.bounds, to: root)
        expect(rect.minY >= 0 && rect.maxY <= root.bounds.height, "button visible: \(button.title)")
    }
    for child in view.subviews { verifyBounds(child, root: root) }
}
verifyBounds(view, root: view)
if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
    view.cacheDisplay(in: view.bounds, to: bitmap)
    let image = NSImage(size: view.bounds.size)
    image.lockFocus()
    NSColor.windowBackgroundColor.setFill(); view.bounds.fill()
    NSImage(cgImage: bitmap.cgImage!, size: view.bounds.size).draw(in: view.bounds)
    image.unlockFocus()
    let final = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try final.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "dist/settings-preview.png"))
}
print("UI_TESTS_OK")
