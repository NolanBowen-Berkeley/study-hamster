import CoreGraphics
import Foundation
import HamsterUI

/// `--verify-animator`: samples every mode switch (from each mode, at several times into it, to each mode)
/// at 240 Hz and checks that nothing pops, one-shots settle, and no param is ever NaN. It also walks the
/// stage's frame schedule (`nextFrameTime`) and checks the pose never changes between two frames.
enum AnimatorVerifier {
    static let sampleRate = 240.0
    static let look = CGVector(dx: 0.35, dy: -0.2)

    /// Largest allowed change of each param between two samples 1/240 s apart. Real motion stays well
    /// below these (the fastest move, a duck from a jump's apex, is ~5.4 pt per sample); a pop — a
    /// discontinuity — shows up as a step of its full size.
    static let maxStep: [(name: String, limit: CGFloat, value: (HamsterParams) -> CGFloat)] = [
        ("rise", 6, { $0.rise }),
        ("outAmount", 0.08, { $0.outAmount }),
        ("squash", 0.06, { $0.squash }),
        ("tiltDegrees", 3, { $0.tiltDegrees }),
        ("eyeOpenness", 0.2, { $0.eyeOpenness }),
        ("lookX", 0.1, { $0.look.dx }),
        ("lookY", 0.1, { $0.look.dy }),
        ("earPerk", 0.2, { $0.earPerk }),
        ("mouthOpen", 0.15, { $0.mouthOpen }),
        ("armsUp", 0.12, { $0.armsUp }),
        ("blush", 0.1, { $0.blush }),
        ("sparkle", 0.12, { $0.sparkle }),
    ]

    fileprivate struct Worst {
        var step: CGFloat = 0
        var context = ""
    }

    final class Report {
        var failures: [String] = []
        var samples = 0
        fileprivate var worst: [String: Worst] = [:]

        func fail(_ message: String) {
            if failures.count < 40 { failures.append(message) }
            else if failures.count == 40 { failures.append("… more failures omitted") }
        }
    }

    /// Returns true when every check passed.
    static func run() -> Bool {
        let report = Report()
        let offsets: [TimeInterval] = [0, 0.03, 0.07, 0.12, 0.2, 0.3, 0.45, 0.6, 0.8, 0.94, 1.0, 1.3, 2.5, 7.77]
        var pairs = 0
        for from in HamsterMode.allCases {
            for offset in offsets {
                for to in HamsterMode.allCases {
                    checkSwitch(from: from, offset: offset, to: to, report: report)
                    pairs += 1
                }
            }
        }
        checkLongRuns(report: report)
        checkRandomSwitching(report: report)
        checkDeterminism(report: report)
        checkCheer(report: report)
        checkFrameSchedule(report: report)

        print("verify-animator: \(pairs) mode-switch cases, \(report.samples) samples at \(Int(sampleRate)) Hz")
        for entry in maxStep {
            let worst = report.worst[entry.name] ?? Worst()
            let ratio = entry.limit > 0 ? worst.step / entry.limit : 0
            print(String(format: "  %-12@ worst step %8.4f (limit %6.3f, %3.0f%%)  %@",
                         entry.name as NSString, worst.step, entry.limit, ratio * 100, worst.context as NSString))
        }
        if report.failures.isEmpty {
            print("verify-animator: PASS")
            return true
        }
        print("verify-animator: FAIL (\(report.failures.count) problems)")
        report.failures.forEach { print("  - \($0)") }
        return false
    }

    // MARK: Checks

    /// Start settled in peeking, switch to `from`, run `offset` seconds, switch to `to`, run 1.5 s.
    private static func checkSwitch(from: HamsterMode, offset: TimeInterval, to: HamsterMode, report: Report) {
        let animator = HamsterAnimator(seed: 42)
        let t0: TimeInterval = 5_000
        animator.setMode(.peeking, at: t0 - 5)
        animator.setMode(from, at: t0)
        let context = "\(from) +\(offset)s -> \(to)"
        var previous = animator.params(at: t0 - 0.25, look: look)
        var t = t0 - 0.25
        let switchTime = t0 + offset
        // Run up to the switch, sampling exactly at the switch time too.
        while t + 1 / sampleRate < switchTime - 1e-9 {
            t += 1 / sampleRate
            previous = sample(animator, at: t, previous: previous, context: context, report: report)
        }
        let before = sample(animator, at: switchTime, previous: previous, context: context, report: report)
        animator.setMode(to, at: switchTime)
        let after = animator.params(at: switchTime, look: look)
        if let field = firstDifference(before, after, tolerance: 1e-6) {
            report.fail("\(context): pose jumps at the switch instant (\(field))")
        }
        previous = after
        t = switchTime
        let end = switchTime + 1.5
        while t < end {
            t += 1 / sampleRate
            previous = sample(animator, at: t, previous: previous, context: context, report: report)
        }
        let expected = to.settlesInto ?? to
        let showing = animator.effectiveMode(at: end)
        if showing != expected {
            report.fail("\(context): shows \(showing) after 1.5 s, expected \(expected)")
        }
        if animator.isTransitioning(at: end) {
            report.fail("\(context): still transitioning after 1.5 s")
        }
        if to == .hidden, previous.rise > -129 {
            report.fail("\(context): not fully ducked after 1.5 s (rise \(previous.rise))")
        }
        if (to == .sittingOut || to == .alarm || to == .jumpingOut), previous.outAmount < 0.999 {
            report.fail("\(context): not out on the ledge after 1.5 s (outAmount \(previous.outAmount))")
        }
        if (to == .peeking || to == .jumpingBack), previous.outAmount > 0.001 {
            report.fail("\(context): not peeking after 1.5 s (outAmount \(previous.outAmount))")
        }
    }

