import CoreGraphics
import Foundation

public enum HamsterMode: String, Equatable, Sendable, CaseIterable {
    /// Ducked fully behind the ledge (used while moving between windows, or when hidden).
    case hidden
    /// Head and paws over the ledge; idle blinks, ear twitches and glances, looking at the cursor.
    case peeking
    /// One-shot: crouch, spring out from behind the window, land sitting on the ledge. Then sittingOut.
    case jumpingOut
    /// Sitting on the ledge, fully visible (during breaks).
    case sittingOut
    /// Out on the ledge, bouncing and waving excitedly until the mode changes (alarm).
    case alarm
    /// One-shot: hop and drop back behind the window. Then peeking.
    case jumpingBack

    /// Transient modes finish on their own and become this mode.
    public var settlesInto: HamsterMode? {
        switch self {
        case .jumpingOut: return .sittingOut
        case .jumpingBack: return .peeking
        default: return nil
        }
    }
}

/// Deterministic animation: a pure function of (mode, time since the mode was set, look).
/// Times are seconds on one monotonic-ish clock (the app uses Date().timeIntervalSinceReferenceDate).
///
/// How a mode plays:
/// - Every `setMode` captures the pose showing at that instant and blends from it into the new mode
///   (0.15 s cross-fade; `rise` uses the duck curve for `.hidden` and a spring for resting modes), so a
///   switch at any moment never pops.
/// - A one-shot (`.jumpingOut`, `.jumpingBack`) plays its script, then continues as its `settlesInto` mode.
/// - Asking for an "out" resting mode (`.sittingOut`, `.alarm`) while the hamster is not out plays
///   `.jumpingOut` first; asking for `.peeking` while it is out plays `.jumpingBack` first. So the hamster
///   always jumps out for breaks and alarms, even when it was ducked or hidden.
/// - Asking for `.jumpingBack` while the hamster is already peeking at the ledge plays a happy hop in place
///   (the "Let's go!" cheer) instead, and settles back into peeking.
/// - Calling `setMode` with the mode that is already showing is a no-op (it does not restart anything); a
///   one-shot that has already finished can be requested again and replays.
/// - Resting modes hold still between sparse idle events (blinks, ear twitches, glances, little hops), so
///   `nextFrameTime(after:)` can tell the stage exactly when it needs to redraw.
public final class HamsterAnimator {
    public private(set) var mode: HamsterMode = .hidden
    public private(set) var modeStart: TimeInterval = 0

    /// Pose captured at the last `setMode` (nil before the first one: start fully ducked).
    private var captured: HamsterParams?
    /// One-shot that plays before `mode` (the one-shot itself for `.jumpingOut` / `.jumpingBack`, or the
    /// automatic jump in/out when switching between "out" and "in" resting modes).
    private var oneShot: HamsterMode?
    /// The `.jumpingBack` one-shot is the in-place cheer (requested while already peeking), not a jump back in.
    private var cheersInPlace = false
    private let noise: SeededNoise

    public init(seed: UInt64 = 0x5EED) {
        noise = SeededNoise(seed: seed)
    }

    /// Switches mode, cross-fading from the pose shown at `time` so there is never a visible pop.
    public func setMode(_ newMode: HamsterMode, at time: TimeInterval) {
        // Same mode: no-op, except that a finished one-shot may be asked for again (a second "Let's go!").
        guard newMode != mode || (newMode.settlesInto != nil && effectiveMode(at: time) != newMode) else { return }
        if let oneShot, let duration = Self.transitionDuration(of: oneShot) {
            let t = max(0, time - modeStart)
            if t < duration, Self.introNeeded(for: newMode, whenOut: oneShot == .jumpingBack) == oneShot {
                // The jump this mode needs is already in the air: let it land, only what follows changes.
                mode = newMode
                return
            }
            if t >= duration, newMode == restingMode {
                // The one-shot already settled into `newMode`: keep showing exactly the same frames,
                // re-expressed as "entered newMode when the one-shot ended".
                captured = segmentStartPose(for: oneShot, from: captured)
                self.oneShot = nil
                cheersInPlace = false
                mode = newMode
                modeStart += duration
                return
            }
        }
        let pose = rawParams(at: time)
        captured = pose
        oneShot = Self.introNeeded(for: newMode, whenOut: pose.outAmount > 0.5)
        // A jump back while already peeking at the ledge becomes the in-place cheer. (Not from deep in a duck:
        // popping up from there is the entrance, and cross-fading a ducked hamster into a hop would lurch.)
        cheersInPlace = oneShot == nil && newMode == .jumpingBack && pose.rise > -40
        if cheersInPlace { oneShot = .jumpingBack }
        mode = newMode
        modeStart = time
    }

