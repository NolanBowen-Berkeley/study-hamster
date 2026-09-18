import Foundation
import HamsterCore

func runSettingsChecks() {
    section("PomodoroSettings.sanitized") {
        typealias S = PomodoroSettings
        checkEqual(S.standard, S(focusMinutes: 25, shortBreakMinutes: 5, longBreakMinutes: 15, focusBlocksBeforeLongBreak: 4))
        checkEqual(S.standard.sanitized(), S.standard, "standard settings are already sane")
        checkEqual(S(focusMinutes: 50, shortBreakMinutes: 10, longBreakMinutes: 30, focusBlocksBeforeLongBreak: 2).sanitized(),
                   S(focusMinutes: 50, shortBreakMinutes: 10, longBreakMinutes: 30, focusBlocksBeforeLongBreak: 2), "in-range values kept")
        checkEqual(S(focusMinutes: 25.5, shortBreakMinutes: 4.5, longBreakMinutes: 12.5, focusBlocksBeforeLongBreak: 3).sanitized(),
                   S(focusMinutes: 25.5, shortBreakMinutes: 4.5, longBreakMinutes: 12.5, focusBlocksBeforeLongBreak: 3), "fractions kept")
        checkEqual(S(focusMinutes: 0, shortBreakMinutes: 0, longBreakMinutes: 0, focusBlocksBeforeLongBreak: 0).sanitized(),
                   S(focusMinutes: 1, shortBreakMinutes: 1, longBreakMinutes: 1, focusBlocksBeforeLongBreak: 1), "zeros clamp up")
        checkEqual(S(focusMinutes: -5, shortBreakMinutes: -5, longBreakMinutes: -5, focusBlocksBeforeLongBreak: -5).sanitized(),
                   S(focusMinutes: 1, shortBreakMinutes: 1, longBreakMinutes: 1, focusBlocksBeforeLongBreak: 1), "negatives clamp up")
        checkEqual(S(focusMinutes: 500, shortBreakMinutes: 500, longBreakMinutes: 500, focusBlocksBeforeLongBreak: 500).sanitized(),
                   S(focusMinutes: 180, shortBreakMinutes: 60, longBreakMinutes: 120, focusBlocksBeforeLongBreak: 12), "large values clamp down")
        checkEqual(S(focusMinutes: 180, shortBreakMinutes: 60, longBreakMinutes: 120, focusBlocksBeforeLongBreak: 12).sanitized(),
                   S(focusMinutes: 180, shortBreakMinutes: 60, longBreakMinutes: 120, focusBlocksBeforeLongBreak: 12), "upper bounds inclusive")
        checkEqual(S(focusMinutes: 1, shortBreakMinutes: 1, longBreakMinutes: 1, focusBlocksBeforeLongBreak: 1).sanitized(),
                   S(focusMinutes: 1, shortBreakMinutes: 1, longBreakMinutes: 1, focusBlocksBeforeLongBreak: 1), "lower bounds inclusive")
        checkEqual(S(focusMinutes: .nan, shortBreakMinutes: .nan, longBreakMinutes: .nan, focusBlocksBeforeLongBreak: 4).sanitized(),
                   S.standard, "NaN falls back to the defaults")
        checkEqual(S(focusMinutes: .nan, shortBreakMinutes: 7, longBreakMinutes: .nan, focusBlocksBeforeLongBreak: 2).sanitized(),
                   S(focusMinutes: 25, shortBreakMinutes: 7, longBreakMinutes: 15, focusBlocksBeforeLongBreak: 2), "NaN per field")
        checkEqual(S(focusMinutes: .infinity, shortBreakMinutes: .infinity, longBreakMinutes: .infinity, focusBlocksBeforeLongBreak: .max).sanitized(),
                   S(focusMinutes: 180, shortBreakMinutes: 60, longBreakMinutes: 120, focusBlocksBeforeLongBreak: 12), "+infinity clamps down")
        checkEqual(S(focusMinutes: -.infinity, shortBreakMinutes: -.infinity, longBreakMinutes: -.infinity, focusBlocksBeforeLongBreak: .min).sanitized(),
                   S(focusMinutes: 1, shortBreakMinutes: 1, longBreakMinutes: 1, focusBlocksBeforeLongBreak: 1), "-infinity clamps up")
        let odd = S(focusMinutes: 999, shortBreakMinutes: .nan, longBreakMinutes: -3, focusBlocksBeforeLongBreak: 40)
        checkEqual(odd.sanitized().sanitized(), odd.sanitized(), "sanitized is idempotent")

        // Settings are persisted as JSON by the app.
        let settings = S(focusMinutes: 50, shortBreakMinutes: 10, longBreakMinutes: 30, focusBlocksBeforeLongBreak: 2)
        let decoded = (try? JSONEncoder().encode(settings)).flatMap { try? JSONDecoder().decode(S.self, from: $0) }
        checkEqual(decoded, settings, "Codable round trip")
    }
}

