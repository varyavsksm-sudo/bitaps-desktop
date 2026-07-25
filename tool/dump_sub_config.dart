// ignore_for_file: avoid_print
// Служебный скрипт (не входит в приложение): тянет ЖИВУЮ подписку и печатает готовый
// sing-box конфиг — чтобы проверить его настоящим движком (sing-box check).
import 'dart:io';
import 'package:bitaps_vpn/singbox_config.dart';

Future<void> main(List<String> args) async {
  final url = args.isNotEmpty ? args.first : '';
  if (!isSubscriptionUrl(url)) {
    stderr.writeln('не ссылка на подписку: $url');
    exit(2);
  }
  final res = await fetchSubscription(url, hwid: 'toolcheck0123456789', deviceOs: 'macos');
  if (res.error != null) {
    stderr.writeln('ошибка: ${res.error}');
    exit(1);
  }
  if (!res.ok) {
    stderr.writeln('узлов нет; уведомление: ${res.notice}');
    exit(1);
  }
  stderr.writeln('узлов: ${res.nodes.length}, пропущено: ${res.skipped}, до: ${res.expiresAt}');
  stdout.write(singboxConfigJsonFromNodes(res.nodes));
}
