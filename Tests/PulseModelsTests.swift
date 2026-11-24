import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

var sample = ActivitySample()
sample.cpuPercent = 50
expect(abs(sample.intensity(for: .cpu) - 0.5) < 0.001, "CPU 50%=0.5")
sample.cpuPercent = 350
expect(sample.intensity(for: .cpu) == 1, "CPU saturates at one core")
sample.diskReadBps = 2 * 1024 * 1024
sample.diskWriteBps = 2 * 1024 * 1024
expect(sample.intensity(for: .disk) == 1, "Disk 4MiB/s=1")
sample.memoryDeltaBps = -32 * 1024 * 1024
expect(abs(sample.intensity(for: .memory) - 0.5) < 0.001, "RAM delta 32MiB/s=0.5")
expect(PulseEffect.allCases.count == 20, "twenty effects")
expect(ProcessMetric.allCases.count == 8, "eight metrics")
expect(HTTPRequestLine.parse("GET /watch?pid=123&metric=cpu HTTP/1.1")?.parameters["pid"] == "123", "HTTP parse")
print("Model tests passed")

let root = ProcessKey(pid: 100, born: 1000)
let child = ProcessKey(pid: 101, born: 1001)
let grandchild = ProcessKey(pid: 102, born: 1002)
let family = [
    ProcessIdentity(pid: 100, parentPID: 1, born: 1000),
    ProcessIdentity(pid: 101, parentPID: 100, born: 1001),
    ProcessIdentity(pid: 102, parentPID: 101, born: 1002),
    ProcessIdentity(pid: 999, parentPID: 1, born: 9999)
]
expect(processFamily(root: root, tracked: [root], identities: family, includeChildren: true) == [root, child, grandchild], "recursive child discovery")
expect(processFamily(root: root, tracked: [root], identities: family, includeChildren: false) == [root], "root only")
let reparented = [ProcessIdentity(pid: 101, parentPID: 1, born: 1001), ProcessIdentity(pid: 102, parentPID: 101, born: 1002)]
expect(processFamily(root: root, tracked: [root, child], identities: reparented, includeChildren: true) == [child, grandchild], "orphan retained")
let reused = [ProcessIdentity(pid: 100, parentPID: 1, born: 2222)]
expect(processFamily(root: root, tracked: [root], identities: reused, includeChildren: true).isEmpty, "pid reuse guarded")

let oldTraffic = [root: NetworkCounters(received: 1000, sent: 1000), child: NetworkCounters(received: 500, sent: 400)]
let newTraffic = [root: NetworkCounters(received: 3000, sent: 1300), child: NetworkCounters(received: 1000, sent: 900)]
let rates = networkRates(current: newTraffic, previous: oldTraffic, elapsed: 2, hasBaseline: true)
expect(rates.receivedBps == 1250, "network receive child aggregation")
expect(rates.sentBps == 400, "network send child aggregation")
expect(networkRates(current: newTraffic, previous: [:], elapsed: 2, hasBaseline: false).receivedBps == 0, "first network sample creates baseline")
expect(networkRates(current: [root: NetworkCounters(received: 1, sent: 1)], previous: oldTraffic, elapsed: 1, hasBaseline: true).receivedBps == 0, "counter reset no spurious traffic")
var replacedSample = ActivitySample()
replacedSample.networkReceivedBps = 1024 * 1024
replacedSample.networkAvailable = true
expect(abs(replacedSample.intensity(for: .network) - 0.5) < 0.001, "network half-scale")
expect(kittElementsPerSecond(activity: 1) > kittElementsPerSecond(activity: 0), "KITT speed follows activity")
expect(kittElementsPerSecond(activity: 0.5) > kittElementsPerSecond(activity: 0.2), "KITT speed monotonic")
expect(pingPongPosition(progress: 3, segmentCount: 6) == 3, "KITT forward")
expect(pingPongPosition(progress: 7, segmentCount: 6) == 3, "KITT return")
expect(PulseEffect.allCases.count == 20, "twenty effects")
expect(ProcessMetric.allCases.count == 8, "eight metrics")
var energySample = ActivitySample()
energySample.energyWatts = 2.5
energySample.energyReadableCount = 2
expect(abs(energySample.intensity(for: .energy) - 0.5) < 0.001, "2.5 W is half energy scale")
energySample.energyReadableCount = 0
expect(energySample.intensity(for: .energy) == 0, "unavailable energy not fabricated")
var gpuSample = ActivitySample()
gpuSample.gpuAvailable = true
gpuSample.gpuPercent = 75
expect(abs(gpuSample.intensity(for: .gpu) - 0.75) < 0.001, "GPU 75% uses GPU scale")
gpuSample.gpuAvailable = false
expect(gpuSample.intensity(for: .gpu) == 0, "unavailable GPU not fabricated")
expect(appBundlePrefix("/Applications/Demo App.app/Contents/MacOS/Demo App") == "/Applications/Demo App.app/", "example bundle prefix")
expect(appBundlePrefix("/usr/local/bin/node") == nil, "npm node is not .app")
print("Network, energy, GPU, family and KITT speed tests passed")


