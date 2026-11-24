import AppKit

func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    guard value() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
func render(_ snapshot: PulseSnapshot, width: CGFloat = 685) -> NSBitmapImageRep {
    let view = PulseBarView(frame: NSRect(x: 0, y: 0, width: width, height: 30))
    view.animates = false
    view.update(snapshot)
    let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: bitmap)
    return bitmap
}
func samePixels(_ first: NSBitmapImageRep, _ second: NSBitmapImageRep, from: Int, to: Int) -> Bool {
    for x in from..<to {
        for y in 0..<first.pixelsHigh {
            if first.colorAt(x: x, y: y) != second.colorAt(x: x, y: y) { return false }
        }
    }
    return true
}
var snapshot = PulseSnapshot()
snapshot.status = .running
snapshot.effect = .vu
snapshot.activity.cpuPercent = 100
// No PID: toggling the label must still draw it in the preview and idle states.
for width: CGFloat in [160, 685, 1004, 1085] {
    snapshot.showMetricLabel = false
    let off = render(snapshot, width: width)
    snapshot.showMetricLabel = true
    let on = render(snapshot, width: width)
    let scale = CGFloat(on.pixelsWide) / width
    let inset = Int(10 * scale)
    expect(samePixels(off, on, from: on.pixelsWide - inset, to: on.pixelsWide), "label preserves animation at right edge at \(width) pt")
    expect(samePixels(off, on, from: 0, to: Int(CGFloat(on.pixelsWide) * 0.5)), "label preserves animation geometry")
    expect(!samePixels(off, on, from: Int(CGFloat(on.pixelsWide) * 0.5), to: on.pixelsWide - inset), "label actually appears without PID")
}
for status in PulseStatus.allCases {
    snapshot.status = status
    snapshot.showMetricLabel = false
    let off = render(snapshot)
    snapshot.showMetricLabel = true
    expect(!samePixels(off, render(snapshot), from: 0, to: off.pixelsWide), "label visible in \(status)")
}
for metric in ProcessMetric.allCases {
    for effect in PulseEffect.allCases {
        snapshot.status = .running
        snapshot.metric = metric
        snapshot.effect = effect
        snapshot.showMetricLabel = true
        for level in [0.0, 0.5, 1.0] {
            var sample = ActivitySample()
            sample.cpuPercent = level * 100
            sample.memoryDeltaBps = level * 64 * 1_048_576
            sample.diskReadBps = level * 3 * 1_048_576
            sample.diskWriteBps = level * 1_048_576
            sample.networkAvailable = true
            sample.networkReceivedBps = level * 1.5 * 1_048_576
            sample.networkSentBps = level * 0.5 * 1_048_576
            sample.gpuAvailable = true
            sample.gpuPercent = level * 100
            sample.energyReadableCount = 1
            sample.energyWatts = level * 5
            sample.threadCount = UInt64(level * 128)
            sample.contextSwitchesPerSecond = level * 2000
            snapshot.activity = sample
            let bitmap = render(snapshot)
            expect(bitmap.pixelsWide > 0, "renders \(effect) / \(metric)")
        }
    }
}
snapshot.effect = .marquee
snapshot.showMetricLabel = false
let marquee = render(snapshot)
snapshot.showMetricLabel = true
expect(!samePixels(marquee, render(snapshot), from: 0, to: marquee.pixelsWide), "resource label toggle also works with marquee")
print("AppKit rendering passed: 20 effects × 8 metrics × 3 levels; label toggle, no PID, 5 states and 4 widths")

// Persistence uses this harness's defaults domain, never the application's domain.
let defaults = UserDefaults.standard
let keys = ["monitor.metric", "monitor.effect", "monitor.showMetricLabel", "monitor.showInitials"]
let oldValues = keys.map { defaults.object(forKey: $0) }
defer {
    for (key, value) in zip(keys, oldValues) {
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
}
defaults.removeObject(forKey: "monitor.showMetricLabel")
defaults.set(true, forKey: "monitor.showInitials")
expect(SettingsModel().showMetricLabel, "settings migrates legacy initials")
expect(PulseCoordinator().snapshot.showMetricLabel, "renderer uses the same migration")
let coordinator = PulseCoordinator()
coordinator.chooseMetric(.disk)
coordinator.chooseEffect(.radar)
coordinator.chooseMetricLabel(true)
let restored = PulseCoordinator()
expect(restored.snapshot.metric == .disk && restored.snapshot.effect == .radar && restored.snapshot.showMetricLabel, "display settings restored on relaunch")
print("Legacy label migration and coordinator persistence passed")

// Exercise the exact bindings used by Toggle/Picker while real samples arrive.
let model = SettingsModel()
let liveCoordinator = PulseCoordinator()
model.onMetricLabel = { liveCoordinator.chooseMetricLabel($0) }
model.onMetric = { liveCoordinator.chooseMetric($0) }
model.onEffect = { liveCoordinator.chooseEffect($0) }
model.onPalette = { liveCoordinator.choosePalette($0) }
model.onColor = { liveCoordinator.chooseColor($0) }
var updates = 0
liveCoordinator.onChange = { value in updates += 1; model.receive(value) }
expect(liveCoordinator.start(WatchConfiguration(pid: ProcessInfo.processInfo.processIdentifier, includeChildren: false, includeAppHelpers: false, effect: .vu, metric: .cpu)), "start actual sampling of test process")
model.previewLive = true
for enabled in [true, false, true, false] {
    model.metricLabelBinding.wrappedValue = enabled
    expect(liveCoordinator.snapshot.showMetricLabel == enabled, "toggle commits before the next sample")
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.15))
    expect(model.showMetricLabel == enabled && model.previewSnapshot.showMetricLabel == enabled, "live updates preserve the resource label toggle")
}
expect(updates >= 8, "samples arrived between toggles")
model.metricBinding.wrappedValue = .memory
model.effectBinding.wrappedValue = .radar
model.paletteBinding.wrappedValue = .cyan
RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.15))
expect(model.metric == .memory && liveCoordinator.snapshot.metric == .memory, "monitor resource selection reaches sampler")
expect(model.effect == .radar && model.palette == .cyan, "appearance edits persist across live samples")
liveCoordinator.choosePalette(.original)
expect(model.palette == .original, "incoming palette updates do not force a custom color")
liveCoordinator.stop()
print("Live sampling integration passed: repeated on/off, preview, resource and appearance bindings")

