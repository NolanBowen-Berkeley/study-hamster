import CoreGraphics
import Foundation

/// Easing curves. Every curve maps 0 -> 0 and 1 -> 1 and clamps its input to 0...1.
enum Ease {
    static func clamp01(_ x: CGFloat) -> CGFloat { x.isNaN ? 0 : min(max(x, 0), 1) }

    static func linear(_ x: CGFloat) -> CGFloat { clamp01(x) }

    /// Quadratic ease-in (accelerating).
    static func easeIn(_ x: CGFloat) -> CGFloat {
        let u = clamp01(x)
        return u * u
    }

    /// Quadratic ease-out (decelerating), like a thrown object slowing down under gravity.
    static func easeOut(_ x: CGFloat) -> CGFloat {
        let u = 1 - clamp01(x)
        return 1 - u * u
    }

    /// Smoothstep: gentle start and end, maximum slope 1.5.
    static func easeInOut(_ x: CGFloat) -> CGFloat {
        let u = clamp01(x)
        return u * u * (3 - 2 * u)
    }

    /// Sine ease-in: accelerates, ending with slope pi/2 (gentler than quadratic's 2).
    static func easeInSine(_ x: CGFloat) -> CGFloat {
        1 - cos(clamp01(x) * .pi / 2)
    }

    /// Ease-out that overshoots past 1 and settles back. `overshoot` 1.70158 is the classic ~10 % back.
    static func easeOutBack(_ x: CGFloat, overshoot: CGFloat = 1.70158) -> CGFloat {
        let u = clamp01(x) - 1
        return 1 + (overshoot + 1) * u * u * u + overshoot * u * u
    }

    /// Spring-ish step response 0 -> 1 over `duration` seconds: an under-damped second order system
    /// (starts with zero velocity, overshoots once, rings down). The last 40 % of the duration tapers the
    /// remaining ringing to exactly 1 so the curve ends precisely at `duration` without a pop.
    static func springStep(_ t: TimeInterval, duration: TimeInterval, omega: Double = 16, damping zeta: Double = 0.6) -> CGFloat {
        guard t > 0 else { return 0 }
        guard t < duration else { return 1 }
        let wd = omega * (1 - zeta * zeta).squareRoot()
        let envelope = exp(-zeta * omega * t)
        let residual = envelope * (cos(wd * t) + (zeta * omega / wd) * sin(wd * t))
        let taper = 1 - easeInOut(CGFloat((t / duration - 0.6) / 0.4))
        return 1 - CGFloat(residual) * taper
    }

    /// Damped cosine wobble: 1 at t = 0, oscillating at `frequency` Hz and decaying by e^(-decay t).
    static func dampedCosine(_ t: TimeInterval, frequency: Double, decay: Double) -> CGFloat {
        guard t > 0 else { return 1 }
        return CGFloat(exp(-decay * t) * cos(2 * .pi * frequency * t))
    }

    /// Smooth bump 0 -> 1 -> 0 across `x` in 0...1 (a squared sine), zero slope at both ends.
    static func bump(_ x: CGFloat) -> CGFloat {
        guard x > 0, x < 1 else { return 0 }
        let s = sin(x * .pi)
        return s * s
    }

    /// Envelope that rises over `attack`, holds, and falls over `release`, for an event of `length` s.
    static func envelope(_ t: TimeInterval, length: TimeInterval, attack: TimeInterval, release: TimeInterval) -> CGFloat {
        guard t > 0, t < length else { return 0 }
        let rise = easeInOut(CGFloat(t / attack))
        let fall = easeInOut(CGFloat((length - t) / release))
        return min(rise, fall)
    }
}

