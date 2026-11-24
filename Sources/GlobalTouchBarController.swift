import AppKit

private extension NSTouchBarItem.Identifier {
    static let kittStrip = NSTouchBarItem.Identifier("dev.touchbarkitt.studio.strip")
    static let kittDisplay = NSTouchBarItem.Identifier("dev.touchbarkitt.studio.display")
}

final class GlobalTouchBarController: NSObject, NSTouchBarDelegate {
    private let stripItem = NSCustomTouchBarItem(identifier: .kittStrip)
    private let displayItem = NSCustomTouchBarItem(identifier: .kittDisplay)
    private let display = PulseBarView(frame: NSRect(x: 0, y: 0, width: 1085, height: 30))
    private let stripButton = NSButton(title: "KITT", target: nil, action: nil)
    private var modalBar: NSTouchBar?
    private var keepAliveTimer: Timer?
    private var pendingPresentation: DispatchWorkItem?
    private var installed = false
    var displayWidth: CGFloat { display.renderingRect.width }
    var renderingDiagnostics: [String: Double] {
        ["drawingWidth": Double(display.renderingRect.width), "animationRunning": display.animationIsRunning ? 1 : 0, "boundsWidth": Double(display.bounds.width), "frameWidth": Double(display.frame.width),
         "visibleX": Double(display.visibleRect.minX), "visibleWidth": Double(display.visibleRect.width),
         "windowWidth": Double(display.window?.contentView?.bounds.width ?? 0),
         "windowAttached": display.window == nil ? 0 : 1,
         "superviewWidth": Double(display.superview?.bounds.width ?? 0)]
    }

    func install() {
        guard !installed else { return }
        installed = true
        stripButton.target = self
        stripButton.action = #selector(presentNow)
        stripButton.frame = NSRect(x: 0, y: 0, width: 72, height: 30)
        stripButton.bezelStyle = .rounded
        stripItem.view = stripButton
        display.runsWithoutWindow = true
        display.setContentHuggingPriority(.defaultLow, for: .horizontal)
        display.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        display.translatesAutoresizingMaskIntoConstraints = false
        display.widthAnchor.constraint(lessThanOrEqualToConstant: 1085).isActive = true
        display.heightAnchor.constraint(equalToConstant: 30).isActive = true
        displayItem.view = display

        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [.kittDisplay]
        bar.principalItemIdentifier = .kittDisplay
        modalBar = bar

        DFRSystemModalShowsCloseBoxWhenFrontMost(false)
        NSTouchBarItem.addSystemTrayItem(stripItem)
        assertStripPresence()

        let workspace = NSWorkspace.shared.notificationCenter
        for name: NSNotification.Name in [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
            NSWorkspace.didActivateApplicationNotification
        ] {
            workspace.addObserver(self, selector: #selector(schedulePresentation), name: name, object: nil)
        }

        let timer = Timer(timeInterval: 6, repeats: true) { [weak self] _ in
            self?.assertStripPresence()
            self?.presentNow()
        }
        RunLoop.main.add(timer, forMode: .common)
        keepAliveTimer = timer
        schedulePresentation()
    }

    func update(_ snapshot: PulseSnapshot) {
        display.update(snapshot)
        switch snapshot.status {
        case .idle: stripButton.title = "KITT"
        case .running: stripButton.title = "KITT ●"
        case .done: stripButton.title = "KITT ✓"
        case .error: stripButton.title = "KITT !"
        case .attention: stripButton.title = "KITT ?"
        }
    }

    func uninstall() {
        guard installed else { return }
        installed = false
        pendingPresentation?.cancel()
        pendingPresentation = nil
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        display.stopAnimation()
        if let bar = modalBar {
            NSTouchBar.dismissSystemModalTouchBar(bar)
            modalBar = nil
        }
        DFRElementSetControlStripPresenceForIdentifier(.kittStrip, false)
        NSTouchBarItem.removeSystemTrayItem(stripItem)
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        identifier == .kittDisplay ? displayItem : nil
    }

    @objc private func schedulePresentation() {
        guard installed else { return }
        pendingPresentation?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.assertStripPresence()
            self?.presentNow()
        }
        pendingPresentation = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: task)
    }

    @objc private func presentNow() {
        guard installed, let bar = modalBar else { return }
        NSTouchBar.presentSystemModalTouchBar(
            bar,
            placement: 1,
            systemTrayItemIdentifier: .kittStrip
        )
        display.needsDisplay = true
        display.displayIfNeeded()
    }

    private func assertStripPresence() {
        guard installed else { return }
        DFRElementSetControlStripPresenceForIdentifier(.kittStrip, true)
    }
}
