import 'dart:async';
import 'package:flutter/services.dart';

/// Мост к нативному VPN-движку через MethodChannel/EventChannel — LEGACY-контракт, оставлен
/// под iOS (NetworkExtension). Десктоп и Android работают на xray (engine.dart /
/// android_engine.dart) и сюда не ходят.
///
/// Туннель живёт в платформенном коде, здесь — только контракт вызова:
///   • iOS: NetworkExtension PacketTunnelProvider + libXray (LibXray.xcframework, Xray-core):
///     вызовы — через Invoke(runXrayFromJson), utun-fd движку — в env["xray.tun.fd"].
///     Реализация — native_ios/ (AppDelegate.swift + PacketTunnel/), накатывается поверх
///     сгенерированного ios/ (см. native_ios/README-IOS.md и CI build.yml, job ios).
///   • Windows/Linux/Android: НЕ используется — там engine.dart (xray).
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

  /// Запустить туннель на готовом конфиге движка (JSON, см. xray_config.dart). Возвращает при успешном старте.
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
