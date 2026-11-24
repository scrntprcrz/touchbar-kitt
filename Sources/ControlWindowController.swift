import AppKit
import SwiftUI

struct RunningApplicationChoice: Identifiable, Hashable {
    let pid: Int32
    let name: String
    var id: Int32 { pid }
}

enum TargetSource: String, CaseIterable {
    case application, manualPID
}

final class SettingsModel: ObservableObject {
    @Published var language = AppLanguage.current
    @Published var snapshot = PulseSnapshot()
    @Published var applications: [RunningApplicationChoice] = []
    @Published var selectedAppPID: Int32 = 0
    @Published var targetSource: TargetSource = .application
    @Published var manualTarget: RunningApplicationChoice?
    @Published var manualPID = UserDefaults.standard.string(forKey: "monitor.manualPID") ?? ""
    @Published var includeChildren = UserDefaults.standard.object(forKey: "monitor.children") as? Bool ?? true
    @Published var includeHelpers = UserDefaults.standard.object(forKey: "monitor.helpers") as? Bool ?? true
    @Published var metric = ProcessMetric(rawValue: UserDefaults.standard.string(forKey: "monitor.metric") ?? "cpu") ?? .cpu
    @Published var effect = PulseEffect(rawValue: UserDefaults.standard.string(forKey: "monitor.effect") ?? "vu") ?? .vu
    @Published var palette = DisplayPalette(rawValue: UserDefaults.standard.string(forKey: "monitor.palette") ?? "original") ?? .original
    @Published var selectedColor: Color = Color(red: 1, green: 0.2, blue: 0.2)
    @Published var showMetricLabel = UserDefaults.standard.object(forKey: "monitor.showMetricLabel") as? Bool
        ?? UserDefaults.standard.bool(forKey: "monitor.showInitials")
    @Published var marqueeShowsPID = UserDefaults.standard.object(forKey: "monitor.marqueeShowsPID") as? Bool ?? true
    @Published var marqueeShowsProcesses = UserDefaults.standard.object(forKey: "monitor.marqueeShowsProcesses") as? Bool ?? true
    @Published var thresholdEnabled = false
    @Published var minimumText = "0"
    @Published var maximumText = "100"
    @Published var previewLive = true
    @Published var demoLoad = 0.55
    @Published var previewTick = 0.0
    @Published var loginEnabled = false
    @Published var message = ""

    var onWatch: ((WatchConfiguration) -> Void)?
    var onResume: (() -> Void)?
    var onStop: (() -> Void)?
    var onMetric: ((ProcessMetric) -> Void)?
    var onEffect: ((PulseEffect) -> Void)?
    var onMetricLabel: ((Bool) -> Void)?
    var onPalette: ((DisplayPalette) -> Void)?
    var onColor: ((String) -> Void)?
    var onMarqueeFields: ((Bool, Bool) -> Void)?
    var onThreshold: ((SignalThreshold) -> Void)?
    var onLanguageChanged: (() -> Void)?
    var onLoginChanged: ((Bool) -> Void)?

    init() {
        let hex = UserDefaults.standard.string(forKey: "monitor.customColorHex") ?? "#FF3535"
        selectedColor = Self.color(from: hex)
        loadThreshold()
        refreshApplications()
    }

    func refreshApplications() {
        applications = NSWorkspace.shared.runningApplications
            .filter { !$0.isTerminated && $0.activationPolicy == .regular && $0.processIdentifier > 0 }
            .map { RunningApplicationChoice(pid: $0.processIdentifier, name: $0.localizedName ?? "App") }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if !applications.contains(where: { $0.pid == selectedAppPID }) { selectedAppPID = 0 }
    }

    func addApp() {
        guard let choice = applications.first(where: { $0.pid == selectedAppPID }) else { return }
        submit(pid: choice.pid, name: choice.name)
    }

    func addManual() {
        guard refreshManualProcess(), let target = manualTarget else { return }
        UserDefaults.standard.set(manualPID, forKey: "monitor.manualPID")
        submit(pid: target.pid, name: target.name)
    }

