import AppKit
import HamsterUI
import SwiftUI

/// The app icon: the hamster peeking over the top edge of a little window, on a warm rounded square.
/// Drawn on a 1024 pt canvas (macOS icon grid: 824 pt body with ~185 pt continuous corners).
struct AppIconView: View {
    static let canvas: CGFloat = 1024
    static let bodySize: CGFloat = 824

    var body: some View {
        let body = Self.bodySize
        let square = RoundedRectangle(cornerRadius: 185, style: .continuous)
        // Figure scale and where its ledge sits inside the icon body.
        let scale: CGFloat = 4.2
        let ledgeY: CGFloat = 548
        let windowInset: CGFloat = 92
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(red: 1.0, green: 0.95, blue: 0.85), Color(red: 1.0, green: 0.77, blue: 0.52)],
                           startPoint: .top, endPoint: .bottom)
            // Soft glow behind the head.
            Circle()
                .fill(RadialGradient(colors: [Color.white.opacity(0.55), .clear], center: .center, startRadius: 10, endRadius: 330))
                .frame(width: 660, height: 660)
                .offset(x: body / 2 - 330, y: ledgeY - 520)
            // The window the hamster peeks over.
            let window = UnevenRoundedRectangle(topLeadingRadius: 46, topTrailingRadius: 46, style: .continuous)
            VStack(spacing: 0) {
                ZStack(alignment: .leading) {
                    Color(red: 0.93, green: 0.92, blue: 0.95)
                    HStack(spacing: 22) {
                        Circle().fill(Color(red: 1, green: 0.37, blue: 0.34)).frame(width: 34)
                        Circle().fill(Color(red: 1, green: 0.74, blue: 0.18)).frame(width: 34)
                        Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25)).frame(width: 34)
                    }
                    .padding(.leading, 40)
                }
                .frame(height: 82)
                VStack(alignment: .leading, spacing: 30) {
                    ForEach([420, 520, 360], id: \.self) { width in
                        Capsule().fill(Color.black.opacity(0.09)).frame(width: CGFloat(width), height: 26)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 44)
                .padding(.leading, 48)
                Spacer(minLength: 0)
            }
            .background(Color.white)
            .clipShape(window)
            .shadow(color: Color(red: 0.55, green: 0.25, blue: 0.0).opacity(0.35), radius: 18, y: 6)
            .frame(width: body - 2 * windowInset, height: body - ledgeY + 60)
            .offset(x: windowInset, y: ledgeY)
            // Hamster body (clipped at the ledge), then the paws in front of the window.
            figure(.body, scale: scale, ledgeY: ledgeY, cut: ledgeY)
            figure(.frontPaws, scale: scale, ledgeY: ledgeY, cut: ledgeY + 14 * scale)
        }
        .frame(width: body, height: body)
        .clipShape(square)
        .overlay(square.strokeBorder(Color.white.opacity(0.35), lineWidth: 3))
        .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
        .frame(width: Self.canvas, height: Self.canvas)
    }

    private func figure(_ layer: HamsterLayer, scale: CGFloat, ledgeY: CGFloat, cut: CGFloat) -> some View {
        let size = HamsterFigure.designSize
        let params = HamsterParams(look: CGVector(dx: 0, dy: 0.1), earPerk: 0.35, blush: 0.7)
        return HamsterFigure(params: params, layer: layer)
            .frame(width: size.width, height: size.height)
            .scaleEffect(scale, anchor: .top)
            .position(x: Self.bodySize / 2, y: ledgeY - HamsterFigure.ledgeY * scale + size.height / 2)
            .frame(width: Self.bodySize, height: Self.bodySize)
            .mask(alignment: .topLeading) { Rectangle().frame(width: Self.bodySize, height: cut) }
    }
}

enum IconSet {
    /// Writes icon_16x16.png … icon_512x512@2x.png into `dir` (a .iconset folder for `iconutil`).
    @MainActor
    static func write(to dir: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var written: [URL] = []
        for points in [16, 32, 128, 256, 512] {
            for factor in [1, 2] {
                let pixels = CGFloat(points * factor)
                let name = factor == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
                let url = dir.appendingPathComponent(name)
                try writePNG(AppIconView(), size: CGSize(width: AppIconView.canvas, height: AppIconView.canvas),
                             scale: pixels / AppIconView.canvas, to: url)
                written.append(url)
            }
        }
        return written
    }
}
