import ARKit
import Foundation
import ImageIO
import Vision
import simd

final class HandTracker {
    private struct Observation {
        let position: SIMD3<Float>
        let aim: SIMD3<Float>
        let ratio: Float?
        let confidence: Float
    }

    private struct HandState {
        var position = SIMD3<Float>.zero
        var aim = SIMD3<Float>(0, 0, -1)
        var ratio: Float = 1
        var seenAt = -Double.infinity
        var fingersAt = -Double.infinity
        var closingFrames = 0
        var openSeen = false
        var pinched = false

        mutating func update(_ observation: Observation?, at stamp: Double) -> Wire.Hand? {
            if stamp - fingersAt > 0.12 {
                pinched = false
                openSeen = false
                closingFrames = 0
                ratio = 1
            }
            if let observation {
                if stamp - seenAt > 0.15 { self = HandState() }
                let distance = simd_distance(position, observation.position)
                let weight: Float = seenAt.isFinite ? min(0.9, 0.24 + distance * 5) : 1
                position += (observation.position - position) * weight
                let nextAim = aim + (observation.aim - aim) * weight
                aim = simd_length_squared(nextAim) > 0.0001 ? simd_normalize(nextAim) : observation.aim
                seenAt = stamp

                if let measurement = observation.ratio {
                    ratio += (measurement - ratio) * 0.75
                    fingersAt = stamp
                    if ratio > 0.46 {
                        pinched = false
                        if measurement > 0.46 { openSeen = true }
                        closingFrames = 0
                    } else if ratio < 0.30, openSeen {
                        closingFrames = min(2, closingFrames + 1)
                        if closingFrames == 2 { pinched = true }
                    } else {
                        closingFrames = 0
                    }
                } else {
                    closingFrames = 0
                }
            } else {
                closingFrames = 0
            }

            guard stamp - seenAt <= 0.15 else { return nil }
            return Wire.Hand(position: position, aim: aim, ratio: ratio, pinched: pinched)
        }
    }

    private let queue = DispatchQueue(label: "stormvr.vision", qos: .userInitiated)
    private let request: VNDetectHumanHandPoseRequest = {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 2
        return request
    }()
    private var hands = [HandState(), HandState()]

    func detect(
        frame: ARFrame, rotation: simd_quatf,
        completion: @escaping (Wire.Hand?, Wire.Hand?) -> Void
    ) {
        // Retain the image and calibration only while Vision works.
        let image = frame.capturedImage
        let camera = frame.camera
        let stamp = frame.timestamp
        queue.async {
            let handler = VNImageRequestHandler(cvPixelBuffer: image, orientation: .up)
            var observations = [Observation?](repeating: nil, count: 2)
            if (try? handler.perform([self.request])) != nil {
                for result in self.request.results ?? [] {
                    let slot: Int
                    switch result.chirality {
                    case .left: slot = 0
                    case .right: slot = 1
                    default: continue
                    }
                    guard let found = Self.project(result, camera: camera, rotation: rotation) else { continue }
                    if found.confidence > (observations[slot]?.confidence ?? 0) { observations[slot] = found }
                }
            }
            let left = self.hands[0].update(observations[0], at: stamp)
            let right = self.hands[1].update(observations[1], at: stamp)
            completion(left, right)
        }
    }

    private static func project(
        _ result: VNHumanHandPoseObservation, camera: ARCamera, rotation: simd_quatf
    ) -> Observation? {
        guard let wrist = try? result.recognizedPoint(.wrist),
              let middle = try? result.recognizedPoint(.middleMCP),
              min(wrist.confidence, middle.confidence) >= 0.5 else { return nil }

        let calibration = camera.intrinsics
        let resolution = camera.imageResolution
        func ray(_ point: VNRecognizedPoint) -> SIMD2<Float> {
            let x = Float(point.location.x * resolution.width)
            let y = Float((1 - point.location.y) * resolution.height)
            return SIMD2((x - calibration.columns.2.x) / calibration.columns.0.x,
                         (calibration.columns.2.y - y) / calibration.columns.1.y)
        }
        let wristRay = ray(wrist)
        let middleRay = ray(middle)
        let palmLength = simd_distance(wristRay, middleRay)
        guard palmLength > 0.025 else { return nil }
        let depth = min(1.2, max(0.15, 0.085 / palmLength))
        let center = (wristRay + middleRay) * 0.5 * depth
        let palmDirection = middleRay - wristRay
        let position = rotation.act(SIMD3<Float>(center.x, center.y, -depth))
        // Vision supplies screen-space joints. Tilt the pointing ray modestly toward
        // the palm's direction without claiming measured finger depth.
        let aim = rotation.act(simd_normalize(SIMD3<Float>(
            middleRay.x + palmDirection.x * 1.5, middleRay.y + palmDirection.y * 1.5, -1
        )))

        var ratio: Float?
        if let thumb = try? result.recognizedPoint(.thumbTip),
           let index = try? result.recognizedPoint(.indexTip),
           min(thumb.confidence, index.confidence) >= 0.55 {
            ratio = simd_distance(ray(thumb), ray(index)) / palmLength
        }
        return Observation(position: position, aim: aim, ratio: ratio,
                           confidence: min(wrist.confidence, middle.confidence))
    }
}
