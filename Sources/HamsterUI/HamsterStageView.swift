import SwiftUI

/// The whole panel content: hamster (clipped at the ledge), front paws, timer tag and speech bubble.
/// Sized exactly StageMetrics.panelSize with a clear background.
///
/// Clicking the hamster calls `onHamsterTap` (a clear tap target follows `StageModel.hamsterRect`), so the
/// hosting view must accept first mouse and the panel must not ignore mouse events over `hitRects`.
///
/// The hamster only redraws when something moves: 60 fps through jumps and the alarm, 30 fps during idle
/// events (blinks, twitches, glances) and hover, a frame whenever the cursor moves the eyes noticeably, and
/// nothing at all in between (see `HamsterAnimator.nextFrameTime(after:)`).
public struct HamsterStageView: View {
    @ObservedObject var model: StageModel
    let onHamsterTap: () -> Void
    let onAction: (BubbleAction) -> Void

    public init(model: StageModel, onHamsterTap: @escaping () -> Void, onAction: @escaping (BubbleAction) -> Void) {
        self.model = model
        self.onHamsterTap = onHamsterTap
        self.onAction = onAction
    }

    public var body: some View {
        StageComposition(mode: model.mode, isOut: model.layoutIsOut, topInset: model.topInset,
                         bubble: model.bubble, timerTag: model.timerTag, onAction: onAction) {
            HamsterTimeline(model: model, frames: model.frames, onHamsterTap: onHamsterTap)
        }
        .onPreferenceChange(BubbleFrameKey.self) { frame in
            MainActor.assumeIsolated { model.bubbleFrame = frame }
        }
    }
}

/// The live hamster: redrawn on the frame schedule and on `frames` requests only (the bubble and the timer
/// tag updating don't touch it).
struct HamsterTimeline: View {
    let model: StageModel
    @ObservedObject var frames: StageFrameRequests
    let onHamsterTap: () -> Void

    var body: some View {
        TimelineView(StageSchedule(animator: model.animator, inputUntil: frames.until, generation: frames.generation)) { context in
            // Redraws also happen outside the schedule (a redraw request), so draw "now".
            let time = max(context.date.timeIntervalSinceReferenceDate, StageModel.now())
            let params = model.displayParams(at: time)
            HamsterLayers(params: params) {
                if let rect = StageLayout.hamsterRect(for: params) {
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: rect.width, height: rect.height)
                        .placed(at: rect.origin, anchor: .topLeading)
                        .onTapGesture(perform: onHamsterTap)
                }
            }
        }
    }
}

/// One still frame of the stage drawn from explicit params: the same composition as `HamsterStageView`
/// (hamster layers, timer tag, bubble), without the timeline. Used for PNG snapshots — `ImageRenderer`
/// does not run `TimelineView` animations. The bubble's text field is drawn as a static look-alike.
public struct HamsterStageFrame: View {
    let params: HamsterParams
    let mode: HamsterMode
    let bubble: BubbleContent?
    let timerTag: TimerTag?
    let topInset: CGFloat

    /// - Parameter mode: decides where the bubble and timer tag sit (in-front-of-window vs. out-on-the-ledge).
    /// - Parameter topInset: how far the panel's top overhangs the menu bar (see `StageModel.topInset`).
    public init(params: HamsterParams, mode: HamsterMode, bubble: BubbleContent? = nil, timerTag: TimerTag? = nil,
                topInset: CGFloat = 0) {
        self.params = params
        self.mode = mode
        self.bubble = bubble
        self.timerTag = timerTag
        self.topInset = topInset
    }

    public var body: some View {
        StageComposition(mode: mode, topInset: topInset, bubble: bubble, timerTag: timerTag, onAction: { _ in }) {
            HamsterLayers(params: params) { EmptyView() }
        }
        .environment(\.stageRendersStatically, true)
    }
}

// MARK: - Frame schedule

