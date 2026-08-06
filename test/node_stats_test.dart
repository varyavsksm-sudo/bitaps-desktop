// График доступности нод на «Серверах» — чистая логика публичной статистики.
//
// Зачем именно этот тест. Блок рисует CustomPaint по данным /public/stats: ошибки разбора
// или нормализации дают либо пустой/кривой график, либо падение вёрстки. Фиксируем контракт:
// разбор ответа (включая мусор), нормализация series в бакеты графика (мёртвые промежутки —
// разрывы, среднее по живым точкам бакета) и уровень цвета по среднему rtt.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bitaps_vpn/main.dart';

void main() {
  group('parseNodeStats — разбор /public/stats', () {
    test('валидный ответ: generated_at, ok/rtt_now, series с мёртвыми точками', () {
      final r = parseNodeStats('''
        {"generated_at": 1800000000,
         "nodes": [
           {"name":"🇫🇮 Финляндия","ok":true,"rtt_now":40,
            "series":[[1799999000,38],[1799999600,null],[1799999900,41]]},
           {"name":"🛡️ Нидерланды · LTE","ok":false,"rtt_now":null,"series":[]}
         ]}''');
      expect(r, isNotNull);
      expect(r!.generatedAt.millisecondsSinceEpoch, 1800000000 * 1000);
      expect(r.nodes.length, 2);
      final fi = r.nodes.first;
      expect(fi.ok, isTrue);
      expect(fi.rttNow, 40);
      expect(fi.series.length, 3);
      expect(fi.series[1].$2, isNull, reason: 'мёртвая точка — null, а не 0: 0 исказил бы среднее');
      final nl = r.nodes.last;
      expect(nl.ok, isFalse);
      expect(nl.rttNow, isNull);
    });

    test('мусор/не та форма → null (UI покажет «данные недоступны»)', () {
      expect(parseNodeStats('не json'), isNull);
      expect(parseNodeStats('[]'), isNull);
      expect(parseNodeStats('{"foo":1}'), isNull);
      expect(parseNodeStats(''), isNull);
    });

    test('битые точки series пропускаются, нода выживает', () {
      final r = parseNodeStats(
          '{"generated_at":1,"nodes":[{"name":"x","ok":true,"series":[["строка",5],[10],[20,33]]}]}');
      expect(r, isNotNull);
      expect(r!.nodes.single.series, [(20, 33)]);
    });
  });

  group('sparkPoints — нормализация series в точки графика', () {
    const from = 1000000, to = 1004800; // 80 минут окном

    test('живые точки усредняются в бакет, мёртвые бакеты — null (разрыв)', () {
      // окно 4800с / 8 бакетов → бакет = 600с: from+60/+120 → бакет 0, from+4000/+4100 → бакет 6
      final points = sparkPoints(
        [
          (from + 60, 40), (from + 120, 60), // бакет 0 → среднее 50
          // бакеты 1..5 пустые → null
          (from + 4000, 100), (from + 4100, null), // бакет 6: живая + мёртвая → 100
        ],
        buckets: 8, fromSec: from, toSec: to,
      );
      expect(points.length, 8);
      expect(points[0], closeTo(50, 0.001));
      for (final i in [1, 2, 3, 4, 5, 7]) {
        expect(points[i], isNull, reason: 'бакет $i без живых замеров — разрыв линии');
      }
      expect(points[6], closeTo(100, 0.001), reason: 'мёртвая точка бакета среднее не сдвигает');
    });

    test('пустая series → все разрывы', () {
      final points = sparkPoints(const [], buckets: 48, fromSec: from, toSec: to);
      expect(points.every((p) => p == null), isTrue);
    });

    test('точки вне окна клампятся в крайние бакеты, не роняя график', () {
      final points = sparkPoints(
        [(from - 500, 30), (to + 500, 90)],
        buckets: 8, fromSec: from, toSec: to,
      );
      expect(points[0], closeTo(30, 0.001));
      expect(points[7], closeTo(90, 0.001));
    });
  });

  group('sparkColor — цвет линии из акцента темы', () {
    // Неоново-оранжевый акцент Sunset — базовая палитра приложения.
    const sunset = Color(0xFFFF7A1A);

    test('тёмная тема: акцент без изменений', () {
      expect(sparkColor(sunset, light: false), sunset,
          reason: 'на тёмном фоне неон читается — не трогаем');
      expect(sparkColor(const Color(0xFF33FF66), light: false), const Color(0xFF33FF66),
          reason: '«Фосфор» только тёмный — акцент как есть');
    });

    test('светлая тема: тот же акцент, затемнённый по правилу accentSoftInk (lightness ≤ 0.38)', () {
      final c = sparkColor(sunset, light: true);
      expect(c, isNot(sunset), reason: 'неоновый оранжевый на белом выцветает — затемняем');
      final h = HSLColor.fromColor(c);
      // HSL↔RGB раундтрип даёт float-погрешность (0.3803… вместо 0.38) — сравнение с допуском
      expect(h.lightness, closeTo(0.38, 0.01));
      expect(h.hue, closeTo(HSLColor.fromColor(sunset).hue, 1.0),
          reason: 'оттенок палитры сохраняется — меняется только читаемость');
      // То же правило, что у остального UI: сверяем с каноническим accentSoftInk-подходом.
      final expected = HSLColor.fromColor(sunset).withLightness(0.38).toColor();
      expect(c, expected);
    });

    test('светлая тема: уже тёмный акцент не портим', () {
      const dark = Color(0xFF8A4A00); // lightness ≈ 0.27
      expect(sparkColor(dark, light: true), dark);
    });
  });
}