    /// The mode actually showing at `time` (a finished jumpingOut reports sittingOut, and so on).
    public func effectiveMode(at time: TimeInterval) -> HamsterMode {
        let t = max(0, time - modeStart)
        if let oneShot, let duration = Self.transitionDuration(of: oneShot), t < duration {
            return oneShot
        }
        return restingMode
    }

    /// When the stage has to draw the next frame after `time`, or nil when nothing will move until the next
    /// `setMode` (ducked and settled). 60 fps through transitions and the alarm dance; 30 fps inside idle
    /// events (blinks, ear twitches, glance turns, little hops, the arrival grin) plus one frame after each
    /// to land on the settled pose; otherwise the start of the next idle event. Between the returned times
    /// the pose is exactly constant (the cursor `look` and hover are layered on by the stage).
    public func nextFrameTime(after time: TimeInterval) -> TimeInterval? {
        if isTransitioning(at: time) || effectiveMode(at: time) == .alarm { return time + 1.0 / 60 }
        let resting = restingMode
        guard resting == .peeking || resting == .sittingOut else { return nil }
        let restStart = modeStart + (oneShot.flatMap(Self.transitionDuration(of:)) ?? 0)
        let r = max(0, time - restStart)
        var nextStart = TimeInterval.infinity
        for window in idleActivity(of: resting, near: r) {
            if window.lowerBound <= r && r < window.upperBound { return time + 1.0 / 30 }
            if window.lowerBound > r { nextStart = min(nextStart, window.lowerBound) }
        }
        // Idle events repeat forever, so there always is a next one; the guard only protects against a bad schedule.
        guard nextStart.isFinite else { return time + 1 }
        return max(restStart + nextStart, time + 1.0 / 240)
    }

    /// True while a one-shot transition or cross-fade is playing (the stage renders at 60 fps then).
    public func isTransitioning(at time: TimeInterval) -> Bool {
        let t = max(0, time - modeStart)
        var end = Self.entryDuration(of: restingMode)
        if let oneShot, let duration = Self.transitionDuration(of: oneShot) {
            end += duration
        }
        return t < end
    }

    /// Length of the one-shot part of a mode: jumpingOut/jumpingBack durations, the duck for hidden,
    /// the pop-up for peeking; nil for looping modes.
    public static func transitionDuration(of mode: HamsterMode) -> TimeInterval? {
        switch mode {
        case .hidden: return Timing.duck
        case .peeking: return Timing.popUp
        case .jumpingOut: return Timing.jumpOut
        case .jumpingBack: return Timing.jumpBack
        case .sittingOut, .alarm: return nil
        }
    }

    public func params(at time: TimeInterval, look: CGVector) -> HamsterParams {
        var p = rawParams(at: time)
        // rawParams' look holds only the animator's own glances; the cursor look is layered on top.
        p.look = Self.clampUnit(CGVector(dx: p.look.dx + look.dx, dy: p.look.dy + look.dy))
        return p
    }
}

// MARK: - Timings

private enum Timing {
    static let crossFade: TimeInterval = 0.15
    static let duck: TimeInterval = 0.18
    static let popUp: TimeInterval = 0.4
    static let jumpOut: TimeInterval = 0.95
    static let jumpBack: TimeInterval = 0.7
    /// Rise of the fully ducked hamster.
    static let duckedRise: CGFloat = -130
    /// Fastest the duck may move, points per second (keeps even a duck from mid-jump free of big steps).
    static let maxDuckSpeed: CGFloat = 1300
}

// MARK: - Evaluation

private extension HamsterAnimator {
    /// The mode shown once the one-shot (if any) is over.
    var restingMode: HamsterMode { mode.settlesInto ?? mode }

