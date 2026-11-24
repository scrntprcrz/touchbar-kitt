import Foundation

struct ProcessCounters {
    let cpuNanoseconds: UInt64
    let residentBytes: UInt64
    let threadCount: UInt64
    let contextSwitches: UInt64
    let diskReadBytes: UInt64
    let diskWriteBytes: UInt64
    let diskReadable: Bool
    let energyNanojoules: UInt64
    let energyReadable: Bool
}

struct ProcessObservation {
    let sample: ActivitySample
    let isAlive: Bool
}

private struct MonitoredRoot {
    let key: ProcessKey
    let includeChildren: Bool
    let bundlePrefix: String?
}

private struct ProcessScan {
    let observation: ProcessObservation
    let keys: Set<ProcessKey>
    let readings: [ProcessKey: ProcessCounters]
    let timestamp: TimeInterval
    let residentBytes: UInt64
    let threadCount: UInt64
    let contextSwitches: UInt64
    let networkReadings: [ProcessKey: NetworkCounters]
    let networkTimestamp: TimeInterval?
    let networkRates: NetworkRates
    let gpuReadings: [ProcessKey: UInt64]
}

final class ProcessTreeMonitor {
    var onObservation: ((ProcessObservation) -> Void)?
    var onNetworkIssue: ((String) -> Void)?

    private let capacity = 32768
    private let queue = DispatchQueue(label: "dev.touchbarkitt.process-sampling", qos: .utility)
    private let networkMonitor = NativeNetworkMonitor()
    private var timer: Timer?
    private var roots: [MonitoredRoot] = []
    private var trackedKeys = Set<ProcessKey>()
    private var previousReadings: [ProcessKey: ProcessCounters] = [:]
    private var previousTime: TimeInterval?
    private var previousResidentBytes: UInt64?
    private var networkFrame: NetworkFrame?
    private var previousNetworkReadings: [ProcessKey: NetworkCounters] = [:]
    private var previousNetworkTimestamp: TimeInterval?
    private var previousNetworkRates = NetworkRates()
    private var previousGpuReadings: [ProcessKey: UInt64] = [:]
    private var selectedMetric: ProcessMetric = .cpu
    private var generation = 0
    private var isSampling = false

    init() {
        networkMonitor.onFrame = { [weak self] frame in
            self?.networkFrame = frame
        }
        networkMonitor.onFailure = { [weak self] message in
            self?.networkFrame = nil
            self?.onNetworkIssue?(message)
        }
    }

    func isAccessible(pid: Int32) -> Bool {
        identity(for: pid) != nil
    }

    func start(pid: Int32, includeChildren: Bool, includeAppHelpers: Bool, metric: ProcessMetric) -> Bool {
        start(targets: [WatchedProcess(pid: pid, name: "PID \(pid)", includeChildren: includeChildren, includeAppHelpers: includeAppHelpers)], metric: metric)
    }

