import Foundation

final class PulseCoordinator {
    private(set) var snapshot = PulseSnapshot()
    var onChange: ((PulseSnapshot) -> Void)?
    var onMessage: ((String) -> Void)?

    private let monitor = ProcessTreeMonitor()

    init() {
        let defaults = UserDefaults.standard
        snapshot.metric = ProcessMetric(rawValue: defaults.string(forKey: "monitor.metric") ?? "cpu") ?? .cpu
        snapshot.effect = PulseEffect(rawValue: defaults.string(forKey: "monitor.effect") ?? "vu") ?? .vu
        if snapshot.effect.requiresDirectionalMetric && snapshot.metric != .disk && snapshot.metric != .network { snapshot.effect = .vu }
        snapshot.showMetricLabel = defaults.object(forKey: "monitor.showMetricLabel") as? Bool
            ?? defaults.bool(forKey: "monitor.showInitials")
        snapshot.palette = DisplayPalette(rawValue: defaults.string(forKey: "monitor.palette") ?? "original") ?? .original
        snapshot.customColorHex = defaults.string(forKey: "monitor.customColorHex") ?? "#FF3535"
        snapshot.marqueeShowsPID = defaults.object(forKey: "monitor.marqueeShowsPID") as? Bool ?? true
        snapshot.marqueeShowsProcesses = defaults.object(forKey: "monitor.marqueeShowsProcesses") as? Bool ?? true
        snapshot.threshold = SignalThreshold.saved(for: snapshot.metric)
        monitor.onNetworkIssue = { [weak self] issue in
            self?.onMessage?(AppLanguage.current == .english ? "Network: \(issue). No nettop is launched." : "Red: \(issue). No se ejecuta nettop.")
        }
        monitor.onObservation = { [weak self] observation in
            guard let self, self.snapshot.status == .running else { return }
            if !observation.isAlive {
                self.snapshot.status = .done
                self.snapshot.activity = .zero
                self.snapshot.label = AppLanguage.current == .english ? "Monitored processes finished" : "Procesos vigilados finalizados"
                self.onMessage?(AppLanguage.current == .english ? "All monitored process families ended. Exit codes unknown." : "Todas las familias vigiladas terminaron. Se desconocen los códigos de salida.")
            } else {
                self.snapshot.activity = observation.sample
            }
            self.publish()
        }
    }

    @discardableResult
    func start(_ config: WatchConfiguration) -> Bool {
        guard config.pid > 0, monitor.isAccessible(pid: config.pid) else {
            onMessage?(AppLanguage.current == .english ? "PID unavailable or inaccessible" : "PID inexistente o inaccesible")
            return false
        }
        snapshot.watchedProcesses = []
        return add(config)
    }

    @discardableResult
    func add(_ config: WatchConfiguration) -> Bool {
        guard config.pid > 0, monitor.isAccessible(pid: config.pid) else {
            onMessage?(AppLanguage.current == .english ? "PID unavailable or inaccessible" : "PID inexistente o inaccesible")
            return false
        }
        let target = WatchedProcess(
            pid: config.pid,
            name: String(config.processName.prefix(80)),
            includeChildren: config.includeChildren,
            includeAppHelpers: config.includeAppHelpers
        )
        snapshot.watchedProcesses.removeAll { $0.pid == target.pid }
        snapshot.watchedProcesses.append(target)
        snapshot.effect = config.effect.requiresDirectionalMetric && config.metric != .disk && config.metric != .network ? .vu : config.effect
        snapshot.metric = config.metric
        snapshot.threshold = config.threshold
        snapshot.showMetricLabel = config.showMetricLabel
        snapshot.palette = config.palette
        snapshot.customColorHex = config.customColorHex
        snapshot.marqueeShowsPID = config.marqueeShowsPID
        snapshot.marqueeShowsProcesses = config.marqueeShowsProcesses
        persistDisplaySettings()
        let success = resume()
        if !success {
            snapshot.watchedProcesses.removeAll { $0.pid == target.pid }
            publish()
        }
        return success
    }

