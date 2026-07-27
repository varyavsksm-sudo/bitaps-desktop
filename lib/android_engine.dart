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
  String _state = 'disconnected'; // последнее состояние от плагина
  /// Видели ли «подключено» в ТЕКУЩЕЙ попытке. До этого момента «отключено» — не обрыв.
  bool _sawConnected = false;

  /// Плагин и его инициализация. Нужны и для остановки тоже: туннель переживает закрытие
  /// приложения, и после нового запуска остановить его иначе было бы нечем — VPN оставался
  /// висеть в системе, а подключиться заново не давал.
  Future<V2ray> _engine() async {
    final v = _v2ray ??= V2ray(onStatusChanged: (s) {
      _state = _mapState(s.state);
      if (_state == 'connected') _sawConnected = true;
      // «Отключено» ДО первого «подключено» наверх не поднимаем.
      //
      // Плагин рассылает состояние широковещательно и с задержкой. Перед стартом нового
      // туннеля мы гасим прежний — и его «отключено» прилетает уже после того, как новый
      // поднялся. Приложение принимало это за обрыв и тут же убивало свежее подключение:
      // в логе ядра было видно «core started» и через 50 мс «core stopped». Снаружи это
      // выглядело как «подключается и сразу отключается».
      if (!_sawConnected && (_state == 'disconnected' || _state == 'error')) return;
      _onState?.call(_state);
    });
    if (!_initialized) {
      await v.initialize();
      _initialized = true;
    }
    return v;
  }

  /// Системный диалог «разрешить VPN» отдельным шагом — чтобы время на раздумье не съедало
  /// таймаут подключения (см. TunnelEngine.ensurePermission).
  Future<bool> requestPermission() async => (await _engine()).requestPermission();

  /// Поднять туннель. [remark] попадает в системное уведомление Android.
  Future<void> connect(
    String configJson, {
    required String remark,
    required void Function(String state) onState,
  }) async {
    final v = await _engine();
    // Разрешение спрашиваем ещё раз: обычно оно уже получено в ensurePermission() до отсчёта
    // таймаута и этот вызов возвращается мгновенно, но connect() должен оставаться безопасным
    // и при прямом вызове. Отказ — не сбой движка, а осознанное решение человека.
    final allowed = await v.requestPermission();
    if (!allowed) {
      throw EngineUnavailable('нужно разрешить приложению создавать VPN-подключение');
    }
    // Гасим прошлый туннель ДО старта нового. Плагин применяет новый конфиг только на
    // поднятие сервиса: без остановки смена сервера молча оставляла работать прежний.
    // Слушателя подключаем после остановки, чтобы её события не приняли за обрыв нового.
    _onState = null;
    await _stop(v);
    _sawConnected = false; // новая попытка: «отключено» до «подключено» снова не считается обрывом
    _onState = onState;
    await v.startV2Ray(
      remark: remark,
      config: configJson,
      notificationDisconnectButtonName: 'Отключить',
    );
  }

  Future<void> disconnect() async {
    _onState = null; // события собственной остановки наверх не поднимаем
    await _stop(await _engine());
  }

  /// Остановить туннель и дождаться, пока плагин это подтвердит. Без ожидания следующий
  /// старт мог прийти в ещё живой сервис — тогда он игнорировал новый конфиг.
  Future<void> _stop(V2ray v) async {
    _sawConnected = false;
    await v.stopV2Ray();
    for (var i = 0; i < 30 && _state != 'disconnected'; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    _state = 'disconnected';
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

  /// Понятная причина отказа из лога ядра, или null — если ничего внятного нет.
  ///
  /// Самая частая причина на телефоне — занятый локальный порт: рядом стоит другой клиент на
  /// xray. Ядро пишет про это «address already in use», но человеку такая строка ничего не
  /// говорит, поэтому переводим её в понятную фразу. Остальные ошибки отдаём как есть —
  /// пусть лучше будет техническая строка, чем молчание.
  Future<String?> lastError() async {
    final lines = await logs();
    for (final l in lines.reversed) {
      final s = l.trim();
      if (s.isEmpty) continue;
      final low = s.toLowerCase();
      if (low.contains('address already in use') || low.contains('bind: ')) {
        return 'локальный порт занят другим VPN-приложением — закройте его и попробуйте снова';
      }
      if (low.contains('failed to') || low.contains('error') || low.contains('panic')) {
        return s.length > 160 ? s.substring(0, 160) : s;
      }
    }
    return null;
  }

  /// Состояния плагина (V2RAY_CONNECTED / V2RAY_DISCONNECTED / V2RAY_CONNECTING) → словарь
  /// контроллера подключения.
  ///
  /// «CONNECTING» обязан иметь СВОЁ значение. Раньше он не подходил ни под одно условие и
  /// сваливался в «disconnected», а контроллер считает это обрывом и гасит туннель — то есть
  /// приложение убивало собственное подключение в момент его установления.
  String _mapState(String raw) {
    final s = raw.toUpperCase();
    if (s.contains('CONNECTING')) return 'connecting';
    if (s.contains('CONNECTED') && !s.contains('DIS')) return 'connected';
    if (s.contains('ERROR')) return 'error';
    return 'disconnected';
  }
}
