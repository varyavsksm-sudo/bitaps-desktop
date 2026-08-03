part of 'main.dart';

/// Что предложить сделать с неудачной попыткой подключения — кнопка под причиной на Главной.
/// Причина без действия оставляет человека там же, где и молчание: «не работает, и что теперь».
enum ConnFix {
  /// Действия нет — достаточно объяснения (например, повторить попытку).
  none,
  /// Обновить подписку: истекла, занят лимит устройств, узлов не пришло.
  refreshSub,
  /// Отдать ключ стороннему клиенту Happ — он умеет то, что не умеет наш движок.
  happ,
  /// Сами не починим — довести человека до поддержки.
  support,
  /// Узел не пропускает трафик: выбрать другой сервер (кнопка ведёт на список).
  pickOther,
}

// ============================ CONNECTION CONTROLLER ============================
// Жизненный цикл VPN-подключения вынесен из ShellState (god-object): здесь живут состояние
// туннеля (conn/secs/скорость/поколение/таймеры/счётчик трафика) и вся логика connect/disconnect,
// обрыва и демо-сессии. Контроллер НЕ знает про виджеты — зависимости от UI прокинуты колбэками:
//   keyOf/serverOf   — актуальные ключ и выбранный сервер из ShellState
//   dropAlertOn      — тумблер «Обрыв соединения»
//   trafWarnOn       — тумблер «Лимит трафика»
//   killSwitchOn     — тумблер «Килл-свитч»: при НЕОЖИДАННОМ обрыве держим fail-closed
//   demoOn           — тумблер «Демо-режим» (Настройки): разрешена ли демо-сессия без движка
//   onToast          — показать тост (реализует ShellState)
//   onPersist        — сохранить состояние (_save; нужен для счётчика сессий)
//   onSpin(fast)     — крутить кнопку-шестерёнку: быстро во время коннекта, медленно в покое
// Обновления UI идут через ChangeNotifier: ShellState слушает и делает setState.
class ConnectionController extends ChangeNotifier {
  ConnectionController({
    required this.keyOf,
    required this.hwidOf,
    required this.serverOf,
    required this.onNodes,
    required this.nodeTagOf,
    required this.dropAlertOn,
    required this.trafWarnOn,
    required this.killSwitchOn,
    required this.demoOn,
    required this.onNodeDead,
    required this.onToast,
    required this.onPersist,
    required this.onSpin,
  });

  final String Function() keyOf;
  /// Идентификатор устройства для заголовка x-hwid при загрузке подписки (лимит устройств).
  final String Function() hwidOf;
  final Server Function() serverOf;
  /// Свежие узлы подписки — чтобы список серверов в интерфейсе не расходился с тем,
  /// к чему реально подключаемся.
  final void Function(List<SubNode>) onNodes;
  /// Тег узла при ручном выборе сервера (null — авто-выбор лучшего).
  final String? Function() nodeTagOf;
  final bool Function() dropAlertOn;
  final bool Function() trafWarnOn;
  /// Тумблер «Килл-свитч» (Настройки): при НЕОЖИДАННОМ обрыве VPN трафик блокируется
  /// (fail-closed), а не идёт напрямую. По умолчанию ВЫКЛ.
  final bool Function() killSwitchOn;
  /// Разрешена ли демо-сессия там, где движка нет. По умолчанию ВЫКЛЮЧЕНА: молчаливое демо
  /// после оплаты выглядело как рабочий VPN и человек не понимал, почему ничего не открывается.
  final bool Function() demoOn;
  /// Узел не пропустил трафик — записать приговор, чтобы он не считался доступным.
  final void Function(String nodeTag) onNodeDead;
  final void Function(String msg) onToast;
  final Future<void> Function() onPersist;
  final void Function(bool fast) onSpin;

