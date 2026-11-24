import Foundation

struct SignalThreshold: Codable, Equatable {
    var enabled: Bool = false
    var minimum: Double = 0
    var maximum: Double = 0

    func normalized(_ value: Double, for metric: ProcessMetric) -> Double {
        let minValue = enabled ? minimum : 0
        let maxValue = enabled ? maximum : metric.referenceMaximum
        guard value.isFinite, minValue.isFinite, maxValue.isFinite, minValue >= 0, maxValue > minValue else { return 0 }
        return min(1, max(0, (value - minValue) / (maxValue - minValue)))
    }

    static func saved(for metric: ProcessMetric) -> SignalThreshold {
        let defaults = UserDefaults.standard
        let key = "monitor.threshold.\(metric.rawValue)"
        let configured = defaults.bool(forKey: "\(key).enabled")
        let floor = defaults.object(forKey: "\(key).minimum") as? Double ?? 0
        let ceiling = defaults.object(forKey: "\(key).maximum") as? Double ?? metric.referenceMaximum
        guard floor.isFinite, ceiling.isFinite, floor >= 0, ceiling > floor else {
            return SignalThreshold(enabled: false, minimum: 0, maximum: metric.referenceMaximum)
        }
        return SignalThreshold(enabled: configured, minimum: floor, maximum: ceiling)
    }

    func save(for metric: ProcessMetric) {
        let defaults = UserDefaults.standard
        let key = "monitor.threshold.\(metric.rawValue)"
        defaults.set(enabled, forKey: "\(key).enabled")
        defaults.set(minimum, forKey: "\(key).minimum")
        defaults.set(maximum, forKey: "\(key).maximum")
    }
}
