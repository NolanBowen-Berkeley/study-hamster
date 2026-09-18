import AppKit
import CoreGraphics
import HamsterCore

/// Where the hamster should perch: the tracked window (if any) and the visible frame of its screen.
struct PerchTarget: Equatable {
    /// nil when no eligible window exists (desktop focused, everything minimized…).
    var windowID: UInt32?
    /// The window's frame in Cocoa global coordinates (bottom-left origin).
    var windowFrame: CGRect?
    /// `visibleFrame` of the screen the window is on (or of the screen under the mouse when there is none).
    var visibleFrame: CGRect

    /// Same window (or, with no window, the same screen): the panel should follow without ducking.
    func isSamePlace(as other: PerchTarget) -> Bool {
        windowID == other.windowID && (windowID != nil || visibleFrame == other.visibleFrame)
    }
}

/// Follows the frontmost window of the frontmost app using CGWindowList (bounds only — window titles are
/// never read, so no Screen Recording permission is needed).
///
/// Every ~0.25 s, and immediately when another app activates, it does a full scan to pick the target.
/// In between it refreshes just the tracked window's bounds ~30×/s, but only while that window can be
/// moving (a mouse button is down, or it moved within the last half second), so dragging feels glued on
/// while an idle hamster costs only the 4 Hz scan.
@MainActor
final class WindowTracker {
    /// Called only when the target (window, its frame, or its screen) actually changed.
    var onChange: ((PerchTarget) -> Void)?
    private(set) var current: PerchTarget?

    private static let pollInterval: TimeInterval = 1.0 / 30
    private static let fullScanInterval: TimeInterval = 0.25
    /// After the tracked window moves on its own (keyboard, tiling, zoom animations), keep refreshing it at
    /// the poll rate this long.
    private static let hotDuration: TimeInterval = 0.5

    private let ownPID = getpid()
    private var trackedWindowID: UInt32?
    /// Cached from the activation notifications (asking NSWorkspace every scan is a LaunchServices round trip).
    private var frontmostPID: pid_t?
    private var lastFullScan: TimeInterval = -.infinity
    private var hotUntil: TimeInterval = -.infinity
    private var timer: Timer?
    private var activationObserver: NSObjectProtocol?

    /// Starts polling (a no-op while running) and publishes the current target synchronously.
    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.005
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                self?.activated(pid)
            }
        }
        fullScan()
    }

    private func activated(_ pid: pid_t?) {
        frontmostPID = pid ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
        fullScan()
    }

    /// Stops polling (while the hamster is hidden nothing needs to follow windows); `start` resumes.
    func stop() {
        timer?.invalidate()
        timer = nil
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
    }

    /// Forces a full scan now (e.g. after the display configuration changed).
    func rescan() {
        fullScan()
    }

    // MARK: - Polling

    private func poll() {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastFullScan >= Self.fullScanInterval {
            fullScan()
            return
        }
        // Between full scans, only a window that can be moving needs the fast refresh.
        guard let id = trackedWindowID, NSEvent.pressedMouseButtons != 0 || now < hotUntil else { return }
        guard let window = Self.window(withID: id), WindowSelector.isEligible(window, ownPID: ownPID) else {
            fullScan()  // closed, minimized, moved to another Space…
            return
        }
        publish(window)
    }

    private func fullScan() {
        lastFullScan = ProcessInfo.processInfo.systemUptime

        // Our own app is frontmost (Settings is open): keep perching where we were, as long as that window
        // is still there. If it closed, minimized or quit meanwhile, pick another one below.
        if frontmostPID == ownPID, current != nil {
            guard let id = trackedWindowID else { return }  // on the fallback perch: stay there
            if let window = Self.window(withID: id), WindowSelector.isEligible(window, ownPID: ownPID) {
                publish(window)
                return
            }
        }

        let target = WindowSelector.pickTarget(
            windows: Self.onScreenWindows(),
            frontmostPID: frontmostPID == ownPID ? nil : frontmostPID,
            ownPID: ownPID
        )
        publish(target)
    }

    private func publish(_ window: WindowInfo?) {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }  // headless for a moment (displays reconfiguring)
        let primary = screens.first { $0.frame.origin == .zero } ?? screens[0]

        let target: PerchTarget
        if let window {
            let frame = ScreenGeometry.cocoaRect(fromQuartz: window.bounds, primaryScreenHeight: primary.frame.height)
            let index = ScreenGeometry.bestScreenIndex(for: frame, screenFrames: screens.map(\.frame)) ?? 0
            let screen = screens.indices.contains(index) ? screens[index] : primary
            target = PerchTarget(windowID: window.windowID, windowFrame: frame, visibleFrame: screen.visibleFrame)
        } else {
            let mouse = NSEvent.mouseLocation
            let screen = screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? primary
            target = PerchTarget(windowID: nil, windowFrame: nil, visibleFrame: screen.visibleFrame)
        }

        trackedWindowID = window?.windowID
        guard target != current else { return }
        if let previous = current, target.windowID != nil, previous.windowID == target.windowID {
            // The same window moved or resized: follow it closely until it settles.
            hotUntil = ProcessInfo.processInfo.systemUptime + Self.hotDuration
        }
        current = target
        onChange?(target)
    }

    // MARK: - CGWindowList

    /// All on-screen windows, front to back.
    private static func onScreenWindows() -> [WindowInfo] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        guard let entries = list as? [[String: Any]] else { return [] }
        return entries.compactMap(windowInfo(from:))
    }

    /// One window's current info; nil if it is gone or no longer on screen.
    private static func window(withID id: UInt32) -> WindowInfo? {
        let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(id))
        guard let entry = (list as? [[String: Any]])?.first,
              (entry[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true,
              let window = windowInfo(from: entry),
              window.windowID == id
        else { return nil }
        return window
    }

    private static func windowInfo(from entry: [String: Any]) -> WindowInfo? {
        guard let number = entry[kCGWindowNumber as String] as? NSNumber,
              let pid = entry[kCGWindowOwnerPID as String] as? NSNumber,
              let boundsDictionary = entry[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary)
        else { return nil }
        return WindowInfo(
            windowID: number.uint32Value,
            ownerPID: pid.int32Value,
            ownerName: entry[kCGWindowOwnerName as String] as? String ?? "",
            layer: (entry[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0,
            alpha: (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
            bounds: bounds
        )
    }
}