    var validManualPID: Int32? {
        guard let pid = Int32(manualPID.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0 else { return nil }
        return pid
    }

    @discardableResult
    func refreshManualProcess() -> Bool {
        manualTarget = nil
        guard let pid = validManualPID else {
            message = T.text("invalidPID")
            return false
        }
        var identity = KITTProcessIdentity()
        guard KITTReadProcessIdentity(pid, &identity) != 0 else {
            message = language == .spanish ? "No se encuentra el PID o no es accesible." : "PID not found or inaccessible."
            return false
        }
        manualTarget = RunningApplicationChoice(pid: pid, name: NSRunningApplication(processIdentifier: pid)?.localizedName ?? processName(for: pid))
        message = ""
        return true
    }

    func watchSelectedTarget() {
        if targetSource == .application { addApp() } else { addManual() }
    }

    // Commit user edits synchronously. Incoming samples only read these values;
    // they must not race a deferred SwiftUI onChange or write preferences back.
    func editing<Value>(_ keyPath: ReferenceWritableKeyPath<SettingsModel, Value>, commit: @escaping (SettingsModel) -> Void) -> Binding<Value> {
        Binding(get: { self[keyPath: keyPath] }, set: { value in
            self[keyPath: keyPath] = value
            commit(self)
        })
    }

    var metricLabelBinding: Binding<Bool> { editing(\.showMetricLabel) { $0.changeMetricLabel() } }
    var metricBinding: Binding<ProcessMetric> { editing(\.metric) { $0.changeMetric() } }
    var effectBinding: Binding<PulseEffect> { editing(\.effect) { $0.changeEffect() } }
    var paletteBinding: Binding<DisplayPalette> { editing(\.palette) { $0.changePalette() } }
    var colorBinding: Binding<Color> { editing(\.selectedColor) { $0.changeColor() } }

    func receive(_ value: PulseSnapshot) {
        let metricChanged = metric != value.metric
        snapshot = value
        metric = value.metric
        effect = value.effect
        palette = value.palette
        showMetricLabel = value.showMetricLabel
        marqueeShowsPID = value.marqueeShowsPID
        marqueeShowsProcesses = value.marqueeShowsProcesses
        if colorHex != value.customColorHex { selectedColor = Self.color(from: value.customColorHex) }
        if metricChanged { loadThreshold() }
    }

    private func processName(for pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = buffer.withUnsafeMutableBufferPointer { pointer in
            KITTReadProcessPath(pid, pointer.baseAddress, Int32(pointer.count))
        }
        guard length > 0 else { return "PID \(pid)" }
        return URL(fileURLWithPath: String(cString: buffer)).lastPathComponent
    }

    private func submit(pid: Int32, name: String) {
        UserDefaults.standard.set(includeChildren, forKey: "monitor.children")
        UserDefaults.standard.set(includeHelpers, forKey: "monitor.helpers")
        let config = WatchConfiguration(
            pid: pid,
            includeChildren: includeChildren,
            includeAppHelpers: includeHelpers,
            effect: effect,
            metric: metric,
            processName: name,
            showMetricLabel: showMetricLabel,
            palette: palette,
            customColorHex: colorHex,
            marqueeShowsPID: marqueeShowsPID,
            marqueeShowsProcesses: marqueeShowsProcesses,
            threshold: validThreshold ?? SignalThreshold.saved(for: metric)
        )
        message = ""
        onWatch?(config)
    }

    func changeMetric() {
        UserDefaults.standard.set(metric.rawValue, forKey: "monitor.metric")
        if effect.requiresDirectionalMetric && metric != .disk && metric != .network { effect = .vu }
        loadThreshold()
        onMetric?(metric)
    }

    func changeEffect() {
        UserDefaults.standard.set(effect.rawValue, forKey: "monitor.effect")
        onEffect?(effect)
    }

    func changePalette() {
        UserDefaults.standard.set(palette.rawValue, forKey: "monitor.palette")
        onPalette?(palette)
    }

    func changeColor() {
        palette = .custom
        UserDefaults.standard.set(palette.rawValue, forKey: "monitor.palette")
        onColor?(colorHex)
    }

    func restoreColor() {
        palette = .original
        UserDefaults.standard.set(palette.rawValue, forKey: "monitor.palette")
        onPalette?(.original)
    }

    func changeMetricLabel() {
        UserDefaults.standard.set(showMetricLabel, forKey: "monitor.showMetricLabel")
        onMetricLabel?(showMetricLabel)
    }

    func changeMarquee() {
        UserDefaults.standard.set(marqueeShowsPID, forKey: "monitor.marqueeShowsPID")
        UserDefaults.standard.set(marqueeShowsProcesses, forKey: "monitor.marqueeShowsProcesses")
        onMarqueeFields?(marqueeShowsPID, marqueeShowsProcesses)
    }

    var validThreshold: SignalThreshold? {
        if !thresholdEnabled {
            return SignalThreshold(enabled: false, minimum: 0, maximum: metric.referenceMaximum)
        }
        let decimalMin = Double(minimumText.replacingOccurrences(of: ",", with: "."))
        let decimalMax = Double(maximumText.replacingOccurrences(of: ",", with: "."))
        guard let minimum = decimalMin, let maximum = decimalMax,
              minimum.isFinite, maximum.isFinite, minimum >= 0, maximum > minimum else { return nil }
        return SignalThreshold(enabled: true, minimum: minimum, maximum: maximum)
    }

    func loadThreshold() {
        let saved = SignalThreshold.saved(for: metric)
        thresholdEnabled = saved.enabled
        minimumText = String(format: "%.2f", saved.minimum)
        maximumText = String(format: "%.2f", saved.maximum)
    }

    func saveThreshold() {
        guard let validThreshold else { return }
        validThreshold.save(for: metric)
        onThreshold?(validThreshold)
    }

    func restoreThreshold() {
        let fresh = SignalThreshold(enabled: false, minimum: 0, maximum: metric.referenceMaximum)
        fresh.save(for: metric)
        loadThreshold()
        onThreshold?(fresh)
    }

    var colorHex: String {
        guard let rgb = NSColor(selectedColor).usingColorSpace(.deviceRGB) else { return "#FF3535" }
        let r = Int((min(1, max(0, rgb.redComponent)) * 255).rounded())
        let g = Int((min(1, max(0, rgb.greenComponent)) * 255).rounded())
        let b = Int((min(1, max(0, rgb.blueComponent)) * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    static func color(from hex: String) -> Color {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return .red }
        return Color(
            red: Double((value >> 16) & 255) / 255,
            green: Double((value >> 8) & 255) / 255,
            blue: Double(value & 255) / 255
        )
    }

    var previewSnapshot: PulseSnapshot {
        if previewLive { return snapshot }
        let threshold = validThreshold ?? SignalThreshold.saved(for: metric)
        let low = threshold.enabled ? threshold.minimum : 0
        let high = threshold.enabled ? threshold.maximum : metric.referenceMaximum
        let intensity = min(1, max(0, demoLoad * (0.92 + 0.08 * sin(previewTick * 2))))
        let raw = low + (high - low) * intensity
        var sample = ActivitySample()
        sample.processCount = max(1, snapshot.activity.processCount)
        sample.networkAvailable = true
        sample.gpuAvailable = true
        sample.energyReadableCount = 1
        switch metric {
        case .cpu: sample.cpuPercent = raw
        case .memory: sample.residentBytes = 500 * 1_048_576; sample.memoryDeltaBps = raw * 1_048_576
        case .disk: sample.diskReadBps = raw * 1_048_576 * 0.7; sample.diskWriteBps = raw * 1_048_576 * 0.3
        case .network: sample.networkReceivedBps = raw * 1_048_576 * 0.75; sample.networkSentBps = raw * 1_048_576 * 0.25
        case .gpu: sample.gpuPercent = raw
        case .energy: sample.energyWatts = raw
        case .threads: sample.threadCount = UInt64(raw)
        case .switches: sample.contextSwitchesPerSecond = raw
        }
        var preview = snapshot
        preview.status = .running
        preview.pid = snapshot.pid ?? 4317
        preview.processName = snapshot.processName.isEmpty ? "TouchBar KITT" : snapshot.processName
        preview.metric = metric
        preview.effect = effect
        preview.palette = palette
        preview.customColorHex = colorHex
        preview.activity = sample
        preview.threshold = threshold
        preview.showMetricLabel = showMetricLabel
        preview.marqueeShowsPID = marqueeShowsPID
        preview.marqueeShowsProcesses = marqueeShowsProcesses
        preview.updatedAt = Date(timeIntervalSince1970: previewTick)
        return preview
    }
}

struct NativeTouchBarPreview: NSViewRepresentable {
    let snapshot: PulseSnapshot

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        container.layer?.cornerRadius = 9
        container.layer?.masksToBounds = true
        let display = PulseBarView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        display.translatesAutoresizingMaskIntoConstraints = false
        display.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        container.addSubview(display)
        NSLayoutConstraint.activate([
            display.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            display.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            display.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            display.heightAnchor.constraint(equalToConstant: 30)
        ])
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView.subviews.first as? PulseBarView)?.update(snapshot)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        (nsView.subviews.first as? PulseBarView)?.stopAnimation()
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case monitor, appearance, general
    var id: String { rawValue }
    var title: String {
        let english = AppLanguage.current == .english
        switch self {
        case .monitor: return english ? "Monitor" : "Monitoreo"
        case .appearance: return english ? "Appearance" : "Apariencia"
        case .general: return english ? "General" : "General"
        }
    }
    var symbol: String {
        switch self {
        case .monitor: return "chart.xyaxis.line"
        case .appearance: return "paintpalette"
        case .general: return "gearshape"
        }
    }
}

extension PulseEffect {
    var symbol: String {
        switch self {
        case .kitt, .twin: return "arrow.left.and.right"
        case .disk: return "lightbulb"
        case .heartbeat: return "waveform.path.ecg"
        case .vu, .centerVU: return "chart.bar.fill"
        case .peak: return "chart.bar.xaxis"
        case .scope, .wave: return "waveform.path"
        case .waterfall: return "square.stack.3d.down.right"
        case .duplex: return "arrow.up.arrow.down"
        case .marquee: return "textformat.abc"
        case .comet: return "sparkle"
        case .equalizer: return "slider.vertical.3"
        case .sparkline: return "chart.xyaxis.line"
        case .digital: return "number"
        case .signal: return "bolt.horizontal"
        case .radar: return "dot.radiowaves.left.and.right"
        case .particles: return "sparkles"
        case .breathe: return "sun.max"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @State var section: SettingsSection? = .monitor
    @State var galleryExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func translated(_ spanish: String, _ english: String) -> String {
        model.language == .spanish ? spanish : english
    }
    private var activeProcess: WatchedProcess? { model.snapshot.watchedProcesses.first }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.path.ecg.rectangle.fill")
                        .font(.system(size: 28)).foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("TouchBar KITT").font(.headline)
                    }
                    Spacer(minLength: 0)
                }
                .padding(18)
                List(SettingsSection.allCases, selection: $section) { item in
                    Label(item.title, systemImage: item.symbol)
                        .padding(.vertical, 5)
                        .tag(item)
                }
                .listStyle(.sidebar)
                Spacer(minLength: 0)
                sidebarReadings

            }
            .frame(minWidth: 175, idealWidth: 190, maxWidth: 235)
            .background(.regularMaterial)

            VStack(spacing: 0) {
                header
                Group {
                    switch section ?? .monitor {
                    case .monitor: monitoringTab
                    case .appearance: appearanceTab
                    case .general: generalTab
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                preview
                footer
            }
            .frame(minWidth: 575)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 780, minHeight: 620)

    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text((section ?? .monitor).title).font(.title2.weight(.bold))
            }
            Spacer(minLength: 12)
            Label(model.snapshot.status == .running ? translated("En vivo", "Live") : translated("En pausa", "Paused"),
                  systemImage: model.snapshot.status == .running ? "circle.fill" : "pause.circle")
                .font(.caption.weight(.medium))
                .foregroundStyle(model.snapshot.status == .running ? Color.green : Color.secondary)
        }
        .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 4)
    }

    private var preview: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Touch Bar").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Picker(translated("Vista previa", "Preview"), selection: $model.previewLive) {
                    Text(translated("Simulación", "Demo")).tag(false)
                    Text(translated("En vivo", "Live")).tag(true)
                }
                .labelsHidden().pickerStyle(.segmented).frame(width: 174)
            }
            NativeTouchBarPreview(snapshot: model.previewSnapshot)
                .frame(height: 34)
                .accessibilityLabel(translated("Vista previa de Touch Bar", "Touch Bar preview"))
            if !model.previewLive {
                HStack(spacing: 10) {
                    Text(translated("Carga de prueba", "Test load")).font(.caption).foregroundStyle(.secondary)
                    Slider(value: $model.demoLoad, in: 0...1)
                        .accessibilityLabel(translated("Carga simulada", "Simulated load"))
                    Text("\(Int(model.demoLoad * 100))%")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 32, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 20).padding(.top, 10)
    }

    private var footer: some View {
        HStack {
            Text(model.effect.localizedName).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button { model.snapshot.status == .running ? model.onStop?() : model.onResume?() } label: {
                Label(model.snapshot.status == .running ? translated("Pausar", "Pause") : translated("Reanudar", "Resume"),
                      systemImage: model.snapshot.status == .running ? "pause.fill" : "play.fill")
            }
            .disabled(model.snapshot.watchedProcesses.isEmpty)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
    }

    private func effectButton(_ effect: PulseEffect) -> some View {
        let selected = model.effect == effect
        let available = !effect.requiresDirectionalMetric || model.metric == .disk || model.metric == .network
        return Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { model.effectBinding.wrappedValue = effect }
        } label: {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Image(systemName: effect.symbol).font(.system(size: 21, weight: .medium))
                    Spacer()
                    if selected { Image(systemName: "checkmark.circle.fill").font(.body) }
                }
                Text(effect.localizedName).font(.caption.weight(.semibold)).lineLimit(1)
                if !available {
                    Text("RX/TX · I/O").font(.caption2)
                }
            }
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: 90, alignment: .topLeading)
            .background(selected ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color.accentColor.opacity(0.65) : Color.primary.opacity(0.08), lineWidth: selected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain).disabled(!available)
        .help(available ? effect.localizedExplanation : translated("Selecciona Disco o Red para usar dos canales.", "Choose Disk or Network to use two channels."))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var monitoringTab: some View {
        Form {
            Section {
                Picker(translated("Recurso", "Resource"), selection: model.metricBinding) {
                    ForEach(ProcessMetric.allCases, id: \.self) { metric in Text(metric.localizedName).tag(metric) }
                }
                processSummary
            }
            Section {
                Picker(translated("Origen", "Source"), selection: model.editing(\.targetSource) { $0.message = "" }) {
                    Text(translated("Aplicación", "Application")).tag(TargetSource.application)
                    Text(translated("PID manual", "Manual PID")).tag(TargetSource.manualPID)
                }
                .labelsHidden().pickerStyle(.segmented)
                .accessibilityLabel(translated("Tipo de objetivo", "Target source"))
                if model.targetSource == .application {
                    Picker(translated("Aplicación", "Application"), selection: model.editing(\.selectedAppPID) { $0.message = "" }) {
                        Text(translated("Seleccionar…", "Choose…")).tag(Int32(0))
                        ForEach(model.applications) { application in
                            Text("\(application.name) · PID \(String(application.pid))").tag(application.pid)
                        }
                    }
                } else {
                    TextField("PID", text: model.editing(\.manualPID) { $0.manualTarget = nil; $0.message = "" })
                        .textFieldStyle(.roundedBorder).onSubmit { model.refreshManualProcess() }
                    if let target = model.manualTarget {
                        Text(target.name).font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button {
                        model.message = ""
                        if model.targetSource == .application { model.refreshApplications() }
                        else { model.refreshManualProcess() }
                    } label: { Label(translated("Actualizar", "Refresh"), systemImage: "arrow.clockwise") }
                    .help(model.targetSource == .application ? translated("Actualizar aplicaciones", "Refresh applications") : translated("Consultar PID", "Look up PID"))
                    Spacer()
                    Button { model.watchSelectedTarget() } label: {
                        Label(translated("Vigilar", "Watch"), systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.targetSource == .application ? model.selectedAppPID == 0 : model.validManualPID == nil)
                }
                if !model.message.isEmpty {
                    Label(model.message, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.secondary)
                }
            } header: { Text(translated("Proceso", "Process")) }
            Section {
                Toggle(translated("Incluir descendientes", "Include descendants"), isOn: $model.includeChildren)
                Toggle(translated("Incluir helpers", "Include helpers"), isOn: $model.includeHelpers)
                sensitivityControls
            } header: { Text(translated("Opciones", "Options")) }
        }
        .formStyle(.grouped)
    }

    private var processSummary: some View {
        HStack(spacing: 10) {
            Image(systemName: activeProcess == nil ? "app.dashed" : "app.badge.checkmark")
                .foregroundStyle(Color.accentColor).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(activeProcess?.name ?? translated("Sin proceso vigilado", "No watched process"))
                    .fontWeight(.medium).lineLimit(1)
                Text(activeProcess.map { "PID \(String($0.pid))" } ?? translated("Elige un objetivo para empezar.", "Choose a target to start."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if activeProcess != nil {
                Text(model.snapshot.status == .running ? translated("Activo", "Active") : translated("Pausado", "Paused"))
                    .font(.caption).foregroundStyle(model.snapshot.status == .running ? Color.green : Color.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder private var sensitivityControls: some View {
        Toggle(translated("Escala personalizada", "Custom scale"), isOn: model.editing(\.thresholdEnabled) { $0.saveThreshold() })
        if model.thresholdEnabled {
            HStack(spacing: 10) {
                TextField(translated("Mínimo", "Minimum"), text: $model.minimumText).onSubmit { model.saveThreshold() }
                TextField(translated("Máximo", "Maximum"), text: $model.maximumText).onSubmit { model.saveThreshold() }
                Text(model.metric.unit).foregroundStyle(.secondary)
            }
            HStack {
                Button(translated("Restablecer escala", "Reset scale")) { model.restoreThreshold() }
                Spacer()
                Button(translated("Aplicar escala", "Apply scale")) { model.saveThreshold() }.disabled(model.validThreshold == nil)
            }
            if model.validThreshold == nil { Text(T.text("thresholdInvalid")).font(.caption).foregroundStyle(.red) }
        } else {
            LabeledContent(translated("100 % visual", "100% visual"), value: "\(model.metric.referenceMaximum.formatted()) \(model.metric.unit)")
                .foregroundStyle(.secondary)
        }
    }

    private var appearanceTab: some View {
        Form {
            Section {
                Picker(translated("Animación", "Animation"), selection: model.effectBinding) {
                    ForEach(PulseEffect.allCases.filter { !$0.requiresDirectionalMetric || model.metric == .disk || model.metric == .network }, id: \.self) { effect in
                        Text(effect.localizedName).tag(effect)
                    }
                }
                DisclosureGroup(translated("Explorar las 20 animaciones", "Browse all 20 animations"), isExpanded: $galleryExpanded) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(PulseEffect.allCases, id: \.self) { effect in effectButton(effect) }
                    }
                    .padding(.vertical, 10)
                }
            } header: { Text(translated("Movimiento", "Motion")) }
              footer: { EmptyView() }

            Section {
                Picker(translated("Paleta", "Palette"), selection: model.paletteBinding) {
                    ForEach(DisplayPalette.allCases, id: \.self) { palette in Text(palette.localizedName).tag(palette) }
                }
                ColorPicker(translated("Color personalizado", "Custom color"), selection: model.colorBinding, supportsOpacity: false)
                HStack {
                    Spacer()
                    Button(translated("Restablecer color", "Reset color")) { model.restoreColor() }
                }
            } header: { Text(translated("Color", "Color")) }

            Section {
                Toggle(translated("Mostrar etiqueta del recurso", "Show resource label"), isOn: model.metricLabelBinding)
                if model.effect == .marquee {
                    Toggle(translated("Incluir PID en el texto", "Include PID in text"), isOn: model.editing(\.marqueeShowsPID) { $0.changeMarquee() })
                    Toggle(translated("Incluir cantidad de procesos", "Include process count"), isOn: model.editing(\.marqueeShowsProcesses) { $0.changeMarquee() })
                }
            } header: { Text(translated("Etiqueta", "Label")) }
              footer: { EmptyView() }
        }
        .formStyle(.grouped)
    }

    private var sidebarReadings: some View {
        let sample = model.snapshot.activity
        let live = model.snapshot.status == .running && sample.processCount > 0
        return VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack {
                Circle().fill(live ? Color.green : Color.secondary).frame(width: 6, height: 6)
                Text(translated("Actividad", "Activity")).font(.caption.weight(.semibold))
                Spacer()
                Text("\(sample.processCount)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .help(translated("Procesos incluidos", "Included processes"))
            }
            Text(activeProcess?.name ?? translated("Sin proceso", "No process"))
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            VStack(spacing: 7) {
                sidebarReading("CPU", live ? String(format: "%.1f%%", sample.cpuPercent) : "—")
                sidebarReading("RAM", live ? String(format: "%.0f MiB", Double(sample.residentBytes) / 1_048_576) : "—")
                sidebarReading(translated("Disco", "Disk"), live && sample.diskReadableCount > 0 ? sample.formattedRate(sample.diskReadBps + sample.diskWriteBps) : "—")
                sidebarReading(translated("Red", "Network"), live && sample.networkAvailable ? sample.formattedRate(sample.networkReceivedBps + sample.networkSentBps) : "—")
                sidebarReading("GPU", live && sample.gpuAvailable ? String(format: "%.1f%%", sample.gpuPercent) : "—")
                sidebarReading(translated("Potencia", "Power"), live && sample.energyReadableCount > 0 ? String(format: "%.2f W", sample.energyWatts) : "—")
                sidebarReading(translated("Hilos", "Threads"), live ? "\(sample.threadCount)" : "—")
                sidebarReading("CTX", live ? String(format: "%.0f/s", sample.contextSwitchesPerSecond) : "—")
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 16)
    }

    private func sidebarReading(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value).monospacedDigit().lineLimit(1)
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
    }

    private var generalTab: some View {
        Form {
            Section {
                Toggle(translated("Abrir al iniciar sesión", "Launch at Login"), isOn: model.editing(\.loginEnabled) { $0.onLoginChanged?($0.loginEnabled) })
                Picker(translated("Idioma", "Language"), selection: model.editing(\.language) { model in AppLanguage.select(model.language); model.onLanguageChanged?() }) {
                    Text("Español").tag(AppLanguage.spanish)
                    Text("English").tag(AppLanguage.english)
                }
            } header: { Text(translated("Preferencias", "Preferences")) }
        }
        .formStyle(.grouped)
    }

}

final class ControlWindowController: NSWindowController, NSWindowDelegate {
    var onStart: ((WatchConfiguration) -> Void)?
    var onResume: (() -> Void)?
    var onStop: (() -> Void)?
    var onEffect: ((PulseEffect) -> Void)?
    var onMetric: ((ProcessMetric) -> Void)?
    var onMetricLabel: ((Bool) -> Void)?
    var onPalette: ((DisplayPalette) -> Void)?
    var onColor: ((String) -> Void)?
    var onMarqueeFields: ((Bool, Bool) -> Void)?
    var onThreshold: ((SignalThreshold) -> Void)?
    var onLanguageChanged: (() -> Void)?
    var onLoginChanged: ((Bool) -> Void)?
    var isLoginEnabled: (() -> Bool)?

    private let model = SettingsModel()
    private var previewTimer: Timer?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 780, height: 620)
        window.center()
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.setFrameAutosaveName("TouchBarKITT.Settings")
        super.init(window: window)
        window.delegate = self
        window.title = T.text("window")
        window.contentView = NSHostingView(rootView: SettingsView(model: model))
        connectModel()
    }

    required init?(coder: NSCoder) { return nil }

    private func connectModel() {
        model.onWatch = { [weak self] config in self?.onStart?(config) }
        model.onResume = { [weak self] in self?.onResume?() }
        model.onStop = { [weak self] in self?.onStop?() }
        model.onEffect = { [weak self] effect in self?.onEffect?(effect) }
        model.onMetric = { [weak self] metric in self?.onMetric?(metric) }
        model.onMetricLabel = { [weak self] enabled in self?.onMetricLabel?(enabled) }
        model.onPalette = { [weak self] palette in self?.onPalette?(palette) }
        model.onColor = { [weak self] hex in self?.onColor?(hex) }
        model.onMarqueeFields = { [weak self] pid, count in self?.onMarqueeFields?(pid, count) }
        model.onThreshold = { [weak self] threshold in self?.onThreshold?(threshold) }
        model.onLanguageChanged = { [weak self] in self?.onLanguageChanged?() }
        model.onLoginChanged = { [weak self] enabled in self?.onLoginChanged?(enabled) }
    }

    func show() {
        model.refreshApplications()
        refreshLoginState()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        if previewTimer == nil {
            let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
                self?.model.previewTick += 0.25
            }
            RunLoop.main.add(timer, forMode: .common)
            previewTimer = timer
        }
    }

    func windowWillClose(_ notification: Notification) {
        previewTimer?.invalidate()
        previewTimer = nil
    }

    func update(_ snapshot: PulseSnapshot) {
        model.receive(snapshot)
    }

    func localize() {
        model.language = AppLanguage.current
        window?.title = T.text("window")
    }

    func refreshLoginState() {
        model.loginEnabled = isLoginEnabled?() ?? false
    }

    func appendOutput(_ output: String) {
        model.message = String(output.trimmingCharacters(in: .whitespacesAndNewlines).suffix(240))
    }

    func startSelected() {
        if !model.snapshot.watchedProcesses.isEmpty { onResume?() }
        else { model.watchSelectedTarget() }
    }
}
