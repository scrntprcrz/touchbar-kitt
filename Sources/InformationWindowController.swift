import AppKit
import SwiftUI

enum InformationPage {
    case diagnostics
}

private struct InformationView: View {
    let page: InformationPage
    let snapshot: PulseSnapshot
    let displayWidth: CGFloat

    private var english: Bool { AppLanguage.current == .english }

    private func text(_ spanish: String, _ englishText: String) -> String {
        english ? englishText : spanish
    }

    var body: some View {
        Form {

                Section {
                    LabeledContent(text("Objetivo", "Target"), value: snapshot.processName.isEmpty ? "—" : snapshot.processName)
                    LabeledContent("PID", value: snapshot.pid.map { String($0) } ?? "—")
                    LabeledContent(text("Métrica seleccionada", "Selected metric"), value: snapshot.metric.localizedName)
                    LabeledContent(text("Vista Touch Bar", "Touch Bar view"), value: "\(Int(displayWidth)) pt")
                    LabeledContent("macOS", value: ProcessInfo.processInfo.operatingSystemVersionString)
                    LabeledContent(text("Procesos incluidos", "Included processes"), value: "\(snapshot.activity.processCount)")
                } header: {
                    Text(text("Sesión actual", "Current session"))
                }
                Section {
                    source(text("CPU, RAM, hilos y cambios de contexto", "CPU, RAM, threads and context switches"), "libproc · proc_pidinfo")
                    source(text("Disco y energía", "Disk and energy"), "proc_pid_rusage")
                    source(text("Red (solo al seleccionarla)", "Network (only when selected)"), "NetworkStatistics.framework")
                    source(text("GPU experimental", "Experimental GPU"), "IOKit · AGX")
                    source(text("Estado térmico global", "System thermal state"), "ProcessInfo.thermalState")
                } header: {
                    Text(text("Fuentes de datos", "Data sources"))
                }
                Section {
                    Text(text("No se ejecuta nettop. La red y la GPU pueden no estar disponibles. La temperatura no se atribuye a un PID. Las lecturas de varios hijos se agregan cuando es posible.", "nettop is never launched. Network and GPU readings may be unavailable. Temperature is not attributable to a PID. Child-process readings are aggregated when available."))
                        .font(.callout)
                    Text(text("Control local opcional: HTTP en 127.0.0.1:4317. Rutas: /watch, /metric, /effect, /stop, /resume y /state.", "Optional local control: HTTP at 127.0.0.1:4317. Routes: /watch, /metric, /effect, /stop, /resume and /state."))
                        .font(.callout)
                } header: {
                    Text(text("Privacidad y comandos", "Privacy and commands"))
                }
        }
        .formStyle(.grouped)
        .frame(minWidth: 580, minHeight: 350)
    }

    private func source(_ name: String, _ provider: String) -> some View {
        LabeledContent(name, value: provider)
    }
}

final class InformationWindowController: NSWindowController {
    private let page: InformationPage

    init(page: InformationPage) {
        self.page = page
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 440),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 580, height: 380)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { return nil }

    func show(snapshot: PulseSnapshot, displayWidth: CGFloat) {
        window?.title = AppLanguage.current == .english ? "Data Sources and Diagnostics" : "Fuentes de datos y diagnóstico"
        window?.contentView = NSHostingView(rootView: InformationView(page: page, snapshot: snapshot, displayWidth: displayWidth))
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
