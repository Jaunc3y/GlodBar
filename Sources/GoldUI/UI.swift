import AppKit
import UserNotifications
import GoldCore

@MainActor
public final class AppController: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    public private(set) var statusItem: NSStatusItem?
    public private(set) var settings: Settings
    public lazy var settingsWindow = SettingsWindow(owner: self)
    private let defaults: UserDefaults
    private var timer: Timer?
    private var fetching = false
    private var polling = false
    private var engine = AlertEngine()
    private var latest: Quote?
    private var statusText = "正在获取工行报价…"
    private var lastSuccess: Date?
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults; self.settings = Settings.load(from: defaults); super.init() }
    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self
        setup(startPolling: true)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wake), name: NSWorkspace.didWakeNotification, object: nil)
        if CommandLine.arguments.contains("--settings") { showSettings(nil) }
    }
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(nil); return false }
    public func setup(startPolling: Bool) {
        polling = startPolling
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        statusItem?.button?.title = "--.--"
        statusItem?.button?.toolTip = statusText
        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "设置…", action: #selector(showSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self; menu.addItem(settingsItem); menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出", action: #selector(quit(_:)), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit); statusItem?.menu = menu
        if startPolling { restartTimer(); refresh() }
    }
    @objc private func quit(_ sender: Any?) { NSApp.terminate(nil) }
    @objc public func showSettings(_ sender: Any?) {
        settingsWindow.loadWindowIfNeeded()
        settingsWindow.populate(settings)
        settingsWindow.updateStatus(statusText)
        settingsWindow.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow.window?.makeKeyAndOrderFront(nil)
        if polling { updatePermissionStatus() }
    }
    @objc private func wake() { refresh() }
    private func restartTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: TimeInterval(settings.interval), target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    @objc private func tick() { refresh() }
    public func refresh() {
        guard polling, !fetching else { return }
        fetching = true
        Task { @MainActor in
            defer { fetching = false }
            do {
                let quote = try await QuoteClient().fetch()
                display(quote: quote)
                let permission = await Self.authorizationStatus()
                guard permission == .authorized || permission == .provisional else { return }
                var candidate = engine
                let directions = candidate.evaluate(quote.price, limits: settings.limits)
                for direction in directions {
                    let threshold = (direction == .below ? settings.limits.lower : settings.limits.upper)!
                    let content = Self.alertContent(quote: quote, direction: direction, threshold: threshold)
                    do {
                        try await Self.submit(content)
                    } catch {
                        settingsWindow.setPermissionText("通知发送失败：\(error.localizedDescription)")
                        return
                    }
                }
                engine = candidate
            } catch { display(error: error) }
        }
    }
    public func display(quote: Quote) {
        latest = quote; lastSuccess = quote.fetchedAt
        statusItem?.button?.title = quote.priceText
        if CommandLine.arguments.contains("--diagnostics") {
            let message = "QUOTE_OK price=\(quote.priceText) statusTitle=\(statusItem?.button?.title ?? "nil") fetched=\(quote.fetchedAt)\n"
            FileHandle.standardOutput.write(Data(message.utf8))
        }
        let time = quote.fetchedAt.formatted(date: .omitted, time: .standard)
        statusText = "\(quote.priceText) 元/克 · 最近获取 \(time)"
        statusItem?.button?.toolTip = "工行积存金 · 实时主动积存价格\n\(statusText)\n每 \(settings.interval) 秒获取，行情以工行为准"
        if settingsWindow.isWindowLoaded { settingsWindow.updateStatus(statusText) }
    }
    public func display(error: Error) {
        statusItem?.button?.title = latest.map { "\($0.priceText) !" } ?? "--.--"
        let previous = lastSuccess.map { "\n最近成功获取：\($0.formatted(date: .abbreviated, time: .standard))" } ?? ""
        statusText = "刷新失败：\(error.localizedDescription)\(previous)\n将自动重试；旧报价不触发提醒。"
        statusItem?.button?.toolTip = statusText
        if settingsWindow.isWindowLoaded { settingsWindow.updateStatus(statusText) }
    }
    public func apply(_ value: Settings) {
        let changed = value.limits != settings.limits
        settings = value; value.save(to: defaults)
        if changed { engine = AlertEngine() }
        guard polling else { return }
        restartTimer()
        if value.lowerEnabled || value.upperEnabled {
            Task { @MainActor in
                do { _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
                catch { settingsWindow.setPermissionText("申请通知权限失败：\(error.localizedDescription)") }
                updatePermissionStatus(); refresh()
            }
        } else { refresh() }
    }
    public static func alertContent(quote: Quote, direction: AlertDirection, threshold: Decimal) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = direction == .below ? "积存金低价提醒" : "积存金高价提醒"
        let verb = direction == .below ? "低于" : "高于"
        content.body = "工行积存金现价 \(quote.priceText) 元/克，\(verb)你设置的 \(threshold) 元/克。"
        content.sound = .default
        return content
    }
    private static func submit(_ content: UNMutableNotificationContent) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) { @Sendable error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }
    private static func authorizationStatus() async -> UNAuthorizationStatus {
        let raw: Int = await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { @Sendable settings in
                continuation.resume(returning: settings.authorizationStatus.rawValue)
            }
        }
        return UNAuthorizationStatus(rawValue: raw) ?? .notDetermined
    }
    public func updatePermissionStatus() {
        Task { @MainActor in
            let value = await Self.authorizationStatus()
            switch value {
            case .authorized, .provisional: settingsWindow.setPermissionText("系统通知已允许；专注模式可能影响横幅显示。")
            case .denied: settingsWindow.setPermissionText("系统通知未允许，请在「系统设置 → 通知 → 积存金」开启。")
            default: settingsWindow.setPermissionText("首次开启价格提醒并保存时，将申请系统通知权限。")
            }
        }
    }
    public func testNotification() {
        guard polling else { return }
        Task { @MainActor in
            do {
                let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                guard allowed else { updatePermissionStatus(); return }
                let content = UNMutableNotificationContent()
                content.title = "积存金 · 测试通知"
                content.body = "通知功能已开启。达到你设置的价格条件时，将在这里提醒。"
                content.sound = .default
                try await Self.submit(content)
                settingsWindow.setPermissionText("测试通知已提交；如无横幅，请检查通知样式与专注模式。")
            } catch { settingsWindow.setPermissionText("通知失败：\(error.localizedDescription)") }
        }
    }
    nonisolated public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .list, .sound]) }
}