expect(!networkRates(current: [:], previous: [:], elapsed: 2, hasBaseline: true).available, "empty network coverage is unavailable")

expect(!ProcessMetric.memory.needsNetworkSampler, "RAM never opens the network reader")
expect(!ProcessMetric.disk.needsNetworkSampler, "Disk never opens the network reader")
expect(!ProcessMetric.cpu.needsNetworkSampler, "CPU never opens the network reader")
expect(ProcessMetric.network.needsNetworkSampler, "Only network opens the network reader")
expect(!ProcessMetric.memory.needsGPUSampler, "GPU remains off for RAM")
expect(ProcessMetric.gpu.needsGPUSampler, "GPU starts only when chosen")

expect(PulseEffect.marquee.title.contains("Marquesina"), "marquee localized")
expect(MarqueeText.columns(for: "ABC").count == 18, "5x7 dot matrix and one spacer")
expect(MarqueeText.columns(for: "Ñ").count == 6, "diacritics normalized")
var marqueeSnapshot = PulseSnapshot()
marqueeSnapshot.pid = 4317
marqueeSnapshot.processName = "Demo App"
marqueeSnapshot.metric = .cpu
marqueeSnapshot.activity.cpuPercent = 12.5
marqueeSnapshot.activity.processCount = 17
let text = MarqueeText.message(for: marqueeSnapshot)
expect(text.contains("Demo App"), "marquee includes process name")
expect(text.contains("PID 4317"), "marquee includes PID")
expect(text.contains("CPU 12.5%"), "marquee includes measured CPU")
expect(text.contains("17 PROCESOS"), "marquee includes descendant count")
marqueeSnapshot.metric = .network
expect(MarqueeText.message(for: marqueeSnapshot).contains("SIN DATOS"), "unavailable network not faked")
print("Marquesina y etiquetas probadas")
expect(ActivitySample().formattedRate(0) == "0 B/s", "Spanish neutral zero rate")
expect(ActivitySample().formattedRate(1024).contains("KiB/s"), "binary unit rates")
expect(ProcessMetric.cpu.badge == "CPU", "CPU as label")
expect(ProcessMetric.memory.badge == "RAM", "RAM as label")
expect(ProcessMetric.network.badge == "RED", "network as label")
expect(DisplayPalette.allCases.count == 8, "eight palettes including custom color")
expect(MarqueeText.circularColumn(0, offset: 6, columnCount: 6) == 0, "seamless loop wraps exactly")
expect(MarqueeText.circularColumn(-1, offset: 0, columnCount: 6) == 5, "negative column wraps")
expect(MarqueeText.circularColumn(99, offset: 120, columnCount: 7) == 2, "long scrolling remains cyclic")
var slim = marqueeSnapshot
slim.marqueeShowsPID = false
slim.marqueeShowsProcesses = false
let slimMessage = MarqueeText.message(for: slim)
expect(!slimMessage.contains("PID 4317"), "PID optional in marquee")
expect(!slimMessage.contains("17 PROCESOS"), "process count optional in marquee")
expect(slimMessage.hasSuffix(" | "), "compact separator at loop edge")
expect(PulseEffect.allCases.allSatisfy { !$0.quantification.isEmpty }, "all effects explain how they represent measurements")

