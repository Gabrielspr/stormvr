import Foundation
import ImageIO
import SwiftUI

struct StereoVideoFrame {
    let left: CGImage
    let right: CGImage

    init?(image: CGImage, inputIsSBS: Bool) {
        if inputIsSBS {
            let width = image.width / 2
            guard width > 0,
                  let left = image.cropping(to: CGRect(x: 0, y: 0, width: width, height: image.height)),
                  let right = image.cropping(to: CGRect(x: image.width - width, y: 0, width: width, height: image.height)) else {
                return nil
            }
            self.left = left
            self.right = right
        } else {
            left = image
            right = image
        }
    }
}

@MainActor
final class VideoFeed: ObservableObject {
    @Published private(set) var frame: StereoVideoFrame?
    @Published private(set) var status = "Aguardando vídeo do PC…"
    private var task: Task<Void, Never>?

    func start(url: URL, token: String, inputIsSBS: Bool) {
        stop()
        task = Task.detached(priority: .userInitiated) { [weak self] in
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 3
            config.timeoutIntervalForResource = 4
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            let session = URLSession(configuration: config, delegate: LocalVideoDelegate(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            var frameID = ""

            while !Task.isCancelled {
                var request = URLRequest(url: url)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue(frameID, forHTTPHeaderField: "If-None-Match")
                do {
                    let (data, response) = try await session.data(for: request)
                    guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                    if http.statusCode == 401 {
                        await self?.update(frame: nil, status: "Código do vídeo inválido")
                        return
                    }
                    if http.statusCode == 204 {
                        try await Task.sleep(nanoseconds: 30_000_000)
                        continue
                    }
                    if http.statusCode == 503 {
                        frameID = ""
                        await self?.update(frame: nil, status: "Aguardando captura no PC…")
                        try await Task.sleep(nanoseconds: 300_000_000)
                        continue
                    }
                    guard http.statusCode == 200, http.mimeType == "image/jpeg",
                          data.count <= 8 * 1024 * 1024,
                          let decoded = Self.decode(data), let frame = StereoVideoFrame(image: decoded, inputIsSBS: inputIsSBS) else {
                        throw URLError(.cannotDecodeContentData)
                    }
                    frameID = http.value(forHTTPHeaderField: "ETag") ?? ""
                    await self?.update(frame: frame, status: "")
                } catch {
                    if Task.isCancelled { return }
                    frameID = ""
                    await self?.update(frame: nil, status: "Vídeo indisponível · Verifique a captura no PC")
                    try? await Task.sleep(nanoseconds: 800_000_000)
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        frame = nil
        status = "Aguardando vídeo do PC…"
    }

    private func update(frame: StereoVideoFrame?, status: String) {
        guard !Task.isCancelled else { return }
        self.frame = frame
        self.status = status
    }

    nonisolated private static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 3072,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

private final class LocalVideoDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