  int conn = 0; // 0 off · 1 connecting · 2 on
  /// Почему последняя попытка не удалась (null — причин нет). Тост живёт три секунды, а человек
  /// к этому моменту смотрит на «Отключено · нажми на кнопку» и читает это как «нажатие не
  /// сработало». Причина обязана оставаться на экране до следующей попытки — см. карточку на Главной.
  String? failMsg;
  ConnFix failFix = ConnFix.none;
  /// Килл-свитч сработал: VPN отвалился НЕОЖИДАННО (не по кнопке) и системный прокси нарочно
  /// не снят — трафик заблокирован (fail-closed). Живёт до кнопки «Снять блокировку» или новой
  /// попытки подключения. Нарочно НЕ персистится: при старте приложения протухший прокси всё
  /// равно снимает cleanupStale (main.dart) — после перезапуска блокировки фактически нет,
  /// и UI не должен её выдумывать.
  bool blocked = false;
  int secs = 0;
  int down = 0, up = 0;
  int sessions = 0;
  int _gen = 0; // поколение подключения: гасит «поздние» коллбэки отменённых/сменённых попыток
  Timer? _timer;
  StreamSubscription<EngineEvent>? _tunEvents;
  double _sessMB = 0;       // накопленный расход за текущую сессию (для «Лимит трафика»)
  bool _trafWarned = false; // предупреждение о большом расходе уже показано в этой сессии
  bool _disposed = false;
  final math.Random _rnd = math.Random();

