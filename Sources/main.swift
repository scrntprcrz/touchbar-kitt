import AppKit
import Darwin

signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
signal(SIGPIPE, SIG_IGN)

let bundleIdentifier = Bundle.main.bundleIdentifier ?? "dev.touchbarkitt.studio"
let previousInstances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
    .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
for runningApplication in previousInstances {
    runningApplication.terminate()
}
if !previousInstances.isEmpty {
    Thread.sleep(forTimeInterval: 0.5)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
