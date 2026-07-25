// Генератор sing-box конфигурации из share-link ключа (vpn_key, который выдаёт бот) —
// ФУНДАМЕНТ боевого туннеля единой кодовой базы. Порт богатого Swift-генератора
// (SingBoxConfig.swift): поддерживает vless:// (в т.ч. Reality), vmess://, trojan://,
// ss://, hysteria2://. Чистые функции без сайд-эффектов, юнит-тестируемо.
//
// Отличия от старого тонкого vless.dart: 5 протоколов вместо одного, режимы роутинга
// (global/rules/direct), новый формат DNS/route (sing-box 1.11+), geo-RU + ad-block rule-sets.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Схемы share-link, которые умеет разобрать [outboundFromKey] — единый источник
/// правды для гарда подключения (connection.dart), чтобы он не отставал от парсера.
const List<String> kSupportedKeySchemes = [
  'vless://', 'trojan://', 'vmess://', 'ss://', 'hysteria2://', 'hy2://',
];

/// Политика роутинга для генерируемого конфига.
enum Routing {
  global, // всё через прокси
  rules, // умный: RU + приватные адреса напрямую, остальное через прокси
  direct, // байпас (debug): всё напрямую
}

/// Полный sing-box конфиг из ключа. Бросает [FormatException], если ключ не разобрать
/// (совместимо со старым vless.dart, который тоже кидал FormatException).
Map<String, dynamic> singboxConfig(
  String key, {
  Routing routing = Routing.rules,
  String remoteDns = 'https://1.1.1.1/dns-query',
  String directDns = '8.8.8.8',
  int mtu = 9000,
}) {
  final outbound = outboundFromKey(key.trim());
  if (outbound == null) {
    throw const FormatException('не удалось разобрать ключ');
  }
  return {
    'log': {'level': 'warn', 'timestamp': true},
    'dns': _dns(remoteDns, directDns, routing),
    'inbounds': [_tunInbound(mtu)],
    'outbounds': [
      outbound,
      {'type': 'direct', 'tag': 'direct'},
    ],
    'route': _route(routing),
  };
}

/// TUN-вход движка — один и тот же для конфига из одиночного ключа и из подписки.
Map<String, dynamic> _tunInbound(int mtu) => {
      'type': 'tun',
      'tag': 'tun-in',
      'interface_name': 'bitaps-tun',
      'address': ['172.19.0.1/30', 'fdfe:dcba:9876::1/126'],
      'mtu': mtu,
      'auto_route': true,
      'strict_route': true,
      'stack': 'system',
    };

/// Готовый конфиг как pretty-JSON строка (паритет со Swift `generate`).
String singboxConfigJson(String key, {Routing routing = Routing.rules}) =>
    const JsonEncoder.withIndent('  ').convert(singboxConfig(key, routing: routing));

// ============================ DNS ============================

Map<String, dynamic> _dns(String remoteDns, String directDns, Routing routing) {
  // Новый формат DNS-серверов (sing-box 1.12+; legacy "address" удалён в 1.14).
  final rules = <Map<String, dynamic>>[];
  if (routing == Routing.rules) {
    // Русские + офлайн-сайты резолвим прямым резолвером.
    rules.add({'rule_set': ['geosite-ru'], 'server': 'direct'});
  }
  return {
    'servers': [
      _dnsServer('remote', remoteDns, 'proxy'),
      // detour у прямого резолвера НЕ ставим: sing-box 1.12+ отвергает конфиг на старте с
      // «detour to an empty direct outbound makes no sense» (проверено запуском движка).
      // Без detour запрос и так идёт напрямую — поведение то же, конфиг живой.
      _dnsServer('direct', directDns, ''),
    ],
    'rules': rules,
    'final': routing == Routing.direct ? 'direct' : 'remote',
    'strategy': 'prefer_ipv4',
  };
}

/// Один DNS-сервер в новом типизированном формате (udp/tls/https/quic + хост).
Map<String, dynamic> _dnsServer(String tag, String addr, String detour) {
  final s = <String, dynamic>{'tag': tag};
  if (detour.isNotEmpty) s['detour'] = detour;
  if (addr.startsWith('https://')) {
    s['type'] = 'https';
    s['server'] = Uri.tryParse(addr)?.host ?? addr;
  } else if (addr.startsWith('tls://')) {
    s['type'] = 'tls';
    s['server'] = addr.substring('tls://'.length);
  } else if (addr.startsWith('quic://')) {
    s['type'] = 'quic';
    s['server'] = addr.substring('quic://'.length);
  } else {
    s['type'] = 'udp';
    s['server'] = addr;
  }
  return s;
}

