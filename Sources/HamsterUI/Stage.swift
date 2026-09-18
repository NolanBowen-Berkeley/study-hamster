import Combine
import SwiftUI

/// Fixed layout of the transparent panel that hosts the stage. SwiftUI coordinates: origin top-left.
public enum StageMetrics {
    public static let panelSize = CGSize(width: 460, height: 380)
    /// y of the ledge line (the target window's top edge) inside the panel.
    public static let ledgeFromTop: CGFloat = 240
    /// x of the hamster's centerline inside the panel.
    public static let hamsterCenterX: CGFloat = 382
    /// How far left of the window's right edge the hamster's centerline sits.
    public static let hamsterInsetFromWindowRight: CGFloat = 70
    /// Room the peeking hamster needs between the ledge and the menu bar (ear tips perked ≈ 88 pt). A window
    /// whose top is closer to the menu bar than this gets him peeking from just inside its top instead.
    public static let peekHeadroom: CGFloat = 96
    /// The same while out on the ledge: sitting is ≈ 149 pt tall and the alarm hops reach ≈ 167 pt.
    public static let outHeadroom: CGFloat = 170
    /// Top-left of the HamsterFigure canvas inside the panel when rise == 0.
    public static var figureOrigin: CGPoint {
        CGPoint(x: hamsterCenterX - HamsterFigure.designSize.width / 2, y: ledgeFromTop - HamsterFigure.ledgeY)
    }
}

// MARK: - Bubble content (plain data; the app fills it, the stage renders it)

public struct QuickPick: Equatable, Identifiable, Sendable {
    public var label: String
    public var seconds: TimeInterval
    public var id: String { label }

    public init(label: String, seconds: TimeInterval) {
        self.label = label
        self.seconds = seconds
    }
}

public struct AskDurationInfo: Equatable, Sendable {
    public var prompt: String
    public var text: String
    public var placeholder: String
    public var error: String?
    public var hint: String?
    public var quickPicks: [QuickPick]

    public init(prompt: String, text: String = "", placeholder: String = "e.g. 1h 30m", error: String? = nil, hint: String? = nil, quickPicks: [QuickPick] = []) {
        self.prompt = prompt
        self.text = text
        self.placeholder = placeholder
        self.error = error
        self.hint = hint
        self.quickPicks = quickPicks
    }
}

public struct StatusInfo: Equatable, Sendable {
    public var title: String
    public var remaining: String
    public var detail: String
    public var progress: Double
    public var isBreak: Bool
    public var isPaused: Bool

    public init(title: String, remaining: String, detail: String, progress: Double, isBreak: Bool, isPaused: Bool) {
        self.title = title
        self.remaining = remaining
        self.detail = detail
        self.progress = progress
        self.isBreak = isBreak
        self.isPaused = isPaused
    }
}

public enum MessageStyle: Equatable, Sendable {
    case info, breakTime, backToWork, celebration
}

public struct MessageButton: Equatable, Identifiable, Sendable {
    public var title: String
    public var action: BubbleAction
    public var isPrimary: Bool
    public var id: String { title }

    public init(title: String, action: BubbleAction, isPrimary: Bool = false) {
        self.title = title
        self.action = action
        self.isPrimary = isPrimary
    }
}

public struct MessageInfo: Equatable, Sendable {
    public var title: String
    public var detail: String?
    public var style: MessageStyle
    public var buttons: [MessageButton]

    public init(title: String, detail: String? = nil, style: MessageStyle = .info, buttons: [MessageButton] = []) {
        self.title = title
        self.detail = detail
        self.style = style
        self.buttons = buttons
    }
}

public enum BubbleContent: Equatable, Sendable {
    case askDuration(AskDurationInfo)
    case status(StatusInfo)
    case message(MessageInfo)
}

public enum BubbleAction: Equatable, Sendable {
    case submitDuration(String)
    case start(seconds: TimeInterval)
    case pause, resume, skip, stop
    case extend(minutes: Int)
    case dismiss
    case acknowledge
    case openSettings
}

/// Small countdown tag shown next to the hamster during a session.
public struct TimerTag: Equatable, Sendable {
    public var text: String
    public var isBreak: Bool
    public var isPaused: Bool

    public init(text: String, isBreak: Bool, isPaused: Bool) {
        self.text = text
        self.isBreak = isBreak
        self.isPaused = isPaused
    }
}

// MARK: - Model

/// Shared state between the app controller and the SwiftUI stage.
@MainActor
public final class StageModel: ObservableObject {
    public let animator: HamsterAnimator

    @Published public var bubble: BubbleContent?
    @Published public var timerTag: TimerTag?
    /// Mirrors the animator's requested mode (the bubble and tag fade out while it is `.hidden`); set it via
    /// `setMode`.
    @Published public private(set) var mode: HamsterMode = .hidden
    /// How far the top of the panel sticks out above the screen's visible frame (it may overhang the menu bar
    /// when the window is close to the top). The bubble stays below this line.
    @Published public var topInset: CGFloat = 0
    /// Whether the bubble and timer tag use their "out on the ledge" positions. Follows the mode but ignores
    /// `.hidden`, so ducking to move to another window during a break doesn't slide them to the peek spots.
    @Published private(set) var layoutIsOut = false

