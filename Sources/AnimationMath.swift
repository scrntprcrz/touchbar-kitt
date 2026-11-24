import Foundation

// The badge overlays the animation; it must never change the scanner's track.
struct MetricLabelLayout {
    let x: Double
    let width: Double

    static func make(availableWidth: Double, textWidth: Double) -> MetricLabelLayout? {
        let inset = 14.0
        let width = ceil(max(0, textWidth)) + 16
        guard availableWidth >= width + inset * 2 else { return nil }
        return MetricLabelLayout(x: availableWidth - inset - width, width: width)
    }
}

func waveLevel(position: Double, elapsed: Double, activity: Double) -> Double {
    let level = min(1, max(0, activity))
    return level * (0.5 + 0.5 * sin(position * .pi * 4 - elapsed * (1 + level * 5)))
}

func kittElementsPerSecond(activity: Double) -> Double {
    let normalized = min(1, max(0, activity.isFinite ? activity : 0))
    return 8 + 88 * pow(normalized, 0.65)
}

func pingPongPosition(progress: Double, segmentCount: Int) -> Double {
    let end = Double(max(1, segmentCount - 1))
    let cycle = 2 * end
    let phase = progress.truncatingRemainder(dividingBy: cycle)
    return phase <= end ? phase : cycle - phase
}

func normalizedHistory(_ values: [Double], count: Int) -> [Double] {
    let tail = Array(values.suffix(count))
    return Array(repeating: 0, count: max(0, count - tail.count)) + tail
}

func segmentGeometry(index: Int, count: Int, availableWidth: Double, gap: Double) -> (x: Double, width: Double) {
    guard count > 0, index >= 0, index < count, availableWidth > 0 else { return (0, 0) }
    let spacing = min(max(0, gap), availableWidth / Double(max(1, count - 1)))
    let width = max(0, (availableWidth - Double(count - 1) * spacing) / Double(count))
    return (Double(index) * (width + spacing), width)
}
