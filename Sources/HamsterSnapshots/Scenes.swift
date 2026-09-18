import AppKit
import HamsterUI
import SwiftUI

/// Everything the default run renders: figure poses, stage composites and animation strips.
@MainActor
enum Scenes {
    // MARK: Sample content (mirrors what the app shows)

    static let quickPicks = [
        QuickPick(label: "25 min", seconds: 25 * 60), QuickPick(label: "50 min", seconds: 50 * 60),
        QuickPick(label: "1 h", seconds: 3600), QuickPick(label: "2 h", seconds: 7200),
    ]

    static let ask = BubbleContent.askDuration(AskDurationInfo(
        prompt: "How long do you want to study?", hint: "25 min focus · 5 min breaks", quickPicks: quickPicks))

    static let askError = BubbleContent.askDuration(AskDurationInfo(
        prompt: "How long do you want to study?", text: "a while", error: "Try something like 45m or 1h 30m",
        hint: "25 min focus · 5 min breaks", quickPicks: quickPicks))

    static let statusFocus = BubbleContent.status(StatusInfo(
        title: "Focus time", remaining: "18:42", detail: "Pomodoro 2 of 4 · done at 3:45 PM",
        progress: 0.25, isBreak: false, isPaused: false))

    static let statusPaused = BubbleContent.status(StatusInfo(
        title: "Short break", remaining: "3:12", detail: "Up next: pomodoro 3 of 4 · done at 3:52 PM",
        progress: 0.36, isBreak: true, isPaused: true))

    static let statusPausedFocus = BubbleContent.status(StatusInfo(
        title: "Focus time", remaining: "18:42", detail: "Pomodoro 2 of 4 · done at 3:45 PM",
        progress: 0.25, isBreak: false, isPaused: true))

    static let breakTime = BubbleContent.message(MessageInfo(
        title: "Break time!", detail: "5 min — stretch, sip some water", style: .breakTime,
        buttons: [MessageButton(title: "Skip break", action: .skip), MessageButton(title: "OK", action: .acknowledge, isPrimary: true)]))

    static let backToWork = BubbleContent.message(MessageInfo(
        title: "Back to work!", detail: "Pomodoro 3 of 4", style: .backToWork,
        buttons: [MessageButton(title: "Let's go", action: .acknowledge, isPrimary: true)]))

    static let celebration = BubbleContent.message(MessageInfo(
        title: "You did it!", detail: "2 h of studying, 4 pomodoros 🎉", style: .celebration,
        buttons: [MessageButton(title: "Yay!", action: .acknowledge, isPrimary: true)]))

    static let hello = BubbleContent.message(MessageInfo(
        title: "Hi! Click me when you're ready to study.", style: .info))

    static let letsGo = BubbleContent.message(MessageInfo(
        title: "Let's go!", detail: "4 pomodoros · done at 3:45 PM", style: .info))

    static let focusTag = TimerTag(text: "18:42", isBreak: false, isPaused: false)
    static let breakTag = TimerTag(text: "4:59", isBreak: true, isPaused: false)
    static let pausedTag = TimerTag(text: "3:12", isBreak: true, isPaused: true)

    // MARK: Animator samples

    /// Params `seconds` after switching from a settled `from` mode to `to`.
    static func sample(_ to: HamsterMode, after seconds: TimeInterval, from: HamsterMode = .peeking,
                       look: CGVector = .zero) -> HamsterParams {
        let animator = HamsterAnimator(seed: 3)
        animator.setMode(from, at: 0)
        animator.setMode(to, at: 20)
        return animator.params(at: 20 + seconds, look: look)
    }

    // MARK: Poses

