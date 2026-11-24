import AppKit

final class PulseBarView: NSView {
    private let count = 48
    private let gap: CGFloat = 3
    private var snapshot = PulseSnapshot()
    private var animationTimer: Timer?
    private var animationElapsed = 0.0
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var scannerProgress = 0.0
    private var history: [Double] = []
    private var lastSampleAt: Date?
    private var marqueeColumns: [UInt8] = []
    private var marqueeOffset: CGFloat = 0
    var animates = true { didSet { updateTimer() } }
    var runsWithoutWindow = false { didSet { updateTimer() } }
    var animationIsRunning: Bool { animationTimer != nil }
    var renderingRect: NSRect {
        let clipped = visibleRect.intersection(bounds)
        return clipped.isEmpty ? bounds : clipped
    }
    private let labelFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
    private var sideLabel: String? {
        guard snapshot.showMetricLabel else { return nil }
        return snapshot.metric.badge
    }
    private var visualBounds: NSRect { NSRect(origin: .zero, size: renderingRect.size) }

    override var intrinsicContentSize: NSSize { NSSize(width: 1085, height: 30) }
    override var isOpaque: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    func update(_ value: PulseSnapshot) {
        let modeChanged = snapshot.status != value.status || snapshot.effect != value.effect
        let metricChanged = snapshot.metric != value.metric
        let identityChanged = snapshot.processName != value.processName || snapshot.pid != value.pid
        if modeChanged {
            animationElapsed = 0
            scannerProgress = 0
        }
        if metricChanged { history.removeAll() }
        if modeChanged || metricChanged || identityChanged { marqueeOffset = 0 }
        if value.status == .running && value.effect == .marquee {
            marqueeColumns = MarqueeText.columns(for: MarqueeText.message(for: value))
        }
        if value.status == .running && (lastSampleAt != value.updatedAt || metricChanged) {
            let normalized = value.activity.intensity(for: value.metric, threshold: value.threshold)
            history.append(normalized)
            if history.count > 120 { history.removeFirst(history.count - 120) }
        }
        lastSampleAt = value.updatedAt
        snapshot = value
        updateTimer()
        needsDisplay = true
    }

