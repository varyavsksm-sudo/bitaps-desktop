// ignore_for_file: avoid_print
// Оффлайн-проверка генератора конфига: фикстура подписки → готовый xray-конфиг на stdout.
//
// Зачем: конфиг, который приложение отдаёт движку, никем не проверяется. Этот скрипт печатает
// его без сети и без секретов (фикстура — та же, что в юнит-тестах), чтобы CI мог скормить его
// НАСТОЯЩЕМУ xray с ключом `run -test`. Так регрессия генератора и несовместимый бинарь движка
// ловятся до релиза, а не у пользователя.
//
// Использование: dart run tool/check_config.dart test/fixtures/subscription.json [--only <tag>]
import 'dart:io';

import 'package:bitaps_vpn/singbox_config.dart';
import 'package:bitaps_vpn/xray_config.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('использование: dart run tool/check_config.dart <фикстура.json> [--only <tag>]');
    exit(2);
  }
  final file = File(args.first);
  if (!file.existsSync()) {
    stderr.writeln('фикстура не найдена: ${args.first}');
    exit(2);
  }
  String? only;
  final i = args.indexOf('--only');
  if (i >= 0 && i + 1 < args.length) only = args[i + 1];

  final res = parseSubscription(file.readAsStringSync());
  if (!res.hasNodes) {
    stderr.writeln('в фикстуре нет узлов: ${res.notice ?? "(нераспознанных записей: ${res.skipped})"}');
    exit(1);
  }
  // Диагностика в stderr, чтобы stdout остался чистым конфигом для `xray run -test -c`.
  final bs = res.nodes.where((n) => !n.singboxReady).length;
  stderr.writeln('узлов: ${res.nodes.length} (из них «БС»/xhttp: $bs)');
  for (final n in res.nodes) {
    final net = (n.xray['streamSettings'] as Map?)?['network'] ?? 'tcp';
    stderr.writeln('  ${n.singboxReady ? "  " : "БС"} ${n.tag} -> ${n.server}:${n.port} [$net]');
  }
  if (bs == 0) {
    // Фикстура без xhttp не проверяет главное — что «белый список» доживает до движка.
    stderr.writeln('ОШИБКА: в фикстуре нет ни одного xhttp-узла — гейт бессмыслен');
    exit(1);
  }
  stdout.write(xrayConfigJsonFromNodes(
    res.nodes,
    only: only,
    socksPort: 10808,
    httpPort: 10809,
    metricsPort: 10810,
  ));
}