    static let poses: [(name: String, params: HamsterParams, mode: HamsterMode)] = {
        var lookLeft = HamsterParams.peek
        lookLeft.look = CGVector(dx: -1, dy: 0.1)
        var blink = HamsterParams.peek
        blink.eyeOpenness = 0.3
        let happy = HamsterParams(eyeOpenness: 0.05, earPerk: 0.5, mouthOpen: 0.7, blush: 0.85)
        var cheering = HamsterParams.sitting
        cheering.armsUp = 1
        cheering.mouthOpen = 1
        cheering.sparkle = 1
        cheering.earPerk = 1
        cheering.blush = 0.8
        var squash = HamsterParams.sitting
        squash.squash = 0.8
        var stretch = HamsterParams.sitting
        stretch.squash = 1.15
        stretch.armsUp = 1
        stretch.rise = 16
        stretch.mouthOpen = 0.8
        let mid = HamsterParams(outAmount: 0.5, squash: 1.08, armsUp: 0.5, sparkle: 0.5)
        let tilt = HamsterParams(tiltDegrees: 10, look: CGVector(dx: 0.6, dy: -0.4), earPerk: 0.3)
        let sleepy = HamsterParams(eyeOpenness: 0.3, earPerk: -0.8, blush: 0.2)
        return [
            ("peek", .peek, .peeking), ("look-left", lookLeft, .peeking), ("blink", blink, .peeking),
            ("happy", happy, .peeking), ("hover", HamsterParams.peek.hovered(), .peeking),
            ("out-sitting", .sitting, .sittingOut), ("cheering", cheering, .alarm), ("squash", squash, .sittingOut),
            ("stretch", stretch, .sittingOut), ("mid-transition-0.5", mid, .jumpingOut), ("tilt", tilt, .peeking),
            ("sleepy", sleepy, .peeking),
        ]
    }()

    static func renderPoses(to dir: URL) throws -> [URL] {
        var written: [URL] = []
        let poseDir = dir.appendingPathComponent("poses")
        try FileManager.default.createDirectory(at: poseDir, withIntermediateDirectories: true)
        for theme in Theme.allCases {
            let tiles = poses.map { HamsterTile(theme: theme, params: $0.params, mode: $0.mode, caption: $0.name) }
            for (pose, tile) in zip(poses, tiles) {
                let url = poseDir.appendingPathComponent("\(pose.name)-\(theme.rawValue).png")
                try writePNG(tile.background(theme.sheet), size: CGSize(width: HamsterTile.size.width,
                             height: HamsterTile.size.height + HamsterTile.captionHeight), to: url)
            }
            let size = TileSheet<HamsterTile>.size(count: tiles.count, columns: 6)
            let url = dir.appendingPathComponent("poses-\(theme.rawValue).png")
            try writePNG(TileSheet(theme: theme, title: "Poses (\(theme.rawValue) window)", columns: 6, tiles: tiles), size: size, to: url)
            written.append(url)
        }
        return written
    }

    // MARK: Stage composites

    static func renderComposites(to dir: URL) throws -> [URL] {
        let peekIdle = sample(.peeking, after: 1.2, from: .hidden, look: CGVector(dx: -0.8, dy: 0.2))
        let sitting = sample(.sittingOut, after: 2.2, from: .peeking, look: CGVector(dx: -0.7, dy: 0.1))
        let alarmApex = sample(.alarm, after: 1.13, from: .sittingOut)
        let alarmLanding = sample(.alarm, after: 1.26, from: .sittingOut)
        let scenes: [(String, Theme, HamsterParams, HamsterMode, BubbleContent?, TimerTag?)] = [
            ("stage-ask", .light, peekIdle, .peeking, ask, nil),
            ("stage-ask-error", .dark, peekIdle, .peeking, askError, nil),
            ("stage-status-focus", .light, peekIdle, .peeking, statusFocus, focusTag),
            ("stage-status-paused-break", .dark, sitting, .sittingOut, statusPaused, pausedTag),
            ("stage-break-message", .light, sitting, .sittingOut, breakTime, breakTag),
            ("stage-break-message", .dark, sitting, .sittingOut, breakTime, breakTag),
            ("stage-back-to-work", .light, alarmApex, .alarm, backToWork, nil),
            ("stage-celebration", .dark, alarmLanding, .alarm, celebration, nil),
            ("stage-hello", .light, peekIdle, .peeking, hello, nil),
            ("stage-lets-go-tag", .dark, peekIdle, .peeking, letsGo, focusTag),
            ("stage-tag-only", .light, peekIdle, .peeking, nil, focusTag),
            ("stage-tag-only-break", .dark, sitting, .sittingOut, nil, breakTag),
            ("stage-status-paused-focus", .light, peekIdle, .peeking, statusPausedFocus,
             TimerTag(text: "18:42", isBreak: false, isPaused: true)),
        ]
        var written: [URL] = []
        for (name, theme, params, mode, bubble, tag) in scenes {
            let url = dir.appendingPathComponent("\(name)-\(theme.rawValue).png")
            try writePNG(StageScene(theme: theme, params: params, mode: mode, bubble: bubble, timerTag: tag),
                         size: StageMetrics.panelSize, to: url)
            written.append(url)
        }
        written += try renderNearMenuBar(to: dir, peek: peekIdle, sitting: sitting)
        written.append(try renderHitRects(to: dir))
        return written
    }

