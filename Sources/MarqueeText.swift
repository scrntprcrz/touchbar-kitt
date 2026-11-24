import Foundation

enum MarqueeText {
    static let pixelColumnsPerGlyph = 6

    private static let glyphs: [Character: [UInt8]] = [
        "A": [0x7E, 0x11, 0x11, 0x11, 0x7E],
        "B": [0x7F, 0x49, 0x49, 0x49, 0x36],
        "C": [0x3E, 0x41, 0x41, 0x41, 0x22],
        "D": [0x7F, 0x41, 0x41, 0x22, 0x1C],
        "E": [0x7F, 0x49, 0x49, 0x49, 0x41],
        "F": [0x7F, 0x09, 0x09, 0x09, 0x01],
        "G": [0x3E, 0x41, 0x49, 0x49, 0x7A],
        "H": [0x7F, 0x08, 0x08, 0x08, 0x7F],
        "I": [0x41, 0x41, 0x7F, 0x41, 0x41],
        "J": [0x20, 0x40, 0x41, 0x3F, 0x01],
        "K": [0x7F, 0x08, 0x14, 0x22, 0x41],
        "L": [0x7F, 0x40, 0x40, 0x40, 0x40],
        "M": [0x7F, 0x02, 0x0C, 0x02, 0x7F],
        "N": [0x7F, 0x04, 0x08, 0x10, 0x7F],
        "O": [0x3E, 0x41, 0x41, 0x41, 0x3E],
        "P": [0x7F, 0x09, 0x09, 0x09, 0x06],
        "Q": [0x3E, 0x41, 0x51, 0x21, 0x5E],
        "R": [0x7F, 0x09, 0x19, 0x29, 0x46],
        "S": [0x46, 0x49, 0x49, 0x49, 0x31],
        "T": [0x01, 0x01, 0x7F, 0x01, 0x01],
        "U": [0x3F, 0x40, 0x40, 0x40, 0x3F],
        "V": [0x1F, 0x20, 0x40, 0x20, 0x1F],
        "W": [0x7F, 0x20, 0x18, 0x20, 0x7F],
        "X": [0x63, 0x14, 0x08, 0x14, 0x63],
        "Y": [0x03, 0x04, 0x78, 0x04, 0x03],
        "Z": [0x61, 0x51, 0x49, 0x45, 0x43],
        "0": [0x3E, 0x51, 0x49, 0x45, 0x3E],
        "1": [0x00, 0x42, 0x7F, 0x40, 0x00],
        "2": [0x42, 0x61, 0x51, 0x49, 0x46],
        "3": [0x21, 0x41, 0x45, 0x4B, 0x31],
        "4": [0x18, 0x14, 0x12, 0x7F, 0x10],
        "5": [0x27, 0x45, 0x45, 0x45, 0x39],
        "6": [0x3C, 0x4A, 0x49, 0x49, 0x30],
        "7": [0x01, 0x71, 0x09, 0x05, 0x03],
        "8": [0x36, 0x49, 0x49, 0x49, 0x36],
        "9": [0x06, 0x49, 0x49, 0x29, 0x1E],
        " ": [0, 0, 0, 0, 0],
        ".": [0, 0x60, 0x60, 0, 0],
        ",": [0, 0x40, 0x20, 0, 0],
        ":": [0, 0x36, 0x36, 0, 0],
        "/": [0x20, 0x10, 0x08, 0x04, 0x02],
        "-": [0x08, 0x08, 0x08, 0x08, 0x08],
        "+": [0x08, 0x08, 0x3E, 0x08, 0x08],
        "%": [0x63, 0x13, 0x08, 0x64, 0x63],
        "=": [0x14, 0x14, 0x14, 0x14, 0x14],
        "?": [0x02, 0x01, 0x51, 0x09, 0x06],
        "!": [0, 0, 0x5F, 0, 0],
        "*": [0x14, 0x08, 0x3E, 0x08, 0x14],
        "|": [0, 0, 0x7F, 0, 0],
        "_": [0x40, 0x40, 0x40, 0x40, 0x40]
    ]

    static func columns(for string: String) -> [UInt8] {
        let text = string.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "es_ES")).uppercased()
        return text.flatMap { character in
            (glyphs[character] ?? glyphs["?"] ?? [0, 0, 0, 0, 0]) + [0]
        }
    }

    static func circularColumn(_ visibleColumn: Int, offset: Int, columnCount: Int) -> Int {
        guard columnCount > 0 else { return 0 }
        let index = (visibleColumn + offset) % columnCount
        return index >= 0 ? index : index + columnCount
    }

    static func message(for snapshot: PulseSnapshot) -> String {
        let name = snapshot.processName.isEmpty ? "PID \(snapshot.pid ?? 0)" : snapshot.processName
        let sample = snapshot.activity
        let english = AppLanguage.current == .english
        let detail: String
        switch snapshot.metric {
        case .cpu:
            detail = String(format: "CPU %.1f%%", sample.cpuPercent)
        case .disk:
            detail = "\(english ? "DISK" : "DISCO") R \(sample.formattedRate(sample.diskReadBps)) W \(sample.formattedRate(sample.diskWriteBps))"
        case .network:
            detail = sample.networkAvailable
                ? "\(english ? "NET" : "RED") RX \(sample.formattedRate(sample.networkReceivedBps)) TX \(sample.formattedRate(sample.networkSentBps))"
                : (english ? "NET NO DATA" : "RED SIN DATOS")
        case .memory:
            detail = String(format: english ? "RAM %.0f MiB CHANGE %+.1f MiB/s" : "RAM %.0f MiB CAMBIO %+.1f MiB/s", Double(sample.residentBytes) / 1_048_576, sample.memoryDeltaBps / 1_048_576)
        case .gpu:
            detail = sample.gpuAvailable ? String(format: "GPU %.1f%%", sample.gpuPercent) : (english ? "GPU NO DATA" : "GPU SIN DATOS")
        case .energy:
            detail = sample.energyReadableCount > 0 ? String(format: "%.2f W", sample.energyWatts) : (english ? "POWER NO DATA" : "ENERGIA SIN DATOS")
        case .threads:
            detail = "\(english ? "THREADS" : "HILOS") \(sample.threadCount)"
        case .switches:
            detail = String(format: "CTX %.0f/s", sample.contextSwitchesPerSecond)
        }
        var parts = [name]
        if snapshot.marqueeShowsPID { parts.append("PID \(snapshot.pid ?? 0)") }
        parts.append(detail)
        if snapshot.marqueeShowsProcesses { parts.append("\(sample.processCount) \(english ? "PROCESSES" : "PROCESOS")") }
        return parts.joined(separator: " | ") + " | "
    }
}
