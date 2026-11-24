import Foundation

enum AppLanguage: String, CaseIterable {
    case spanish = "es"
    case english = "en"

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: "ui.language") ?? "es") ?? .spanish
    }

    static func select(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: "ui.language")
    }
}

enum T {
    private static let strings: [String: (String, String)] = [
        "settings": ("Configuración…", "Settings…"),
        "startLast": ("Vigilar última selección", "Watch last selection"),
        "stop": ("Detener", "Stop"),
        "reset": ("Reiniciar", "Reset"),
        "login": ("Abrir al iniciar sesión", "Launch at Login"),
        "quit": ("Salir de TouchBar KITT", "Quit TouchBar KITT"),
        "language": ("Idioma", "Language"),
        "spanish": ("Español", "Spanish"),
        "english": ("Inglés", "English"),
        "window": ("TouchBar KITT · Configuración", "TouchBar KITT · Settings"),
        "subtitle": ("Monitor de recursos por proceso y descendientes", "Resource monitor for processes and descendants"),
        "preview": ("Vista previa de Touch Bar", "Touch Bar Preview"),
        "previewHelp": ("Mismo motor gráfico que la Touch Bar real", "Uses the same renderer as the real Touch Bar"),
        "demo": ("Simulación", "Demo"),
        "live": ("En vivo", "Live"),
        "demoActivity": ("Carga de prueba", "Test activity"),
        "process": ("Proceso", "Process"),
        "processHelp": ("Selecciona una app o escribe el PID", "Select an app or enter a PID"),
        "app": ("Aplicación abierta", "Running application"),
        "pickApp": ("Selecciona una app…", "Select an app…"),
        "refresh": ("Actualizar", "Refresh"),
        "watchApp": ("Vigilar app", "Watch app"),
        "manualPID": ("PID manual", "Manual PID"),
        "watchPID": ("Vigilar PID", "Watch PID"),
        "children": ("Incluir hijos y descendientes", "Include children and descendants"),
        "helpers": ("Incluir helpers del mismo .app", "Include helpers from the same .app"),
        "visual": ("Visualización", "Visualization"),
        "visualHelp": ("Métrica, animación y color", "Metric, animation, and color"),
        "metric": ("Métrica", "Metric"),
        "effect": ("Animación", "Animation"),
        "palette": ("Color", "Color"),
        "metricTag": ("Mostrar etiqueta de métrica al extremo derecho", "Show metric tag at the right edge"),
        "marqueePID": ("Mostrar PID en marquesina", "Show PID in marquee"),
        "marqueeProcesses": ("Mostrar cantidad de procesos", "Show process count"),
        "threshold": ("Sensibilidad y umbrales", "Sensitivity and Thresholds"),
        "thresholdHelp": ("Ajusta la escala visual sin modificar las mediciones reales", "Tune the visual scale without changing measured values"),
        "customScale": ("Usar escala personalizada", "Use custom scale"),
        "minimum": ("Umbral mínimo", "Minimum threshold"),
        "maximum": ("100 % visual", "100% visual"),
        "defaults": ("Valores predeterminados", "Restore Defaults"),
        "thresholdInvalid": ("El máximo debe ser mayor que el mínimo y ambos no negativos.", "Maximum must exceed minimum; both must be nonnegative."),
        "thresholdAuto": ("Escala predeterminada", "Default scale"),
        "thresholdUnits": ("Unidad", "Unit"),
        "readings": ("Lecturas del proceso", "Process Readings"),
        "readingsHelp": ("Se agregan las métricas disponibles del PID y su familia", "Aggregates available metrics for the PID and its process family"),
        "statusIdle": ("En reposo", "Idle"),
        "statusRunning": ("Vigilando", "Monitoring"),
        "statusDone": ("Finalizado", "Finished"),
        "statusError": ("No disponible", "Unavailable"),
        "statusAttention": ("Atención", "Attention"),
        "noProcess": ("Sin proceso", "No process"),
        "empty": ("Selecciona un proceso y pulsa Vigilar", "Choose a process and press Watch"),
        "cpu": ("CPU", "CPU"),
        "ram": ("Memoria", "Memory"),
        "disk": ("Disco", "Disk"),
        "network": ("Red", "Network"),
        "gpu": ("GPU", "GPU"),
        "energy": ("Energía", "Energy"),
        "processes": ("procesos", "processes"),
        "unavailable": ("Sin datos", "No data"),
        "coverage": ("Cobertura", "Coverage"),
        "active": ("Actividad visual", "Visual activity"),
        "background": ("Cerrar esta ventana no detiene el monitoreo.", "Closing this window does not stop monitoring."),
        "loginError": ("No se pudo cambiar el inicio automático", "Could not change Launch at Login"),
        "loginHint": ("Instala la app en /Applications y revisa Ítems de inicio.", "Move the app to /Applications and check Login Items."),
        "invalidPID": ("Introduce un PID válido.", "Enter a valid PID."),
        "invalidApp": ("Selecciona una app o utiliza un PID manual.", "Choose an app or use a manual PID."),
        "marqueeNote": ("El carrusel usa valores reales y admite la etiqueta opcional.", "The marquee uses measured values and supports the optional resource label."),
        "statusUnavailable": ("Algunas mediciones no están disponibles.", "Some metrics are unavailable.")
    ]