// ============================ ROUTE ============================

Map<String, dynamic> _route(Routing routing) {
  // Новый формат action (sing-box 1.11+): dns hijack + reject вместо удалённых
  // dns/block outbounds; geo-матчинг через remote rule_sets.
  final rules = <Map<String, dynamic>>[
    {'action': 'sniff'},
    {'protocol': 'dns', 'action': 'hijack-dns'},
    {'ip_is_private': true, 'outbound': 'direct'},
    {'rule_set': ['geosite-ads'], 'action': 'reject'},
  ];
  final ruleSets = <Map<String, dynamic>>[
    _ruleSet('geosite-ads',
        'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ads-all.srs'),
  ];
  if (routing == Routing.rules) {
    // RU geoip/geosite — напрямую; всё остальное через прокси.
    rules.add({'rule_set': ['geoip-ru', 'geosite-ru'], 'outbound': 'direct'});
    ruleSets.add(_ruleSet('geoip-ru',
        'https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-ru.srs'));
    ruleSets.add(_ruleSet('geosite-ru',
        'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ru.srs'));
  }
  return {
    'rules': rules,
    'rule_set': ruleSets,
    'final': routing == Routing.direct ? 'direct' : 'proxy',
    'auto_detect_interface': true,
  };
}

Map<String, dynamic> _ruleSet(String tag, String url) =>
    {'type': 'remote', 'tag': tag, 'format': 'binary', 'url': url, 'download_detour': 'proxy'};

// ============================ OUTBOUND PARSING ============================

/// Разобрать один share-link в sing-box outbound (tag "proxy"). null — если не распарсить.
/// Бросает [FormatException] при внутренне-противоречивом ключе (напр. Reality без обязательного pbk),
/// чтобы вызывающий получил явную ошибку вместо тихо-битого конфига.
Map<String, dynamic>? outboundFromKey(String key) {
  final scheme = key.split(':').first.toLowerCase();
  switch (scheme) {
    case 'vless':
      return _parseVless(key);
    case 'trojan':
      return _parseTrojan(key);
    case 'vmess':
      return _parseVmess(key);
    case 'ss':
      return _parseShadowsocks(key);
    case 'hysteria2':
    case 'hy2':
      return _parseHysteria2(key);
    default:
      return null;
  }
}

// vless://uuid@host:port?type=&security=&sni=&pbk=&sid=&fp=&flow=&host=&path=&serviceName=#name
Map<String, dynamic>? _parseVless(String key) {
  final u = Uri.tryParse(key);
  if (u == null || u.host.isEmpty || u.userInfo.isEmpty) return null;
  final uuid = _decode(u.userInfo);
  final q = u.queryParameters;
  final out = <String, dynamic>{
    'type': 'vless',
    'tag': 'proxy',
    'server': u.host,
    'server_port': u.hasPort ? u.port : 443,
    'uuid': uuid,
    'packet_encoding': 'xudp',
  };
  final security = (q['security'] ?? 'none').toLowerCase();
  final flow = q['flow'] ?? '';
  if (flow.isNotEmpty) out['flow'] = flow;
  if (security == 'reality' || security == 'tls' || security == 'xtls') {
    out['tls'] = _tlsBlock(security, q, u.host);
  }
  final transport = _transportBlock(q);
  if (transport != null) out['transport'] = transport;
  return out;
}

// trojan://password@host:port?security=tls&sni=&type=#name
Map<String, dynamic>? _parseTrojan(String key) {
  final u = Uri.tryParse(key);
  if (u == null || u.host.isEmpty || u.userInfo.isEmpty) return null;
  final q = u.queryParameters;
  final out = <String, dynamic>{
    'type': 'trojan',
    'tag': 'proxy',
    'server': u.host,
    'server_port': u.hasPort ? u.port : 443,
    'password': _decode(u.userInfo),
  };
  final security = (q['security'] ?? 'tls').toLowerCase();
  if (security != 'none') out['tls'] = _tlsBlock(security, q, u.host);
  final transport = _transportBlock(q);
  if (transport != null) out['transport'] = transport;
  return out;
}

