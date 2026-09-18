import SwiftUI

public enum HamsterLayer: Sendable {
    /// Everything except the front paws: drawn behind the window edge (the stage clips it at the ledge).
    case body
    /// The two front paws gripping the ledge while peeking: drawn in front of the window edge.
    case frontPaws
}

/// Draws the hamster for one frame. Ignores `params.rise` (the stage applies it); applies everything else.
public struct HamsterFigure: View {
    /// Local canvas size in points. The hamster is horizontally centered at x = designSize.width / 2.
    public static let designSize = CGSize(width: 160, height: 200)
    /// Local y of the ledge (the window's top edge) when rise == 0.
    public static let ledgeY: CGFloat = 150

    public let params: HamsterParams
    public let layer: HamsterLayer

    public init(params: HamsterParams, layer: HamsterLayer) {
        self.params = params
        self.layer = layer
    }

    public var body: some View {
        let rig = Rig(params)
        let layer = layer
        let bleed = Rig.bleed
        // The canvas is larger than the layout frame so stretches, leans and sparkles are never clipped.
        Canvas { context, _ in
            var c = context
            c.translateBy(x: bleed.width, y: bleed.height)
            switch layer {
            case .body: rig.drawBody(in: c)
            case .frontPaws: rig.drawFrontPaws(in: c)
            }
        }
        .frame(width: Self.designSize.width + bleed.width * 2, height: Self.designSize.height + bleed.height * 2)
        .frame(width: Self.designSize.width, height: Self.designSize.height)
        // Only the head/body catches clicks, never the paws or the transparent canvas around them.
        .contentShape(HitShape(rect: rig.hitBounds))
        .allowsHitTesting(layer == .body)
    }

    /// Clickable bounds (head + visible body, excluding front paws) in figure-local coordinates,
    /// ignoring `rise`.
    public static func hitBounds(for params: HamsterParams) -> CGRect {
        Rig(params).hitBounds
    }
}

// Every helper is nested in HamsterFigure, so none of these names can clash with the rest of the module.
extension HamsterFigure {
    // MARK: - Palette

    fileprivate enum Ink {
        static let outline = rgb(0x6B4226)
        static let fur = rgb(0xF6A857)
        static let furShade = rgb(0xE28A3E)
        static let cream = rgb(0xFFF4E3)
        static let creamShade = rgb(0xF2D9BA)
        static let paw = rgb(0xFFE9DC)
        static let pad = rgb(0xFFA9B4)
        static let earInner = rgb(0xFFB3B5)
        static let nose = rgb(0xFF8C9D)
        static let eye = rgb(0x2B1A12)
        static let eyeGlow = rgb(0x7B4E33)
        static let blush = rgb(0xFF8FA3)
        static let blushLine = rgb(0xF2607A)
        static let mouth = rgb(0x8E3A33)
        static let tongue = rgb(0xFF8E9A)
        static let star = rgb(0xFFD54F)

        static func rgb(_ hex: UInt32) -> Color {
            Color(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
        }
    }

    // MARK: - Geometry helpers

    fileprivate enum G {
        static func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat, fallback: CGFloat? = nil) -> CGFloat {
            guard v.isFinite else { return fallback ?? lo }
            return min(max(v, lo), hi)
        }

        /// Hermite ramp from 0 at `e0` to 1 at `e1` (either order).
        static func smoothstep(_ e0: CGFloat, _ e1: CGFloat, _ x: CGFloat) -> CGFloat {
            let t = clamp((x - e0) / (e1 - e0), 0, 1)
            return t * t * (3 - 2 * t)
        }

        static func mix(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

        static func mix(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
            CGPoint(x: mix(a.x, b.x, t), y: mix(a.y, b.y, t))
        }

        /// Point on the quadratic Bézier a → b with control `c`.
        static func bezier(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
            mix(mix(a, c, t), mix(c, b, t), t)
        }

        static func rect(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat) -> CGRect {
            CGRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2)
        }

        static func ellipse(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat) -> Path {
            Path(ellipseIn: rect(c, rx, ry))
        }

        static func rotation(_ degrees: CGFloat, around p: CGPoint) -> CGAffineTransform {
            CGAffineTransform(translationX: p.x, y: p.y)
                .rotated(by: degrees * .pi / 180)
                .translatedBy(x: -p.x, y: -p.y)
        }

        static func rotate(_ c: inout GraphicsContext, _ degrees: CGFloat, around p: CGPoint) {
            c.concatenate(rotation(degrees, around: p))
        }
    }

    /// Hit-test shape: a fixed rectangle in the figure's own coordinates.
    fileprivate struct HitShape: Shape {
        let rect: CGRect
        func path(in _: CGRect) -> Path { Path(rect) }
    }

    // MARK: - Rig

