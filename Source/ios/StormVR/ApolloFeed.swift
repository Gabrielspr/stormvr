import CoreImage
import CoreVideo
import MetalKit
import SwiftUI

enum HostVideoSource: String, CaseIterable, Identifiable {
    case apollo = "Apollo / Sunshine"
    case capture = "Captura StormVR (8089)"
    var id: Self { self }
}

final class ApolloFrames: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: CVPixelBuffer?
    private var generation: UInt64 = 0

    func replace(with next: CVPixelBuffer?) {
        lock.lock()
        buffer = next
        generation &+= 1
        lock.unlock()
    }

    func latest() -> (CVPixelBuffer?, UInt64) {
        lock.lock()
        defer { lock.unlock() }
        return (buffer, generation)
    }
}

@MainActor
final class ApolloFeed: ObservableObject {
    @Published private(set) var status = "Conecte ao Apollo para escolher o que transmitir."
    @Published private(set) var applications: [SVRApolloApplication] = []
    @Published var selectedApp = ""
    private(set) var address = ""
    let frames = ApolloFrames()
    private let client = SVRApolloClient()

    func prepare(address: String) {
        self.address = address
        applications = []
        selectedApp = ""
        frames.replace(with: nil)
        status = "Consultando Apollo…"
        client.prepare(host: address, status: { [weak self] in self?.status = $0 }, applications: { [weak self] apps in
            guard let self else { return }
            self.applications = apps
            self.selectedApp = apps.first(where: { $0.title.caseInsensitiveCompare("Desktop") == .orderedSame })?.identifier
                ?? apps.first?.identifier ?? ""
        })
    }

    func isReady(for target: String) -> Bool {
        address == target && applications.contains { $0.identifier == selectedApp }
    }

    func start() {
        frames.replace(with: nil)
        status = "Iniciando transmissão Apollo…"
        let buffer = frames
        client.start(application: selectedApp, frame: { buffer.replace(with: $0) }, status: { [weak self] in self?.status = $0 })
    }

    func stop() {
        client.stop()
        frames.replace(with: nil)
    }
}

struct ApolloVideoSurface: UIViewRepresentable {
    let frames: ApolloFrames
    let inputIsSBS: Bool

    func makeCoordinator() -> Presenter { Presenter(frames: frames, inputIsSBS: inputIsSBS) }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        view.backgroundColor = .black
        view.preferredFramesPerSecond = 60
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) { context.coordinator.inputIsSBS = inputIsSBS }

    final class Presenter: NSObject, MTKViewDelegate {
        let device: MTLDevice?
        var inputIsSBS: Bool
        private let frames: ApolloFrames
        private let queue: MTLCommandQueue?
        private let context: CIContext?
        private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        private var lastFrame: UInt64?
        private var lastSize: CGSize = .zero
        private var lastSBS = false

        init(frames: ApolloFrames, inputIsSBS: Bool) {
            let device = MTLCreateSystemDefaultDevice()
            self.frames = frames
            self.inputIsSBS = inputIsSBS
            self.device = device
            queue = device?.makeCommandQueue()
            context = device.map { CIContext(mtlDevice: $0, options: [.cacheIntermediates: false]) }
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { lastFrame = nil }

        func draw(in view: MTKView) {
            let (buffer, generation) = frames.latest()
            let extent = CGRect(origin: .zero, size: view.drawableSize)
            guard extent.width >= 2, extent.height > 0,
                  lastFrame != generation || lastSize != extent.size || lastSBS != inputIsSBS,
                  let context, let drawable = view.currentDrawable, let commands = queue?.makeCommandBuffer() else { return }

            var output = CIImage(color: .black).cropped(to: extent)
            if let buffer {
                let source = CIImage(cvPixelBuffer: buffer)
                let sources: (CIImage, CIImage)
                if inputIsSBS {
                    let half = floor(source.extent.width / 2)
                    let left = CGRect(x: source.extent.minX, y: source.extent.minY, width: half, height: source.extent.height)
                    let right = CGRect(x: source.extent.maxX - half, y: source.extent.minY, width: half, height: source.extent.height)
                    sources = (source.cropped(to: left), source.cropped(to: right))
                } else {
                    sources = (source, source)
                }
                let halfWidth = floor(extent.width / 2)
                let leftEye = CGRect(x: 0, y: 0, width: halfWidth, height: extent.height)
                let rightEye = CGRect(x: halfWidth, y: 0, width: extent.width - halfWidth, height: extent.height)
                output = fit(sources.1, into: rightEye).composited(over: fit(sources.0, into: leftEye).composited(over: output))
            }
            context.render(output, to: drawable.texture, commandBuffer: commands, bounds: extent, colorSpace: colorSpace)
            commands.present(drawable)
            commands.commit()
            lastFrame = generation
            lastSize = extent.size
            lastSBS = inputIsSBS
        }

        private func fit(_ image: CIImage, into eye: CGRect) -> CIImage {
            let rect = image.extent
            guard rect.width > 0, rect.height > 0 else { return CIImage.empty() }
            let scale = min(eye.width / rect.width, eye.height / rect.height)
            return image.transformed(by: CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                tx: eye.midX - rect.midX * scale, ty: eye.midY - rect.midY * scale))
        }
    }
}
