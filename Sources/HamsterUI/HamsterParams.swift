import CoreGraphics

/// Everything needed to draw one frame of the hamster. `HamsterAnimator` produces it every frame and
/// `HamsterFigure` renders it. Distances are points in the figure's design space.
public struct HamsterParams: Equatable, Sendable {
    /// Vertical offset of the whole hamster from its resting position, positive = up. Applied by the
    /// stage, not the figure. About -130 hides the hamster completely behind the ledge.
    public var rise: CGFloat
    /// 0 = peeking (head and front paws above the ledge, body hidden behind the window);
    /// 1 = fully out, sitting on the ledge with the whole body visible. Values between blend the two.
    public var outAmount: CGFloat
    /// 1 = neutral; < 1 squashed (wider and shorter); > 1 stretched. Anchored at the ledge.
    public var squash: CGFloat
    /// Head/body tilt in degrees, positive = clockwise.
    public var tiltDegrees: CGFloat
    /// 0 = eyes closed, 1 = fully open.
    public var eyeOpenness: CGFloat
    /// Pupil offset direction, each component -1...1 (x right, y down).
    public var look: CGVector
    /// -1 droopy ... 0 neutral ... 1 perked up.
    public var earPerk: CGFloat
    /// 0 = closed "ω" mouth, 1 = wide open happy mouth.
    public var mouthOpen: CGFloat
    /// 0 = paws resting on the ledge (peeking) or at the sides (out), 1 = both arms raised high.
    public var armsUp: CGFloat
    /// Cheek blush intensity 0...1.
    public var blush: CGFloat
    /// Excitement effects (sparkles, motion marks) 0...1.
    public var sparkle: CGFloat

    public init(
        rise: CGFloat = 0,
        outAmount: CGFloat = 0,
        squash: CGFloat = 1,
        tiltDegrees: CGFloat = 0,
        eyeOpenness: CGFloat = 1,
        look: CGVector = .zero,
        earPerk: CGFloat = 0,
        mouthOpen: CGFloat = 0,
        armsUp: CGFloat = 0,
        blush: CGFloat = 0.4,
        sparkle: CGFloat = 0
    ) {
        self.rise = rise
        self.outAmount = outAmount
        self.squash = squash
        self.tiltDegrees = tiltDegrees
        self.eyeOpenness = eyeOpenness
        self.look = look
        self.earPerk = earPerk
        self.mouthOpen = mouthOpen
        self.armsUp = armsUp
        self.blush = blush
        self.sparkle = sparkle
    }

    /// Resting peek pose.
    public static let peek = HamsterParams()
    /// Resting pose sitting on the ledge.
    public static let sitting = HamsterParams(outAmount: 1)

    /// Linear interpolation of every field (used for cross-fading between animation modes).
    public static func lerp(_ a: HamsterParams, _ b: HamsterParams, _ t: CGFloat) -> HamsterParams {
        func mix(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * t }
        return HamsterParams(
            rise: mix(a.rise, b.rise),
            outAmount: mix(a.outAmount, b.outAmount),
            squash: mix(a.squash, b.squash),
            tiltDegrees: mix(a.tiltDegrees, b.tiltDegrees),
            eyeOpenness: mix(a.eyeOpenness, b.eyeOpenness),
            look: CGVector(dx: mix(a.look.dx, b.look.dx), dy: mix(a.look.dy, b.look.dy)),
            earPerk: mix(a.earPerk, b.earPerk),
            mouthOpen: mix(a.mouthOpen, b.mouthOpen),
            armsUp: mix(a.armsUp, b.armsUp),
            blush: mix(a.blush, b.blush),
            sparkle: mix(a.sparkle, b.sparkle)
        )
    }
}