    func start(targets: [WatchedProcess], metric: ProcessMetric) -> Bool {
        let selected = targets.compactMap { target -> MonitoredRoot? in
            guard let identity = identity(for: target.pid) else { return nil }
            return MonitoredRoot(
                key: identity.key,
                includeChildren: target.includeChildren,
                bundlePrefix: target.includeAppHelpers ? bundlePrefix(for: target.pid) : nil
            )
        }
        guard !selected.isEmpty else { return false }
        stop()
        roots = selected
        selectedMetric = metric
        trackedKeys = Set(selected.map(\.key))
        networkMonitor.setWatchedPIDs(selected.map { $0.key.pid })
        if metric.needsNetworkSampler { networkMonitor.start() }
        let interval = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.scheduleSample() }
        RunLoop.main.add(interval, forMode: .common)
        timer = interval
        scheduleSample()
        return true
    }

    func configureMetric(_ metric: ProcessMetric) {
        guard selectedMetric != metric else { return }
        let previousMetric = selectedMetric
        selectedMetric = metric
        if previousMetric.needsNetworkSampler { networkMonitor.stop() }
        if metric.needsNetworkSampler, !roots.isEmpty {
            networkMonitor.setWatchedPIDs(trackedKeys.map(\.pid))
            networkMonitor.start()
        }
        networkFrame = nil
        previousNetworkReadings.removeAll()
        previousNetworkTimestamp = nil
        previousNetworkRates = NetworkRates()
        previousGpuReadings.removeAll()
    }

    func stop() {
        generation += 1
        timer?.invalidate()
        timer = nil
        networkMonitor.stop()
        roots.removeAll()
        trackedKeys.removeAll()
        previousReadings.removeAll()
        previousTime = nil
        previousResidentBytes = nil
        networkFrame = nil
        previousNetworkReadings.removeAll()
        previousNetworkTimestamp = nil
        previousNetworkRates = NetworkRates()
        previousGpuReadings.removeAll()
        isSampling = false
    }

    private func scheduleSample() {
        guard !isSampling, !roots.isEmpty else { return }
        isSampling = true
        let version = generation
        let known = trackedKeys
        let previous = previousReadings
        let previousInstant = previousTime
        let previousMemory = previousResidentBytes
        let selectedRoots = roots
        let currentNetwork = networkFrame
        let olderNetwork = previousNetworkReadings
        let olderNetworkTime = previousNetworkTimestamp
        let olderNetworkRates = previousNetworkRates
        let olderGPU = previousGpuReadings
        let captureGPU = selectedMetric.needsGPUSampler
        queue.async { [weak self] in
            guard let self else { return }
            let result = self.scan(
                roots: selectedRoots,
                tracked: known,
                previous: previous,
                previousTime: previousInstant,
                previousMemory: previousMemory,
                networkFrame: currentNetwork,
                previousNetwork: olderNetwork,
                previousNetworkTime: olderNetworkTime,
                previousNetworkRates: olderNetworkRates,
                previousGPU: olderGPU,
                captureGPU: captureGPU
            )
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == version else { return }
                self.isSampling = false
                self.trackedKeys = result.keys
                self.networkMonitor.setWatchedPIDs(result.keys.map(\.pid))
                self.previousReadings = result.readings
                self.previousTime = result.timestamp
                self.previousResidentBytes = result.residentBytes
                self.previousNetworkReadings = result.networkReadings
                self.previousNetworkTimestamp = result.networkTimestamp
                self.previousNetworkRates = result.networkRates
                self.previousGpuReadings = result.gpuReadings
                self.onObservation?(result.observation)
                if !result.observation.isAlive { self.stop() }
            }
        }
    }

    private func scan(
        roots: [MonitoredRoot],
        tracked: Set<ProcessKey>,
        previous: [ProcessKey: ProcessCounters],
        previousTime: TimeInterval?,
        previousMemory: UInt64?,
        networkFrame: NetworkFrame?,
        previousNetwork: [ProcessKey: NetworkCounters],
        previousNetworkTime: TimeInterval?,
        previousNetworkRates: NetworkRates,
        previousGPU: [ProcessKey: UInt64],
        captureGPU: Bool
    ) -> ProcessScan {
        let now = ProcessInfo.processInfo.systemUptime
        let identities = listIdentities()
        var active = Set<ProcessKey>()
        let bundlePrefixes = roots.compactMap(\.bundlePrefix)
        for root in roots {
            active.formUnion(processFamily(root: root.key, tracked: tracked, identities: identities, includeChildren: root.includeChildren))
        }
        if !bundlePrefixes.isEmpty {
            for identity in identities {
                if let candidate = processPath(for: identity.pid), bundlePrefixes.contains(where: { candidate.hasPrefix($0) }) {
                    active.insert(identity.key)
                }
            }
        }
        guard !active.isEmpty else {
            return ProcessScan(
                observation: ProcessObservation(sample: .zero, isAlive: false),
                keys: [], readings: [:], timestamp: now, residentBytes: 0,
                threadCount: 0, contextSwitches: 0,
                networkReadings: [:], networkTimestamp: nil, networkRates: NetworkRates(), gpuReadings: [:]
            )
        }

        let elapsed = max(0.001, now - (previousTime ?? now))
        var cpuTicks: UInt64 = 0
        var readBytes: UInt64 = 0
        var writeBytes: UInt64 = 0
        var resident: UInt64 = 0
        var threadCount: UInt64 = 0
        var contextSwitches: UInt64 = 0
        var readable = 0
        var diskReadable = 0
        var energyReadable = 0
        var energyDelta: UInt64 = 0
        var currentReadings: [ProcessKey: ProcessCounters] = [:]

        for key in active {
            guard let counters = counters(for: key.pid) else { continue }
            readable += 1
            resident = resident &+ counters.residentBytes
            threadCount = threadCount &+ counters.threadCount
            currentReadings[key] = counters
            if counters.diskReadable { diskReadable += 1 }
            if counters.energyReadable { energyReadable += 1 }
            guard let prior = previous[key] else { continue }
            if counters.energyReadable && prior.energyReadable {
                energyDelta = energyDelta &+ maxDelta(counters.energyNanojoules, prior.energyNanojoules)
            }
            cpuTicks = cpuTicks &+ maxDelta(counters.cpuNanoseconds, prior.cpuNanoseconds)
            contextSwitches = contextSwitches &+ maxDelta(counters.contextSwitches, prior.contextSwitches)
            if counters.diskReadable && prior.diskReadable {
                readBytes = readBytes &+ maxDelta(counters.diskReadBytes, prior.diskReadBytes)
                writeBytes = writeBytes &+ maxDelta(counters.diskWriteBytes, prior.diskWriteBytes)
            }
        }

        var netReadings = previousNetwork.filter { active.contains($0.key) }
        var netTime = previousNetworkTime
        var netRates = previousNetworkRates
        if let frame = networkFrame {
            if frame.timestamp != previousNetworkTime {
                var collected: [ProcessKey: NetworkCounters] = [:]
                for key in active {
                    if let counters = frame.countersByPID[key.pid] { collected[key] = counters }
                }
                netRates = networkRates(
                    current: collected,
                    previous: previousNetwork,
                    elapsed: max(0.001, frame.timestamp - (previousNetworkTime ?? frame.timestamp)),
                    hasBaseline: previousNetworkTime != nil
                )
                netReadings = collected
                netTime = frame.timestamp
            }
        } else {
            netRates = NetworkRates()
            netReadings.removeAll()
            netTime = nil
        }

        var gpuBuffer = [KITTGPUCounter](repeating: KITTGPUCounter(), count: 4096)
        let gpuCount = captureGPU ? gpuBuffer.withUnsafeMutableBufferPointer { pointer in
            KITTListGPUCounters(pointer.baseAddress, Int32(pointer.count))
        } : -1
        var gpuNow: [ProcessKey: UInt64] = [:]
        var gpuDelta: UInt64 = 0
        if gpuCount >= 0 {
            let gpuByPID = Dictionary(gpuBuffer.prefix(Int(gpuCount)).map { ($0.pid, $0.gpuNanoseconds) }, uniquingKeysWith: { _, new in new })
            for key in active {
                guard let value = gpuByPID[key.pid] else { continue }
                gpuNow[key] = value
                if let old = previousGPU[key] { gpuDelta = gpuDelta &+ maxDelta(value, old) }
            }
        }

        var sample = ActivitySample()
        sample.thermalState = thermalStateName(ProcessInfo.processInfo.thermalState)
        sample.gpuAvailable = gpuCount >= 0 && !gpuNow.isEmpty
        sample.gpuVisiblePIDs = gpuNow.count
        sample.gpuPercent = previousTime == nil ? 0 : Double(gpuDelta) / 1_000_000_000 / elapsed * 100
        sample.energyReadableCount = energyReadable
        sample.energyWatts = previousTime == nil ? 0 : Double(energyDelta) / 1_000_000_000 / elapsed
        sample.processCount = active.count
        sample.readableCount = readable
        sample.diskReadableCount = diskReadable
        sample.residentBytes = resident
        sample.threadCount = threadCount
        sample.networkAvailable = netRates.available
        sample.networkVisiblePIDs = netRates.visiblePIDs
        sample.networkReceivedBps = netRates.receivedBps
        sample.networkSentBps = netRates.sentBps
        if previousTime != nil {
            sample.cpuPercent = min(100_000, Double(cpuTicks) / 1_000_000_000 / elapsed * 100)
            sample.contextSwitchesPerSecond = Double(contextSwitches) / elapsed
            sample.diskReadBps = Double(readBytes) / elapsed
            sample.diskWriteBps = Double(writeBytes) / elapsed
            if let previousMemory {
                sample.memoryDeltaBps = (Double(resident) - Double(previousMemory)) / elapsed
            }
            sample.sampledSeconds = elapsed
        }
        return ProcessScan(
            observation: ProcessObservation(sample: sample, isAlive: true),
            keys: active, readings: currentReadings, timestamp: now, residentBytes: resident,
            threadCount: threadCount, contextSwitches: contextSwitches,
            networkReadings: netReadings, networkTimestamp: netTime, networkRates: netRates,
            gpuReadings: gpuNow
        )
    }

    private func processPath(for pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let count = buffer.withUnsafeMutableBufferPointer { pointer in
            KITTReadProcessPath(pid, pointer.baseAddress, Int32(pointer.count))
        }
        guard count > 0 else { return nil }
        return String(cString: buffer)
    }

    private func bundlePrefix(for pid: Int32) -> String? {
        guard let path = processPath(for: pid) else { return nil }
        return appBundlePrefix(path)
    }

    private func thermalStateName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "normal"
        case .fair: return "moderado"
        case .serious: return "alto"
        case .critical: return "crítico"
        @unknown default: return "desconocido"
        }
    }

    private func identity(for pid: Int32) -> ProcessIdentity? {
        var raw = KITTProcessIdentity()
        guard KITTReadProcessIdentity(pid, &raw) == 1 else { return nil }
        let stamp = raw.birthSeconds &* 1_000_000 &+ raw.birthMicroseconds
        return ProcessIdentity(pid: raw.pid, parentPID: raw.parentPID, born: stamp)
    }

    private func listIdentities() -> [ProcessIdentity] {
        var ids = [Int32](repeating: 0, count: capacity)
        let count = ids.withUnsafeMutableBufferPointer { buffer in
            KITTListProcessIDs(buffer.baseAddress, Int32(buffer.count))
        }
        guard count > 0 else { return [] }
        return ids.prefix(min(capacity, Int(count))).compactMap(identity(for:))
    }

    private func counters(for pid: Int32) -> ProcessCounters? {
        var raw = KITTProcessCounters()
        guard KITTReadProcessCounters(pid, &raw) == 1 else { return nil }
        return ProcessCounters(
            cpuNanoseconds: raw.cpuNanoseconds,
            residentBytes: raw.residentBytes,
            threadCount: raw.threadCount,
            contextSwitches: raw.contextSwitches,
            diskReadBytes: raw.diskReadBytes,
            diskWriteBytes: raw.diskWriteBytes,
            diskReadable: raw.diskReadable == 1,
            energyNanojoules: raw.energyNanojoules,
            energyReadable: raw.energyReadable == 1
        )
    }

    private func maxDelta(_ current: UInt64, _ previous: UInt64) -> UInt64 {
        current >= previous ? current - previous : 0
    }
}
