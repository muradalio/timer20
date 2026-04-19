import AppKit
import Foundation
import ServiceManagement
import UserNotifications

private struct AppSettings {
    private enum Key {
        static let legacyWorkMinutes = "workMinutes"
        static let workSeconds = "workSeconds"
        static let restSeconds = "restSeconds"
    }

    var workSeconds: Int
    var restSeconds: Int

    var workDuration: TimeInterval {
        TimeInterval(workSeconds)
    }

    var restDuration: TimeInterval {
        TimeInterval(restSeconds)
    }

    static func load() -> AppSettings {
        let defaults = UserDefaults.standard
        let savedWorkSeconds = defaults.object(forKey: Key.workSeconds) == nil ? nil : defaults.integer(forKey: Key.workSeconds)
        let legacyWorkMinutes = defaults.integer(forKey: Key.legacyWorkMinutes)
        let savedRestSeconds = defaults.integer(forKey: Key.restSeconds)

        return AppSettings(
            workSeconds: savedWorkSeconds ?? (legacyWorkMinutes > 0 ? legacyWorkMinutes * 60 : 20 * 60),
            restSeconds: savedRestSeconds > 0 ? savedRestSeconds : 20
        )
    }

    func save() {
        UserDefaults.standard.set(workSeconds, forKey: Key.workSeconds)
        UserDefaults.standard.set(restSeconds, forKey: Key.restSeconds)
    }
}

private enum L {
    static let isEnglish = Locale.preferredLanguages.first?.hasPrefix("en") == true

    static let launchAtLogin = isEnglish ? "Launch at login" : "Запускать при входе в macOS"
    static let settings = isEnglish ? "Settings" : "Настройки"
    static let workDuration = isEnglish ? "Work, minutes" : "Работа, минут"
    static let workDurationHint = isEnglish ? "Use 0.5 or 0:30 for 30 seconds." : "Для 30 секунд можно ввести 0,3 или 0:30."
    static let restDuration = isEnglish ? "Rest, seconds" : "Отдых, секунд"
    static let save = isEnglish ? "Save" : "Сохранить"
    static let loginEnabled = isEnglish ? "Launch at login is enabled." : "Автозапуск включён."
    static let loginRequiresApproval = isEnglish
        ? "Approve in System Settings > General > Login Items."
        : "Нужно подтвердить в System Settings > General > Login Items."
    static let loginDisabled = isEnglish ? "Launch at login is off." : "Автозапуск выключен."
    static let loginUnknown = isEnglish ? "Launch at login status is unknown." : "Статус автозапуска неизвестен."
    static let launchAtLoginError = isEnglish ? "Could not change launch at login" : "Не удалось изменить автозапуск"
    static let starting = isEnglish ? "Timer20 is starting..." : "Timer20 запускается..."
    static let pause = isEnglish ? "Pause" : "Пауза"
    static let resume = isEnglish ? "Resume" : "Продолжить"
    static let startRestNow = isEnglish ? "Start rest now" : "Начать отдых сейчас"
    static let settingsMenu = isEnglish ? "Settings..." : "Настройки..."
    static let about = isEnglish ? "About Timer20" : "О Timer20"
    static let quit = isEnglish ? "Quit" : "Выйти"
    static let work = isEnglish ? "Work" : "Работа"
    static let rest = isEnglish ? "Rest" : "Отдых"
    static let restPause = isEnglish ? "Rest paused" : "Пауза отдыха"
    static let continueTitle = isEnglish ? "You can continue" : "Можно продолжать"
    static let restTitle = isEnglish ? "Time to rest" : "Пора отдохнуть"
    static let author = isEnglish ? "Author" : "Автор"
    static let aboutSummary = isEnglish ? "Work, then rest your eyes." : "20 минут работы, 20 секунд отдыха."

    static func nextBreakBody(duration: String) -> String {
        isEnglish ? "Next break in \(duration)." : "Следующий перерыв через \(duration)."
    }

    static func restBody(duration: String) -> String {
        isEnglish ? "Look away for \(duration)." : "Посмотри вдаль \(duration)."
    }

