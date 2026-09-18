import CoreGraphics
import Foundation
import HamsterCore

private let ownPID: Int32 = 100
private let frontPID: Int32 = 200
private let otherPID: Int32 = 300

private func window(
    _ id: UInt32, pid: Int32, owner: String = "Some App", layer: Int = 0, alpha: Double = 1,
    bounds: CGRect = CGRect(x: 100, y: 100, width: 800, height: 600)
) -> WindowInfo {
    WindowInfo(windowID: id, ownerPID: pid, ownerName: owner, layer: layer, alpha: alpha, bounds: bounds)
}

private func pick(_ windows: [WindowInfo], frontmost: Int32?) -> UInt32? {
    WindowSelector.pickTarget(windows: windows, frontmostPID: frontmost, ownPID: ownPID)?.windowID
}

func runWindowSelectorChecks() {
    section("WindowSelector.isEligible") {
        func eligible(_ info: WindowInfo) -> Bool { WindowSelector.isEligible(info, ownPID: ownPID) }

        check(eligible(window(1, pid: otherPID)), "a normal window is eligible")
        check(!eligible(window(1, pid: ownPID)), "our own windows are never eligible")
        for layer in [-1, 1, 3, 8, 24, 25, 1000] {
            check(!eligible(window(1, pid: otherPID, layer: layer)), "layer \(layer) is not eligible")
        }
        check(!eligible(window(1, pid: otherPID, alpha: 0)), "alpha 0 is not eligible")
        check(!eligible(window(1, pid: otherPID, alpha: 0.05)), "alpha 0.05 is not eligible (must exceed it)")
        check(eligible(window(1, pid: otherPID, alpha: 0.06)), "alpha 0.06 is eligible")
        check(!eligible(window(1, pid: otherPID, bounds: CGRect(x: 0, y: 0, width: 159, height: 500))), "too narrow")
        check(!eligible(window(1, pid: otherPID, bounds: CGRect(x: 0, y: 0, width: 500, height: 99))), "too short")
        check(!eligible(window(1, pid: otherPID, bounds: .zero)), "zero-size")
        check(eligible(window(1, pid: otherPID, bounds: CGRect(x: -50, y: -30, width: 160, height: 100))), "exactly the minimum size")
        check(!eligible(window(1, pid: otherPID, bounds: CGRect(x: CGFloat.nan, y: 0, width: 800, height: 600))), "NaN origin")
        check(!eligible(window(1, pid: otherPID, bounds: CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 600))), "infinite width")
        for owner in WindowSelector.ignoredOwners.sorted() {
            check(!eligible(window(1, pid: otherPID, owner: owner)), "\(owner) windows are ignored")
        }
        check(eligible(window(1, pid: otherPID, owner: "Dock Helper")), "only exact owner names are ignored")
        checkEqual(WindowSelector.minimumSize, CGSize(width: 160, height: 100))
    }

    section("WindowSelector.pickTarget") {
        checkEqual(pick([], frontmost: frontPID), nil, "empty list")
        checkEqual(pick([], frontmost: nil), nil, "empty list, no frontmost app")

        // The frontmost app's frontmost window wins even when another app's window is in front of it.
        let mixed = [window(1, pid: otherPID), window(2, pid: frontPID), window(3, pid: frontPID)]
        checkEqual(pick(mixed, frontmost: frontPID), 2, "frontmost app preferred")
        checkEqual(pick(mixed, frontmost: otherPID), 1, "frontmost app preferred (other)")
        checkEqual(pick(mixed, frontmost: nil), 1, "no frontmost app: first eligible window")
        checkEqual(pick(mixed, frontmost: 999), 1, "frontmost app without windows: first eligible window")

        // The frontmost app has only ineligible windows (palette, tiny, invisible) → fall back.
        let frontIneligible = [
            window(1, pid: frontPID, layer: 3),
            window(2, pid: frontPID, bounds: CGRect(x: 0, y: 0, width: 100, height: 50)),
            window(3, pid: frontPID, alpha: 0),
            window(4, pid: otherPID),
            window(5, pid: otherPID),
        ]
        checkEqual(pick(frontIneligible, frontmost: frontPID), 4, "fallback to another app's window")

        // Skips ineligible windows of the frontmost app to reach its eligible one.
        let layered = [window(1, pid: frontPID, layer: 25), window(2, pid: otherPID), window(3, pid: frontPID)]
        checkEqual(pick(layered, frontmost: frontPID), 3, "non-zero layer skipped")

        // Our own windows (the hamster panel, settings) are excluded.
        let withOwn = [window(1, pid: ownPID), window(2, pid: otherPID), window(3, pid: frontPID)]
        checkEqual(pick(withOwn, frontmost: frontPID), 3, "own window skipped")
        checkEqual(pick(withOwn, frontmost: nil), 2, "own window skipped without frontmost app")
        checkEqual(pick(withOwn, frontmost: ownPID), 2, "we are frontmost: no preference, own windows still excluded")
        checkEqual(pick([window(1, pid: ownPID)], frontmost: ownPID), nil, "only our own windows")

        let ignored = [window(1, pid: 400, owner: "Dock"), window(2, pid: 401, owner: "Window Server"), window(3, pid: otherPID)]
        checkEqual(pick(ignored, frontmost: 400), 3, "ignored owners skipped even when frontmost")

        let nothing = [window(1, pid: otherPID, alpha: 0), window(2, pid: otherPID, layer: 20), window(3, pid: ownPID)]
        checkEqual(pick(nothing, frontmost: otherPID), nil, "no eligible window")
    }
}

