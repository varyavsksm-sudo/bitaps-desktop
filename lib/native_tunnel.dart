import 'dart:async';
import 'package:flutter/services.dart';

/// Мост к НАСТОЯЩЕМУ нативному VPN-движку (sing-box) через MethodChannel/EventChannel.
///
/// Туннель живёт в платформенном коде, здесь — только контракт вызова:
///   • Apple (iOS/macOS): NetworkExtension PacketTunnelProvider + Libbox.xcframework.
///     Готовая реализация уже есть — ~/bitaps-vpn-app/PacketTunnel (startOrReloadService
///     на переданном конфиге) + собранный движок ~/bitaps-libbox/Libbox.xcframework.
///     Её нужно подключить как extension-таргет к этому раннеру (Xcode + App Group + подпись).
///   • Android: VpnService + libbox (gomobile .aar) — тот же конфиг.
///   • Windows/Linux: процесс sing-box + wintun/tun.
///
/// Пока нативная сторона на платформе НЕ подключена, connect() бросает [TunnelUnavailable] —
/// UI показывает честную ошибку и НЕ рисует фейковое «Подключено». Никаких выдуманных
/// скорости/IP: цифры приходят только из реального движка через [events].
enum TunnelState { disconnected, connecting, connected, error }

/// Движок не установлен/недоступен на этой платформе — туннель поднять нечем.
class TunnelUnavailable implements Exception {
  final String message;
  TunnelUnavailable(this.message);
  @override
  String toString() => message;
}

class NativeTunnel {
  static const MethodChannel _ctrl = MethodChannel('app.bitaps.vpn/control');
  static const EventChannel _evt = EventChannel('app.bitaps.vpn/events');

  /// Запустить туннель на готовом sing-box конфиге (JSON). Возвращает при успешном старте.
  /// Бросает [TunnelUnavailable], если движок не установлен (нет нативного канала) или отказал.
  static Future<void> connect(String configJson, {String server = ''}) async {
    try {
      await _ctrl.invokeMethod('connect', {'config': configJson, 'server': server});
    } on MissingPluginException {
      throw TunnelUnavailable('VPN-движок ещё не установлен в этой сборке');
    } on PlatformException catch (e) {
      throw TunnelUnavailable(e.message ?? 'Не удалось запустить туннель');
    }
  }

  /// Остановить туннель. При отсутствии движка/уже отключённом — тихо ничего не делает.
  static Future<void> disconnect() async {
    try {
      await _ctrl.invokeMethod('disconnect');
    } on MissingPluginException {
      /* движка нет — уже «отключены» */
    } on PlatformException {
      /* при отключении ошибки глотаем */
    }
  }

  /// Поток статуса/статистики ИЗ реального движка: {state, down, up} (down/up — kbps).
  /// Если нативного канала нет — поток просто пуст (ошибки MissingPlugin гасим).
  static Stream<Map<String, dynamic>> events() {
    return _evt.receiveBroadcastStream().map<Map<String, dynamic>>(
      (e) => e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{},
    // Гасим ТОЛЬКО MissingPluginException (нет нативной стороны). Настоящие ошибки канала
    // (смерть процесса движка) пропускаем дальше — их ловит onError в connection.dart и
    // честно роняет туннель, иначе UI навсегда завис бы в «Подключено».
    ).handleError((_) {}, test: (e) => e is MissingPluginException);
  }
}
