import ARKit
import CoreMotion
import Foundation
import Network
import simd

enum TrackingMode: String, CaseIterable, Identifiable {
    case head = "Headset 3DoF"
    case spatial = "Headset 6DoF"
    case controller = "Controle 3DoF"

    var id: Self { self }
}

struct TrackingReport {
    let status: String
    let rate: Int
    let hands: String?
}

// Sensors and UDP run on a serial queue independent of the UI and video decoder.
final class TrackingSession {
    private let queue = DispatchQueue(label: "stormvr.tracking", qos: .userInteractive)
    private let mode: TrackingMode
    private let host: IPv4Address
    private let port: NWEndpoint.Port
    private let device: UInt32
    private let leftHand: Bool
    private let handTracker: HandTracker?
    private let report: (TrackingReport) -> Void
    private let session = UInt32.random(in: 1...UInt32.max)
    private let motion = CMMotionManager()
    private let enuToVR = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))
    // The app uses UIInterfaceOrientation.landscapeRight (device top on the left).
    private let mount = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(0, 0, 1))
    private var ar: ARSession?
    private var timer: DispatchSourceTimer?
    private var connection: NWConnection?
    private var handLink: NWConnection?
    private var handSequence: UInt32 = 0
    private var handCaptureStamp = -1.0
    private var handJob = false
    private var lastHandDelivery = 0.0
    private var handsVisible = false
    private var handStatus = "Aguardando mãos"
    private var ready = false
    private var inFlight = false
    private var retryAfter = 0.0
    private var networkStatus = "Abrindo conexão UDP…"
    private var sensorStatus = "Aguardando sensores…"
    private var lastReport = ProcessInfo.processInfo.systemUptime
    private var sent = 0
    private var sequence: UInt32 = 0
    private var recenter: UInt32 = 0
    private var recenterPending = true
    private var positionOrigin = SIMD3<Float>.zero
    private var yawReference = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    private var controllerHeading: Float = 0
    private var buttons: UInt16 = 0
    private var stick = SIMD2<Float>.zero
    private var lastSensorStamp = -1.0
    private var lastFresh = 0.0
    private var lastSend = 0.0

    init(
        mode: TrackingMode, host: IPv4Address, port: NWEndpoint.Port, device: UInt32,
        leftHand: Bool, hands: Bool, report: @escaping (TrackingReport) -> Void
    ) {
        self.mode = mode
        self.host = host
        self.port = port
        self.device = device
        self.leftHand = leftHand
        self.handTracker = hands && mode == .spatial ? HandTracker() : nil
        self.report = report
    }

    func start() {
        queue.async {
            if self.mode == .spatial {
                let config = ARWorldTrackingConfiguration()
                config.worldAlignment = .gravity
                let ar = ARSession()
                self.ar = ar
                ar.run(config, options: [.resetTracking])
            } else {
                self.motion.deviceMotionUpdateInterval = 0.01
                self.motion.startDeviceMotionUpdates(using: .xArbitraryZVertical)
            }

            self.connect()
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(10), leeway: .milliseconds(1))
            timer.setEventHandler { [weak self] in self?.tick() }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        queue.async {
            self.timer?.cancel()
            self.timer = nil
            self.connection?.cancel()
            self.connection = nil
            self.handLink?.cancel()
            self.handLink = nil
            self.motion.stopDeviceMotionUpdates()
            self.ar?.pause()
            self.ar = nil
        }
    }

    func requestRecenter() {
        queue.async { self.recenterPending = true }
    }

    func setButton(_ mask: UInt16, pressed: Bool) {
        queue.async {
            if pressed { self.buttons |= mask } else { self.buttons &= ~mask }
        }
    }

    func moveStick(_ value: SIMD2<Float>) {
        queue.async { self.stick = value }
    }

    private func connect() {
        let link = NWConnection(host: .ipv4(host), port: port, using: .udp)
        connection = link
        networkStatus = "Abrindo conexão UDP…"
        link.stateUpdateHandler = { [weak self, weak link] state in
            guard let self, let link, self.connection === link else { return }
            switch state {
            case .ready:
                self.ready = true
                self.networkStatus = "Enviando por UDP"
            case .waiting(let error):
                self.ready = false
                self.networkStatus = link.currentPath?.unsatisfiedReason == .localNetworkDenied
                    ? "Permita o acesso à Rede Local nos Ajustes"
                    : "Aguardando rede · \(error.localizedDescription)"
            case .failed(let error):
                self.restartLink(link, error: error)
            default:
                break
            }
        }
        link.start(queue: queue)
    }

    private func restartLink(_ link: NWConnection, error: NWError) {
        networkStatus = "Reconectando · \(error.localizedDescription)"
        retryAfter = ProcessInfo.processInfo.systemUptime + 1
        ready = false
        inFlight = false
        connection = nil
        link.cancel()
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        if handsVisible, now - lastHandDelivery >= 0.15, let link = handLink, case .ready = link.state {
            sendHands(nil, nil, stamp: now, over: link)
        }
        if connection == nil, now >= retryAfter { connect() }
        if let packet = sample(now: now), let link = connection, ready, !inFlight {
            lastSend = now
            sequence &+= 1
            inFlight = true
            link.send(content: packet, completion: .contentProcessed { [weak self, weak link] error in
                guard let self, let link, self.connection === link else { return }
                self.inFlight = false
                if let error { self.restartLink(link, error: error) } else { self.sent += 1 }
            })
        }

        let elapsed = now - lastReport
        if elapsed >= 0.5 {
            report(TrackingReport(
                status: ready && !sensorStatus.isEmpty ? sensorStatus : networkStatus,
                rate: Int((Double(sent) / elapsed).rounded()),
                hands: handTracker == nil ? nil : handStatus
            ))
            lastReport = now
            sent = 0
        }
    }

    private func sample(now: Double) -> Data? {
        if let ar {
            guard let frame = ar.currentFrame, case .normal = frame.camera.trackingState else {
                sensorStatus = "6DoF · Mova o iPhone devagar em um ambiente bem iluminado"
                handStatus = "Aguardando câmera"
                return nil
            }
            guard shouldSend(stamp: frame.timestamp, now: now) else { return nil }
            let transform = frame.camera.transform
            let rotation = simd_quatf(transform).normalized
            let forward = rotation.act(SIMD3<Float>(0, 0, -1))
            let level = hypot(forward.x, forward.z) > 0.25
            let yaw = atan2(-forward.x, -forward.z)
            let translation = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            if recenterPending {
                guard level else {
                    sensorStatus = "Aponte o headset para frente para recentrar"
                    return nil
                }
                yawReference = simd_quatf(angle: -yaw, axis: SIMD3<Float>(0, 1, 0))
                positionOrigin = translation
                finishRecenter()
            }
            if level {
                let removeYaw = simd_quatf(angle: -yaw, axis: SIMD3<Float>(0, 1, 0))
                trackHands(frame, rotation: removeYaw * rotation)
            }
            sensorStatus = ""
            return head(
                stamp: frame.timestamp, rotation: (yawReference * rotation).normalized,
                position: yawReference.act(translation - positionOrigin)
            )
        }

        guard let sample = motion.deviceMotion, shouldSend(stamp: sample.timestamp, now: now) else { return nil }
        let q = sample.attitude.quaternion
        // Core Motion describes the reference frame in device axes. Invert it before
        // converting the Z-up world into SteamVR's Y-up world.
        let orientation = simd_quatf(ix: Float(q.x), iy: Float(q.y), iz: Float(q.z), r: Float(q.w))
        let deviceToVR = enuToVR * orientation.inverse
        if mode == .controller { return controller(rotation: deviceToVR, now: now) }

        if recenterPending { finishRecenter() }
        sensorStatus = ""
        return head(stamp: sample.timestamp, rotation: (deviceToVR * mount).normalized, position: nil)
    }

    private func shouldSend(stamp: Double, now: Double) -> Bool {
        let fresh = stamp != lastSensorStamp
        if fresh {
            lastSensorStamp = stamp
            lastFresh = now
        }
        guard now - lastFresh < 0.5 else {
            sensorStatus = "Aguardando nova leitura dos sensores…"
            return false
        }
        return fresh || recenterPending || now - lastSend >= 0.025
    }

    private func finishRecenter() {
        recenter &+= 1
        recenterPending = false
    }

    private func trackHands(_ frame: ARFrame, rotation: simd_quatf) {
        guard let handTracker, !handJob, frame.timestamp - handCaptureStamp >= 1.0 / 30 - 0.001 else { return }
        if handLink == nil {
            let link = NWConnection(host: .ipv4(host), port: 5557, using: .udp)
            link.stateUpdateHandler = { [weak self, weak link] state in
                guard let self, let link, self.handLink === link else { return }
                if case .failed = state {
                    self.handLink = nil
                    link.cancel()
                }
            }
            handLink = link
            link.start(queue: queue)
        }
        handJob = true
        handCaptureStamp = frame.timestamp
        let stamp = frame.timestamp
        let started = ProcessInfo.processInfo.systemUptime
        handTracker.detect(frame: frame, rotation: rotation) { [weak self] left, right in
            guard let self else { return }
            self.queue.async {
                self.handJob = false
                guard let link = self.handLink, case .ready = link.state,
                      let current = self.ar?.currentFrame, case .normal = current.camera.trackingState,
                      ProcessInfo.processInfo.systemUptime - started < 0.18 else { return }
                self.sendHands(left, right, stamp: stamp, over: link)
            }
        }
    }

    private func sendHands(_ left: Wire.Hand?, _ right: Wire.Hand?, stamp: Double, over link: NWConnection) {
        let packet = Wire.hands(
            device: device, session: session, sequence: handSequence,
            timeUs: UInt64(stamp * 1_000_000), left: left, right: right
        )
        handSequence &+= 1
        lastHandDelivery = ProcessInfo.processInfo.systemUptime
        let count = (left == nil ? 0 : 1) + (right == nil ? 0 : 1)
        handsVisible = count > 0
        handStatus = ["Nenhuma mão visível", "1 mão detectada", "2 mãos detectadas"][count]
        link.send(content: packet, completion: .idempotent)
    }

    private func head(stamp: Double, rotation: simd_quatf, position: SIMD3<Float>?) -> Data {
        Wire.head(
            device: device, session: session, sequence: sequence, timeUs: UInt64(stamp * 1_000_000),
            rotation: rotation.vector, recenter: recenter, position: position
        )
    }

    private func controller(rotation: simd_quatf, now: Double) -> Data? {
        let forward = rotation.act(SIMD3<Float>(0, 1, 0))
        let right = rotation.act(SIMD3<Float>(1, 0, 0))
        let heading = atan2(-forward.z, forward.x)
        let horizontal = hypot(forward.x, forward.z)
        if recenterPending {
            guard horizontal > 0.25 else {
                sensorStatus = "Aponte a borda de cima do iPhone para frente"
                return nil
            }
            controllerHeading = heading
            finishRecenter()
        }
        let delta = heading - controllerHeading
        let yaw = atan2(sin(delta), cos(delta))
        let pitch = asin(max(-1, min(1, forward.y)))
        let roll = horizontal > 0.001
            ? atan2(right.y, (right.z * forward.x - right.x * forward.z) / horizontal)
            : 0
        sensorStatus = ""
        return Wire.controller(
            sequence: UInt16(truncatingIfNeeded: sequence), buttons: buttons, stick: stick,
            angles: SIMD3<Float>(roll, pitch, yaw) * (180 / .pi),
            uptimeMs: UInt32(truncatingIfNeeded: UInt64(now * 1000)), left: leftHand
        )
    }
}