func runScreenGeometryChecks() {
    // Primary 1440×900 at the origin; a 1920×1080 screen above it and shifted left; a 1280×1024 screen to
    // the left, slightly lower. Cocoa coordinates (bottom-left origin, y up).
    let primaryHeight: CGFloat = 900
    let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let above = CGRect(x: -200, y: 900, width: 1920, height: 1080)
    let left = CGRect(x: -1280, y: -100, width: 1280, height: 1024)
    let screens = [primary, above, left]

    section("ScreenGeometry conversions") {
        checkEqual(ScreenGeometry.cocoaRect(fromQuartz: CGRect(x: 100, y: 50, width: 800, height: 600), primaryScreenHeight: primaryHeight),
                   CGRect(x: 100, y: 250, width: 800, height: 600), "window on the primary screen")
        checkEqual(ScreenGeometry.cocoaRect(fromQuartz: CGRect(x: 0, y: 0, width: 1440, height: 900), primaryScreenHeight: primaryHeight),
                   primary, "the primary screen maps onto itself")
        checkEqual(ScreenGeometry.quartzRect(fromCocoa: above, primaryScreenHeight: primaryHeight),
                   CGRect(x: -200, y: -1080, width: 1920, height: 1080), "screen above has negative Quartz y")
        checkEqual(ScreenGeometry.quartzRect(fromCocoa: left, primaryScreenHeight: primaryHeight),
                   CGRect(x: -1280, y: -24, width: 1280, height: 1024), "screen to the left")
        checkEqual(ScreenGeometry.cocoaRect(fromQuartz: CGRect(x: -100, y: -900, width: 800, height: 600), primaryScreenHeight: primaryHeight),
                   CGRect(x: -100, y: 1200, width: 800, height: 600), "window on the screen above")

        let samples = [
            CGRect(x: 100, y: 50, width: 800, height: 600),
            CGRect(x: -100, y: -900, width: 800, height: 600),
            CGRect(x: -1200, y: 300, width: 640, height: 480),
            CGRect(x: 1300, y: 850, width: 400, height: 300),
            CGRect(x: 10.5, y: -20.25, width: 333.75, height: 222.5),
            primary, above, left,
        ]
        for rect in samples {
            let cocoa = ScreenGeometry.cocoaRect(fromQuartz: rect, primaryScreenHeight: primaryHeight)
            checkEqual(ScreenGeometry.quartzRect(fromCocoa: cocoa, primaryScreenHeight: primaryHeight), rect, "round trip Quartz→Cocoa→Quartz \(rect)")
            let quartz = ScreenGeometry.quartzRect(fromCocoa: rect, primaryScreenHeight: primaryHeight)
            checkEqual(ScreenGeometry.cocoaRect(fromQuartz: quartz, primaryScreenHeight: primaryHeight), rect, "round trip Cocoa→Quartz→Cocoa \(rect)")
            checkEqual(cocoa.size, rect.size, "size preserved \(rect)")
            checkEqual(cocoa.maxY, primaryHeight - rect.minY, "Quartz top edge becomes Cocoa maxY \(rect)")
        }
    }

    section("ScreenGeometry.bestScreenIndex") {
        func best(_ rect: CGRect, _ frames: [CGRect]? = nil) -> Int? {
            ScreenGeometry.bestScreenIndex(for: rect, screenFrames: frames ?? screens)
        }
        checkEqual(best(CGRect(x: 100, y: 100, width: 800, height: 600)), 0, "inside the primary")
        checkEqual(best(CGRect(x: 0, y: 1200, width: 800, height: 600)), 1, "inside the screen above")
        checkEqual(best(CGRect(x: -1000, y: 100, width: 600, height: 400)), 2, "inside the left screen")
        checkEqual(best(CGRect(x: 100, y: 700, width: 800, height: 600)), 1, "straddling, mostly above")
        checkEqual(best(CGRect(x: 100, y: 500, width: 800, height: 600)), 0, "straddling, mostly primary")
        checkEqual(best(CGRect(x: -300, y: 100, width: 800, height: 600)), 0, "straddling left/primary, mostly primary")
        checkEqual(best(CGRect(x: -700, y: 100, width: 800, height: 600)), 2, "straddling left/primary, mostly left")

        let a = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let b = CGRect(x: 1000, y: 0, width: 1000, height: 1000)
        let straddle = CGRect(x: 900, y: 100, width: 200, height: 200)
        checkEqual(best(straddle, [a, b]), 0, "tie goes to the lowest index")
        checkEqual(best(straddle, [b, a]), 0, "tie goes to the lowest index (reversed)")
        checkEqual(best(CGRect(x: 1000, y: 0, width: 100, height: 100), [a, b]), 1, "touching an edge is not overlap")

        checkEqual(best(CGRect(x: 2500, y: 400, width: 200, height: 200), [a, b]), 1, "off-screen right: nearest center")
        checkEqual(best(CGRect(x: -3000, y: 0, width: 200, height: 200), [a, b]), 0, "off-screen left: nearest center")
        checkEqual(best(CGRect(x: -100, y: 0, width: 100, height: 100), [a, b]), 0, "edge contact only: nearest center")
        checkEqual(best(CGRect(x: 5000, y: 5000, width: 10, height: 10), [b, b]), 0, "equal distances: lowest index")
        checkEqual(best(CGRect(x: 5000, y: 5000, width: 10, height: 10)), 1, "far above-right: the screen above is nearest")

        checkEqual(best(CGRect(x: 0, y: 0, width: 100, height: 100), []), nil, "no screens")
        checkEqual(best(CGRect(x: 500, y: 500, width: 0, height: 0), [a]), 0, "zero-size rect still gets a screen")
        checkEqual(best(CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100), [a, b]), 0, "NaN rect does not crash")
    }
}

