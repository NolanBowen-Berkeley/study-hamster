import CoreGraphics
import Foundation

/// Fixed layout of the hamster's panel, in points.
public struct PerchMetrics: Equatable, Sendable {
    public var panelSize: CGSize
    /// Distance from the panel's top edge down to the ledge line (the window's top edge).
    public var ledgeFromTop: CGFloat
    /// Hamster centerline, measured from the panel's left edge.
    public var hamsterCenterX: CGFloat
    /// How far left of the window's right edge the hamster's centerline sits.
    public var hamsterInsetFromWindowRight: CGFloat
    /// Room the hamster needs between the ledge and the top of the visible frame (the menu bar). The part of
    /// the panel above that is transparent (jump apex, bubble headroom), so it may hang over the menu bar and
    /// off the top of the screen. Defaults to `ledgeFromTop`: the whole panel stays inside the visible frame.
    public var headroom: CGFloat

    public init(
        panelSize: CGSize, ledgeFromTop: CGFloat, hamsterCenterX: CGFloat, hamsterInsetFromWindowRight: CGFloat,
        headroom: CGFloat? = nil
    ) {
        self.panelSize = panelSize
        self.ledgeFromTop = ledgeFromTop
        self.hamsterCenterX = hamsterCenterX
        self.hamsterInsetFromWindowRight = hamsterInsetFromWindowRight
        self.headroom = headroom ?? ledgeFromTop
    }
}

public struct PerchLayout: Equatable, Sendable {
    /// Cocoa global coordinates (bottom-left origin).
    public var panelFrame: CGRect
    /// True when the panel had to be pushed down/sideways to stay on screen (e.g. a maximized window with
    /// no room above it), so the hamster peeks from just inside the window instead of above its edge.
    public var isClamped: Bool
    /// How far the panel's (transparent) top sticks out above the visible frame, in points (0 when it
    /// doesn't). The stage keeps its bubble below this line so it never hides under the menu bar.
    public var topOverhang: CGFloat

    public init(panelFrame: CGRect, isClamped: Bool, topOverhang: CGFloat = 0) {
        self.panelFrame = panelFrame
        self.isClamped = isClamped
        self.topOverhang = topOverhang
    }
}

public enum PerchCalculator {
    /// Positions the panel so the ledge line sits on `windowFrame`'s top edge with the hamster near its
    /// top-right corner, then clamps it to `visibleFrame`. All rects are Cocoa coordinates.
    ///
    /// Horizontally and at the bottom the whole panel stays inside `visibleFrame`. At the top only the
    /// hamster's `headroom` has to fit: the ledge never rises above `visibleFrame.maxY - headroom`, and the
    /// transparent rest of the panel may stick out above the visible frame (reported as `topOverhang`).
    /// So the hamster sits on the window's real edge whenever it has that much room under the menu bar,
    /// and otherwise peeks from just inside the window's top. When the panel does not fit, the top wins
    /// over the bottom and the left edge wins over the right edge. The origin is rounded to whole points.
    public static func layout(windowFrame: CGRect, visibleFrame: CGRect, metrics: PerchMetrics) -> PerchLayout {
        let size = metrics.panelSize
        let idealMaxX = windowFrame.maxX - metrics.hamsterInsetFromWindowRight + (size.width - metrics.hamsterCenterX)
        let idealMaxY = windowFrame.maxY + metrics.ledgeFromTop
        let ideal = CGPoint(x: idealMaxX - size.width, y: idealMaxY - size.height)

        var x = ideal.x
        if x + size.width > visibleFrame.maxX { x = visibleFrame.maxX - size.width }
        if x < visibleFrame.minX { x = visibleFrame.minX }

        var y = ideal.y
        if y < visibleFrame.minY { y = visibleFrame.minY }
        let maxTop = visibleFrame.maxY + max(0, metrics.ledgeFromTop - metrics.headroom)
        if y + size.height > maxTop { y = maxTop - size.height }

        let isClamped = x != ideal.x || y != ideal.y
        let frame = CGRect(origin: CGPoint(x: x.rounded(), y: y.rounded()), size: size)
        return PerchLayout(panelFrame: frame, isClamped: isClamped, topOverhang: max(0, frame.maxY - visibleFrame.maxY))
    }

    /// Where to perch when there is no eligible window: the top-right of `visibleFrame`.
    /// Lays out for an imaginary window whose top-right corner is the visible frame's top-right corner,
    /// so the hamster ends up peeking just under the menu bar.
    public static func fallbackLayout(visibleFrame: CGRect, metrics: PerchMetrics) -> PerchLayout {
        var layout = layout(windowFrame: visibleFrame, visibleFrame: visibleFrame, metrics: metrics)
        layout.isClamped = true
        return layout
    }
}