    /// Windows whose top is 0, 30 and 300 pt below the menu bar. The ledge stays on the window's edge while
    /// the hamster has its headroom under the menu bar; closer than that he peeks from just inside the window
    /// and the panel's transparent top overhangs the menu bar (PerchCalculator, checked in HamsterChecks).
    static func renderNearMenuBar(to dir: URL, peek: HamsterParams, sitting: HamsterParams) throws -> [URL] {
        var written: [URL] = []
        for gap: CGFloat in [0, 30, 300] {
            let variants: [(String, Theme, HamsterParams, HamsterMode, CGFloat, BubbleContent?, TimerTag?)] = [
                ("ask", .light, peek, .peeking, StageMetrics.peekHeadroom, askError, nil),
                ("status", .dark, peek, .peeking, StageMetrics.peekHeadroom, statusFocus, focusTag),
                ("break", .light, sitting, .sittingOut, StageMetrics.outHeadroom, breakTime, breakTag),
            ]
            for (name, theme, params, mode, headroom, bubble, tag) in variants {
                // Panel y of the menu bar's bottom edge (negative: above the panel) and of the window's top.
                let menuBarBottom = StageMetrics.ledgeFromTop - max(gap, headroom)
                let url = dir.appendingPathComponent("menubar-gap\(Int(gap))-\(name)-\(theme.rawValue).png")
                try writePNG(StageScene(theme: theme, params: params, mode: mode, bubble: bubble, timerTag: tag,
                                        topInset: max(0, menuBarBottom), windowTop: menuBarBottom + gap),
                             size: StageMetrics.panelSize, to: url)
                written.append(url)
            }
        }
        return written
    }

    /// Debug overlay: the clickable hamster rect and eye center the app uses, over the peeking stage.
    static func renderHitRects(to dir: URL) throws -> URL {
        let model = StageModel(animator: HamsterAnimator(seed: 3))
        model.setMode(.peeking, at: 0)
        let t: TimeInterval = 5
        let params = model.animator.params(at: t, look: .zero)
        let rect = model.hamsterRect(at: t) ?? .zero
        let eye = model.eyeCenter(at: t)
        let view = ZStack(alignment: .topLeading) {
            StageScene(theme: .light, params: params, mode: .peeking)
            Rectangle().strokeBorder(Color.red, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
            Circle().fill(Color.blue).frame(width: 7, height: 7).offset(x: eye.x - 3.5, y: eye.y - 3.5)
            Rectangle().fill(Color.red.opacity(0.6)).frame(width: StageMetrics.panelSize.width, height: 1)
                .offset(y: StageMetrics.ledgeFromTop)
        }
        let url = dir.appendingPathComponent("debug-hitrect-light.png")
        try writePNG(view, size: StageMetrics.panelSize, to: url)
        return url
    }

    // MARK: Animation strips

    static func renderStrips(to dir: URL) throws -> [URL] {
        struct Strip {
            let name: String
            let from: HamsterMode
            let to: HamsterMode
            let start: TimeInterval
            let length: TimeInterval
        }
        let strips = [
            Strip(name: "jumpingOut", from: .peeking, to: .jumpingOut, start: 0, length: 0.95),
            Strip(name: "alarm", from: .sittingOut, to: .alarm, start: 1.0, length: 0.5 * 7 / 8),
            Strip(name: "jumpingBack", from: .sittingOut, to: .jumpingBack, start: 0, length: 0.7),
            Strip(name: "cheer", from: .peeking, to: .jumpingBack, start: 0, length: 0.7),
            Strip(name: "popUp", from: .hidden, to: .peeking, start: 0, length: 0.4),
            Strip(name: "duck", from: .peeking, to: .hidden, start: 0, length: 0.18),
        ]
        var written: [URL] = []
        for theme in Theme.allCases {
            for strip in strips {
                let tiles: [HamsterTile] = (0..<8).map { i in
                    let t = strip.start + strip.length * Double(i) / 7
                    let params = sample(strip.to, after: t, from: strip.from)
                    return HamsterTile(theme: theme, params: params, mode: strip.to,
                                       caption: String(format: "%.2f s", t))
                }
                let size = TileSheet<HamsterTile>.size(count: 8, columns: 8)
                let url = dir.appendingPathComponent("strip-\(strip.name)-\(theme.rawValue).png")
                try writePNG(TileSheet(theme: theme, title: "\(strip.from) → \(strip.to)", columns: 8, tiles: tiles),
                             size: size, scale: 1.5, to: url)
                written.append(url)
            }
        }
        return written
    }
}
