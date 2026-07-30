import Flutter
import UIKit
import NetworkExtension

/// Мост Dart ↔ NetworkExtension.
/// Контракт канала (lib/native_tunnel.dart):
///   MethodChannel('app.bitaps.vpn/control'): 'connect' {config, server}, 'disconnect'.
///   EventChannel('app.bitaps.vpn/events'):   {state, down, up}.
/// Конфиг для движка кладём ФАЙЛОМ в App Group-контейнер (NSFileProtectionComplete, атомарная
/// запись) — оттуда его читает PacketTunnelProvider. Статусы эмитим ТОЛЬКО по факту
/// NEVPNStatusDidChange: start/stopVPNTunnel — лишь запросы системе, а не смена состояния.
@main
@objc class AppDelegate: FlutterAppDelegate {

    private let appGroup = "group.com.bitapsvpn.bitapsVpn"
    private var eventsSink: FlutterEventSink?
    private let manager = NETunnelProviderManager()
    private var startedOnce = false

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        // Наследие старых версий: конфиг (UUID/ключи узлов) раньше лежал plaintext в
        // App Group UserDefaults бессрочно — сносим при запуске (теперь это файл, см. writeConfig).
        purgeLegacyDefaults()

        // Реальный статус туннеля → EventChannel. Раньше «connected» эмитился сразу после
        // startVPNTunnel (это лишь ЗАПРОС системе): при падении extension UI врал «Подключено»,
        // а трафик шёл мимо туннеля. Теперь — только факт от системы (vpnStatusDidChange).
        NotificationCenter.default.addObserver(self, selector: #selector(vpnStatusDidChange(_:)),
                                               name: NSNotification.Name.NEVPNStatusDidChange,
                                               object: nil)

        guard let controller = window?.rootViewController as? FlutterViewController else {
            return super.application(application, didFinishLaunchingWithOptions: launchOptions)
        }