// vmess://base64({v,ps,add,port,id,aid,net,type,host,path,tls,sni,scy})
Map<String, dynamic>? _parseVmess(String key) {
  final data = _base64Pad(key.substring('vmess://'.length));
  if (data == null) return null;
  Map<String, dynamic> j;
  try {
    final decoded = json.decode(utf8.decode(data));
    if (decoded is! Map) return null;
    j = decoded.cast<String, dynamic>();
  } catch (_) {
    return null;
  }
  final host = (j['add'] as String?) ?? '';
  final id = j['id'] as String?;
  if (host.isEmpty || id == null) return null;
  final out = <String, dynamic>{
    'type': 'vmess',
    'tag': 'proxy',
    'server': host,
    'server_port': _int(j['port']) ?? 443,
    'uuid': id,
    'security': (j['scy'] as String?) ?? 'auto',
    'alter_id': _int(j['aid']) ?? 0,
  };
  if (j['tls'] == 'tls') {
    out['tls'] = _tlsBlock('tls', {
      'sni': (j['sni'] as String?) ?? (j['host'] as String?) ?? host,
    }, host);
  }
  final net = (j['net'] as String?) ?? 'tcp';
  final transport = _transportBlock({
    'type': net,
    'host': (j['host'] as String?) ?? '',
    'path': (j['path'] as String?) ?? '',
    'serviceName': (j['path'] as String?) ?? '',
  });
  if (transport != null) out['transport'] = transport;
  return out;
}

// ss://base64(method:password)@host:port#name  ИЛИ  ss://base64(method:password@host:port)#name
Map<String, dynamic>? _parseShadowsocks(String key) {
  var body = key.substring('ss://'.length);
  final hash = body.indexOf('#');
  if (hash != -1) body = body.substring(0, hash);
  // Форма A: userinfo в base64, host:port открытым текстом.
  final at = body.indexOf('@');
  if (at != -1) {
    final userinfo = body.substring(0, at);
    final hostPort = body.substring(at + 1);
    final decodedData = _base64Pad(userinfo);
    if (decodedData == null) return null;
    final decoded = utf8.decode(decodedData, allowMalformed: true);
    final colon = decoded.indexOf(':');
    final hp = _splitHostPort(hostPort);
    if (colon == -1 || hp == null) return null;
    return {
      'type': 'shadowsocks',
      'tag': 'proxy',
      'server': hp.$1,
      'server_port': hp.$2,
      'method': decoded.substring(0, colon),
      'password': decoded.substring(colon + 1),
    };
  }
  // Форма B: всё в base64.
  final decodedData = _base64Pad(body);
  if (decodedData == null) return null;
  final decoded = utf8.decode(decodedData, allowMalformed: true);
  final at2 = decoded.indexOf('@');
  if (at2 == -1) return null;
  final colon = decoded.substring(0, at2).indexOf(':');
  final hp = _splitHostPort(decoded.substring(at2 + 1));
  if (colon == -1 || hp == null) return null;
  return {
    'type': 'shadowsocks',
    'tag': 'proxy',
    'server': hp.$1,
    'server_port': hp.$2,
    'method': decoded.substring(0, colon),
    'password': decoded.substring(colon + 1, at2),
  };
}

// hysteria2://password@host:port?sni=&insecure=#name
Map<String, dynamic>? _parseHysteria2(String key) {
  final u = Uri.tryParse(key.replaceFirst('hy2://', 'hysteria2://'));
  if (u == null || u.host.isEmpty || u.userInfo.isEmpty) return null;
  final q = u.queryParameters;
  final tls = <String, dynamic>{'enabled': true, 'server_name': q['sni'] ?? u.host};
  // insecure уважаем только для доверенных bitaps-хостов (иначе чужой ключ открыл бы MITM).
  if (q['insecure'] == '1' && _isTrustedTunnelHost(u.host)) tls['insecure'] = true;
  return {
    'type': 'hysteria2',
    'tag': 'proxy',
    'server': u.host,
    'server_port': u.hasPort ? u.port : 443,
    'password': _decode(u.userInfo),
    'tls': tls,
  };
}

// ============================ SHARED BUILDERS ============================