    /// Resolves `HamsterParams` into geometry and paints it.
    ///
    /// Everything is laid out in "out space": the pose with `outAmount == 1`, feet on the ledge. While
    /// peeking the whole figure slides down by `drop` so only the head clears the ledge. The paws are the
    /// exception: while gripping they sit on the ledge in canvas space, then ride along with the body.
    fileprivate struct Rig {
        static let cx: CGFloat = 80
        static let ledge = HamsterFigure.ledgeY
        /// How far the figure sits lower when peeking than when sitting out.
        static let peekDrop: CGFloat = 61
        /// Extra drawing room around the design canvas.
        static let bleed = CGSize(width: 24, height: 40)
        static let headCenter = CGPoint(x: 80, y: 52)
        static let neck = CGPoint(x: 80, y: 86)

        let out: CGFloat
        let drop: CGFloat
        /// 0 = paws gripping the ledge, 1 = paws carried by the body. Holds the grip while the body starts
        /// to rise, then lets go.
        let release: CGFloat
        let sx: CGFloat
        let sy: CGFloat
        let tilt: CGFloat
        let eyeOpen: CGFloat
        let look: CGVector
        let perk: CGFloat
        let mouthOpen: CGFloat
        let armsUp: CGFloat
        let blush: CGFloat
        let sparkle: CGFloat

        init(_ p: HamsterParams) {
            out = G.clamp(p.outAmount, 0, 1)
            drop = (1 - out) * Self.peekDrop
            release = G.smoothstep(0.1, 0.55, out)
            let s = G.clamp(p.squash, 0.5, 1.6, fallback: 1)
            sy = s
            sx = 1 / s.squareRoot()
            tilt = G.clamp(p.tiltDegrees, -45, 45)
            eyeOpen = G.clamp(p.eyeOpenness, 0, 1, fallback: 1)
            let lx = G.clamp(p.look.dx, -1, 1), ly = G.clamp(p.look.dy, -1, 1)
            let len = max(1, (lx * lx + ly * ly).squareRoot())
            look = CGVector(dx: lx / len, dy: ly / len)
            perk = G.clamp(p.earPerk, -1, 1)
            mouthOpen = G.clamp(p.mouthOpen, 0, 1)
            armsUp = G.clamp(p.armsUp, 0, 1)
            blush = G.clamp(p.blush, 0, 1)
            sparkle = G.clamp(p.sparkle, 0, 1)
        }

        /// The part of the tilt carried by the whole body (pivoting on the feet); the head adds the rest.
        var bodyTilt: CGFloat { tilt * 0.4 * out }

        /// Squash/stretch anchored on the ledge, then the body's share of the tilt pivoting on the feet.
        func poseTransform(lean: Bool = true) -> CGAffineTransform {
            CGAffineTransform(translationX: Self.cx, y: Self.ledge)
                .scaledBy(x: sx, y: sy)
                .rotated(by: (lean ? bodyTilt : 0) * .pi / 180)
                .translatedBy(x: -Self.cx, y: -Self.ledge)
        }

        /// Head (ears, cowlick and cheek tufts included) and body as drawn: the head box turns with the neck,
        /// then everything leans and squashes like the drawing. Kept inside the drawn area (canvas + bleed).
        var hitBounds: CGRect {
            let top = min(6.5, 7.5 - 6 * max(0, perk))
            let neck = CGPoint(x: Self.neck.x, y: Self.neck.y + drop)
            let head = CGRect(x: 24, y: top + drop, width: 112, height: 88 - top)
                .applying(G.rotation(tilt - bodyTilt, around: neck))
            let torso = CGRect(x: 26, y: 72 + drop, width: 108, height: 80)
            let bounds = head.union(torso).applying(poseTransform())
            let canvas = CGRect(origin: .zero, size: HamsterFigure.designSize)
            let clipped = bounds.intersection(canvas.insetBy(dx: -Self.bleed.width, dy: -Self.bleed.height))
            return clipped.isNull ? .zero : clipped
        }

        // MARK: Layers

        func drawBody(in context: GraphicsContext) {
            var c = context
            c.concatenate(poseTransform())
            var fig = c
            fig.translateBy(x: 0, y: drop)
            drawTorso(fig)
            // Feet stay planted on the ledge when the body leans.
            var feet = context
            feet.concatenate(poseTransform(lean: false))
            feet.translateBy(x: 0, y: drop)
            drawFeet(feet)
            let arms = [arm(-1), arm(1)]
            for a in arms { drawLimb(c, a) }
            var head = fig
            G.rotate(&head, tilt - bodyTilt, around: Self.neck)
            drawHead(head)
            for a in arms { drawPaw(c, a) }
            drawSparkles(fig)
        }

        /// Only paws that actually hook over the ledge belong in front of the window. A paw that has let go
        /// is fully above the ledge, where the body layer draws the identical paw, so this layer fades it out
        /// by overhang (never leaving a ghost paw floating over the window when the stage lowers the figure).
        func drawFrontPaws(in context: GraphicsContext) {
            var c = context
            c.concatenate(poseTransform())
            let lifted = G.smoothstep(0, 0.2, armsUp)
            for side in [-1, 1] as [CGFloat] {
                let a = arm(side)
                let overhang = a.hand.y + a.size.height / 2 - Self.ledge
                let grip = G.clamp(overhang / 4, 0, 1) * (1 - release)
                faded(c, grip) { c in
                    // Contact shadow on the window face, only while the fingers really curl over the edge.
                    let shadow = G.clamp(overhang / 6, 0, 1) * (1 - lifted) * (1 - G.smoothstep(0, 0.15, out))
                    if shadow > 0.01 {
                        c.fill(G.ellipse(CGPoint(x: a.hand.x + 1, y: Self.ledge + 9.5), 12, 3.5),
                               with: .color(.black.opacity(0.13 * shadow)))
                    }
                    drawPaw(c, a)
                    // The fold where the fingers bend over the edge.
                    var fold = Path()
                    fold.move(to: CGPoint(x: a.hand.x - a.size.width * 0.34, y: Self.ledge + 0.6))
                    fold.addQuadCurve(to: CGPoint(x: a.hand.x + a.size.width * 0.34, y: Self.ledge + 0.6),
                                      control: CGPoint(x: a.hand.x, y: Self.ledge - 1.6))
                    c.stroke(fold, with: .color(Ink.outline.opacity(0.35 * (1 - lifted))),
                             style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                }
            }
        }

        /// Draws `content` at `alpha` as one flattened layer, so stacked outline-then-fill shapes fade as a
        /// whole instead of letting their hidden outlines show through.
        private func faded(_ c: GraphicsContext, _ alpha: CGFloat, _ content: (inout GraphicsContext) -> Void) {
            guard alpha > 0.001 else { return }
            if alpha >= 0.999 {
                var direct = c
                content(&direct)
            } else {
                var layered = c
                layered.opacity = alpha
                layered.drawLayer { layer in
                    layer.opacity = 1
                    content(&layer)
                }
            }
        }

        // MARK: Torso

        private var bodyPath: Path {
            Path { p in
                p.move(to: CGPoint(x: 80, y: 72))
                p.addCurve(to: CGPoint(x: 133, y: 122), control1: CGPoint(x: 114, y: 72), control2: CGPoint(x: 133, y: 98))
                p.addCurve(to: CGPoint(x: 104, y: 151), control1: CGPoint(x: 133, y: 143), control2: CGPoint(x: 122, y: 151))
                p.addLine(to: CGPoint(x: 56, y: 151))
                p.addCurve(to: CGPoint(x: 27, y: 122), control1: CGPoint(x: 38, y: 151), control2: CGPoint(x: 27, y: 143))
                p.addCurve(to: CGPoint(x: 80, y: 72), control1: CGPoint(x: 27, y: 98), control2: CGPoint(x: 46, y: 72))
                p.closeSubpath()
            }
        }

        private func drawTorso(_ c: GraphicsContext) {
            let body = bodyPath
            let belly = G.ellipse(CGPoint(x: 80, y: 121), 33, 26)
            c.stroke(body, with: .color(Ink.outline), lineWidth: 4)
            fillShaded(c, clip: body, layers: [(body, Ink.fur, Ink.furShade), (belly, Ink.cream, Ink.creamShade)])
            // Shadow cast by the head onto the chest.
            var shadow = c
            shadow.clip(to: body)
            shadow.clip(to: headSilhouette.offsetBy(dx: 0, dy: 6))
            shadow.fill(body, with: .color(Ink.furShade))
            shadow.fill(belly, with: .color(Ink.creamShade))
        }

        private func drawFeet(_ c: GraphicsContext) {
            for side in [-1, 1] as [CGFloat] {
                let foot = G.ellipse(CGPoint(x: 80 + side * 17, y: 150), 9.5, 5.5)
                c.stroke(foot, with: .color(Ink.outline), lineWidth: 4)
                c.fill(foot, with: .color(Ink.paw))
                toeMarks(c, center: CGPoint(x: 80 + side * 17, y: 150), halfSpacing: 3.2, bottom: 154.5, length: 3)
            }
        }

        // MARK: Head

        /// Skull, puffy cheek pouches, the fluffy tufts along their lower outer edge and the crown cowlick:
        /// one path, so the outline-then-fill sticker style wraps all of it in a single outline.
        private var headSilhouette: Path {
            Path { p in
                p.addEllipse(in: G.rect(Self.headCenter, 45, 38))
                p.addEllipse(in: G.rect(CGPoint(x: 50, y: 66), 23, 21))
                p.addEllipse(in: G.rect(CGPoint(x: 110, y: 66), 23, 21))
                p.addPath(cheekTufts)
                p.addPath(cowlick)
            }
        }

        /// Two little licks of fur sticking up from the crown.
        private var cowlick: Path {
            Path { p in
                p.move(to: CGPoint(x: 72.5, y: 17))
                p.addQuadCurve(to: CGPoint(x: 77, y: 6.5), control: CGPoint(x: 72.6, y: 10))
                p.addQuadCurve(to: CGPoint(x: 81, y: 14.6), control: CGPoint(x: 78.6, y: 11.8))
                p.addQuadCurve(to: CGPoint(x: 88.4, y: 9), control: CGPoint(x: 83.8, y: 9.6))
                p.addQuadCurve(to: CGPoint(x: 89.5, y: 17.5), control: CGPoint(x: 90.4, y: 13))
                p.closeSubpath()
            }
        }

        /// Pointed fur tufts on the outer, lower edge of each cheek pouch (Syrian hamster fluff).
        private var cheekTufts: Path {
            Path { p in
                for side in [-1, 1] as [CGFloat] {
                    let center = CGPoint(x: 80 + side * 30, y: 66)
                    for (from, to, reach) in [(28, 46, 4), (44, 62, 4.4), (60, 76, 3.2)] as [(CGFloat, CGFloat, CGFloat)] {
                        p.addPath(tuft(on: center, rx: 23, ry: 21, side: side, from: from, to: to, reach: reach))
                    }
                }
            }
        }

        /// A pointed tuft growing out of an ellipse's edge between two angles (degrees; 0 = straight out
        /// sideways, positive = downward), mirrored by `side`. The tip sweeps a little downward.
        private func tuft(on c: CGPoint, rx: CGFloat, ry: CGFloat, side s: CGFloat,
                          from a0: CGFloat, to a1: CGFloat, reach: CGFloat) -> Path {
            func at(_ deg: CGFloat, _ extra: CGFloat) -> CGPoint {
                let t = deg * .pi / 180
                return CGPoint(x: c.x + s * (rx + extra) * cos(t), y: c.y + (ry + extra) * sin(t))
            }
            let mid = (a0 + a1) / 2
            let tip = at(mid + 7, reach)
            // Mirroring flips the winding; walk the mirrored tuft backwards so every tuft winds like the
            // cheek ellipses and the non-zero fill never punches a hole where they overlap.
            let (start, lead, trail, end) = s > 0
                ? (at(a0, -2.5), at(a0 + 2, reach * 0.8), at(mid + 5, reach * 0.3), at(a1, -2.5))
                : (at(a1, -2.5), at(mid + 5, reach * 0.3), at(a0 + 2, reach * 0.8), at(a0, -2.5))
            return Path { p in
                p.move(to: start)
                p.addQuadCurve(to: tip, control: lead)
                p.addQuadCurve(to: end, control: trail)
                p.closeSubpath()
            }
        }

        /// The cream muzzle and cheek fur (clipped to the head).
        private var faceCream: Path {
            Path { p in
                p.addEllipse(in: G.rect(CGPoint(x: 80, y: 74), 15, 12))
                p.addEllipse(in: G.rect(CGPoint(x: 50, y: 76), 21, 15))
                p.addEllipse(in: G.rect(CGPoint(x: 110, y: 76), 21, 15))
                // Blaze running up the forehead.
                p.move(to: CGPoint(x: 74, y: 66))
                p.addCurve(to: CGPoint(x: 80, y: 37), control1: CGPoint(x: 75, y: 50), control2: CGPoint(x: 76.4, y: 37))
                p.addCurve(to: CGPoint(x: 86, y: 66), control1: CGPoint(x: 83.6, y: 37), control2: CGPoint(x: 85, y: 50))
                p.closeSubpath()
            }
        }

        private func drawHead(_ c: GraphicsContext) {
            // A tiny head-turn cheat: the face slides toward where the hamster looks and the ears the other
            // way, so the gaze reads at a glance even though the pupils only move ~3pt.
            let turn = CGVector(dx: look.dx * 2.4, dy: look.dy * 1.5)
            var ears = c
            ears.translateBy(x: -turn.dx * 0.4, y: 0)
            for side in [-1, 1] as [CGFloat] { drawEar(ears, side: side) }
            let head = headSilhouette
            c.stroke(head, with: .color(Ink.outline), style: StrokeStyle(lineWidth: 4, lineJoin: .round))
            let cream = faceCream.offsetBy(dx: turn.dx * 0.7, dy: turn.dy * 0.7)
            fillShaded(c, clip: head, layers: [(head, Ink.fur, Ink.furShade), (cream, Ink.cream, Ink.creamShade),
                                               (cheekTufts, Ink.cream, Ink.creamShade)])
            // Sticker gloss on the crown, left of the cowlick.
            c.fill(G.ellipse(CGPoint(x: 62, y: 25), 9, 4.5).applying(G.rotation(-18, around: CGPoint(x: 62, y: 25))),
                   with: .color(.white.opacity(0.45)))
            var face = c
            face.translateBy(x: turn.dx, y: turn.dy)
            drawCheeks(face)
            drawWhiskers(face)
            for side in [-1, 1] as [CGFloat] {
                drawEye(face, center: CGPoint(x: 80 + side * 20, y: 53.5), side: side)
            }
            drawMouth(face)
            drawNose(face)
        }

        private func drawEar(_ c: GraphicsContext, side: CGFloat) {
            let up = max(0, perk), droop = max(0, -perk)
            var e = c
            e.translateBy(x: 80 + side * 27, y: 32 - 3 * up + 4 * droop)
            e.rotate(by: .degrees(side * (7 * up - 40 * droop)))
            e.scaleBy(x: 1 + 0.05 * up, y: 1 + 0.12 * up - 0.12 * droop)
            let outer = G.ellipse(CGPoint(x: side * 5, y: -12), 12.5, 12.5)
            e.stroke(outer, with: .color(Ink.outline), lineWidth: 4)
            e.fill(outer, with: .color(Ink.fur))
            e.fill(G.ellipse(CGPoint(x: side * 4, y: -10.5), 7, 7), with: .color(Ink.earInner))
        }

        private func drawCheeks(_ c: GraphicsContext) {
            guard blush > 0.01 else { return }
            for side in [-1, 1] as [CGFloat] {
                let center = CGPoint(x: 80 + side * 33, y: 68)
                c.fill(G.ellipse(center, 8.5, 5.5), with: .color(Ink.blush.opacity(0.95 * pow(blush, 0.6))))
                let hatch = G.clamp((blush - 0.55) / 0.35, 0, 1)
                if hatch > 0 {
                    var lines = Path()
                    for i in -1...1 {
                        let x = center.x + CGFloat(i) * 3.4
                        lines.move(to: CGPoint(x: x + 1.2, y: center.y - 2.2))
                        lines.addLine(to: CGPoint(x: x - 1.2, y: center.y + 2.2))
                    }
                    c.stroke(lines, with: .color(Ink.blushLine.opacity(hatch)),
                             style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                }
            }
        }

        private func drawWhiskers(_ c: GraphicsContext) {
            var w = Path()
            for side in [-1, 1] as [CGFloat] {
                for (y0, y1) in [(71, 68), (75.5, 77)] as [(CGFloat, CGFloat)] {
                    w.move(to: CGPoint(x: 80 + side * 47, y: y0))
                    w.addLine(to: CGPoint(x: 80 + side * 60, y: y1))
                }
            }
            c.stroke(w, with: .color(Ink.outline), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        }

        /// Big glossy eye. Half-closed, the upper lid sags a little and grows an outer lash (drowsy, never
        /// smug). Below 0.15 the eye closes into a relaxed "‿" lid, or a happy "^" squint when the hamster
        /// is grinning or blushing hard. The two states never overlap, so the switch cannot read as a frown.
        private func drawEye(_ c: GraphicsContext, center: CGPoint, side: CGFloat) {
            let rx: CGFloat = 9.3, ry: CGFloat = 10.8
            let socket = CGPoint(x: center.x + look.dx * 1.4, y: center.y + look.dy * 1.2)
            // 0 = calm closed lid "‿", 1 = happy squint "^".
            let happy = max(mouthOpen, G.smoothstep(0.4, 0.8, blush))
            // The calm lid closes right where the slit's lid line is, so the two may overlap briefly; the
            // happy arc only fades in once the open eye is gone, so they never mix into a frown.
            let openAlpha = G.smoothstep(0.15, 0.17, eyeOpen)
            let closedAlpha = 1 - G.smoothstep(G.mix(0.14, 0.12, happy), G.mix(0.18, 0.15, happy), eyeOpen)
            faded(c, openAlpha) { e in
                let iris = G.ellipse(socket, rx, ry)
                let shut = 1 - eyeOpen
                // Upper lid edge: arched ("⌒") when barely lowered, sagging in the middle when heavy, and always
                // a touch lower at the outer corner (sleepy puppy, never a frown).
                let heavy = G.smoothstep(0.6, 0.35, eyeOpen)
                let arch = 3 - 5 * heavy
                let droop = 2 * G.smoothstep(0.9, 0.45, eyeOpen)
                let lidMid = socket.y - ry + shut * 2 * ry
                let reach = rx + 2
                let outer = CGPoint(x: socket.x + side * reach, y: lidMid + arch + droop)
                let inner = CGPoint(x: socket.x - side * reach, y: lidMid + arch - droop * 0.4)
                let apex = CGPoint(x: socket.x, y: lidMid - arch)
                var lidEdge = Path()
                lidEdge.move(to: inner)
                lidEdge.addQuadCurve(to: outer, control: apex)
                let lidded = eyeOpen < 0.97
                var open = e
                if lidded {
                    var below = lidEdge
                    below.addLine(to: CGPoint(x: outer.x, y: socket.y + ry + 2))
                    below.addLine(to: CGPoint(x: inner.x, y: socket.y + ry + 2))
                    below.closeSubpath()
                    open.clip(to: below)
                }
                open.fill(iris, with: .color(Ink.eye))
                open.clip(to: iris)
                // Glow and highlights ride down with the lid so a drowsy eye stays dark and glossy.
                let pupil = CGPoint(x: socket.x + look.dx * 1.6, y: socket.y + look.dy * 1.6 + shut * ry * 0.85)
                let shine = 1 - 0.35 * shut
                open.fill(G.ellipse(CGPoint(x: pupil.x, y: pupil.y + 7), rx * 0.8, ry * 0.5), with: .color(Ink.eyeGlow))
                open.fill(G.ellipse(CGPoint(x: pupil.x - 2.6, y: pupil.y - 3.9 * shine), 3.7 * shine, 4.1 * shine),
                          with: .color(.white))
                open.fill(G.ellipse(CGPoint(x: pupil.x + 3.4, y: pupil.y + 3.6 * shine), 1.7, 1.7), with: .color(.white))
                guard lidded else { return }
                var line = e
                line.clip(to: G.ellipse(socket, rx + 0.9, ry + 0.9))
                line.stroke(lidEdge, with: .color(Ink.outline), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                // A little lash flicking out of the outer corner of a drowsy lid.
                let lash = G.smoothstep(0.62, 0.5, eyeOpen)
                guard lash > 0.01 else { return }
                // Where the lid line leaves the eye on the outer side.
                let rim = CGSize(width: rx + 0.9, height: ry + 0.9)
                var corner = outer
                for step in 0...24 {
                    corner = G.bezier(outer, apex, inner, CGFloat(step) / 24)
                    let nx = (corner.x - socket.x) / rim.width, ny = (corner.y - socket.y) / rim.height
                    if nx * nx + ny * ny <= 1 { break }
                }
                var tick = Path()
                tick.move(to: CGPoint(x: corner.x - side * 0.6, y: corner.y))
                tick.addQuadCurve(to: CGPoint(x: corner.x + side * 3.6, y: corner.y + 1.4),
                                  control: CGPoint(x: corner.x + side * 2.4, y: corner.y - 0.2))
                e.stroke(tick, with: .color(Ink.outline.opacity(lash)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            }
            faded(c, closedAlpha) { a in
                let x = socket.x, y = socket.y
                let endY = G.mix(y + 4, y + 3, happy)
                let bend = G.mix(y + 11, y - 8, happy)
                var arc = Path()
                arc.move(to: CGPoint(x: x - 7.5, y: endY))
                arc.addQuadCurve(to: CGPoint(x: x + 7.5, y: endY), control: CGPoint(x: x, y: bend))
                a.stroke(arc, with: .color(Ink.eye), style: StrokeStyle(lineWidth: 2.8, lineCap: .round))
                let lash = 1 - happy
                if lash > 0.01 {
                    var tick = Path()
                    tick.move(to: CGPoint(x: x + side * 7, y: endY + 0.6))
                    tick.addQuadCurve(to: CGPoint(x: x + side * 10.6, y: endY - 1.2),
                                      control: CGPoint(x: x + side * 9.4, y: endY + 0.6))
                    a.stroke(tick, with: .color(Ink.eye.opacity(lash)), style: StrokeStyle(lineWidth: 1.9, lineCap: .round))
                }
            }
        }

        private func drawNose(_ c: GraphicsContext) {
            let nose = Path { p in
                p.move(to: CGPoint(x: 76, y: 63.6))
                p.addQuadCurve(to: CGPoint(x: 84, y: 63.6), control: CGPoint(x: 80, y: 62))
                p.addQuadCurve(to: CGPoint(x: 80, y: 67.6), control: CGPoint(x: 83.6, y: 66.4))
                p.addQuadCurve(to: CGPoint(x: 76, y: 63.6), control: CGPoint(x: 76.4, y: 66.4))
                p.closeSubpath()
            }
            c.stroke(nose, with: .color(Ink.outline), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
            c.fill(nose, with: .color(Ink.nose))
            c.fill(G.ellipse(CGPoint(x: 78.6, y: 64), 1.1, 0.8), with: .color(.white.opacity(0.9)))
        }

        private func drawMouth(_ c: GraphicsContext) {
            let m = mouthOpen
            let x: CGFloat = 80, y: CGFloat = 70.5
            let w = 6 + 1.8 * m
            let lobe: CGFloat = 3.6
            var omega = Path()
            omega.move(to: CGPoint(x: x - w, y: y - 1.2))
            omega.addCurve(to: CGPoint(x: x, y: y - 0.2),
                           control1: CGPoint(x: x - w + 0.2, y: y + lobe), control2: CGPoint(x: x - 0.2, y: y + lobe))
            omega.addCurve(to: CGPoint(x: x + w, y: y - 1.2),
                           control1: CGPoint(x: x + 0.2, y: y + lobe), control2: CGPoint(x: x + w - 0.2, y: y + lobe))
            if m > 0.04 {
                let d = 11 * m
                var open = omega
                open.addCurve(to: CGPoint(x: x - w, y: y - 1.2),
                              control1: CGPoint(x: x + w + 0.8, y: y + 2 + d * 1.3),
                              control2: CGPoint(x: x - w - 0.8, y: y + 2 + d * 1.3))
                open.closeSubpath()
                c.fill(open, with: .color(Ink.mouth))
                var tongue = c
                tongue.clip(to: open)
                tongue.fill(G.ellipse(CGPoint(x: x, y: y + 3 + d * 0.95), w * 0.62, 1.5 + d * 0.4), with: .color(Ink.tongue))
                // Two little buck teeth hanging from the middle of the "ω".
                let toothLength = 2.8 + min(2, d * 0.3)
                tongue.fill(Path(roundedRect: CGRect(x: x - 2.8, y: y - 1, width: 5.6, height: toothLength), cornerRadius: 1.2),
                            with: .color(.white))
                var gap = Path()
                gap.move(to: CGPoint(x: x, y: y))
                gap.addLine(to: CGPoint(x: x, y: y - 1 + toothLength))
                tongue.stroke(gap, with: .color(Ink.outline.opacity(0.45)), lineWidth: 0.8)
                c.stroke(open, with: .color(Ink.outline), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
            var philtrum = Path()
            philtrum.move(to: CGPoint(x: x, y: 66.5))
            philtrum.addLine(to: CGPoint(x: x, y: y - 0.2))
            c.stroke(philtrum, with: .color(Ink.outline), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            c.stroke(omega, with: .color(Ink.outline), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }

        // MARK: Arms & paws

        private struct Arm {
            var shoulder: CGPoint
            var hand: CGPoint
            var angle: CGFloat      // degrees clockwise; 0 = fingers pointing down
            var size: CGSize
            var palm: CGFloat       // 0...1 visibility of the paw pads (palm facing the viewer)
        }

        /// Arm geometry in canvas space. `side` is -1 for the viewer's left paw, +1 for the right one.
        ///
        /// The shoulder always rides on the torso (out space + drop), so the limb reaches out and up from the
        /// body and never dangles below it. Only the hand blends between the ledge grip and the body pose.
        private func arm(_ side: CGFloat) -> Arm {
            func mirror(_ p: CGPoint) -> CGPoint { CGPoint(x: Self.cx - side * (p.x - Self.cx), y: p.y) }
            func onBody(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: p.y + drop) }
            let a = armsUp
            // Left arm key points. Out space: paw at the chest under the cheek, raised high beside the ear.
            let rest = CGPoint(x: 69, y: 101), raised = CGPoint(x: 18, y: 50)
            // The raised paw swings out along an arc, so it passes beside the cheek instead of over the face.
            let carried = onBody(G.bezier(rest, CGPoint(x: 12, y: 100), raised, a))
            // Canvas space: paw hooked over the ledge; lifting, it rises beside the cheek.
            let grip = CGPoint(x: 52, y: 149)
            let lifted = G.bezier(grip, CGPoint(x: 27, y: 146), onBody(raised), a)
            let hand = G.mix(lifted, carried, release)
            // Tucked under the cheek at rest, on the body's flank when raised.
            let shoulder = onBody(G.mix(CGPoint(x: 51, y: 92), CGPoint(x: 34, y: 95), a))
            let angle = G.mix(165 * a, G.mix(-15, 150, a), release)
            let w = G.mix(G.mix(23, 20, a), G.mix(17, 18, a), release)
            let h = G.mix(G.mix(18, 17, a), G.mix(14, 16, a), release)
            return Arm(shoulder: mirror(shoulder), hand: mirror(hand), angle: angle * -side,
                       size: CGSize(width: w, height: h), palm: G.smoothstep(0.45, 0.9, a))
        }

        /// The furry arm, drawn behind the head so the puffy cheeks overlap it. It is outlined only where it
        /// stands out against the background: over the torso it is fur on fur, so arm and body merge into one
        /// sticker shape (no ring or seam where the limb meets the torso).
        private func drawLimb(_ c: GraphicsContext, _ a: Arm) {
            var limb = Path()
            limb.move(to: a.shoulder)
            limb.addLine(to: a.hand)
            var outside = c
            outside.clip(to: bodyPath.offsetBy(dx: 0, dy: drop), options: .inverse)
            outside.stroke(limb, with: .color(Ink.outline), style: StrokeStyle(lineWidth: 16, lineCap: .round))
            c.stroke(limb, with: .color(Ink.fur), style: StrokeStyle(lineWidth: 12, lineCap: .round))
        }

        private func drawPaw(_ c: GraphicsContext, _ a: Arm) {
            var h = c
            h.translateBy(x: a.hand.x, y: a.hand.y)
            h.rotate(by: .degrees(a.angle))
            let w = a.size.width, hh = a.size.height / 2
            // Back of the paw plus three fingertip bumps along the finger end (+y).
            let tip = w * 0.19
            let paw = Path { p in
                p.addEllipse(in: CGRect(x: -w / 2, y: -hh, width: w, height: hh * 2 - 2.5))
                for i in -1...1 {
                    p.addEllipse(in: G.rect(CGPoint(x: CGFloat(i) * w * 0.27, y: hh - tip + 0.4 - abs(CGFloat(i)) * 1.2), tip, tip))
                }
            }
            h.stroke(paw, with: .color(Ink.outline), lineWidth: 4)
            h.fill(paw, with: .color(Ink.paw))
            if a.palm > 0 {
                var pads = h
                pads.opacity = a.palm
                pads.fill(G.ellipse(CGPoint(x: 0, y: -hh * 0.2), a.size.width * 0.2, hh * 0.36), with: .color(Ink.pad))
                for i in -1...1 {
                    pads.fill(G.ellipse(CGPoint(x: CGFloat(i) * a.size.width * 0.23, y: hh * 0.42 - abs(CGFloat(i)) * 1.2), 1.7, 1.7),
                              with: .color(Ink.pad))
                }
            }
            toeMarks(h, center: .zero, halfSpacing: w * 0.135, bottom: hh - 1.6, length: 3)
        }

        private func toeMarks(_ c: GraphicsContext, center: CGPoint, halfSpacing: CGFloat, bottom: CGFloat, length: CGFloat) {
            var toes = Path()
            for s in [-1, 1] as [CGFloat] {
                toes.move(to: CGPoint(x: center.x + s * halfSpacing, y: bottom))
                toes.addLine(to: CGPoint(x: center.x + s * halfSpacing, y: bottom - length))
            }
            c.stroke(toes, with: .color(Ink.outline), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        }

        // MARK: Sparkles

        /// Twinkling stars and dots around the head. They pop in one after another as `sparkle` rises, so the
        /// jump reads as a little burst.
        private func drawSparkles(_ c: GraphicsContext) {
            guard sparkle > 0.01 else { return }
            // Placed clear of the raised paws (≈ x 9...27 and 133...151, y 41...59 in out space).
            let stars: [(CGPoint, CGFloat)] = [
                (CGPoint(x: 14, y: 24), 8.5), (CGPoint(x: 146, y: 28), 6.5), (CGPoint(x: 131, y: 5), 4),
                (CGPoint(x: 150, y: 82), 4), (CGPoint(x: 9, y: 84), 4.5),
            ]
            let dots = [CGPoint(x: 30, y: 6), CGPoint(x: 156, y: 56)]
            for (i, (center, r)) in stars.enumerated() {
                let t = G.smoothstep(CGFloat(i) * 0.1, CGFloat(i) * 0.1 + 0.5, sparkle)
                guard t > 0.02 else { continue }
                faded(c, min(1, t * 3)) { s in
                    let star = starPath(center, r * t)
                    s.stroke(star, with: .color(Ink.outline), style: StrokeStyle(lineWidth: 2.6, lineJoin: .round))
                    s.fill(star, with: .color(Ink.star))
                }
            }
            for (i, center) in dots.enumerated() {
                let t = G.smoothstep(0.15 + CGFloat(i) * 0.2, 0.55 + CGFloat(i) * 0.2, sparkle)
                guard t > 0.02 else { continue }
                faded(c, min(1, t * 3)) { s in
                    let dot = G.ellipse(center, 2 * t, 2 * t)
                    s.stroke(dot, with: .color(Ink.outline), lineWidth: 2.4)
                    s.fill(dot, with: .color(Ink.star))
                }
            }
        }

        private func starPath(_ c: CGPoint, _ r: CGFloat) -> Path {
            let k = r * 0.2
            return Path { p in
                p.move(to: CGPoint(x: c.x, y: c.y - r))
                p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + k, y: c.y - k))
                p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + k, y: c.y + k))
                p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - k, y: c.y + k))
                p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - k, y: c.y - k))
                p.closeSubpath()
            }
        }

        // MARK: Shading helper

        /// Flat sticker shading: each layer is filled in its shade colour, then re-filled in its base colour
        /// inside the silhouette nudged up-left, leaving a shade crescent along the lower-right rim.
        private func fillShaded(_ c: GraphicsContext, clip: Path, layers: [(Path, Color, Color)]) {
            var shade = c
            shade.clip(to: clip)
            for (path, _, dark) in layers { shade.fill(path, with: .color(dark)) }
            var lit = shade
            lit.clip(to: clip.offsetBy(dx: -2.5, dy: -3.5))
            for (path, base, _) in layers { lit.fill(path, with: .color(base)) }
        }
    }
}