    func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        NSBezierPath(rect: bounds).fill()
        let elapsed = animationElapsed
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: renderingRect.minX, yBy: renderingRect.minY)
        transform.concat()
        NSBezierPath(rect: visualBounds).addClip()
        if snapshot.status == .running {
            let activity = snapshot.activity.intensity(for: snapshot.metric, threshold: snapshot.threshold)
            switch snapshot.effect {
            case .kitt: drawKitt()
            case .disk: drawLED(activity, elapsed)
            case .heartbeat: drawHeartbeat(elapsed, activity)
            case .vu: drawVU(activity)
            case .peak: drawPeakVU(activity)
            case .scope: drawScope()
            case .waterfall: drawWaterfall()
            case .duplex: drawDuplex()
            case .marquee: drawMarquee()
            case .comet: drawComet(activity)
            case .equalizer: drawEqualizer()
            case .sparkline: drawSparkline()
            case .centerVU: drawCenterVU(activity)
            case .digital: drawDigital(activity)
            case .signal: drawSignal(activity, elapsed)
            case .wave: drawWave(activity, elapsed)
            case .radar: drawRadar(activity, elapsed)
            case .particles: drawParticles(activity, elapsed)
            case .breathe: drawBreathe(activity, elapsed)
            case .twin: drawTwin(activity, elapsed)
            }
        } else {
            drawStatus(elapsed)
        }
        if sideLabel != nil { drawMetricLabel() }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawMarquee() {
        guard !marqueeColumns.isEmpty else { return }
        let pitch: CGFloat = 3.5
        let dotSize: CGFloat = 2.5
        let shifted = Int(floor(marqueeOffset / pitch))
        let fraction = marqueeOffset.truncatingRemainder(dividingBy: pitch)
        let visibleColumns = Int(ceil(visualBounds.width / pitch)) + 2
        let bottom = (visualBounds.height - pitch * 7) / 2
        let bands = snapshot.palette == .rainbow ? 12 : 1
        let paths = (0..<bands).map { _ in NSBezierPath() }
        for column in -1...visibleColumns {
            let index = MarqueeText.circularColumn(column, offset: shifted, columnCount: marqueeColumns.count)
            let bits = marqueeColumns[index]
            if bits == 0 { continue }
            let x = CGFloat(column) * pitch - fraction
            let band = snapshot.palette == .rainbow
                ? min(bands - 1, max(0, Int(CGFloat(max(0, column)) / max(1, visualBounds.width / pitch) * CGFloat(bands))))
                : 0
            for row in 0..<7 where bits & (1 << row) != 0 {
                let y = bottom + CGFloat(6 - row) * pitch
                paths[band].appendRect(NSRect(x: x, y: y, width: dotSize, height: dotSize))
            }
        }
        for (index, path) in paths.enumerated() {
            paletteColor(position: Double(index) / Double(bands), original: NSColor(calibratedRed: 1, green: 0.65, blue: 0.06, alpha: 1)).setFill()
            path.fill()
        }
    }

    private func drawMetricLabel() {
        guard let sideLabel else { return }
        let measured = (sideLabel as NSString).size(withAttributes: [.font: labelFont]).width
        guard let layout = MetricLabelLayout.make(availableWidth: Double(visualBounds.width), textWidth: Double(measured)) else { return }
        let area = NSRect(x: visualBounds.minX + CGFloat(layout.x), y: visualBounds.midY - 10, width: CGFloat(layout.width), height: 20)
        let badge = NSBezierPath(roundedRect: area, xRadius: 5, yRadius: 5)
        NSColor(calibratedWhite: 0.025, alpha: 0.94).setFill()
        badge.fill()
        NSColor.white.withAlphaComponent(0.28).setStroke()
        badge.lineWidth = 0.5
        badge.stroke()
        let style: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: NSColor.white
        ]
        let text = NSAttributedString(string: sideLabel, attributes: style)
        let size = text.size()
        text.draw(at: NSPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2))
    }

    private func paletteColor(position: Double, original: NSColor) -> NSColor {
        switch snapshot.palette {
        case .original: return original
        case .amber: return NSColor(calibratedRed: 1, green: 0.65, blue: 0.04, alpha: 1)
        case .red: return NSColor(calibratedRed: 1, green: 0.12, blue: 0.10, alpha: 1)
        case .green: return NSColor(calibratedRed: 0.12, green: 1, blue: 0.29, alpha: 1)
        case .cyan: return NSColor(calibratedRed: 0.08, green: 0.87, blue: 1, alpha: 1)
        case .violet: return NSColor(calibratedRed: 0.77, green: 0.34, blue: 1, alpha: 1)
        case .custom: return customColor()
        case .rainbow:
            let hue = CGFloat(position - floor(position))
            return NSColor(calibratedHue: hue, saturation: 0.88, brightness: 1, alpha: 1)
        }
    }

    private func customColor() -> NSColor {
        let hex = snapshot.customColorHex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, let number = UInt32(hex, radix: 16) else { return .systemRed }
        return NSColor(
            calibratedRed: CGFloat((number >> 16) & 255) / 255,
            green: CGFloat((number >> 8) & 255) / 255,
            blue: CGFloat(number & 255) / 255,
            alpha: 1
        )
    }

    private func drawComet(_ activity: Double) {
        let head = pingPongPosition(progress: scannerProgress, segmentCount: count)
        let trailLength = 3 + activity * 15
        for index in 0..<count {
            let distance = abs(Double(index) - head)
            let level = exp(-distance / max(1, trailLength / 3))
            fill(segmentRect(index), color: tintedColor(
                NSColor(calibratedRed: level, green: level * 0.45, blue: 0.08, alpha: 1),
                amount: level,
                position: Double(index) / Double(count)
            ))
        }
    }

    private func drawCenterVU(_ activity: Double) {
        let half = Double(count) / 2
        let lit = Int(ceil(activity * half))
        for index in 0..<count {
            let distance = index < count / 2 ? count / 2 - 1 - index : index - count / 2
            fill(segmentRect(index), color: meterColor(index, lit: distance < lit))
        }
    }

    private func drawDigital(_ activity: Double) {
        let percentage = Int((activity * 100).rounded())
        let font = NSFont.monospacedDigitSystemFont(ofSize: 18, weight: .bold)
        let caption = "\(percentage)%" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: paletteColor(position: 0.5, original: .systemGreen)
        ]
        let size = caption.size(withAttributes: attributes)
        caption.draw(at: NSPoint(x: visualBounds.midX - size.width / 2, y: visualBounds.midY - size.height / 2 + 3), withAttributes: attributes)
        let bar = NSRect(x: 0, y: 1, width: visualBounds.width * CGFloat(activity), height: 3)
        fill(bar, color: paletteColor(position: activity, original: .systemGreen))
    }

    private func drawSignal(_ activity: Double, _ elapsed: Double) {
        let frequency = 0.5 + activity * 3.5
        let phase = (elapsed * frequency).truncatingRemainder(dividingBy: 1)
        let level = activity > 0 ? exp(-phase * 8) : 0
        for index in 0..<count {
            let emphasis = 0.7 + 0.3 * cos(Double(index) / Double(max(1, count - 1)) * .pi * 2)
            let value = level * emphasis
            let original = NSColor(calibratedRed: 0.02 + value * 0.94, green: value * 0.16, blue: 0.02, alpha: 1)
            fill(segmentRect(index), color: tintedColor(original, amount: value, position: Double(index) / Double(count)))
        }
    }

    private func drawWave(_ activity: Double, _ elapsed: Double) {
        for index in 0..<count {
            let position = Double(index) / Double(count - 1)
            let level = waveLevel(position: position, elapsed: elapsed, activity: activity)
            let height = max(2, CGFloat(level) * (visualBounds.height - 4))
            fill(segmentRect(index, height: height), color: emissionColor(.systemCyan, amount: 0.08 + level * 0.92, position: position))
        }
    }

    private func drawRadar(_ activity: Double, _ elapsed: Double) {
        let head = (elapsed * (0.08 + activity * 0.6)).truncatingRemainder(dividingBy: 1)
        for index in 0..<count {
            let position = Double(index) / Double(count)
            let distance = (head - position + 1).truncatingRemainder(dividingBy: 1)
            let level = activity * exp(-distance * 12)
            fill(segmentRect(index), color: emissionColor(.systemGreen, amount: 0.04 + level * 0.96, position: position))
        }
    }

    private func drawParticles(_ activity: Double, _ elapsed: Double) {
        // Deterministic particle tracks; no random measurements are introduced.
        for index in 0..<count {
            fill(segmentRect(index), color: NSColor(calibratedWhite: 0.025, alpha: 1))
        }
        let particles = Int(ceil(activity * 14))
        for index in 0..<particles {
            let seed = Double(index)
            let phase = (seed * 0.618 + elapsed * (0.08 + activity * 0.35) * (1 + seed * 0.035)).truncatingRemainder(dividingBy: 1)
            let size: CGFloat = 3 + CGFloat(activity) * 3
            let y = visualBounds.midY + CGFloat(sin(seed * 2.4 + elapsed)) * max(0, visualBounds.height / 2 - size)
            fill(NSRect(x: CGFloat(phase) * max(0, visualBounds.width - size), y: y - size / 2, width: size, height: size), color: paletteColor(position: phase, original: .systemOrange))
        }
    }

    private func drawBreathe(_ activity: Double, _ elapsed: Double) {
        let breath = 0.25 + 0.75 * (0.5 - 0.5 * cos(elapsed * (0.8 + activity * 4)))
        for index in 0..<count {
            let position = Double(index) / Double(count - 1)
            let level = activity * breath * (0.55 + 0.45 * sin(position * .pi))
            fill(segmentRect(index), color: emissionColor(.systemPurple, amount: 0.025 + level * 0.975, position: position))
        }
    }

    private func drawTwin(_ activity: Double, _ elapsed: Double) {
        let head = pingPongPosition(progress: scannerProgress, segmentCount: count)
        for index in 0..<count {
            let distance = min(abs(Double(index) - head), abs(Double(index) - (Double(count - 1) - head)))
            let level = exp(-pow(distance / 1.6, 2))
            fill(segmentRect(index), color: emissionColor(.systemRed, amount: 0.025 + 0.975 * level, position: Double(index) / Double(count - 1)))
        }
    }

    private func drawEqualizer() {
        let values = normalizedHistory(history, count: count)
        let barHeight = max(1, visualBounds.height - 6)
        for (index, value) in values.enumerated() {
            let height = CGFloat(max(0.04, value)) * barHeight
            let rect = segmentRect(index, height: height, y: 3)
            fill(rect, color: tintedColor(.systemGreen, amount: max(0.08, value), position: Double(index) / Double(count)))
        }
    }

    private func drawSparkline() {
        let values = normalizedHistory(history, count: 120)
        guard values.count > 1 else { return }
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0, y: 2))
        for (index, value) in values.enumerated() {
            path.line(to: NSPoint(x: CGFloat(index) / CGFloat(values.count - 1) * visualBounds.width,
                                  y: 2 + CGFloat(value) * (visualBounds.height - 4)))
        }
        path.line(to: NSPoint(x: visualBounds.width, y: 2))
        path.close()
        paletteColor(position: 0.5, original: .systemTeal).withAlphaComponent(0.27).setFill()
        path.fill()
        drawLine(values: values, color: paletteColor(position: 0.5, original: .systemTeal))
    }

    private func tintedColor(_ original: NSColor, amount: Double, position: Double) -> NSColor {
        guard snapshot.palette != .original else { return original }
        let color = paletteColor(position: position, original: original)
        let level = CGFloat(min(1, max(0, amount)))
        return NSColor(
            calibratedRed: 0.018 + color.redComponent * level * 0.95,
            green: 0.018 + color.greenComponent * level * 0.95,
            blue: 0.018 + color.blueComponent * level * 0.95,
            alpha: 1
        )
    }

    private func segmentRect(_ index: Int, height: CGFloat? = nil, y: CGFloat? = nil) -> NSRect {
        let position = segmentGeometry(index: index, count: count, availableWidth: Double(visualBounds.width), gap: Double(gap))
        let height = height ?? min(24, visualBounds.height - 6)
        return NSRect(
            x: visualBounds.minX + CGFloat(position.x),
            y: y ?? (visualBounds.height - height) / 2,
            width: CGFloat(position.width),
            height: height
        )
    }

    private func fill(_ rect: NSRect, color: NSColor) {
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 1.6, yRadius: 1.6).fill()
    }

    private func drawStatus(_ elapsed: Double) {
        for index in 0..<count {
            let color: NSColor
            switch snapshot.status {
            case .idle: color = NSColor(calibratedWhite: 0.025, alpha: 1)
            case .done: color = NSColor(calibratedRed: 0.01, green: 0.78, blue: 0.28, alpha: 1)
            case .error: color = Int(elapsed * 3) % 2 == 0 ? .systemRed : NSColor(calibratedRed: 0.12, green: 0, blue: 0, alpha: 1)
            case .attention: color = .systemOrange
            case .running: color = .black
            }
            fill(segmentRect(index), color: color)
        }
    }

    private func drawKitt() {
        let head = pingPongPosition(progress: scannerProgress, segmentCount: count)
        let directionForward = scannerProgress.truncatingRemainder(dividingBy: Double((count - 1) * 2)) <= Double(count - 1)
        for index in 0..<count {
            let x = Double(index)
            let distance = abs(x - head)
            let tail = directionForward ? head - x : x - head
            let beam = min(1, exp(-pow(distance / 1.2, 2)) + (tail > 0 ? 0.65 * exp(-tail / 4.5) : 0))
            let original = NSColor(calibratedRed: 0.025 + 0.97 * beam, green: 0.025 * beam, blue: 0.01 * beam, alpha: 1)
            fill(segmentRect(index), color: tintedColor(original, amount: beam, position: Double(index) / Double(count)))
        }
    }

    private func drawLED(_ activity: Double, _ elapsed: Double) {
        let pulse = 0.88 + 0.12 * abs(sin(elapsed * 12))
        for index in 0..<count {
            let value = index < 8 ? activity * pulse : 0
            let original = NSColor(calibratedRed: 0.025 + 0.97 * value, green: 0.02 + value * 0.06, blue: 0, alpha: 1)
            fill(segmentRect(index), color: tintedColor(original, amount: value, position: Double(index) / Double(count)))
        }
    }

    private func drawVU(_ activity: Double) {
        let lit = Int((activity * Double(count)).rounded(.up))
        for index in 0..<count {
            fill(segmentRect(index), color: meterColor(index, lit: index < lit))
        }
    }

    private func drawPeakVU(_ activity: Double) {
        let lit = Int((activity * Double(count)).rounded(.up))
        let peak = Int(((history.suffix(10).max() ?? 0) * Double(count)).rounded(.up))
        for index in 0..<count {
            let color = index == min(count - 1, max(0, peak - 1)) && peak > 0
                ? NSColor.white
                : meterColor(index, lit: index < lit)
            fill(segmentRect(index), color: color)
        }
    }

    private func meterColor(_ index: Int, lit: Bool) -> NSColor {
        guard lit else { return NSColor(calibratedWhite: 0.055, alpha: 1) }
        if snapshot.palette != .original {
            return tintedColor(.white, amount: 1, position: Double(index) / Double(count))
        }
        if index >= 41 { return NSColor(calibratedRed: 1, green: 0.13, blue: 0.12, alpha: 1) }
        if index >= 32 { return NSColor(calibratedRed: 1, green: 0.69, blue: 0.05, alpha: 1) }
        return NSColor(calibratedRed: 0.05, green: 0.87, blue: 0.40, alpha: 1)
    }

    private func drawScope() {
        let values = normalizedHistory(history, count: 120)
        drawLine(values: values, color: paletteColor(position: 0.3, original: NSColor(calibratedRed: 0.16, green: 0.94, blue: 0.66, alpha: 1)))
    }

    private func drawLine(values: [Double], color: NSColor) {
        guard values.count >= 2 else { return }
        let path = NSBezierPath()
        path.lineWidth = 2.0
        path.lineJoinStyle = .round
        for (index, value) in values.enumerated() {
            let x = CGFloat(index) / CGFloat(values.count - 1) * visualBounds.width
            let y = 3 + CGFloat(value) * (visualBounds.height - 6)
            let point = NSPoint(x: x, y: y)
            if index == 0 { path.move(to: point) } else { path.line(to: point) }
        }
        color.setStroke()
        path.stroke()
    }

    private func drawWaterfall() {
        let levels = normalizedHistory(history, count: count)
        for (index, value) in levels.enumerated() {
            let color = NSColor(calibratedRed: 0.03 + value * 0.92, green: 0.05 + value * 0.58, blue: 0.17 + (1 - value) * 0.16, alpha: 1)
            fill(segmentRect(index), color: tintedColor(color, amount: value, position: Double(index) / Double(count)))
        }
    }

    private func drawDuplex() {
        let (originalRead, originalWrite) = snapshot.activity.componentIntensities(for: snapshot.metric)
        let (read, write): (Double, Double)
        if snapshot.threshold.enabled {
            let scale = snapshot.metric.referenceMaximum
            read = snapshot.threshold.normalized(originalRead * scale, for: snapshot.metric)
            write = snapshot.threshold.normalized(originalWrite * scale, for: snapshot.metric)
        } else {
            read = originalRead
            write = originalWrite
        }
        let first = Int(ceil(read * Double(count)))
        let second = Int(ceil(write * Double(count)))
        let height = min((visualBounds.height - 8) / 2, 10)
        for index in 0..<count {
            let top = index < first
                ? NSColor(calibratedRed: 0.03, green: 0.83, blue: 0.98, alpha: 1)
                : NSColor(calibratedWhite: 0.05, alpha: 1)
            let bottom = index < second
                ? NSColor(calibratedRed: 1, green: 0.43, blue: 0.07, alpha: 1)
                : NSColor(calibratedWhite: 0.05, alpha: 1)
            fill(segmentRect(index, height: height, y: visualBounds.midY + 2), color: index < first ? tintedColor(top, amount: 1, position: Double(index) / Double(count)) : top)
            fill(segmentRect(index, height: height, y: visualBounds.midY - height - 2), color: index < second ? tintedColor(bottom, amount: 1, position: Double(index) / Double(count)) : bottom)
        }
    }

    private func drawHeartbeat(_ elapsed: Double, _ activity: Double) {
        let path = NSBezierPath()
        path.lineWidth = 2.2
        path.lineJoinStyle = .round
        for step in 0...240 {
            let x = CGFloat(step) / 240 * visualBounds.width
            let phase = (Double(x / visualBounds.width) * 2.4 - elapsed / 1.3).truncatingRemainder(dividingBy: 1)
            let normalized = phase < 0 ? phase + 1 : phase
            let y = visualBounds.midY + CGFloat(beat(normalized) * activity) * visualBounds.height * 0.40
            let point = NSPoint(x: x, y: y)
            if step == 0 { path.move(to: point) } else { path.line(to: point) }
        }
        NSColor(calibratedRed: 0.17, green: 0, blue: 0.04, alpha: 1).setStroke()
        let glow = path.copy() as? NSBezierPath ?? path
        glow.lineWidth = 6
        glow.stroke()
        paletteColor(position: 0.6, original: NSColor(calibratedRed: 0.97, green: 0.08, blue: 0.20, alpha: 1)).setStroke()
        path.stroke()
    }

    private func beat(_ phase: Double) -> Double {
        let points: [(Double, Double)] = [
            (0, 0), (0.12, 0), (0.17, 0.13), (0.21, 0),
            (0.245, -0.25), (0.27, 0.94), (0.30, -0.48),
            (0.34, 0), (0.46, 0), (0.54, 0.18), (0.64, 0), (1, 0)
        ]
        for index in 1..<points.count where phase <= points[index].0 {
            let earlier = points[index - 1]
            let later = points[index]
            let mix = (phase - earlier.0) / (later.0 - earlier.0)
            return earlier.1 + (later.1 - earlier.1) * mix
        }
        return 0
    }

    private func emissionColor(_ original: NSColor, amount: Double, position: Double) -> NSColor {
        let color = paletteColor(position: position, original: original).usingColorSpace(.deviceRGB) ?? .white
        let level = CGFloat(min(1, max(0, amount)))
        return NSColor(calibratedRed: color.redComponent * level, green: color.greenComponent * level,
                       blue: color.blueComponent * level, alpha: 1)
    }

    // One clock drives both the global bar and the preview. Tests can advance it
    // deterministically and verify motion, not merely that a frame can render.
    func advanceAnimation(by interval: Double) {
        guard interval.isFinite, interval > 0 else { return }
        animationElapsed += interval
        if snapshot.status == .running && snapshot.effect == .marquee {
            marqueeOffset += CGFloat(interval) * 58
            let length = CGFloat(marqueeColumns.count) * 3.5
            if length > 0 { marqueeOffset = marqueeOffset.truncatingRemainder(dividingBy: length) }
        }
        if snapshot.status == .running && [.kitt, .comet, .twin].contains(snapshot.effect) {
            scannerProgress += interval * kittElementsPerSecond(activity: snapshot.activity.intensity(for: snapshot.metric, threshold: snapshot.threshold))
        }
        needsDisplay = true
    }

    private func updateTimer() {
        let animated = animates && (runsWithoutWindow || window != nil) && (snapshot.status == .running || snapshot.status == .error)
        if animated && animationTimer == nil {
            lastTick = ProcessInfo.processInfo.systemUptime
            let timer = Timer(timeInterval: 1 / 30, repeats: true) { [weak self] _ in
                guard let self else { return }
                let now = ProcessInfo.processInfo.systemUptime
                let elapsed = max(0, min(0.1, now - self.lastTick))
                self.lastTick = now
                self.advanceAnimation(by: elapsed)
            }
            RunLoop.main.add(timer, forMode: .common)
            animationTimer = timer
        } else if !animated {
            stopAnimation()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsDisplay = true
        updateTimer()
    }
}