/// When the live stage redraws: asks the animator for each next frame, plus 30 fps until `inputUntil`
/// (the hover ease). The sequence ends while the hamster is ducked and settled. `generation` changes
/// whenever the model wants the frames re-planned (the timeline re-reads a schedule only when it changes).
struct StageSchedule: TimelineSchedule {
    let animator: HamsterAnimator
    let inputUntil: TimeInterval
    let generation: Int

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> UnfoldFirstSequence<Date> {
        let animator = animator
        let inputUntil = inputUntil
        return sequence(first: startDate) { date in
            let t = date.timeIntervalSinceReferenceDate
            var next = animator.nextFrameTime(after: t)
            if t < inputUntil {
                next = min(next ?? .infinity, t + 1.0 / 30)
            }
            return next.map { Date(timeIntervalSinceReferenceDate: $0) }
        }
    }
}

// MARK: - Composition shared by the live view and the static frame

/// Timer tag (behind), hamster, then the bubble (in front), in the "stage" coordinate space.
struct StageComposition<Hamster: View>: View {
    let mode: HamsterMode
    /// Out-on-the-ledge positions for the bubble and tag.
    var isOut: Bool
    let topInset: CGFloat
    let bubble: BubbleContent?
    let timerTag: TimerTag?
    let onAction: (BubbleAction) -> Void
    @ViewBuilder let hamster: Hamster

    init(mode: HamsterMode, isOut: Bool? = nil, topInset: CGFloat = 0, bubble: BubbleContent?, timerTag: TimerTag?,
         onAction: @escaping (BubbleAction) -> Void, @ViewBuilder hamster: () -> Hamster) {
        self.mode = mode
        self.isOut = isOut ?? StageLayout.isOut(mode)
        self.topInset = topInset
        self.bubble = bubble
        self.timerTag = timerTag
        self.onAction = onAction
        self.hamster = hamster()
    }

    var body: some View {
        let isHidden = mode == .hidden
        PanelCanvas {
            TimerTagLayer(tag: timerTag, isOut: isOut, isHamsterHidden: isHidden)
            hamster
            BubbleLayer(content: bubble, isOut: isOut, hasTimerTag: timerTag != nil,
                        minTop: StageLayout.bubbleMinTop(topInset: topInset),
                        isHamsterHidden: isHidden, onAction: onAction)
        }
        .coordinateSpace(.named(StageLayout.coordinateSpace))
    }
}

/// The hamster for one frame: the body clipped at the ledge (it is "behind" the window) and the front paws
/// in front of the window edge, overhanging it a little. `overlay` is drawn on top in panel coordinates.
struct HamsterLayers<Overlay: View>: View {
    let params: HamsterParams
    @ViewBuilder let overlay: Overlay

    var body: some View {
        PanelCanvas {
            place(HamsterFigure(params: params, layer: .body), at: params, visibleAbove: StageLayout.bodyCut(for: params))
            let pawsOpacity = StageLayout.pawsOpacity(for: params)
            if params.outAmount < 0.999 && pawsOpacity > 0 {
                place(PawsFigure(key: PawsFigure.key(for: params)).equatable(), at: StageLayout.pawsPlacement(for: params),
                      visibleAbove: StageLayout.pawsCut)
                    .opacity(pawsOpacity)
            }
            overlay
        }
    }

    private func place<Figure: View>(_ figure: Figure, at params: HamsterParams, visibleAbove cut: CGFloat) -> some View {
        let size = HamsterFigure.designSize
        return figure
            .frame(width: size.width, height: size.height)
            .position(StageLayout.figureCenter(for: params))
            .frame(width: StageLayout.panel.width, height: StageLayout.panel.height)
            .mask(alignment: .topLeading) {
                Rectangle().frame(width: StageLayout.panel.width, height: max(0, cut))
            }
            .allowsHitTesting(false)
    }
}

/// The front-paws layer, keyed only by what it draws with, so SwiftUI skips redrawing it while the face
/// animates (eyes, ears, blush and the cursor look never touch the paws).
struct PawsFigure: View, Equatable {
    let key: HamsterParams

    /// The paws depend on how far out the hamster is, squash, arms and (once out) the body's lean.
    static func key(for params: HamsterParams) -> HamsterParams {
        HamsterParams(outAmount: params.outAmount, squash: params.squash,
                      tiltDegrees: params.outAmount > 0 ? params.tiltDegrees : 0, armsUp: params.armsUp)
    }

    var body: some View {
        HamsterFigure(params: key, layer: .frontPaws)
    }
}
