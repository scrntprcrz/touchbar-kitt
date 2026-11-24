import AppKit
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let coordinator = PulseCoordinator()
    private let touchBarController = GlobalTouchBarController()
    private let settings = ControlWindowController()
    private let loginItem = LoginItemManager()
    private var httpServer: LocalHTTPServer?
    private var statusItem: NSStatusItem?
    private var settingsItem: NSMenuItem?
    private var quitItem: NSMenuItem?
    private var aboutItem: NSMenuItem?
    private var diagnosticsItem: NSMenuItem?
    private var diagnosticsWindow: InformationWindowController?
    private var languageItem: NSMenuItem?
    private var languageChoices: [NSMenuItem] = []
    private var startItem: NSMenuItem?
    private var stopItem: NSMenuItem?
    private var loginItemMenu: NSMenuItem?
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        installTerminationSignals()
        configureMainMenu()
        configureMenu()
        connectControls()
        touchBarController.install()
        touchBarController.update(coordinator.snapshot)
        settings.update(coordinator.snapshot)
        if ProcessInfo.processInfo.arguments.contains("--settings") { settings.show() }

        let server = LocalHTTPServer(port: 4317) { [weak self] request in
            self?.route(request) ?? HTTPReply(code: 500, body: "{\"error\":\"not_ready\"}")
        }
        do {
            try server.start()
            httpServer = server
        } catch {
            settings.appendOutput("HTTP no disponible: \(error.localizedDescription)\n")
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        httpServer?.stop()
        coordinator.stop()
        touchBarController.uninstall()
        signalSources.removeAll()
    }

    private func connectControls() {
        coordinator.onChange = { [weak self] snapshot in
            guard let self else { return }
            self.touchBarController.update(snapshot)
            self.settings.update(snapshot)
            let stateName: String
            switch snapshot.status {
            case .idle: stateName = T.text("statusIdle")
            case .running: stateName = T.text("statusRunning")
            case .done: stateName = T.text("statusDone")
            case .error: stateName = T.text("statusError")
            case .attention: stateName = T.text("statusAttention")
            }
            self.statusItem?.button?.toolTip = "TouchBar KITT · \(stateName) · \(snapshot.activity.processCount) \(T.text("processes"))"
        }
        coordinator.onMessage = { [weak self] message in
            self?.settings.appendOutput(message)
        }
        settings.onLanguageChanged = { [weak self] in
            self?.refreshMenuLanguage()
            self?.settings.localize()
        }
        settings.onStart = { [weak self] config in
            _ = self?.coordinator.start(config)
        }
        settings.onResume = { [weak self] in
            _ = self?.coordinator.resume()
        }
        settings.onColor = { [weak self] hex in
            self?.coordinator.chooseColor(hex)
        }
        settings.onStop = { [weak self] in self?.coordinator.stop() }
        settings.onEffect = { [weak self] effect in self?.coordinator.chooseEffect(effect) }
        settings.onMetric = { [weak self] metric in self?.coordinator.chooseMetric(metric) }
        settings.onMetricLabel = { [weak self] enabled in self?.coordinator.chooseMetricLabel(enabled) }
        settings.onThreshold = { [weak self] threshold in self?.coordinator.chooseThreshold(threshold) }
        settings.onPalette = { [weak self] palette in self?.coordinator.choosePalette(palette) }
        settings.onMarqueeFields = { [weak self] showPID, showProcesses in
            self?.coordinator.chooseMarqueeFields(showPID: showPID, showProcesses: showProcesses)
        }
        settings.onLoginChanged = { [weak self] enabled in self?.updateLogin(enabled) }
        settings.isLoginEnabled = { [weak self] in self?.loginItem.isEnabled ?? false }
    }

    private func configureMainMenu() {
        // Accessory apps still need an Edit menu for standard text-field shortcuts.
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "TouchBar KITT")
        let aboutMenu = NSMenuItem(title: AppLanguage.current == .english ? "About TouchBar KITT…" : "Acerca de TouchBar KITT…", action: #selector(openAbout), keyEquivalent: "")
        aboutMenu.target = self
        appMenu.addItem(aboutMenu)
        appMenu.addItem(.separator())
        let settingsMenu = NSMenuItem(title: T.text("settings"), action: #selector(openSettings), keyEquivalent: ",")
        settingsMenu.target = self
        appMenu.addItem(settingsMenu)
        appMenu.addItem(.separator())
        let quitMenu = NSMenuItem(title: T.text("quit"), action: #selector(quit), keyEquivalent: "q")
        quitMenu.target = self
        appMenu.addItem(quitMenu)
        appItem.submenu = appMenu
        main.addItem(appItem)
        let english = AppLanguage.current == .english
        let editItem = NSMenuItem()
        let edit = NSMenu(title: english ? "Edit" : "Edición")
        edit.addItem(withTitle: english ? "Undo" : "Deshacer", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: english ? "Redo" : "Rehacer", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: english ? "Cut" : "Cortar", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: english ? "Copy" : "Copiar", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: english ? "Paste" : "Pegar", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: english ? "Select All" : "Seleccionar todo", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    private func configureMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let image = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "TouchBar KITT") {
            image.isTemplate = true
            item.button?.image = image
        } else {
            item.button?.title = "KITT"
        }
        let menu = NSMenu()
        menu.delegate = self
        settingsItem = NSMenuItem(title: T.text("settings"), action: #selector(openSettings), keyEquivalent: ",")
        startItem = NSMenuItem(title: T.text("startLast"), action: #selector(startSelected), keyEquivalent: "")
        stopItem = NSMenuItem(title: T.text("stop"), action: #selector(stopSelected), keyEquivalent: "")
        loginItemMenu = NSMenuItem(title: T.text("login"), action: #selector(toggleLogin), keyEquivalent: "")
        quitItem = NSMenuItem(title: T.text("quit"), action: #selector(quit), keyEquivalent: "q")
        languageItem = NSMenuItem(title: T.text("language"), action: nil, keyEquivalent: "")
        aboutItem = NSMenuItem(title: AppLanguage.current == .english ? "About TouchBar KITT…" : "Acerca de TouchBar KITT…", action: #selector(openAbout), keyEquivalent: "")
        diagnosticsItem = NSMenuItem(title: AppLanguage.current == .english ? "Data Sources and Diagnostics…" : "Fuentes de datos y diagnóstico…", action: #selector(openDiagnostics), keyEquivalent: "")
        let languages = NSMenu(title: T.text("language"))
        languageChoices = AppLanguage.allCases.map { language in
            let choice = NSMenuItem(title: language == .spanish ? "Español" : "English", action: #selector(changeLanguage(_:)), keyEquivalent: "")
            choice.representedObject = language.rawValue
            choice.target = self
            languages.addItem(choice)
            return choice
        }
        languageItem?.submenu = languages
        for menuItem in [settingsItem, startItem, stopItem, loginItemMenu, quitItem, aboutItem, diagnosticsItem] {
            menuItem?.target = self
        }
        if let settingsItem { menu.addItem(settingsItem) }
        menu.addItem(.separator())
        if let startItem { menu.addItem(startItem) }
        if let stopItem { menu.addItem(stopItem) }
        menu.addItem(.separator())
        if let loginItemMenu { menu.addItem(loginItemMenu) }
        if let languageItem { menu.addItem(languageItem) }
        menu.addItem(.separator())
        if let diagnosticsItem { menu.addItem(diagnosticsItem) }
        if let aboutItem { menu.addItem(aboutItem) }
        menu.addItem(.separator())
        if let quitItem { menu.addItem(quitItem) }
        item.menu = menu
        statusItem = item
        refreshMenuLanguage()
    }

    private func refreshMenuLanguage() {
        configureMainMenu()
        settingsItem?.title = T.text("settings")
        startItem?.title = T.text("startLast")
        stopItem?.title = T.text("stop")
        loginItemMenu?.title = T.text("login")
        languageItem?.title = T.text("language")
        quitItem?.title = T.text("quit")
        aboutItem?.title = AppLanguage.current == .english ? "About TouchBar KITT…" : "Acerca de TouchBar KITT…"
        diagnosticsItem?.title = AppLanguage.current == .english ? "Data Sources and Diagnostics…" : "Fuentes de datos y diagnóstico…"
        for choice in languageChoices {
            choice.state = choice.representedObject as? String == AppLanguage.current.rawValue ? .on : .off
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        startItem?.isEnabled = !coordinator.snapshot.watchedProcesses.isEmpty
        stopItem?.isEnabled = coordinator.snapshot.status == .running
        loginItemMenu?.state = loginItem.isEnabled ? .on : .off
        refreshMenuLanguage()
    }

    @objc private func changeLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let language = AppLanguage(rawValue: raw) else { return }
        AppLanguage.select(language)
        refreshMenuLanguage()
        settings.localize()
    }

    private func updateLogin(_ enabled: Bool) {
        do {
            try loginItem.setEnabled(enabled)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = T.text("loginError")
            alert.informativeText = "\(error.localizedDescription)\n\(T.text("loginHint"))"
            alert.runModal()
        }
        settings.refreshLoginState()
    }

    private func route(_ request: HTTPRequestLine) -> HTTPReply {
        let params = request.parameters
        switch request.path {
        case "/display":
            let data = try? JSONSerialization.data(withJSONObject: touchBarController.renderingDiagnostics, options: [.sortedKeys])
            return HTTPReply(code: 200, body: data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}")
        case "/state":
            break
        case "/watch":
            guard let value = params["pid"], let pid = Int32(value) else {
                return HTTPReply(code: 400, body: "{\"error\":\"invalid_pid\"}")
            }
            let config = WatchConfiguration(
                pid: pid,
                includeChildren: params["children"] != "0",
                includeAppHelpers: params["helpers"] != "0",
                effect: PulseEffect(rawValue: params["effect"] ?? "") ?? coordinator.snapshot.effect,
                metric: ProcessMetric(rawValue: params["metric"] ?? "") ?? coordinator.snapshot.metric,
                processName: params["name"] ?? "PID \(pid)",
                showMetricLabel: (params["label"] ?? params["initials"]).map { $0 == "1" } ?? coordinator.snapshot.showMetricLabel,
                palette: DisplayPalette(rawValue: params["palette"] ?? "") ?? coordinator.snapshot.palette,
                customColorHex: coordinator.snapshot.customColorHex,
                marqueeShowsPID: params["showPID"].map { $0 == "1" } ?? coordinator.snapshot.marqueeShowsPID,
                marqueeShowsProcesses: params["showProcesses"].map { $0 == "1" } ?? coordinator.snapshot.marqueeShowsProcesses,
                threshold: SignalThreshold.saved(for: ProcessMetric(rawValue: params["metric"] ?? "") ?? coordinator.snapshot.metric)
            )
            if !coordinator.start(config) {
                return HTTPReply(code: 400, body: "{\"error\":\"pid_unavailable\"}")
            }
        case "/add":
            guard let value = params["pid"], let pid = Int32(value) else {
                return HTTPReply(code: 400, body: "{\"error\":\"invalid_pid\"}")
            }
            let config = WatchConfiguration(
                pid: pid,
                includeChildren: params["children"] != "0",
                includeAppHelpers: params["helpers"] != "0",
                effect: coordinator.snapshot.effect,
                metric: coordinator.snapshot.metric,
                processName: params["name"] ?? "PID \(pid)",
                showMetricLabel: coordinator.snapshot.showMetricLabel,
                palette: coordinator.snapshot.palette,
                customColorHex: coordinator.snapshot.customColorHex,
                marqueeShowsPID: coordinator.snapshot.marqueeShowsPID,
                marqueeShowsProcesses: coordinator.snapshot.marqueeShowsProcesses,
                threshold: coordinator.snapshot.threshold
            )
            guard coordinator.start(config) else { return HTTPReply(code: 400, body: "{\"error\":\"pid_unavailable\"}") }
        case "/remove":
            guard let value = params["pid"], let pid = Int32(value) else {
                return HTTPReply(code: 400, body: "{\"error\":\"invalid_pid\"}")
            }
            coordinator.remove(pid: pid)
        case "/color":
            guard let hex = params["hex"], hex.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil else {
                return HTTPReply(code: 400, body: "{\"error\":\"invalid_color\"}")
            }
            coordinator.chooseColor(hex)
        case "/resume":
            _ = coordinator.resume()
        case "/threshold":
            let metric = coordinator.snapshot.metric
            let previous = SignalThreshold.saved(for: metric)
            let enabled = params["enabled"].map { $0 == "1" } ?? previous.enabled
            let minimum = Double(params["minimum"] ?? "") ?? previous.minimum
            let maximum = Double(params["maximum"] ?? "") ?? previous.maximum
            guard minimum.isFinite, maximum.isFinite, minimum >= 0, maximum > minimum else {
                return HTTPReply(code: 400, body: "{\"error\":\"invalid_threshold\"}")
            }
            coordinator.chooseThreshold(SignalThreshold(enabled: enabled, minimum: minimum, maximum: maximum))
        case "/label", "/initials":
            coordinator.chooseMetricLabel(params["enabled"] == "1")
        case "/palette":
            guard let palette = DisplayPalette(rawValue: params["name"] ?? "") else {
                return HTTPReply(code: 400, body: "{\"error\":\"invalid_palette\"}")
            }
            coordinator.choosePalette(palette)
        case "/marquee":
            coordinator.chooseMarqueeFields(
                showPID: params["pid"].map { $0 == "1" } ?? coordinator.snapshot.marqueeShowsPID,
                showProcesses: params["processes"].map { $0 == "1" } ?? coordinator.snapshot.marqueeShowsProcesses
            )
        case "/stop", "/halt":
            coordinator.stop()
        case "/reset":
            coordinator.reset()
        case "/effect":
            guard let effect = PulseEffect(rawValue: params["name"] ?? "") else {
                return HTTPReply(code: 400, body: "{\"error\":\"invalid_effect\"}")
            }
            coordinator.chooseEffect(effect)
        case "/metric":
            guard let metric = ProcessMetric(rawValue: params["name"] ?? "") else {
                return HTTPReply(code: 400, body: "{\"error\":\"invalid_metric\"}")
            }
            coordinator.chooseMetric(metric)
        default:
            return HTTPReply(code: 404, body: "{\"error\":\"not_found\"}")
        }
        let data = try? JSONEncoder().encode(coordinator.snapshot)
        return HTTPReply(code: 200, body: data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}")
    }

    private func installTerminationSignals() {
        for number in [SIGTERM, SIGINT] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
    }

    @objc private func openSettings() { settings.show() }
    @objc private func openAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let configuration = NSImage.SymbolConfiguration(pointSize: 64, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.systemBlue]))
        let icon = NSImage(systemSymbolName: "waveform.path.ecg.rectangle.fill", accessibilityDescription: "TouchBar KITT")?
            .withSymbolConfiguration(configuration)
        icon?.size = NSSize(width: 96, height: 96)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "TouchBar KITT",
            .applicationIcon: icon ?? NSApp.applicationIconImage!
        ])
    }
    @objc private func openDiagnostics() {
        if diagnosticsWindow == nil { diagnosticsWindow = InformationWindowController(page: .diagnostics) }
        diagnosticsWindow?.show(snapshot: coordinator.snapshot, displayWidth: touchBarController.displayWidth)
    }
    @objc private func startSelected() { settings.startSelected() }
    @objc private func stopSelected() { coordinator.stop() }
    @objc private func toggleLogin() { updateLogin(!loginItem.isEnabled) }
    @objc private func quit() { NSApp.terminate(nil) }
}
