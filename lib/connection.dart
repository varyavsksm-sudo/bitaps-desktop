part of 'main.dart';

// ============================ CONNECTION CONTROLLER ============================
// Жизненный цикл VPN-подключения вынесен из ShellState (god-object): здесь живут состояние
// туннеля (conn/secs/скорость/поколение/таймеры/счётчик трафика) и вся логика connect/disconnect,
// обрыва и демо-сессии. Контроллер НЕ знает про виджеты — зависимости от UI прокинуты колбэками:
//   keyOf/serverOf   — актуальные ключ и выбранный сервер из ShellState
//   dropAlertOn      — тумблер «Обрыв соединения»
//   trafWarnOn       — тумблер «Лимит трафика»
//   onToast          — показать тост (реализует ShellState)
//   onPersist        — сохранить состояние (_save; нужен для счётчика сессий)
//   onSpin(fast)     — крутить кнопку-шестерёнку: быстро во время коннекта, медленно в покое
// Обновления UI идут через ChangeNotifier: ShellState слушает и делает setState.
class ConnectionController extends ChangeNotifier {
  ConnectionController({
    required this.keyOf,
    required this.serverOf,
    required this.dropAlertOn,
    required this.trafWarnOn,
    required this.onToast,
    required this.onPersist,
    required this.onSpin,
  });

  final String Function() keyOf;
  final Server Function() serverOf;
  final bool Function() dropAlertOn;
  final bool Function() trafWarnOn;
  final void Function(String msg) onToast;
  final Future<void> Function() onPersist;
  final void Function(bool fast) onSpin;

  int conn = 0; // 0 off · 1 connecting · 2 on
  int secs = 0;
  int down = 0, up = 0;
  int sessions = 0;
  int _gen = 0; // поколение подключения: гасит «поздние» коллбэки отменённых/сменённых попыток
  Timer? _timer;
  StreamSubscription<Map<String, dynamic>>? _tunEvents;
  double _sessMB = 0;       // накопленный расход за текущую сессию (для «Лимит трафика»)
  bool _trafWarned = false; // предупреждение о большом расходе уже показано в этой сессии
  bool _disposed = false;
  final math.Random _rnd = math.Random();

  String get hms {
    if (secs >= 86400) {
      final d = secs ~/ 86400;
      final h = (secs % 86400) ~/ 3600;
      return '${d}d ${h}h';
    }
    final h = (secs ~/ 3600).toString().padLeft(2, '0');
    final m = ((secs % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (secs % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  Future<void> toggle() async {
    if (conn == 1) {
      // отмена во время «Подключение…»: инвалидируем поколение → awaited/отложенный коллбэк отвалится
      _gen++;
      if (kRealTunnel) await NativeTunnel.disconnect();
      _stopWatch();
      onSpin(false);
      conn = 0;
      notifyListeners();
      return;
    }
    if (conn == 0) {
      final gen = ++_gen; // это конкретное подключение; отмена/реконнект сменят _gen
      conn = 1;
      notifyListeners();
      onSpin(true);

      if (kRealTunnel) {
        // БОЕВОЙ режим: поднимаем НАСТОЯЩИЙ туннель через нативный движок sing-box.
        final key = keyOf();
        // пускаем все схемы, что умеет singbox_config (не только vless://) — иначе валидный
        // trojan/vmess/ss/hysteria2-ключ ложно отвергался бы «Нужен рабочий VPN-ключ».
        if (!kSupportedKeySchemes.any((s) => key.startsWith(s))) { _fail(gen, tr('Нужен рабочий VPN-ключ')); return; }
        String cfg;
        try {
          cfg = singboxConfigJson(key);
        } catch (e) {
          _fail(gen, appLang == 'en' ? 'Key is corrupted: $e' : 'Ключ повреждён: $e');
          return;
        }
        try {
          // таймаут: если нативный движок завис и не вернул ни успех, ни ошибку — не залипаем
          // навсегда в «Подключение…», а честно откатываемся в «выключено» с тостом.
          await NativeTunnel.connect(cfg, server: serverOf().city)
              .timeout(const Duration(seconds: 30));
        } on TunnelUnavailable catch (e) {
          _fail(gen, '$e');
          return;
        } on TimeoutException {
          _fail(gen, appLang == 'en' ? 'Connection timed out' : 'Подключение не удалось — таймаут');
          return;
        } catch (e) {
          _fail(gen, appLang == 'en' ? 'Failed to connect: $e' : 'Не удалось подключиться: $e');
          return;
        }
        if (_disposed || gen != _gen) { await NativeTunnel.disconnect(); return; } // отменили во время старта
        _startSession(down: 0, up: 0);
        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (_disposed) return;
          secs++; _accTraffic(); notifyListeners();
        });
        // РЕАЛЬНАЯ статистика/статус из движка — никаких выдуманных чисел
        _tunEvents = NativeTunnel.events().listen((e) {
          if (_disposed || gen != _gen) return;
          final st = e['state']?.toString();
          if (st == 'error' || st == 'disconnected') { _dropped(gen); return; }
          if (e['down'] is num) down = (e['down'] as num).round();
          if (e['up'] is num) up = (e['up'] as num).round();
          notifyListeners();
        });
        return;
      }

      // ДЕМО-режим (kRealTunnel=false): туннель НЕ поднимается — показываем демо-сессию
      // с явной пометкой «демо» в UI (см. home.dart). Цифры условны, это НЕ реальная защита.
      Future.delayed(const Duration(milliseconds: 1700), () {
        if (_disposed || gen != _gen) return; // «поздний» коллбэк отменённой попытки — игнор
        _startSession(down: 84, up: 13);
        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (_disposed) return;
          secs++; down = 60 + _rnd.nextInt(70); up = 8 + _rnd.nextInt(20); _accTraffic(); notifyListeners();
        });
      });
    } else {
      _gen++; // отключение инвалидирует любое незавершённое поколение
      if (kRealTunnel) await NativeTunnel.disconnect();
      _stopWatch();
      onSpin(false);
      conn = 0; secs = 0;
      notifyListeners();
    }
  }

