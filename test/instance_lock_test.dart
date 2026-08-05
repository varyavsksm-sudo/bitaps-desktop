// Одна копия приложения (single-instance): решение по занятому порту + живой прогон протокола.
//
// Зачем. Вторая копия при живом VPN первой — fail-open (доходила до cleanupStale и снимала
// «наш» прокси при живом туннеле, аудит п.1). Но и обратная ошибка недопустима: порт,
// занятый ЧУЖИМ процессом, не должен блокировать наш запуск — иначе постороннее приложение
// на 47631 превращалось бы в запрет запуска VPN. Поэтому решение — по рукопожатию magic,
// и обе ветки зафиксированы: чистой функцией и реальным ServerSocket-прогоном.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bitaps_vpn/instance_lock.dart';

void main() {
  test('resolveInstanceVerdict: решение по занятому порту', () {
    expect(resolveInstanceVerdict(lockTaken: true, peerIsOurs: false),
        InstanceVerdict.primary,
        reason: 'порт заняли мы — первая копия');
    expect(resolveInstanceVerdict(lockTaken: true, peerIsOurs: true),
        InstanceVerdict.primary);
    expect(resolveInstanceVerdict(lockTaken: false, peerIsOurs: true),
        InstanceVerdict.secondary,
        reason: 'отвечает наш протокол — первая копия жива, мы лишние');
    expect(resolveInstanceVerdict(lockTaken: false, peerIsOurs: false),
        InstanceVerdict.foreignSquatter,
        reason: 'чужой процесс на порту НЕ должен блокировать наш запуск');
  });

  test('живой прогон: вторая копия узнаёт первую по протоколу и просит подняться', () async {
    // Отдельный от приложения порт: боевой 47631 на машине разработчика может быть занят.
    const testPort = 47687;
    final first = await InstanceLock.acquire(port: testPort);
    expect(first.verdict, InstanceVerdict.primary);
    expect(first.lock, isNotNull);
    var raised = false;
    first.lock!.onRaise = () => raised = true;
    try {
      final second = await InstanceLock.acquire(port: testPort);
      expect(second.verdict, InstanceVerdict.secondary,
          reason: 'рукопожатие magic: вторая копия распознала первую');
      expect(second.lock, isNull);
      // onRaise дёргается из слушателя серверного сокета — даже после подтверждения
      // колбэк мог ещё не отработать: ждём его, а не фиксируем гонку в тесте.
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (!raised && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(raised, isTrue, reason: 'первая копия получила просьбу «поднимись»');
    } finally {
      await first.lock?.release();
    }
    // После освобождения порта новая попытка снова становится primary.
    final again = await InstanceLock.acquire(port: testPort);
    expect(again.verdict, InstanceVerdict.primary);
    await again.lock?.release();
  });

  test('чужой процесс на порту — запускаемся без блокировки (foreignSquatter)', () async {
    const testPort = 47688;
    final squatter = await ServerSocket.bind(InternetAddress.loopbackIPv4, testPort);
    // Молчаливый чужой слушатель: соединения принимает, наш протокол не отвечает.
    final sub = squatter.listen((c) => c.destroy());
    try {
      final res = await InstanceLock.acquire(port: testPort);
      expect(res.verdict, InstanceVerdict.foreignSquatter);
      expect(res.lock, isNull);
    } finally {
      await sub.cancel();
      await squatter.close();
    }
  });
}