@MainActor
public final class SettingsWindow: NSWindowController {
    private unowned let appController: AppController
    public let intervalPicker = NSPopUpButton()
    public let lowerToggle = NSButton(checkboxWithTitle: "低于", target: nil, action: nil)
    public let upperToggle = NSButton(checkboxWithTitle: "高于", target: nil, action: nil)
    public let lowerField = NSTextField()
    public let upperField = NSTextField()
    public let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let quoteLabel = NSTextField(wrappingLabelWithString: "正在获取工行报价…")
    private let permissionLabel = NSTextField(wrappingLabelWithString: "首次开启价格提醒并保存时，将申请系统通知权限。")
    public init(owner: AppController) { self.appController = owner; super.init(window: nil) }
    required init?(coder: NSCoder) { fatalError("Not supported") }
    private var built = false
    public func loadWindowIfNeeded() { if !built { loadWindow() } }
    public override func loadWindow() {
        guard !built else { return }; built = true
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 545), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "积存金 · 设置"
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        let root = NSStackView()
        root.orientation = .vertical; root.alignment = .leading; root.spacing = 15
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(root)
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 26), root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -26), root.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24)])
        func text(_ value: String, size: CGFloat = 12, bold: Bool = false) -> NSTextField {
            let label = NSTextField(wrappingLabelWithString: value)
            label.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
            label.textColor = bold ? .labelColor : .secondaryLabelColor
            return label
        }
        func row(_ views: [NSView]) -> NSStackView { let s = NSStackView(views: views); s.orientation = .horizontal; s.spacing = 12; return s }
        func divider() { let line = NSBox(); line.boxType = .separator; root.addArrangedSubview(line); line.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true }
        root.addArrangedSubview(text("工行积存金", size: 23, bold: true))
        quoteLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        root.addArrangedSubview(quoteLabel)
        root.addArrangedSubview(text("显示「实时主动积存价格」，单位：人民币元/克。"))
        divider()
        intervalPicker.addItems(withTitles: Settings.intervals.map { "\($0) 秒" })
        intervalPicker.setAccessibilityLabel("价格刷新间隔")
        root.addArrangedSubview(row([text("刷新间隔", size: 13, bold: true), intervalPicker]))
        root.addArrangedSubview(text("按所选间隔获取工行最新报价；不代表工行每次都有新价格。"))
        divider()
        root.addArrangedSubview(text("价格提醒", size: 14, bold: true))
        for (toggle, field, label) in [(lowerToggle, lowerField, "低价提醒阈值"), (upperToggle, upperField, "高价提醒阈值")] {
            field.placeholderString = "输入价格"; field.setAccessibilityLabel(label)
            field.widthAnchor.constraint(equalToConstant: 130).isActive = true
            toggle.target = self; toggle.action = #selector(toggleChanged(_:))
            root.addArrangedSubview(row([toggle, field, text("元/克时，发送系统通知")]))
        }
        root.addArrangedSubview(text("严格低于 / 高于时触发，等于不提醒。持续超限只提醒一次，回到范围后再次越界才提醒。启动或修改阈值后重新判断。"))
        permissionLabel.font = .systemFont(ofSize: 11); permissionLabel.textColor = .secondaryLabelColor
        root.addArrangedSubview(permissionLabel)
        let test = NSButton(title: "发送测试通知", target: self, action: #selector(testNotice(_:)))
        let permissions = NSButton(title: "系统通知设置", target: self, action: #selector(openPermissions(_:)))
        root.addArrangedSubview(row([test, permissions]))
        errorLabel.textColor = .systemRed; errorLabel.font = .systemFont(ofSize: 12)
        root.addArrangedSubview(errorLabel)
        let saveButton = NSButton(title: "保存设置", target: self, action: #selector(save(_:)))
        saveButton.bezelStyle = .rounded; saveButton.keyEquivalent = "\r"
        let source = NSButton(title: "工行行情网页 ↗", target: self, action: #selector(openSource(_:)))
        root.addArrangedSubview(row([source, saveButton]))
        for view in [quoteLabel, permissionLabel, errorLabel] { view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true }
        populate(appController.settings)
    }
    public func populate(_ settings: Settings) {
        intervalPicker.selectItem(at: Settings.intervals.firstIndex(of: settings.interval) ?? 3)
        lowerToggle.state = settings.lowerEnabled ? .on : .off; upperToggle.state = settings.upperEnabled ? .on : .off
        lowerField.stringValue = settings.lowerText; upperField.stringValue = settings.upperText
        errorLabel.stringValue = ""; toggleChanged(nil)
    }
    @objc private func toggleChanged(_ sender: Any?) { lowerField.isEnabled = lowerToggle.state == .on; upperField.isEnabled = upperToggle.state == .on }
    @objc public func save(_ sender: Any?) {
        do {
            let value = try Settings(interval: Settings.intervals[intervalPicker.indexOfSelectedItem], lowerEnabled: lowerToggle.state == .on, lowerText: lowerField.stringValue, upperEnabled: upperToggle.state == .on, upperText: upperField.stringValue)
            appController.apply(value)
            errorLabel.textColor = .secondaryLabelColor; errorLabel.stringValue = "已保存，下次获取报价时使用新设置。"
        } catch { errorLabel.textColor = .systemRed; errorLabel.stringValue = error.localizedDescription }
    }
    public func updateStatus(_ text: String) { quoteLabel.stringValue = text }
    public func setPermissionText(_ text: String) { permissionLabel.stringValue = text }
    @objc private func testNotice(_ sender: Any?) { appController.testNotification() }
    @objc private func openPermissions(_ sender: Any?) { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!) }
    @objc private func openSource(_ sender: Any?) { NSWorkspace.shared.open(QuoteClient.sourceURL) }
}
