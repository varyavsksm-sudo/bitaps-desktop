import Flutter
import UIKit
import NetworkExtension

/// Мост Dart ↔ NetworkExtension.
/// Контракт канала (lib/native_tunnel.dart):
///   MethodChannel('app.bitaps.vpn/control'): 'connect' {config, server}, 'disconnect'.
///   EventChannel('app.bitaps.vpn/events'):   {state, down, up}.
/// Конфиг для движка кладём в App Group UserDefaults — оттуда его читает PacketTunnelProvider.
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

    // MARK: - connect: конфиг в App Group + старт менеджера

    private func connect(config: String, server: String, result: @escaping FlutterResult) {
        guard !config.isEmpty else {
            result(FlutterError(code: "bad_args", message: "пустой конфиг", details: nil))
            return
        }
        let ud = UserDefaults(suiteName: appGroup)
        ud?.set(config, forKey: "xray_config_json")
        ud?.set(server, forKey: "xray_server_id")
        ud?.set(Date().timeIntervalSince1970, forKey: "xray_config_at")

        loadManager { [weak self] error in
            guard let self else { return }
            if let error {
                result(FlutterError(code: "manager", message: error.localizedDescription, details: nil))
                return
            }
            do {
                try self.manager.connection.startVPNTunnel(options: [:])
                self.startedOnce = true
                result(nil)
                self.emitState("connected")
            } catch {
                result(FlutterError(code: "start", message: error.localizedDescription, details: nil))
            }
        }
    }

    private func disconnect(result: @escaping FlutterResult) {
        manager.connection.stopVPNTunnel()
        emitState("disconnected")
        result(nil)
    }

    // MARK: - NETunnelProviderManager

    private func loadManager(_ done: @escaping (Error?) -> Void) {
        // Наш провайдер — локальный (extension в этом же пакете), конфиг читается из App Group.
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = "com.bitapsvpn.bitapsVpn.PacketTunnel"
        proto.serverAddress = "bitaps VPN"
        manager.localizedDescription = "bitaps VPN"
        manager.protocolConfiguration = proto
        manager.isEnabled = true
        manager.saveToPreferences { error in
            if error == nil { self.manager.loadFromPreferences(completionHandler: done) } else { done(error) }
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
