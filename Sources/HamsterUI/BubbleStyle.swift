import SwiftUI

/// Colors of the speech bubble and timer tag. The bubble is always light (warm paper) with dark ink, so it
/// reads the same over light and dark windows.
enum Palette {
    static let paper = Color(red: 1.0, green: 0.984, blue: 0.955)
    static let paperShade = Color(red: 0.995, green: 0.962, blue: 0.91)
    static let paperEdge = Color(red: 0.84, green: 0.74, blue: 0.62).opacity(0.75)
    static let shadow = Color(red: 0.22, green: 0.13, blue: 0.05)

    static let ink = Color(red: 0.23, green: 0.16, blue: 0.11)
    static let inkSecondary = Color(red: 0.47, green: 0.38, blue: 0.31)
    static let inkFaint = Color(red: 0.64, green: 0.56, blue: 0.49)
    static let error = Color(red: 0.82, green: 0.33, blue: 0.27)

    static let field = Color.white
    static let fieldEdge = Color(red: 0.87, green: 0.79, blue: 0.69)

    static let chip = Color(red: 0.99, green: 0.925, blue: 0.84)
    static let chipEdge = Color(red: 0.93, green: 0.81, blue: 0.66)
    static let chipInk = Color(red: 0.55, green: 0.31, blue: 0.09)

    static let secondaryFill = Color(red: 0.965, green: 0.93, blue: 0.885)
    static let secondaryEdge = Color(red: 0.88, green: 0.81, blue: 0.72)

    static let track = Color(red: 0.93, green: 0.89, blue: 0.83)

    /// Warm orange: focus, the hamster's own color, the default primary action.
    static let focus = Color(red: 0.95, green: 0.55, blue: 0.16)
    /// Mint green: breaks.
    static let rest = Color(red: 0.22, green: 0.66, blue: 0.47)
    static let study = Color(red: 0.25, green: 0.49, blue: 0.84)
    static let party = Color(red: 0.87, green: 0.33, blue: 0.6)
    static let stop = Color(red: 0.8, green: 0.33, blue: 0.29)

    static func tint(for style: MessageStyle) -> Color {
        switch style {
        case .info: return focus
        case .breakTime: return rest
        case .backToWork: return study
        case .celebration: return party
        }
    }

    static func emoji(for style: MessageStyle) -> String {
        switch style {
        case .info: return "🐹"
        case .breakTime: return "☕️"
        case .backToWork: return "📚"
        case .celebration: return "🎉"
        }
    }
}

extension Font {
    /// The bubble's rounded type.
    static func bubble(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - Bubble shape

/// Comic speech bubble: a rounded rectangle with a curved tail on its right edge. The tail tip is at the
/// right edge of the rect, at `tipY` (clamped so the tail always leaves the straight part of the edge).
struct BubbleShape: Shape {
    var tipY: CGFloat
    var tailLength: CGFloat = StageLayout.tailLength
    var cornerRadius: CGFloat = 20

    func path(in rect: CGRect) -> Path {
        let body = CGRect(x: rect.minX, y: rect.minY, width: max(0, rect.width - tailLength), height: rect.height)
        let r = min(cornerRadius, body.height / 2, body.width / 2)
        let baseHeight: CGFloat = 20
        // Tail leaves the right edge between baseTop and baseBottom and points slightly downwards.
        let lowestTip = body.maxY - r * 0.5
        let highestTip = body.minY + r * 0.5 + baseHeight
        let tip = CGPoint(x: rect.maxX, y: min(max(rect.minY + tipY, highestTip), max(highestTip, lowestTip)))
        let baseBottom = tip.y - 1
        let baseTop = baseBottom - baseHeight

        var path = Path()
        path.move(to: CGPoint(x: body.minX + r, y: body.minY))
        path.addLine(to: CGPoint(x: body.maxX - r, y: body.minY))
        path.addArc(tangent1End: CGPoint(x: body.maxX, y: body.minY), tangent2End: CGPoint(x: body.maxX, y: body.minY + r), radius: r)
        path.addLine(to: CGPoint(x: body.maxX, y: max(body.minY + r, baseTop)))
        path.addQuadCurve(to: tip, control: CGPoint(x: body.maxX + tailLength * 0.45, y: baseTop + 5))
        path.addQuadCurve(to: CGPoint(x: body.maxX, y: min(body.maxY - r, baseBottom)),
                          control: CGPoint(x: body.maxX + tailLength * 0.3, y: tip.y - 1))
        path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - r))
        path.addArc(tangent1End: CGPoint(x: body.maxX, y: body.maxY), tangent2End: CGPoint(x: body.maxX - r, y: body.maxY), radius: r)
        path.addLine(to: CGPoint(x: body.minX + r, y: body.maxY))
        path.addArc(tangent1End: CGPoint(x: body.minX, y: body.maxY), tangent2End: CGPoint(x: body.minX, y: body.maxY - r), radius: r)
        path.addLine(to: CGPoint(x: body.minX, y: body.minY + r))
        path.addArc(tangent1End: CGPoint(x: body.minX, y: body.minY), tangent2End: CGPoint(x: body.minX + r, y: body.minY), radius: r)
        path.closeSubpath()
        return path
    }
}

