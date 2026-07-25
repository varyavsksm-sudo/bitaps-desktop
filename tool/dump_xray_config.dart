// ignore_for_file: avoid_print
// Служебный скрипт: тянет живую подписку и печатает готовый XRAY-конфиг (все узлы + балансировщик),
// чтобы проверить его настоящим движком xray.
import 'dart:io';
import 'package:bitaps_vpn/singbox_config.dart';
import 'package:bitaps_vpn/xray_config.dart';

Future<void> main(List<String> args) async {
  final url = args.isNotEmpty ? args.first : '';
  final only = args.length > 1 ? args[1] : null;
  final res = await fetchSubscription(url, hwid: 'toolcheck0123456789', deviceOs: 'macos');
  if (!res.ok) {
    stderr.writeln('ошибка: ${res.error ?? res.notice}');
    exit(1);
  }
  stderr.writeln('узлов всего: ${res.nodes.length} (для sing-box: ${res.nodes.where((n) => n.singboxReady).length})');
  for (final n in res.nodes) {
    stderr.writeln('  ${n.singboxReady ? " " : "БС"} ${n.tag} -> ${n.server}:${n.port}');
  }
  stdout.write(xrayConfigJsonFromNodes(res.nodes, only: only));
}
