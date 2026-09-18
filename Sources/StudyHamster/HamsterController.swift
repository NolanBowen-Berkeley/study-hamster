import AppKit
import HamsterCore
import HamsterUI

/// Runs the whole show: follows your front window, drives the pomodoro engine, and tells the stage what
/// the hamster should do and say.
@MainActor
final class HamsterController {
    /// What the bubble on screen is announcing. Alarms keep the hamster bouncing until acknowledged.
    private enum Alert {
        case none, breakStarted, backToWork, celebration

        var isAlarm: Bool { self == .backToWork || self == .celebration }
    }

    private enum Timing {
        static let engineTick: TimeInterval = 0.25
        static let mousePoll: TimeInterval = 1.0 / 30
        /// Duck before jumping to another window / before ordering the panel out.
        static let duck: TimeInterval = 0.2
        static let welcomeMessage: TimeInterval = 6
        static let shortMessage: TimeInterval = 4
        static let breakMessage: TimeInterval = 20
        static let backToWorkAlarm: TimeInterval = 8
        static let celebrationAlarm: TimeInterval = 10
        static var jumpBack: TimeInterval { HamsterAnimator.transitionDuration(of: .jumpingBack) ?? 0.7 }
    }

    /// Distance (points) at which the pupils reach the edge of the eye.
    private static let lookRange: CGFloat = 250

    private let settings: SettingsStore
    private let model: StageModel
    private let engine: PomodoroEngine
    private let sounds: SoundPlayer
    private let tracker: WindowTracker
    private let panel: HamsterPanel
    private let settingsWindow: SettingsWindowController
    private var statusItem: StatusItemController?
    private let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private var target: PerchTarget?
    /// Room above the ledge the panel is laid out for: `StageMetrics.peekHeadroom`, or `outHeadroom` while
    /// the hamster is out on the ledge. Only changes while he is ducked or off screen (see `present`).
    private var layoutHeadroom = StageMetrics.peekHeadroom
    private var alert: Alert = .none
    /// True between ducking at the old window (or height) and popping up at the new one.
    private var isRelocating = false
    /// SwiftUI's tap fires for every click of a double-click; clicks closer together than the system
    /// double-click interval count as one.
    private var lastTapUptime: TimeInterval = -.infinity
    /// The single pending "later" step: a bubble's auto-dismiss, or the second half of hiding. Every new
    /// bubble or explicit mode change replaces it, so stale steps can never strand the hamster.
    private var pendingWork: DispatchWorkItem?
    private var timers: [Timer] = []
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    init(settings: SettingsStore) {
        self.settings = settings
        model = StageModel()
        engine = PomodoroEngine()
        sounds = SoundPlayer()
        tracker = WindowTracker()
        panel = HamsterPanel()
        settingsWindow = SettingsWindowController(settings: settings, sounds: sounds)

        panel.host(HamsterStageView(
            model: model,
            onHamsterTap: { [weak self] in self?.hamsterTapped() },
            onAction: { [weak self] action in self?.perform(action) }
        ))
    }

    // MARK: - Lifecycle

    func start() {
        statusItem = StatusItemController(actions: menuActions(), state: { [weak self] in
            self?.menuState ?? StatusMenuState(isSessionActive: false, isPaused: false, isHamsterHidden: false)
        })
        installTimers()
        installObservers()

        tracker.onChange = { [weak self] target in self?.targetChanged(target) }
        tracker.start()  // publishes the first target synchronously, placing the (still hidden) panel

        if !settings.hamsterHidden {
            revealPanel()
        }
        if !settings.hasLaunchedBefore {
            settings.hasLaunchedBefore = true
            revealPanel()
            showBubble(
                .message(MessageInfo(title: "Hi! I'm your study hamster.", detail: "Click me when you're ready to study.")),
                autoDismissAfter: Timing.welcomeMessage
            )
        }
        if !panel.isVisible {
            tracker.stop()  // hidden by the user: nothing to follow until he comes back (revealPanel restarts it)
        }
        refreshDisplays()
    }

    /// The app was opened again while running (Finder, Spotlight, Launchpad): bring a hidden hamster back,
    /// since the menu-bar item may be out of sight behind the notch.
    func handleReopen() {
        if settings.hamsterHidden {
            setHamsterHidden(false)
        } else {
            revealPanel()
        }
    }

