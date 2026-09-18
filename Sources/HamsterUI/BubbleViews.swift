import AppKit
import SwiftUI

// MARK: - Bubble layer

/// Reports the bubble's frame in the stage coordinate space (nil when no bubble is shown).
struct BubbleFrameKey: PreferenceKey {
    static let defaultValue: CGRect? = nil

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        guard let next = nextValue() else { return }
        value = value.map { $0.union(next) } ?? next
    }
}

extension BubbleContent {
    /// Bubbles with the same identity update in place (keeping text field state, no re-appear animation);
    /// a different identity animates the old bubble out and the new one in.
    var identity: String {
        switch self {
        case .askDuration: return "ask"
        case .status: return "status"
        case .message(let info): return "message|\(info.style)|\(info.title)"
        }
    }

    /// Width of the bubble body (the tail comes on top of this).
    var bodyWidth: CGFloat {
        switch self {
        case .askDuration: return 262
        case .status: return 246
        case .message: return 250
        }
    }
}

/// The speech bubble to the left of the hamster, placed so its tail points at the hamster's head.
struct BubbleLayer: View {
    let content: BubbleContent?
    let isOut: Bool
    let hasTimerTag: Bool
    /// Highest the bubble's top may go (below the part of the panel that overhangs the menu bar).
    let minTop: CGFloat
    let isHamsterHidden: Bool
    let onAction: (BubbleAction) -> Void

    var body: some View {
        let anchor = StageLayout.bubbleAnchor(isOut: isOut)
        let maxBottom = StageLayout.bubbleMaxBottom(isOut: isOut, hasTimerTag: hasTimerTag)
        BubblePlacementLayout(anchor: anchor, maxBottom: maxBottom, minTop: minTop) {
            if let content {
                SpeechBubble(content: content, anchor: anchor, maxBottom: maxBottom, minTop: minTop, onAction: onAction)
                    .id(content.identity)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.4, anchor: UnitPoint(x: 1, y: 0.62)).combined(with: .opacity),
                        removal: .scale(scale: 0.85, anchor: UnitPoint(x: 1, y: 0.62)).combined(with: .opacity)
                    ))
            }
        }
        .opacity(isHamsterHidden ? 0 : 1)
        .animation(.spring(response: 0.34, dampingFraction: 0.66), value: content?.identity)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isOut)
        .animation(.easeInOut(duration: 0.2), value: hasTimerTag)
        .animation(.easeOut(duration: 0.12), value: isHamsterHidden)
    }
}

/// Places each bubble with `StageLayout.bubbleFrame`: measured at its natural height, tail tip on the anchor.
struct BubblePlacementLayout: Layout {
    var anchor: CGPoint
    var maxBottom: CGFloat
    var minTop: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        StageMetrics.panelSize
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let frame = StageLayout.bubbleFrame(size: size, anchor: anchor, maxBottom: maxBottom, minTop: minTop)
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          anchor: .topLeading, proposal: ProposedViewSize(size))
        }
    }
}

/// One bubble: content on warm paper with a tail on the right pointing at `anchor` (panel coordinates).
struct SpeechBubble: View {
    let content: BubbleContent
    let anchor: CGPoint
    let maxBottom: CGFloat
    let minTop: CGFloat
    let onAction: (BubbleAction) -> Void

    var body: some View {
        inner
            .padding(EdgeInsets(top: 13, leading: 16, bottom: 15, trailing: 14))
            .frame(width: content.bodyWidth, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.trailing, StageLayout.tailLength)
            .background {
                GeometryReader { geo in
                    let placed = StageLayout.bubbleFrame(size: geo.size, anchor: anchor, maxBottom: maxBottom, minTop: minTop)
                    let shape = BubbleShape(tipY: anchor.y - placed.minY)
                    shape
                        .fill(LinearGradient(colors: [Palette.paper, Palette.paperShade], startPoint: .top, endPoint: .bottom))
                        .overlay(shape.stroke(Palette.paperEdge, lineWidth: 1))
                        .shadow(color: Palette.shadow.opacity(0.10), radius: 1, y: 1)
                        .shadow(color: Palette.shadow.opacity(0.22), radius: 9, y: 4)
                        .preference(key: BubbleFrameKey.self, value: geo.frame(in: .named(StageLayout.coordinateSpace)))
                }
            }
            // The bubble is always light; this also keeps the text field's text and caret dark.
            .environment(\.colorScheme, .light)
    }

