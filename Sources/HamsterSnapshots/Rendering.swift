import AppKit
import HamsterUI
import SwiftUI

enum RenderError: Error, CustomStringConvertible {
    case noImage(String)
    case noPNG(String)

    var description: String {
        switch self {
        case .noImage(let name): return "ImageRenderer produced no image for \(name)"
        case .noPNG(let name): return "could not encode \(name) as PNG"
        }
    }
}

/// Renders `view` at exactly `size` points × `scale` and writes a PNG.
@MainActor
func writePNG<V: View>(_ view: V, size: CGSize, scale: CGFloat = 2, to url: URL, opaque: Bool = false) throws {
    let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
    renderer.scale = scale
    renderer.proposedSize = ProposedViewSize(size)
    renderer.isOpaque = opaque
    guard let image = renderer.cgImage else { throw RenderError.noImage(url.lastPathComponent) }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else { throw RenderError.noPNG(url.lastPathComponent) }
    try data.write(to: url)
}

// MARK: - Backdrops

enum Theme: String, CaseIterable {
    case light, dark

    var desktop: [Color] {
        switch self {
        case .light: return [Color(red: 0.66, green: 0.75, blue: 0.91), Color(red: 0.9, green: 0.84, blue: 0.95)]
        case .dark: return [Color(red: 0.1, green: 0.13, blue: 0.25), Color(red: 0.22, green: 0.15, blue: 0.3)]
        }
    }

    var windowBody: Color { self == .light ? .white : Color(red: 0.12, green: 0.12, blue: 0.13) }
    var titleBar: Color { self == .light ? Color(red: 0.93, green: 0.93, blue: 0.94) : Color(red: 0.19, green: 0.19, blue: 0.2) }
    var edge: Color { self == .light ? Color.black.opacity(0.14) : Color.white.opacity(0.12) }
    var text: Color { self == .light ? Color.black.opacity(0.1) : Color.white.opacity(0.1) }
    var titleText: Color { self == .light ? Color.black.opacity(0.55) : Color.white.opacity(0.55) }
    var label: Color { self == .light ? Color(red: 0.25, green: 0.2, blue: 0.16) : Color(red: 0.9, green: 0.87, blue: 0.84) }
    var sheet: Color { self == .light ? Color(red: 0.97, green: 0.96, blue: 0.95) : Color(red: 0.08, green: 0.08, blue: 0.09) }
}

/// Desktop wallpaper above, and an app window whose top edge is the ledge (or `windowTop`) and whose right
/// edge sits `hamsterInsetFromWindowRight` right of the hamster — in panel coordinates, like the real app.
struct FakeDesktop: View {
    let theme: Theme
    var windowLeft: CGFloat = 18
    var windowTop: CGFloat = StageMetrics.ledgeFromTop

    var body: some View {
        let right = StageMetrics.hamsterCenterX + StageMetrics.hamsterInsetFromWindowRight
        let size = StageMetrics.panelSize
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: theme.desktop, startPoint: .topLeading, endPoint: .bottomTrailing)
            FakeWindow(theme: theme, title: "Biology — Chapter 4 notes")
                .frame(width: right - windowLeft, height: size.height - windowTop + 40)
                .offset(x: windowLeft, y: windowTop)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

/// What covers the top of a panel that overhangs the menu bar: the menu bar (drawn above the hamster's
/// panel level) ending at `menuBarBottom`, and above it the edge of the screen.
struct FakeMenuBar: View {
    static let height: CGFloat = 34
    let theme: Theme
    let menuBarBottom: CGFloat

