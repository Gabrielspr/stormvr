import ARKit
import AVFoundation
import CoreMotion
import Network
import SwiftUI

@main
struct StormVRApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .tint(Color(red: 0.62, green: 0.84, blue: 1))
        }
    }
}

private struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("pcAddress") private var address = ""
    @AppStorage("headPort") private var headPort = "5556"
    @AppStorage("videoPort") private var videoPort = "8089"
    @AppStorage("mode") private var mode = TrackingMode.head
    @AppStorage("leftHand") private var leftHand = false
    @AppStorage("trackHands") private var trackHands = false
    @AppStorage("showVideo") private var showVideo = false
    @AppStorage("stereo") private var stereo = true
    @StateObject private var video = VideoFeed()
    @State private var token = ""
    @State private var activeMode: TrackingMode?
    @State private var tracking: TrackingSession?
    @State private var runID = UUID()
    @State private var pending = false
    @State private var message = ""
    @State private var report = TrackingReport(status: "Aguardando sensores…", rate: 0, hands: nil)
    @State private var showHud = true

    var body: some View {
        Group {
            if let activeMode {
                if activeMode == .controller { controller }
                else { headset }
            } else {
                setup
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                let interrupted = activeMode != nil || pending
                stop()
                if interrupted { message = "Sessão encerrada ao sair do StormVR." }
            }
        }
    }

    private var setup: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 36) {
                VStack(alignment: .leading, spacing: 10) {
                    Image("StormLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 52, height: 52)
                        .accessibilityHidden(true)
                    Text("StormVR")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    Text("SteamVR no iPhone")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Picker("Modo", selection: $mode) {
                        ForEach(TrackingMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                    if mode == .controller {
                        Toggle("Mão esquerda", isOn: $leftHand)
                    } else if mode == .spatial {
                        Toggle("Rastrear mãos e pinça", isOn: $trackHands)
                    }
                    if !message.isEmpty {
                        Text(message).font(.footnote).foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: 220, alignment: .leading)

                VStack(alignment: .leading, spacing: 10) {
                    TextField("IPv4 do PC", text: $address)
                        .textContentType(.URL)
                        .accessibilityLabel("IPv4 do PC")
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.numbersAndPunctuation)
                        .textFieldStyle(.roundedBorder)
                    if mode != .controller {
                        TextField("Porta UDP do headset", text: $headPort)
                            .accessibilityLabel("Porta UDP do headset")
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                        Toggle("Exibir vídeo do PC", isOn: $showVideo)
                        if showVideo {
                            HStack {
                                TextField("Porta do vídeo", text: $videoPort)
                                    .accessibilityLabel("Porta do vídeo")
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 120)
                                SecureField("Código do vídeo", text: $token)
                                    .accessibilityLabel("Código do vídeo")
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .textFieldStyle(.roundedBorder)
                            }
                            Toggle("Imagem lado a lado (SBS)", isOn: $stereo)
                        }
                    }
                    Button(pending ? "Aguardando permissão…" : "Iniciar sessão", action: start)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(pending)
                }
                .frame(maxWidth: 420, alignment: .leading)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .disabled(pending)
        }
        .scrollDismissesKeyboard(.interactively)
        .background {
            LinearGradient(colors: [Color(red: 0.07, green: 0.14, blue: 0.21), .black],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
        }
    }

    private var headset: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            if let image = video.image, showVideo {
                if stereo {
                    eye(image)
                } else {
                    HStack(spacing: 0) { eye(image); eye(image) }
                }
            } else {
                VStack(spacing: 6) {
                    Text(showVideo ? video.status : "Rastreamento do headset")
                    if !showVideo { Text(report.status).foregroundStyle(.secondary) }
                }
                .font(.callout)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if showHud {
                HStack {
                    status
                    Spacer()
                    controls
                }
                .padding(8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { showHud.toggle() }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }

    private func eye(_ image: CGImage) -> some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var controller: some View {
        VStack(spacing: 12) {
            HStack {
                status
                Spacer()
                controls
            }
            HStack(spacing: 30) {
                VStack {
                    Stick { tracking?.moveStick($0) }
                    control("L3", mask: 1 << 7)
                }
                Spacer(minLength: 0)
                VStack(spacing: 8) {
                    HStack {
                        control("Grip", mask: 1)
                        control("Gatilho", mask: 1 << 1)
                        control("R2", mask: 1 << 8)
                    }
                    HStack {
                        control("X", mask: 1 << 4)
                        control("Y", mask: 1 << 5)
                        control("A", mask: 1 << 2)
                        control("B", mask: 1 << 3)
                    }
                    control("Start", mask: 1 << 6)
                }
            }
            .frame(maxWidth: 570, maxHeight: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color(red: 0.07, green: 0.12, blue: 0.18).ignoresSafeArea())
        .statusBarHidden(true)
    }

    private func control(_ title: String, mask: UInt16) -> some View {
        MomentaryButton(title: title) { tracking?.setButton(mask, pressed: $0) }
    }

    private var controls: some View {
        HStack {
            Button("Recentrar") { tracking?.requestRecenter() }
                .buttonStyle(.bordered)
            Button("Parar", action: stop)
                .buttonStyle(.borderedProminent)
        }
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(report.status)
            HStack {
                Text("\(report.rate) pacotes/s")
                if let hands = report.hands { Text(hands) }
            }
            .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private func start() {
        message = ""
        let server = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let host = IPv4Address(server),
              let first = host.rawValue.first, first > 0, first < 224 else {
            message = "Informe um endereço IPv4 do PC."
            return
        }
        let selected = mode
        let udpText = selected == .controller ? (leftHand ? "5558" : "5555") : headPort
        guard let udp = UInt16(udpText), udp >= 1024, let port = NWEndpoint.Port(rawValue: udp) else {
            message = "Informe uma porta UDP entre 1024 e 65535."
            return
        }
        var videoURL: URL?
        let code = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if selected != .controller && showVideo {
            let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
            guard let tcp = UInt16(videoPort), tcp >= 1024, code.count == 16,
                  code.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
                message = "Preencha a porta e o código exibidos no PC."
                return
            }
            var components = URLComponents()
            components.scheme = "http"
            components.host = server
            components.port = Int(tcp)
            components.path = "/frame.jpg"
            videoURL = components.url
        }

        if selected == .spatial, !ARWorldTrackingConfiguration.isSupported {
            message = "Este aparelho não oferece rastreamento 6DoF. Selecione 3DoF."
            return
        }
        if selected != .spatial, !CMMotionManager().isDeviceMotionAvailable {
            message = "Os sensores de movimento estão indisponíveis neste aparelho."
            return
        }

        let id = UUID()
        runID = id
        pending = true
        Task { @MainActor in
            if selected == .spatial {
                let allowed = await AVCaptureDevice.requestAccess(for: .video)
                guard runID == id else { return }
                if !allowed {
                    pending = false
                    message = "Permita o uso da câmera nos Ajustes para usar 6DoF."
                    return
                }
            }
            guard runID == id else { return }
            activeMode = selected
            pending = false
            showHud = true
            report = TrackingReport(status: "Aguardando sensores…", rate: 0, hands: nil)
            let session = TrackingSession(
                mode: selected, host: host, port: port, device: Self.deviceID,
                leftHand: leftHand, hands: trackHands
            ) { next in
                DispatchQueue.main.async {
                    if runID == id { report = next }
                }
            }
            tracking = session
            UIApplication.shared.isIdleTimerDisabled = true
            session.start()
            if let videoURL { video.start(url: videoURL, token: code) }
        }
    }

    private func stop() {
        runID = UUID()
        pending = false
        tracking?.stop()
        tracking = nil
        activeMode = nil
        video.stop()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private static var deviceID: UInt32 {
        let key = "stormvrDeviceID"
        let settings = UserDefaults.standard
        if let stored = UInt32(settings.string(forKey: key) ?? ""), stored != 0 { return stored }
        let value = UInt32.random(in: 1...UInt32.max)
        settings.set(String(value), forKey: key)
        return value
    }
}

private struct MomentaryButton: View {
    let title: String
    let onPress: (Bool) -> Void
    @GestureState private var pressed = false

    var body: some View {
        Text(title)
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 12)
            .frame(minWidth: 48, minHeight: 44)
            .background(pressed ? Color.blue : Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).updating($pressed) { _, state, _ in state = true })
            .onChange(of: pressed, perform: onPress)
            .accessibilityAddTraits(.isButton)
    }
}

private struct Stick: View {
    let onMove: (SIMD2<Float>) -> Void
    @GestureState private var drag: CGSize = .zero
    private let radius: CGFloat = 53

    var body: some View {
        ZStack {
            Circle().fill(.white.opacity(0.08))
            Circle().strokeBorder(.white.opacity(0.25))
            Circle().fill(.white.opacity(0.6)).frame(width: 42)
                .offset(drag)
        }
        .frame(width: 152, height: 152)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0).updating($drag) { touch, state, _ in
            let dx = touch.location.x - 76
            let dy = touch.location.y - 76
            let scale = radius / max(radius, hypot(dx, dy))
            state = CGSize(width: dx * scale, height: dy * scale)
        })
        .onChange(of: drag) { value in
            onMove(SIMD2(Float(value.width / radius), Float(-value.height / radius)))
        }
        .accessibilityLabel("Analógico")
    }
}
