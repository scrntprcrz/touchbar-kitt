import Foundation

enum PulseStatus: String, Codable, CaseIterable {
    case idle
    case running
    case done
    case error
    case attention
}

enum PulseEffect: String, Codable, CaseIterable {
    case kitt
    case disk
    case heartbeat
    case vu
    case peak
    case scope
    case waterfall
    case duplex
    case marquee
    case comet
    case equalizer
    case sparkline
    case centerVU
    case digital
    case signal
    case wave
    case radar
    case particles
    case breathe
    case twin

    var title: String {
        switch self {
        case .kitt: return "KITT · Velocidad por actividad"
        case .disk: return "LED · Brillo proporcional"
        case .heartbeat: return "ECG · Amplitud proporcional"
        case .vu: return "VU · Barras proporcionales"
        case .peak: return "VU con pico · Máximos recientes"
        case .scope: return "Osciloscopio · Historial"
        case .waterfall: return "Cascada · Actividad temporal"
        case .duplex: return "Doble canal · RX/TX o lectura/escritura"
        case .marquee: return "Marquesina LED · Texto desplazándose"
        case .comet: return "Cometa · Velocidad proporcional"
        case .equalizer: return "Ecualizador · Historial de barras"
        case .sparkline: return "Gráfico continuo · Historial"
        case .centerVU: return "VU central · Barras simétricas"
        case .digital: return "Digital · Nivel porcentual"
        case .signal: return "Pulsos · Frecuencia por carga"
        case .wave: return "Ondas · Amplitud y velocidad"
        case .radar: return "Radar · Barrido con estela"
        case .particles: return "Partículas · Densidad por carga"
        case .breathe: return "Respiración · Brillo suave"
        case .twin: return "KITT doble · Barrido simétrico"
        }
    }

    var requiresDirectionalMetric: Bool { self == .duplex }

    var quantification: String {
        switch self {
        case .kitt: return "Velocidad: 8–96 segmentos/s según la señal normalizada. Luz siempre intensa."
        case .disk: return "LED: brillo entre 0 y 100% según la señal normalizada."
        case .heartbeat: return "ECG: altura de los picos proporcional a la señal; no mide pulsaciones reales."
        case .vu: return "VU: segmentos encendidos = señal normalizada × 48."
        case .peak: return "VU con pico: barras actuales + máximo de las últimas 10 muestras."
        case .scope: return "Osciloscopio: historial de hasta 120 muestras; eje vertical = intensidad."
        case .waterfall: return "Cascada: cada columna guarda una intensidad histórica."
        case .duplex: return "Dos canales: lectura/escritura de disco o RX/TX de red, con escalas propias."
        case .marquee: return "Carrusel continuo: texto y valores reales; velocidad fija 58 px/s, sin pausas."
        case .comet: return "Cometa: la velocidad aumenta con la actividad y la cola sigue su recorrido."
        case .equalizer: return "Ecualizador: cada columna indica una muestra reciente de actividad."
        case .sparkline: return "Gráfico: historial de intensidad con relleno proporcional."
        case .centerVU: return "VU central: barras desde el centro a los extremos según la intensidad."
        case .digital: return "Digital: porcentaje visual actual calculado con el umbral de la métrica."
        case .signal: return "Pulsos: la frecuencia de destello crece con la intensidad; no mide latidos reales."
        case .wave: return "Ondas: amplitud y velocidad aumentan con el nivel normalizado."
        case .radar: return "Radar: brillo y velocidad del barrido crecen con la actividad."
        case .particles: return "Partículas: hasta 14 puntos; cantidad y velocidad proporcionales a la señal."
        case .breathe: return "Respiración: brillo y frecuencia de un fundido suave según la señal."
        case .twin: return "KITT doble: dos luces reflejadas; velocidad de 8–96 segmentos/s según la señal."
        }
    }
}

enum DisplayPalette: String, Codable, CaseIterable {
    case original
    case amber
    case red
    case green
    case cyan
    case violet
    case rainbow
    case custom

    var title: String {
        switch self {
        case .original: return "Original · Según efecto"
        case .amber: return "Ámbar · LED de bus"
        case .red: return "Rojo · KITT"
        case .green: return "Verde · Fósforo"
        case .cyan: return "Cian · Digital"
        case .violet: return "Violeta · Neón"
        case .rainbow: return "Arcoíris · Multicolor"
        case .custom: return "Personalizado"
        }
    }
}