    var body: some View {
        let size = StageMetrics.panelSize
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.85)
                .frame(width: size.width, height: max(0, menuBarBottom - Self.height))
            HStack(spacing: 14) {
                Spacer()
                ForEach(["wifi", "battery.75percent", "magnifyingglass", "switch.2"], id: \.self) { symbol in
                    Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                }
                Text("Fri 3:12 PM").font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(theme == .light ? Color.black.opacity(0.8) : Color.white.opacity(0.9))
            .padding(.trailing, 12)
            .frame(width: size.width, height: Self.height)
            .background(theme == .light ? Color.white.opacity(0.55) : Color.black.opacity(0.45))
            .offset(y: menuBarBottom - Self.height)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
        .allowsHitTesting(false)
    }
}

struct FakeWindow: View {
    let theme: Theme
    let title: String

    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 11, topTrailingRadius: 11, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                theme.titleBar
                HStack(spacing: 7) {
                    Circle().fill(Color(red: 1, green: 0.37, blue: 0.34)).frame(width: 11)
                    Circle().fill(Color(red: 1, green: 0.74, blue: 0.18)).frame(width: 11)
                    Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25)).frame(width: 11)
                    Spacer()
                }
                .padding(.leading, 12)
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.titleText)
            }
            .frame(height: 30)
            VStack(alignment: .leading, spacing: 9) {
                ForEach(0..<9, id: \.self) { line in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(theme.text)
                        .frame(width: [300, 340, 270, 320, 200, 330, 290, 310, 250][line], height: 7)
                }
            }
            .padding(.top, 18)
            .padding(.leading, 22)
            Spacer(minLength: 0)
        }
        .background(theme.windowBody)
        .clipShape(shape)
        .overlay(shape.stroke(theme.edge, lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
    }
}

/// The stage (frame from explicit params) on the fake desktop, full panel size. With a `topInset` the panel
/// overhangs the menu bar by that much (a window near the top of the screen): the menu bar is drawn over it.
struct StageScene: View {
    let theme: Theme
    let params: HamsterParams
    let mode: HamsterMode
    var bubble: BubbleContent?
    var timerTag: TimerTag?
    var topInset: CGFloat = 0
    var windowTop: CGFloat = StageMetrics.ledgeFromTop

    var body: some View {
        ZStack(alignment: .topLeading) {
            FakeDesktop(theme: theme, windowTop: windowTop)
            HamsterStageFrame(params: params, mode: mode, bubble: bubble, timerTag: timerTag, topInset: topInset)
            if topInset > 0 {
                FakeMenuBar(theme: theme, menuBarBottom: topInset)
            }
        }
        .frame(width: StageMetrics.panelSize.width, height: StageMetrics.panelSize.height)
    }
}

/// A crop of a `StageScene` around the hamster, with a caption.
struct HamsterTile: View {
    static let size = CGSize(width: 176, height: 290)
    /// Panel y shown at the top of the tile.
    static let cropTop: CGFloat = 0
    static let captionHeight: CGFloat = 24

    let theme: Theme
    let params: HamsterParams
    let mode: HamsterMode
    let caption: String
    var timerTag: TimerTag?

    var body: some View {
        VStack(spacing: 0) {
            StageScene(theme: theme, params: params, mode: mode, timerTag: timerTag)
                .offset(x: -(StageMetrics.hamsterCenterX - Self.size.width / 2), y: -Self.cropTop)
                .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(caption)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.label)
                .lineLimit(1)
                .frame(height: Self.captionHeight)
        }
        .frame(width: Self.size.width, height: Self.size.height + Self.captionHeight)
    }
}

/// Tiles in a grid on a plain sheet.
struct TileSheet<Tile: View>: View {
    let theme: Theme
    let title: String
    let columns: Int
    let tiles: [Tile]

    static func size(count: Int, columns: Int) -> CGSize {
        let rows = (count + columns - 1) / columns
        let tile = CGSize(width: HamsterTile.size.width, height: HamsterTile.size.height + HamsterTile.captionHeight)
        return CGSize(width: CGFloat(columns) * tile.width + CGFloat(columns - 1) * 12 + 32,
                      height: CGFloat(rows) * tile.height + CGFloat(rows - 1) * 10 + 32 + 30)
    }

    var body: some View {
        let rows = stride(from: 0, to: tiles.count, by: columns).map { Array($0..<min($0 + columns, tiles.count)) }
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(theme.label)
                .frame(height: 20)
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(rows[row], id: \.self) { index in tiles[index] }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.sheet)
    }
}