    static func resetTitle(seconds: Int) -> String {
        if isEnglish {
            return "Reset \(durationText(seconds: seconds))"
        }

        return "Сбросить \(durationText(seconds: seconds))"
    }

    static func durationText(seconds: Int) -> String {
        if seconds < 60 {
            if isEnglish {
                let unit = seconds == 1 ? "second" : "seconds"
                return "\(seconds) \(unit)"
            }
            return "\(seconds) \(russianSecondWord(seconds))"
        }

        if seconds.isMultiple(of: 60) {
            let minutes = seconds / 60
            if isEnglish {
                let unit = minutes == 1 ? "minute" : "minutes"
                return "\(minutes) \(unit)"
            }
            return "\(minutes) \(russianMinuteWord(minutes))"
        }

        let minutes = seconds / 60
        let restSeconds = seconds % 60
        return String(format: "%02d:%02d", minutes, restSeconds)
    }

    private static func russianMinuteWord(_ count: Int) -> String {
        let lastTwoDigits = count % 100
        let lastDigit = count % 10

        if (11...14).contains(lastTwoDigits) {
            return "минут"
        }

        switch lastDigit {
        case 1:
            return "минуту"
        case 2...4:
            return "минуты"
        default:
            return "минут"
        }
    }

    private static func russianSecondWord(_ count: Int) -> String {
        let lastTwoDigits = count % 100
        let lastDigit = count % 10

        if (11...14).contains(lastTwoDigits) {
            return "секунд"
        }

        switch lastDigit {
        case 1:
            return "секунду"
        case 2...4:
            return "секунды"
        default:
            return "секунд"
        }
    }
}

private enum TimerPhase {
    case working
    case resting
    case paused(previous: RunningPhase, remaining: TimeInterval)
}

private enum RunningPhase {
    case working
    case resting
}