    /// The jump to play before `mode`: out-modes need a jump out when the hamster is in, and vice versa.
    static func introNeeded(for mode: HamsterMode, whenOut isOut: Bool) -> HamsterMode? {
        switch mode {
        case .jumpingOut, .sittingOut, .alarm: return isOut ? nil : .jumpingOut
        case .jumpingBack, .peeking: return isOut ? .jumpingBack : nil
        case .hidden: return nil
        }
    }

    /// Blend-in time of a resting mode (the part that `isTransitioning` covers).
    static func entryDuration(of mode: HamsterMode) -> TimeInterval {
        mode == .hidden ? Timing.duck : Timing.popUp
    }

    /// Params without the cursor `look` (it is layered on in `params(at:look:)`, so it is never cross-faded).
    func rawParams(at time: TimeInterval) -> HamsterParams {
        let t = max(0, time - modeStart)
        var from = captured
        var restingT = t
        if let oneShot, let duration = Self.transitionDuration(of: oneShot) {
            if t < duration {
                return clamped(blend(from: from, into: script(for: oneShot).pose(at: t), at: t, restingMode: nil))
            }
            from = segmentStartPose(for: oneShot, from: from)
            restingT = t - duration
        }
        let pose = restingPose(restingMode, at: restingT)
        return clamped(blend(from: from, into: pose, at: restingT, restingMode: restingMode))
    }

    /// Pose at the very end of a one-shot, which is where the following resting mode starts from.
    func segmentStartPose(for oneShot: HamsterMode, from: HamsterParams?) -> HamsterParams {
        let duration = Self.transitionDuration(of: oneShot) ?? 0
        return clamped(blend(from: from, into: script(for: oneShot).pose(at: duration), at: duration, restingMode: nil))
    }

    /// Blends the captured pose into the target pose. `restingMode` nil means a scripted one-shot.
    func blend(from: HamsterParams?, into target: HamsterParams, at t: TimeInterval, restingMode: HamsterMode?) -> HamsterParams {
        guard let from else { return target }
        let w = Ease.easeInOut(CGFloat(t / Timing.crossFade))
        var p = HamsterParams.lerp(from, target, w)
        switch restingMode {
        case .hidden?:
            // The duck: accelerate down from wherever we were. Mostly a sine ease-in, blended towards linear
            // when the distance is large so the hamster never moves faster than maxDuckSpeed.
            let distance = abs(target.rise - from.rise)
            let u = CGFloat(t / Timing.duck)
            let linearSpeed = distance / CGFloat(Timing.duck)
            let sineShare = linearSpeed > 0
                ? Ease.clamp01((Timing.maxDuckSpeed / linearSpeed - 1) / (.pi / 2 - 1))
                : 1
            let curve = mix(Ease.linear(u), Ease.easeInSine(u), sineShare)
            p.rise = mix(from.rise, target.rise, curve)
        case .peeking?, .sittingOut?, .alarm?:
            // Pop-up: the mode's own motion runs underneath while the starting offset springs away.
            let startOffset = from.rise - restingPose(restingMode ?? .peeking, at: 0).rise
            p.rise = target.rise + startOffset * (1 - Ease.springStep(t, duration: Timing.popUp))
        default:
            break
        }
        return p
    }

    func clamped(_ p: HamsterParams) -> HamsterParams {
        var q = p
        q.outAmount = Ease.clamp01(p.outAmount)
        q.eyeOpenness = Ease.clamp01(p.eyeOpenness)
        q.mouthOpen = Ease.clamp01(p.mouthOpen)
        q.armsUp = Ease.clamp01(p.armsUp)
        q.blush = Ease.clamp01(p.blush)
        q.sparkle = Ease.clamp01(p.sparkle)
        q.earPerk = min(max(p.earPerk, -1), 1)
        q.squash = min(max(p.squash, 0.5), 1.5)
        return q
    }

    static func clampUnit(_ v: CGVector) -> CGVector {
        guard v.dx.isFinite, v.dy.isFinite else { return .zero }
        let length = (v.dx * v.dx + v.dy * v.dy).squareRoot()
        guard length > 1 else { return v }
        return CGVector(dx: v.dx / length, dy: v.dy / length)
    }
}

