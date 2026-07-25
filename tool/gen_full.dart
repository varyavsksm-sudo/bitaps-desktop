// ignore_for_file: avoid_print
import 'dart:io';
import 'package:bitaps_vpn/singbox_config.dart';
import 'package:bitaps_vpn/xray_config.dart';
Future<void> main(List<String> a) async {
  final sub = await fetchSubscription(a[0], hwid: 'fullcheck0123456789', deviceOs: 'linux');
  if (!sub.ok) { stderr.writeln(sub.error ?? sub.notice); exit(1); }
  stderr.writeln('узлов: ${sub.nodes.length}');
  stdout.write(xrayConfigJsonFromNodes(sub.nodes, socksPort: 13808, metricsPort: 13809));
}
