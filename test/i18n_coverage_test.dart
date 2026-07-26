// Полнота перевода: каждая строка, обёрнутая в tr(), обязана быть в словаре _kEn.
//
// Зачем. tr() устроен как «нет перевода — верни как есть», поэтому забытая строка не роняет
// ни сборку, ни анализатор: в английском интерфейсе просто остаётся русский текст. Именно так
// накопились пропуски, которые пользователь и увидел. Тест читает исходники и сверяет два
// множества — новая tr('…') без записи в словаре теперь валит тесты.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

final _key = RegExp(r"tr\('((?:[^'\\]|\\.)*)'\)");
final _dictKey = RegExp(r"^\s*'((?:[^'\\]|\\.)*)'\s*:", multiLine: true);
final _cyr = RegExp(r'[а-яё]', caseSensitive: false);

void main() {
  test('каждая строка из tr() есть в словаре EN', () {
    final root = Directory('lib');
    final dictSrc = File('lib/i18n.dart').readAsStringSync();
    final dict = _dictKey.allMatches(dictSrc).map((m) => m.group(1)!).toSet();
    expect(dict.length, greaterThan(200), reason: 'словарь не разобрался — проверь регулярку');

    final missing = <String, String>{};
    for (final f in root.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.endsWith('i18n.dart')) continue;
      final src = f.readAsStringSync();
      for (final m in _key.allMatches(src)) {
        final k = m.group(1)!;
        if (!_cyr.hasMatch(k) || dict.contains(k)) continue;
        missing[k] = f.path.split('/').last;
      }
    }
    expect(missing, isEmpty,
        reason: 'нет перевода EN:\n${missing.entries.map((e) => '  ${e.value}: ${e.key}').join('\n')}');
  });
}
