import AppKit

// Study Hamster: a menu-bar pomodoro buddy that peeks over the top-right corner of your front window.

MainActor.assumeIsolated {
    // Single instance: only meaningful inside the .app bundle (a bare `swift run` binary has no bundle id).
    if let bundleID = Bundle.main.bundleIdentifier {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != getpid() }
        if !others.isEmpty {
            exit(0)
        }
    }

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)  // no Dock icon, no app menu bar
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
    // `run()` only returns at termination; keep the (weakly held) delegate alive until then.
    withExtendedLifetime(delegate) {}
}