    func remove(pid: Int32) {
        snapshot.watchedProcesses.removeAll { $0.pid == pid }
        if snapshot.watchedProcesses.isEmpty { stop() }
        else { _ = resume() }
    }

    @discardableResult
    func resume() -> Bool {
        guard !snapshot.watchedProcesses.isEmpty else { return false }
        monitor.stop()
        guard monitor.start(targets: snapshot.watchedProcesses, metric: snapshot.metric) else {
            snapshot.status = .error
            snapshot.activity = .zero
            snapshot.label = AppLanguage.current == .english ? "No accessible processes" : "No hay procesos accesibles"
            publish()
            return false
        }
        snapshot.status = .running
        snapshot.pid = snapshot.watchedProcesses.first?.pid
        snapshot.processName = String(snapshot.watchedProcesses.map(\.name).joined(separator: " + ").prefix(120))
        snapshot.label = "\(snapshot.watchedProcesses.count) \(T.text("processes"))"
        snapshot.activity = .zero
        publish()
        return true
    }

    func stop() {
        monitor.stop()
        snapshot.status = .idle
        snapshot.activity = .zero
        snapshot.label = T.text("statusIdle")
        publish()
    }

    func reset() {
        monitor.stop()
        snapshot.watchedProcesses.removeAll()
        snapshot.status = .idle
        snapshot.pid = nil
        snapshot.label = ""
        snapshot.processName = ""
        snapshot.activity = .zero
        publish()
    }

    func chooseEffect(_ effect: PulseEffect) {
        snapshot.effect = effect.requiresDirectionalMetric && snapshot.metric != .disk && snapshot.metric != .network ? .vu : effect
        persistDisplaySettings()
        publish()
    }

    func chooseMetric(_ metric: ProcessMetric) {
        monitor.configureMetric(metric)
        snapshot.metric = metric
        snapshot.threshold = SignalThreshold.saved(for: metric)
        if snapshot.effect.requiresDirectionalMetric && metric != .disk && metric != .network {
            snapshot.effect = .vu
        }
        persistDisplaySettings()
        publish()
    }

    func chooseThreshold(_ threshold: SignalThreshold) {
        snapshot.threshold = threshold
        threshold.save(for: snapshot.metric)
        publish()
    }

    func chooseMetricLabel(_ enabled: Bool) {
        snapshot.showMetricLabel = enabled
        UserDefaults.standard.set(enabled, forKey: "monitor.showMetricLabel")
        publish()
    }

    func choosePalette(_ palette: DisplayPalette) {
        snapshot.palette = palette
        UserDefaults.standard.set(palette.rawValue, forKey: "monitor.palette")
        publish()
    }

    func chooseColor(_ hex: String) {
        snapshot.customColorHex = hex
        snapshot.palette = .custom
        UserDefaults.standard.set(hex, forKey: "monitor.customColorHex")
        UserDefaults.standard.set(DisplayPalette.custom.rawValue, forKey: "monitor.palette")
        publish()
    }

    func chooseMarqueeFields(showPID: Bool, showProcesses: Bool) {
        snapshot.marqueeShowsPID = showPID
        snapshot.marqueeShowsProcesses = showProcesses
        UserDefaults.standard.set(showPID, forKey: "monitor.marqueeShowsPID")
        UserDefaults.standard.set(showProcesses, forKey: "monitor.marqueeShowsProcesses")
        publish()
    }

    private func persistDisplaySettings() {
        let defaults = UserDefaults.standard
        defaults.set(snapshot.metric.rawValue, forKey: "monitor.metric")
        defaults.set(snapshot.effect.rawValue, forKey: "monitor.effect")
        defaults.set(snapshot.showMetricLabel, forKey: "monitor.showMetricLabel")
        defaults.set(snapshot.palette.rawValue, forKey: "monitor.palette")
        defaults.set(snapshot.customColorHex, forKey: "monitor.customColorHex")
        defaults.set(snapshot.marqueeShowsPID, forKey: "monitor.marqueeShowsPID")
        defaults.set(snapshot.marqueeShowsProcesses, forKey: "monitor.marqueeShowsProcesses")
    }

    private func publish() {
        snapshot.updatedAt = Date()
        onChange?(snapshot)
    }
}
