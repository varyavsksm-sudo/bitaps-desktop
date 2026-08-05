// Одна копия приложения на десктопе (single-instance) — БЕЗ новых нативных зависимостей.
//
// Зачем. Вторая копия, запущенная при живом VPN первой, — это не просто лишнее окно:
// на старте она выполняет SystemProxy.cleanupStale (см. desktop_engine.dart) и могла снять
// «наш» системный прокси при ЖИВОМ туннеле первой копии — трафик молча пошёл напрямую
// (fail-open, аудит п.1). Поэтому вторая копия не должна доходить даже до уборки: она
// активирует окно первой и завершается.
//
// Механика (app-level, только dart:io): первая копия при старте занимает фиксированный
// порт на loopback (ServerSocket.bind) и держит его до выхода. Вторая копия bind'ить тот же
// порт не может → стучится на него протоколом «raise <magic>»; первая отвечает «ok <magic>»
// и поднимает своё окно (колбэк onRaise подключает main.dart к window_manager). Рукопожатие
// по magic обязательно: порт мог занять ЧУЖОЙ процесс — тогда мы НЕ «вторая копия» и обязаны
// запуститься (иначе постороннее приложение на этом порту блокировало бы наш запуск).
//
// Порт kInstanceLockPort выбран фиксированным в диапазоне 476xx (не конфликтует с эфемерными
// портами туннеля — те берутся через bind(0), и с типичными dev-сервисами). Менять нельзя:
// между версиями приложения он и есть «мьютекс» одной копии.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Решение по занятому порту блокировки — вынесено в чистую функцию (покрыто instance_lock_test).
enum InstanceVerdict {
  /// Порт заняли мы — это первая (и единственная) копия.
  primary,

  /// Порт занят и отвечает нашим протоколом — первая копия жива, мы лишние: активировать
  /// её окно и завершиться.
  secondary,

  /// Порт занят чужим процессом (наш протокол не ответил) — запускаемся без блокировки.
  foreignSquatter,
}

InstanceVerdict resolveInstanceVerdict({required bool lockTaken, required bool peerIsOurs}) {
  if (lockTaken) return InstanceVerdict.primary;
  return peerIsOurs ? InstanceVerdict.secondary : InstanceVerdict.foreignSquatter;
}

/// Результат попытки занять блокировку: решение и (для primary) сам держатель сокета.
typedef InstanceAcquire = ({InstanceVerdict verdict, InstanceLock? lock});

class InstanceLock {
  InstanceLock._(this._server);

  final ServerSocket _server;

  /// Фиксированный порт блокировки одной копии (см. шапку файла — выбран, задокументирован,
  /// не менять). 127.0.0.1 only: снаружи стукнуться нельзя.
  static const int kInstanceLockPort = 47631;

  /// Метка протокола между копиями: по ней вторая копия отличает наш первый экземпляр от
  /// чужого процесса, случайно занявшего порт.
  static const String magic = 'bitaps-vpn-instance/1';

  /// Просьба «поднимись» от второй копии: main.dart подключает сюда window_manager
  /// (show+focus) после инициализации окна. Может быть заменён — поле, а не final.
  void Function()? onRaise;

  /// Занять блокировку. Первой копии — держатель сокета (живёт до выхода процесса,
  /// освобождается ОС). [port] параметризован ради тестов.
  static Future<InstanceAcquire> acquire({int port = kInstanceLockPort}) async {
    ServerSocket? server;
    try {
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    } catch (_) {
      server = null; // порт занят — разбираемся, кем
    }
    if (server != null) {
      final lock = InstanceLock._(server);
      lock._serve();
      return (verdict: InstanceVerdict.primary, lock: lock);
    }
    final ours = await _pokePrimary(port);
    return (verdict: resolveInstanceVerdict(lockTaken: false, peerIsOurs: ours), lock: null);
  }

  /// Отвечать вторым копиям: валидная просьба → onRaise + подтверждение по протоколу.
  /// Мусор/чужие клиенты на порту тихо закрываются.
  void _serve() {
    _server.listen((conn) async {
      try {
        final first = await conn.first.timeout(const Duration(seconds: 2));
        if (utf8.decode(first, allowMalformed: true).trim() == 'raise $magic') {
          onRaise?.call();
          conn.writeln('ok $magic');
          await conn.flush();
        }
      } catch (_) {/* таймаут/битые байты — просто закрываем соединение */}
      try { await conn.close(); } catch (_) {}
    });
  }

  /// Стукнуться к первой копии: попросить показать окно. true — ответили нашим протоколом
  /// (это точно мы), false — порт занят чужим или не отвечает.
  static Future<bool> _pokePrimary(int port) async {
    Socket? s;
    try {
      s = await Socket.connect(InternetAddress.loopbackIPv4, port,
          timeout: const Duration(milliseconds: 500));
      s.writeln('raise $magic');
      await s.flush();
      final reply = await s.first.timeout(const Duration(milliseconds: 700));
      return utf8.decode(reply, allowMalformed: true).trim().startsWith('ok $magic');
    } catch (_) {
      return false;
    } finally {
      s?.destroy();
    }
  }

  /// Освободить блокировку (тесты; в приложении сокет живёт до выхода процесса).
  Future<void> release() async {
    try { await _server.close(); } catch (_) {}
  }
}