// MARK: - Resting modes (looping idle life)

private extension HamsterAnimator {
    static let blinks = EventSchedule(stream: 1, offset: 2.0, period: 4.25, jitter: 0.9)
    static let earTwitches = EventSchedule(stream: 2, offset: 3.0, period: 7.0, jitter: 1.0)
    static let glances = EventSchedule(stream: 3, offset: 5.0, period: 9.5, jitter: 2.0)
    static let outings = EventSchedule(stream: 4, offset: 4.0, period: 8.0, jitter: 1.0)

    /// Idle pose of a resting mode `t` seconds after it started (one-shots rest as the mode they settle into).
    /// Peeking and sitting out hold perfectly still between sparse events (see `idleActivity`), so the stage
    /// only redraws while something actually moves: there is no continuous breathing or sway.
    func restingPose(_ mode: HamsterMode, at t: TimeInterval) -> HamsterParams {
        switch mode {
        case .hidden:
            return HamsterParams(rise: Timing.duckedRise, earPerk: -0.5, blush: 0.4)
        case .peeking, .jumpingBack:
            let glance = glance(at: t)
            var p = HamsterParams()
            p.tiltDegrees = 3 * glance.amount * glance.side
            p.eyeOpenness = eyeOpenness(at: t)
            p.earPerk = earTwitch(at: t) + 0.3 * glance.amount
            p.look = glance.look
            return p
        case .sittingOut, .jumpingOut:
            var p = HamsterParams.sitting
            p.eyeOpenness = eyeOpenness(at: t)
            p.earPerk = earTwitch(at: t)
            p.look = glance(at: t).look
            // Still grinning for a moment after arriving on the ledge.
            p.mouthOpen = 0.5 * (1 - Ease.easeInOut(CGFloat(t / 1.4)))
            applyOuting(to: &p, at: t)
            return p
        case .alarm:
            return alarmPose(at: t)
        }
    }

    /// Resting-time windows `[start, end)` around `r` in which `mode`'s idle pose moves (the pose is constant
    /// everywhere else): blinks (a double blink lasts 0.38 s), ear twitches, a glance's turn and return (its
    /// hold is still), and while sitting out the arrival grin and the little hops and waves.
    func idleActivity(of mode: HamsterMode, near r: TimeInterval) -> [Range<TimeInterval>] {
        var windows: [Range<TimeInterval>] = []
        func add(_ schedule: EventSchedule, _ spans: (Int, TimeInterval) -> [Range<TimeInterval>]) {
            let center = Int(((r - schedule.offset) / schedule.period).rounded(.down))
            for k in max(0, center - 1)...max(0, center + 2) {
                let s = schedule.start(of: k, noise: noise)
                windows += spans(k, s)
            }
        }
        add(Self.blinks) { k, s in [s..<(s + (noise.unit(11, k) < 0.22 ? 0.38 : 0.14))] }
        add(Self.earTwitches) { _, s in [s..<(s + 0.4)] }
        add(Self.glances) { k, s in noise.unit(31, k) < 0.6 ? [s..<(s + 0.3), (s + 1.25)..<(s + 1.6)] : [] }
        if mode == .sittingOut {
            windows.append(0..<1.4)
            add(Self.outings) { k, s in [s..<(s + (noise.unit(41, k) < 0.6 ? 0.5 : 1.5))] }
        }
        return windows
    }

    /// 1 with quick blinks every 2.5–6 s; about one blink in five is a double blink.
    func eyeOpenness(at t: TimeInterval) -> CGFloat {
        var closed: CGFloat = 0
        for event in Self.blinks.recentEvents(at: t, lookBack: 0.5, noise: noise) {
            closed = max(closed, blinkPulse(event.age))
            if noise.unit(11, event.index) < 0.22 {
                closed = max(closed, blinkPulse(event.age - 0.24))
            }
        }
        return 1 - closed
    }

