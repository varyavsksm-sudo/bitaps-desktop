// Сцена B-box: коробка на углу + шестерёнка с буквой B.
//
// Рисование проверялось РЕНДЕРОМ в картинку — так нашлись две настоящие беды: куб вылезал за
// холст почти вдвое и висел боком вместо стойки на углу (ось наклона была с обратным знаком).
// В репозитории оставлена быстрая проверка: сцена строится и рисует без исключений на разных
// фазах оборота. Полный рендер в PNG в наборе тестов подвешивал прогон, а падающий из-за
// инструмента прогон хуже, чем отсутствие этой проверки.
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bitaps_vpn/main.dart';

void main() {
  test('painter рисует на всех фазах оборота и не бросает', () {
    for (final phase in [0.0, 0.17, 0.33, 0.5, 0.83, 1.0]) {
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      BBoxPainter(phase, const Color(0xFFFF7A1A), const Color(0xFFFFB347), const Color(0xFFEDF1F8))
          .paint(canvas, const Size(320, 320));
      final pic = rec.endRecording();
      expect(pic, isNotNull);
      pic.dispose();
    }
  });

  testWidgets('сцена встраивается и живёт с анимацией', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(body: SizedBox(width: 300, height: 300, child: BBoxScene())),
    ));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(BBoxScene), findsOneWidget);
    // гасим бесконечную анимацию, иначе pumpWidget(null) в teardown ждёт её вечно
    await t.pumpWidget(const SizedBox.shrink());
  });
}