  String get hms {
    if (secs >= 86400) {
      final d = secs ~/ 86400;
      final h = (secs % 86400) ~/ 3600;
      return appLang == 'en' ? '${d}d ${h}h' : '$dд $hч';
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
      if (kRealTunnel) { await TunnelEngine.instance.disconnect(); gEngineReal = false; }
      _stopWatch();
      onSpin(false);
      conn = 0;
      notifyListeners();
      return;
    }
    if (conn == 0) {
      // Новая попытка из состояния блокировки сперва снимает её: килл-свитч — защита от
      // НЕОЖИДАННОГО обрыва, а явный коннект — осознанное действие человека. Прокси перед
      // подключением всё равно переписывается (_connectDesktop → _stopDesktop), но снимаем
      // уже здесь — до загрузки подписки и системного диалога разрешения.
      if (blocked) { blocked = false; await TunnelEngine.instance.disconnect(); }
      final gen = ++_gen; // это конкретное подключение; отмена/реконнект сменят _gen
      conn = 1;
      failMsg = null; failFix = ConnFix.none; // новая попытка — старую причину с экрана убираем
      notifyListeners();
      onSpin(true);

      // Боевой режим возможен, только если на этой платформе реально есть движок:
      // на десктопе — лежащий рядом xray (он умеет и узлы «белого списка»), на мобильных —
      // нативная сторона. Нет движка → остаёмся в честном демо-режиме, как раньше.
      final engineKind = TunnelEngine.kind();
      if (kRealTunnel && engineKind != EngineKind.none) {
        // БОЕВОЙ режим: поднимаем НАСТОЯЩИЙ туннель.
        // trim + lowercase-схема как в парсере (singboxConfigJson тоже триммит/нормализует): иначе
        // ключ с ведущим пробелом или «VLESS://» гард отверг бы, хотя парсер его разбирает.
        final key = keyOf().trim();
        // Демо-заглушка — НЕ ключ: синтаксически она валидна (vless://…), но pbk у неё
        // ненастоящий, и без этого гарда коннект умирал бы невнятной ошибкой движка.
        if (key == kDemoKey) { _fail(gen, tr('Сначала войди или импортируй ключ'), fix: ConnFix.refreshSub); return; }
        // Подписка (https://…/u/<token>) — не одиночный ключ: её надо СКАЧАТЬ и собрать конфиг
        // из всех узлов сразу. Одиночные share-link'и идут прежним путём без изменений.
        final isSub = isSubscriptionUrl(key);
        // пускаем все схемы, что умеет singbox_config (не только vless://) — иначе валидный
        // trojan/vmess/ss/hysteria2-ключ ложно отвергался бы «Нужен рабочий VPN-ключ».
        if (!isSub && !kSupportedKeySchemes.any((s) => key.toLowerCase().startsWith(s))) { _fail(gen, tr('Нужен рабочий VPN-ключ'), fix: ConnFix.refreshSub); return; }
        List<SubNode> nodes = const [];
        if (isSub) {
          final sub = await fetchSubscription(key, hwid: hwidOf(), deviceOs: Platform.operatingSystem);
          if (_disposed || gen != _gen) return; // отменили, пока грузилась подписка
          // Сервис отвечает уведомлением вместо узлов: подписка истекла / исчерпан лимит устройств.
          // Показываем его текст как есть — он уже написан для пользователя и локализован сервисом.
          if (sub.notice != null && !sub.ok) { _fail(gen, sub.notice!, fix: ConnFix.refreshSub); return; }
          if (sub.error != null) { _fail(gen, sub.error!, fix: ConnFix.refreshSub); return; }
          onNodes(sub.nodes);
          nodes = TunnelEngine.usableNodes(sub.nodes);
          if (nodes.isEmpty) {
            // Узлы пришли, но наш движок их не понимает → Happ понимает: это не тупик, а обход.
            // Если же записи были, но ВСЕ отброшены гейтом/капом (skipped > 0), говорим честно:
            // иначе человек видел бы «нет серверов» при живой, но отрезанной выдаче.
            _fail(gen,
                sub.nodes.isNotEmpty
                    ? tr('Узлы подписки не поддерживаются этой сборкой')
                    : sub.skipped > 0
                        ? tr('Узлы подписки отклонены: чужие адреса')
                        : tr('В подписке нет доступных серверов'),
                fix: sub.nodes.isNotEmpty ? ConnFix.happ : ConnFix.refreshSub);
            return;
          }
        } else {
          // Одиночный ключ (импортированный вручную) — заворачиваем в такой же узел подписки,
          // чтобы дальше был один путь подключения для обоих случаев.
          final one = subNodeFromKey(key);
          if (one == null) {
            _fail(gen, appLang == 'en' ? 'Key is corrupted' : 'Ключ повреждён', fix: ConnFix.refreshSub);
            return;
          }
          nodes = TunnelEngine.usableNodes([one]);
          if (nodes.isEmpty) { _fail(gen, tr('Этот ключ не поддерживается этой сборкой'), fix: ConnFix.happ); return; }
        }
        // Разрешение на VPN спрашиваем ДО таймаута: системный диалог показывает система, читает
        // его человек, и его время не имеет отношения к тому, «завис ли движок». Раньше эти
        // секунды входили в те же 40 — и неспешный пользователь получал «таймаут» одновременно
        // с поднявшимся туннелем: ключ в шторке горит, а приложение говорит «Отключено».
        if (!await TunnelEngine.instance.ensurePermission()) {
          if (_disposed || gen != _gen) return;
          _fail(gen, appLang == 'en'
              ? 'VPN permission is required to connect'
              : 'Нужно разрешить приложению создавать VPN-подключение', fix: ConnFix.none);
          return;
        }
        if (_disposed || gen != _gen) return; // отменили, пока человек читал диалог
        try {
          // таймаут: если движок завис и не вернул ни успех, ни ошибку — не залипаем
          // навсегда в «Подключение…», а честно откатываемся в «выключено» с тостом.
          // ручной выбор сервера уважаем: подключаемся ровно к нему, а не к «лучшему»
          final only = nodeTagOf();
          await TunnelEngine.instance
              .connect(nodes, onlyTag: only != null && nodes.any((n) => n.tag == only) ? only : null,
                       server: serverOf().city)
              .timeout(const Duration(seconds: 40));
        } on TunnelUnavailable catch (e) {
          // Нет разрешения на VPN-подключение: чинится повторной попыткой и «разрешить» в системе.
          _fail(gen, '$e', fix: ConnFix.none);
          return;
        } on EngineUnavailable catch (e) {
          // Проблема самого движка (нет бинаря, занят порт) — Happ поднимет тот же ключ мимо него.
          _fail(gen, '$e', fix: ConnFix.happ);
          return;
        } on TimeoutException {
          // Движок мог подняться уже ПОСЛЕ таймаута — тогда останется «осиротевший» туннель:
          // ключ в шторке горит, а интерфейс показывает «Отключено». Гасим дважды с паузой:
          // первый вызов ловит уже поднятый туннель, второй — тот, что встал следом.
          await TunnelEngine.instance.disconnect().catchError((_) {});
          Future<void>.delayed(const Duration(seconds: 3),
              () => TunnelEngine.instance.disconnect().catchError((_) {}));
          _fail(gen, appLang == 'en' ? 'Connection timed out' : 'Подключение не удалось — таймаут', fix: ConnFix.none);
          return;
        } catch (e) {
          _fail(gen, appLang == 'en' ? 'Failed to connect: $e' : 'Не удалось подключиться: $e');
          return;
        }
        if (_disposed || gen != _gen) { await TunnelEngine.instance.disconnect(); return; } // отменили во время старта
        // «Подключено» и «работает» — разные вещи. Движок поднимает туннель и рапортует об успехе,
        // а сессию сквозь фильтрацию может рвать: у человека горит ключ в шторке и не грузится
        // ничего. Именно так сейчас ведут себя ПРЯМЫЕ узлы при глушении интернета, тогда как узлы
        // через CDN работают. Поэтому сразу после старта тянем маленький ответ СКВОЗЬ туннель.
        final passes = await TunnelEngine.instance.verifyConnected();
        if (_disposed || gen != _gen) { await TunnelEngine.instance.disconnect(); return; }
        if (!passes) {
          // Узел не пропускает трафик — держать на нём человека нельзя, это и есть то самое
          // «подключено, но интернета нет». Гасим, помечаем узел и предлагаем взять рабочий.
          await TunnelEngine.instance.disconnect().catchError((_) {});
          onNodeDead(serverOf().id);
          _fail(gen,
              appLang == 'en'
                  ? 'This server is not passing traffic right now'
                  : 'Через этот сервер сейчас не идёт трафик',
              fix: ConnFix.pickOther);
          return;
        }
        gEngineReal = true;
        _startSession(down: 0, up: 0);
        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (_disposed) return;
          secs++; _accTraffic(); notifyListeners();
        });
        // РЕАЛЬНАЯ статистика/статус из движка — никаких выдуманных чисел
        _tunEvents = TunnelEngine.instance.events.listen((e) {
          if (_disposed || gen != _gen) return;
          if (e.state == 'error' || e.state == 'disconnected') { _dropped(gen, why: e.message); return; }
          down = e.downKbps;
          up = e.upKbps;
          notifyListeners();
        // ошибка самого канала (смерть процесса движка вместе с EventChannel) не приходит событием
        // state=='error' — ловим её отдельно, иначе UI навсегда завис бы в «Подключено».
        }, onError: (_) { _dropped(gen); });
        return;
      }

