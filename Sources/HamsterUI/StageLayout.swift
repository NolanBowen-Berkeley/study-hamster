import SwiftUI

/// Geometry shared by the live stage, the static snapshot frame and `StageModel`'s hit testing.
/// Panel coordinates, origin top-left. Head positions come from `HamsterFigure.hitBounds(for:)`, so any
/// figure that honours that contract lines up with the bubble and the tag.
enum StageLayout {
    static let coordinateSpace = "stage"
    static let panel = StageMetrics.panelSize
    static let ledge = StageMetrics.ledgeFromTop

    // MARK: Hamster

    /// Front paws may overhang the ledge by up to this much.
    static let pawsCut = ledge + 14

    /// Lowest visible y of the body layer: the ledge while peeking; a few points lower once fully out so
    /// the feet overlap the window edge slightly instead of looking sliced off.
    static func bodyCut(for params: HamsterParams) -> CGFloat {
        ledge + 6 * Ease.clamp01((params.outAmount - 0.75) / 0.25)
    }

    /// The front paws grip the ledge; when the hamster drops well below it (the duck, the dip at the end
    /// of jumpingBack) they let go and fade instead of dangling over the window's face.
    static func pawsOpacity(for params: HamsterParams) -> CGFloat {
        Ease.clamp01((params.rise + 20) / 8)
    }

    /// Params the front-paws layer is positioned with: gripping paws rise with the hamster when it hops, but
    /// stay on the ledge while the body sinks behind the window (the crouch, the duck, the dip of a jump
    /// back) and fade out there instead of sliding down the window's face.
    static func pawsPlacement(for params: HamsterParams) -> HamsterParams {
        var pinned = params
        pinned.rise = max(0, params.rise)
        return pinned
    }