        let ctrl = FlutterMethodChannel(name: "app.bitaps.vpn/control", binaryMessenger: controller.binaryMessenger)
        ctrl.setMethodCallHandler { [weak self] call, result in
            guard let self else { return }
            switch call.method {
            case "connect":
                let args = call.arguments as? [String: Any]
                let config = args?["config"] as? String ?? ""
                let server = args?["server"] as? String ?? ""
                self.connect(config: config, server: server, result: result)
            case "disconnect":
                self.disconnect(result: result)
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        let evt = FlutterEventChannel(name: "app.bitaps.vpn/events", binaryMessenger: controller.binaryMessenger)
        evt.setStreamHandler(self)

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    deinit {
        // Парно к addObserver при запуске — без снятия подписки NotificationCenter
        // продолжал бы слать нотификации освобождённому объекту.
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - connect: конфиг в App Group (файл) + старт менеджера

    private func connect(config: String, server: String, result: @escaping FlutterResult) {
        guard !config.isEmpty else {
            result(FlutterError(code: "bad_args", message: "пустой конфиг", details: nil))
            return
        }
        do {
            try writeConfig(config: config, server: server)
        } catch {
            result(FlutterError(code: "config_io", message: error.localizedDescription, details: nil))
            return
        }

        loadManager { [weak self] error in
            guard let self else { return }
            if let error {
                result(FlutterError(code: "manager", message: error.localizedDescription, details: nil))
                return
            }
            do {
                try self.manager.connection.startVPNTunnel(options: [:])
                self.startedOnce = true
                // Никакого emitState("connected") здесь: startVPNTunnel — лишь ЗАПРОС системе,
                // реальный статус придёт нотификацией → vpnStatusDidChange.
                result(nil)
            } catch {
                result(FlutterError(code: "start", message: error.localizedDescription, details: nil))
            }
        }
    }

    private func disconnect(result: @escaping FlutterResult) {
        manager.connection.stopVPNTunnel()
        // Ключи узлов не должны переживать сессию — файл конфига удаляем сразу.
        wipeConfig()
        // Событие обрыва тоже придёт от системы (.disconnecting/.disconnected → "disconnected").
        result(nil)
    }

    // MARK: - Конфиг: файл в App Group-контейнере вместо UserDefaults

    /// Файл-конверт с конфигом в общем контейнере (доступен и приложению, и extension).
    private var configFileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("xray_config.json")
    }

    /// Атомарная запись (temp+rename) под NSFileProtectionComplete: UUID/ключи узлов не лежат
    /// plaintext в UserDefaults, а гонки «app пишет / extension читает» нет — читатель видит
    /// версию целиком. write() синхронный и завершается ДО startVPNTunnel, отдельный flush не
    /// нужен; extension сверяет xray_config_at с моментом своего старта (просрочен >10 c → отказ).
    private func writeConfig(config: String, server: String) throws {
        guard let url = configFileURL else {
            throw NSError(domain: "bitaps.AppDelegate", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "App Group-контейнер недоступен (проверь entitlements)"
            ])
        }
        let envelope: [String: Any] = [
            "xray_config_json": config,
            "xray_server_id": server,
            "xray_config_at": Date().timeIntervalSince1970,
        ]
        let data = try JSONSerialization.data(withJSONObject: envelope)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    /// Удаляем файл конфига + заодно чистим ключи эпохи UserDefaults-хранилища.
    private func wipeConfig() {
        if let url = configFileURL { try? FileManager.default.removeItem(at: url) }
        purgeLegacyDefaults()
    }

    /// У обновлённых установок старый plaintext в App Group UserDefaults остался бы навсегда.
    private func purgeLegacyDefaults() {
        let ud = UserDefaults(suiteName: appGroup)
        ud?.removeObject(forKey: "xray_config_json")
        ud?.removeObject(forKey: "xray_server_id")
        ud?.removeObject(forKey: "xray_config_at")
    }

    // MARK: - NETunnelProviderManager

    private func loadManager(_ done: @escaping (Error?) -> Void) {
        // Наш провайдер — локальный (extension в этом же пакете), конфиг читается из App Group.
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = "com.bitapsvpn.bitapsVpn.PacketTunnel"
        proto.serverAddress = "bitaps VPN"
        // Без includeAllNetworks при падении extension система молча пускала бы трафик мимо
        // туннеля (kill switch, iOS 14+). excludeLocalNetworks не трогаем — не выставлен и не нужен.
        if #available(iOS 14.0, *) { proto.includeAllNetworks = true }
        manager.localizedDescription = "bitaps VPN"
        manager.protocolConfiguration = proto
        manager.isEnabled = true
        manager.saveToPreferences { error in
            if error == nil { self.manager.loadFromPreferences(completionHandler: done) } else { done(error) }
        }
    }

    /// Единственный источник правды о состоянии туннеля — нотификация системы.
    /// Dart-сторона (connection.dart) понимает 'connected' и обрыв — 'disconnected'/'error'.
    @objc private func vpnStatusDidChange(_ note: Notification) {
        // Нотификации чужих VPN тоже прилетают, а фильтр по note.object ненадёжен (после
        // loadFromPreferences identity connection меняется). Поэтому на ЛЮБУЮ нотификацию
        // эмитим реальный статус НАШЕГО connection — наврать здесь нечему.
        switch manager.connection.status {
        case .connected:
            emitState("connected")
        case .connecting, .reasserting:
            emitState("connecting")
        case .disconnecting, .disconnected:
            emitState("disconnected")
        case .invalid:
            break // конфигурация ещё не загружена или уже удалена — эмитить нечего
        @unknown default:
            break
        }
    }

    private func emitState(_ state: String) {
        DispatchQueue.main.async { [weak self] in
            self?.eventsSink?(["state": state, "down": 0, "up": 0])
        }
    }
}

// MARK: - FlutterStreamHandler

extension AppDelegate: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventsSink = events
        return nil
    }
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventsSink = nil
        return nil
    }
}