  // старт сессии: обнуляем счётчики трафика/времени и поднимаем статус в «Подключено»
  void _startSession({required int down, required int up}) {
    conn = 2; secs = 0; this.down = down; this.up = up; sessions++;
    _sessMB = 0; _trafWarned = false;
    notifyListeners();
    onPersist();
  }

  // сброс наблюдателей туннеля (таймер секунд + поток статистики движка)
  void _stopWatch() {
    _timer?.cancel(); _timer = null;
    _tunEvents?.cancel(); _tunEvents = null;
  }

  // накопление расхода за сессию + разовое предупреждение при большом расходе («Лимит трафика»)
  void _accTraffic() {
    // Движок шлёт down/up в kbps (килобитах/с) — см. NativeTunnel.events() контракт.
    // kbps → МБ за 1 сек: делим на 8 (бит→байт) и на 1024 (КБ→МБ). Без /8 расход завышался в 8 раз.
    _sessMB += (down + up) / (8 * 1024.0);
    if (trafWarnOn() && !_trafWarned && _sessMB >= kTrafficWarnMB) {
      _trafWarned = true;
      onToast(appLang == 'en'
          ? 'Session usage passed ${(kTrafficWarnMB / 1024).toStringAsFixed(0)} GB'
          : 'Расход за сессию превысил ${(kTrafficWarnMB / 1024).toStringAsFixed(0)} ГБ');
    }
  }

  // боевой режим: не удалось подключиться — честно откатываемся в «выключено» + тост
  void _fail(int gen, String msg) {
    if (_disposed || gen != _gen) return;
    _stopWatch();
    onSpin(false);
    conn = 0;
    notifyListeners();
    onToast(msg);
  }

  // движок сообщил об обрыве соединения — снимаем «подключено»
  void _dropped(int gen) {
    if (_disposed || gen != _gen) return;
    _stopWatch();
    onSpin(false);
    conn = 0; secs = 0;
    notifyListeners();
    // «Обрыв соединения»: уведомляем об обрыве, только если включён тумблер
    if (dropAlertOn()) onToast(tr('Соединение разорвано'));
  }

  // полный сброс подключения (напр. при выходе из аккаунта): гасит поколение, таймеры, статус
  void reset() {
    _gen++;
    _stopWatch();
    onSpin(false);
    conn = 0; secs = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopWatch();
    super.dispose();
  }
}
