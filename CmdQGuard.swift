import AppKit
import ApplicationServices
import CoreGraphics
import UniformTypeIdentifiers

enum ProtectionScope: Int {
    case all = 0
    case whitelist = 1
    case blacklist = 2
}

@main
private struct CmdQGuardEntry {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var statusLabel: NSTextField?
    private var windowDelayLabel: NSTextField?
    private var menuDelayLabel: NSTextField?
    private var delaySlider: NSSlider?
    private var protectionCheckbox: NSButton?
    private var showsPermissionUI = true
    private let guarder = CmdQGuard()
    private var enabled = true
    private var delay: Double = 1.0
    private var scope: ProtectionScope = .all
    private var protectedApps: [(id: String, name: String, icon: NSImage)] = []
    private var appsTable: NSTableView?
    private var addAppButton: NSButton?
    private var removeAppButton: NSButton?
    private var statusMessage = "Запускаю защиту…"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        enabled = UserDefaults.standard.object(forKey: "protectionEnabled") as? Bool ?? true
        delay = UserDefaults.standard.object(forKey: "holdDelay") as? Double ?? 1.0
        scope = ProtectionScope(rawValue: UserDefaults.standard.integer(forKey: "protectionScope")) ?? .all
        protectedApps = (UserDefaults.standard.stringArray(forKey: "protectedAppBundleIDs") ?? [])
            .map { appEntry(for: $0) }
        guarder.setHoldSeconds(delay)
        guarder.setProtectedApps(Set(protectedApps.map(\.id)), scope: scope)
        guarder.onStatusChange = { [weak self] message in
            self?.statusMessage = message
            self?.statusLabel?.stringValue = message
            self?.updatePermissionUI()
            self?.rebuildMenu()
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "CmdQ Guard")
            button.title = " ⌘Q"
            button.toolTip = "CmdQ Guard — защита от случайного выхода"
        }
        buildSettingsWindow()
        rebuildMenu()
        if enabled {
            guarder.start()
        } else {
            statusMessage = "Защита выключена"
            rebuildMenu()
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let enabledItem = NSMenuItem(title: "Защищать от случайного ⌘Q", action: #selector(toggleProtection(_:)), keyEquivalent: "")
        enabledItem.target = self
        enabledItem.state = enabled ? .on : .off
        menu.addItem(enabledItem)

        let delayItem = NSMenuItem()
        delayItem.view = makeDelayControl()
        menu.addItem(delayItem)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Закрыть CmdQ Guard", action: #selector(quit(_:)), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
        let settings = NSMenuItem(title: "Открыть окно CmdQ Guard", action: #selector(showSettings(_:)), keyEquivalent: "")
        settings.target = self
        menu.insertItem(settings, at: 0)
        self.statusItem.menu = menu
    }

    private func buildSettingsWindow() {
        let permissionNeeded = !isAccessibilityTrusted()
        showsPermissionUI = permissionNeeded
        let height = windowHeight(permissionNeeded: permissionNeeded)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: height),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CmdQ Guard"
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView?.wantsLayer = true
        populateWindow(window, permissionNeeded: permissionNeeded, height: height)
        settingsWindow = window
    }

    private func windowHeight(permissionNeeded: Bool) -> CGFloat {
        var h: CGFloat = 24                                   // верхний отступ
        h += 30 + 2 + 44 + 10 + 48 + 6                        // заголовок, пояснение, статус
        if permissionNeeded { h += 76 + 11 }                  // инструкция
        h += 24 + 11 + 20 + 8 + 28 + 6 + 18 + 6 + 26 + 8      // галочка, задержка, режим
        h += 170 + 8 + 26                                     // таблица, кнопки списка
        if permissionNeeded { h += 18 + 32 }                  // кнопки разрешения
        return h + 28                                         // нижний отступ
    }

    // Раскладка сверху вниз: y — нижняя кромка следующего блока.
    private func populateWindow(_ window: NSWindow, permissionNeeded: Bool, height: CGFloat) {
        guard let content = window.contentView else { return }
        content.subviews.forEach { $0.removeFromSuperview() }
        var y = height - 24

        let title = NSTextField(labelWithString: "Защита от случайного выхода")
        title.font = .boldSystemFont(ofSize: 22)
        y -= 30
        title.frame = NSRect(x: 28, y: y, width: 500, height: 30)
        content.addSubview(title)
        y -= 2

        let explanation = NSTextField(wrappingLabelWithString: "Короткое ⌘Q будет блокироваться. Чтобы закрыть активное приложение, удерживайте ⌘Q дольше выбранного времени.")
        y -= 44
        explanation.frame = NSRect(x: 28, y: y, width: 500, height: 44)
        content.addSubview(explanation)
        y -= 10

        let status = NSTextField(wrappingLabelWithString: statusMessage)
        status.font = .systemFont(ofSize: 13, weight: .medium)
        y -= 48
        status.frame = NSRect(x: 28, y: y, width: 500, height: 48)
        statusLabel = status
        content.addSubview(status)
        y -= 6

        if permissionNeeded {
            let instructions = NSTextField(wrappingLabelWithString: "Чтобы включить перехват: нажмите кнопку ниже → в окне настроек откройте «Конфиденциальность и безопасность» → «Универсальный доступ» → нажмите + → выберите CmdQ Guard.app в папке CmdQGuard → включите переключатель. Вернитесь сюда и нажмите «Проверить разрешение».")
            instructions.font = .systemFont(ofSize: 12)
            y -= 76
            instructions.frame = NSRect(x: 28, y: y, width: 500, height: 76)
            content.addSubview(instructions)
            y -= 11
        }

        let checkbox = NSButton(checkboxWithTitle: "Защищать от случайного ⌘Q", target: self, action: #selector(windowToggleProtection(_:)))
        checkbox.state = enabled ? .on : .off
        y -= 24
        checkbox.frame = NSRect(x: 28, y: y, width: 300, height: 24)
        protectionCheckbox = checkbox
        content.addSubview(checkbox)
        y -= 11

        let delayText = NSTextField(labelWithString: "Удерживать ⌘Q: \(delay.formatted(.number.precision(.fractionLength(1)))) с")
        y -= 20
        delayText.frame = NSRect(x: 28, y: y, width: 300, height: 20)
        windowDelayLabel = delayText
        content.addSubview(delayText)
        y -= 8

        let slider = NSSlider(value: delay, minValue: 0.5, maxValue: 3.0, target: self, action: #selector(delayChanged(_:)))
        y -= 28
        slider.frame = NSRect(x: 24, y: y, width: 320, height: 28)
        slider.numberOfTickMarks = 6
        slider.allowsTickMarkValuesOnly = false
        delaySlider = slider
        content.addSubview(slider)
        y -= 6

        let scopeText = NSTextField(labelWithString: "Применять защиту:")
        y -= 18
        scopeText.frame = NSRect(x: 28, y: y, width: 300, height: 18)
        content.addSubview(scopeText)
        y -= 6

        let scopeControl = NSSegmentedControl(
            labels: ["Все приложения", "Только выбранные", "Все, кроме выбранных"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(scopeChanged(_:))
        )
        scopeControl.selectedSegment = scope.rawValue
        y -= 26
        scopeControl.frame = NSRect(x: 28, y: y, width: 440, height: 26)
        content.addSubview(scopeControl)
        y -= 8

        y -= 170
        let scroll = NSScrollView(frame: NSRect(x: 28, y: y, width: 504, height: 170))
        let table = NSTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        column.width = 480
        table.addTableColumn(column)
        table.headerView = nil
        table.rowSizeStyle = .default
        table.usesAlternatingRowBackgroundColors = true
        table.dataSource = self
        table.delegate = self
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        table.isEnabled = scope != .all
        appsTable = table
        content.addSubview(scroll)
        y -= 8

        y -= 26
        let addButton = NSButton(title: "Добавить приложение…", target: self, action: #selector(addAppMenu(_:)))
        addButton.bezelStyle = .rounded
        addButton.frame = NSRect(x: 28, y: y, width: 180, height: 26)
        addButton.isEnabled = scope != .all
        addAppButton = addButton
        content.addSubview(addButton)

        let removeButton = NSButton(title: "Убрать выбранное", target: self, action: #selector(removeSelectedApp(_:)))
        removeButton.bezelStyle = .rounded
        removeButton.frame = NSRect(x: 220, y: y, width: 160, height: 26)
        removeButton.isEnabled = scope != .all
        removeAppButton = removeButton
        content.addSubview(removeButton)

        if permissionNeeded {
            y -= 18
            y -= 32
            let settingsButton = NSButton(title: "Открыть настройки разрешения", target: self, action: #selector(openAccessibility(_:)))
            settingsButton.bezelStyle = .rounded
            settingsButton.frame = NSRect(x: 28, y: y, width: 230, height: 32)
            content.addSubview(settingsButton)

            let retry = NSButton(title: "Проверить разрешение", target: self, action: #selector(retryProtection(_:)))
            retry.bezelStyle = .rounded
            retry.frame = NSRect(x: 270, y: y, width: 190, height: 32)
            content.addSubview(retry)
        }
    }

    @objc private func showSettings(_ sender: Any?) {
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(nil)
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    private func makeDelayControl() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 52))
        let label = NSTextField(labelWithString: "Удерживать ⌘Q: \(delay.formatted(.number.precision(.fractionLength(1)))) с")
        label.frame = NSRect(x: 22, y: 30, width: 220, height: 16)
        menuDelayLabel = label
        container.addSubview(label)

        let slider = NSSlider(value: delay, minValue: 0.5, maxValue: 3.0, target: self, action: #selector(delayChanged(_:)))
        slider.frame = NSRect(x: 18, y: 4, width: 234, height: 24)
        slider.numberOfTickMarks = 6
        slider.allowsTickMarkValuesOnly = false
        slider.tag = 9201
        container.addSubview(slider)
        return container
    }

    @objc private func toggleProtection(_ sender: NSMenuItem) {
        enabled = sender.state != .on
        protectionCheckbox?.state = enabled ? .on : .off
        UserDefaults.standard.set(enabled, forKey: "protectionEnabled")
        if enabled {
            guarder.start()
        } else {
            guarder.stop()
            statusMessage = "Защита выключена"
        }
        rebuildMenu()
    }

    @objc private func windowToggleProtection(_ sender: NSButton) {
        enabled = sender.state == .on
        UserDefaults.standard.set(enabled, forKey: "protectionEnabled")
        if enabled { guarder.start() } else {
            guarder.stop()
            statusMessage = "Защита выключена"
            statusLabel?.stringValue = statusMessage
        }
        rebuildMenu()
    }

    @objc private func delayChanged(_ sender: NSSlider) {
        delay = (sender.doubleValue * 10).rounded() / 10
        UserDefaults.standard.set(delay, forKey: "holdDelay")
        guarder.setHoldSeconds(delay)
        let delayText = "Удерживать ⌘Q: \(delay.formatted(.number.precision(.fractionLength(1)))) с"
        windowDelayLabel?.stringValue = delayText
        menuDelayLabel?.stringValue = delayText
        delaySlider?.doubleValue = delay
    }

    @objc private func retryProtection(_ sender: Any?) {
        enabled = true
        UserDefaults.standard.set(true, forKey: "protectionEnabled")
        protectionCheckbox?.state = .on
        guarder.start(manualCheck: true)
        rebuildMenu()
    }

    @objc private func openAccessibility(_ sender: Any?) {
        let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrustedWithOptions([
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false
        ] as CFDictionary)
    }

    private func updatePermissionUI() {
        let needed = !isAccessibilityTrusted()
        guard needed != showsPermissionUI, let window = settingsWindow else { return }
        showsPermissionUI = needed
        let height = windowHeight(permissionNeeded: needed)
        var frame = window.frame
        frame.origin.y += frame.height - height
        frame.size.height = height
        window.setFrame(frame, display: true, animate: true)
        populateWindow(window, permissionNeeded: needed, height: height)
    }

    @objc private func scopeChanged(_ sender: NSSegmentedControl) {
        scope = ProtectionScope(rawValue: sender.selectedSegment) ?? .all
        let editable = scope != .all
        appsTable?.isEnabled = editable
        addAppButton?.isEnabled = editable
        removeAppButton?.isEnabled = editable
        syncProtectedApps()
    }

    @objc private func addAppMenu(_ sender: NSButton) {
        let menu = NSMenu()
        let fileItem = NSMenuItem(title: "Выбрать файл приложения…", action: #selector(chooseAppFile(_:)), keyEquivalent: "")
        fileItem.target = self
        menu.addItem(fileItem)
        menu.addItem(.separator())

        let ownID = Bundle.main.bundleIdentifier
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != ownID }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        for app in running {
            let item = NSMenuItem(title: app.localizedName ?? "?", action: #selector(addRunningApp(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = app.bundleIdentifier
            if let icon = app.icon {
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
            }
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func addRunningApp(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        addProtectedApp(bundleID)
    }

    @objc private func chooseAppFile(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Добавить"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let bundleID = Bundle(url: url)?.bundleIdentifier {
                addProtectedApp(bundleID)
            }
        }
    }

    @objc private func removeSelectedApp(_ sender: Any?) {
        guard let table = appsTable, table.selectedRow >= 0 else { return }
        protectedApps.remove(at: table.selectedRow)
        syncProtectedApps()
    }

    private func addProtectedApp(_ bundleID: String) {
        guard !protectedApps.contains(where: { $0.id == bundleID }) else { return }
        protectedApps.append(appEntry(for: bundleID))
        protectedApps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        syncProtectedApps()
    }

    private func appEntry(for bundleID: String) -> (id: String, name: String, icon: NSImage) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return (id: bundleID, name: bundleID, icon: NSImage())
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 18, height: 18)
        return (id: bundleID, name: FileManager.default.displayName(atPath: url.path), icon: icon)
    }

    private func syncProtectedApps() {
        UserDefaults.standard.set(protectedApps.map(\.id), forKey: "protectedAppBundleIDs")
        UserDefaults.standard.set(scope.rawValue, forKey: "protectionScope")
        guarder.setProtectedApps(Set(protectedApps.map(\.id)), scope: scope)
        appsTable?.reloadData()
    }

    @objc private func quit(_ sender: Any?) { NSApp.terminate(nil) }
}

extension AppDelegate: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        protectedApps.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        24
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTableCellView()
        let imageView = NSImageView(frame: NSRect(x: 4, y: 3, width: 18, height: 18))
        imageView.image = protectedApps[row].icon
        let text = NSTextField(labelWithString: protectedApps[row].name)
        text.frame = NSRect(x: 28, y: 3, width: 420, height: 18)
        text.lineBreakMode = .byTruncatingTail
        cell.addSubview(imageView)
        cell.addSubview(text)
        cell.imageView = imageView
        cell.textField = text
        return cell
    }
}

private final class CmdQGuard {
    var onStatusChange: ((String) -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let lock = NSLock()
    private var qDown = false
    private var alreadyQuit = false
    private var generation = 0
    private var targetPID: pid_t = 0
    private var holdSeconds: TimeInterval = 1.0
    private var protectedBundleIDs = Set<String>()
    private var scope: ProtectionScope = .all

    func setHoldSeconds(_ seconds: TimeInterval) {
        lock.lock()
        holdSeconds = max(0.5, min(3.0, seconds))
        lock.unlock()
    }

    func setProtectedApps(_ bundleIDs: Set<String>, scope: ProtectionScope) {
        lock.lock()
        protectedBundleIDs = bundleIDs
        self.scope = scope
        lock.unlock()
    }

    // Вызывается только при захваченном lock.
    private func isProtected(_ bundleID: String?) -> Bool {
        if protectedBundleIDs.isEmpty || scope == .all { return true }
        guard let bundleID else { return scope != .whitelist }
        return scope == .whitelist
            ? protectedBundleIDs.contains(bundleID)
            : !protectedBundleIDs.contains(bundleID)
    }

    func start(manualCheck: Bool = false) {
        guard tap == nil else {
            onStatusChange?("Защита работает. Короткое нажатие ⌘Q блокируется.")
            return
        }
        // Only check the existing grant here. Opening System Settings is an
        // explicit user action via the dedicated button, not a side effect of
        // launching the app or pressing “Check permission”.
        let trusted = AXIsProcessTrustedWithOptions([
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false
        ] as CFDictionary)
        guard trusted else {
            let message = manualCheck
                ? "Проверка завершена: macOS не подтвердил доступ CmdQ Guard 4. В Универсальном доступе выключите и снова включите переключатель CmdQ Guard 4, затем перезапустите приложение."
                : "macOS не подтвердил доступ CmdQ Guard 4. Проверьте переключатель в разделе «Универсальный доступ»."
            onStatusChange?(message)
            return
        }

        let events: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: events,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                return Unmanaged<CmdQGuard>.fromOpaque(refcon)
                    .takeUnretainedValue().handle(type: type, event: event)
            },
            userInfo: refcon
        ) else {
            onStatusChange?("Не удалось создать перехват клавиш. Проверьте разрешение Универсального доступа.")
            return
        }
        tap = newTap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        CGEvent.tapEnable(tap: newTap, enable: true)
        onStatusChange?("Защита работает. Удерживайте ⌘Q, чтобы выйти.")
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        source = nil
        tap = nil
        lock.lock()
        generation += 1
        qDown = false
        lock.unlock()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyDown, keyCode == 12, event.flags.contains(.maskCommand),
           !event.flags.contains(.maskAlternate), !event.flags.contains(.maskControl) {
            let frontmost = NSWorkspace.shared.frontmostApplication
            lock.lock()
            if !qDown {
                if !isProtected(frontmost?.bundleIdentifier) {
                    lock.unlock()
                    return Unmanaged.passUnretained(event)
                }
                qDown = true
                alreadyQuit = false
                generation += 1
                let currentGeneration = generation
                targetPID = frontmost?.processIdentifier ?? 0
                let pid = targetPID
                let delay = holdSeconds
                lock.unlock()
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.completeHold(generation: currentGeneration, pid: pid)
                }
            } else {
                lock.unlock()
            }
            return nil
        }

        if type == .keyUp, keyCode == 12 {
            lock.lock()
            let wasOurChord = qDown
            qDown = false
            generation += 1
            alreadyQuit = false
            lock.unlock()
            if wasOurChord { return nil }
        }

        if type == .flagsChanged, !event.flags.contains(.maskCommand) {
            lock.lock()
            let wasOurChord = qDown
            qDown = false
            generation += 1
            alreadyQuit = false
            lock.unlock()
            if wasOurChord { return nil }
        }
        return Unmanaged.passUnretained(event)
    }

    private func completeHold(generation expected: Int, pid: pid_t) {
        lock.lock()
        let shouldQuit = qDown && !alreadyQuit && generation == expected
        if shouldQuit { alreadyQuit = true }
        lock.unlock()
        guard shouldQuit, pid != 0 else { return }
        if let app = NSRunningApplication(processIdentifier: pid) { app.terminate() }
    }
}