func runPerchChecks() {
    let metrics = PerchMetrics(panelSize: CGSize(width: 460, height: 380), ledgeFromTop: 240, hamsterCenterX: 382, hamsterInsetFromWindowRight: 70)
    // A 1440×900 screen with a 25pt menu bar and a 70pt Dock at the bottom (Cocoa coordinates).
    let visible = CGRect(x: 0, y: 70, width: 1440, height: 805)

    func ledgeY(_ layout: PerchLayout) -> CGFloat { layout.panelFrame.maxY - metrics.ledgeFromTop }
    func centerX(_ layout: PerchLayout) -> CGFloat { layout.panelFrame.minX + metrics.hamsterCenterX }
    func inside(_ layout: PerchLayout, _ frame: CGRect) -> Bool { frame.contains(layout.panelFrame) }

    section("PerchCalculator.layout normal placement") {
        let windowFrame = CGRect(x: 200, y: 100, width: 800, height: 500)
        let layout = PerchCalculator.layout(windowFrame: windowFrame, visibleFrame: visible, metrics: metrics)
        checkEqual(layout.panelFrame, CGRect(x: 548, y: 460, width: 460, height: 380))
        checkEqual(layout.isClamped, false)
        checkEqual(ledgeY(layout), windowFrame.maxY, "ledge line exactly on the window's top edge")
        checkEqual(centerX(layout), windowFrame.maxX - 70, "hamster centerline 70pt left of the window's right edge")
        check(inside(layout, visible), "panel inside the visible frame")

        // Other metrics follow the same formula.
        let small = PerchMetrics(panelSize: CGSize(width: 200, height: 100), ledgeFromTop: 50, hamsterCenterX: 150, hamsterInsetFromWindowRight: 20)
        let smallLayout = PerchCalculator.layout(windowFrame: CGRect(x: 100, y: 100, width: 400, height: 300), visibleFrame: visible, metrics: small)
        checkEqual(smallLayout.panelFrame, CGRect(x: 330, y: 350, width: 200, height: 100), "custom metrics")
        checkEqual(smallLayout.isClamped, false)

        // A window on a secondary screen above the primary (negative Quartz y), end to end.
        let aboveVisible = CGRect(x: -200, y: 900, width: 1920, height: 1055)
        let quartzWindow = CGRect(x: 0, y: -800, width: 1000, height: 600)
        let cocoaWindow = ScreenGeometry.cocoaRect(fromQuartz: quartzWindow, primaryScreenHeight: 900)
        checkEqual(ScreenGeometry.bestScreenIndex(for: cocoaWindow, screenFrames: [CGRect(x: 0, y: 0, width: 1440, height: 900), aboveVisible]), 1,
                   "window found on the upper screen")
        let aboveLayout = PerchCalculator.layout(windowFrame: cocoaWindow, visibleFrame: aboveVisible, metrics: metrics)
        checkEqual(aboveLayout.isClamped, false, "room above the window on the upper screen")
        checkEqual(ledgeY(aboveLayout), cocoaWindow.maxY, "upper screen: ledge on the window top")
        checkEqual(centerX(aboveLayout), cocoaWindow.maxX - 70, "upper screen: centerline inset")
    }

    section("PerchCalculator.layout clamping") {
        // Maximized window right under the menu bar: pushed down, and left because the window touches the
        // screen's right edge.
        let maximized = CGRect(x: 0, y: 70, width: 1440, height: 805)
        let maxLayout = PerchCalculator.layout(windowFrame: maximized, visibleFrame: visible, metrics: metrics)
        checkEqual(maxLayout.panelFrame, CGRect(x: 980, y: 495, width: 460, height: 380), "maximized window")
        checkEqual(maxLayout.isClamped, true)
        checkEqual(maxLayout.panelFrame.maxY, visible.maxY, "clamped under the menu bar")
        check(ledgeY(maxLayout) < maximized.maxY, "hamster peeks from inside the window")
        check(inside(maxLayout, visible), "maximized: inside the visible frame")

        // Top at the menu bar but well away from the right edge: only the vertical clamp applies.
        let tall = CGRect(x: 100, y: 70, width: 800, height: 805)
        let tallLayout = PerchCalculator.layout(windowFrame: tall, visibleFrame: visible, metrics: metrics)
        checkEqual(tallLayout.panelFrame, CGRect(x: 448, y: 495, width: 460, height: 380), "window under the menu bar")
        checkEqual(tallLayout.isClamped, true)
        checkEqual(centerX(tallLayout), tall.maxX - 70, "horizontal placement unaffected")

        // Window extending past the right edge of the screen.
        let pastRight = CGRect(x: 1000, y: 100, width: 800, height: 500)
        let rightLayout = PerchCalculator.layout(windowFrame: pastRight, visibleFrame: visible, metrics: metrics)
        checkEqual(rightLayout.panelFrame, CGRect(x: 980, y: 460, width: 460, height: 380), "past the right edge")
        checkEqual(rightLayout.isClamped, true)
        checkEqual(ledgeY(rightLayout), pastRight.maxY, "past the right edge: ledge still on the window top")
        checkEqual(rightLayout.panelFrame.maxX, visible.maxX)

        // Window hanging off the left edge.
        let pastLeft = CGRect(x: -900, y: 100, width: 800, height: 500)
        let leftLayout = PerchCalculator.layout(windowFrame: pastLeft, visibleFrame: visible, metrics: metrics)
        checkEqual(leftLayout.panelFrame, CGRect(x: 0, y: 460, width: 460, height: 380), "past the left edge")
        checkEqual(leftLayout.isClamped, true)

        // Window whose top is near the bottom of the screen: pushed up.
        let low = CGRect(x: 200, y: -400, width: 800, height: 500)
        let lowLayout = PerchCalculator.layout(windowFrame: low, visibleFrame: visible, metrics: metrics)
        checkEqual(lowLayout.panelFrame, CGRect(x: 548, y: 70, width: 460, height: 380), "window low on the screen")
        checkEqual(lowLayout.isClamped, true)

        // Screen smaller than the panel: the top-left corner wins.
        let tiny = CGRect(x: 0, y: 0, width: 300, height: 200)
        for windowFrame in [tiny, CGRect(x: 0, y: -500, width: 300, height: 200), CGRect(x: 5000, y: 5000, width: 300, height: 200)] {
            let tinyLayout = PerchCalculator.layout(windowFrame: windowFrame, visibleFrame: tiny, metrics: metrics)
            checkEqual(tinyLayout.panelFrame, CGRect(x: 0, y: -180, width: 460, height: 380), "tiny screen, window \(windowFrame)")
            checkEqual(tinyLayout.isClamped, true, "tiny screen is clamped")
        }

        // A screen to the left of the primary with negative coordinates.
        let leftScreen = CGRect(x: -1280, y: -100, width: 1280, height: 999)
        let leftWindow = CGRect(x: -1000, y: 0, width: 700, height: 500)
        let leftScreenLayout = PerchCalculator.layout(windowFrame: leftWindow, visibleFrame: leftScreen, metrics: metrics)
        checkEqual(leftScreenLayout.panelFrame, CGRect(x: -752, y: 360, width: 460, height: 380), "negative coordinates")
        checkEqual(leftScreenLayout.isClamped, false, "negative coordinates: room to spare")
        checkEqual(ledgeY(leftScreenLayout), leftWindow.maxY, "negative coordinates: ledge on the window top")
        checkEqual(centerX(leftScreenLayout), leftWindow.maxX - 70, "negative coordinates: centerline inset")
        let edgeWindow = CGRect(x: -700, y: 0, width: 700, height: 500)
        let edgeLayout = PerchCalculator.layout(windowFrame: edgeWindow, visibleFrame: leftScreen, metrics: metrics)
        checkEqual(edgeLayout.panelFrame, CGRect(x: -460, y: 360, width: 460, height: 380), "window at the left screen's right edge")
        checkEqual(edgeLayout.isClamped, true, "clamped against the left screen's right edge")
    }

    section("PerchCalculator.layout headroom (panel top may overhang the menu bar)") {
        checkEqual(metrics.headroom, metrics.ledgeFromTop, "headroom defaults to the whole panel above the ledge")
        let peek = PerchMetrics(panelSize: metrics.panelSize, ledgeFromTop: 240, hamsterCenterX: 382,
                                hamsterInsetFromWindowRight: 70, headroom: 96)
        let out = PerchMetrics(panelSize: metrics.panelSize, ledgeFromTop: 240, hamsterCenterX: 382,
                               hamsterInsetFromWindowRight: 70, headroom: 170)

        // Windows 0, 30, 95, 96, 150 and 300 pt below the menu bar (visible.maxY = 875).
        for gap: CGFloat in [0, 30, 95, 96, 150, 300] {
            let window = CGRect(x: 100, y: 70, width: 900, height: 805 - gap)
            let layout = PerchCalculator.layout(windowFrame: window, visibleFrame: visible, metrics: peek)
            let expectedLedge = min(window.maxY, visible.maxY - 96)
            checkEqual(ledgeY(layout), expectedLedge, "peek, window \(gap) pt below the menu bar: ledge")
            checkEqual(centerX(layout), window.maxX - 70, "peek, window \(gap) pt below the menu bar: centerline")
            checkEqual(layout.isClamped, gap < 96, "peek, window \(gap) pt below the menu bar: clamped only without room")
            checkEqual(layout.topOverhang, max(0, expectedLedge + 240 - visible.maxY), "peek, gap \(gap): overhang")
            check(layout.panelFrame.minY >= visible.minY, "peek, gap \(gap): bottom stays on screen")
            check(visible.maxY - ledgeY(layout) >= 96, "peek, gap \(gap): the head fits under the menu bar")
        }
        // A window 150 pt down sits on its real edge, the transparent top overhangs by 90 pt.
        let mid = CGRect(x: 100, y: 70, width: 900, height: 655)
        let midLayout = PerchCalculator.layout(windowFrame: mid, visibleFrame: visible, metrics: peek)
        checkEqual(midLayout.panelFrame, CGRect(x: 548, y: 585, width: 460, height: 380), "window 150 pt down")
        checkEqual(midLayout.topOverhang, 90)
        checkEqual(midLayout.isClamped, false)

        // Maximized: the hamster peeks from 96 pt inside, the panel overhangs by 144 pt.
        let maximized = CGRect(x: 0, y: 70, width: 1440, height: 805)
        let maxPeek = PerchCalculator.layout(windowFrame: maximized, visibleFrame: visible, metrics: peek)
        checkEqual(maxPeek.panelFrame, CGRect(x: 980, y: 639, width: 460, height: 380), "maximized, peeking")
        checkEqual(ledgeY(maxPeek), visible.maxY - 96, "maximized: ledge 96 pt under the menu bar")
        checkEqual(maxPeek.topOverhang, 144)
        checkEqual(maxPeek.isClamped, true)
        // Out on the ledge (break, alarm) needs more room: 170 pt.
        let maxOut = PerchCalculator.layout(windowFrame: maximized, visibleFrame: visible, metrics: out)
        checkEqual(ledgeY(maxOut), visible.maxY - 170, "maximized, sitting out: ledge 170 pt under the menu bar")
        checkEqual(maxOut.topOverhang, 70)
        let roomy = CGRect(x: 100, y: 70, width: 900, height: 600)
        checkEqual(PerchCalculator.layout(windowFrame: roomy, visibleFrame: visible, metrics: out).panelFrame,
                   PerchCalculator.layout(windowFrame: roomy, visibleFrame: visible, metrics: peek).panelFrame,
                   "with room for both, peek and out layouts agree")

        // The bottom clamp still applies, and the top clamp wins on a screen too short for the panel.
        let low = CGRect(x: 200, y: -400, width: 800, height: 500)
        checkEqual(PerchCalculator.layout(windowFrame: low, visibleFrame: visible, metrics: peek).panelFrame.minY, visible.minY,
                   "window low on the screen: pushed up")
        let short = CGRect(x: 0, y: 0, width: 1440, height: 200)
        let shortLayout = PerchCalculator.layout(windowFrame: CGRect(x: 0, y: 0, width: 800, height: 150), visibleFrame: short, metrics: peek)
        checkEqual(ledgeY(shortLayout), short.maxY - 96, "short screen: the head still fits under the top")

        // Headroom larger than the panel above the ledge never pushes the ledge higher than normal.
        let huge = PerchMetrics(panelSize: metrics.panelSize, ledgeFromTop: 240, hamsterCenterX: 382,
                                hamsterInsetFromWindowRight: 70, headroom: 400)
        checkEqual(PerchCalculator.layout(windowFrame: maximized, visibleFrame: visible, metrics: huge).panelFrame.maxY, visible.maxY,
                   "headroom above ledgeFromTop behaves like the whole panel")
        checkEqual(PerchCalculator.layout(windowFrame: maximized, visibleFrame: visible, metrics: huge).topOverhang, 0)

        // Fractional frames: integral origin, overhang measured from the rounded frame.
        let fractional = PerchCalculator.layout(windowFrame: CGRect(x: 10.4, y: 70, width: 900.3, height: 790.6),
                                                visibleFrame: visible, metrics: peek)
        check(fractional.panelFrame.origin.y == fractional.panelFrame.origin.y.rounded(), "fractional: integral origin")
        checkEqual(fractional.topOverhang, fractional.panelFrame.maxY - visible.maxY, "fractional: overhang of the rounded frame")

        let fallback = PerchCalculator.fallbackLayout(visibleFrame: visible, metrics: peek)
        checkEqual(ledgeY(fallback), visible.maxY - 96, "fallback perch: peeks just under the menu bar")
        checkEqual(fallback.panelFrame.maxX, visible.maxX, "fallback perch: at the right edge")
        checkEqual(fallback.topOverhang, 144)
        checkEqual(fallback.isClamped, true)
    }

    section("PerchCalculator.fallbackLayout") {
        let layout = PerchCalculator.fallbackLayout(visibleFrame: visible, metrics: metrics)
        checkEqual(layout.panelFrame, CGRect(x: 980, y: 495, width: 460, height: 380))
        checkEqual(layout.isClamped, true)
        checkEqual(layout.topOverhang, 0, "default headroom never overhangs")
        checkEqual(layout.panelFrame.maxY, visible.maxY, "tucked under the menu bar")
        checkEqual(layout.panelFrame.maxX, visible.maxX, "at the right edge")

        let secondary = CGRect(x: -1280, y: -100, width: 1280, height: 999)
        let secondaryLayout = PerchCalculator.fallbackLayout(visibleFrame: secondary, metrics: metrics)
        checkEqual(secondaryLayout.panelFrame, CGRect(x: -460, y: 519, width: 460, height: 380), "secondary screen")
        checkEqual(secondaryLayout.isClamped, true)

        // Even when the panel would not be moved, the fallback reports clamped.
        let roomy = PerchMetrics(panelSize: CGSize(width: 100, height: 100), ledgeFromTop: 0, hamsterCenterX: 100, hamsterInsetFromWindowRight: 0)
        checkEqual(PerchCalculator.fallbackLayout(visibleFrame: visible, metrics: roomy).isClamped, true, "fallback is always clamped")
    }

    section("PerchCalculator integral origins") {
        let fractional = [
            CGRect(x: 200.3, y: 100.6, width: 800.2, height: 500.1),
            CGRect(x: 10.5, y: 20.5, width: 700.5, height: 400.5),
            CGRect(x: 999.75, y: 0.25, width: 640.4, height: 480.49),
        ]
        for windowFrame in fractional {
            for screen in [visible, CGRect(x: 0.5, y: 0.5, width: 1439.5, height: 874.5)] {
                let layout = PerchCalculator.layout(windowFrame: windowFrame, visibleFrame: screen, metrics: metrics)
                let origin = layout.panelFrame.origin
                check(origin.x == origin.x.rounded() && origin.y == origin.y.rounded(), "origin \(origin) is integral for \(windowFrame)")
                checkEqual(layout.panelFrame.size, metrics.panelSize, "size is the panel size")
            }
            let unclamped = PerchCalculator.layout(windowFrame: windowFrame, visibleFrame: visible, metrics: metrics)
            if !unclamped.isClamped {
                check(abs(ledgeY(unclamped) - windowFrame.maxY) <= 0.5, "rounded ledge within half a point of \(windowFrame.maxY)")
                check(abs(centerX(unclamped) - (windowFrame.maxX - 70)) <= 0.5, "rounded centerline within half a point")
            }
        }
    }
}
