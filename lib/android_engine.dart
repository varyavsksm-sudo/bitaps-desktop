// Движок туннеля для ANDROID: xray-core внутри системного VpnService.
//
// Почему так: на Android нельзя просто запустить процесс — трафик всей системы забирает
// VpnService, а он живёт в платформенном коде. Плагин flutter_v2ray_client несёт готовый
// VpnService со встроенным xray-core и принимает СЫРОЙ xray-конфиг — ровно тот, что мы
// собираем в xray_config.dart. Значит на Android доступны ВСЕ узлы подписки, включая
// «белый список» на транспорте xhttp (в sing-box такого транспорта нет вообще).
//
// Плагин используем только как оболочку VpnService: состояние берём из его колбэка, а
// счётчики и задержки узлов читаем сами из метрик движка (см. XrayStats) — счётчики плагина
// считают тег «proxy», которого при балансировщике не существует, и всегда показывали бы ноль.

import 'package:flutter_v2ray_client/flutter_v2ray.dart';

import 'desktop_engine.dart' show EngineUnavailable;

class AndroidXrayEngine {
  V2ray? _v2ray;
  bool _initialized = false;
  void Function(String state)? _onState;

  /// Поднять туннель. [remark] попадает в системное уведомление Android.
  Future<void> connect(
    String configJson, {
    required String remark,
    required void Function(String state) onState,
  }) async {
    _onState = onState;
    _v2ray ??= V2ray(onStatusChanged: (s) => _onState?.call(_mapState(s.state)));
    if (!_initialized) {
      await _v2ray!.initialize();
      _initialized = true;
    }
    // Системный диалог «разрешить VPN». Пользователь может отказаться — это не сбой движка,
    // а осознанный отказ: говорим об этом прямо, без «не удалось подключиться».
    final allowed = await _v2ray!.requestPermission();
    if (!allowed) {
      throw EngineUnavailable('нужно разрешить приложению создавать VPN-подключение');
    }
    await _v2ray!.startV2Ray(
      remark: remark,
      config: configJson,
      notificationDisconnectButtonName: 'Отключить',
    );
  }

  Future<void> disconnect() async {
    await _v2ray?.stopV2Ray();
  }

  /// Версия ядра внутри плагина — для экрана самодиагностики.
  Future<String> coreVersion() async {
    try {
      return await (_v2ray ??= V2ray(onStatusChanged: (_) {})).getCoreVersion();
    } catch (_) {
      return '';
    }
  }

  /// Последние строки лога ядра — чтобы ошибка подключения была диагностируемой.
  Future<List<String>> logs() async {
    try {
      return await (_v2ray ??= V2ray(onStatusChanged: (_) {})).getLogs();
    } catch (_) {
      return const [];
    }
  }

  /// Состояния плагина («CONNECTED»/«DISCONNECTED»/…) → словарь контроллера подключения.
  String _mapState(String raw) {
    final s = raw.toUpperCase();
    if (s.contains('CONNECTED') && !s.contains('DIS')) return 'connected';
    if (s.contains('ERROR')) return 'error';
    return 'disconnected';
  }
}
