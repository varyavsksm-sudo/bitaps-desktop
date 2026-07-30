//
//  PacketTunnelProvider.swift
//  PacketTunnel (bundle id: com.bitapsvpn.bitapsVpn.PacketTunnel)
//
//  NetworkExtension packet-tunnel для bitaps VPN (движок: Xray-core через LibXray.xcframework).
//
//  Поток конфигурации:
//    Flutter (Dart, xray_config.dart forIOS) → MethodChannel → AppDelegate
//      → файл xray_config.json в App Group-контейнере (NSFileProtectionComplete,
//        атомарная запись temp+rename)  →  этот провайдер.
//
//  libXray API (XTLS/libXray, MIT): единая точка `Invoke(requestJSON) -> responseJSON`.
//  Поддерживаемые методы: runXray/runXrayFromJson/stopXray/xrayVersion/getXrayState.
//  Tun-fd передаётся через корневое поле `env` конфига: {"xray.tun.fd": <fd>}
//  (метод SetTunFd из старых версий удалён — только env, см. README libXray).
//

import Foundation

#if canImport(NetworkExtension)
import NetworkExtension
import os.log
#if canImport(LibXray)
import LibXray
#endif

/// Маркер App Group — тот же, что в entitlements обоих таргетов и в AppDelegate.swift.
private let kAppGroup = "group.com.bitapsvpn.bitapsVpn"
/// Конфиг — файл-конверт в контейнере App Group (НЕ UserDefaults: там UUID/ключи узлов
/// лежали plaintext бессрочно, плюс была гонка записи (app) / чтения (extension)).
private let kConfigFile = "xray_config.json"
private let kConfigKey = "xray_config_json"
private let kServerKey = "xray_server_id"
private let kConfigAtKey = "xray_config_at"
/// Конфиг пишется приложением прямо перед startVPNTunnel; всё старше — не наше
/// (система переподняла extension сама) → честный отказ, а не работа на старых ключах.
private let kMaxConfigAge: TimeInterval = 10

final class PacketTunnelProvider: NEPacketTunnelProvider {

    private let log = OSLog(subsystem: "com.bitapsvpn.bitapsVpn.PacketTunnel", category: "tunnel")

    private enum Net {
        static let tunnelRemoteAddress = "172.19.0.1"
        static let ipv4Address         = "172.19.0.2"
        static let ipv4SubnetMask      = "255.255.255.252"
        // ULA-подсеть — зеркало IPv4: ::1 — сторона движка (декларировано в xray_config.dart,
        // tun address fdfe:dcba:9876::1/126), ::2 — наш конец туннеля.
        static let ipv6Address         = "fdfe:dcba:9876::2"
        static let ipv6PrefixLength: NSNumber = 126
        static let dnsServers          = ["77.88.8.8", "8.8.8.8"]
    }

    private var configJSON: String?
    private var serverID: String?
    private var running = false

    // MARK: - libXray Invoke (тонкая обёртка над JSON-API)

