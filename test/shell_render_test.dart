// Рендер-тест оболочки в МОБИЛЬНОЙ раскладке: собираем настоящий интерфейс и проверяем, что
// контент вообще виден, а каждая вкладка строится без исключений.
//
// Зачем именно так. Приложение однажды приехало к людям с пустым экраном: нижний бар забирал
// всю высоту Scaffold, телу оставалось ноль пикселей. Исключения при этом НЕ было — экран
// честно строился пустым, поэтому ни анализатор, ни прежние тесты ничего не замечали. А на
// десктопе (широкое окно) вместо нижнего бара работает боковой рейл, и там всё выглядело
// нормально. Отсюда два обязательных условия ниже: высота тела > 0 и текст на экране есть.
//
// Нативные плагины (окно, трей, хоткеи, хранилище) в тест-харнессе отсутствуют — подменяем
// их каналы заглушками, поведение интерфейса от этого не зависит.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bitaps_vpn/main.dart';

// Каналы плагинов, которые оболочка дёргает на старте. Ответы не важны — важно, чтобы вызов
// не падал MissingPluginException.
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Состояние «знакомство пройдено» — то, что видит человек при обычном запуске.
    SharedPreferences.setMockInitialValues({
      'seen_onboarding': true,
      'lang': 'ru',
      'hwid': 'testhwid0000000001',
      'tgId': 900000001,
    });
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final c in _channels) {
      m.setMockMethodCallHandler(MethodChannel(c), (call) async {
        // Токен входа лежит в защищённом хранилище: отдаём его, чтобы проверять экраны в
        // состоянии «человек вошёл» — именно там и был замечен пустой экран. PIN не отдаём,
        // иначе оболочка покажет экран блокировки вместо интерфейса.
        if (call.method == 'read') {
          return (call.arguments as Map?)?['key'] == 'appToken' ? 'testtoken0000000001' : null;
        }
        if (call.method == 'readAll') return <String, String>{'appToken': 'testtoken0000000001'};
        if (call.method == 'getAll') return <String, Object>{};
        return null;
      });
    }
  });

  // Два размера: типовой современный телефон и узкий бюджетный. Второй важен — переполнения
  // вёрстки вылезают именно на нём, а на широком экране их не видно.
  for (final screen in const [(1170.0, 2532.0, 3.0, '390x844'), (720.0, 1280.0, 2.0, '360x640')]) {
  testWidgets('мобильная раскладка ${screen.$4}: контент виден, все вкладки строятся', (tester) async {
    tester.view.physicalSize = Size(screen.$1, screen.$2);
    tester.view.devicePixelRatio = screen.$3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const BitApp());
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull, reason: 'стартовый экран не собрался');

    // Ключевая проверка: телу Scaffold досталась ненулевая высота. Именно её потеря и делала
    // экран пустым, не вызывая никакой ошибки.
    final body = tester.renderObject<RenderBox>(find.byType(Stack).first);
    expect(body.size.height, greaterThan(400),
        reason: 'у контента ${body.size.height.toInt()}px высоты — нижний бар съел экран');

    // И осмысленный текст на экране, а не только подписи вкладок.
    final texts = tester.widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '').where((s) => s.isNotEmpty).toList();
    expect(texts.length, greaterThan(6), reason: 'на экране почти нет текста: $texts');

    for (final label in ['Серверы', 'Кабинет', 'Настройки', 'Главная']) {
      final tab = find.text(label);
      expect(tab, findsWidgets, reason: 'вкладка «$label» не отрисовалась');
      await tester.tap(tab.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull, reason: 'экран «$label» не собрался');
      expect(tester.widgetList<Text>(find.byType(Text)).length, greaterThan(6),
          reason: 'экран «$label» пустой');
    }
  });
  }
}