/// Linear interpolation helper.
@inline(__always) func mix(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

// MARK: - Keyframe tracks

/// How a keyframe segment is eased on its way INTO the keyframe that owns the curve.
enum Curve: Sendable {
    case linear, easeIn, easeOut, easeInOut, easeInSine, easeOutBack

    func apply(_ x: CGFloat) -> CGFloat {
        switch self {
        case .linear: return Ease.linear(x)
        case .easeIn: return Ease.easeIn(x)
        case .easeOut: return Ease.easeOut(x)
        case .easeInOut: return Ease.easeInOut(x)
        case .easeInSine: return Ease.easeInSine(x)
        case .easeOutBack: return Ease.easeOutBack(x, overshoot: 1.3)
        }
    }
}

/// Piecewise keyframed value. Continuous by construction: each segment eases from the previous
/// keyframe's value to the next one's with the next keyframe's curve.
struct Track: Sendable {
    struct Key: Sendable {
        var time: TimeInterval
        var value: CGFloat
        var curve: Curve
    }

    private let keys: [Key]

    init(_ keys: [(TimeInterval, CGFloat, Curve)]) {
        self.keys = keys.map { Key(time: $0.0, value: $0.1, curve: $0.2) }.sorted { $0.time < $1.time }
    }

    /// A track holding one value forever.
    init(constant value: CGFloat) {
        self.keys = [Key(time: 0, value: value, curve: .linear)]
    }

    func value(at t: TimeInterval) -> CGFloat {
        guard let first = keys.first, let last = keys.last else { return 0 }
        if t <= first.time { return first.value }
        if t >= last.time { return last.value }
        // Few keys per track: a linear scan is faster than anything clever.
        var previous = first
        for key in keys.dropFirst() {
            if t < key.time {
                let span = key.time - previous.time
                let u = span > 0 ? CGFloat((t - previous.time) / span) : 1
                return mix(previous.value, key.value, key.curve.apply(u))
            }
            previous = key
        }
        return last.value
    }
}

// MARK: - Deterministic pseudo-randomness

/// Stateless, seeded hash noise: the same (seed, stream, index) always gives the same number.
struct SeededNoise: Sendable {
    let seed: UInt64

    /// Uniform value in 0..<1 for the `index`-th event of `stream` (streams keep blinks, twitches, ... independent).
    func unit(_ stream: UInt64, _ index: Int) -> Double {
        var z = seed &+ stream &* 0x9E37_79B9_7F4A_7C15 &+ UInt64(bitPattern: Int64(index)) &* 0xD1B5_4A32_D192_ED03
        // SplitMix64 finalizer.
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }

    /// Uniform value in `range` for the `index`-th event of `stream`.
    func value(_ stream: UInt64, _ index: Int, in range: ClosedRange<Double>) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * unit(stream, index)
    }
}

/// Recurring random events laid out in fixed slots: event k happens at `offset + k * period + jitter_k`
/// with jitter in `-jitter...jitter`, so consecutive events are `period ± 2 * jitter` apart.
/// Looking up the events near `t` is O(1), however long the mode has been running.
struct EventSchedule: Sendable {
    var stream: UInt64
    var offset: TimeInterval
    var period: TimeInterval
    var jitter: TimeInterval

    /// Start time of event `k`.
    func start(of k: Int, noise: SeededNoise) -> TimeInterval {
        offset + Double(k) * period + noise.value(stream, k, in: -jitter...jitter)
    }

    /// Events whose start lies within `lookBack` seconds before `t` (and not after `t`), as (index, age).
    func recentEvents(at t: TimeInterval, lookBack: TimeInterval, noise: SeededNoise) -> [(index: Int, age: TimeInterval)] {
        guard t >= 0 else { return [] }
        let center = Int(((t - offset) / period).rounded(.down))
        let reach = Int((lookBack + jitter) / period) + 1
        var result: [(Int, TimeInterval)] = []
        for k in max(0, center - reach)...max(0, center + 1) {
            let age = t - start(of: k, noise: noise)
            if age >= 0 && age < lookBack { result.append((k, age)) }
        }
        return result
    }
}