@MainActor
private final class SettingsWindowController: NSWindowController {
    private let workField = NSTextField()
    private let restField = NSTextField()
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: L.launchAtLogin, target: nil, action: nil)
    private let loginStatusLabel = NSTextField(labelWithString: "")
    private let onSave: (AppSettings) -> Void

    init(settings: AppSettings, onSave: @escaping (AppSettings) -> Void) {
        self.onSave = onSave

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 390, height: 250),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Timer20"
        window.center()

        super.init(window: window)

        setupContent(settings: settings)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show(settings: AppSettings) {
        workField.stringValue = formatWorkInput(seconds: settings.workSeconds)
        restField.integerValue = settings.restSeconds
        launchAtLoginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
        updateLoginStatus()

        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setupContent(settings: AppSettings) {
        workField.stringValue = formatWorkInput(seconds: settings.workSeconds)
        restField.integerValue = settings.restSeconds
        workField.placeholderString = "20"
        restField.placeholderString = "20"
        workField.alignment = .right
        restField.alignment = .right

        launchAtLoginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
        updateLoginStatus()

        let title = NSTextField(labelWithString: L.settings)
        title.font = .boldSystemFont(ofSize: 16)

        let workRow = row(label: L.workDuration, field: workField)
        let workHint = NSTextField(labelWithString: L.workDurationHint)
        workHint.font = .systemFont(ofSize: 11)
        workHint.textColor = .secondaryLabelColor
        let restRow = row(label: L.restDuration, field: restField)

        let saveButton = NSButton(title: L.save, target: self, action: #selector(save))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"

        let stack = NSStackView(views: [
            title,
            workRow,
            workHint,
            restRow,
            launchAtLoginCheckbox,
            loginStatusLabel,
            saveButton
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        window?.contentView = stack
    }

    private func row(label: String, field: NSTextField) -> NSView {
        let labelView = NSTextField(labelWithString: label)
        labelView.widthAnchor.constraint(equalToConstant: 150).isActive = true
        field.widthAnchor.constraint(equalToConstant: 80).isActive = true

        let stack = NSStackView(views: [labelView, field])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        return stack
    }

    @objc private func save() {
        let workSeconds = max(1, min(240 * 60, parseWorkSeconds(from: workField.stringValue)))
        let restSeconds = max(1, min(600, restField.integerValue))
        workField.stringValue = formatWorkInput(seconds: workSeconds)
        restField.integerValue = restSeconds

        let settings = AppSettings(workSeconds: workSeconds, restSeconds: restSeconds)
        settings.save()
        configureLaunchAtLogin(enabled: launchAtLoginCheckbox.state == .on)
        onSave(settings)
        window?.close()
    }

    private func parseWorkSeconds(from rawValue: String) -> Int {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = value.replacingOccurrences(of: ",", with: ":")

        if normalized.contains(":") {
            let parts = normalized.split(separator: ":", omittingEmptySubsequences: false)
            let minutes = Int(parts.first ?? "0") ?? 0
            let secondsPart = parts.dropFirst().first.map(String.init) ?? "0"
            let paddedSeconds = secondsPart.count == 1 ? "\(secondsPart)0" : secondsPart
            let seconds = Int(paddedSeconds) ?? 0
            return minutes * 60 + min(seconds, 59)
        }

        if let minutes = Double(value.replacingOccurrences(of: ",", with: ".")) {
            return Int((minutes * 60).rounded())
        }

        return 20 * 60
    }

    private func formatWorkInput(seconds: Int) -> String {
        if seconds.isMultiple(of: 60) {
            return "\(seconds / 60)"
        }

        let minutes = seconds / 60
        let restSeconds = seconds % 60
        return "\(minutes):\(String(format: "%02d", restSeconds))"
    }

    private func configureLaunchAtLogin(enabled: Bool) {
        do {
            if enabled, SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            } else if !enabled, SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            showAlert(message: L.launchAtLoginError, detail: error.localizedDescription)
        }
        updateLoginStatus()
    }

    private func updateLoginStatus() {
        switch SMAppService.mainApp.status {
        case .enabled:
            loginStatusLabel.stringValue = L.loginEnabled
        case .requiresApproval:
            loginStatusLabel.stringValue = L.loginRequiresApproval
        case .notRegistered:
            loginStatusLabel.stringValue = L.loginDisabled
        case .notFound:
            loginStatusLabel.stringValue = ""
        @unknown default:
            loginStatusLabel.stringValue = L.loginUnknown
        }
    }

    private func showAlert(message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.runModal()
    }
}

@MainActor
private final class TransitionBannerController {
    private let panel: NSPanel
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let bodyLabel = NSTextField(labelWithString: "")
    private var dismissTimer: Timer?

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 112),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        setupContent()
    }

    func show(title: String, body: String, symbolName: String) {
        dismissTimer?.invalidate()

        titleLabel.stringValue = title
        bodyLabel.stringValue = body
        iconView.image = image(symbolName: symbolName, size: 28)

        positionPanel()
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 1
        }

        dismissTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.dismiss()
            }
        }
    }

    private func dismiss() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.panel.orderOut(nil)
            }
        }
    }

    private func setupContent() {
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 8
        visualEffect.layer?.masksToBounds = true
        visualEffect.translatesAutoresizingMaskIntoConstraints = false

        iconView.symbolConfiguration = .init(pointSize: 26, weight: .semibold)
        iconView.contentTintColor = .labelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .boldSystemFont(ofSize: 17)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        bodyLabel.font = .systemFont(ofSize: 13)
        bodyLabel.textColor = .secondaryLabelColor
        bodyLabel.lineBreakMode = .byTruncatingTail

        let textStack = NSStackView(views: [titleLabel, bodyLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4

        let contentStack = NSStackView(views: [iconView, textStack])
        contentStack.orientation = .horizontal
        contentStack.alignment = .centerY
        contentStack.spacing = 14
        contentStack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        visualEffect.addSubview(contentStack)
        panel.contentView = visualEffect

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 34),
            iconView.heightAnchor.constraint(equalToConstant: 34)
        ])
    }

    private func positionPanel() {
        guard let screen = NSScreen.main else {
            panel.center()
            return
        }

        let visibleFrame = screen.visibleFrame
        let frame = panel.frame
        let x = visibleFrame.midX - frame.width / 2
        let y = visibleFrame.maxY - frame.height - 16
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func image(symbolName: String, size: CGFloat) -> NSImage? {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        image?.isTemplate = true
        image?.size = NSSize(width: size, height: size)
        return image
    }
}