    /// Where the pupils should point, each component -1...1. Updated ~30x/s by the app; read every frame.
    /// The hamster only redraws for it when it moved noticeably (the pupils lag by at most `lookStep`, about
    /// 0.2 pt) and at most `lookFrameInterval` apart; the app's next poll catches up on anything skipped.
    public var look: CGVector = .zero {
        didSet {
            guard abs(look.dx - drawnLook.dx) >= Self.lookStep || abs(look.dy - drawnLook.dy) >= Self.lookStep else { return }
            let t = StageModel.now()
            guard t - lastLookFrame >= Self.lookFrameInterval else { return }
            lastLookFrame = t
            drawnLook = look
            frames.redraw()
        }
    }
    /// True while the mouse is over the hamster. The ear/blush reaction eases in and out over ~0.15 s.
    public var isHovered: Bool = false {
        didSet {
            guard isHovered != oldValue else { return }
            let t = StageModel.now()
            // Start the new ease from wherever the previous one had got to (it was heading for `oldValue`).
            let u = Ease.easeInOut(CGFloat((t - hoverChanged) / Self.hoverEase))
            hoverFrom = mix(hoverFrom, oldValue ? 1 : 0, u)
            hoverChanged = t
            frames.redraw(until: t + Self.hoverEase)
        }
    }
    /// Current bubble frame in panel coordinates (reported by the view; nil when no bubble is shown).
    public internal(set) var bubbleFrame: CGRect?

    /// Redraw requests for the hamster layer alone (cursor, hover, mode switches), kept apart from this
    /// model's own changes so a cursor move doesn't rebuild the bubble and the tag.
    let frames = StageFrameRequests()

    private static let hoverEase: TimeInterval = 0.15
    private static let lookStep: CGFloat = 0.06
    private static let lookFrameInterval: TimeInterval = 1.0 / 20
    private var drawnLook: CGVector = .zero
    private var lastLookFrame: TimeInterval = -.infinity
    private var hoverFrom: CGFloat = 0
    private var hoverChanged: TimeInterval = -.infinity

    public init(animator: HamsterAnimator = HamsterAnimator()) {
        self.animator = animator
    }

    public nonisolated static func now() -> TimeInterval { Date().timeIntervalSinceReferenceDate }

    public func setMode(_ newMode: HamsterMode, at time: TimeInterval = StageModel.now()) {
        animator.setMode(newMode, at: time)
        frames.redraw()
        mode = newMode
        if newMode != .hidden, layoutIsOut != StageLayout.isOut(newMode) {
            layoutIsOut = StageLayout.isOut(newMode)
        }
    }

    /// Panel-coordinate rects that should receive mouse clicks at `time`: the visible hamster (above the
    /// ledge, excluding the front paws) and the bubble. Everything else passes clicks through.
    public func hitRects(at time: TimeInterval) -> [CGRect] {
        var rects: [CGRect] = []
        if let hamster = hamsterRect(at: time) { rects.append(hamster) }
        // While ducked the bubble is faded out, so it must not swallow clicks either.
        if mode != .hidden, let bubbleFrame, !bubbleFrame.isEmpty { rects.append(bubbleFrame) }
        return rects
    }

    /// Panel-coordinate rect of the clickable hamster at `time` (nil when hidden).
    public func hamsterRect(at time: TimeInterval) -> CGRect? {
        StageLayout.hamsterRect(for: displayParams(at: time))
    }

    /// Panel-coordinate center of the hamster's eyes at `time` (for computing `look`).
    public func eyeCenter(at time: TimeInterval) -> CGPoint {
        StageLayout.eyeCenter(for: displayParams(at: time))
    }

    /// The params the stage draws at `time`: the animator's pose plus the hover reaction.
    func displayParams(at time: TimeInterval) -> HamsterParams {
        animator.params(at: time, look: look).hovered(hoverAmount(at: time))
    }

    /// 0...1, easing towards `isHovered` over 0.15 s.
    private func hoverAmount(at time: TimeInterval) -> CGFloat {
        let target: CGFloat = isHovered ? 1 : 0
        let u = Ease.easeInOut(CGFloat((time - hoverChanged) / Self.hoverEase))
        return mix(hoverFrom, target, u)
    }
}

/// Asks the hamster layer to draw now and re-plan its frames. The timeline re-reads its schedule only when
/// the schedule value changes, so every request bumps `generation`.
@MainActor
final class StageFrameRequests: ObservableObject {
    private(set) var generation = 0
    /// Keep drawing at least until this time (the hover ease).
    private(set) var until: TimeInterval = -.infinity

    func redraw(until time: TimeInterval? = nil) {
        if let time { until = max(until, time) }
        generation += 1
        objectWillChange.send()
    }
}

extension HamsterParams {
    /// The hover reaction: ears perk up a bit and the cheeks blush. `amount` 0...1.
    public func hovered(_ amount: CGFloat = 1) -> HamsterParams {
        let a = Ease.clamp01(amount)
        guard a > 0 else { return self }
        var p = self
        p.earPerk = min(1, earPerk + 0.4 * a)
        p.blush = min(1, blush + 0.35 * a)
        return p
    }
}