Map<String, dynamic> _tlsBlock(String security, Map<String, String> q, String host) {
  final tls = <String, dynamic>{
    'enabled': true,
    'server_name': q['sni'] ?? q['host'] ?? host,
  };
  final alpn = q['alpn'] ?? '';
  if (alpn.isNotEmpty) tls['alpn'] = alpn.split(',');
  // insecure/allowInsecure отключает проверку TLS-сертификата (MITM-риск). Уважаем флаг ТОЛЬКО для
  // доверенных bitaps-хостов; у любого чужого хоста игнорируем, чтобы вредоносный ключ не открыл перехват.
  if ((q['allowInsecure'] == '1' || q['insecure'] == '1') && _isTrustedTunnelHost(host)) {
    tls['insecure'] = true;
  }
  final fp = q['fp'] ?? '';
  final hasFp = fp.isNotEmpty;
  if (security == 'reality') {
    // Reality без public_key (pbk) сгенерил бы reality:{enabled:true} без ключа — движок такой конфиг
    // не поднимет (это тихо-битый туннель). Явно фейлим импорт вместо генерации нерабочего конфига.
    final pbk = q['pbk'] ?? '';
    if (pbk.isEmpty) {
      throw const FormatException('Reality-ключ без public_key (pbk) — конфиг был бы невалиден');
    }
    final reality = <String, dynamic>{'enabled': true, 'public_key': pbk};
    if (q['sid'] != null && q['sid']!.isNotEmpty) reality['short_id'] = q['sid'];
    tls['reality'] = reality;
    tls['utls'] = {'enabled': true, 'fingerprint': hasFp ? fp : 'chrome'};
  } else if (hasFp) {
    tls['utls'] = {'enabled': true, 'fingerprint': fp};
  }
  return tls;
}

/// ws / grpc / httpupgrade transport (null для обычного tcp).
Map<String, dynamic>? _transportBlock(Map<String, String> q) {
  switch ((q['type'] ?? 'tcp').toLowerCase()) {
    case 'ws':
      final t = <String, dynamic>{'type': 'ws'};
      final path = q['path'] ?? '';
      final host = q['host'] ?? '';
      if (path.isNotEmpty) t['path'] = path;
      if (host.isNotEmpty) t['headers'] = {'Host': host};
      return t;
    case 'grpc':
      return {'type': 'grpc', 'service_name': q['serviceName'] ?? q['path'] ?? ''};
    case 'httpupgrade':
      final t = <String, dynamic>{'type': 'httpupgrade'};
      final path = q['path'] ?? '';
      final host = q['host'] ?? '';
      if (path.isNotEmpty) t['path'] = path;
      if (host.isNotEmpty) t['host'] = host;
      return t;
    default:
      return null;
  }
}

// ============================ HELPERS ============================

/// Единый список доверенных bitaps-доменов + проверка хоста — общий источник правды
/// для гарда туннеля здесь (_isTrustedTunnelHost) и гарда импорта в UI (_isTrustedHost,
/// main.dart). Обе стороны делегируют сюда, чтобы список доменов и логика сравнения не
/// разъезжались. Логика прежняя: точный домен bitaps ИЛИ его поддомен (h == d либо h
/// оканчивается на «.d»). Определено в этом (импортируемом) модуле, т.к. main.dart уже
/// импортирует singbox_config.dart, а models.dart — лишь `part of main.dart` и извне не виден.
/// bit-core.online — домен доставки: origin.bit-core.online отдаёт подписку /u/<token>,
/// cdn*.bit-core.online — узлы «белого списка». Без него подписка не прошла бы гард импорта.
const List<String> kTrustedBitapsDomains = ['bitaps.app', 'bitapsvpn.com', 'bit-core.online'];

bool isTrustedBitapsHost(String host) {
  final h = host.toLowerCase();
  for (final d in kTrustedBitapsDomains) {
    if (h == d || h.endsWith('.$d')) return true;
  }
  return false;
}

/// Доверенные bitaps-хосты, которым позволено запрашивать insecure-TLS (отключение проверки
/// сертификата). Для любого другого хоста insecure игнорируется — иначе чужой ключ открыл бы MITM.
/// Делегирует к общей [isTrustedBitapsHost] (единый список доменов).
bool _isTrustedTunnelHost(String host) => isTrustedBitapsHost(host);

/// percent-decode с фолбэком (битый encoding не должен ронять импорт).
String _decode(String s) {
  try {
    return Uri.decodeComponent(s);
  } catch (_) {
    return s;
  }
}

(String, int)? _splitHostPort(String s) {
  final colon = s.lastIndexOf(':');
  if (colon == -1) return null;
  final port = int.tryParse(s.substring(colon + 1));
  if (port == null) return null;
  return (s.substring(0, colon), port);
}

int? _int(dynamic v) {
  if (v is int) return v;
  if (v is String) return int.tryParse(v);
  if (v is num) return v.toInt();
  return null;
}

