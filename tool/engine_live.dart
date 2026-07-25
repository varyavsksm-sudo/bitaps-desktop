// ignore_for_file: avoid_print
// Живая проверка ДВИЖКА целиком: подписка → узлы → xray-конфиг → процесс → socks → метрики.
// Системный прокси НЕ трогаем (это делает приложение) — проверяем сам туннель.
import 'dart:io';
import 'package:bitaps_vpn/singbox_config.dart';
import 'package:bitaps_vpn/xray_config.dart';
import 'package:bitaps_vpn/desktop_engine.dart';

Future<void> main(List<String> args) async {
  final url = args[0];
  final bin = args[1];
  final only = args.length > 2 ? args[2] : null;
  final sub = await fetchSubscription(url, hwid: 'enginelive0123456789', deviceOs: 'linux');
  if (!sub.ok) { stderr.writeln('подписка: ${sub.error ?? sub.notice}'); exit(1); }
  const socks = 13808, metrics = 13809;
  final cfg = xrayConfigJsonFromNodes(sub.nodes, only: only, socksPort: socks, metricsPort: metrics);
  final p = await XrayProcess.start(cfg, socksPort: socks, binaryPath: bin);
  print('движок поднят на ${sub.nodes.length} узлах${only != null ? " (выбран: $only)" : " (балансировщик)"}');
  final ip = await Process.run('curl', ['-s', '--max-time', '30', '--socks5-hostname', '127.0.0.1:$socks', 'https://api.ipify.org']);
  print('внешний IP через туннель: ${ip.stdout}');
  await Future<void>.delayed(const Duration(seconds: 2));
  final st = await XrayStats.read(metrics);
  print('метрики движка: up=${st?.up} down=${st?.down} байт');
  print('пинги узлов: ${st?.pings}');
  await p.stop();
  print('движок остановлен');
}
