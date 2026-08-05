// Пул замера флота (runPooled): ограничение одновременности и полнота выполнения.
//
// Зачем именно этот тест. Кнопка «Проверить серверы» гоняет по узлам тяжёлый probe (процесс
// xray на узел): последовательный обход флота шёл минутами, а безлимитный параллелизм поднял
// бы 13+ процессов разом. Пул обязан (а) не превышать заданную одновременность, (б) выполнить
// ВСЕ задачи, (в) вернуть результаты по индексам задач, а не по порядку завершения. Движок
// здесь не нужен — проверяется чистая механика семафора (как noEngine-тесты: без туннеля).
import 'package:flutter_test/flutter_test.dart';
import 'package:bitaps_vpn/engine.dart';

void main() {
  test('runPooled: одновременность не превышает lanes, все задачи выполнены', () async {
    var active = 0, maxActive = 0, finished = 0;
    final tasks = <Future<int> Function()>[
      for (var i = 0; i < 13; i++)
        () async {
          active++;
          if (active > maxActive) maxActive = active;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          active--;
          finished++;
          return i;
        },
    ];
    final results = await runPooled(tasks, 6);
    expect(maxActive, lessThanOrEqualTo(6), reason: 'пул поднял больше lanes одновременно');
    expect(maxActive, greaterThan(1), reason: 'пул не параллелит — смысл теряется');
    expect(finished, 13, reason: 'часть задач потерялась');
    expect(results.length, 13);
  });

  test('runPooled: результаты — по индексам задач, а не по порядку завершения', () async {
    // ранняя задача медленнее поздних: если бы порядок был «по завершению», ноль уехал бы в конец
    final results = await runPooled<int>([
      () async { await Future<void>.delayed(const Duration(milliseconds: 60)); return 0; },
      () async => 1,
      () async => 2,
      () async => 3,
    ], 3);
    expect(results, [0, 1, 2, 3]);
  });

  test('runPooled: lanes больше числа задач и пустой список — без зависаний', () async {
    final few = await runPooled<int>([() async => 1, () async => 2], 6);
    expect(few, [1, 2]);
    final none = await runPooled<int>(const [], 6);
    expect(none, isEmpty);
  });
}