    #if canImport(LibXray)
    @discardableResult
    private func lx(_ request: [String: Any]) throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: request)
        let reqStr = String(data: data, encoding: .utf8)!
        guard let respStr = LibXrayInvoke(reqStr) else {
            throw NSError(domain: "bitaps.PacketTunnel", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "libXray Invoke вернул null"])
        }
        let respData = respStr.data(using: .utf8)!
        let obj = try JSONSerialization.jsonObject(with: respData) as? [String: Any] ?? [:]
        if (obj["success"] as? Bool) == true { return obj }
        throw NSError(domain: "bitaps.PacketTunnel", code: -3,
                      userInfo: [NSLocalizedDescriptionKey: "libXray: \(obj["error"] ?? "unknown")"])
    }
    #endif

    // MARK: - Start

    override func startTunnel(options: [String: NSObject]?,
                             completionHandler: @escaping (Error?) -> Void) {
        os_log("startTunnel", log: log, type: .info)

        // 1. Конфиг из App Group — ФАЙЛ (его атомарно записал AppDelegate по MethodChannel
        //    из Dart): temp+rename на той стороне гарантирует, что читаем версию целиком.
        var configAt: TimeInterval = 0
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: kAppGroup),
           let data = try? Data(contentsOf: container.appendingPathComponent(kConfigFile)),
           let env = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            self.configJSON = env[kConfigKey] as? String
            self.serverID = env[kServerKey] as? String
            configAt = env[kConfigAtKey] as? TimeInterval ?? 0
        }

        // Свежесть: конфиг пишется приложением прямо перед startVPNTunnel. Просрочен (>10 c)
        // или файла нет вовсе — значит, туннель поднимает система без приложения: честный
        // отказ, а не работа на старых ключах.
        guard let config = configJSON, !config.isEmpty,
              Date().timeIntervalSince1970 - configAt <= kMaxConfigAge else {
            let e = NSError(domain: "bitaps.PacketTunnel", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "нет конфигурации — откройте приложение и подключитесь заново"
            ])
            completionHandler(e)
            return
        }

        #if canImport(LibXray)
        do {
            // 2. Сетевые настройки интерфейса (адрес + маршрут по умолчанию + DNS).
            try setTunnelNetworkSettings(makeTunnelSettings()) { [weak self] error in
                guard let self else { return }
                if let error { completionHandler(error); return }
                do {
                    try self.startEngine(config: config)
                    self.running = true
                    os_log("tunnel started (engine=libXray)", log: self.log, type: .info)
                    completionHandler(nil)
                } catch {
                    completionHandler(error)
                }
            }
        } catch {
            completionHandler(error)
        }
        #else
        // Честный отказ без движка: не поднимаем TUN, чтобы не блокировать трафик пользователя.
        let e = NSError(domain: "bitaps.PacketTunnel", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "LibXray.xcframework не слинкован в этой сборке (см. tools/fetch-libxray.sh)"
        ])
        completionHandler(e)
        #endif
    }

    #if canImport(LibXray)
    /// Поднять xray: сливаем конфиг из Dart с env{xray.tun.fd} и стартуем Invoke(runXrayFromJson).
    private func startEngine(config: String) throws {
        // 3. utun fd от системы (KVC на socket.packetFlow — стандартный приём NE).
        guard let fd = packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32 else {
            throw NSError(domain: "bitaps.PacketTunnel", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "не удалось получить utun fd"])
        }
        var root = (try JSONSerialization.jsonObject(with: Data(config.utf8))) as? [String: Any] ?? [:]
        var env = root["env"] as? [String: Any] ?? [:]
        env["xray.tun.fd"] = NSNumber(value: fd)
        root["env"] = env
        let merged = try JSONSerialization.data(withJSONObject: root)
        let mergedStr = String(data: merged, encoding: .utf8)!

        let resp = try lx(["apiVersion": 1, "method": "runXrayFromJson", "payload": ["json": mergedStr]])
        os_log("runXrayFromJson ok: fd=%{public}d resp=%{public}@",
               log: log, type: .info, fd, String(describing: resp["data"] ?? ""))
    }
    #endif

    // MARK: - Stop

    override func stopTunnel(with reason: NEProviderStopReason,
                            completionHandler: @escaping () -> Void) {
        os_log("stopTunnel: reason=%{public}d", log: log, type: .info, reason.rawValue)
        #if canImport(LibXray)
        if running {
            try? lx(["apiVersion": 1, "method": "stopXray", "payload": [:]])
            running = false
        }
        #endif
        configJSON = nil
        serverID = nil
        completionHandler()
    }

    // MARK: - App ↔ extension сообщения (статистика/пинг)

    override func handleAppMessage(_ messageData: Data,
                                  completionHandler: ((Data?) -> Void)?) {
        #if canImport(LibXray)
        let text = String(data: messageData, encoding: .utf8) ?? ""
        if text.contains("\"method\":\"getXrayState\"") {
            if let resp = try? lx(["apiVersion": 1, "method": "getXrayState", "payload": [:]]),
               let data = try? JSONSerialization.data(withJSONObject: resp["data"] ?? [:]) {
                completionHandler?(data)
                return
            }
        }
        #endif
        let reply = "{\"server\":\"\(serverID ?? "")\",\"running\":\(running)}"
        completionHandler?(reply.data(using: .utf8))
    }

    override func sleep(completionHandler: @escaping () -> Void) { completionHandler() }
    override func wake() {}

    // MARK: - Сетевые настройки интерфейса

    private func makeTunnelSettings() -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: Net.tunnelRemoteAddress)
        let ipv4 = NEIPv4Settings(addresses: [Net.ipv4Address], subnetMasks: [Net.ipv4SubnetMask])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4
        // IPv6 — зеркало IPv4-блока: без ipv6Settings система пускала весь v6-трафик мимо
        // туннеля открытым текстом, пока UI показывал «Подключено».
        let ipv6 = NEIPv6Settings(addresses: [Net.ipv6Address],
                                  networkPrefixLengths: [Net.ipv6PrefixLength])
        ipv6.includedRoutes = [NEIPv6Route.default()]
        settings.ipv6Settings = ipv6
        // DNS общий для обоих стеков (matchDomains = [""] — резолв всего и только через туннель).
        let dns = NEDNSSettings(servers: Net.dnsServers)
        dns.matchDomains = [""]
        settings.dnsSettings = dns
        settings.mtu = 1500
        return settings
    }
}

#endif // canImport(NetworkExtension)
