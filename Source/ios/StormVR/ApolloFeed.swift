import CoreImage
import CoreVideo
import MetalKit
import SwiftUI

enum HostVideoSource: String, CaseIterable, Identifiable {
    case apollo = "Apollo / Sunshine"
    case capture = "Captura StormVR (8089)"
    var id: Self { self }
}

final class HeadsetFrames: @unchecked Sendable {
    private let lock = NSLock()
    private var image: CIImage?
    private var generation: UInt64 = 0

    func replace(with next: CIImage?) {
        lock.lock()
        image = next
        generation &+= 1
        lock.unlock()
    }

    func latest() -> (CIImage?, UInt64) {
        lock.lock()
        defer { lock.unlock() }
        return (image, generation)
    }
}

@MainActor
final class ApolloFeed: ObservableObject {
    @Published private(set) var status = "Conecte ao Apollo para escolher o que transmitir."
    @Published private(set) var applications: [SVRApolloApplication] = []
    @Published var selectedApp = ""
    private(set) var address = ""
    let frames = HeadsetFrames()
    private let client = SVRApolloClient()

    static func isVirtualDisplay(_ app: SVRApolloApplication) -> Bool {
        app.title.caseInsensitiveCompare("Virtual Display") == .orderedSame ||
            app.title.caseInsensitiveCompare("StormVR SteamVR") == .orderedSame
    }

    func prepare(address: String) {
        self.address = address
        applications = []
        selectedApp = ""
        frames.replace(with: nil)
        status = "Consultando Apollo…"
        client.prepare(host: address, status: { [weak self] in self?.status = $0 }, applications: { [weak self] apps in
            guard let self else { return }
            self.applications = apps
            self.selectedApp = apps.first(where: { $0.title.caseInsensitiveCompare("StormVR SteamVR") == .orderedSame })?.identifier
                ?? apps.first(where: Self.isVirtualDisplay)?.identifier
                ?? apps.first(where: { $0.title.caseInsensitiveCompare("Desktop") == .orderedSame })?.identifier
                ?? apps.first?.identifier ?? ""
        })
    }

    func isReady(for target: String) -> Bool {
        address == target && applications.contains { $0.identifier == selectedApp }
    }

    func start() {
        frames.replace(with: nil)
        status = "Iniciando transmissão Apollo…"
        let frames = frames
        let screen = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.screen
        let bounds = screen?.nativeBounds ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let isVirtual = applications.contains { $0.identifier == selectedApp && Self.isVirtualDisplay($0) }
        let width = isVirtual ? ViewerLayout.virtualDisplayWidth(for: bounds.size) : 1920
        client.start(application: selectedApp, width: width,
                     frame: { frames.replace(with: CIImage(cvPixelBuffer: $0)) },
                     status: { [weak self] in self?.status = $0 })
    }

    func stop() {
        client.stop()
        frames.replace(with: nil)
    }
}

struct HeadsetVideoSurface: UIViewRepresentable {
    let frames: HeadsetFrames
    let layout: ViewerLayout
    var showGrid = false