// ============================ ПОДПИСКА /u/<token> ============================
// Бот и оплаты выдают не одиночный share-link, а ПОДПИСКУ вида
//   https://origin.bit-core.online/u/<token>
// Тело подписки — JSON-массив готовых XRAY-конфигов (формат Happ): по записи на узел
// (узлы «БС» через CDN + прямые REALITY), у каждой — remarks и outbounds[0] с тегом proxy.
// Здесь мы разбираем массив и собираем ОДИН sing-box конфиг со всеми узлами сразу и
// авто-выбором самого быстрого (urltest) — вместо единственного захардкоженного outbound'а.
//
// ⚠️ Записи с транспортом xhttp ПРОПУСКАЕМ: такого транспорта в sing-box нет (он только в
// xray-core). Пока движок приложения — sing-box, узлы «белого списка» работают в Happ, но не
// здесь; чтобы они заработали и в приложении, нативной стороне нужен xray-core.

/// Токен подписки в пути /u/<token> — тот же алфавит, что выдаёт сервис доставки.
final RegExp _kSubToken = RegExp(r'^[A-Za-z0-9]{8,64}$');

/// Это ссылка на подписку bitaps? Гард НАМЕРЕННО узкий: только https, только доверенный
/// домен bitaps и только путь /u/<token>. Любой другой URL остаётся отвергнутым, как и раньше,
/// иначе «ключом» стала бы произвольная ссылка (вектор подмены конфига).
bool isSubscriptionUrl(String value) {
  final s = value.trim();
  if (!s.startsWith('https://')) return false;
  final u = Uri.tryParse(s);
  if (u == null || u.host.isEmpty || !isTrustedBitapsHost(u.host)) return false;
  final seg = u.pathSegments;
  return seg.length == 2 && seg[0] == 'u' && _kSubToken.hasMatch(seg[1]);
}

/// Один узел из подписки: как показать пользователю + готовый sing-box outbound.
class SubNode {
  final String remark; // «🇫🇮 Финляндия» — то, что видит пользователь
  final String tag;    // уникальный тег outbound'а внутри конфига
  final String server;
  final int port;
  final Map<String, dynamic> outbound;
  const SubNode({
    required this.remark,
    required this.tag,
    required this.server,
    required this.port,
    required this.outbound,
  });
}

/// Результат разбора тела подписки.
class SubParseResult {
  final List<SubNode> nodes;
  /// Сервис прислал уведомление вместо узлов («Подписка истекла», «Лимит устройств») —
  /// показываем его пользователю вместо попытки подключения.
  final String? notice;
  /// Сколько записей движок не понимает (xhttp «БС» и прочее) — для честного сообщения.
  final int skipped;
  const SubParseResult({this.nodes = const [], this.notice, this.skipped = 0});
  bool get hasNodes => nodes.isNotEmpty;
}

/// Протоколы xray-записей, которые мы вообще рассматриваем как узел.
const List<String> _kSubProxyProtocols = ['vless', 'vmess', 'trojan', 'shadowsocks'];

/// Разобрать тело подписки. Бросает [FormatException], если это вообще не массив JSON.
SubParseResult parseSubscription(String body, {String? headerNotice}) {
  final dynamic decoded = json.decode(body);
  if (decoded is! List) {
    throw const FormatException('подписка: ожидался JSON-массив конфигов');
  }
  final nodes = <SubNode>[];
  final usedTags = <String>{};
  String? notice = headerNotice;
  var skipped = 0;
  for (final entry in decoded) {
    if (entry is! Map) continue;
    final remark = (entry['remarks'] ?? '').toString().trim();
    final proxy = _proxyOutboundOf(entry['outbounds']);
    // Уведомление сервиса — одна запись «❌ …» с заглушкой на 127.0.0.1:1. Подключаться к ней
    // нельзя: это не узел, а способ донести текст до клиента подписки.
    if (remark.startsWith('❌') || _isNoticeOutbound(proxy)) {
      notice ??= remark.replaceFirst('❌', '').trim();
      continue;
    }
    if (proxy == null) continue;
    final out = _outboundFromXray(proxy);
    if (out == null) {
      skipped++; // движок не умеет этот транспорт/протокол (обычно xhttp)
      continue;
    }
    var tag = remark.isEmpty ? 'узел ${nodes.length + 1}' : remark;
    if (usedTags.contains(tag)) {
      var n = 2;
      while (usedTags.contains('$tag $n')) {
        n++;
      }
      tag = '$tag $n';
    }
    usedTags.add(tag);
    out['tag'] = tag;
    nodes.add(SubNode(
      remark: remark.isEmpty ? tag : remark,
      tag: tag,
      server: (out['server'] ?? '').toString(),
      port: _int(out['server_port']) ?? 0,
      outbound: out,
    ));
  }
  return SubParseResult(nodes: nodes, notice: notice, skipped: skipped);
}

