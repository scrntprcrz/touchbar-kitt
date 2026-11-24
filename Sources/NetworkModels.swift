import Foundation

struct NetworkCounters: Equatable {
    let received: UInt64
    let sent: UInt64
}

struct NetworkFrame {
    let timestamp: TimeInterval
    let countersByPID: [Int32: NetworkCounters]
}

struct NetworkRates: Equatable {
    var receivedBps: Double = 0
    var sentBps: Double = 0
    var visiblePIDs: Int = 0
    var available = false
}

func networkRates(
    current: [ProcessKey: NetworkCounters],
    previous: [ProcessKey: NetworkCounters],
    elapsed: Double,
    hasBaseline: Bool
) -> NetworkRates {
    var result = NetworkRates(visiblePIDs: current.count, available: !current.isEmpty)
    guard hasBaseline && elapsed > 0 else { return result }
    var inBytes: UInt64 = 0
    var outBytes: UInt64 = 0
    for (key, counters) in current {
        guard let old = previous[key] else { continue }
        inBytes = inBytes &+ (counters.received >= old.received ? counters.received - old.received : 0)
        outBytes = outBytes &+ (counters.sent >= old.sent ? counters.sent - old.sent : 0)
    }
    result.receivedBps = Double(inBytes) / elapsed
    result.sentBps = Double(outBytes) / elapsed
    return result
}