enum ProcessMetric: String, Codable, CaseIterable {
    case cpu
    case disk
    case network
    case memory
    case gpu
    case energy
    case threads
    case switches

    var badge: String {
        switch self {
        case .cpu: return "CPU"
        case .disk: return AppLanguage.current == .english ? "DISK" : "DISCO"
        case .network: return AppLanguage.current == .english ? "NET" : "RED"
        case .memory: return "RAM"
        case .gpu: return "GPU"
        case .energy: return "W"
        case .threads: return AppLanguage.current == .english ? "THR" : "HILOS"
        case .switches: return "CTX"
        }
    }

    var needsNetworkSampler: Bool { self == .network }
    var needsGPUSampler: Bool { self == .gpu }

    var title: String {
        switch self {
        case .cpu: return "CPU · % de un núcleo"
        case .disk: return "Disco · lectura + escritura"
        case .network: return "Red · descarga + subida"
        case .memory: return "Memoria · cambio de RAM"
        case .gpu: return "GPU · tiempo de ejecución"
        case .energy: return "Energía · potencia estimada"
        case .threads: return "Hilos · cantidad activa"
        case .switches: return "Cambios de contexto · por segundo"
        }
    }

    var explanation: String {
        switch self {
        case .cpu: return "100% = 1 núcleo; CPU de la familia puede superar 100%."
        case .disk: return "100% visual = 4 MiB/s leídos + escritos, atribuidos al PID y sus hijos."
        case .network: return "100% visual = 2 MiB/s RX + TX. Muestreo nativo cada 2,5 s, solo cuando seleccionas Red. Sin nettop."
        case .memory: return "100% visual = 64 MiB/s de cambio absoluto de RAM residente. RAM estable = 0."
        case .gpu: return "100% visual = 100% de tiempo GPU acumulado, por AGXDeviceUserClient; experimental, puede no haber datos."
        case .energy: return "100% visual = 5 W derivados de ri_energy_nj; no equivale a Energy Impact de Apple."
        case .threads: return "100% visual = 128 hilos de la familia del PID."
        case .switches: return "100% visual = 2000 cambios de contexto por segundo de la familia del PID."
        }
    }
}

struct WatchedProcess: Codable, Equatable, Identifiable {
    var pid: Int32
    var name: String
    var includeChildren: Bool
    var includeAppHelpers: Bool
    var id: Int32 { pid }
}

struct WatchConfiguration {
    var pid: Int32
    var includeChildren: Bool
    var includeAppHelpers: Bool
    var effect: PulseEffect
    var metric: ProcessMetric
    var processName: String = ""
    var showMetricLabel: Bool = false
    var palette: DisplayPalette = .original
    var customColorHex: String = "#FF3535"
    var marqueeShowsPID: Bool = true
    var marqueeShowsProcesses: Bool = true
    var threshold = SignalThreshold()
}

struct ActivitySample: Codable, Equatable {
    var cpuPercent: Double = 0
    var diskReadBps: Double = 0
    var diskWriteBps: Double = 0
    var networkReceivedBps: Double = 0
    var networkSentBps: Double = 0
    var networkAvailable: Bool = false
    var networkVisiblePIDs: Int = 0
    var residentBytes: UInt64 = 0
    var memoryDeltaBps: Double = 0
    var processCount: Int = 0
    var readableCount: Int = 0
    var diskReadableCount: Int = 0
    var gpuPercent: Double = 0
    var gpuAvailable: Bool = false
    var gpuVisiblePIDs: Int = 0
    var energyWatts: Double = 0
    var threadCount: UInt64 = 0
    var contextSwitchesPerSecond: Double = 0
    var energyReadableCount: Int = 0
    var thermalState: String = "—"
    var sampledSeconds: Double = 0

    static let zero = ActivitySample()

    func rawValue(for metric: ProcessMetric) -> Double {
        switch metric {
        case .cpu: return cpuPercent
        case .disk: return (diskReadBps + diskWriteBps) / 1_048_576
        case .network: return networkAvailable ? (networkReceivedBps + networkSentBps) / 1_048_576 : 0
        case .memory: return abs(memoryDeltaBps) / 1_048_576
        case .gpu: return gpuAvailable ? gpuPercent : 0
        case .energy: return energyReadableCount > 0 ? energyWatts : 0
        case .threads: return Double(threadCount)
        case .switches: return contextSwitchesPerSecond
        }
    }