/// Полный sing-box конфиг из разобранных узлов подписки: selector «proxy» → urltest «auto»
/// → сами узлы. Тег proxy сохранён, потому что на него ссылаются route.final и DNS-детуры.
Map<String, dynamic> singboxConfigFromNodes(
  List<SubNode> nodes, {
  Routing routing = Routing.rules,
  String remoteDns = 'https://1.1.1.1/dns-query',
  String directDns = '8.8.8.8',
  int mtu = 9000,
}) {
  if (nodes.isEmpty) {
    throw const FormatException('в подписке нет узлов, которые понимает движок');
  }
  final tags = [for (final n in nodes) n.tag];
  return {
    'log': {'level': 'warn', 'timestamp': true},
    'dns': _dns(remoteDns, directDns, routing),
    'inbounds': [_tunInbound(mtu)],
    'outbounds': [
      // Ручной выбор узла (по умолчанию — авто). Сюда же смотрит route.final.
      {'type': 'selector', 'tag': 'proxy', 'outbounds': ['auto', ...tags], 'default': 'auto'},
      // Авто-выбор быстрейшего: замер по 204-эндпоинту, переключение при заметной разнице.
      {
        'type': 'urltest',
        'tag': 'auto',
        'outbounds': tags,
        'url': 'https://www.gstatic.com/generate_204',
        'interval': '3m',
        'tolerance': 50,
        // без idle_timeout группа продолжала бы простукивать все узлы даже когда через неё
        // не идёт трафик — лишние handshake'и на каждую ноду каждые 3 минуты
        'idle_timeout': '30m',
      },
      for (final n in nodes) n.outbound,
      {'type': 'direct', 'tag': 'direct'},
    ],
    'route': _route(routing),
  };
}

/// Готовый конфиг подписки как JSON-строка (то, что уходит в нативный движок).
String singboxConfigJsonFromNodes(List<SubNode> nodes, {Routing routing = Routing.rules}) =>
    const JsonEncoder.withIndent('  ').convert(singboxConfigFromNodes(nodes, routing: routing));

/// Итог загрузки подписки по сети: либо узлы, либо уведомление, либо ошибка — но НИКОГДА
/// исключение наружу: вызывающий (гард подключения) должен показать текст, а не упасть.
class SubFetchResult {
  final List<SubNode> nodes;
  final String? notice;
  final String? error;
  final int skipped;
  final DateTime? expiresAt;
  const SubFetchResult({
    this.nodes = const [],
    this.notice,
    this.error,
    this.skipped = 0,
    this.expiresAt,
  });
  bool get ok => error == null && nodes.isNotEmpty;
}

