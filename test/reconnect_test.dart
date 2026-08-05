// Авто-реконнект: расписание пауз между попытками и правило «тумблер выключен — серии нет».
//
// Зачем именно этот тест. Сам обрыв через публичный API контроллера без живого движка не
// воспроизвести (события шлёт только TunnelEngine — та же причина, что в killswitch_test),
// поэтому тест фиксирует решающее правило ConnectionController.reconnectDelay, которым
// _scheduleReconnect выбирает паузу:
//   • попытки 1..4 — 2с, 5с, 15с, 30с; дальше каждые 60с, бессрочно: сеть может лежать долго,
//     и серия обязана жить, пока не подключится или человек не отменит её сам;
//   • тумблер ВЫКЛ → null на любой попытке: человек отказался — после обрыва остаёмся
//     отключёнными, как раньше;
//   • ручная НЕУДАЧА старта серии не создаёт (виджет-тест ниже): реконнект начинается только
//     после обрыва УСТАНОВЛЕННОГО соединения, иначе каждая опечатка в ключе долбила бы сеть
//     бессрочно. Отмена серии ручными действиями (кнопка/выход/«Снять блокировку») живёт в
//     toggle/reset/unblock контроллера и без живого движка не воспроизводится.
//
// Виджет-тест идёт только там, где движка действительно нет (CI-раннер, чистая машина). Если
// рядом лежит или стоит в PATH xray — тапать «Подключиться» нельзя: это подняло бы НАСТОЯЩИЙ
// туннель и переключило системный прокси (как в connect_no_engine_test).
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bitaps_vpn/engine.dart';
import 'package:bitaps_vpn/main.dart';

// Те же каналы плагинов, что и в connect_no_engine_test: без заглушек старт падает
// MissingPluginException.
const _channels = <String>[
  'window_manager',
  'screen_retriever',
  'screen_retriever_windows',
  'tray_manager',
  'hotkey_manager',
  'plugins.it_nomads.com/flutter_secure_storage',
  'dev.fluttercommunity.plus/package_info',
  'dev.fluttercommunity.plus/share',
  'plugins.flutter.io/url_launcher',
  'com.llfbandit.app_links/messages',
  'launch_at_startup',
  'flutter_v2ray_client',
];

final bool _noEngine = TunnelEngine.kind() == EngineKind.none;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('авто-реконнект: паузы 2/5/15/30 с, дальше каждые 60 с — бессрочно', () {
    expect(ConnectionController.reconnectDelay(true, 1), const Duration(seconds: 2));
    expect(ConnectionController.reconnectDelay(true, 2), const Duration(seconds: 5));
    expect(ConnectionController.reconnectDelay(true, 3), const Duration(seconds: 15));
    expect(ConnectionController.reconnectDelay(true, 4), const Duration(seconds: 30));
    expect(ConnectionController.reconnectDelay(true, 5), const Duration(seconds: 60),
        reason: 'после 30с пауза фиксируется на 60с');
    expect(ConnectionController.reconnectDelay(true, 100), const Duration(seconds: 60),
        reason: 'серия бессрочна: сотая попытка ждёт те же 60с');
  });

  test('авто-реконнект: тумблер выключен — ни одной попытки', () {
    for (var attempt = 1; attempt <= 6; attempt++) {
      expect(ConnectionController.reconnectDelay(false, attempt), isNull,
          reason: 'попытка $attempt: тумблер выключен — переподключаться нельзя');
    }
  });

  setUp(() {
    // Человек вошёл (стартовая вкладка — Главная), тумблер «Автопереподключение» не трогал
    // (по умолчанию ВКЛ) — и это важно: даже включённый тумблер не должен запускать серию
    // после ручной неудачи.
    SharedPreferences.setMockInitialValues({
      'seen_onboarding': true,
      'lang': 'ru',
      'hwid': 'testhwid0000000001',
      'tgId': 900000001,
    });
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final c in _channels) {
      m.setMockMethodCallHandler(MethodChannel(c), (call) async {
        if (call.method == 'read') {
          return (call.arguments as Map?)?['key'] == 'appToken' ? 'testtoken0000000001' : null;
        }
        if (call.method == 'readAll') return <String, String>{'appToken': 'testtoken0000000001'};
        if (call.method == 'getAll') return <String, Object>{};
        return null;
      });
    }
  });

  testWidgets('ручная неудача старта НЕ запускает авто-реконнект', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const BitApp());
    await tester.pump(const Duration(milliseconds: 400));

    final semantics = tester.ensureSemantics();
    await tester.tap(find.bySemanticsLabel('Подключиться'));
    await tester.pump();

    // Попытка упала (движка нет), причина на экране — как в connect_no_engine_test.
    expect(find.text('Подключение не выполнено'), findsOneWidget);
    // Серии быть не должно: ни сразу…
    expect(find.text('Переподключение…'), findsNothing,
        reason: 'ручная неудача — не обрыв: реконнект начинается только после установленного соединения');
    // …ни после первой паузы расписания (2с): ждём с запасом.
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Переподключение…'), findsNothing,
        reason: 'первая пауза (2с) прошла — попытки не случилось');
    expect(find.text('Подключение…'), findsNothing);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  }, skip: !_noEngine);
}