@MainActor
private final class Timer20App: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var settings = AppSettings.load()
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var phase: TimerPhase = .working
    private var phaseEndsAt = Date()
    private var lastVisibleSecond: Int = -1
    private var settingsWindowController: SettingsWindowController?
    private var bannerController: TransitionBannerController?
    private var pulseTimer: Timer?
    private var pulseTicks = 0

    private lazy var menu: NSMenu = {
        let menu = NSMenu()
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        menu.addItem(pauseMenuItem)
        menu.addItem(startRestMenuItem)
        menu.addItem(resetMenuItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L.settingsMenu, action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L.about, action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L.quit, action: #selector(quit), keyEquivalent: "q"))
        return menu
    }()

    private lazy var statusMenuItem: NSMenuItem = {
        let item = NSMenuItem(title: L.starting, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }()

    private lazy var pauseMenuItem: NSMenuItem = {
        menuItem(title: L.pause, symbolName: "pause.fill", action: #selector(togglePause), keyEquivalent: "p")
    }()

    private lazy var startRestMenuItem: NSMenuItem = {
        menuItem(title: L.startRestNow, symbolName: "eye.fill", action: #selector(startRestNow), keyEquivalent: "r")
    }()

    private lazy var resetMenuItem: NSMenuItem = {
        menuItem(title: resetMenuTitle(), symbolName: "arrow.counterclockwise", action: #selector(resetWork), keyEquivalent: "0")
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                NSLog("Notification authorization failed: \(error.localizedDescription)")
            }
            if !granted {
                NSLog("Notification authorization was not granted.")
            }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = statusImage()
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        statusItem.menu = menu

        start(.working, duration: settings.workDuration, shouldNotify: false)
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        pulseTimer?.invalidate()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    @objc private func togglePause() {
        switch phase {
        case .working:
            pause(previous: .working)
        case .resting:
            pause(previous: .resting)
        case let .paused(previous, remaining):
            start(previous, duration: remaining, shouldNotify: false)
        }
    }

    @objc private func startRestNow() {
        start(.resting, duration: settings.restDuration, shouldNotify: true)
    }

    @objc private func resetWork() {
        start(.working, duration: settings.workDuration, shouldNotify: false)
    }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(settings: settings) { [weak self] newSettings in
                self?.apply(newSettings)
            }
        }

        settingsWindowController?.show(settings: settings)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"

        let alert = NSAlert()
        alert.messageText = "Timer20"
        alert.informativeText = "\(L.isEnglish ? "Version" : "Версия") \(version) (\(build))\n\(L.author): Mur\n\n\(L.aboutSummary)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.icon = statusImage()
        alert.runModal()
    }

    @objc private func tick() {
        updateMenuBar()

        guard remainingSeconds() <= 0 else {
            return
        }

        switch phase {
        case .working:
            start(.resting, duration: settings.restDuration, shouldNotify: true)
        case .resting:
            start(.working, duration: settings.workDuration, shouldNotify: true)
        case .paused:
            break
        }
    }

    @objc private func pulseTick() {
        pulseTicks += 1
        statusItem.button?.alphaValue = pulseTicks.isMultiple(of: 2) ? 0.35 : 1

        if pulseTicks >= 8 {
            pulseTimer?.invalidate()
            pulseTimer = nil
            statusItem.button?.alphaValue = 1
        }
    }

    private func apply(_ newSettings: AppSettings) {
        settings = newSettings
        updateStaticMenuTitles()
        start(.working, duration: settings.workDuration, shouldNotify: false)
    }

    private func start(_ runningPhase: RunningPhase, duration: TimeInterval, shouldNotify: Bool) {
        timer?.invalidate()
        phase = runningPhase == .working ? .working : .resting
        phaseEndsAt = Date().addingTimeInterval(duration)
        lastVisibleSecond = -1

        timer = Timer.scheduledTimer(
            timeInterval: 0.5,
            target: self,
            selector: #selector(tick),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer!, forMode: .common)

        if shouldNotify {
            announceTransition(to: runningPhase)
        }

        updateMenuBar(force: true)
    }

    private func announceTransition(to runningPhase: RunningPhase) {
        let message = transitionMessage(for: runningPhase)
        notify(title: message.title, body: message.body)

        if bannerController == nil {
            bannerController = TransitionBannerController()
        }
        bannerController?.show(title: message.title, body: message.body, symbolName: message.symbolName)

        pulseStatusItem()
    }

    private func transitionMessage(for runningPhase: RunningPhase) -> (title: String, body: String, symbolName: String) {
        switch runningPhase {
        case .working:
            return (
                title: L.continueTitle,
                body: L.nextBreakBody(duration: format(Int(settings.workDuration))),
                symbolName: "laptopcomputer"
            )
        case .resting:
            return (
                title: L.restTitle,
                body: L.restBody(duration: format(Int(settings.restDuration))),
                symbolName: "eye.fill"
            )
        }
    }

    private func pulseStatusItem() {
        pulseTimer?.invalidate()
        pulseTicks = 0
        statusItem.button?.alphaValue = 1

        pulseTimer = Timer.scheduledTimer(
            timeInterval: 0.16,
            target: self,
            selector: #selector(pulseTick),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(pulseTimer!, forMode: .common)
    }

    private func updateStaticMenuTitles() {
        resetMenuItem.title = resetMenuTitle()
    }

    private func resetMenuTitle() -> String {
        L.resetTitle(seconds: settings.workSeconds)
    }

    private func pause(previous: RunningPhase) {
        let remaining = max(0, phaseEndsAt.timeIntervalSinceNow)
        timer?.invalidate()
        phase = .paused(previous: previous, remaining: remaining)
        lastVisibleSecond = -1
        updateMenuBar(force: true)
    }

    private func updateMenuBar(force: Bool = false) {
        let seconds = remainingSeconds()
        guard force || seconds != lastVisibleSecond else {
            return
        }
        lastVisibleSecond = seconds

        let title: String
        let detail: String
        let statusSymbolName: String

        switch phase {
        case .working:
            title = format(seconds)
            detail = "\(L.work): \(format(seconds))"
            statusSymbolName = "laptopcomputer"
            pauseMenuItem.title = L.pause
            pauseMenuItem.image = menuImage(symbolName: "pause.fill")
        case .resting:
            title = format(seconds)
            detail = "\(L.rest): \(format(seconds))"
            statusSymbolName = "eye.fill"
            pauseMenuItem.title = L.pause
            pauseMenuItem.image = menuImage(symbolName: "pause.fill")
        case let .paused(previous, remaining):
            let label = previous == .working ? L.pause : L.restPause
            title = format(Int(ceil(remaining)))
            detail = "\(label): \(format(Int(ceil(remaining))))"
            statusSymbolName = "pause.fill"
            pauseMenuItem.title = L.resume
            pauseMenuItem.image = menuImage(symbolName: "play.fill")
        }

        statusItem.button?.image = statusImage(symbolName: statusSymbolName)
        statusItem.button?.title = title
        statusMenuItem.title = detail
    }

    private func statusImage(symbolName: String = "eye") -> NSImage? {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Timer20")
        image?.isTemplate = true
        image?.size = NSSize(width: 16, height: 16)
        return image
    }

    private func menuItem(
        title: String,
        symbolName: String,
        action: Selector,
        keyEquivalent: String
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.image = menuImage(symbolName: symbolName)
        return item
    }

    private func menuImage(symbolName: String) -> NSImage? {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        image?.isTemplate = true
        image?.size = NSSize(width: 16, height: 16)
        return image
    }

    private func remainingSeconds() -> Int {
        switch phase {
        case .working, .resting:
            return max(0, Int(ceil(phaseEndsAt.timeIntervalSinceNow)))
        case let .paused(_, remaining):
            return max(0, Int(ceil(remaining)))
        }
    }

    private func format(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "timer20-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("Notification delivery failed: \(error.localizedDescription)")
            }
        }
    }
}

let app = NSApplication.shared
private let delegate = Timer20App()
app.delegate = delegate
app.run()