/// Скачать и разобрать подписку. [hwid] уходит заголовком x-hwid — по нему сервис считает
/// устройства (лимит тарифа), поэтому идентификатор должен быть стабильным для установки.
Future<SubFetchResult> fetchSubscription(
  String url, {
  required String hwid,
  String deviceOs = '',
  http.Client? client,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final ownClient = client == null;
  final c = client ?? http.Client();
  try {
    final r = await c.get(Uri.parse(url), headers: {
      'accept': 'application/json',
      if (hwid.isNotEmpty) 'x-hwid': hwid,
      if (deviceOs.isNotEmpty) 'x-device-os': deviceOs,
    }).timeout(timeout);
    if (r.statusCode != 200) {
      return SubFetchResult(error: 'сервер подписки ответил ${r.statusCode}');
    }
    final parsed = parseSubscription(
      utf8.decode(r.bodyBytes),
      headerNotice: _decodeSubHeader(r.headers['sub-info-text'] ?? r.headers['announce']),
    );
    return SubFetchResult(
      nodes: parsed.nodes,
      notice: parsed.notice,
      skipped: parsed.skipped,
      expiresAt: _expiryOf(r.headers['subscription-userinfo']),
    );
  } on TimeoutException {
    return const SubFetchResult(error: 'подписка не ответила вовремя');
  } on FormatException catch (e) {
    return SubFetchResult(error: 'подписка повреждена: ${e.message}');
  } catch (_) {
    // сеть/DNS/TLS — точный текст пользователю не нужен, важен факт недоступности
    return const SubFetchResult(error: 'не удалось получить подписку');
  } finally {
    if (ownClient) c.close();
  }
}

// ---------- разбор одной xray-записи ----------

Map<String, dynamic>? _proxyOutboundOf(dynamic outbounds) {
  if (outbounds is! List) return null;
  for (final o in outbounds) {
    if (o is! Map) continue;
    final m = o.cast<String, dynamic>();
    final proto = (m['protocol'] ?? '').toString().toLowerCase();
    if (m['tag'] == 'proxy' || _kSubProxyProtocols.contains(proto)) return m;
  }
  return null;
}

/// Запись-заглушка уведомления: сервис ставит адрес 127.0.0.1:1 и нулевой uuid.
bool _isNoticeOutbound(Map<String, dynamic>? proxy) {
  if (proxy == null) return false;
  final vnext = (proxy['settings'] as Map?)?['vnext'];
  if (vnext is! List || vnext.isEmpty) return false;
  final v = (vnext.first as Map).cast<String, dynamic>();
  return (v['address'] ?? '') == '127.0.0.1' && (_int(v['port']) ?? 0) <= 1;
}

/// xray-outbound → sing-box outbound. null — узел движку не по зубам (пропускаем).
Map<String, dynamic>? _outboundFromXray(Map<String, dynamic> o) {
  final proto = (o['protocol'] ?? '').toString().toLowerCase();
  final ss = (o['streamSettings'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
  final network = (ss['network'] ?? 'tcp').toString().toLowerCase();
  final security = (ss['security'] ?? 'none').toString().toLowerCase();
  final settings = (o['settings'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};

  // Транспорт должен быть из тех, что есть в sing-box. xhttp/splithttp — только xray.
  if (!_kXrayNetToSingbox.containsKey(network)) return null;
  // TLS обязателен для reality/tls: если параметры битые — узел мёртвый, лучше пропустить.
  final needsTls = security == 'reality' || security == 'tls' || security == 'xtls';
  final tls = needsTls ? _tlsFromXray(security, ss) : null;
  if (needsTls && tls == null) return null;

  Map<String, dynamic>? out;
  switch (proto) {
    case 'vless':
    case 'vmess':
      final vnext = settings['vnext'];
      if (vnext is! List || vnext.isEmpty) return null;
      final v = (vnext.first as Map).cast<String, dynamic>();
      final users = v['users'];
      if (users is! List || users.isEmpty) return null;
      final u = (users.first as Map).cast<String, dynamic>();
      final id = (u['id'] ?? '').toString();
      final host = (v['address'] ?? '').toString();
      if (id.isEmpty || host.isEmpty) return null;
      out = {
        'type': proto,
        'server': host,
        'server_port': _int(v['port']) ?? 443,
        'uuid': id,
      };
      if (proto == 'vless') {
        out['packet_encoding'] = 'xudp';
        final flow = (u['flow'] ?? '').toString();
        if (flow.isNotEmpty) out['flow'] = flow;
      } else {
        out['security'] = (u['security'] ?? 'auto').toString();
        out['alter_id'] = _int(u['alterId']) ?? 0;
      }
      break;
    case 'trojan':
    case 'shadowsocks':
      final servers = settings['servers'];
      if (servers is! List || servers.isEmpty) return null;
      final s = (servers.first as Map).cast<String, dynamic>();
      final host = (s['address'] ?? '').toString();
      final password = (s['password'] ?? '').toString();
      if (host.isEmpty || password.isEmpty) return null;
      out = {
        'type': proto,
        'server': host,
        'server_port': _int(s['port']) ?? 443,
        'password': password,
      };
      if (proto == 'shadowsocks') {
        final method = (s['method'] ?? '').toString();
        if (method.isEmpty) return null;
        out['method'] = method;
      }
      break;
    default:
      return null;
  }

  if (tls != null) out['tls'] = tls;
  final transport = _kXrayNetToSingbox[network];
  if (transport != null) {
    final block = _transportFromXray(transport, ss);
    if (block != null) out['transport'] = block;
  }
  return out;
}

/// Сети xray → тип транспорта sing-box. null-значение = «транспорт не нужен» (обычный tcp).
const Map<String, String?> _kXrayNetToSingbox = {
  'tcp': null,
  'raw': null,
  'ws': 'ws',
  'websocket': 'ws',
  'grpc': 'grpc',
  'httpupgrade': 'httpupgrade',
  'http': 'http',
  'h2': 'http',
};

Map<String, dynamic>? _tlsFromXray(String security, Map<String, dynamic> ss) {
  if (security == 'reality') {
    final r = (ss['realitySettings'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final pbk = (r['publicKey'] ?? '').toString();
    // Reality без публичного ключа движок не поднимет — это тихо-битый узел (см. _tlsBlock).
    if (pbk.isEmpty) return null;
    final sni = (r['serverName'] ?? '').toString();
    if (sni.isEmpty) return null;
    final reality = <String, dynamic>{'enabled': true, 'public_key': pbk};
    final sid = (r['shortId'] ?? '').toString();
    if (sid.isNotEmpty) reality['short_id'] = sid;
    return {
      'enabled': true,
      'server_name': sni,
      'utls': {'enabled': true, 'fingerprint': _utlsFp((r['fingerprint'] ?? '').toString())},
      'reality': reality,
    };
  }
  final t = ((ss['tlsSettings'] ?? ss['xtlsSettings']) as Map?)?.cast<String, dynamic>() ??
      const <String, dynamic>{};
  final sni = (t['serverName'] ?? '').toString();
  if (sni.isEmpty) return null;
  final tls = <String, dynamic>{'enabled': true, 'server_name': sni};
  final alpn = t['alpn'];
  if (alpn is List && alpn.isNotEmpty) tls['alpn'] = [for (final a in alpn) a.toString()];
  final fp = (t['fingerprint'] ?? '').toString();
  if (fp.isNotEmpty) tls['utls'] = {'enabled': true, 'fingerprint': _utlsFp(fp)};
  return tls;
}

Map<String, dynamic>? _transportFromXray(String type, Map<String, dynamic> ss) {
  switch (type) {
    case 'ws':
      final w = (ss['wsSettings'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
      final t = <String, dynamic>{'type': 'ws'};
      final path = (w['path'] ?? '').toString();
      if (path.isNotEmpty) t['path'] = path;
      final headers = w['headers'];
      if (headers is Map && headers['Host'] != null) {
        t['headers'] = {'Host': headers['Host'].toString()};
      }
      return t;
    case 'grpc':
      final g = (ss['grpcSettings'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
      return {'type': 'grpc', 'service_name': (g['serviceName'] ?? '').toString()};
    case 'httpupgrade':
      final h =
          (ss['httpupgradeSettings'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
      final t = <String, dynamic>{'type': 'httpupgrade'};
      final path = (h['path'] ?? '').toString();
      if (path.isNotEmpty) t['path'] = path;
      final host = (h['host'] ?? '').toString();
      if (host.isNotEmpty) t['host'] = host;
      return t;
    case 'http':
      final h = (ss['httpSettings'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
      final t = <String, dynamic>{'type': 'http'};
      final path = (h['path'] ?? '').toString();
      if (path.isNotEmpty) t['path'] = path;
      final hosts = h['host'];
      if (hosts is List && hosts.isNotEmpty) t['host'] = [for (final x in hosts) x.toString()];
      return t;
    default:
      return null;
  }
}

/// Отпечаток uTLS: движок знает ограниченный набор — незнакомый заменяем на chrome,
/// иначе конфиг не поднимется из-за одной опечатки в подписке.
String _utlsFp(String fp) {
  const known = [
    'chrome', 'firefox', 'edge', 'safari', 'ios', 'android', 'random', 'randomized', '360', 'qq',
  ];
  final f = fp.toLowerCase();
  return known.contains(f) ? f : 'chrome';
}

/// Заголовки sub-info-text / announce приходят как «base64:<…>» (иначе — как есть).
String? _decodeSubHeader(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  if (!raw.startsWith('base64:')) return raw;
  final data = _base64Pad(raw.substring('base64:'.length));
  if (data == null) return null;
  try {
    return utf8.decode(data);
  } catch (_) {
    return null;
  }
}

/// Заголовок subscription-userinfo: «expire=<unix>» (плюс возможные upload/download/total).
DateTime? _expiryOf(String? raw) {
  if (raw == null) return null;
  for (final part in raw.split(';')) {
    final kv = part.trim().split('=');
    if (kv.length == 2 && kv[0].trim() == 'expire') {
      final secs = int.tryParse(kv[1].trim());
      if (secs != null && secs > 0) {
        return DateTime.fromMillisecondsSinceEpoch(secs * 1000, isUtc: true);
      }
    }
  }
  return null;
}

/// Base64 (обычный или URL-safe, с паддингом или без) → байты. null при ошибке.
List<int>? _base64Pad(String s) {
  var str = s.replaceAll('-', '+').replaceAll('_', '/');
  while (str.length % 4 != 0) {
    str += '=';
  }
  try {
    return base64.decode(str);
  } catch (_) {
    return null;
  }
}
