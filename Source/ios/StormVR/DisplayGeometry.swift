import Foundation

enum VideoPacking: String, CaseIterable, Identifiable {
    case mono = "Desktop / mono"
    case stereo = "SBS do SteamVR"
    case halfSBS = "SBS comprimido (Half-SBS)"

    var id: Self { self }
    var horizontalStretch: CGFloat { self == .halfSBS ? 2 : 1 }

    func sourceRect(_ frame: CGRect, eye: Int) -> CGRect {
        guard self != .mono else { return frame }
        let width = floor(frame.width / 2)
        let x = eye == 0 ? frame.minX : frame.maxX - width
        return CGRect(x: x, y: frame.minY, width: width, height: frame.height)
    }
}

struct ViewerLayout: Equatable {
    // Compress the edges of the display before the lens magnifies them.
    static let lensWarpSource = """
        kernel vec2 lensWarp(vec2 center, float radius, float strength) {
            vec2 p = destCoord() - center;
            vec2 normalized = p / radius;
            return center + p * (1.0 + strength * dot(normalized, normalized));
        }
        """

    var packing: VideoPacking
    var fill: Bool
    var zoom: CGFloat
    var lensDistance: CGFloat
    var verticalOffset: CGFloat
    var distortion: CGFloat

    static func virtualDisplayWidth(for screen: CGSize) -> Int32 {
        let ratio = max(screen.width, screen.height) / max(1, min(screen.width, screen.height))
        return Int32(min(2560, max(1280, (1080 * ratio / 16).rounded() * 16)))
    }

    func eyeRect(in screen: CGRect, eye: Int) -> CGRect {
        let leftWidth = floor(screen.width / 2)
        return CGRect(x: screen.minX + (eye == 0 ? 0 : leftWidth),
                      y: screen.minY, width: eye == 0 ? leftWidth : screen.width - leftWidth,
                      height: screen.height)
    }

    func center(in screen: CGRect, eye: Int, screenWidthMM: CGFloat) -> CGPoint {
        let halfGap = min(0.40, max(0.12, lensDistance / max(screenWidthMM, 1) / 2))
        return CGPoint(x: screen.midX + (eye == 0 ? -halfGap : halfGap) * screen.width,
                       y: screen.midY + verticalOffset * screen.height)
    }

    func scales(source: CGSize, viewport: CGRect, center: CGPoint) -> CGSize {
        let stretch = packing.horizontalStretch
        let horizontal = viewport.width / (source.width * stretch)
        let vertical = viewport.height / source.height
        let scale: CGFloat
        if fill {
            scale = max(horizontal, vertical)
        } else {
            let availableWidth = 2 * min(center.x - viewport.minX, viewport.maxX - center.x)
            let availableHeight = 2 * min(center.y - viewport.minY, viewport.maxY - center.y)
            scale = min(availableWidth / (source.width * stretch), availableHeight / source.height)
        }
        return CGSize(width: scale * zoom * stretch, height: scale * zoom)
    }
}
