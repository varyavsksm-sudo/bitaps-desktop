// Тесты локализации (i18n). Полноценный widget-тест на BitApp здесь не гоняем:
// приложение тянет нативные плагины (window_manager, secure_storage, shared_preferences),
// которых нет в чистом test-харнессе. Проверяем чистый слой tr() без плагинов.
import 'package:flutter_test/flutter_test.dart';
import 'package:bitaps_vpn/main.dart';

void main() {
  group('i18n tr()', () {
    setUp(() => appLang = 'ru');

    test('по умолчанию (ru) возвращает исходную строку', () {
      appLang = 'ru';
      expect(tr('Отмена'), 'Отмена');
      expect(tr('Настройки'), 'Настройки');
    });

    test('en отдаёт перевод из словаря', () {
      appLang = 'en';
      expect(tr('Отмена'), 'Cancel');
      expect(tr('Настройки'), 'Settings');
    });

    test('en для строки без перевода — фолбэк на исходник', () {
      appLang = 'en';
      const unknown = 'нет-такого-ключа-в-словаре-12345';
      expect(tr(unknown), unknown);
    });
  });
}
