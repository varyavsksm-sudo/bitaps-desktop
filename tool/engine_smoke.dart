// ignore_for_file: avoid_print
// Дым-тест движка БЕЗ туннеля: поднимаем xray на конфиге, где весь трафик идёт напрямую
// (freedom), и проверяем, что локальный socks реально работает и процесс корректно гаснет.
// Так проверяется вся обвязка запуска/готовности/уборки, не завися от доступности нод.
import 'dart:convert';
import 'dart:io';
import 'package:bitaps_vpn/desktop_engine.dart';

Future<void> main(List<String> args) async {
  final bin = args.isNotEmpty ? args.first : XrayBinary.locate();
  if (bin == null) { stderr.writeln('движок не найден'); exit(2); }
  const port = 12808;
  final cfg = json.encode({
    'log': {'loglevel': 'warning'},
    'inbounds': [
      {'listen': '127.0.0.1', 'port': port, 'protocol': 'socks',
       'settings': {'udp': true, 'auth': 'noauth'}, 'tag': 'socks'}
    ],
    'outbounds': [{'protocol': 'freedom', 'tag': 'direct'}],
  });
  final t0 = DateTime.now();
  final p = await XrayProcess.start(cfg, socksPort: port, binaryPath: bin);
  print('движок готов за ${DateTime.now().difference(t0).inMilliseconds} мс, socks=$port');

  final res = await Process.run('curl', ['-s', '-o', '/dev/null', '-w', '%{http_code}',
      '--max-time', '15', '--socks5-hostname', '127.0.0.1:$port',
      'https://origin.bit-core.online/gen204']);
  print('запрос через socks движка: HTTP ${res.stdout}');

  await p.stop();
  // порт должен освободиться
  var alive = true;
  try {
    final s = await Socket.connect('127.0.0.1', port, timeout: const Duration(milliseconds: 600));
    s.destroy();
  } catch (_) { alive = false; }
  print('после stop() порт занят: $alive');

  // ошибка «движка нет» должна быть внятной, а не исключением из недр
  try {
    await XrayProcess.start(cfg, socksPort: port + 1, binaryPath: '/nope/xray');
    print('ОШИБКА: старт с несуществующим бинарём не упал');
  } on EngineUnavailable catch (e) {
    print('несуществующий бинарь -> «$e»');
  }
}
