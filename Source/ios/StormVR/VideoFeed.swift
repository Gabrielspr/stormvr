import Foundation
import ImageIO
import SwiftUI

@MainActor
final class VideoFeed: ObservableObject {
    @Published private(set) var image: CGImage?
    @Published private(set) var status = "Aguardando vídeo do PC…"
    private var task: Task<Void, Never>?

    func start(url: URL, token: String) {
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
                        await self?.update(image: nil, status: "Código do vídeo inválido")
                        return
                    }
                    if http.statusCode == 204 || http.statusCode == 503 {
                        frameID = ""
                        await self?.update(image: nil, status: "Aguardando captura no PC…")
                        try await Task.sleep(nanoseconds: 300_000_000)
                        continue
                    }
                    guard http.statusCode == 200, http.mimeType == "image/jpeg",
                          data.count <= 8 * 1024 * 1024,
                          let decoded = Self.decode(data) else { throw URLError(.cannotDecodeContentData) }
                    frameID = http.value(forHTTPHeaderField: "ETag") ?? ""
                    await self?.update(image: decoded, status: "")
                } catch {
                    if Task.isCancelled { return }
                    frameID = ""
                    await self?.update(image: nil, status: "Vídeo indisponível · Verifique a captura no PC")
                    try? await Task.sleep(nanoseconds: 800_000_000)
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        image = nil
        status = "Aguardando vídeo do PC…"
    }

    private func update(image: CGImage?, status: String) {
        guard !Task.isCancelled else { return }
        self.image = image
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