    /// 0 -> 1 -> 0 over 0.14 s: close 0.06 s, hold 0.02 s, open 0.06 s.
    func blinkPulse(_ age: TimeInterval) -> CGFloat {
        guard age > 0, age < 0.14 else { return 0 }
        if age < 0.06 { return Ease.easeInOut(CGFloat(age / 0.06)) }
        if age < 0.08 { return 1 }
        return 1 - Ease.easeInOut(CGFloat((age - 0.08) / 0.06))
    }

    /// Quick double flick of the ears every 5–9 s.
    func earTwitch(at t: TimeInterval) -> CGFloat {
        var perk: CGFloat = 0
        for event in Self.earTwitches.recentEvents(at: t, lookBack: 0.4, noise: noise) {
            let u = CGFloat(event.age / 0.4)
            let strength: CGFloat = noise.unit(21, event.index) < 0.5 ? 0.45 : 0.6
            perk += strength * sin(2 * .pi * u * 2) * (1 - u) * (1 - u)
        }
        return perk
    }

    /// Occasional curious look to one side: envelope 0...1, side ±1 and the pupil offset it adds.
    func glance(at t: TimeInterval) -> (amount: CGFloat, side: CGFloat, look: CGVector) {
        for event in Self.glances.recentEvents(at: t, lookBack: 1.6, noise: noise) where noise.unit(31, event.index) < 0.6 {
            let amount = Ease.envelope(event.age, length: 1.6, attack: 0.3, release: 0.35)
            let side: CGFloat = noise.unit(32, event.index) < 0.5 ? -1 : 1
            let dx = side * CGFloat(noise.value(33, event.index, in: 0.45...0.75))
            let dy = CGFloat(noise.value(34, event.index, in: -0.35...0.15))
            return (amount, side, CGVector(dx: dx * amount, dy: dy * amount))
        }
        return (0, 0, .zero)
    }

    /// Sitting out: every 6–10 s a little hop (10 pt) or a wave.
    func applyOuting(to p: inout HamsterParams, at t: TimeInterval) {
        for event in Self.outings.recentEvents(at: t, lookBack: 1.5, noise: noise) {
            if noise.unit(41, event.index) < 0.6 {
                let hop = Self.littleHop
                p.rise += hop.rise.value(at: event.age)
                p.squash *= hop.squash.value(at: event.age)
                p.earPerk += hop.earPerk.value(at: event.age)
            } else {
                let amount = Ease.envelope(event.age, length: 1.5, attack: 0.3, release: 0.35)
                let wave = CGFloat(sin(2 * .pi * event.age / 0.45))
                p.armsUp = max(p.armsUp, amount * (0.7 + 0.15 * wave))
                p.tiltDegrees += amount * 3 * wave
                p.mouthOpen = max(p.mouthOpen, 0.55 * amount)
                p.earPerk += 0.4 * amount
            }
        }
    }

    /// Relative offsets of the little hop while sitting out (0.5 s).
    static let littleHop = (
        rise: Track([(0, 0, .linear), (0.1, -1.5, .easeInOut), (0.25, 10, .easeOut), (0.42, 0, .easeIn), (0.5, 0, .linear)]),
        squash: Track([(0, 1, .linear), (0.1, 0.92, .easeInOut), (0.16, 1.06, .easeOut), (0.36, 1.0, .easeInOut),
                       (0.42, 0.93, .easeOut), (0.5, 1, .easeInOut)]),
        earPerk: Track([(0, 0, .linear), (0.1, -0.2, .easeInOut), (0.25, 0.5, .easeOut), (0.5, 0, .easeInOut)])
    )

    /// Alarm: hopping in place (period 0.5 s, 18 pt), arms waving, big grin, sparkles.
    func alarmPose(at t: TimeInterval) -> HamsterParams {
        let period = 0.5
        let phase = CGFloat((t / period).truncatingRemainder(dividingBy: 1))
        let contact: CGFloat = 0.2
        var p = HamsterParams.sitting
        if phase > contact {
            let q = (phase - contact) / (1 - contact)
            p.rise = 18 * 4 * q * (1 - q)
        }
        // Squash just after each landing, a little stretch at take-off.
        p.squash = 1 - 0.17 * pulse(phase, center: 0.05, width: 0.07) + 0.07 * pulse(phase, center: 0.28, width: 0.08)
        p.armsUp = 0.8 + 0.2 * CGFloat(sin(2 * .pi * t / 0.35))
        p.mouthOpen = 1
        p.sparkle = 0.85 + 0.15 * CGFloat(sin(2 * .pi * t / 0.8))
        p.earPerk = 0.85 + 0.15 * CGFloat(sin(2 * .pi * t / 0.5 + 1))
        p.tiltDegrees = 5 * CGFloat(sin(2 * .pi * t / 1.0))
        p.eyeOpenness = eyeOpenness(at: t)
        p.blush = 0.8
        return p
    }