    func shutdown() {
        timers.forEach { $0.invalidate() }
        timers.removeAll()
        for observer in observers {
            observer.center.removeObserver(observer.token)
        }
        observers.removeAll()
        tracker.stop()
        sounds.stop()
        statusItem?.remove()
    }

    private func installTimers() {
        addTimer(interval: Timing.engineTick, tolerance: 0.05) { $0.tick() }
        addTimer(interval: Timing.mousePoll, tolerance: 0.005) { $0.pollMouse() }
    }

    private func addTimer(interval: TimeInterval, tolerance: TimeInterval, _ body: @escaping (HamsterController) -> Void) {
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                if let self { body(self) }
            }
        }
        timer.tolerance = tolerance
        RunLoop.main.add(timer, forMode: .common)
        timers.append(timer)
    }

    private func installObservers() {
        // The Mac slept: settle overdue phases right away instead of on the next tick.
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification) { $0.tick() }
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { $0.tracker.rescan() }
        // Clicking anywhere else while the ask bubble is up dismisses it.
        observe(NotificationCenter.default, NSWindow.didResignKeyNotification, object: panel) { controller in
            if case .askDuration = controller.model.bubble {
                controller.closeBubble()
            }
        }
    }

    private func observe(
        _ center: NotificationCenter, _ name: Notification.Name, object: AnyObject? = nil,
        _ body: @escaping (HamsterController) -> Void
    ) {
        let token = center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if let self { body(self) }
            }
        }
        observers.append((center, token))
    }

    // MARK: - Following windows

    private func targetChanged(_ newTarget: PerchTarget) {
        let previous = target
        target = newTarget
        // Mid-duck: the pending pop-up reads `target` when it fires, so it simply lands on the newest one.
        guard !isRelocating else { return }
        guard panel.isVisible, let previous, !previous.isSamePlace(as: newTarget) else {
            moveToTarget()  // same window moved/resized (or panel not showing): follow instantly
            return
        }
        // A different window: duck behind the old one, jump over, pop up behind the new one.
        relocate()
    }

    /// Ducks, then (once out of sight) moves the panel to the target laid out for the resting mode and pops
    /// up into that mode. Popping up into sitting out or the alarm jumps out.
    private func relocate() {
        isRelocating = true
        model.setMode(.hidden)
        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.duck) { [weak self] in
            MainActor.assumeIsolated { self?.finishRelocation() }
        }
    }

    private func finishRelocation() {
        isRelocating = false
        layoutHeadroom = headroom(for: settledMode)
        moveToTarget()
        if panel.isVisible {
            model.setMode(settledMode)
        }
    }

    private func moveToTarget() {
        guard let layout = layout(headroom: layoutHeadroom) else { return }
        if panel.frame != layout.panelFrame {
            panel.setFrame(layout.panelFrame, display: false)
        }
        if model.topInset != layout.topOverhang {
            model.topInset = layout.topOverhang
        }
    }

    /// Where the panel goes for the current target when the hamster needs `headroom` above the ledge.
    private func layout(headroom: CGFloat) -> PerchLayout? {
        guard let target else { return nil }
        let metrics = PerchMetrics(
            panelSize: StageMetrics.panelSize,
            ledgeFromTop: StageMetrics.ledgeFromTop,
            hamsterCenterX: StageMetrics.hamsterCenterX,
            hamsterInsetFromWindowRight: StageMetrics.hamsterInsetFromWindowRight,
            headroom: headroom
        )
        if let windowFrame = target.windowFrame {
            return PerchCalculator.layout(windowFrame: windowFrame, visibleFrame: target.visibleFrame, metrics: metrics)
        }
        return PerchCalculator.fallbackLayout(visibleFrame: target.visibleFrame, metrics: metrics)
    }

    /// Room above the ledge `mode` needs: more while out on the ledge than while peeking.
    private func headroom(for mode: HamsterMode) -> CGFloat {
        switch mode {
        case .jumpingOut, .sittingOut, .alarm: return StageMetrics.outHeadroom
        case .hidden, .peeking, .jumpingBack: return StageMetrics.peekHeadroom
        }
    }

    // MARK: - Showing and hiding

    /// The mode the hamster rests in when nothing one-shot is playing.
    private var settledMode: HamsterMode {
        if alert.isAlarm { return .alarm }
        if settings.hamsterHidden && model.bubble == nil { return .hidden }
        return isOnBreak ? .sittingOut : .peeking
    }

    /// Requests a mode unless the hamster is mid-relocation (the pop-up then applies `settledMode`).
    private func show(mode: HamsterMode) {
        guard !isRelocating else { return }
        model.setMode(mode)
    }

    /// Like `show(mode:)`, for modes that go out onto the ledge or back in. On a window near the top of the
    /// screen those need the panel at a different height (see `StageMetrics.outHeadroom`): then the hamster
    /// ducks, the panel moves, and he pops up into his resting mode there (jumping out for a break or alarm).
    private func present(_ mode: HamsterMode) {
        guard !isRelocating else { return }
        let headroom = headroom(for: mode)
        if headroom != layoutHeadroom {
            let moves = layout(headroom: headroom).map { $0.panelFrame != panel.frame } ?? false
            // Not when he is about to hide anyway: the next reveal lays the panel out afresh.
            if panel.isVisible && moves && settledMode != .hidden {
                relocate()
                return
            }
            if !panel.isVisible || !moves {
                layoutHeadroom = headroom
                moveToTarget()
            }
        }
        model.setMode(mode)
    }

    /// Orders the panel in at the current target with the hamster ducked out of sight, laid out for the mode
    /// about to be shown (`entering`, by default the resting mode). `settle` pops it straight up into its
    /// resting pose; announcements pass false and choose their own entrance.
    private func revealPanel(settle: Bool = true, entering: HamsterMode? = nil) {
        guard !panel.isVisible else { return }
        tracker.start()  // publishes a fresh target first (it is stopped while the panel is off screen)
        let resting = settledMode == .hidden ? .peeking : settledMode
        layoutHeadroom = headroom(for: entering ?? resting)
        moveToTarget()
        model.setMode(.hidden)
        panel.orderFrontRegardless()
        if settle {
            show(mode: resting)
        }
    }

    private var isHamsterOut: Bool {
        switch model.animator.effectiveMode(at: StageModel.now()) {
        case .jumpingOut, .sittingOut, .alarm: return true
        case .hidden, .peeking, .jumpingBack: return false
        }
    }

    /// Hidden by the user and nothing to say: duck, then take the panel off screen.
    private func scheduleHideIfNeeded(after delay: TimeInterval) {
        guard settings.hamsterHidden else { return }
        schedule(after: delay) { controller in
            guard controller.settings.hamsterHidden, controller.model.bubble == nil else { return }
            controller.show(mode: .hidden)
            controller.schedule(after: Timing.duck) { controller in
                guard controller.settings.hamsterHidden, controller.model.bubble == nil else { return }
                controller.panel.orderOut(nil)
                controller.tracker.stop()
            }
        }
    }

    private func setHamsterHidden(_ hidden: Bool) {
        settings.hamsterHidden = hidden
        if hidden {
            if model.bubble != nil {
                closeBubble()  // also schedules the hide
            } else {
                scheduleHideIfNeeded(after: 0)
            }
        } else if model.bubble == nil {
            cancelPendingWork()  // a hide may be mid-duck
            if panel.isVisible {
                present(settledMode)
            } else {
                revealPanel()
            }
        } else if panel.isVisible && model.mode == .hidden {
            present(settledMode)  // a bubble is up but he had already ducked away: bring him back to it
        }
        refreshDisplays()
    }

    // MARK: - Bubbles

    private func showBubble(_ content: BubbleContent, alert newAlert: Alert = .none, autoDismissAfter delay: TimeInterval? = nil) {
        cancelPendingWork()
        let endsAlarm = alert.isAlarm && !newAlert.isAlarm
        alert = newAlert
        model.bubble = content
        if case .askDuration = content {} else {
            returnKeyFocus()
        }
        if endsAlarm {
            // Replaced before it was acknowledged: stop bouncing (callers may pick another entrance after).
            present(settledMode == .sittingOut ? .sittingOut : .jumpingBack)
        }
        if let delay {
            schedule(after: delay) { $0.closeBubble() }
        }
    }

    /// Closes whatever bubble is up and finishes the alert it announced.
    private func closeBubble() {
        cancelPendingWork()
        let finished = alert
        alert = .none
        if model.bubble != nil {
            model.bubble = nil
        }
        returnKeyFocus()
        if finished.isAlarm {
            present(.jumpingBack)  // settles into peeking
        }
        scheduleHideIfNeeded(after: finished.isAlarm ? Timing.jumpBack : 0)
    }

    /// Hands keyboard focus back to the app you're studying in. The panel never activates this app, so
    /// ordering it out and straight back in is enough to give up key status without any visible flicker.
    private func returnKeyFocus() {
        guard panel.isKeyWindow else { return }
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }

    private func showAsk(error: String? = nil, text: String? = nil) {
        let pomodoro = settings.pomodoro.sanitized()
        let hint = "\(TimeFormat.humanDuration(pomodoro.focusMinutes * 60)) focus · "
            + "\(TimeFormat.humanDuration(pomodoro.shortBreakMinutes * 60)) breaks"
        let info = AskDurationInfo(
            prompt: "How long do you want to study?",
            text: text ?? settings.lastDurationText,
            placeholder: "e.g. 1h 30m",
            error: error,
            hint: hint,
            quickPicks: [
                QuickPick(label: "25 min", seconds: 25 * 60),
                QuickPick(label: "50 min", seconds: 50 * 60),
                QuickPick(label: "1 h", seconds: 60 * 60),
                QuickPick(label: "2 h", seconds: 2 * 60 * 60),
            ]
        )
        // Key first, so the text field can take focus as soon as it appears.
        panel.makeKey()
        showBubble(.askDuration(info))
    }

    private func showStatus() {
        guard let info = statusInfo(now: Date()) else { return }
        showBubble(.status(info))
    }

    // MARK: - User input

    private func hamsterTapped() {
        let now = ProcessInfo.processInfo.systemUptime
        let isRepeatClick = now - lastTapUptime < NSEvent.doubleClickInterval
        lastTapUptime = now
        // Also ignore taps on a hamster that is already ducking away (the tail end of the hide duck).
        guard !isRepeatClick, !isRelocating, model.mode != .hidden else { return }
        if alert.isAlarm {
            closeBubble()
            return
        }
        switch model.bubble {
        case .askDuration?, .status?:
            closeBubble()
        case .message?, nil:
            if isSessionActive {
                showStatus()
            } else {
                showAsk()
            }
        }
    }

    private func perform(_ action: BubbleAction) {
        switch action {
        case .submitDuration(let text): submitDuration(text)
        case .start(let seconds): startSession(seconds: seconds)
        case .pause: pause()
        case .resume: resume()
        case .skip: skip()
        case .stop: stopSession()
        case .extend(let minutes): extend(minutes: minutes)
        case .dismiss, .acknowledge: closeBubble()
        case .openSettings:
            closeBubble()
            settingsWindow.show()
        }
    }

    private func menuActions() -> StatusItemController.Actions {
        StatusItemController.Actions(
            startStudying: { [weak self] in
                // Let the menu finish closing before the panel takes keyboard focus.
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.startStudyingFromMenu() }
                }
            },
            pause: { [weak self] in self?.pause() },
            resume: { [weak self] in self?.resume() },
            skip: { [weak self] in self?.skip() },
            stop: { [weak self] in self?.stopSession() },
            toggleHamsterHidden: { [weak self] in
                guard let self else { return }
                setHamsterHidden(!settings.hamsterHidden)
            },
            openSettings: { [weak self] in self?.settingsWindow.show() }
        )
    }

    private func startStudyingFromMenu() {
        if settings.hamsterHidden {
            setHamsterHidden(false)
        }
        revealPanel()
        showAsk()
    }

    private func submitDuration(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let seconds = DurationParser.parse(trimmed) else {
            showAsk(error: "Try something like 45m or 1h 30m", text: text)
            return
        }
        settings.lastDurationText = trimmed
        startSession(seconds: seconds)
    }

    // MARK: - Session control

    private var isSessionActive: Bool { engine.status == .running || engine.status == .paused }
    private var isOnBreak: Bool { isSessionActive && (engine.currentPhase?.kind.isBreak ?? false) }

    private func startSession(seconds: TimeInterval) {
        let now = Date()
        let phases = SessionPlanner.plan(totalDuration: seconds, settings: settings.pomodoro)
        guard !engine.start(phases: phases, now: now).isEmpty else {
            showAsk(error: "Hmm, I couldn't plan that. Try 25m or 1h.")
            return
        }
        let doneAt = clockFormatter.string(from: now.addingTimeInterval(engine.sessionRemaining(now: now)))
        showBubble(
            .message(MessageInfo(title: "Let's go!", detail: "\(pomodoroCount(engine.totalFocusBlocks)) · done at \(doneAt)")),
            autoDismissAfter: Timing.shortMessage
        )
        present(.jumpingBack)  // from a peek: a happy little cheer before settling in to watch
        refreshDisplays(now: now)
    }

    private func pause() {
        engine.pause(now: Date())
        refreshDisplays()
    }

    private func resume() {
        engine.resume(now: Date())
        refreshDisplays()
    }

    private func extend(minutes: Int) {
        engine.extendCurrent(by: TimeInterval(minutes) * 60, now: Date())
        refreshDisplays()
    }

    private func skip() {
        let now = Date()
        handle(engine.skip(now: now), natural: false)
        refreshDisplays(now: now)
    }

    private func stopSession() {
        guard isSessionActive else { return }
        let wasOut = isHamsterOut
        engine.stop()
        if panel.isVisible && !settings.hamsterHidden {
            showBubble(
                .message(MessageInfo(title: "Session stopped.", detail: "Click me whenever you want to study again.")),
                autoDismissAfter: Timing.shortMessage
            )
            if wasOut && model.mode != .jumpingBack {
                present(.jumpingBack)
            }
        } else {
            closeBubble()  // hidden by the user: just tidy up and stay hidden
        }
        refreshDisplays()
    }

    private func tick() {
        let now = Date()
        let events = engine.tick(now: now)
        if !events.isEmpty {
            handle(events, natural: true)
        }
        refreshDisplays(now: now)
    }

    /// Reacts to engine events. `natural` = time ran out (alarms + sounds); otherwise the user skipped.
    private func handle(_ events: [EngineEvent], natural: Bool) {
        for event in events {
            switch event {
            case .phaseCompleted:
                break  // the phaseStarted / sessionCompleted that follows carries the announcement
            case .phaseStarted(let index, let phase):
                if phase.kind.isBreak {
                    announceBreak(phase, natural: natural)
                } else if index > 0 {
                    announceBackToWork(phase, natural: natural)
                }
            case .sessionCompleted:
                announceCelebration(natural: natural)
            }
        }
    }

    /// Skipped phases stay quiet while the user has hidden the hamster; natural ones always come out.
    private func shouldAnnounce(natural: Bool) -> Bool {
        natural || panel.isVisible
    }

    private func announceBreak(_ phase: Phase, natural: Bool) {
        guard shouldAnnounce(natural: natural) else { return }
        revealPanel(settle: false, entering: .sittingOut)
        if natural {
            playAlertSound(times: 1)
        }
        let length = TimeFormat.humanDuration(phase.duration)
        let isLong = phase.kind == .longBreak
        let message = MessageInfo(
            title: isLong ? "Long break!" : "Break time!",
            detail: isLong ? "\(length). You earned it." : "\(length) — stretch, sip some water",
            style: .breakTime,
            buttons: [
                MessageButton(title: "Skip break", action: .skip),
                MessageButton(title: "OK", action: .acknowledge, isPrimary: true),
            ]
        )
        showBubble(.message(message), alert: .breakStarted, autoDismissAfter: Timing.breakMessage)
        if !isHamsterOut {
            present(.jumpingOut)  // settles into sittingOut for the rest of the break
        }
    }

    private func announceBackToWork(_ phase: Phase, natural: Bool) {
        guard shouldAnnounce(natural: natural) else { return }
        revealPanel(settle: false, entering: natural ? .alarm : .peeking)
        let message = MessageInfo(
            title: "Back to work!",
            detail: "Pomodoro \(phase.focusNumber) of \(engine.totalFocusBlocks)",
            style: .backToWork,
            buttons: [MessageButton(title: "Let's go", action: .acknowledge, isPrimary: true)]
        )
        if natural {
            playAlertSound(times: 2)
            showBubble(.message(message), alert: .backToWork, autoDismissAfter: Timing.backToWorkAlarm)
            present(.alarm)
        } else {
            showBubble(.message(message), autoDismissAfter: Timing.shortMessage)
            if isHamsterOut {
                present(.jumpingBack)
            }
        }
    }

    private func announceCelebration(natural: Bool) {
        guard shouldAnnounce(natural: natural) else { return }
        revealPanel(settle: false, entering: .alarm)
        if natural {
            playAlertSound(times: 2)
        }
        let studied = engine.phases.reduce(0) { $0 + $1.duration }
        let blocks = pomodoroCount(engine.totalFocusBlocks)
        let detail = natural && studied > 0
            ? "\(TimeFormat.humanDuration(studied)) of studying, \(blocks) 🎉"
            : "\(blocks) done — nice work 🎉"
        showBubble(
            .message(MessageInfo(
                title: "You did it!",
                detail: detail,
                style: .celebration,
                buttons: [MessageButton(title: "Yay!", action: .acknowledge, isPrimary: true)]
            )),
            alert: .celebration,
            autoDismissAfter: Timing.celebrationAlarm
        )
        present(.alarm)
    }

    private func playAlertSound(times: Int) {
        guard settings.soundEnabled else { return }
        sounds.play(settings.soundName, times: times)
    }

    // MARK: - Live displays (4 Hz)

    private func refreshDisplays(now: Date = Date()) {
        let remaining = TimeFormat.clock(engine.remaining(now: now))
        let isPaused = engine.status == .paused

        let tag = isSessionActive && settings.showTimerTag
            ? TimerTag(text: remaining, isBreak: isOnBreak, isPaused: isPaused)
            : nil
        if model.timerTag != tag {
            model.timerTag = tag
        }

        if case .status = model.bubble {
            if let info = statusInfo(now: now) {
                if model.bubble != .status(info) {
                    model.bubble = .status(info)
                }
            } else {
                closeBubble()  // the session ended underneath the status bubble
            }
        }

        let title: String
        if !isSessionActive {
            title = "🐹"
        } else if isPaused {
            title = "⏸ \(remaining)"
        } else {
            title = isOnBreak ? "☕️ \(remaining)" : "🐹 \(remaining)"
        }
        statusItem?.setTitle(title)
    }

    private func statusInfo(now: Date) -> StatusInfo? {
        guard isSessionActive, let phase = engine.currentPhase else { return nil }
        let title: String
        switch phase.kind {
        case .focus: title = "Focus time"
        case .shortBreak: title = "Short break"
        case .longBreak: title = "Long break"
        }
        let total = engine.totalFocusBlocks
        let doneAt = clockFormatter.string(from: now.addingTimeInterval(engine.sessionRemaining(now: now)))
        let position = phase.kind.isBreak
            ? "Up next: pomodoro \(min(phase.focusNumber + 1, total)) of \(total)"
            : "Pomodoro \(phase.focusNumber) of \(total)"
        // The bubble's PAUSED chip shows the paused state; the title stays the phase name.
        return StatusInfo(
            title: title,
            remaining: TimeFormat.clock(engine.remaining(now: now)),
            detail: "\(position) · done at \(doneAt)",
            progress: engine.progress(now: now),
            isBreak: phase.kind.isBreak,
            isPaused: engine.status == .paused
        )
    }

    private var menuState: StatusMenuState {
        StatusMenuState(
            isSessionActive: isSessionActive,
            isPaused: engine.status == .paused,
            isHamsterHidden: settings.hamsterHidden
        )
    }

    // MARK: - Mouse (30 Hz): click-through, hover, eyes

    private func pollMouse() {
        guard panel.isVisible else { return }
        let mouse = NSEvent.mouseLocation
        let frame = panel.frame
        // Panel-local, top-left origin (the stage's coordinate space).
        let local = CGPoint(x: mouse.x - frame.minX, y: frame.maxY - mouse.y)
        let time = StageModel.now()

        let catchesClicks = model.hitRects(at: time).contains { $0.contains(local) }
        if panel.ignoresMouseEvents == catchesClicks {
            panel.ignoresMouseEvents = !catchesClicks
        }

        let hovered = model.hamsterRect(at: time)?.contains(local) ?? false
        if model.isHovered != hovered {
            model.isHovered = hovered
        }

        guard settings.eyesFollowCursor else {
            model.look = .zero
            return
        }
        let eye = model.eyeCenter(at: time)
        var look = CGVector(dx: (local.x - eye.x) / Self.lookRange, dy: (local.y - eye.y) / Self.lookRange)
        let length = hypot(look.dx, look.dy)
        if length > 1 {
            look = CGVector(dx: look.dx / length, dy: look.dy / length)
        }
        model.look = look
    }

    // MARK: - Helpers

    private func schedule(after delay: TimeInterval, _ body: @escaping (HamsterController) -> Void) {
        pendingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                if let self { body(self) }
            }
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelPendingWork() {
        pendingWork?.cancel()
        pendingWork = nil
    }

    private func pomodoroCount(_ count: Int) -> String {
        count == 1 ? "1 pomodoro" : "\(count) pomodoros"
    }
}
