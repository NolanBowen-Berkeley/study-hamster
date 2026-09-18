import Foundation

public enum EngineEvent: Equatable, Sendable {
    /// A phase began (on start, after a natural completion, or after a skip).
    case phaseStarted(index: Int, phase: Phase)
    /// A phase ran out of time on its own (not emitted for skips).
    case phaseCompleted(index: Int, phase: Phase)
    /// The last phase ended (naturally or by skip).
    case sessionCompleted
}

public enum EngineStatus: Equatable, Sendable {
    case idle, running, paused, finished
}

/// Clock-driven pomodoro state machine. Never reads the system clock: every call takes `now`.
public final class PomodoroEngine {
    public private(set) var phases: [Phase] = []
    /// Index into `phases`; nil when idle or finished.
    public private(set) var currentIndex: Int?
    public private(set) var status: EngineStatus = .idle

    /// When the current phase ends; only meaningful while running.
    private var phaseEnd = Date.distantFuture
    /// Time left in the current phase; only meaningful while paused.
    private var pausedRemaining: TimeInterval = 0

    /// A tick at most this late continues seamlessly from the scheduled end (no drift). A later tick means
    /// the Mac slept or the app stalled, so the next phase starts fresh at `now` instead.
    private static let catchUpTolerance: TimeInterval = 2

    public init() {}

    public var currentPhase: Phase? { currentIndex.map { phases[$0] } }

    /// Starts a new session. Returns [.phaseStarted(0, first)], or [] (and stays idle) for an empty plan.
    /// Starting while a session is active replaces it.
    @discardableResult
    public func start(phases: [Phase], now: Date) -> [EngineEvent] {
        stop()
        guard !phases.isEmpty else { return [] }
        // Negative or non-finite durations would stall the clock; treat them as instantaneous phases.
        self.phases = phases.map { phase in
            var phase = phase
            if !(phase.duration.isFinite && phase.duration > 0) { phase.duration = 0 }
            return phase
        }
        return begin(index: 0, at: now)
    }

    /// Freezes the countdown. No-op unless running.
    public func pause(now: Date) {
        guard status == .running else { return }
        pausedRemaining = max(0, phaseEnd.timeIntervalSince(now))
        status = .paused
    }

    /// Continues a paused countdown. No-op unless paused.
    public func resume(now: Date) {
        guard status == .paused else { return }
        phaseEnd = now.addingTimeInterval(pausedRemaining)
        status = .running
    }

    /// Ends the current phase early. Returns [.phaseStarted(next)] or [.sessionCompleted].
    /// The next phase always starts running, even when skipping from a paused phase.
    @discardableResult
    public func skip(now: Date) -> [EngineEvent] {
        guard status == .running || status == .paused, let index = currentIndex else { return [] }
        return advance(from: index, nextStart: now)
    }

    /// Back to idle; clears the plan.
    public func stop() {
        phases = []
        currentIndex = nil
        status = .idle
        phaseEnd = .distantFuture
        pausedRemaining = 0
    }

    /// Advances time. Completes at most one phase per call: emits [.phaseCompleted, .phaseStarted] or
    /// [.phaseCompleted, .sessionCompleted] once the current phase's end has passed, [] otherwise.
    /// A tick within `catchUpTolerance` of the end starts the next phase exactly at the old end; a later
    /// one (after sleep) starts it at `now`, so a sleeping Mac never burns through several phases.
    @discardableResult
    public func tick(now: Date) -> [EngineEvent] {
        guard status == .running, let index = currentIndex, now >= phaseEnd else { return [] }
        let lateness = now.timeIntervalSince(phaseEnd)
        let nextStart = lateness <= Self.catchUpTolerance ? phaseEnd : now
        return [.phaseCompleted(index: index, phase: phases[index])] + advance(from: index, nextStart: nextStart)
    }

    /// Adds time to the current phase (running or paused). The phase's `duration` grows too, so
    /// `progress` stays meaningful. Ignores non-positive or non-finite amounts.
    public func extendCurrent(by seconds: TimeInterval, now: Date) {
        guard seconds.isFinite, seconds > 0, let index = currentIndex else { return }
        switch status {
        case .running: phaseEnd = phaseEnd.addingTimeInterval(seconds)
        case .paused: pausedRemaining += seconds
        case .idle, .finished: return
        }
        phases[index].duration += seconds
    }

    /// Seconds left in the current phase (>= 0); 0 when idle/finished.
    public func remaining(now: Date) -> TimeInterval {
        switch status {
        case .running: return max(0, phaseEnd.timeIntervalSince(now))
        case .paused: return pausedRemaining
        case .idle, .finished: return 0
        }
    }

    /// 0...1 progress through the current phase; 0 when there is no current phase.
    public func progress(now: Date) -> Double {
        guard let phase = currentPhase else { return 0 }
        guard phase.duration > 0 else { return 1 }
        return min(max(1 - remaining(now: now) / phase.duration, 0), 1)
    }

    /// Seconds left in the current phase plus all later phases.
    public func sessionRemaining(now: Date) -> TimeInterval {
        guard let index = currentIndex else { return 0 }
        return phases[(index + 1)...].reduce(remaining(now: now)) { $0 + $1.duration }
    }

    /// Focus blocks fully finished (naturally or skipped) in this session.
    public var completedFocusBlocks: Int {
        switch status {
        case .idle: return 0
        case .finished: return totalFocusBlocks
        case .running, .paused:
            guard let index = currentIndex else { return 0 }
            return phases[..<index].filter { $0.kind == .focus }.count
        }
    }

    public var totalFocusBlocks: Int { phases.filter { $0.kind == .focus }.count }

    // MARK: - Private

    /// Starts phase `index` running at `start`.
    private func begin(index: Int, at start: Date) -> [EngineEvent] {
        currentIndex = index
        status = .running
        phaseEnd = start.addingTimeInterval(phases[index].duration)
        pausedRemaining = 0
        return [.phaseStarted(index: index, phase: phases[index])]
    }

    /// Leaves phase `index` and starts the next one at `nextStart`, or finishes the session.
    private func advance(from index: Int, nextStart: Date) -> [EngineEvent] {
        let next = index + 1
        if next < phases.count {
            return begin(index: next, at: nextStart)
        }
        currentIndex = nil
        status = .finished
        phaseEnd = .distantFuture
        pausedRemaining = 0
        return [.sessionCompleted]
    }
}
