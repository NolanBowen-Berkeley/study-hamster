import Foundation

/// User-tunable pomodoro lengths.
public struct PomodoroSettings: Codable, Equatable, Sendable {
    public var focusMinutes: Double
    public var shortBreakMinutes: Double
    public var longBreakMinutes: Double
    /// A long break replaces the short break after every N focus blocks.
    public var focusBlocksBeforeLongBreak: Int

    public init(
        focusMinutes: Double = 25,
        shortBreakMinutes: Double = 5,
        longBreakMinutes: Double = 15,
        focusBlocksBeforeLongBreak: Int = 4
    ) {
        self.focusMinutes = focusMinutes
        self.shortBreakMinutes = shortBreakMinutes
        self.longBreakMinutes = longBreakMinutes
        self.focusBlocksBeforeLongBreak = focusBlocksBeforeLongBreak
    }

    public static let standard = PomodoroSettings()

    /// Clamps every field into a sane range (focus 1...180, short 1...60, long 1...120, every 1...12).
    /// A NaN length falls back to the standard value for that field.
    public func sanitized() -> PomodoroSettings {
        let standard = PomodoroSettings.standard
        return PomodoroSettings(
            focusMinutes: Self.clamp(focusMinutes, to: 1...180, nanFallback: standard.focusMinutes),
            shortBreakMinutes: Self.clamp(shortBreakMinutes, to: 1...60, nanFallback: standard.shortBreakMinutes),
            longBreakMinutes: Self.clamp(longBreakMinutes, to: 1...120, nanFallback: standard.longBreakMinutes),
            focusBlocksBeforeLongBreak: min(max(focusBlocksBeforeLongBreak, 1), 12)
        )
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>, nanFallback: Double) -> Double {
        value.isNaN ? nanFallback : min(max(value, range.lowerBound), range.upperBound)
    }
}

public enum PhaseKind: String, Codable, Sendable, CaseIterable {
    case focus, shortBreak, longBreak

    public var isBreak: Bool { self != .focus }
}

/// One timed block of a study session.
public struct Phase: Equatable, Codable, Sendable {
    public var kind: PhaseKind
    /// Seconds.
    public var duration: TimeInterval
    /// 1-based number of the focus block this phase is (or, for a break, the focus block it follows).
    public var focusNumber: Int

    public init(kind: PhaseKind, duration: TimeInterval, focusNumber: Int) {
        self.kind = kind
        self.duration = duration
        self.focusNumber = focusNumber
    }
}

public struct PlanSummary: Equatable, Sendable {
    public var focusBlocks: Int
    public var totalFocus: TimeInterval
    public var totalBreak: TimeInterval
    public var total: TimeInterval

    public init(focusBlocks: Int, totalFocus: TimeInterval, totalBreak: TimeInterval, total: TimeInterval) {
        self.focusBlocks = focusBlocks
        self.totalFocus = totalFocus
        self.totalBreak = totalBreak
        self.total = total
    }
}

public enum SessionPlanner {
    /// A trailing focus block shorter than this is merged into the previous focus block instead of
    /// being preceded by a break.
    public static let minimumFocusBlock: TimeInterval = 5 * 60

    /// Splits a total wall-clock study time (breaks included) into focus/break phases.
    ///
    /// Focus blocks of `settings.focusMinutes` alternate with breaks (a long break after every
    /// `focusBlocksBeforeLongBreak`-th block). Whenever what is left after a focus block would not fit a
    /// break plus a `minimumFocusBlock`, it is added to that focus block instead, so the plan always ends
    /// with focus and its durations add up exactly to the (whole-second) total.
    /// Returns [] for a total that is not positive and finite.
    public static func plan(totalDuration: TimeInterval, settings: PomodoroSettings) -> [Phase] {
        guard totalDuration.isFinite else { return [] }
        let total = totalDuration.rounded()
        guard total > 0 else { return [] }

        let settings = settings.sanitized()
        // Whole seconds keep every sum exact even for fractional minute settings.
        let focus = (settings.focusMinutes * 60).rounded()
        let shortBreak = (settings.shortBreakMinutes * 60).rounded()
        let longBreak = (settings.longBreakMinutes * 60).rounded()
        let every = settings.focusBlocksBeforeLongBreak

        var phases: [Phase] = []
        var remaining = total
        var focusCount = 0
        while true {
            let block = min(focus, remaining)
            focusCount += 1
            phases.append(Phase(kind: .focus, duration: block, focusNumber: focusCount))
            remaining -= block
            if remaining <= 0 { break }

            let isLong = focusCount % every == 0
            let breakLength = isLong ? longBreak : shortBreak
            if remaining <= breakLength + minimumFocusBlock {
                phases[phases.count - 1].duration += remaining
                break
            }
            phases.append(Phase(kind: isLong ? .longBreak : .shortBreak, duration: breakLength, focusNumber: focusCount))
            remaining -= breakLength
        }
        return phases
    }

    public static func summary(of phases: [Phase]) -> PlanSummary {
        var summary = PlanSummary(focusBlocks: 0, totalFocus: 0, totalBreak: 0, total: 0)
        for phase in phases {
            if phase.kind.isBreak {
                summary.totalBreak += phase.duration
            } else {
                summary.focusBlocks += 1
                summary.totalFocus += phase.duration
            }
            summary.total += phase.duration
        }
        return summary
    }
}
