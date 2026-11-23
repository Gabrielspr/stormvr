import Darwin
import Foundation
import SwiftUI

struct DiscoveredHost: Identifiable, Equatable {
    let name: String
    let address: String
    var id: String { address }
}

final class HostDiscovery: NSObject, ObservableObject, NetServiceBrowserDelegate, NetServiceDelegate {
    @Published private(set) var hosts: [DiscoveredHost] = []
    @Published private(set) var searching = false
    @Published private(set) var status = ""
    private var browser: NetServiceBrowser?
    private var services: [NetService] = []
    private var timeout: DispatchWorkItem?

    func search() {
        stop()
        hosts = []
        status = "Procurando Apollo / Sunshine na rede local…"
        searching = true
        let browser = NetServiceBrowser()
        self.browser = browser
        browser.delegate = self
        browser.searchForServices(ofType: "_nvstream._tcp.", inDomain: "local.")
        let timeout = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.stop()
            self.status = self.hosts.isEmpty ? "Nenhum PC encontrado. Confira a rede local ou informe o IPv4." : ""
        }
        self.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: timeout)
    }

    func stop() {
        timeout?.cancel()
        timeout = nil
        browser?.stop()
        browser = nil
        for service in services { service.stop() }
        services = []
        searching = false
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        guard browser === self.browser else { return }
        services.append(service)
        service.delegate = self
        service.resolve(withTimeout: 4)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        guard browser === self.browser else { return }
        stop()
        status = "Busca indisponível. Confira a permissão de rede local do StormVR."
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard services.contains(where: { $0 === sender }) else { return }
        for item in sender.addresses ?? [] {
            guard item.count >= MemoryLayout<sockaddr_in>.size else { continue }
            var socket = item.withUnsafeBytes { $0.loadUnaligned(as: sockaddr_in.self) }
            guard socket.sin_family == sa_family_t(AF_INET) else { continue }
            let size = Int(INET_ADDRSTRLEN)
            var text = [CChar](repeating: 0, count: size)
            guard inet_ntop(AF_INET, &socket.sin_addr, &text, socklen_t(size)) != nil else { continue }
            let address = String(cString: text)
            guard !hosts.contains(where: { $0.address == address }) else { continue }
            hosts.append(DiscoveredHost(name: sender.name, address: address))
            status = ""
        }
    }
}