    /// Gaussian pulse on a phase circle (0...1 wraps).
    func pulse(_ phase: CGFloat, center: CGFloat, width: CGFloat) -> CGFloat {
        var d = abs(phase - center)
        d = min(d, 1 - d)
        return exp(-(d / width) * (d / width))
    }
}

// MARK: - One-shot scripts

/// Keyframed params for a one-shot mode.
private struct Script {
    var rise, outAmount, squash, tilt, eyeOpenness, earPerk, mouthOpen, armsUp, blush, sparkle: Track

    func pose(at t: TimeInterval) -> HamsterParams {
        HamsterParams(
            rise: rise.value(at: t),
            outAmount: outAmount.value(at: t),
            squash: squash.value(at: t),
            tiltDegrees: tilt.value(at: t),
            eyeOpenness: eyeOpenness.value(at: t),
            earPerk: earPerk.value(at: t),
            mouthOpen: mouthOpen.value(at: t),
            armsUp: armsUp.value(at: t),
            blush: blush.value(at: t),
            sparkle: sparkle.value(at: t)
        )
    }
}

private extension HamsterAnimator {
    func script(for oneShot: HamsterMode) -> Script {
        guard oneShot == .jumpingBack else { return Self.jumpOutScript }
        return cheersInPlace ? Self.cheerScript : Self.jumpBackScript
    }

    /// Crouch 0–0.15, launch 0.15–0.5 (apex +80), fall 0.5–0.75, land & settle 0.75–0.95.
    static let jumpOutScript = Script(
        rise: Track([(0, 0, .linear), (0.15, -10, .easeInOut), (0.5, 80, .easeOut), (0.75, 0, .easeIn),
                     (0.85, 2, .easeOut), (0.95, 0, .easeInOut)]),
        outAmount: Track([(0, 0, .linear), (0.18, 0, .linear), (0.52, 1, .easeInOut)]),
        squash: Track([(0, 1, .linear), (0.15, 0.85, .easeInOut), (0.22, 1.15, .easeOut), (0.45, 1.0, .easeInOut),
                       (0.7, 1.05, .easeInOut), (0.78, 0.8, .easeOut), (0.88, 1.04, .easeInOut), (0.95, 1, .easeInOut)]),
        tilt: Track([(0, 0, .linear), (0.15, 0, .linear), (0.4, -6, .easeInOut), (0.7, 4, .easeInOut), (0.95, 0, .easeInOut)]),
        eyeOpenness: Track([(0, 1, .linear), (0.15, 0.55, .easeInOut), (0.25, 1, .easeOut), (0.76, 1, .linear),
                            (0.82, 0.08, .easeInOut), (0.87, 0.08, .linear), (0.95, 1, .easeInOut)]),
        earPerk: Track([(0, 0, .linear), (0.15, -0.4, .easeInOut), (0.3, 1, .easeOut), (0.6, 0.6, .easeInOut),
                        (0.8, -0.2, .easeInOut), (0.95, 0, .easeInOut)]),
        mouthOpen: Track([(0, 0, .linear), (0.15, 0.2, .easeInOut), (0.3, 1, .easeOut), (0.7, 0.8, .easeInOut),
                          (0.95, 0.5, .easeInOut)]),
        armsUp: Track([(0, 0, .linear), (0.15, 0, .linear), (0.3, 1, .easeOut), (0.55, 1, .linear),
                       (0.75, 0.3, .easeInOut), (0.95, 0, .easeInOut)]),
        blush: Track([(0, 0.4, .linear), (0.5, 0.8, .easeInOut), (0.95, 0.4, .easeInOut)]),
        sparkle: Track([(0, 0, .linear), (0.2, 0, .linear), (0.35, 1, .easeOut), (0.7, 1, .linear), (0.95, 0, .easeInOut)])
    )

