// Быстрый замер флота ОДНИМ процессом xray (десктоп): генератор конфига «все узлы +
// observatory + метрики» и парсер ответа /debug/vars.
//
// Зачем именно этот тест. Раньше кнопка «Проверить серверы» поднимала процесс xray на КАЖДЫЙ
// узел — флот мерился 10–12 с. Новый путь (probeFleet в engine.dart) поднимает один процесс
// и читает alive/rtt всех узлов из /debug/vars; обе ошибки, которые здесь возможны, для
// пользователя фатальны: конфиг без observatory молча не замеряет ничего, а кривой парсер
// ставит ложные приговоры «узел не пропускает трафик» живым рельсам. Сам процесс в тесте не
// поднимаем (движок есть не везде) — фиксируем чистый генератор и чистый парсер.
import 'package:flutter_test/flutter_test.dart';
import 'package:bitaps_vpn/desktop_engine.dart';
import 'package:bitaps_vpn/singbox_config.dart';
import 'package:bitaps_vpn/xray_config.dart';

// Выдача: CDN-рельса (xhttp) + прямая VLESS+Reality — обе на доверенных хостах (гейт).
const String _subBody = '''
[
 {"remarks":"🛡️ Нидерланды · LTE",
  "outbounds":[
   {"tag":"proxy","protocol":"vless",
    "settings":{"vnext":[{"address":"cdn2.bit-core.online","port":443,
      "users":[{"id":"11111111-2222-3333-4444-555555555555","encryption":"none"}]}]},
    "streamSettings":{"network":"xhttp","security":"tls",
      "tlsSettings":{"serverName":"cdn2.bit-core.online","alpn":["h2","http/1.1"],"fingerprint":"firefox"},
      "xhttpSettings":{"mode":"packet-up","path":"/"}}},
   {"protocol":"freedom","tag":"direct"},
   {"protocol":"blackhole","tag":"block"}]},
 {"remarks":"🇫🇮 Финляндия",
  "outbounds":[
   {"tag":"proxy","protocol":"vless",
    "settings":{"vnext":[{"address":"fi1.bitapsvpn.com","port":8443,
      "users":[{"id":"11111111-2222-3333-4444-555555555555","encryption":"none","flow":"xtls-rprx-vision"}]}]},
    "streamSettings":{"security":"reality","network":"tcp",
      "realitySettings":{"serverName":"ya.ru","fingerprint":"firefox",
        "publicKey":"mRX3TKTKefW4WrXGIEiKQL1aIWVlfZ5I3Xyf0We4skQ","shortId":"974a7f83c1977d80","spiderX":"/"}}},
   {"protocol":"freedom","tag":"direct"}]}
]
''';

void main() {
  final nodes = parseSubscription(_subBody).nodes;

  group('xrayFleetProbeConfig — все узлы в одном процессе', () {
    final cfg = xrayFleetProbeConfig(nodes, socksPort: 41001, metricsPort: 41002);

    test('каждый узел — outbound node-<i> плюс direct/block', () {
      expect(nodes.length, 2, reason: 'фикстура подписки не разобралась');
      final outbounds = (cfg['outbounds'] as List).cast<Map>();
      final tags = outbounds.map((o) => o['tag']).toList();
      expect(tags, containsAll(['node-0', 'node-1', 'direct', 'block']));
      // сырой outbound узла сохранён: рельса обязана остаться xhttp, иначе быстрый замер её потеряет
      final relay = outbounds.firstWhere((o) => o['tag'] == 'node-0');
      expect(((relay['streamSettings'] as Map)['network']), 'xhttp');
    });

    test('observatory: probeUrl gen204, интервал 1с, конкурентные пробы по всем node-*', () {
      final obs = cfg['observatory'] as Map;
      expect(obs['probeUrl'], kXrayObservatoryUrl);
      expect(obs['probeInterval'], '1s');
      expect(obs['enableConcurrency'], isTrue);
      expect(obs['subjectSelector'], ['node-']);
    });

    test('метрики слушают localhost на заданном порту, счётчики включены', () {
      expect((cfg['metrics'] as Map)['listen'], '127.0.0.1:41002');
      expect(cfg['stats'], isA<Map>());
      expect((cfg['policy'] as Map)['system'], isNotNull);
    });

    test('флот из одного узла: observatory всё равно есть (замер нужен и ему)', () {
      final one = xrayFleetProbeConfig([nodes.first], socksPort: 41003, metricsPort: 41004);
      expect(one['observatory'], isA<Map>(),
          reason: 'базовый генератор добавляет observatory только при балансировке — '
              'пробный конфиг обязан ставить её безусловно');
    });
  });

  group('XrayStats.parse — разбор /debug/vars', () {
    test('живой узел → rtt, мёртвый (alive false / заглушка 99999999) → null', () {
      final r = XrayStats.parse('''
        {"observatory":{
          "node-0":{"alive":true,"delay":187},
          "node-1":{"alive":false,"delay":99999999},
          "node-2":{"delay":99999999}
        }}''');
      expect(r, isNotNull);
      expect(r!.pings['node-0'], 187);
      expect(r.pings['node-1'], isNull, reason: 'alive false — замерен и не пропускает');
      expect(r.pings['node-2'], isNull,
          reason: 'proto3 опускает alive=false — это тоже «замерен и мёртв», а не «нет данных»');
    });

    test('счётчики трафика суммируются только по node-*', () {
      final r = XrayStats.parse('''
        {"stats":{"outbound":{
          "node-0":{"uplink":1000,"downlink":2000},
          "node-1":{"uplink":3000,"downlink":4000},
          "direct":{"uplink":99999,"downlink":99999}
        }}}''');
      expect(r!.up, 4000);
      expect(r.down, 6000);
    });

    test('нет observatory → пустая карта пингов (покрытие 0 — фолбэк добьёт)', () {
      final r = XrayStats.parse('{"stats":{"outbound":{}}}');
      expect(r, isNotNull);
      expect(r!.pings, isEmpty);
    });

    test('битый ответ → null, а не падение', () {
      expect(XrayStats.parse('не json'), isNull);
      expect(XrayStats.parse('[]'), isNull);
      expect(XrayStats.parse(''), isNull);
    });
  });
}