// MARK: - Buttons

/// Custom-drawn buttons that look clickable in a panel that never becomes the active window (system
/// bordered buttons render greyed out there).
struct BubbleButtonStyle: ButtonStyle {
    enum Kind {
        /// Filled with the tint, white label.
        case primary(Color)
        /// Soft paper-colored button with a hairline edge.
        case secondary
        /// Quick-pick chip.
        case chip
        /// Small square tool button (icon over label), optionally tinted.
        case tool(Color?)
    }

    var kind: Kind
    var fillsWidth = false

    func makeBody(configuration: Configuration) -> some View {
        BubbleButtonBody(label: configuration.label, isPressed: configuration.isPressed, kind: kind, fillsWidth: fillsWidth)
    }
}

private struct BubbleButtonBody<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let kind: BubbleButtonStyle.Kind
    let fillsWidth: Bool
    /// `@State` is a compiler-plugin macro in this SDK and the plugin ships only with Xcode, so state is
    /// declared with the property wrapper type directly (SwiftUI finds it the same way).
    private var isHovering = State(initialValue: false)

    var body: some View {
        label
            .lineLimit(1)
            .fixedSize(horizontal: !fillsWidth, vertical: false)
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: minHeight)
            .foregroundStyle(foreground)
            .background(background)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .scaleEffect(isPressed ? 0.96 : 1)
            .brightness(isPressed ? -0.06 : (isHovering.wrappedValue ? 0.03 : 0))
            .animation(.easeOut(duration: 0.12), value: isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovering.wrappedValue)
            .onHover { isHovering.wrappedValue = $0 }
    }

    private var cornerRadius: CGFloat {
        switch kind {
        case .primary, .secondary: return 10
        case .chip: return 9
        case .tool: return 10
        }
    }

    private var minHeight: CGFloat {
        switch kind {
        case .primary, .secondary: return 30
        case .chip: return 26
        case .tool: return 42
        }
    }

    private var horizontalPadding: CGFloat {
        switch kind {
        case .primary, .secondary: return 14
        case .chip: return 6
        case .tool: return 2
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary: return .white
        case .secondary: return Palette.ink
        case .chip: return Palette.chipInk
        case .tool(let tint): return tint ?? Palette.ink
        }
    }

    @ViewBuilder private var background: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        switch kind {
        case .primary(let tint):
            shape
                .fill(tint.gradient)
                .overlay(shape.strokeBorder(Color.black.opacity(0.08), lineWidth: 1))
                .overlay(alignment: .top) {
                    // Soft top highlight for a gently domed, pressable look.
                    shape.fill(LinearGradient(colors: [.white.opacity(0.28), .clear], startPoint: .top, endPoint: .center))
                }
                .shadow(color: tint.opacity(0.35), radius: 3, y: 1.5)
        case .secondary:
            shape
                .fill(Palette.secondaryFill)
                .overlay(shape.strokeBorder(Palette.secondaryEdge, lineWidth: 1))
                .shadow(color: Palette.shadow.opacity(0.08), radius: 1, y: 1)
        case .chip:
            shape
                .fill(Palette.chip)
                .overlay(shape.strokeBorder(Palette.chipEdge, lineWidth: 1))
        case .tool(let tint):
            shape
                .fill((tint ?? Palette.ink).opacity(0.08))
                .overlay(shape.strokeBorder((tint ?? Palette.ink).opacity(0.14), lineWidth: 1))
        }
    }
}

/// Small round "×" in a bubble's top-right corner.
struct BubbleCloseButton: View {
    let action: () -> Void
    /// `@State` is a compiler-plugin macro in this SDK and the plugin ships only with Xcode, so state is
    /// declared with the property wrapper type directly (SwiftUI finds it the same way).
    private var isHovering = State(initialValue: false)

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(isHovering.wrappedValue ? Palette.ink : Palette.inkFaint)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Palette.ink.opacity(isHovering.wrappedValue ? 0.1 : 0.05)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering.wrappedValue = $0 }
        .help("Close")
        .accessibilityLabel("Close")
    }
}
