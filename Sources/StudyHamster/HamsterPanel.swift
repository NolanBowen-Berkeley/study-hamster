import AppKit
import HamsterUI
import SwiftUI

/// The transparent, always-on-top, non-activating panel the hamster lives in.
///
/// `.nonactivatingPanel` must be passed at init (toggling it later is unreliable). A non-activating panel
/// can become key and take typing without activating this app, so the app you are studying in stays
/// frontmost while you type into the hamster's bubble — which also keeps window tracking stable.
final class HamsterPanel: NSPanel {
    init() {
        super.init(
            contentRect: CGRect(origin: .zero, size: StageMetrics.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isFloatingPanel = true
        hidesOnDeactivate = false
        // The app is almost never active (the panel doesn't activate it), so allow the bubbles' tooltips anyway.
        allowsToolTipsWhenApplicationIsInactive = true
        becomesKeyOnlyIfNeeded = true
        isMovable = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// The panel has no close button; swallow ⌘W instead of beeping while the ask bubble has focus.
    override func performClose(_ sender: Any?) {}

    /// Placement is fully decided by `PerchCalculator` (which keeps the hamster and bubble on screen while the
    /// transparent top of the panel may overhang the menu bar); don't let AppKit nudge it away from the edge.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    /// Installs the SwiftUI stage as the panel's transparent content.
    func host<Content: View>(_ view: Content) {
        let hostingView = StageHostingView(rootView: view)
        hostingView.sizingOptions = []
        hostingView.frame = CGRect(origin: .zero, size: StageMetrics.panelSize)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.isOpaque = false
        contentView = hostingView
    }
}

/// Lets the very first click land on the hamster/bubble without first activating anything.
final class StageHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