/// Compact plan notation for readable failure output: "F25 S5 L15" in minutes (seconds shown when not whole).
private func describe(_ phases: [Phase]) -> String {
    phases.map { phase in
        let letter = phase.kind == .focus ? "F" : phase.kind == .shortBreak ? "S" : "L"
        let minutes = phase.duration / 60
        return minutes == minutes.rounded() ? "\(letter)\(Int(minutes))" : "\(letter)\(Int(phase.duration))s"
    }.joined(separator: " ")
}

func runPlannerChecks() {
    let standard = PomodoroSettings.standard

    section("SessionPlanner spec examples") {
        let examples: [(minutes: Double, expected: String)] = [
            (10, "F10"),
            (25, "F25"),
            (30, "F30"),
            (60, "F25 S5 F30"),
            (120, "F25 S5 F25 S5 F25 S5 F30"),
            (180, "F25 S5 F25 S5 F25 S5 F25 L15 F25 S5 F20"),
        ]
        for (minutes, expected) in examples {
            checkEqual(describe(SessionPlanner.plan(totalDuration: minutes * 60, settings: standard)), expected, "plan(\(minutes) min)")
        }

        // Exact phases (kinds, durations, focus numbers) for 180 minutes.
        let expected180: [Phase] = [
            Phase(kind: .focus, duration: 1500, focusNumber: 1), Phase(kind: .shortBreak, duration: 300, focusNumber: 1),
            Phase(kind: .focus, duration: 1500, focusNumber: 2), Phase(kind: .shortBreak, duration: 300, focusNumber: 2),
            Phase(kind: .focus, duration: 1500, focusNumber: 3), Phase(kind: .shortBreak, duration: 300, focusNumber: 3),
            Phase(kind: .focus, duration: 1500, focusNumber: 4), Phase(kind: .longBreak, duration: 900, focusNumber: 4),
            Phase(kind: .focus, duration: 1500, focusNumber: 5), Phase(kind: .shortBreak, duration: 300, focusNumber: 5),
            Phase(kind: .focus, duration: 1200, focusNumber: 6),
        ]
        checkEqual(SessionPlanner.plan(totalDuration: 180 * 60, settings: standard), expected180, "plan(180 min) phases")
        checkEqual(SessionPlanner.minimumFocusBlock, 300, "minimum focus block")
    }

    section("SessionPlanner edge totals") {
        for total in [0, -60, -0.1, 0.4, .nan, .infinity, -.infinity] as [TimeInterval] {
            checkEqual(SessionPlanner.plan(totalDuration: total, settings: standard), [], "plan(\(total)) is empty")
        }
        checkEqual(SessionPlanner.plan(totalDuration: 0.6, settings: standard),
                   [Phase(kind: .focus, duration: 1, focusNumber: 1)], "0.6 s rounds up to 1 s")
        checkEqual(SessionPlanner.plan(totalDuration: 600.4, settings: standard),
                   [Phase(kind: .focus, duration: 600, focusNumber: 1)], "total rounded to whole seconds")
        checkEqual(SessionPlanner.plan(totalDuration: 1500.6, settings: standard),
                   [Phase(kind: .focus, duration: 1501, focusNumber: 1)], "total rounded to whole seconds")
        checkEqual(describe(SessionPlanner.plan(totalDuration: 35 * 60, settings: standard)), "F35",
                   "35 min: 10 min left is exactly break + minimum, so it merges")
        checkEqual(describe(SessionPlanner.plan(totalDuration: 35 * 60 + 1, settings: standard)), "F25 S5 F301s",
                   "35 min 1 s: just enough room for a break and a last focus")

        // Settings are sanitized first: zeros behave like the 1-minute minimums.
        let zeros = PomodoroSettings(focusMinutes: 0, shortBreakMinutes: 0, longBreakMinutes: 0, focusBlocksBeforeLongBreak: 0)
        let ones = PomodoroSettings(focusMinutes: 1, shortBreakMinutes: 1, longBreakMinutes: 1, focusBlocksBeforeLongBreak: 1)
        checkEqual(SessionPlanner.plan(totalDuration: 1800, settings: zeros), SessionPlanner.plan(totalDuration: 1800, settings: ones),
                   "planner sanitizes settings")
        let nanSettings = PomodoroSettings(focusMinutes: .nan, shortBreakMinutes: .nan, longBreakMinutes: .nan, focusBlocksBeforeLongBreak: 4)
        checkEqual(SessionPlanner.plan(totalDuration: 7200, settings: nanSettings), SessionPlanner.plan(totalDuration: 7200, settings: standard),
                   "NaN settings plan like the defaults")

        // Fractional minute settings still give whole-second phases that add up exactly.
        let fractional = PomodoroSettings(focusMinutes: 25.51, shortBreakMinutes: 4.99, longBreakMinutes: 14.3, focusBlocksBeforeLongBreak: 3)
        let plan = SessionPlanner.plan(totalDuration: 4 * 3600, settings: fractional)
        check(plan.allSatisfy { $0.duration == $0.duration.rounded() }, "fractional settings give whole-second phases: \(describe(plan))")
        checkEqual(plan.reduce(0) { $0 + $1.duration }, 4 * 3600, "fractional settings: sum == total")
    }

    section("SessionPlanner property sweep") {
        let settingsList = [
            PomodoroSettings(focusMinutes: 25, shortBreakMinutes: 5, longBreakMinutes: 15, focusBlocksBeforeLongBreak: 4),
            PomodoroSettings(focusMinutes: 50, shortBreakMinutes: 10, longBreakMinutes: 30, focusBlocksBeforeLongBreak: 2),
            PomodoroSettings(focusMinutes: 1, shortBreakMinutes: 1, longBreakMinutes: 1, focusBlocksBeforeLongBreak: 1),
            PomodoroSettings(focusMinutes: 180, shortBreakMinutes: 60, longBreakMinutes: 120, focusBlocksBeforeLongBreak: 12),
        ]
        for settings in settingsList {
            let focus = settings.focusMinutes * 60
            let short = settings.shortBreakMinutes * 60
            let long = settings.longBreakMinutes * 60
            let every = settings.focusBlocksBeforeLongBreak
            for minutes in 1...720 {
                let total = TimeInterval(minutes * 60)
                let plan = SessionPlanner.plan(totalDuration: total, settings: settings)
                let label = "\(settings.focusMinutes)/\(settings.shortBreakMinutes)/\(settings.longBreakMinutes)/\(every) @ \(minutes) min: \(describe(plan))"
                guard let first = plan.first, let last = plan.last else {
                    check(false, "\(label): plan is empty")
                    continue
                }
                checkEqual(plan.reduce(0) { $0 + $1.duration }, total, "\(label): sum == total")
                check(first.kind == .focus && last.kind == .focus, "\(label): starts and ends with focus")
                check(plan.allSatisfy { $0.duration > 0 }, "\(label): every duration > 0")

                var alternates = true
                var numbering = true
                var breakKinds = true
                var breakLengths = true
                for (index, phase) in plan.enumerated() {
                    let blockNumber = index / 2 + 1
                    if phase.kind.isBreak != (index % 2 == 1) { alternates = false }
                    if phase.focusNumber != blockNumber { numbering = false }
                    if phase.kind.isBreak {
                        let shouldBeLong = blockNumber % every == 0
                        if (phase.kind == .longBreak) != shouldBeLong { breakKinds = false }
                        if phase.duration != (shouldBeLong ? long : short) { breakLengths = false }
                    }
                }
                check(alternates, "\(label): focus and breaks alternate (never two in a row)")
                check(numbering, "\(label): focus numbers are 1, 1, 2, 2, 3, ...")
                check(breakKinds, "\(label): the break after focus #n is long iff n % \(every) == 0")
                check(breakLengths, "\(label): breaks have the configured lengths")

                let focusBlocks = plan.filter { $0.kind == .focus }
                check(focusBlocks.dropLast().allSatisfy { $0.duration == focus }, "\(label): all but the last focus are full length")
                if plan.count > 1 {
                    check(last.duration > min(focus, SessionPlanner.minimumFocusBlock), "\(label): last focus is not a tiny stub")
                } else {
                    checkEqual(last.duration, total, "\(label): single block covers everything")
                }
            }
        }
    }

    section("SessionPlanner.summary") {
        checkEqual(SessionPlanner.summary(of: []), PlanSummary(focusBlocks: 0, totalFocus: 0, totalBreak: 0, total: 0), "empty plan")
        checkEqual(SessionPlanner.summary(of: SessionPlanner.plan(totalDuration: 7200, settings: standard)),
                   PlanSummary(focusBlocks: 4, totalFocus: 105 * 60, totalBreak: 15 * 60, total: 7200), "120 min")
        checkEqual(SessionPlanner.summary(of: SessionPlanner.plan(totalDuration: 180 * 60, settings: standard)),
                   PlanSummary(focusBlocks: 6, totalFocus: 145 * 60, totalBreak: 35 * 60, total: 180 * 60), "180 min")
        checkEqual(SessionPlanner.summary(of: SessionPlanner.plan(totalDuration: 600, settings: standard)),
                   PlanSummary(focusBlocks: 1, totalFocus: 600, totalBreak: 0, total: 600), "10 min")
        let handMade = [
            Phase(kind: .shortBreak, duration: 10, focusNumber: 1),
            Phase(kind: .longBreak, duration: 20, focusNumber: 1),
            Phase(kind: .focus, duration: 30, focusNumber: 1),
        ]
        checkEqual(SessionPlanner.summary(of: handMade), PlanSummary(focusBlocks: 1, totalFocus: 30, totalBreak: 30, total: 60),
                   "counts both break kinds")
    }
}
