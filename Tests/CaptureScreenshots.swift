import AppKit
import SwiftUI

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.finishLaunching()
AppLanguage.select(.spanish)
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let model = SettingsModel()
model.showMetricLabel = true
model.metric = .cpu
model.selectedColor = Color(red: 1, green: 0.2, blue: 0.2)
model.includeChildren = true
model.includeHelpers = true
model.manualPID = ""
model.thresholdEnabled = false
model.minimumText = "0"
model.maximumText = "100"
model.previewLive = true
model.effect = .kitt
model.palette = .original
model.demoLoad = 0.65
model.previewTick = 2
model.applications = [RunningApplicationChoice(pid: 4317, name: "Demo App")]
model.selectedAppPID = model.applications[0].pid
var sample = ActivitySample()
sample.cpuPercent = 36.8
sample.residentBytes = 268 * 1_048_576
sample.diskReadBps = 314_572
sample.diskWriteBps = 104_857
sample.threadCount = 24
sample.contextSwitchesPerSecond = 720
sample.processCount = 4
sample.readableCount = 4
sample.diskReadableCount = 4
sample.sampledSeconds = 1
sample.energyReadableCount = 1
sample.energyWatts = 1.24
model.snapshot.status = .running
model.snapshot.processName = "Demo App"
model.snapshot.pid = model.selectedAppPID
model.snapshot.watchedProcesses = [WatchedProcess(pid: model.selectedAppPID, name: "Demo App", includeChildren: true, includeAppHelpers: true)]
model.snapshot.activity = sample
model.snapshot.metric = .cpu
model.snapshot.effect = .kitt
model.snapshot.palette = .original
model.snapshot.showMetricLabel = true

// AppKit may attach EXIF to PNG representations. Screenshots for the public
// repository retain pixels and color information, but no EXIF or text metadata.
func withoutPNGMetadata(_ data: Data) -> Data {
    let privateChunks = ["eXIf", "tEXt", "iTXt", "zTXt"]
    var result = Data(data.prefix(8))
    var offset = 8
    while offset + 12 <= data.count {
        let length = data[offset..<(offset + 4)].reduce(0) { ($0 << 8) | Int($1) }
        guard length <= data.count - offset - 12 else { fatalError("Invalid PNG chunk") }
        let kind = String(decoding: data[(offset + 4)..<(offset + 8)], as: UTF8.self)
        let end = offset + length + 12
        if !privateChunks.contains(kind) { result.append(data[offset..<end]) }
        offset = end
    }
    return result
}

func capture(section: SettingsSection, appearance: NSAppearance.Name, name: String, height: CGFloat = 760, width: CGFloat = 920, galleryExpanded: Bool = false) throws {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: appearance)
    window.title = "TouchBar KITT"
    let host = NSHostingView(rootView: SettingsView(model: model, section: section, galleryExpanded: galleryExpanded))
    window.contentView = host
    window.setContentSize(NSSize(width: width, height: height))
    app.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("Cannot render UI") }
    host.cacheDisplay(in: host.bounds, to: bitmap)
    try withoutPNGMetadata(bitmap.representation(using: .png, properties: [:])!).write(to: destination.appendingPathComponent(name))
    window.orderOut(nil)
}
try capture(section: .monitor, appearance: .aqua, name: "monitor-light.png")
model.effect = .radar
model.palette = .cyan
model.snapshot.effect = .radar
model.snapshot.palette = .cyan
try capture(section: .appearance, appearance: .darkAqua, name: "animations-dark.png", height: 1220, galleryExpanded: true)
model.effect = .kitt
model.palette = .original
model.snapshot.effect = .kitt
model.snapshot.palette = .original
try capture(section: .appearance, appearance: .aqua, name: "appearance-light.png")
try capture(section: .appearance, appearance: .darkAqua, name: "appearance-dark.png")
try capture(section: .monitor, appearance: .darkAqua, name: "monitor-compact.png", height: 620, width: 780)
model.targetSource = .manualPID
model.manualPID = String(model.selectedAppPID)
model.manualTarget = RunningApplicationChoice(pid: 4317, name: "Demo App")
try capture(section: .monitor, appearance: .aqua, name: "monitor-manual-pid.png")
try capture(section: .monitor, appearance: .darkAqua, name: "sidebar-readings-dark.png")
print("UI screenshots saved to \(destination.path); all displayed readings are demonstration values.")