    /// Center of the figure canvas in panel coordinates (rise applied).
    static func figureCenter(for params: HamsterParams) -> CGPoint {
        let size = HamsterFigure.designSize
        let origin = StageMetrics.figureOrigin
        return CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2 - params.rise)
    }

    /// Clickable hamster in panel coordinates: the figure's hit bounds, moved by rise and cut at the
    /// ledge (the part behind the window is not clickable). Nil while ducked.
    static func hamsterRect(for params: HamsterParams) -> CGRect? {
        guard params.rise > -100 else { return nil }
        let bounds = HamsterFigure.hitBounds(for: params)
        guard bounds.width.isFinite, bounds.height.isFinite, !bounds.isEmpty else { return nil }
        let origin = StageMetrics.figureOrigin
        var rect = bounds.offsetBy(dx: origin.x, dy: origin.y - params.rise)
        let cut = bodyCut(for: params)
        if rect.maxY > cut { rect.size.height = cut - rect.minY }
        rect = rect.intersection(CGRect(origin: .zero, size: panel))
        guard !rect.isNull, rect.height >= 6, rect.width >= 6 else { return nil }
        return rect
    }

    /// Figure-local box around the head: the top of the hit bounds (all of it while peeking; the upper
    /// part when the whole body is out).
    static func headBox(for params: HamsterParams) -> CGRect {
        let bounds = HamsterFigure.hitBounds(for: params)
        return CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: min(bounds.height, 88))
    }

    /// Approximate midpoint between the eyes, in panel coordinates.
    static func eyeCenter(for params: HamsterParams) -> CGPoint {
        let head = headBox(for: params)
        let origin = StageMetrics.figureOrigin
        return CGPoint(x: origin.x + head.midX, y: origin.y + head.midY - params.rise)
    }

    static func isOut(_ mode: HamsterMode) -> Bool {
        switch mode {
        case .jumpingOut, .sittingOut, .alarm: return true
        case .hidden, .peeking, .jumpingBack: return false
        }
    }

    // MARK: Bubble

    static let tailLength: CGFloat = 18
    static let bubbleMargin: CGFloat = 12
    /// Room kept free for the bubble's soft shadow at the panel's bottom edge.
    static let bubbleBottomMargin: CGFloat = 20

    /// Where the bubble's tail tip points: just left of the hamster's cheek, a little below eye level.
    static func bubbleAnchor(isOut: Bool) -> CGPoint {
        let pose: HamsterParams = isOut ? .sitting : .peek
        let head = headBox(for: pose)
        let origin = StageMetrics.figureOrigin
        return CGPoint(x: origin.x + head.minX - 2, y: origin.y + head.midY + 10)
    }

    /// Lowest the bubble may reach: above the standing timer tag while out, otherwise the panel bottom.
    static func bubbleMaxBottom(isOut: Bool, hasTimerTag: Bool) -> CGFloat {
        if isOut && hasTimerTag { return outTagTop - 8 }
        return panel.height - bubbleBottomMargin
    }

    /// Highest the bubble may start: a margin below the panel top, or below the part of the panel that
    /// overhangs the menu bar (`topInset`), so the bubble always stays on screen.
    static func bubbleMinTop(topInset: CGFloat) -> CGFloat {
        max(0, topInset) + bubbleMargin
    }

    /// Frame of a bubble of `size` (tail included, on its right edge) in panel coordinates: the tail tip
    /// sits on `anchor` and the body hangs about 60 % above it, clamped inside the panel. When there is not
    /// room for both, staying below `minTop` wins over `maxBottom` (the bubble then hangs lower beside the
    /// hamster, over the window, rather than under the menu bar).
    static func bubbleFrame(size: CGSize, anchor: CGPoint, maxBottom: CGFloat, minTop: CGFloat = bubbleMargin) -> CGRect {
        let x = max(bubbleMargin, anchor.x - size.width)
        let preferredTop = anchor.y - size.height * 0.6
        let top = max(minTop, min(preferredTop, maxBottom - size.height))
        return CGRect(x: x, y: top, width: size.width, height: size.height)
    }

    // MARK: Timer tag

    static let tagHeight: CGFloat = 22
    /// While peeking the tag hangs this far below the ledge, under the paws.
    static let tagHang: CGFloat = 20
    /// Horizontal offset of the tag's two strings from the hamster's centerline (behind the paws).
    static let tagStringOffset: CGFloat = 24

    /// Top-center of the hanging tag while peeking.
    static var peekTagPoint: CGPoint { CGPoint(x: StageMetrics.hamsterCenterX, y: ledge + tagHang) }

    /// Bottom-right of the tag standing on the ledge beside the sitting hamster.
    static var outTagPoint: CGPoint {
        let body = HamsterFigure.hitBounds(for: .sitting)
        return CGPoint(x: StageMetrics.figureOrigin.x + body.minX - 10, y: ledge)
    }

    static var outTagTop: CGFloat { ledge - tagHeight }
}

// MARK: - Absolute placement helpers

extension View {
    /// Places the view so its `anchor` point sits at `point` inside a top-leading `PanelCanvas`.
    func placed(at point: CGPoint, anchor: UnitPoint) -> some View {
        alignmentGuide(.leading) { d in d.width * anchor.x - point.x }
            .alignmentGuide(.top) { d in d.height * anchor.y - point.y }
    }
}

/// A panel-sized, top-leading ZStack whose coordinate system is exactly panel coordinates.
struct PanelCanvas<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.frame(width: StageLayout.panel.width, height: StageLayout.panel.height)
            content
        }
        .frame(width: StageLayout.panel.width, height: StageLayout.panel.height, alignment: .topLeading)
    }
}

/// True inside `HamsterStageFrame`: views render a static look-alike of AppKit-backed controls
/// (ImageRenderer cannot draw a live TextField) and skip focus side effects.
private struct StaticRenderingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var stageRendersStatically: Bool {
        get { self[StaticRenderingKey.self] }
        set { self[StaticRenderingKey.self] = newValue }
    }
}
