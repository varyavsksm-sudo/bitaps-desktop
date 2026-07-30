// Единая точка входа к движку туннеля: контроллер подключения не должен знать, чем именно
// поднят туннель на этой платформе.
//
// Две реализации:
//   • ДЕСКТОП (Windows/macOS/Linux) — рядом лежащий xray-core как процесс + системный прокси.
//     xray понимает ВСЕ узлы подписки, включая «белый список» на транспорте xhttp.
//   • ANDROID — тот же xray, но внутри системного VpnService (плагин flutter_v2ray_client):
//     умеет все узлы, включая БС.
//   • iOS — нативной стороны пока нет (заглушка native_tunnel.dart): connect() честно падает
//     с TunnelUnavailable, БС недоступен.
// Если движка нет — честно говорим об этом, а не рисуем фейковое «подключено».

import 'dart:async';
import 'dart:io';

import 'android_engine.dart';
import 'desktop_engine.dart';
import 'native_tunnel.dart';
import 'singbox_config.dart';
import 'xray_config.dart';

/// Чем поднимаем туннель на этой платформе.
enum EngineKind {
  /// Процесс xray рядом с приложением (десктоп). Умеет все узлы, включая БС.
  desktopXray,

  /// xray внутри системного VpnService (Android). Тоже умеет все узлы, включая БС.
  androidXray,

  /// Нативная сторона платформы (iOS). Пока не подключена → без БС, connect() бросает.
  native,

  /// Движка нет — туннель поднять нечем.
  none,
}

/// Состояние туннеля для интерфейса.
class EngineEvent {
  final String state; // connected | disconnected | error
  final int upKbps;
  final int downKbps;
  final String? message;
  const EngineEvent(this.state, {this.upKbps = 0, this.downKbps = 0, this.message});
}

class TunnelEngine {
  TunnelEngine._();
  static final TunnelEngine instance = TunnelEngine._();

  XrayProcess? _proc;
  int? _metricsPort;
  /// Локальный HTTP-вход поднятого десктоп-туннеля: verifyConnected идёт ЧЕРЕЗ него —
  /// dart:io системный прокси на десктопе игнорирует, и прямой запрос мерил бы мимо туннеля.
  int? _activeHttpPort;
  Timer? _statsTimer;
  (int, int)? _lastTotals;
  final StreamController<EngineEvent> _events = StreamController<EngineEvent>.broadcast();

  Stream<EngineEvent> get events => _events.stream;

