import CoreGraphics
import Foundation

/// A plain snapshot of one on-screen window, as read from CGWindowListCopyWindowInfo.
public struct WindowInfo: Equatable, Sendable {
    public var windowID: UInt32
    public var ownerPID: Int32
    public var ownerName: String
    public var layer: Int
    public var alpha: Double
    /// Quartz global coordinates: origin at the top-left of the primary display, y grows downward.
    public var bounds: CGRect

    public init(windowID: UInt32, ownerPID: Int32, ownerName: String, layer: Int, alpha: Double, bounds: CGRect) {
        self.windowID = windowID
        self.ownerPID = ownerPID
        self.ownerName = ownerName
        self.layer = layer
        self.alpha = alpha
        self.bounds = bounds
    }
}

public enum WindowSelector {
    public static let minimumSize = CGSize(width: 160, height: 100)
    public static let ignoredOwners: Set<String> = [
        "Window Server", "Dock", "Control Center", "Notification Center", "SystemUIServer",
        "Spotlight", "WindowManager", "Screenshot", "loginwindow",
    ]

    /// Normal (layer 0), visible, reasonably sized window not owned by us or a system UI process.
    /// Windows with non-finite bounds are never eligible.
    public static func isEligible(_ window: WindowInfo, ownPID: Int32) -> Bool {
        let bounds = window.bounds
        return window.layer == 0
            && window.alpha > 0.05
            && bounds.origin.x.isFinite && bounds.origin.y.isFinite
            && bounds.width.isFinite && bounds.height.isFinite
            && bounds.width >= minimumSize.width
            && bounds.height >= minimumSize.height
            && window.ownerPID != ownPID
            && !ignoredOwners.contains(window.ownerName)
    }

    /// `windows` is front-to-back. Returns the frontmost eligible window of `frontmostPID`; if that app
    /// has none, the frontmost eligible window of any app; nil if there is none.
    /// When we are the frontmost app ourselves there is no preference: our own windows are never eligible,
    /// so the search falls through to the frontmost eligible window of any other app.
    public static func pickTarget(windows: [WindowInfo], frontmostPID: Int32?, ownPID: Int32) -> WindowInfo? {
        let eligible = windows.lazy.filter { isEligible($0, ownPID: ownPID) }
        if let preferredPID = frontmostPID,
           let window = eligible.first(where: { $0.ownerPID == preferredPID }) {
            return window
        }
        return eligible.first
    }
}

public enum ScreenGeometry {
    /// Quartz (top-left origin) → Cocoa (bottom-left origin): (x, h - y - height, width, height).
    public static func cocoaRect(fromQuartz rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        flipped(rect, primaryScreenHeight: primaryScreenHeight)
    }

    /// Cocoa (bottom-left origin) → Quartz (top-left origin); the exact inverse of `cocoaRect`.
    public static func quartzRect(fromCocoa rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        flipped(rect, primaryScreenHeight: primaryScreenHeight)
    }

    /// Index of the screen with the largest intersection with `rect`; if none intersect, the screen whose
    /// center is nearest to the rect's center; nil for an empty list. Ties go to the lowest index.
    public static func bestScreenIndex(for rect: CGRect, screenFrames: [CGRect]) -> Int? {
        guard !screenFrames.isEmpty else { return nil }

        var bestIndex: Int?
        var bestArea: CGFloat = 0
        for (index, frame) in screenFrames.enumerated() {
            let overlap = rect.intersection(frame)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area > bestArea {
                bestArea = area
                bestIndex = index
            }
        }
        if let bestIndex { return bestIndex }

        let center = CGPoint(x: rect.midX, y: rect.midY)
        var nearestIndex = 0
        var nearestDistance = CGFloat.infinity
        for (index, frame) in screenFrames.enumerated() {
            let dx = frame.midX - center.x
            let dy = frame.midY - center.y
            let distance = dx * dx + dy * dy
            if distance < nearestDistance {
                nearestDistance = distance
                nearestIndex = index
            }
        }
        return nearestIndex
    }

    /// Flipping y about the primary screen's height is its own inverse.
    private static func flipped(_ rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