    /// A minute of each looping mode: idle life never pops, and nothing breaks after a long time.
    private static func checkLongRuns(report: Report) {
        for mode in [HamsterMode.peeking, .sittingOut, .alarm] {
            let animator = HamsterAnimator(seed: 7)
            animator.setMode(mode, at: 0)
            var previous = animator.params(at: 0, look: look)
            var t = 0.0
            while t < 60 {
                t += 1 / sampleRate
                previous = sample(animator, at: t, previous: previous, context: "\(mode) long run", report: report)
            }
            for late in [3_600.0, 86_400.0, 1e7] {
                let p = animator.params(at: late, look: look)
                if hasNaN(p) { report.fail("\(mode): NaN at t = \(late)") }
            }
        }
        let animator = HamsterAnimator()
        if hasNaN(animator.params(at: 0, look: CGVector(dx: CGFloat.nan, dy: 1))) {
            report.fail("NaN look leaks into params")
        }
        if animator.params(at: -10, look: .zero).rise > -129 {
            report.fail("a fresh animator should start fully ducked")
        }
    }

    /// 400 switches at random moments (seeded), sampled continuously.
    private static func checkRandomSwitching(report: Report) {
        var rng = SplitMix(seed: 0xC0FFEE)
        let animator = HamsterAnimator(seed: 99)
        let modes = HamsterMode.allCases
        var t = 100.0
        animator.setMode(.peeking, at: t)
        var previous = animator.params(at: t, look: look)
        for _ in 0..<400 {
            let hold = 0.01 + rng.unit() * 1.3
            let next = t + hold
            while t + 1 / sampleRate < next {
                t += 1 / sampleRate
                previous = sample(animator, at: t, previous: previous, context: "random switching", report: report)
            }
            t = next
            previous = sample(animator, at: t, previous: previous, context: "random switching", report: report)
            let mode = modes[Int(rng.unit() * Double(modes.count)) % modes.count]
            animator.setMode(mode, at: t)
            let after = animator.params(at: t, look: look)
            if let field = firstDifference(previous, after, tolerance: 1e-6) {
                report.fail("random switching: pose jumps at switch to \(mode) (\(field))")
            }
            previous = after
        }
    }

    /// Same seed, same frames; different seeds, different idle timing.
    private static func checkDeterminism(report: Report) {
        func trace(seed: UInt64) -> [HamsterParams] {
            let animator = HamsterAnimator(seed: seed)
            animator.setMode(.peeking, at: 0)
            return stride(from: 0.0, to: 30, by: 0.05).map { animator.params(at: $0, look: .zero) }
        }
        if trace(seed: 1) != trace(seed: 1) { report.fail("animator is not deterministic for a fixed seed") }
        if trace(seed: 1) == trace(seed: 2) { report.fail("different seeds should give different idle timing") }
        let blinks = trace(seed: 1).filter { $0.eyeOpenness < 0.5 }.count
        if blinks == 0 { report.fail("no blink in 30 s of peeking") }
    }

    /// Starting a session while peeking requests `.jumpingBack`: a visible happy hop that never leaves the
    /// ledge, ends peeking, and plays again on the next start.
    private static func checkCheer(report: Report) {
        let animator = HamsterAnimator(seed: 5)
        animator.setMode(.peeking, at: 0)
        for start in [10.0, 20.0] {
            animator.setMode(.jumpingBack, at: start)
            let poses = stride(from: start, to: start + 0.7, by: 1 / sampleRate).map { animator.params(at: $0, look: .zero) }
            let context = "cheer at \(Int(start)) s"
            let maxRise = poses.map(\.rise).max() ?? 0
            if maxRise <= 8 { report.fail("\(context): no visible hop (max rise \(maxRise))") }
            if (poses.map(\.eyeOpenness).min() ?? 1) > 0.15 { report.fail("\(context): no happy closed eyes") }
            if (poses.map(\.outAmount).max() ?? 0) > 0.001 { report.fail("\(context): left the ledge") }
            if animator.effectiveMode(at: start + 0.75) != .peeking { report.fail("\(context): did not settle into peeking") }
        }
    }

