import AppKit
import Foundation
import ServiceManagement
import UserNotifications

private struct AppSettings {
    private enum Key {
        static let workMinutes = "workMinutes"
        static let restSeconds = "restSeconds"
    }

    var workMinutes: Int
    var restSeconds: Int

    var workDuration: TimeInterval {
        TimeInterval(workMinutes * 60)
    }

    var restDuration: TimeInterval {
        TimeInterval(restSeconds)
    }

    static func load() -> AppSettings {
        let defaults = UserDefaults.standard
        let savedWorkMinutes = defaults.integer(forKey: Key.workMinutes)
        let savedRestSeconds = defaults.integer(forKey: Key.restSeconds)

        return AppSettings(
            workMinutes: savedWorkMinutes > 0 ? savedWorkMinutes : 20,
            restSeconds: savedRestSeconds > 0 ? savedRestSeconds : 20
        )
    }

    func save() {
        UserDefaults.standard.set(workMinutes, forKey: Key.workMinutes)
        UserDefaults.standard.set(restSeconds, forKey: Key.restSeconds)
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
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Запускать при входе в macOS", target: nil, action: nil)
    private let loginStatusLabel = NSTextField(labelWithString: "")
    private let onSave: (AppSettings) -> Void

    init(settings: AppSettings, onSave: @escaping (AppSettings) -> Void) {
        self.onSave = onSave

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 220),
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
        workField.integerValue = settings.workMinutes
        restField.integerValue = settings.restSeconds
        launchAtLoginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
        updateLoginStatus()

        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setupContent(settings: AppSettings) {
        workField.integerValue = settings.workMinutes
        restField.integerValue = settings.restSeconds
        workField.placeholderString = "20"
        restField.placeholderString = "20"
        workField.alignment = .right
        restField.alignment = .right

        launchAtLoginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
        updateLoginStatus()

        let title = NSTextField(labelWithString: "Настройки")
        title.font = .boldSystemFont(ofSize: 16)

        let workRow = row(label: "Работа, минут", field: workField)
        let restRow = row(label: "Отдых, секунд", field: restField)

        let saveButton = NSButton(title: "Сохранить", target: self, action: #selector(save))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"

        let stack = NSStackView(views: [
            title,
            workRow,
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
        let workMinutes = max(1, min(240, workField.integerValue))
        let restSeconds = max(1, min(600, restField.integerValue))
        workField.integerValue = workMinutes
        restField.integerValue = restSeconds

        let settings = AppSettings(workMinutes: workMinutes, restSeconds: restSeconds)
        settings.save()
        configureLaunchAtLogin(enabled: launchAtLoginCheckbox.state == .on)
        onSave(settings)
        window?.close()
    }

    private func configureLaunchAtLogin(enabled: Bool) {
        do {
            if enabled, SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            } else if !enabled, SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            showAlert(message: "Не удалось изменить автозапуск", detail: error.localizedDescription)
        }
        updateLoginStatus()
    }

    private func updateLoginStatus() {
        switch SMAppService.mainApp.status {
        case .enabled:
            loginStatusLabel.stringValue = "Автозапуск включён."
        case .requiresApproval:
            loginStatusLabel.stringValue = "Нужно подтвердить в System Settings > General > Login Items."
        case .notRegistered:
            loginStatusLabel.stringValue = "Автозапуск выключен."
        case .notFound:
            loginStatusLabel.stringValue = ""
        @unknown default:
            loginStatusLabel.stringValue = "Статус автозапуска неизвестен."
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
private final class Timer20App: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var settings = AppSettings.load()
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var phase: TimerPhase = .working
    private var phaseEndsAt = Date()
    private var lastVisibleSecond: Int = -1
    private var settingsWindowController: SettingsWindowController?

    private lazy var menu: NSMenu = {
        let menu = NSMenu()
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        menu.addItem(pauseMenuItem)
        menu.addItem(startRestMenuItem)
        menu.addItem(resetMenuItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Настройки...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "О Timer20", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Выйти", action: #selector(quit), keyEquivalent: "q"))
        return menu
    }()

    private lazy var statusMenuItem: NSMenuItem = {
        let item = NSMenuItem(title: "Timer20 запускается...", action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }()

    private lazy var pauseMenuItem: NSMenuItem = {
        menuItem(title: "Пауза", symbolName: "pause.fill", action: #selector(togglePause), keyEquivalent: "p")
    }()

    private lazy var startRestMenuItem: NSMenuItem = {
        menuItem(title: "Начать отдых сейчас", symbolName: "eye.fill", action: #selector(startRestNow), keyEquivalent: "r")
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
        alert.informativeText = "Версия \(version) (\(build))\nАвтор: Mur\n\n20 минут работы, 20 секунд отдыха."
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
            switch runningPhase {
            case .working:
                notify(title: "Можно продолжать", body: "Следующий перерыв через \(format(Int(settings.workDuration))).")
            case .resting:
                notify(title: "Пора отдохнуть", body: "Посмотри вдаль \(format(Int(settings.restDuration))).")
            }
        }

        updateMenuBar(force: true)
    }

    private func updateStaticMenuTitles() {
        resetMenuItem.title = resetMenuTitle()
    }

    private func resetMenuTitle() -> String {
        "Сбросить \(settings.workMinutes) \(minuteWord(settings.workMinutes))"
    }

    private func minuteWord(_ count: Int) -> String {
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
            detail = "Работа: \(format(seconds))"
            statusSymbolName = "laptopcomputer"
            pauseMenuItem.title = "Пауза"
            pauseMenuItem.image = menuImage(symbolName: "pause.fill")
        case .resting:
            title = format(seconds)
            detail = "Отдых: \(format(seconds))"
            statusSymbolName = "eye.fill"
            pauseMenuItem.title = "Пауза"
            pauseMenuItem.image = menuImage(symbolName: "pause.fill")
        case let .paused(previous, remaining):
            let label = previous == .working ? "Пауза" : "Пауза отдыха"
            title = format(Int(ceil(remaining)))
            detail = "\(label): \(format(Int(ceil(remaining))))"
            statusSymbolName = "pause.fill"
            pauseMenuItem.title = "Продолжить"
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