  /// Какой движок доступен ЗДЕСЬ И СЕЙЧАС (для десктопа — реально ли лежит бинарь).
  static EngineKind kind() {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      return XrayBinary.locate() != null ? EngineKind.desktopXray : EngineKind.none;
    }
    // На Android/iOS наличие нативной стороны проверяется только попыткой вызова —
    // считаем, что она есть, и честно падаем с TunnelUnavailable, если нет.
    if (Platform.isAndroid) return EngineKind.androidXray;
    // iOS: нативная сторона (NetworkExtension) — её ещё предстоит собрать владельцу.
    if (Platform.isIOS) return EngineKind.native;
    return EngineKind.none;
  }

  /// Узлы, которые движок этой платформы реально умеет поднять. У xray — любые,
  /// у sing-box — только те, чей транспорт он понимает (xhttp «белого списка» он не умеет).
  static List<SubNode> usableNodes(List<SubNode> all) =>
      supportsWhitelist ? all : [for (final n in all) if (n.singboxReady) n];

  /// Доступен ли узел «белого списка» (xhttp) на этой платформе.
  static bool get supportsWhitelist =>
      kind() == EngineKind.desktopXray || kind() == EngineKind.androidXray;

  /// Спросить у системы разрешение на VPN — ДО начала отсчёта таймаута подключения.
  ///
  /// Раньше запрос жил внутри connect(), а connect() был обёрнут таймаутом в 40 секунд: пока
  /// человек читал системный диалог «разрешить VPN», таймаут тикал. Кто читал дольше, получал
  /// «Подключение не удалось — таймаут» и при этом ЖИВОЙ туннель, поднявшийся сразу после
  /// разрешения: ключ в шторке есть, а интерфейс говорит «Отключено». Ровно на это и жаловались.
  ///
  /// true — разрешение есть (или платформе оно не нужно), false — человек отказался.
  Future<bool> ensurePermission() async {
    if (kind() == EngineKind.androidXray) return _android.requestPermission();
    return true;
  }

  /// Поднять туннель по узлам подписки. [onlyTag] — если пользователь выбрал сервер вручную.
  /// Бросает [EngineUnavailable] / [TunnelUnavailable] с текстом для пользователя.
  Future<void> connect(List<SubNode> nodes, {String? onlyTag, String server = ''}) async {
    final usable = usableNodes(nodes);
    if (usable.isEmpty) {
      throw EngineUnavailable('в подписке нет узлов, поддерживаемых этой сборкой');
    }
    switch (kind()) {
      case EngineKind.desktopXray:
        await _connectDesktop(usable, onlyTag);
        return;
      case EngineKind.androidXray:
        await _connectAndroid(usable, onlyTag, server);
        return;
      case EngineKind.native:
        // Нативной стороне отдаём конфиг xray с tun-входом (движок — libXray в расширении).
        await NativeTunnel.connect(xrayConfigJsonForIos(usable), server: server);
        return;
      case EngineKind.none:
        throw EngineUnavailable('VPN-движок не установлен в этой сборке');
    }
  }

  Future<void> _connectDesktop(List<SubNode> nodes, String? onlyTag) async {
    await _stopDesktop(); // повторный connect не должен плодить процессы
    final bin = XrayBinary.locate();
    if (bin == null) throw EngineUnavailable('VPN-движок не найден в сборке');
    // Порты берём свободные: фиксированные конфликтуют со вторым запуском и чужими клиентами.
    final socksPort = await _freePort();
    final httpPort = await _freePort();
    final metricsPort = await _freePort();
    final cfg = xrayConfigJsonFromNodes(nodes,
        only: onlyTag, socksPort: socksPort, httpPort: httpPort, metricsPort: metricsPort);
    final proc = await XrayProcess.start(cfg, socksPort: socksPort, binaryPath: bin);
    final proxyOk = await SystemProxy.enable(socksPort: socksPort, httpPort: httpPort);
    if (!proxyOk) {
      // Прокси мог встать частично (на части сервисов/платформы) — снимаем ДО остановки
      // движка, иначе система остаётся с указателем в порт, который сейчас умрёт.
      try { await SystemProxy.disable(); } catch (_) {/* при откате ошибки глотаем */}
      await proc.stop();
      throw EngineUnavailable('не удалось включить системный прокси');
    }
    _proc = proc;
    _metricsPort = metricsPort;
    _activeHttpPort = httpPort;
    _lastTotals = null;
    _events.add(const EngineEvent('connected'));
    // Реальные счётчики движка раз в секунду → скорость в интерфейсе.
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) => _pollStats());
  }

  /// Пинги узлов из последнего замера движка (тег outbound'а → мс; null — узел не отвечает).
  Map<String, int?> nodePings = const {};

  final AndroidXrayEngine _android = AndroidXrayEngine();

  /// Узел, к которому подключаемся на Android. Один — не список: движок там получает готовый
  /// конфиг записи подписки (см. xrayEntryConfigJson).
  SubNode _pickAndroidNode(List<SubNode> nodes, String? onlyTag) {
    if (onlyTag != null) {
      final hit = nodes.where((n) => n.tag == onlyTag);
      if (hit.isNotEmpty) return hit.first;
      throw const FormatException('выбранный сервер отсутствует в подписке');
    }
    // Авто: первый прямой узел (у прямых отклик заведомо ниже, чем у узлов через CDN),
    // иначе просто первый. Пер-узловых замеров на Android нет: конфиг подписки метрик не
    // несёт, а serverDelay живёт на временном экземпляре и результаты сюда не пишет.
    final direct = nodes.where((n) => n.singboxReady);
    return direct.isNotEmpty ? direct.first : nodes.first;
  }

  Future<void> _connectAndroid(List<SubNode> nodes, String? onlyTag, String server) async {
    if (nodes.isEmpty) {
      throw const FormatException('в подписке нет узлов для подключения');
    }
    // Отдаём движку конфиг ОДНОГО узла — ровно тот, что приходит в подписке и работает в
    // сторонних клиентах. Собственная сборка со всеми узлами, балансировщиком и метриками
    // внутри системного VpnService поднимала туннель, но трафик через него не шёл.
    final node = _pickAndroidNode(nodes, onlyTag);
    // Свой порт локального входа: 10808 занимают Happ и v2rayNG, и тогда наш движок не может
    // его открыть — туннель поднимается пустым.
    final cfg = xrayEntryConfigJson(node, socksPort: kXrayAndroidSocksPort);
    await _android.connect(
      cfg,
      remark: server.isEmpty ? node.remark : server,
      onState: (state) {
        // «connected» и «connecting» наверх не поднимаем: о подключении сообщаем сами ниже,
        // а «connecting» контроллер принял бы за обрыв и погасил бы туннель.
        if (state == 'connected' || state == 'connecting') return;
        // Туннель отвалился — вытаскиваем причину из лога движка. Без неё «подключился и сразу
        // отключился» выглядит одинаково для занятого порта, отказа узла и битого конфига,
        // и разбираться приходится вслепую.
        _android.lastError().then((why) {
          _events.add(EngineEvent(state, message: why));
        }, onError: (_) => _events.add(EngineEvent(state)));
      },
    );
    // Метрик на Android больше нет: конфиг подписки их не содержит, а добавлять свои значит
    // снова отойти от проверенного. Счётчики скорости на этой платформе не показываем.
    _metricsPort = null;
    _lastTotals = null;
    _events.add(const EngineEvent('connected'));
  }

  Future<void> _pollStats() async {
    final port = _metricsPort;
    // Статистика есть только на десктопе: метрики поднимает наш процесс xray. На Android
    // конфиг подписки метрик не содержит, порт всегда null — счётчиков скорости там нет.
    if (port == null || (kind() == EngineKind.desktopXray && _proc == null)) return;
    final r = await XrayStats.read(port);
    if (r == null) return;
    nodePings = r.pings;
    final prev = _lastTotals;
    _lastTotals = (r.up, r.down);
    if (prev == null) return;
    // байты за секунду → килобиты в секунду (интерфейс ждёт kbps, см. connection.dart)
    final up = ((r.up - prev.$1) * 8 / 1000).round();
    final down = ((r.down - prev.$2) * 8 / 1000).round();
    _events.add(EngineEvent('connected', upKbps: up < 0 ? 0 : up, downKbps: down < 0 ? 0 : down));
  }

  Future<void> disconnect() async {
    switch (kind()) {
      case EngineKind.native:
        await NativeTunnel.disconnect();
        return;
      case EngineKind.androidXray:
        _statsTimer?.cancel();
        _statsTimer = null;
        _metricsPort = null;
        _lastTotals = null;
        await _android.disconnect();
        return;
      case EngineKind.desktopXray:
      case EngineKind.none:
        await _stopDesktop();
        return;
    }
  }

  Future<void> _stopDesktop() async {
    _statsTimer?.cancel();
    _statsTimer = null;
    // Системный прокси снимаем ПЕРВЫМ: если упасть между шагами, лучше остаться без прокси,
    // чем с прокси в уже мёртвый порт (иначе у пользователя пропадёт интернет).
    await SystemProxy.disable();
    final p = _proc;
    _proc = null;
    _metricsPort = null;
    _activeHttpPort = null;
    _lastTotals = null;
    if (p != null) await p.stop();
  }

  /// Свободный локальный порт (нужен и проверке узлов, поэтому не приватный).
  static Future<int> freePort() => _freePort();

  // ── ПРОВЕРКА УЗЛА: пропускает ли он трафик С ЭТОГО УСТРОЙСТВА ──
  //
  // Смысл: поднять временный экземпляр движка ровно на один узел и вытянуть сквозь него
  // маленький ответ из сети. Дошло — узел настоящий, и число это честное время ответа
  // СКВОЗЬ туннель. Не дошло — узел непригоден, сколько бы его порт ни отвечал на TCP.
  //
  // Что тянем. Свой /gen204 — основной: всегда живой и отдаёт пустой ответ, то есть проверка
  // стоит доли килобайта. Второй адрес независимый: если наш ориджин прилёг, нельзя объявлять
  // непригодными все узлы разом.
  static const List<String> probeUrls = [
    'https://origin.bit-core.online/gen204',
    'https://cp.cloudflare.com/generate_204',
  ];
  // Реальные узлы отвечают за 0.3–1.5 с. Шесть секунд — это уже не «медленно», а «не работает».
  static const Duration probeTimeout = Duration(seconds: 6);

  /// Время ответа сквозь узел в мс, либо null — трафик не пошёл. Никогда не бросает:
  /// непригодный узел это результат проверки, а не сбой приложения.
  Future<int?> probe(SubNode node) async {
    try {
      switch (kind()) {
        case EngineKind.androidXray:
          return await _probeAndroid(node);
        case EngineKind.desktopXray:
          return await _probeDesktop(node);
        case EngineKind.native:
        case EngineKind.none:
          return null; // проверять нечем — выдумывать «работает» нельзя
      }
    } catch (_) {
      return null;
    }
  }

  /// Идёт ли трафик сквозь УЖЕ ПОДНЯТЫЙ туннель. Отдельно от [probe]: там временный экземпляр
  /// на конкретный узел, здесь — тот самый туннель, которым сейчас пользуется человек.
  /// Нужна потому, что «подключено» и «работает» — разные вещи: движок поднимается и рапортует
  /// об успехе, а сессию сквозь фильтрацию рвёт, и человек сидит с зелёной кнопкой без интернета.
  Future<bool> verifyConnected() async {
    // Два круга по тем же причинам, что и в probe: рвать человеку рабочее подключение из-за
    // одной не дошедшей проверки нельзя — это было бы хуже, чем не проверять вовсе.
    for (var round = 0; round < 2; round++) {
      if (round > 0) await Future<void>.delayed(const Duration(milliseconds: 700));
      if (await _verifyOnce()) return true;
    }
    return false;
  }

  Future<bool> _verifyOnce() async {
    for (final url in probeUrls) {
      try {
        if (kind() == EngineKind.androidXray) {
          final ms = await _android.connectedDelay(url).timeout(probeTimeout);
          if (ms > 0) return true;
          continue;
        }
        // Десктоп: системный прокси для dart:io не существует (HttpClient его игнорирует) —
        // прямой запрос измерял бы НАШУ сеть, а не туннель. Идём через локальный HTTP-вход
        // поднятого движка, как в _probeDesktop; порта нет (не должно быть) — прямой запрос.
        final client = HttpClient()..connectionTimeout = probeTimeout;
        final httpPort = kind() == EngineKind.desktopXray ? _activeHttpPort : null;
        if (httpPort != null) client.findProxy = (_) => 'PROXY 127.0.0.1:$httpPort';
        try {
          final req = await client.getUrl(Uri.parse(url)).timeout(probeTimeout);
          final res = await req.close().timeout(probeTimeout);
          await res.drain<void>();
          if (res.statusCode < 400) return true;
        } finally {
          client.close(force: true);
        }
      } catch (_) { /* следующий адрес */ }
    }
    return false;
  }

  Future<int?> _probeAndroid(SubNode node) async {
    final cfg = xrayEntryConfigJson(node, socksPort: kXrayProbeSocksPort);
    // Две попытки, а не одна. Проверено на живом прогоне: при холодном старте и загруженном
    // устройстве рабочий узел иногда не укладывается в таймаут, и с одного раза его записали бы
    // в непригодные — а потом человек видел бы «не работает» у сервера, который работает.
    // Хоронить узел можно только по ПОДТВЕРЖДЁННОЙ неудаче.
    for (var round = 0; round < 2; round++) {
      if (round > 0) await Future<void>.delayed(const Duration(milliseconds: 700));
      for (final url in probeUrls) {
        try {
          final ms = await _android.serverDelay(cfg, url).timeout(probeTimeout);
          if (ms > 0) return ms;
        } catch (_) { /* следующий адрес */ }
      }
    }
    return null;
  }

  // На десктопе движок наш собственный: поднимаем процесс на один узел с локальным ВХОДОМ HTTP
  // (HttpClient умеет http-прокси, socks — нет) и тянем канарейку через него.
  Future<int?> _probeDesktop(SubNode node) async {
    final bin = XrayBinary.locate();
    if (bin == null) return null;
    final socksPort = await _freePort();
    final httpPort = await _freePort();
    XrayProcess? proc;
    final client = HttpClient()
      ..connectionTimeout = probeTimeout
      ..findProxy = (_) => 'PROXY 127.0.0.1:$httpPort';
    try {
      final cfg = xrayConfigJsonFromNodes([node], only: node.tag, socksPort: socksPort, httpPort: httpPort);
      proc = await XrayProcess.start(cfg, socksPort: socksPort, binaryPath: bin);
      for (final url in probeUrls) {
        final sw = Stopwatch()..start();
        try {
          final req = await client.getUrl(Uri.parse(url)).timeout(probeTimeout);
          final res = await req.close().timeout(probeTimeout);
          await res.drain<void>();
          sw.stop();
          if (res.statusCode < 400) return sw.elapsedMilliseconds.clamp(1, 99999);
        } catch (_) { /* следующий адрес */ }
      }
      return null;
    } finally {
      client.close(force: true);
      await proc?.stop();
    }
  }

  static Future<int> _freePort() async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = s.port;
    await s.close();
    return port;
  }
}