      // Движка на этой платформе нет. Раньше отсюда МОЛЧА стартовала демо-сессия: человек видел
      // бегущий таймер, скорости и «Демо-режим» — экран выглядел рабочим, а трафик шёл мимо
      // туннеля. Оплативший при этом не понимал, почему ничего не открылось. Говорим прямо и
      // даём рабочий обход (Happ умеет наш ключ); демо остаётся, но только по явной просьбе
      // из Настроек — «посмотреть интерфейс», а не «подключиться».
      if (!demoOn()) {
        _fail(gen, tr('На этой системе туннель ещё не поддержан'), fix: ConnFix.happ);
        return;
      }

      // ДЕМО-режим (тумблер в Настройках): туннель НЕ поднимается — показываем демо-сессию
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
      if (kRealTunnel) { await TunnelEngine.instance.disconnect(); gEngineReal = false; }
      _stopWatch();
      onSpin(false);
      conn = 0; secs = 0;
      notifyListeners();
    }
  }

  // старт сессии: обнуляем счётчики трафика/времени и поднимаем статус в «Подключено»
  void _startSession({required int down, required int up}) {
    conn = 2; secs = 0; this.down = down; this.up = up; sessions++;
    failMsg = null; failFix = ConnFix.none; // получилось — причина прошлой неудачи неактуальна
    blocked = false; // подключились — блокировки килл-свитча больше нет
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
    // В демо ускоряем накопление (kDemoTrafficBoost), чтобы порог «Лимит трафика» был достижим и
    // тумблер можно было показать; в боевом режиме множитель = 1 (реальные байты не искажаем).
    _sessMB += (down + up) / (8 * 1024.0) * (gEngineReal ? 1 : kDemoTrafficBoost);
    if (trafWarnOn() && !_trafWarned && _sessMB >= kTrafficWarnMB) {
      _trafWarned = true;
      onToast(appLang == 'en'
          ? 'Session usage passed ${(kTrafficWarnMB / 1024).toStringAsFixed(0)} GB'
          : 'Расход за сессию превысил ${(kTrafficWarnMB / 1024).toStringAsFixed(0)} ГБ');
    }
  }

  // боевой режим: не удалось подключиться — честно откатываемся в «выключено».
  // Причину показываем ДВАЖДЫ намеренно: тост ловит момент (подключение могли запустить хоткеем
  // или из трея с любой вкладки), карточка на Главной держит её вместе с кнопкой «что делать».
  void _fail(int gen, String msg, {ConnFix fix = ConnFix.support}) {
    if (_disposed || gen != _gen) return;
    _stopWatch();
    onSpin(false);
    conn = 0;
    failMsg = msg; failFix = fix;
    notifyListeners();
    onToast(msg);
  }

  // Держим ли при обрыве системный прокси (fail-closed). Только десктоп с xray удерживает
  // блокировку через неснятый прокси (порт мёртв → трафик умирает); на Android/iOS приложению
  // удерживать нечего (см. комментарий к TunnelEngine.failClosed) — объявлять там «трафик
  // заблокирован» было бы ложью. Вынесено в чистую функцию: правило покрыто killswitch_test.
  static bool holdProxyOnDrop(bool killSwitch, EngineKind kind) =>
      killSwitch && kind == EngineKind.desktopXray;

  // движок сообщил об обрыве соединения — снимаем «подключено»
  void _dropped(int gen, {String? why}) {
    if (_disposed || gen != _gen) return;
    // Килл-свитч ≠ отключение по кнопке. Кнопка/reset()/выход — осознанные действия человека,
    // там прокси снимается всегда и интернет снова прямой. Здесь же обрыв НЕОЖИДАННЫЙ: при
    // включённом тумблере системный прокси НЕ снимаем (fail-closed) — порт мёртв, и трафик
    // умирает, а не течёт мимо туннеля. При выключенном тумблере — прежнее поведение.
    final hold = kRealTunnel && holdProxyOnDrop(killSwitchOn(), TunnelEngine.kind());
    // синхронизируем натив с UI: явно гасим движок, чтобы после обрыва он не остался в
    // полу-поднятом/реконнектящем состоянии (как reset()/disconnect-ветка toggle()).
    if (kRealTunnel) {
      if (hold) { TunnelEngine.instance.failClosed(); } else { TunnelEngine.instance.disconnect(); }
      gEngineReal = false;
    }
    _stopWatch();
    onSpin(false);
    conn = 0; secs = 0;
    blocked = hold;
    // Причину обрыва держим на экране так же, как причину неудачного старта: человек мог
    // отойти от компьютера и вернуться уже после того, как тост погас. При блокировке обычную
    // карточку причины заменяет карточка килл-свитча (см. home.dart) — fix ей не нужен.
    failMsg = (why != null && why.isNotEmpty) ? why : tr('Соединение разорвано');
    failFix = hold ? ConnFix.none : ConnFix.support;
    notifyListeners();
    // При блокировке тостим сам факт fail-closed (это важнее причины: интернет «пропал»
    // намеренно). Иначе — как раньше: причину от движка показываем ВСЕГДА, независимо от
    // тумблера «Обрыв соединения»: тумблер про фоновые уведомления, а это ответ на действие
    // пользователя — без него отказ выглядит как «нажал подключить, ничего не произошло».
    if (hold) {
      onToast(tr('VPN отвалился — трафик заблокирован'));
    } else if (why != null && why.isNotEmpty) {
      onToast(tr(why));
    } else if (dropAlertOn()) {
      onToast(tr('Соединение разорвано'));
    }
  }

  /// «Снять блокировку» — единственный выход из fail-closed без нового подключения:
  /// снимает системный прокси (интернет снова прямой) и возвращает обычное «Отключено».
  Future<void> unblock() async {
    if (!blocked) return;
    blocked = false; // UI сразу возвращаем в «Отключено», прокси догоняет асинхронно
    notifyListeners();
    // disconnect идемпотентен: движок уже мёртв, здесь важно именно снятие прокси.
    await TunnelEngine.instance.disconnect();
  }

  // полный сброс подключения (напр. при выходе из аккаунта): гасит поколение, таймеры, статус
  void reset() {
    _gen++;
    // боевой режим: гасим и НАСТОЯЩИЙ туннель — иначе после logout трафик продолжал бы идти через
    // движок (reset раньше только обнулял UI). fire-and-forget, как ветка disconnect в toggle().
    // Демо-режим (kRealTunnel=false) туннель не поднимает — там гасить нечего, поведение не меняем.
    if (kRealTunnel) { TunnelEngine.instance.disconnect(); gEngineReal = false; }
    _stopWatch();
    onSpin(false);
    conn = 0; secs = 0;
    // сброс — осознанное действие (logout/закрытие окна), а не обрыв: блокировки килл-свитча
    // здесь быть не должно, прокси уже снял disconnect выше.
    blocked = false;
    failMsg = null; failFix = ConnFix.none; // причина прошлого аккаунта новому не показывается
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopWatch();
    super.dispose();
  }
}
