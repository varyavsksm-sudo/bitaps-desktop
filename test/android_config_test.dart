// Конфиг, который приложение отдаёт движку на Android.
//
// Здесь проверяется главное свойство: он должен быть ТЕМ ЖЕ конфигом, что наш сервис кладёт
// в подписку, а не собранным нами заново. Собственная сборка (все узлы + балансировщик +
// обсерватория + метрики) внутри системного VpnService поднимала туннель, но трафик через
// него не шёл, тогда как та же подписка в стороннем клиенте работала. Поэтому на Android
// берём запись подписки как есть и меняем в ней только порт socks-входа — его ищет плагин.
//
// Образец подписки снят с живой выдачи (uuid обезличен) и содержит узел через CDN, прямой
// узел и служебную запись-балансировщик.
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

  test('узел через CDN сохраняет транспорт xhttp', () {
    final cdn = parsed.nodes.firstWhere((n) => n.remark.contains('LTE'));
    final cfg = json.decode(xrayEntryConfigJson(cdn)) as Map<String, dynamic>;
    final ss = ((cfg['outbounds'] as List).first as Map)['streamSettings'] as Map;
    expect(ss['network'], 'xhttp', reason: 'без xhttp узел белого списка не поднимется');
    expect(ss['xhttpSettings'], isNotNull);
  });
}
