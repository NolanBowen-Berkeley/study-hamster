import Foundation
import HamsterCore

/// A realistic reference time; whole and half seconds stay exact at this magnitude.
private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

private let focus1 = Phase(kind: .focus, duration: 1500, focusNumber: 1)
private let short1 = Phase(kind: .shortBreak, duration: 300, focusNumber: 1)
private let focus2 = Phase(kind: .focus, duration: 1500, focusNumber: 2)
private let long2 = Phase(kind: .longBreak, duration: 900, focusNumber: 2)
private let focus3 = Phase(kind: .focus, duration: 600, focusNumber: 3)
/// F25 S5 F25 L15 F10 = 4800 s, 3 focus blocks.
private let plan = [focus1, short1, focus2, long2, focus3]

private func startedEngine(_ phases: [Phase] = plan, at start: Date = t0) -> PomodoroEngine {
    let engine = PomodoroEngine()
    engine.start(phases: phases, now: start)
    return engine
}

func runEngineChecks() {
    section("PomodoroEngine idle") {
        let engine = PomodoroEngine()
        checkEqual(engine.status, .idle)
        checkEqual(engine.currentIndex, nil)
        checkEqual(engine.currentPhase, nil)
        checkEqual(engine.phases, [])
        checkEqual(engine.remaining(now: t0), 0)
        checkEqual(engine.progress(now: t0), 0)
        checkEqual(engine.sessionRemaining(now: t0), 0)
        checkEqual(engine.completedFocusBlocks, 0)
        checkEqual(engine.totalFocusBlocks, 0)
        checkEqual(engine.tick(now: at(10_000)), [], "tick while idle")
        checkEqual(engine.skip(now: t0), [], "skip while idle")
        engine.pause(now: t0)
        checkEqual(engine.status, .idle, "pause while idle is a no-op")
        engine.resume(now: t0)
        checkEqual(engine.status, .idle, "resume while idle is a no-op")
        engine.extendCurrent(by: 300, now: t0)
        checkEqual(engine.phases, [], "extend while idle is a no-op")
    }

    section("PomodoroEngine start") {
        let engine = PomodoroEngine()
        checkEqual(engine.start(phases: [], now: t0), [], "empty plan")
        checkEqual(engine.status, .idle, "empty plan stays idle")

        checkEqual(engine.start(phases: plan, now: t0), [.phaseStarted(index: 0, phase: focus1)])
        checkEqual(engine.status, .running)
        checkEqual(engine.currentIndex, 0)
        checkEqual(engine.currentPhase, focus1)
        checkEqual(engine.phases, plan)
        checkEqual(engine.remaining(now: t0), 1500)
        checkEqual(engine.progress(now: t0), 0)
        checkEqual(engine.sessionRemaining(now: t0), 4800)
        checkEqual(engine.completedFocusBlocks, 0)
        checkEqual(engine.totalFocusBlocks, 3)

        // Starting while running replaces the old session.
        engine.tick(now: at(1500))
        let other = [Phase(kind: .focus, duration: 600, focusNumber: 1)]
        checkEqual(engine.start(phases: other, now: at(1600)), [.phaseStarted(index: 0, phase: other[0])], "restart")
        checkEqual(engine.phases, other, "restart replaces the plan")
        checkEqual(engine.currentIndex, 0, "restart begins at the first phase")
        checkEqual(engine.remaining(now: at(1600)), 600, "restart timing")
        checkEqual(engine.completedFocusBlocks, 0, "restart resets progress")
        checkEqual(engine.totalFocusBlocks, 1)

        // Starting an empty plan over a running session leaves the engine idle and cleared.
        checkEqual(engine.start(phases: [], now: at(1700)), [], "empty restart")
        checkEqual(engine.status, .idle, "empty restart is idle")
        checkEqual(engine.phases, [], "empty restart clears the plan")
        checkEqual(engine.tick(now: at(99_999)), [], "empty restart: no events later")

        // Degenerate durations never stall the clock: they count as instantaneous phases.
        let broken = PomodoroEngine()
        broken.start(phases: [Phase(kind: .focus, duration: .nan, focusNumber: 1)], now: t0)
        checkEqual(broken.phases.first?.duration, 0, "NaN duration stored as 0")
        checkEqual(broken.tick(now: t0), [.phaseCompleted(index: 0, phase: Phase(kind: .focus, duration: 0, focusNumber: 1)), .sessionCompleted],
                   "NaN-duration phase completes on the next tick")
    }

    section("PomodoroEngine tick timing") {
        let engine = startedEngine()
        checkEqual(engine.tick(now: at(1499.9)), [], "tick before end")
        checkEqual(engine.currentIndex, 0)
        checkClose(engine.remaining(now: at(1499.9)), 0.1, tolerance: 1e-6)
        checkClose(engine.progress(now: at(750)), 0.5)

        checkEqual(engine.tick(now: at(1500)), [.phaseCompleted(index: 0, phase: focus1), .phaseStarted(index: 1, phase: short1)],
                   "tick exactly at end")
        checkEqual(engine.remaining(now: at(1500)), 300, "next phase ends at previous end + duration")
        checkEqual(engine.tick(now: at(1500)), [], "second tick at the same time does nothing")

        // Late tick within the 2 s tolerance: the next phase still starts at the scheduled end.
        checkEqual(engine.tick(now: at(1802)), [.phaseCompleted(index: 1, phase: short1), .phaseStarted(index: 2, phase: focus2)],
                   "tick 2 s late")
        checkEqual(engine.remaining(now: at(1802)), 1498, "2 s late: no drift")
        checkEqual(engine.remaining(now: at(3300)), 0, "2 s late: ends at the scheduled time")

        // Just beyond the tolerance, the next phase starts fresh at `now`.
        checkEqual(engine.tick(now: at(3302.5)), [.phaseCompleted(index: 2, phase: focus2), .phaseStarted(index: 3, phase: long2)],
                   "tick 2.5 s late")
        checkEqual(engine.remaining(now: at(3302.5)), 900, "2.5 s late: next phase starts at now")
    }

    section("PomodoroEngine no drift across 10 phases") {
        let phases = (0..<10).map { index in
            index % 2 == 0
                ? Phase(kind: .focus, duration: 60 + TimeInterval(index), focusNumber: index / 2 + 1)
                : Phase(kind: .shortBreak, duration: 30.5, focusNumber: index / 2 + 1)
        }
        for lateness in [0, 1.5, 2] as [TimeInterval] {
            let engine = startedEngine(phases)
            var boundary: TimeInterval = 0
            var ok = true
            for (index, phase) in phases.enumerated() {
                boundary += phase.duration
                if engine.remaining(now: at(boundary - 1)) != 1 { ok = false }
                if engine.tick(now: at(boundary - 0.25)) != [] { ok = false }
                let events = engine.tick(now: at(boundary + lateness))
                let expectedNext: EngineEvent = index + 1 < phases.count
                    ? .phaseStarted(index: index + 1, phase: phases[index + 1])
                    : .sessionCompleted
                checkEqual(events, [.phaseCompleted(index: index, phase: phase), expectedNext],
                           "lateness \(lateness): events at boundary \(index)")
            }
            check(ok, "lateness \(lateness): every phase ended exactly on schedule")
            checkEqual(engine.status, .finished, "lateness \(lateness): finished")
            checkEqual(boundary, phases.reduce(0) { $0 + $1.duration }, "total length")
        }
    }

    section("PomodoroEngine sleep catch-up") {
        let engine = startedEngine()
        let wake = at(1500 + 3600)
        checkEqual(engine.tick(now: wake), [.phaseCompleted(index: 0, phase: focus1), .phaseStarted(index: 1, phase: short1)],
                   "one hour late: exactly one completion")
        checkEqual(engine.remaining(now: wake), 300, "the next phase starts fresh at wake time")
        checkEqual(engine.tick(now: wake), [], "no burning through further phases")
        checkEqual(engine.tick(now: wake.addingTimeInterval(299)), [])
        checkEqual(engine.tick(now: wake.addingTimeInterval(300)).first, .phaseCompleted(index: 1, phase: short1))

        // Sleeping through the final phase finishes the session with a single completion.
        let last = startedEngine([focus3])
        checkEqual(last.tick(now: at(86_400)), [.phaseCompleted(index: 0, phase: focus3), .sessionCompleted], "slept through the end")
        checkEqual(last.status, .finished)
    }

    section("PomodoroEngine pause and resume") {
        let engine = startedEngine()
        engine.pause(now: at(100))
        checkEqual(engine.status, .paused)
        checkEqual(engine.remaining(now: at(100)), 1400)
        checkEqual(engine.remaining(now: at(5000)), 1400, "remaining is frozen while paused")
        checkClose(engine.progress(now: at(5000)), 100.0 / 1500.0, tolerance: 1e-12, "progress frozen while paused")
        checkEqual(engine.sessionRemaining(now: at(5000)), 4700)
        checkEqual(engine.tick(now: at(5000)), [], "no completion while paused")
        checkEqual(engine.currentIndex, 0)

        engine.pause(now: at(600))
        checkEqual(engine.remaining(now: at(600)), 1400, "pausing twice keeps the first remaining")

        engine.resume(now: at(1000))
        checkEqual(engine.status, .running)
        checkEqual(engine.remaining(now: at(1000)), 1400, "resume continues where it paused")
        checkEqual(engine.tick(now: at(2399)), [], "not yet over")
        checkEqual(engine.remaining(now: at(2399)), 1)
        engine.resume(now: at(2000))
        checkEqual(engine.remaining(now: at(2399)), 1, "resume while running is a no-op")
        checkEqual(engine.tick(now: at(2400)), [.phaseCompleted(index: 0, phase: focus1), .phaseStarted(index: 1, phase: short1)],
                   "ends at resume + remaining")
        checkEqual(engine.remaining(now: at(2400)), 300)

        // Pausing an overdue phase keeps 0 remaining; resuming completes it on the next tick.
        let overdue = startedEngine()
        overdue.pause(now: at(1600))
        checkEqual(overdue.remaining(now: at(1600)), 0, "overdue pause")
        overdue.resume(now: at(1700))
        checkEqual(overdue.tick(now: at(1700)), [.phaseCompleted(index: 0, phase: focus1), .phaseStarted(index: 1, phase: short1)])
    }

    section("PomodoroEngine skip") {
        let engine = startedEngine()
        checkEqual(engine.skip(now: at(10)), [.phaseStarted(index: 1, phase: short1)], "skip while running: no phaseCompleted")
        checkEqual(engine.currentIndex, 1)
        checkEqual(engine.status, .running)
        checkEqual(engine.remaining(now: at(10)), 300, "skipped-to phase starts now")
        checkEqual(engine.completedFocusBlocks, 1, "skipped focus counts as completed")

        engine.pause(now: at(20))
        checkEqual(engine.skip(now: at(50)), [.phaseStarted(index: 2, phase: focus2)], "skip while paused")
        checkEqual(engine.status, .running, "skip from pause starts the next phase running")
        checkEqual(engine.remaining(now: at(50)), 1500)
        checkEqual(engine.remaining(now: at(60)), 1490, "and it counts down")

        engine.skip(now: at(60))
        checkEqual(engine.currentIndex, 3)
        checkEqual(engine.completedFocusBlocks, 2)
        engine.skip(now: at(70))
        checkEqual(engine.currentIndex, 4)
        checkEqual(engine.skip(now: at(80)), [.sessionCompleted], "skip the last phase")
        checkEqual(engine.status, .finished)
        checkEqual(engine.currentIndex, nil)
        checkEqual(engine.currentPhase, nil)
        checkEqual(engine.remaining(now: at(80)), 0)
        checkEqual(engine.progress(now: at(80)), 0)
        checkEqual(engine.sessionRemaining(now: at(80)), 0)
        checkEqual(engine.completedFocusBlocks, 3, "all focus blocks done when finished")
        checkEqual(engine.totalFocusBlocks, 3, "plan kept when finished")
        checkEqual(engine.tick(now: at(99_999)), [], "tick after finish")
        checkEqual(engine.skip(now: at(99_999)), [], "skip after finish")
        engine.pause(now: at(99_999))
        checkEqual(engine.status, .finished, "pause after finish is a no-op")
        engine.extendCurrent(by: 300, now: at(99_999))
        checkEqual(engine.phases, plan, "extend after finish is a no-op")

        // Skipping a paused last phase also finishes.
        let single = startedEngine([focus3])
        single.pause(now: at(5))
        checkEqual(single.skip(now: at(6)), [.sessionCompleted], "skip paused last phase")
        checkEqual(single.status, .finished)
    }

    section("PomodoroEngine extendCurrent") {
        let running = startedEngine()
        running.extendCurrent(by: 300, now: at(1000))
        checkEqual(running.remaining(now: at(1000)), 800, "running extend adds to the end")
        checkEqual(running.phases[0].duration, 1800, "running extend grows the phase")
        checkClose(running.progress(now: at(1000)), 1000.0 / 1800.0, tolerance: 1e-12, "progress uses the new duration")
        checkEqual(running.sessionRemaining(now: at(1000)), 4100)
        checkEqual(running.tick(now: at(1500)), [], "old end passes without completing")
        let extended = Phase(kind: .focus, duration: 1800, focusNumber: 1)
        checkEqual(running.tick(now: at(1800)), [.phaseCompleted(index: 0, phase: extended), .phaseStarted(index: 1, phase: short1)],
                   "completes at the new end")

        let paused = startedEngine()
        paused.pause(now: at(1000))
        paused.extendCurrent(by: 60, now: at(1100))
        checkEqual(paused.status, .paused, "extend keeps it paused")
        checkEqual(paused.remaining(now: at(1100)), 560, "paused extend adds to the remaining")
        checkEqual(paused.phases[0].duration, 1560)
        checkClose(paused.progress(now: at(1100)), 1000.0 / 1560.0, tolerance: 1e-12)
        paused.resume(now: at(2000))
        checkEqual(paused.tick(now: at(2559)), [])
        checkEqual(paused.tick(now: at(2560)).count, 2, "completes at resume + extended remaining")

        let ignored = startedEngine()
        for amount in [0, -60, .nan, .infinity] as [TimeInterval] {
            ignored.extendCurrent(by: amount, now: at(100))
        }
        checkEqual(ignored.phases, plan, "non-positive or non-finite extensions are ignored")
        checkEqual(ignored.remaining(now: at(100)), 1400)
    }

    section("PomodoroEngine progress bookkeeping") {
        let engine = startedEngine()
        checkEqual(engine.sessionRemaining(now: t0), 4800)
        checkEqual(engine.remaining(now: at(750)), 750)
        checkClose(engine.progress(now: at(750)), 0.5)
        checkEqual(engine.sessionRemaining(now: at(750)), 4050)
        checkEqual(engine.remaining(now: at(10_000)), 0, "remaining never negative")
        checkEqual(engine.progress(now: at(10_000)), 1, "progress clamps at 1")
        checkEqual(engine.progress(now: at(-100)), 0, "progress clamps at 0")

        let steps: [(time: TimeInterval, index: Int?, completed: Int, remaining: TimeInterval, session: TimeInterval)] = [
            (1500, 1, 1, 300, 3300),
            (1800, 2, 1, 1500, 3000),
            (3300, 3, 2, 900, 1500),
            (4200, 4, 2, 600, 600),
            (4800, nil, 3, 0, 0),
        ]
        for step in steps {
            engine.tick(now: at(step.time))
            checkEqual(engine.currentIndex, step.index, "index at \(step.time)")
            checkEqual(engine.completedFocusBlocks, step.completed, "completed focus blocks at \(step.time)")
            checkEqual(engine.remaining(now: at(step.time)), step.remaining, "remaining at \(step.time)")
            checkEqual(engine.sessionRemaining(now: at(step.time)), step.session, "session remaining at \(step.time)")
            checkEqual(engine.totalFocusBlocks, 3, "total focus blocks at \(step.time)")
        }
        checkEqual(engine.status, .finished)
    }

    section("PomodoroEngine stop") {
        let engine = startedEngine()
        engine.tick(now: at(1500))
        engine.stop()
        checkEqual(engine.status, .idle)
        checkEqual(engine.phases, [])
        checkEqual(engine.currentIndex, nil)
        checkEqual(engine.remaining(now: at(1600)), 0)
        checkEqual(engine.sessionRemaining(now: at(1600)), 0)
        checkEqual(engine.completedFocusBlocks, 0)
        checkEqual(engine.totalFocusBlocks, 0)
        checkEqual(engine.tick(now: at(99_999)), [], "no events after stop")

        let paused = startedEngine()
        paused.pause(now: at(10))
        paused.stop()
        checkEqual(paused.status, .idle, "stop while paused")
        paused.resume(now: at(20))
        checkEqual(paused.status, .idle, "resume after stop is a no-op")
    }
}
