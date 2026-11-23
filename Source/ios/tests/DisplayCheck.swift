import CoreImage
import Foundation

@main
struct DisplayCheck {
    static func main() {
        let screen = CGRect(x: 0, y: 0, width: 2532, height: 1170)
        let widthMM = screen.width / 460 * 25.4
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        var layout = ViewerLayout(packing: .mono, fill: true, zoom: 1,
                                  lensDistance: 62, verticalOffset: 0, distortion: 0.10)
        let left = layout.eyeRect(in: screen, eye: 0)
        let right = layout.eyeRect(in: screen, eye: 1)
        let leftCenter = layout.center(in: screen, eye: 0, screenWidthMM: widthMM)
        let rightCenter = layout.center(in: screen, eye: 1, screenWidthMM: widthMM)
        precondition(left.maxX == right.minX && right.maxX == screen.maxX)
        precondition(left.contains(leftCenter) && right.contains(rightCenter))
        precondition(abs((rightCenter.x - leftCenter.x) * widthMM / screen.width - 62) < 0.001)

        let cover = layout.scales(source: frame.size, viewport: left, center: leftCenter)
        precondition(cover.width == cover.height && frame.height * cover.height == screen.height)
        layout.fill = false
        let fit = layout.scales(source: frame.size, viewport: left, center: leftCenter)
        precondition(fit.width == fit.height && fit.width < cover.width)

        let odd = CGRect(x: 2, y: 0, width: 1921, height: 1080)
        let first = VideoPacking.stereo.sourceRect(odd, eye: 0)
        let second = VideoPacking.stereo.sourceRect(odd, eye: 1)
        precondition(first.width == second.width && first.maxX + 1 == second.minX)
        layout.packing = .halfSBS
        let anamorphic = layout.scales(source: first.size, viewport: left, center: leftCenter)
        precondition(anamorphic.width == 2 * anamorphic.height)
        precondition(ViewerLayout.virtualDisplayWidth(for: CGSize(width: 1170, height: 2532)) == 2336)
        precondition(CIWarpKernel(source: ViewerLayout.lensWarpSource) != nil)
        print("StormVR eye layout, G10 lens warp and virtual display resolution OK")
    }
}