    @ViewBuilder private var inner: some View {
        switch content {
        case .askDuration(let info):
            AskDurationContent(info: info, onAction: onAction)
        case .status(let info):
            StatusContent(info: info, onAction: onAction)
        case .message(let info):
            MessageContent(info: info, onAction: onAction)
        }
    }
}

// MARK: - Ask duration

struct AskDurationContent: View {
    let info: AskDurationInfo
    let onAction: (BubbleAction) -> Void

    /// Local, so re-sending the bubble (e.g. with an error) keeps what the user typed. (Declared with the
    /// `State` type: `@State` is a compiler-plugin macro in this SDK that Command Line Tools cannot expand.)
    private var text: State<String>
    @FocusState private var isFieldFocused: Bool
    @Environment(\.stageRendersStatically) private var rendersStatically

    init(info: AskDurationInfo, onAction: @escaping (BubbleAction) -> Void) {
        self.info = info
        self.onAction = onAction
        text = State(initialValue: info.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Text(info.prompt)
                    .font(.bubble(15, .bold))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                BubbleCloseButton { onAction(.dismiss) }
                    .offset(x: 3, y: -2)
            }

            VStack(alignment: .leading, spacing: 6) {
                field
                if let error = info.error {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text(error)
                            .font(.bubble(11.5, .medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(Palette.error)
                    .padding(.leading, 2)
                    .transition(.opacity)
                }
            }

            if !info.quickPicks.isEmpty {
                quickPicks
            }

            HStack(alignment: .center, spacing: 10) {
                if let hint = info.hint {
                    // "25 min focus · 5 min breaks" reads best as two stacked lines next to the button.
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(hint.components(separatedBy: " · ").enumerated()), id: \.offset) { _, line in
                            Text(line)
                        }
                    }
                    .font(.bubble(11, .medium))
                    .foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button { submit() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill").font(.system(size: 9.5, weight: .bold))
                        Text("Start").font(.bubble(13.5, .bold))
                    }
                }
                .buttonStyle(BubbleButtonStyle(kind: .primary(Palette.focus)))
            }
        }
        .onExitCommand { onAction(.dismiss) }
        .onAppear {
            guard !rendersStatically else { return }
            // Focus on the next runloop turn, once the field is in the window.
            DispatchQueue.main.async { isFieldFocused = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            // The app makes the panel key right around showing this bubble; focus again once it is.
            if !rendersStatically { isFieldFocused = true }
        }
    }

    private func submit() {
        onAction(.submitDuration(text.wrappedValue))
    }

    private var fieldIsHighlighted: Bool { rendersStatically || isFieldFocused }

    @ViewBuilder private var field: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Group {
            if rendersStatically {
                // ImageRenderer cannot draw an AppKit text field: draw a look-alike with a caret.
                HStack(spacing: 1) {
                    let typed = text.wrappedValue
                    if !typed.isEmpty { Text(typed).foregroundStyle(Palette.ink) }
                    Rectangle().fill(Palette.focus).frame(width: 1.5, height: 17)
                    if typed.isEmpty { Text(info.placeholder).foregroundStyle(Palette.inkFaint) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("", text: text.projectedValue, prompt: Text(info.placeholder).foregroundColor(Palette.inkFaint))
                    .textFieldStyle(.plain)
                    .foregroundStyle(Palette.ink)
                    .focused($isFieldFocused)
                    .onSubmit(submit)
            }
        }
        .font(.bubble(14, .medium))
        .padding(.horizontal, 11)
        .frame(height: 34)
        .background(shape.fill(Palette.field))
        .overlay(
            shape.strokeBorder(fieldIsHighlighted ? Palette.focus.opacity(0.85) : Palette.fieldEdge,
                               lineWidth: fieldIsHighlighted ? 1.5 : 1)
        )
        .shadow(color: fieldIsHighlighted ? Palette.focus.opacity(0.18) : .clear, radius: 3)
    }

    private var quickPicks: some View {
        let rows = stride(from: 0, to: info.quickPicks.count, by: 4).map {
            Array(info.quickPicks[$0..<min($0 + 4, info.quickPicks.count)])
        }
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(rows[row]) { pick in
                        Button { onAction(.start(seconds: pick.seconds)) } label: {
                            Text(pick.label).font(.bubble(12, .semibold))
                        }
                        .buttonStyle(BubbleButtonStyle(kind: .chip, fillsWidth: true))
                    }
                }
            }
        }
    }
}

