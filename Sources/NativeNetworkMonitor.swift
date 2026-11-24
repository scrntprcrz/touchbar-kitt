import Foundation

final class NativeNetworkMonitor {
    var onFrame: ((NetworkFrame) -> Void)?
    var onFailure: ((String) -> Void)?

    private let queue = DispatchQueue(label: "dev.touchbarkitt.network-reader", qos: .utility)
    private var timer: Timer?
    private var handle: UnsafeMutableRawPointer?
    private var generation = 0
    private var watchedPIDs = Set<Int32>()
    private var enabled = false

    func setWatchedPIDs(_ ids: [Int32]) {
        watchedPIDs = Set(ids.filter { $0 > 0 })
    }

    func start() {
        stop()
        enabled = true
        generation += 1
        let version = generation
        queue.async { [weak self] in
            guard let self else { return }
            let handle = KITTNetworkCreate()
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    KITTNetworkDestroy(handle)
                    return
                }
                guard self.enabled, self.generation == version else {
                    self.queue.async { KITTNetworkDestroy(handle) }
                    return
                }
                guard let handle else {
                    self.onFailure?("NetworkStatistics no disponible en este macOS")
                    return
                }
                self.handle = handle
                let timer = Timer(timeInterval: 2.5, repeats: true) { [weak self] _ in
                    self?.sample(handle: handle, generation: version)
                }
                RunLoop.main.add(timer, forMode: .common)
                self.timer = timer
                self.sample(handle: handle, generation: version)
            }
        }
    }

    func stop() {
        generation += 1
        enabled = false
        timer?.invalidate()
        timer = nil
        if let handle {
            self.handle = nil
            queue.async { KITTNetworkDestroy(handle) }
        }
    }

    private func sample(handle: UnsafeMutableRawPointer, generation version: Int) {
        let requested = watchedPIDs
        queue.async { [weak self] in
            var output = [KITTNetworkCounter](repeating: KITTNetworkCounter(), count: 4096)
            let count = output.withUnsafeMutableBufferPointer { pointer in
                KITTNetworkRead(handle, pointer.baseAddress, Int32(pointer.count))
            }
            let counters: [Int32: NetworkCounters] = count < 0 ? [:] : Dictionary(
                uniqueKeysWithValues: output.prefix(Int(count)).filter { requested.contains($0.pid) }.map {
                    ($0.pid, NetworkCounters(received: $0.received, sent: $0.sent))
                }
            )
            DispatchQueue.main.async { [weak self] in
                guard let self, self.enabled, self.generation == version else { return }
                if count < 0 {
                    self.onFailure?("La lectura de NetworkStatistics falló")
                } else {
                    self.onFrame?(NetworkFrame(timestamp: ProcessInfo.processInfo.systemUptime, countersByPID: counters))
                }
            }
        }
    }
}
