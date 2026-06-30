// Генератор sing-box конфигурации из vless:// ключа — ФУНДАМЕНТ боевого туннеля.
// Чистая функция без сайд-эффектов: даёт готовый конфиг для движка sing-box, когда он будет
// подключён. Сам VPN-движок (нативная TUN-интеграция по платформам) + боевой VLESS-сервер —
// на владельце; до этого приложение работает в демо-режиме (см. kRealTunnel в main.dart).

/// Парсит vless:// ключ в outbound-секцию sing-box (reality/tls, tcp/ws/grpc).
Map<String, dynamic> vlessOutbound(String key) {
  final u = Uri.parse(key.trim());
  if (u.scheme != 'vless') throw const FormatException('not a vless key');
  final q = u.queryParameters;
  final cfg = <String, dynamic>{
    'type': 'vless',
    'tag': 'proxy',
    'server': u.host,
    'server_port': u.hasPort ? u.port : 443,
    'uuid': Uri.decodeComponent(u.userInfo),
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
      tls['reality'] = {'enabled': true, 'public_key': q['pbk'] ?? '', 'short_id': q['sid'] ?? ''};
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