    /// The stage only draws at the times `nextFrameTime` returns. Walks that schedule through settled idle
    /// modes, one-shots and random switches (re-planning at every switch, like the stage) and samples every
    /// gap longer than one 30 fps frame at 240 Hz: the pose must not change inside a gap, or the hamster
    /// would freeze mid-blink or land late. Also keeps settled idle cheap (a few frames per second).
    private static func checkFrameSchedule(report: Report) {
        let scripts: [(name: String, steps: [(mode: HamsterMode, at: TimeInterval)], end: TimeInterval)] = [
            ("peeking idle", [(.peeking, 0)], 180),
            ("sittingOut idle", [(.sittingOut, 0)], 180),
            ("peeking -> jumpingOut", [(.peeking, 0), (.jumpingOut, 6.1)], 40),
            ("sittingOut -> jumpingBack", [(.sittingOut, 0), (.jumpingBack, 9.3)], 40),
            ("peeking -> cheer", [(.peeking, 0), (.jumpingBack, 7.37)], 40),
            ("alarm -> peeking", [(.alarm, 0), (.peeking, 3.2)], 40),
            ("peeking -> hidden -> peeking", [(.peeking, 0), (.hidden, 4.4), (.peeking, 5.1)], 40),
        ]
        for script in scripts {
            let animator = HamsterAnimator(seed: 23)
            var frames = 0
            var idleSpan: TimeInterval = 0
            for (index, step) in script.steps.enumerated() {
                animator.setMode(step.mode, at: step.at)
                let until = index + 1 < script.steps.count ? script.steps[index + 1].at : script.end
                let walk = walkFrames(animator, from: step.at, to: until, context: script.name, report: report)
                frames += walk.frames
                idleSpan = until - step.at
            }
            if script.steps.count == 1 {
                let fps = Double(frames) / idleSpan
                print(String(format: "  frame schedule: %@ draws %.1f frames/s", script.name as NSString, fps))
                if fps > 10 { report.fail("\(script.name): \(fps) frames/s while idle (budget 10)") }
            }
        }
        // Ducked and settled: nothing to draw until the next mode switch.
        let animator = HamsterAnimator(seed: 23)
        animator.setMode(.peeking, at: 0)
        animator.setMode(.hidden, at: 2)
        if animator.nextFrameTime(after: 2.5) != nil { report.fail("hidden and settled should stop the frame schedule") }
        if animator.nextFrameTime(after: 2.05) == nil { report.fail("the duck itself must be drawn") }

        var rng = SplitMix(seed: 0xF00D)
        let random = HamsterAnimator(seed: 77)
        var t = 50.0
        for _ in 0..<150 {
            let mode = HamsterMode.allCases[Int(rng.unit() * Double(HamsterMode.allCases.count)) % HamsterMode.allCases.count]
            random.setMode(mode, at: t)
            let hold = 0.05 + rng.unit() * 6
            _ = walkFrames(random, from: t, to: t + hold, context: "random switching schedule", report: report)
            t += hold
        }
    }

    /// Follows `nextFrameTime` from `start` to `end`; fails where the pose changes between two frames.
    private static func walkFrames(_ animator: HamsterAnimator, from start: TimeInterval, to end: TimeInterval,
                                   context: String, report: Report) -> (frames: Int, gaps: Int) {
        var frame = start
        var frames = 0
        var gaps = 0
        while frame < end {
            frames += 1
            let next = min(animator.nextFrameTime(after: frame) ?? end, end)
            if next <= frame {
                report.fail("\(context): frame schedule does not advance at \(frame)")
                break
            }
            if next - frame > 1.0 / 30 + 1e-6 {
                gaps += 1
                let shown = animator.params(at: frame, look: .zero)
                var t = frame + 1 / sampleRate
                while t < next - 1e-9 {
                    report.samples += 1
                    if let field = firstDifference(shown, animator.params(at: t, look: .zero), tolerance: 1e-3) {
                        report.fail(String(format: "%@: pose changes between frames %.3f and %.3f (at %.3f: %@)",
                                           context, frame, next, t, field))
                        break
                    }
                    t += 1 / sampleRate
                }
            }
            frame = next
        }
        return (frames, gaps)
    }

    // MARK: Helpers

    private static func sample(_ animator: HamsterAnimator, at t: TimeInterval, previous: HamsterParams,
                               context: String, report: Report) -> HamsterParams {
        let p = animator.params(at: t, look: look)
        report.samples += 1
        if hasNaN(p) {
            report.fail("\(context): NaN at t = \(t)")
            return p
        }
        for entry in maxStep {
            let step = abs(entry.value(p) - entry.value(previous))
            if step > (report.worst[entry.name]?.step ?? 0) {
                report.worst[entry.name] = Worst(step: step, context: context)
            }
            if step > entry.limit {
                report.fail(String(format: "%@: %@ jumps %.4f (limit %.3f) at %.4f s",
                                   context, entry.name, step, entry.limit, t.truncatingRemainder(dividingBy: 100)))
            }
        }
        return p
    }

    private static func firstDifference(_ a: HamsterParams, _ b: HamsterParams, tolerance: CGFloat) -> String? {
        for entry in maxStep where abs(entry.value(a) - entry.value(b)) > tolerance {
            return "\(entry.name) \(entry.value(a)) -> \(entry.value(b))"
        }
        return nil
    }

    private static func hasNaN(_ p: HamsterParams) -> Bool {
        maxStep.contains { !$0.value(p).isFinite }
    }
}

/// Small seeded generator for the random-switching check.
struct SplitMix {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}