let targetModel = SettingsModel()
let selfPID = ProcessInfo.processInfo.processIdentifier
targetModel.applications = [RunningApplicationChoice(pid: selfPID, name: "Application choice")]
targetModel.selectedAppPID = selfPID
targetModel.manualPID = "2147483647"
var watched: WatchConfiguration?
targetModel.onWatch = { watched = $0 }
targetModel.targetSource = .application
targetModel.watchSelectedTarget()
expect(watched?.processName == "Application choice", "application mode ignores a stale manual PID")
watched = nil
targetModel.targetSource = .manualPID
targetModel.watchSelectedTarget()
expect(watched == nil && !targetModel.message.isEmpty, "manual mode rejects unavailable PID instead of watching selected application")
targetModel.manualPID = String(selfPID)
expect(targetModel.refreshManualProcess() && targetModel.manualTarget?.pid == selfPID, "manual refresh resolves process without starting monitoring")
expect(watched == nil, "refresh is read-only")
targetModel.watchSelectedTarget()
expect(watched?.pid == selfPID, "manual mode watches entered PID")
targetModel.onWatch = { _ in targetModel.message = "unavailable" }
targetModel.watchSelectedTarget()
expect(targetModel.message == "unavailable", "watch error remains visible")
print("Segmented application/manual PID targeting and refresh tests passed")

// Reproduce the hardware composition: a 1085 pt view clipped to 1004 pt.
let clip = NSClipView(frame: NSRect(x: 0, y: 0, width: 1004, height: 30))
let oversized = PulseBarView(frame: NSRect(x: 0, y: 0, width: 1085, height: 30))
oversized.animates = false
clip.documentView = oversized
var clippedSnapshot = PulseSnapshot()
clippedSnapshot.status = .running
clippedSnapshot.effect = .vu
clippedSnapshot.metric = .cpu
clippedSnapshot.activity.cpuPercent = 100
clippedSnapshot.showMetricLabel = true
oversized.update(clippedSnapshot)
expect(oversized.renderingRect.width == 1004, "physical renderer uses exposed 1004 pt, not oversized 1085 pt bounds")
func bitmap(_ view: NSView) -> NSBitmapImageRep {
    let result = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: result)
    return result
}
let clippedOn = bitmap(oversized)
clippedSnapshot.showMetricLabel = false
oversized.update(clippedSnapshot)
let clippedOff = bitmap(oversized)
let pixelScale = CGFloat(clippedOn.pixelsWide) / 1085
expect(!samePixels(clippedOn, clippedOff, from: Int(930 * pixelScale), to: Int(995 * pixelScale)), "hardware label is drawn inside the physically exposed right edge")
expect(samePixels(clippedOn, clippedOff, from: Int(995 * pixelScale), to: Int(1004 * pixelScale)), "hardware label keeps its right inset and full animation track")

let movingEffects: [PulseEffect] = [.kitt, .disk, .heartbeat, .marquee, .comet, .signal, .wave, .radar, .particles, .breathe, .twin]
for palette in [DisplayPalette.original, .cyan, .rainbow] {
    for effect in movingEffects {
        let view = PulseBarView(frame: NSRect(x: 0, y: 0, width: 685, height: 30))
        view.animates = false
        var value = PulseSnapshot()
        value.status = .running
        value.effect = effect
        value.palette = palette
        value.activity.cpuPercent = 60
        value.processName = "DEMO APP"
        view.update(value)
        let before = bitmap(view)
        view.advanceAnimation(by: 0.37)
        let after = bitmap(view)
        expect(!samePixels(before, after, from: 0, to: before.pixelsWide), "\(effect) actually moves in \(palette) palette")
    }
}
let remoteView = PulseBarView(frame: NSRect(x: 0, y: 0, width: 1004, height: 30))
remoteView.runsWithoutWindow = true
var remoteSnapshot = PulseSnapshot()
remoteSnapshot.status = .running
remoteView.update(remoteSnapshot)
expect(remoteView.window == nil && remoteView.animationIsRunning, "global renderer animates without a conventional app window")
remoteView.stopAnimation()
expect(!remoteView.animationIsRunning, "global owner stops its timer on uninstall")
print("Hardware clipping, label position, remote timer and 33 temporal animation comparisons passed")
