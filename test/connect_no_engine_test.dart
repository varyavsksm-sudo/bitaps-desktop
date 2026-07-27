// Система, на которой туннель поднять нечем: нажатие «Подключиться» обязано ОБЪЯСНИТЬ это,
// а не уйти в демо-сессию.
//
// Зачем именно этот тест. Раньше при отсутствующем движке приложение молча запускало демо:
// 1.7 с спиннера, потом бежал таймер, крутились выдуманные скорости и IP. Экран выглядел
// работающим, и оплативший человек не понимал, почему YouTube не открылся — а узнать это
// было неоткуда. Тест держит новое поведение: статус остаётся «Отключено», на экране висит
// причина, слова «Демо-режим» без явного тумблера в Настройках не появляется.
//
// Тест идёт только там, где движка действительно нет (CI-раннер, чистая машина). Если рядом
// лежит или стоит в PATH xray — путь другой, и тапать «Подключиться» в тесте нельзя: это
// подняло бы НАСТОЯЩИЙ туннель и переключило системный прокси.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bitaps_vpn/engine.dart';
import 'package:bitaps_vpn/main.dart';

// Те же каналы плагинов, что и в shell_render_test: без заглушек старт падает MissingPluginException.
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

  setUp(() {
    // Человек вошёл (стартовая вкладка — Главная) и тумблер «Демо-режим» не трогал.
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

  // Два размера, как в shell_render_test: карточка причины несёт ряд из двух кнопок, и
  // переполнение вёрстки вылезло бы именно на узком телефоне.
  for (final screen in const [(1170.0, 2532.0, 3.0, '390x844'), (720.0, 1280.0, 2.0, '360x640')]) {
  testWidgets('${screen.$4}: без движка «Подключиться» показывает причину, а не демо-сессию', (tester) async {
    tester.view.physicalSize = Size(screen.$1, screen.$2);
    tester.view.devicePixelRatio = screen.$3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const BitApp());
    await tester.pump(const Duration(milliseconds: 400));

    // Кнопка подключения — Semantics-узел с лейблом «Подключиться» (визуал из него исключён).
    // Handle гасим до конца теста: харнесс проверяет это раньше, чем отработает addTearDown.
    final semantics = tester.ensureSemantics();
    await tester.tap(find.bySemanticsLabel('Подключиться'));
    await tester.pump();

    expect(find.text('Подключение не выполнено'), findsOneWidget, reason: 'причина отказа не показана');
    // Причина видна дважды намеренно: карточка на Главной + тост (подключение могли запустить
    // хоткеем или из трея с другой вкладки, где карточки не видно).
    expect(find.text('На этой системе туннель ещё не поддержан'), findsWidgets);
    expect(find.text('Отключено'), findsWidgets, reason: 'статус должен вернуться в «Отключено»');
    expect(find.text('Демо-режим'), findsNothing, reason: 'демо не должно включаться само');

    // Демо-сессия обязана НЕ стартовать и позже: раньше она поднималась через 1.7 с.
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Демо-режим'), findsNothing);
    expect(find.text('Подключено'), findsNothing);
    expect(tester.takeException(), isNull, reason: 'карточка причины сломала вёрстку');
    semantics.dispose();
  }, skip: !_noEngine);
  }
}