    static func text(_ key: String) -> String {
        guard let entry = strings[key] else { return key }
        return AppLanguage.current == .spanish ? entry.0 : entry.1
    }
}

extension ProcessMetric {
    var localizedName: String {
        switch self {
        case .cpu: return T.text("cpu") + " · % / core"
        case .memory: return T.text("ram") + " · Δ MiB/s"
        case .disk: return T.text("disk") + " · ↓ + ↑"
        case .network: return T.text("network") + " · RX + TX"
        case .gpu: return "GPU · %"
        case .energy: return T.text("energy") + " · W"
        case .threads: return AppLanguage.current == .english ? "Threads · Count" : "Hilos · Cantidad"
        case .switches: return AppLanguage.current == .english ? "Context switches · /s" : "Cambios de contexto · /s"
        }
    }

    var unit: String {
        switch self {
        case .cpu, .gpu: return "%"
        case .disk, .network, .memory: return "MiB/s"
        case .energy: return "W"
        case .threads: return AppLanguage.current == .english ? "threads" : "hilos"
        case .switches: return "ctx/s"
        }
    }

    var referenceMaximum: Double {
        switch self {
        case .cpu, .gpu: return 100
        case .disk: return 4
        case .network: return 2
        case .memory: return 64
        case .energy: return 5
        case .threads: return 128
        case .switches: return 2000
        }
    }

    var localizedExplanation: String {
        let english = AppLanguage.current == .english
        switch self {
        case .cpu: return english ? "100% equals one CPU core; process families can exceed 100%." : "100 % equivale a un núcleo; la familia puede superar 100 %."
        case .memory: return english ? "Activity is absolute RAM change per second, not occupied RAM." : "Actividad = cambio absoluto de RAM por segundo, no RAM ocupada."
        case .disk: return english ? "Reads + writes in MiB/s; not SSD device utilization." : "Lecturas + escrituras en MiB/s; no es el uso físico del SSD."
        case .network: return english ? "RX + TX in MiB/s; private native sampler, availability may vary." : "RX + TX en MiB/s; lector nativo privado con disponibilidad variable."
        case .gpu: return english ? "Experimental GPU execution-time estimate, may be unavailable." : "Estimación experimental de tiempo GPU; puede no estar disponible."
        case .energy: return english ? "Estimated power in W; not Apple's Energy Impact score." : "Potencia estimada en W; no es Impacto energético de Apple."
        case .threads: return english ? "Number of live threads in the process family; not CPU load." : "Hilos activos del árbol; no equivalen al uso de CPU."
        case .switches: return english ? "Context switches per second sampled from libproc, not total CPU usage." : "Cambios de contexto por segundo de libproc; no equivalen al uso de CPU."
        }
    }
}