let custom = SignalThreshold(enabled: true, minimum: 10, maximum: 50)
expect(abs(custom.normalized(30, for: .cpu) - 0.5) < 0.001, "custom thresholds normalize linearly")
expect(custom.normalized(5, for: .cpu) == 0, "below minimum is inactive")
expect(custom.normalized(75, for: .cpu) == 1, "above maximum is saturated")
expect(abs(sample.intensity(for: .cpu, threshold: custom) - 1) < 0.001, "CPU uses threshold")
expect(SignalThreshold().normalized(25, for: .cpu) == 0.25, "default scale preserved")
AppLanguage.select(.english)
expect(T.text("settings") == "Settings…", "menu localizes to English")
expect(PulseEffect.kitt.localizedExplanation.contains("speed"), "effect guide localizes")
AppLanguage.select(.spanish)
expect(T.text("settings") == "Configuración…", "menu localizes to Spanish")
print("Threshold and language tests passed")

let secondRoot = ProcessKey(pid: 200, born: 2000)
let sharedChild = ProcessKey(pid: 101, born: 1001)
let aggregate = Set(processFamily(root: root, tracked: [root], identities: family, includeChildren: true))
    .union(processFamily(root: sharedChild, tracked: [sharedChild], identities: family, includeChildren: true))
expect(aggregate.count == 3, "multiple watched processes do not double-count shared descendants")
let monitored = [
    WatchedProcess(pid: root.pid, name: "npm", includeChildren: true, includeAppHelpers: false),
    WatchedProcess(pid: secondRoot.pid, name: "node", includeChildren: true, includeAppHelpers: false)
]
var monitoredSnapshot = PulseSnapshot()
monitoredSnapshot.watchedProcesses = monitored
let serialized = try JSONEncoder().encode(monitoredSnapshot)
let restored = try JSONDecoder().decode(PulseSnapshot.self, from: serialized)
expect(restored.watchedProcesses == monitored, "watched process list survives serialization")
expect(PulseEffect.comet.localizedExplanation.count > 5, "comet has an explanation")
expect(PulseEffect.equalizer.localizedExplanation.count > 5, "equalizer has an explanation")
expect(PulseEffect.sparkline.localizedExplanation.count > 5, "sparkline has an explanation")
expect(DisplayPalette.custom.localizedName == "Personalizado", "custom color is localized")
print("Multi-PID and new effect tests passed")

let firstSegment = segmentGeometry(index: 0, count: 48, availableWidth: 1085, gap: 3)
let lastSegment = segmentGeometry(index: 47, count: 48, availableWidth: 1085, gap: 3)
expect(firstSegment.x == 0, "segment layout touches the left edge")
expect(abs(lastSegment.x + lastSegment.width - 1085) < 0.0001, "segment layout touches the right edge")
var threadSample = ActivitySample()
threadSample.threadCount = 64
threadSample.contextSwitchesPerSecond = 1000
expect(abs(threadSample.intensity(for: .threads) - 0.5) < 0.001, "threads reach half scale")
expect(abs(threadSample.intensity(for: .switches) - 0.5) < 0.001, "context switches reach half scale")

for width in [160.0, 685, 1004, 1085] {
    for textWidth in [8.0, 22, 40] {
        let badge = MetricLabelLayout.make(availableWidth: width, textWidth: textWidth)!
        expect(abs(width - badge.x - badge.width - 14) < 0.001, "badge keeps 14 pt right inset")
        expect(badge.x >= 14, "badge fits inside the view")
        let end = segmentGeometry(index: 47, count: 48, availableWidth: width, gap: 3)
        expect(abs(end.x + end.width - width) < 0.0001, "scanner still reaches right edge with overlay")
    }
}
expect(MetricLabelLayout.make(availableWidth: 25, textWidth: 40) == nil, "narrow view safely hides badge")
for position in stride(from: 0.0, through: 1.0, by: 0.05) {
    expect(waveLevel(position: position, elapsed: 1, activity: 0) == 0, "wave is inactive at zero")
    let level = waveLevel(position: position, elapsed: 1, activity: 0.5)
    expect(level >= 0 && level <= 0.5, "wave respects measured amplitude")
}
for language in AppLanguage.allCases {
    AppLanguage.select(language)
    for effect in PulseEffect.allCases {
        expect(!effect.localizedName.isEmpty && !effect.localizedExplanation.isEmpty, "all 20 effects translated")
        expect(PulseEffect(rawValue: effect.rawValue) == effect, "effect identifier round trips")
    }
}
AppLanguage.select(.spanish)
print("Overlay geometry, full-width track and 20-effect coverage passed")