    /// Crouch, hop up (+20), drop behind the ledge (-25) and bob back up to grip it again.
    static let jumpBackScript = Script(
        rise: Track([(0, 0, .linear), (0.08, -4, .easeOut), (0.25, 20, .easeOut), (0.48, -25, .easeIn),
                     (0.7, 0, .easeOutBack)]),
        outAmount: Track([(0, 1, .linear), (0.22, 1, .linear), (0.48, 0, .easeInOut)]),
        squash: Track([(0, 1, .linear), (0.08, 0.88, .easeInOut), (0.18, 1.1, .easeOut), (0.3, 1.0, .easeInOut),
                       (0.48, 1.05, .easeInOut), (0.56, 0.92, .easeOut), (0.7, 1, .easeInOut)]),
        tilt: Track([(0, 0, .linear), (0.25, 4, .easeInOut), (0.5, -3, .easeInOut), (0.7, 0, .easeInOut)]),
        eyeOpenness: Track([(0, 1, .linear), (0.08, 0.6, .easeInOut), (0.2, 1, .easeOut)]),
        earPerk: Track([(0, 0, .linear), (0.2, 0.6, .easeOut), (0.48, -0.3, .easeInOut), (0.7, 0, .easeInOut)]),
        mouthOpen: Track([(0, 0.3, .linear), (0.25, 0.6, .easeOut), (0.6, 0, .easeInOut)]),
        armsUp: Track([(0, 0, .linear), (0.1, 0, .linear), (0.25, 0.7, .easeOut), (0.45, 0.2, .easeInOut), (0.7, 0, .easeInOut)]),
        blush: Track(constant: 0.4),
        sparkle: Track([(0, 0, .linear), (0.2, 0.3, .easeOut), (0.5, 0, .easeInOut)])
    )

    /// The "Let's go!" cheer while peeking (0.7 s, never leaves the ledge): a crouch and a happy hop (+12) with
    /// the paws up by the cheeks, happy closed eyes, a grin and a little head wiggle, then a small second
    /// bounce. Every track ends on the resting peek pose so the idle life continues without a pop.
    static let cheerScript = Script(
        rise: Track([(0, 0, .linear), (0.08, -4, .easeOut), (0.25, 12, .easeOut), (0.42, 0, .easeIn),
                     (0.55, 4, .easeOut), (0.7, 0, .easeInOut)]),
        outAmount: Track(constant: 0),
        squash: Track([(0, 1, .linear), (0.08, 0.9, .easeInOut), (0.2, 1.08, .easeOut), (0.42, 0.94, .easeInOut),
                       (0.55, 1.02, .easeInOut), (0.7, 1, .easeInOut)]),
        tilt: Track([(0, 0, .linear), (0.15, -5, .easeInOut), (0.35, 5, .easeInOut), (0.55, -2, .easeInOut),
                     (0.7, 0, .easeInOut)]),
        eyeOpenness: Track([(0, 1, .linear), (0.08, 1, .linear), (0.18, 0.1, .easeInOut), (0.5, 0.1, .linear),
                            (0.62, 1, .easeInOut)]),
        earPerk: Track([(0, 0, .linear), (0.12, -0.2, .easeInOut), (0.27, 0.8, .easeOut), (0.5, 0.5, .easeInOut),
                        (0.7, 0, .easeInOut)]),
        mouthOpen: Track([(0, 0, .linear), (0.2, 0.9, .easeOut), (0.5, 0.7, .linear), (0.68, 0, .easeInOut)]),
        armsUp: Track([(0, 0, .linear), (0.1, 0, .linear), (0.25, 0.6, .easeOut), (0.45, 0.6, .linear),
                       (0.66, 0, .easeInOut)]),
        blush: Track([(0, 0.4, .linear), (0.25, 0.8, .easeInOut), (0.7, 0.4, .easeInOut)]),
        sparkle: Track([(0, 0, .linear), (0.15, 0, .linear), (0.3, 0.6, .easeOut), (0.5, 0.5, .linear),
                        (0.68, 0, .easeInOut)])
    )
}
