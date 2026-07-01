// Генератор sing-box конфигурации из vless:// ключа — ФУНДАМЕНТ боевого туннеля.
// Чистая функция без сайд-эффектов: даёт готовый конфиг для движка sing-box, когда он будет
// подключён. Сам VPN-движок (нативная TUN-интеграция по платформам) + боевой VLESS-сервер —
// на владельце; до этого приложение работает в демо-режиме (см. kRealTunnel в main.dart).

/// Парсит vless:// ключ в outbound-секцию sing-box (reality/tls, tcp/ws/grpc).
Map<String, dynamic> vlessOutbound(String key) {
  final Uri u;
  try {
    u = Uri.parse(key.trim());
  } catch (_) {
    throw const FormatException('не удалось разобрать ключ');
  }
  if (u.scheme != 'vless') throw const FormatException('not a vless key');
  if (u.host.isEmpty) throw const FormatException('в ключе нет адреса сервера');
  // uuid в userInfo может быть percent-encoded; битый encoding не должен ронять весь импорт
  String uuid;
  try {
    uuid = Uri.decodeComponent(u.userInfo);
  } catch (_) {
    uuid = u.userInfo;
  }
  if (uuid.isEmpty) throw const FormatException('в ключе нет UUID');
  final q = u.queryParameters;
  final cfg = <String, dynamic>{
    'type': 'vless',
    'tag': 'proxy',
    'server': u.host,
    'server_port': u.hasPort ? u.port : 443,
    'uuid': uuid,
    'packet_encoding': 'xudp',
  };
  final flow = q['flow'] ?? '';
  if (flow.isNotEmpty) cfg['flow'] = flow;
  final sec = q['security'];
  if (sec == 'reality' || sec == 'tls') {
    final tls = <String, dynamic>{
      'enabled': true,
      'server_name': q['sni'] ?? u.host,
      'utls': {'enabled': true, 'fingerprint': q['fp'] ?? 'chrome'},
    };
    if (sec == 'reality') {
      final pbk = q['pbk'] ?? '';
      if (pbk.isEmpty) throw const FormatException('reality-ключ без public_key (pbk)');
      tls['reality'] = {'enabled': true, 'public_key': pbk, 'short_id': q['sid'] ?? ''};
    }
    cfg['tls'] = tls;
  }
  final net = q['type'] ?? 'tcp';
  if (net == 'ws') {
    cfg['transport'] = {'type': 'ws', 'path': q['path'] ?? '/', 'headers': {'Host': q['host'] ?? u.host}};
  } else if (net == 'grpc') {
    cfg['transport'] = {'type': 'grpc', 'service_name': q['serviceName'] ?? ''};
  }
  return cfg;
}

/// Полный sing-box конфиг: TUN-вход + vless-выход + базовый роутинг. Готов к запуску движком.
Map<String, dynamic> singboxConfig(String vlessKey) => {
      'log': {'level': 'warn'},
      'inbounds': [
        {
          'type': 'tun',
          'tag': 'tun-in',
          'interface_name': 'bitaps0',
          'auto_route': true,
          'strict_route': true,
          'stack': 'system',
          'sniff': true,
        },
      ],
      'outbounds': [
        vlessOutbound(vlessKey),
        {'type': 'direct', 'tag': 'direct'},
      ],
      'route': {'auto_detect_interface': true, 'final': 'proxy'},
    };