    func makeCoordinator() -> Presenter { Presenter(frames: frames, layout: layout) }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        view.backgroundColor = .black
        view.isUserInteractionEnabled = false
        view.preferredFramesPerSecond = 60
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.frames = frames
        context.coordinator.layout = layout
        context.coordinator.showGrid = showGrid
    }

    final class Presenter: NSObject, MTKViewDelegate {
        let device: MTLDevice?
        var frames: HeadsetFrames
        var layout: ViewerLayout
        var showGrid = false
        private let queue: MTLCommandQueue?
        private let context: CIContext?
        private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        private var lastFrame: UInt64?
        private var lastSource: ObjectIdentifier?
        private var lastSize: CGSize = .zero
        private var lastLayout: ViewerLayout?
        private var lastGrid = false

        private static let lensWarp = CIWarpKernel(source: ViewerLayout.lensWarpSource)

        private static let grid: CIImage? = {
            let size = CGSize(width: 768, height: 768)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let image = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
                let context = renderer.cgContext
                context.setFillColor(UIColor(white: 0.08, alpha: 1).cgColor)
                context.fill(CGRect(origin: .zero, size: size))
                context.setStrokeColor(UIColor(white: 0.50, alpha: 1).cgColor)
                context.setLineWidth(2)
                for i in 0...12 {
                    let p = CGFloat(i) * 64
                    context.move(to: CGPoint(x: p, y: 0))
                    context.addLine(to: CGPoint(x: p, y: size.height))
                    context.move(to: CGPoint(x: 0, y: p))
                    context.addLine(to: CGPoint(x: size.width, y: p))
                }
                context.strokePath()
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                context.setStrokeColor(UIColor.white.cgColor)
                context.setLineWidth(5)
                context.strokeEllipse(in: CGRect(x: center.x - 96, y: center.y - 96, width: 192, height: 192))
                context.move(to: CGPoint(x: center.x - 24, y: center.y))
                context.addLine(to: CGPoint(x: center.x + 24, y: center.y))
                context.move(to: CGPoint(x: center.x, y: center.y - 24))
                context.addLine(to: CGPoint(x: center.x, y: center.y + 24))
                context.strokePath()
            }
            return image.cgImage.map { CIImage(cgImage: $0) }
        }()

        init(frames: HeadsetFrames, layout: ViewerLayout) {
            let device = MTLCreateSystemDefaultDevice()
            self.frames = frames
            self.layout = layout
            self.device = device
            queue = device?.makeCommandQueue()
            context = device.map { CIContext(mtlDevice: $0, options: [.cacheIntermediates: false]) }
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { lastFrame = nil }

        func draw(in view: MTKView) {
            let (frame, generation) = frames.latest()
            let source = ObjectIdentifier(frames)
            let extent = CGRect(origin: .zero, size: view.drawableSize)
            guard extent.width >= 2, extent.height > 0,
                  (!showGrid && (lastFrame != generation || lastSource != source)) || lastSize != extent.size ||
                      lastLayout != layout || lastGrid != showGrid,
                  let context, let drawable = view.currentDrawable, let commands = queue?.makeCommandBuffer() else { return }

            var output = CIImage(color: .black).cropped(to: extent)
            if let image = showGrid ? Self.grid : frame {
                let screen = view.window?.windowScene?.screen
                let nativeWidth = screen.map { max($0.nativeBounds.width, $0.nativeBounds.height) } ?? extent.width
                // UIKit supplies pixels, not the physical width. The slider trims this estimate.
                let nominalPPI: CGFloat = (screen?.nativeScale ?? 3) >= 2.5 ? 460 : 326
                let widthMM = nativeWidth / nominalPPI * 25.4
                var geometry = layout
                if showGrid { geometry.packing = .mono }
                let distortion = geometry.distortion
                for eye in 0..<2 {
                    let viewport = geometry.eyeRect(in: extent, eye: eye)
                    let center = geometry.center(in: extent, eye: eye, screenWidthMM: widthMM)
                    let rect = geometry.packing.sourceRect(image.extent, eye: eye)
                    guard rect.width > 0, rect.height > 0 else { continue }
                    let scales = geometry.scales(source: rect.size, viewport: viewport, center: center)
                    let eyeImage = image.cropped(to: rect).transformed(by: CGAffineTransform(
                        a: scales.width, b: 0, c: 0, d: scales.height,
                        tx: center.x - rect.midX * scales.width, ty: center.y - rect.midY * scales.height
                    ))
                    let radius = viewport.height / 2
                    let warped = distortion > 0 ? Self.lensWarp?.apply(
                        extent: viewport,
                        roiCallback: { _, tile in
                            let dx = max(abs(tile.minX - center.x), abs(tile.maxX - center.x))
                            let dy = max(abs(tile.minY - center.y), abs(tile.maxY - center.y))
                            let distance = hypot(dx, dy)
                            let padding = distortion * distance * (distance / radius) * (distance / radius) + 2
                            return tile.insetBy(dx: -padding, dy: -padding)
                        },
                        image: eyeImage,
                        arguments: [CIVector(cgPoint: center), radius, distortion]
                    ) : nil
                    output = (warped ?? eyeImage).cropped(to: viewport).composited(over: output)
                }
            }
            context.render(output, to: drawable.texture, commandBuffer: commands, bounds: extent, colorSpace: colorSpace)
            commands.present(drawable)
            commands.commit()
            lastFrame = generation
            lastSource = source
            lastSize = extent.size
            lastLayout = layout
            lastGrid = showGrid
        }
    }
}