// MARK: - Session status

struct StatusContent: View {
    let info: StatusInfo
    let onAction: (BubbleAction) -> Void

    private var tint: Color { info.isBreak ? Palette.rest : Palette.focus }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: info.isBreak ? "cup.and.saucer.fill" : "book.fill")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(tint)
                Text(info.title)
                    .font(.bubble(13.5, .bold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if info.isPaused {
                    Text("PAUSED")
                        .font(.bubble(9, .heavy))
                        .tracking(0.6)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Palette.ink.opacity(0.08)))
                }
                Spacer(minLength: 4)
                BubbleCloseButton { onAction(.dismiss) }
                    .offset(x: 3)
            }

            Text(info.remaining)
                .font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(info.isPaused ? Palette.inkSecondary : Palette.ink)
                .padding(.top, 2)

            Text(info.detail)
                .font(.bubble(11.5, .medium))
                .foregroundStyle(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ProgressTrack(progress: info.progress, tint: tint)
                .padding(.top, 9)

            HStack(spacing: 6) {
                if info.isPaused {
                    toolButton("Resume", symbol: "play.fill", action: .resume, tint: tint)
                } else {
                    toolButton("Pause", symbol: "pause.fill", action: .pause, tint: nil)
                }
                toolButton("Skip", symbol: "forward.end.fill", action: .skip, tint: nil)
                toolButton("+5 min", symbol: "plus", action: .extend(minutes: 5), tint: nil)
                toolButton("Stop", symbol: "stop.fill", action: .stop, tint: Palette.stop)
            }
            .padding(.top, 12)
        }
    }

    private func toolButton(_ title: String, symbol: String, action: BubbleAction, tint: Color?) -> some View {
        Button { onAction(action) } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 12, weight: .bold))
                Text(title).font(.bubble(10.5, .semibold))
            }
        }
        .buttonStyle(BubbleButtonStyle(kind: .tool(tint), fillsWidth: true))
    }
}

/// Rounded progress bar drawn with shapes (renders identically live and in snapshots).
struct ProgressTrack: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let fraction = progress.isFinite ? min(max(progress, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.track)
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: max(fraction > 0 ? 7 : 0, geo.size.width * fraction))
            }
        }
        .frame(height: 7)
        .animation(.easeOut(duration: 0.25), value: progress)
    }
}

// MARK: - Message

struct MessageContent: View {
    let info: MessageInfo
    let onAction: (BubbleAction) -> Void

    private var tint: Color { Palette.tint(for: info.style) }

    var body: some View {
        if info.buttons.isEmpty {
            // A message without buttons is dismissed by clicking it.
            layout
                .contentShape(Rectangle())
                .onTapGesture { onAction(.dismiss) }
        } else {
            layout
        }
    }

    private var layout: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 11) {
                Text(Palette.emoji(for: info.style))
                    .font(.system(size: 19))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(tint.opacity(0.16)))
                    .overlay(Circle().strokeBorder(tint.opacity(0.28), lineWidth: 1))
                VStack(alignment: .leading, spacing: 3) {
                    Text(info.title)
                        .font(.bubble(15, .bold))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = info.detail {
                        Text(detail)
                            .font(.bubble(12.5, .medium))
                            .foregroundStyle(Palette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, info.detail == nil ? 8 : 1)
            }

            if !info.buttons.isEmpty {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    ForEach(info.buttons) { button in
                        Button { onAction(button.action) } label: {
                            Text(button.title).font(.bubble(13, .bold))
                        }
                        .buttonStyle(BubbleButtonStyle(kind: button.isPrimary ? .primary(tint) : .secondary))
                    }
                }
            }
        }
    }
}
