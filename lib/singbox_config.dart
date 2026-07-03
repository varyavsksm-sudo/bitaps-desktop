// Генератор sing-box конфигурации из share-link ключа (vpn_key, который выдаёт бот) —
// ФУНДАМЕНТ боевого туннеля единой кодовой базы. Порт богатого Swift-генератора
// (SingBoxConfig.swift): поддерживает vless:// (в т.ч. Reality), vmess://, trojan://,
// ss://, hysteria2://. Чистые функции без сайд-эффектов, юнит-тестируемо.
//
// Отличия от старого тонкого vless.dart: 5 протоколов вместо одного, режимы роутинга
// (global/rules/direct), новый формат DNS/route (sing-box 1.11+), geo-RU + ad-block rule-sets.

import 'dart:convert';

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
    'inbounds': [
      {
        'type': 'tun',
        'tag': 'tun-in',
        'interface_name': 'bitaps-tun',
        'address': ['172.19.0.1/30', 'fdfe:dcba:9876::1/126'],
        'mtu': mtu,
        'auto_route': true,
        'strict_route': true,
        'stack': 'system',
      },
    ],
    'outbounds': [
      outbound,
      {'type': 'direct', 'tag': 'direct'},
    ],
    'route': _route(routing),
  };
}

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
      _dnsServer('direct', directDns, 'direct'),
    ],
    'rules': rules,
    'final': routing == Routing.direct ? 'direct' : 'remote',
    'strategy': 'prefer_ipv4',
  };
}

/// Один DNS-сервер в новом типизированном формате (udp/tls/https/quic + хост).
Map<String, dynamic> _dnsServer(String tag, String addr, String detour) {
  final s = <String, dynamic>{'tag': tag, 'detour': detour};
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
  if (q['insecure'] == '1') tls['insecure'] = true;
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

Map<String, dynamic> _tlsBlock(String security, Map<String, String> q, String defaultSni) {
  final tls = <String, dynamic>{
    'enabled': true,
    'server_name': q['sni'] ?? q['host'] ?? defaultSni,
  };
  final alpn = q['alpn'] ?? '';
  if (alpn.isNotEmpty) tls['alpn'] = alpn.split(',');
  if (q['allowInsecure'] == '1' || q['insecure'] == '1') tls['insecure'] = true;
  final fp = q['fp'] ?? '';
  final hasFp = fp.isNotEmpty;
  if (security == 'reality') {
    final reality = <String, dynamic>{'enabled': true};
    if (q['pbk'] != null) reality['public_key'] = q['pbk'];
    if (q['sid'] != null) reality['short_id'] = q['sid'];
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