extension PulseEffect {
    var localizedName: String {
        let english = AppLanguage.current == .english
        switch self {
        case .kitt: return "KITT · " + (english ? "Speed" : "Velocidad")
        case .disk: return "LED · " + (english ? "Brightness" : "Brillo")
        case .heartbeat: return "ECG · " + (english ? "Pulse height" : "Altura de pulso")
        case .vu: return "VU · " + (english ? "Level" : "Nivel")
        case .peak: return "VU Peak · " + (english ? "Peak hold" : "Pico retenido")
        case .scope: return english ? "Oscilloscope" : "Osciloscopio"
        case .waterfall: return english ? "Waterfall" : "Cascada"
        case .duplex: return english ? "Dual-channel" : "Doble canal"
        case .marquee: return english ? "LED Marquee" : "Marquesina LED"
        case .comet: return english ? "Comet" : "Cometa"
        case .equalizer: return english ? "Equalizer" : "Ecualizador"
        case .sparkline: return english ? "Filled graph" : "Gráfico de área"
        case .centerVU: return english ? "Center VU" : "VU central"
        case .digital: return english ? "Digital meter" : "Medidor digital"
        case .signal: return english ? "Signal pulses" : "Pulsos de señal"
        case .wave: return english ? "Waves" : "Ondas"
        case .radar: return "Radar"
        case .particles: return english ? "Particles" : "Partículas"
        case .breathe: return english ? "Breathe" : "Respiración"
        case .twin: return english ? "Twin KITT" : "KITT doble"
        }
    }

    var localizedExplanation: String {
        let english = AppLanguage.current == .english
        switch self {
        case .kitt: return english ? "More activity increases scanner speed; brightness stays constant." : "Más actividad acelera el barrido; el brillo permanece constante."
        case .disk: return english ? "LED brightness follows the normalized level." : "El brillo del LED sigue el nivel normalizado."
        case .heartbeat: return english ? "ECG peak amplitude follows activity; not a real heartbeat." : "La amplitud de ECG sigue la actividad; no mide pulsaciones."
        case .vu: return english ? "Lit bars represent the normalized value directly." : "Las barras encendidas representan directamente el valor normalizado."
        case .peak: return english ? "VU bars plus the recent maximum." : "Barras VU y máximo de las últimas muestras."
        case .scope: return english ? "Rolling history of normalized samples." : "Historial continuo de muestras normalizadas."
        case .waterfall: return english ? "Scrolling columns of historical intensity." : "Columnas de intensidad histórica que se desplazan."
        case .duplex: return english ? "Two independent RX/TX or read/write tracks." : "Dos pistas independientes para RX/TX o lectura/escritura."
        case .marquee: return english ? "Continuous pixel-text loop with measured values." : "Carrusel de texto LED continuo con valores reales."
        case .comet: return english ? "A bright dot and tail move faster as usage increases." : "Una luz con estela acelera cuando aumenta la actividad."
        case .equalizer: return english ? "Each column represents a recent normalized sample." : "Cada columna representa una muestra reciente normalizada."
        case .sparkline: return english ? "Filled area chart of recent activity samples." : "Área rellena con las muestras recientes de actividad."
        case .centerVU: return english ? "Symmetric bars extend outward from the center according to the measured level." : "Las barras crecen desde el centro hacia los bordes según el valor medido."
        case .digital: return english ? "Shows the normalized visual percentage and a proportional progress strip." : "Muestra el porcentaje visual normalizado y una barra proporcional."
        case .signal: return english ? "Signal pulse frequency increases with activity; not actual heartbeat measurement." : "La frecuencia de destello aumenta con la carga; no mide pulsaciones reales."
        case .wave: return english ? "Wave height and speed follow the measured level." : "La altura y velocidad de las ondas siguen el nivel medido."
        case .radar: return english ? "A sweeping trail brightens and accelerates with activity." : "Un barrido con estela aumenta su brillo y velocidad con la actividad."
        case .particles: return english ? "Activity controls the number and speed of up to 14 light particles." : "La actividad controla la cantidad y velocidad de hasta 14 partículas de luz."
        case .breathe: return english ? "A smooth fade; brightness and frequency follow activity." : "Un fundido suave cuyo brillo y frecuencia siguen la actividad."
        case .twin: return english ? "Two mirrored scanners move faster with activity." : "Dos luces simétricas se desplazan más rápido con la actividad."
        }
    }
}

extension DisplayPalette {
    var localizedName: String {
        let english = AppLanguage.current == .english
        switch self {
        case .original: return english ? "Original" : "Original"
        case .amber: return english ? "Amber" : "Ámbar"
        case .red: return english ? "Red" : "Rojo"
        case .green: return english ? "Green" : "Verde"
        case .cyan: return english ? "Cyan" : "Cian"
        case .violet: return english ? "Violet" : "Violeta"
        case .rainbow: return english ? "Rainbow" : "Arcoíris"
        case .custom: return english ? "Custom" : "Personalizado"
        }
    }
}