    func intensity(for metric: ProcessMetric, threshold: SignalThreshold = SignalThreshold()) -> Double {
        threshold.normalized(rawValue(for: metric), for: metric)
    }

    func componentIntensities(for metric: ProcessMetric) -> (Double, Double) {
        let first: Double
        let second: Double
        switch metric {
        case .disk:
            first = diskReadBps / (4 * 1024 * 1024)
            second = diskWriteBps / (4 * 1024 * 1024)
        case .network:
            first = networkAvailable ? networkReceivedBps / (2 * 1024 * 1024) : 0
            second = networkAvailable ? networkSentBps / (2 * 1024 * 1024) : 0
        case .cpu, .memory, .gpu, .energy, .threads, .switches:
            return (0, 0)
        }
        return (min(1, max(0, first)), min(1, max(0, second)))
    }

    func formattedRate(_ bytes: Double) -> String {
        let rate = max(0, bytes.isFinite ? bytes : 0)
        if rate < 1024 { return String(format: "%.0f B/s", rate) }
        if rate < 1_048_576 { return String(format: "%.1f KiB/s", rate / 1024) }
        if rate < 1_073_741_824 { return String(format: "%.1f MiB/s", rate / 1_048_576) }
        return String(format: "%.2f GiB/s", rate / 1_073_741_824)
    }

    var summary: String {
        let memory = String(format: "%.1f MiB", Double(residentBytes) / 1_048_576)
        let change = String(format: "%+.2f MiB/s", memoryDeltaBps / 1_048_576)
        let net = networkAvailable
            ? "Red ↓ \(formattedRate(networkReceivedBps)) ↑ \(formattedRate(networkSentBps))"
            : "Red ↓ — ↑ — (pausada o sin datos)"
        let gpu = gpuAvailable ? String(format: "%.1f%%", gpuPercent) : "—"
        let energy = energyReadableCount > 0 ? String(format: "%.2f W", energyWatts) : "—"
        return "CPU \(String(format: "%.1f", cpuPercent))%   RAM \(memory) (Δ \(change))\nDisco ↓ \(formattedRate(diskReadBps)) ↑ \(formattedRate(diskWriteBps))\n\(net)\nGPU \(gpu)   Energía \(energy)   Térmico \(thermalState)"
    }

    var coverage: String {
        let net = networkAvailable ? "red nativa: \(networkVisiblePIDs)" : "red: sin datos"
        let gpu = gpuAvailable ? "GPU en AGX: \(gpuVisiblePIDs)" : "GPU: sin datos"
        return "Procesos: \(processCount) · CPU/RAM: \(readableCount) · disco: \(diskReadableCount) · energía: \(energyReadableCount) · \(gpu) · \(net)"
    }
}

struct PulseSnapshot: Codable, Equatable {
    var watchedProcesses: [WatchedProcess] = []
    var status: PulseStatus = .idle
    var effect: PulseEffect = .vu
    var metric: ProcessMetric = .cpu
    var label: String = ""
    var processName: String = ""
    var showMetricLabel: Bool = false
    var palette: DisplayPalette = .original
    var customColorHex: String = "#FF3535"
    var marqueeShowsPID: Bool = true
    var marqueeShowsProcesses: Bool = true
    var threshold = SignalThreshold()
    var pid: Int32? = nil
    var includeChildren: Bool = true
    var includeAppHelpers: Bool = true
    var activity: ActivitySample = .zero
    var updatedAt: Date = Date()
}

struct HTTPRequestLine: Equatable {
    let method: String
    let path: String
    let parameters: [String: String]

    static func parse(_ line: String) -> HTTPRequestLine? {
        let tokens = line.split(separator: " ", omittingEmptySubsequences: true)
        guard tokens.count == 3,
              ["GET", "POST"].contains(String(tokens[0])),
              String(tokens[2]).hasPrefix("HTTP/"),
              let components = URLComponents(string: "http://localhost\(tokens[1])") else {
            return nil
        }
        let parameters = Dictionary(
            (components.queryItems ?? []).compactMap { item in item.value.map { (item.name, $0) } },
            uniquingKeysWith: { _, newer in newer }
        )
        return HTTPRequestLine(method: String(tokens[0]), path: components.path, parameters: parameters)
    }
}
