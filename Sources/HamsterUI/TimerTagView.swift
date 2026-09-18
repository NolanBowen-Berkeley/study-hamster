import SwiftUI

/// The countdown tag: hangs off the window edge under the paws while peeking (a little sign on two
/// strings), and stands on the ledge beside the hamster while it is out.
struct TimerTagLayer: View {
    let tag: TimerTag?
    let isOut: Bool
    let isHamsterHidden: Bool

    var body: some View {
        PanelCanvas {
            if let tag {
                TimerTagView(tag: tag, showsStrings: !isOut)
                    .placed(at: isOut ? StageLayout.outTagPoint : StageLayout.peekTagPoint,
                            anchor: isOut ? .bottomTrailing : .top)
                    .transition(.scale(scale: 0.6, anchor: .top).combined(with: .opacity))
            }
        }
        .opacity(isHamsterHidden ? 0 : 1)
        .animation(.spring(response: 0.45, dampingFraction: 0.72), value: isOut)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: tag == nil)
        .animation(.easeOut(duration: 0.12), value: isHamsterHidden)
    }
}

struct TimerTagView: View {
    let tag: TimerTag
    /// Draw the two strings the tag hangs from (they disappear behind the paws at the ledge).
    let showsStrings: Bool

    private var fill: Color {
        tag.isBreak ? Color(red: 0.86, green: 0.96, blue: 0.9) : Color(red: 1.0, green: 0.95, blue: 0.85)
    }

    private var edge: Color {
        tag.isBreak ? Color(red: 0.55, green: 0.8, blue: 0.66) : Color(red: 0.9, green: 0.76, blue: 0.55)
    }

    private var ink: Color {
        tag.isBreak ? Color(red: 0.13, green: 0.43, blue: 0.29) : Color(red: 0.5, green: 0.3, blue: 0.1)
    }

    private var symbol: String {
        if tag.isPaused { return "pause.fill" }
        return tag.isBreak ? "cup.and.saucer.fill" : "book.fill"
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
            Text(tag.text)
                .font(.system(size: 12.5, weight: .bold, design: .rounded).monospacedDigit())
        }
        .foregroundStyle(ink.opacity(tag.isPaused ? 0.75 : 1))
        .padding(.horizontal, 9)
        .frame(height: StageLayout.tagHeight)
        .background(
            Capsule().fill(LinearGradient(colors: [fill.opacity(0.96), fill], startPoint: .top, endPoint: .bottom))
        )
        .overlay(Capsule().strokeBorder(edge, lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 2.5, y: 1.5)
        .background(alignment: .top) {
            strings.opacity(showsStrings ? 1 : 0)
        }
        .fixedSize()
        .environment(\.colorScheme, .light)
    }

    /// Two short cords from the tag up to the ledge, under the paws.
    private var strings: some View {
        let length = StageLayout.tagHang + 2
        return HStack(spacing: StageLayout.tagStringOffset * 2 - 1.5) {
            Capsule().frame(width: 1.5, height: length)
            Capsule().frame(width: 1.5, height: length)
        }
        .foregroundStyle(edge.opacity(0.9))
        .offset(y: -length + 3)
    }
}
