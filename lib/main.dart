import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, File, Directory, Process, Socket;
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'singbox_config.dart';
import 'xray_config.dart';
import 'engine.dart';
import 'desktop_engine.dart';
import 'native_tunnel.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:app_links/app_links.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

// Приложение разбито на модули; все они — части одной библиотеки (part/part of),
// чтобы приватные имена (_secRead, _load, _conn и т.п.) и extension'ы на ShellState
// оставались доступны между файлами.
part 'i18n.dart';        // локализация RU/EN
part 'theme.dart';       // тема/токены/шрифты
part 'models.dart';      // модели, константы/эндпоинты, токены+secure storage
part 'connection.dart';  // ConnectionController — жизненный цикл VPN-туннеля (вынесен из god-object)
part 'native.dart';      // deep-link (bitaps://), автозапуск при входе, глобальный хоткей — десктоп
part 'widgets.dart';     // painters + общие виджеты-строители
part 'api.dart';         // сетевые вызовы к edge-функциям + сетевые инструменты
part 'screens/home.dart';
part 'screens/servers.dart';
part 'screens/account.dart';
part 'screens/settings.dart';
part 'screens/lock.dart';
part 'screens/onboarding.dart';
part 'screens/paywall.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Автозапуск при входе может передать флаг «старт свёрнутым» (launch_at_startup args / OS).
  // Тогда окно не показываем — приложение живёт в трее до клика по иконке.
  final bootMinimized = args.contains('--minimized') || args.contains('--hidden');
  // Тему применяем СИНХРОННО до первого кадра и до WindowOptions: иначе backgroundColor окна
  // читает дефолтную тёмную C.bg, и у пользователей светлой темы мелькает тёмный фон на старте.
  await _applyStoredThemeEarly();
  // window_manager — только десктоп (на Android/iOS его нет → иначе краш на старте)
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    // Прошлый запуск мог завершиться падением/убийством процесса с включённым системным
    // прокси — тогда у пользователя «нет интернета» до ручной правки настроек. Прибираем за
    // собой на старте (снимаем только прокси, указывающий на localhost, — чужой не трогаем).
    unawaited(SystemProxy.cleanupStale());
    await windowManager.ensureInitialized();
    // hotkey_manager требует сброса «залипших» с прошлого запуска хоткеев на старте (десктоп).
    // fail-soft: на платформе без нативной стороны бросит — глотаем, живём без хоткея.
    try { await hotKeyManager.unregisterAll(); } catch (_) {}
    // Десктоп больше не «растянутый телефон» 440px: окно по умолчанию широкое (виден боковой
    // рейл навигации, см. LayoutBuilder в _buildBody), максимума нет — ресайз свободный.
    // Узкое окно (<720) продолжает работать мобильной раскладкой с нижним таб-баром.
    // Отладочный размер окна: BITAPS_WIN=ШИРИНАxВЫСОТА. Нужен, чтобы проверять МОБИЛЬНУЮ
    // раскладку (<720) на десктопе — иначе телефонные экраны нечем посмотреть без устройства.
    // В release ветка мертва (kDebugMode == false) и выкидывается компилятором.
    Size winSize = const Size(1024, 800);
    if (kDebugMode) {
      final m = RegExp(r'^(\d{3,4})x(\d{3,4})$').firstMatch(Platform.environment['BITAPS_WIN'] ?? '');
      if (m != null) winSize = Size(double.parse(m.group(1)!), double.parse(m.group(2)!));
    }
    final opts = WindowOptions(
      size: winSize,
      minimumSize: const Size(360, 640),
      center: true,
      backgroundColor: C.bg, // уже согласован с сохранённой темой (см. _applyStoredThemeEarly)
      title: 'bitaps VPN',
    );
    windowManager.waitUntilReadyToShow(opts, () async {
      if (bootMinimized) {
        // старт свёрнутым: окно не показываем (только трей); skipTaskbar чтобы не мигало в доке/панели
        try { await windowManager.setSkipTaskbar(true); } catch (_) {}
        await windowManager.hide();
      } else {
        await windowManager.show();
        await windowManager.focus();
      }
    });
  }
  runApp(const BitApp());
  _maybeStartShotLoop();
}

// ── Самопроверка визуала (ТОЛЬКО debug) ──
// screencapture/CGWindowListCreateImage требуют TCC-разрешение «запись экрана», которого у
// автоматизации нет → в debug-сборке с env BITAPS_SHOT=<папка> приложение раз в 2 секунды
// сохраняет PNG собственного кадра (RepaintBoundary поверх MaterialApp). В release kDebugMode
// == false → вся ветка мертва и выкидывается компилятором; на поведение приложения не влияет.
final GlobalKey _shotKey = GlobalKey();

void _maybeStartShotLoop() {
  if (!kDebugMode) return;
  final dir = Platform.environment['BITAPS_SHOT'];
  if (dir == null || dir.isEmpty) return;
  Timer.periodic(const Duration(seconds: 2), (_) async {
    try {
      final ro = _shotKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (ro == null) return;
      final img = await ro.toImage(pixelRatio: 2);
      final bytes = await img.toByteData(format: ImageByteFormat.png);
      if (bytes != null) File('$dir/shot.png').writeAsBytesSync(bytes.buffer.asUint8List());
    } catch (e) {
      debugPrint('shot loop: $e');
    }
  });
}

// Прочитать сохранённые тему И акцент и применить их ДО runApp/окна.
// Дешёвое чтение SharedPreferences; при любой ошибке молча остаёмся на дефолте, старт не блокируем.
Future<void> _applyStoredThemeEarly() async {
  try {
    final p = await SharedPreferences.getInstance();
    final tm = (p.getInt('themeMode') ?? 0).clamp(0, 2);
    // Акцент тоже применяем ДО первого кадра (зеркалит _load): иначе у сменившего акцент
    // юзера первые кадры рисуются дефолтным Sunset-оранжевым и скачком перекрашиваются.
    final ai = (p.getInt('accent') ?? 0).clamp(0, accentThemes.length - 1);
    final th = accentThemes[ai];
    C.accent = th.$2;
    C.accentSoft = th.$3;
    // Секретный «Фосфор» форсит люминофорную палитру ДО первого кадра (иначе мелькает обычный фон).
    if (ai == kPhosphorAccent) {
      C.applyTheme(false, phosphorOn: true);
      return;
    }
    final light = tm == 1 ||
        (tm == 2 &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.light);
    C.applyTheme(light);
  } catch (_) {
    // не удалось прочитать настройку — оставляем дефолтную тему, окно всё равно откроется
  }
}

// ============================ APP ============================
class BitApp extends StatelessWidget {
  const BitApp({super.key});
  @override
  Widget build(BuildContext context) {
    // Тема реактивна: слушаем глобальный флаг яркости (обновляется из C.applyTheme при смене
    // темы/системной яркости) и перестраиваем ThemeData целиком. `home: const Shell()` сохраняет
    // ShellState между пересборками MaterialApp (тот же тип виджета → State не пересоздаётся).
    return ValueListenableBuilder<bool>(
      valueListenable: themeLight,
      // RepaintBoundary(_shotKey) — для debug-самоскриншотов (см. _maybeStartShotLoop);
      // в release просто лишний no-op слой поверх корня.
      builder: (_, light, __) => RepaintBoundary(key: _shotKey, child: MaterialApp(
        title: 'bitaps VPN',
        debugShowCheckedModeBanner: false,
        theme: _appTheme(light),
        home: const Shell(),
      )),
    );
  }

  ThemeData _appTheme(bool light) => ThemeData(
        brightness: light ? Brightness.light : Brightness.dark,
        scaffoldBackgroundColor: C.bg,
        colorScheme: light
            ? ColorScheme.light(primary: C.accent, surface: C.bg2)
            : ColorScheme.dark(primary: C.accent, surface: C.bg2),
        useMaterial3: true,
        fontFamily: 'SpaceGrotesk',
      );
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => ShellState();
}

class ShellState extends State<Shell> with TickerProviderStateMixin, WidgetsBindingObserver, TrayListener {
  int tab = 0;
  int mode = 0;
  Server server = kNoServer;
  /// Почему список серверов пуст: текст от сервиса выдачи («Лимит устройств исчерпан»,
  /// «Подписка истекла»). Без него экран молча показывал бы пустоту, и человек не понимал бы,
  /// что делать.
  String? subNotice;
  /// Узлы из подписки — источник правды для списка серверов и для подключения.
  List<SubNode> subNodes = const [];
  bool tgl1 = false, tgl2 = true, tgl3 = true, tgl4 = false;
  String? appPin; // PIN блокировки приложения
  bool _locked = false;
  final TextEditingController _pinCtrl = TextEditingController();
  int _pinFails = 0;       // подряд неверных попыток PIN (сбрасывается при успехе)
  int _pinLockSecs = 0;    // >0 → ввод PIN временно заблокирован на это число секунд
  Timer? _pinLockTimer;    // тикает обратный отсчёт блокировки
  int accentIdx = 0, btnStyle = 0;
  int themeMode = 0; // 0 тёмная · 1 светлая · 2 системная
  bool autoConnect = false;
  // Режим «лучший сервер»: при подключении сами берём оптимальный сервер (ползунок на Главной).
  // Выбор конкретного сервера в списке выключает режим (см. _pickServer).
  bool bestServer = true;
  // Живые замеры отклика (кнопка «Пинг» на Серверах): id сервера → мс. Пока замера не было —
  // показываем статичный s.ping из models.dart. Не персистим: замер живёт в рамках сессии.
  final Map<String, int> pingMeasured = {};
  bool _pinging = false; // идёт замер пинга — гвард от двойного запуска
  String keyStr = kDemoKey;
  String? customCfg;
  String? importedHost;
  // Идентификатор устройства для подписки (заголовок x-hwid). Создаётся один раз при первом
  // запуске и живёт в prefs: по нему сервис считает устройства в лимите тарифа.
  String hwid = '';
  final TextEditingController _support = TextEditingController();
  final Set<String> favs = {};
  // вход / подписка / устройства (реальные данные из Supabase)
  int? tgId;
  String? appToken, subPlan, subExpires, subName;
  String? loginSecret; // код входа (отдельный от vpn_key credential) — для входа в приложение/кабинет
  int? subLimit;
  bool subActive = false;
  bool _subLoading = false; // re-entrancy-гвард _refreshSub (в т.ч. тихий фоновый рефреш)
  bool _subVisibleLoading = false; // спиннеры/дизейбл в UI — ТОЛЬКО для явного (не silent) рефреша
  bool _pairing = false; // идёт авто-вход через бота — гвард от двойного тапа (два диалога подряд)
  bool _toolBusy = false; // идёт сетевой инструмент (спид-тест/утечки) — гвард от двойного запуска
  bool _supportSending = false; // идёт отправка в поддержку — гвард от двойной отправки
  bool _loggingIn = false; // идёт вход по ключу — гвард от двойного входа
  bool _rotating = false; // идёт ротация «Кода входа» — гвард от двойного тапа (два POST)
  List<Map<String, dynamic>> devices = [];
  final TextEditingController _loginCtrl = TextEditingController();
  bool get loggedIn => tgId != null && appToken != null;

  // Подключение вынесено в ConnectionController (см. connection.dart) — состояние и логика туннеля
  // больше не живут в ShellState. Ниже тонкие прокси, чтобы экраны читали conn/hms/скорость как раньше.
  late final ConnectionController _conn;
  int get conn => _conn.conn;
  String get hms => _conn.hms;
  int get down => _conn.down;
  int get up => _conn.up;
  int get sessions => _conn.sessions;
  void toggle() {
    // Режим «лучший сервер»: перед стартом коннекта сами берём оптимальный для текущего режима
    // сервер (для «Авто»/«Игры» это минимальный пинг — с учётом живых замеров pingOf). Только при
    // conn==0: конфиг уже идущего подключения не трогаем.
    if (bestServer && _conn.conn == 0) setState(() => server = serverForMode(mode));
    _conn.toggle();
  }

  // Анимации НЕ гоняем безусловно (..repeat()) — это жгло батарею: starfield + шестерёнка + кольца
  // перерисовывались каждый кадр на всех вкладках и даже в фоне. Теперь _syncAnimations() держит
  // каждый контроллер запущенным ТОЛЬКО когда он реально виден (нужная вкладка + приложение активно).
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 6));
  late final AnimationController _wave =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  late final AnimationController _twinkle =
      AnimationController(vsync: this, duration: const Duration(seconds: 4));
  bool _foreground = true; // окно ВИДИМО (не свёрнуто); расфокус (inactive) — тоже видимо, см. lifecycle

  // Запускать/останавливать анимации по факту видимости — экономит CPU/GPU/батарею.
  // Вызывается пост-фрейм из build() (ловит смену вкладки/темы/стиля/подключения) и из lifecycle.
  void _syncAnimations() {
    // не гоняем, если свёрнуто, заблокировано или поверх экрана онбординг (анимации не видны)
    final vis = _foreground && !_locked && !_showOnboarding;
    final onHome = tab == 0;
    _drive(_twinkle, vis && onHome && !C.light);         // звёзды: только Главная, тёмная тема
    _drive(_spin, vis && onHome && btnStyle == 0);        // шестерёнка: только Главная, стиль по умолчанию
    _drive(_wave, vis && onHome && (conn == 2 || btnStyle == 3)); // кольца: когда реально показаны
  }

  void _drive(AnimationController c, bool on) {
    if (on && !c.isAnimating) {
      c.repeat();
    } else if (!on && c.isAnimating) {
      c.stop();
    }
  }

  // Публичная обёртка над setState для extension-файлов (api/screens/widgets): они не наследники
  // State, поэтому прямой setState даёт analyzer-warning invalid_use_of_protected_member. Обёртка
  // закрывает это без большого рефактора god-object. mounted — публичный геттер, его звать можно.
  void rebuild([VoidCallback? fn]) { if (mounted) setState(fn ?? () {}); }

  bool _updateAvail = false; // доступна новая сборка (build_number из релиза > вшитого)

  // ----- онбординг (первый запуск / «Показать знакомство» в Настройках) -----
  bool _showOnboarding = false; // поверх всего UI (после PIN-замка)
  int _onbPage = 0;
  final PageController _onbCtrl = PageController();

  // ----- статистика аккаунта из app-sub (fail-soft: null → в карточке прочерк) -----
  String? statMemberSince; // ISO-дата первого события аккаунта
  int? statPaidDays, statRefs, statTokens;
  int subStreak = 0, subNextBonus = 0; // стрик продлений + бонус за СЛЕДУЮЩЕЕ раннее продление
  bool subVip = false;

  // ----- tray (десктоп): иконка в меню-баре/трее, показать/скрыть окно -----
  bool _trayReady = false;
  int _lastTrayConn = -1; // фаза conn, под которую последний раз пересобрано трей-меню (анти-спам)

  // ----- автозапуск (десктоп): «запускать при входе» + «старт свёрнутым» -----
  bool autoLaunch = false;   // приложение стартует при входе в систему
  bool startMinimized = false; // при автозапуске окно не показываем (только трей)

  // ----- глобальный хоткей подключения (десктоп) -----
  String hotkeyStr = kDefaultHotkey; // сериализованный хоткей (persist prefs)
  bool _recordingHotkey = false;     // рекордер в Настройках ждёт нажатия
  HotKey? _registeredHotkey;         // текущий зарегистрированный (для unregister при смене)

  // ----- секретная тема «Фосфор» -----
  bool phosphorUnlocked = false; // свотч Phosphor виден в Настройках
  int _logoTaps = 0;             // счётчик тапов по мини-лого шапки (пасхалка)
  DateTime? _lastLogoTap;        // сброс серии, если между тапами >1.2с

  // ----- deep-link (bitaps://): приём кастомной схемы -----
  // Подписку держим в поле — она удерживает AppLinks живым и отменяется в dispose.
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _conn = ConnectionController(
      keyOf: () => keyStr,
      hwidOf: () => hwid,
      serverOf: () => server,
      onNodes: _applyNodes,
      // Даже в режиме «лучший сервер» отдаём движку КОНКРЕТНЫЙ узел — тот же, что показан на
      // экране. Раньше в авто-режиме сюда шёл null, и на Android движок выбирал узел сам, своим
      // правилом: интерфейс писал «Румыния», а туннель уходил в Финляндию. Выбор делает интерфейс
      // (serverForMode), движок его исполняет. null остаётся только если выбирать пока не из чего.
      nodeTagOf: () => server.id.isEmpty ? null : server.id,
      dropAlertOn: () => tgl2,
      trafWarnOn: () => tgl4,
      onToast: _toast,
      onPersist: _save,
      onSpin: _spinConn,
    );
    // conn мог смениться (подключение/обрыв/таймер) → пересобираем И сверяем анимации здесь,
    // а не пост-фреймом на каждый build (см. _syncAnimations вызовы у мутаторов tab/тема/стиль).
    // !_locked: при замке build() отдаёт _lockScreen(), который conn/hms/скорость не читает —
    // посекундный тик таймера сессии не должен впустую перестраивать экран блокировки.
    _conn.addListener(() {
      if (mounted && !_locked) {
        setState(() {});
        _syncAnimations();
        // трей-меню пересобираем ТОЛЬКО при смене фазы conn (0/1/2), а не на каждый тик таймера сессии
        if (_conn.conn != _lastTrayConn) { _lastTrayConn = _conn.conn; _refreshTray(); }
      }
    });
    _load();
    _checkUpdate();
    // Tray — только десктоп; вся инициализация fail-soft (без нативной стороны/библиотеки
    // приложение просто живёт без трея, не падая).
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) _initTray();
    // deep-link (bitaps://) — все платформы; автозапуск+хоткей — только десктоп. Всё fail-soft.
    _initDeepLinks();
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) _initNativeDesktop();
    // Одноразовый пост-фрейм: первичная сверка анимаций после первого кадра (дальше — событийно).
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _syncAnimations(); });
  }

  // ---------------- TRAY (десктоп) ----------------
  Future<void> _initTray() async {
    try {
      // ассет-пути (tray_manager сам резолвит их в data/flutter_assets); Windows требует .ico
      await trayManager.setIcon(
        Platform.isWindows ? 'assets/tray.ico' : 'assets/tray.png',
        // macOS: template-иконка перекрашивается системой под светлый/тёмный меню-бар
        isTemplate: Platform.isMacOS,
      );
      await _updateTrayMenu();
      // setToolTip не реализован на Linux (метод бросает) — зовём только там, где поддержан
      if (!Platform.isLinux) await trayManager.setToolTip('bitaps VPN');
      trayManager.addListener(this);
      _trayReady = true;
    } catch (e) {
      debugPrint('tray init failed: $e'); // нет libayatana/нативной стороны → живём без трея
    }
  }

  // Меню трея = мини-пульт: статус (демо-гейт как везде), подключить/отключить, дни подписки,
  // режимы, окно, выход. Пересобираем при смене языка (_langChip) И при смене состояния —
  // подключения/подписки/режима (см. _refreshTray, зовём из слушателя _conn и _applySub/_save).
  Future<void> _updateTrayMenu() async {
    try {
      // строка статуса — тот же honesty-гейт, что и на Главной: в демо не пишем «Подключено»
      final statusLabel = conn == 0
          ? tr('Отключено')
          : conn == 1
              ? tr('Подключение…')
              : (gEngineReal ? tr('Подключено') : tr('Демо-режим'));
      // дни подписки в меню (если вошёл и знаем срок)
      final days = _trayDaysLeft();
      final subLabel = !loggedIn
          ? tr('Не вошёл')
          : (days != null
              ? (appLang == 'en' ? '$days days left' : 'осталось $days ${_trayPluralDays(days)}')
              : (subActive ? tr('Подписка активна') : tr('Подписка неактивна')));
      final connected = conn == 2;
      await trayManager.setContextMenu(Menu(items: [
        MenuItem(key: 'status', label: '● $statusLabel', disabled: true),
        MenuItem(key: 'sub', label: '  $subLabel', disabled: true),
        MenuItem.separator(),
        // одна строка-тумблер: подключить при отключённом, отключить при активном
        MenuItem(key: 'toggle', label: connected ? tr('Отключить') : tr('Подключить')),
        // подменю выбора режима (Авто/Стрим/Игры/Прив.)
        MenuItem.submenu(
          key: 'mode',
          label: tr('Режим'),
          submenu: Menu(items: [
            for (int i = 0; i < modeLabels.length; i++)
              MenuItem.checkbox(key: 'mode_$i', label: tr(modeLabels[i]), checked: mode == i),
          ]),
        ),
        MenuItem.separator(),
        MenuItem(key: 'show', label: tr('Открыть bitaps')),
        MenuItem(key: 'quit', label: tr('Выйти из bitaps')),
      ]));
    } catch (e) {
      debugPrint('tray menu failed: $e');
    }
  }

  // Пересобрать меню трея под текущее состояние (fail-soft; только если трей готов).
  void _refreshTray() { if (_trayReady) _updateTrayMenu(); }

  // дни до конца подписки для меню трея (дублирует логику account._daysLeft, но без extension-зависимости)
  int? _trayDaysLeft() {
    if (subExpires == null) return null;
    final e = DateTime.tryParse(subExpires!);
    if (e == null) return null;
    final d = (e.toUtc().difference(DateTime.now().toUtc()).inMinutes / 1440).ceil();
    return d < 0 ? 0 : d;
  }

  String _trayPluralDays(int n) {
    final n10 = n % 10, n100 = n % 100;
    if (n10 == 1 && n100 != 11) return 'день';
    if (n10 >= 2 && n10 <= 4 && (n100 < 12 || n100 > 14)) return 'дня';
    return 'дней';
  }

  @override
  void onTrayIconMouseDown() {
    // macOS-конвенция: клик по иконке меню-бара открывает меню; Win/Linux — тумблер окна
    if (Platform.isMacOS) {
      trayManager.popUpContextMenu();
    } else {
      _toggleWindowVisible();
    }
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    final key = menuItem.key;
    switch (key) {
      case 'show':
        // старт-свёрнутым мог поставить skipTaskbar — снимаем при явном открытии
        try { await windowManager.setSkipTaskbar(false); } catch (_) {}
        await windowManager.show();
        await windowManager.focus();
        break;
      case 'hide':
        await windowManager.hide();
        break;
      case 'toggle':
        // тот же ConnectionController.toggle, что у большой кнопки и хоткея
        toggle();
        _refreshTray();
        break;
      case 'quit':
        // сначала убираем иконку из трея, затем закрываем окно/процесс
        try { await trayManager.destroy(); } catch (_) {}
        await windowManager.destroy();
        break;
      default:
        // выбор режима из подменю (mode_0..mode_3): только при отключённом туннеле (как _modeChip)
        if (key != null && key.startsWith('mode_')) {
          final i = int.tryParse(key.substring(5));
          if (i == null || i < 0 || i >= modeLabels.length) return;
          if (conn != 0) { _toast(tr('Отключись, чтобы сменить режим')); return; }
          setState(() { mode = i; bestServer = true; server = serverForMode(i); });
          _save();
          _refreshTray();
        }
    }
  }

  Future<void> _toggleWindowVisible() async {
    try {
      if (await windowManager.isVisible()) {
        await windowManager.hide();
      } else {
        await windowManager.show();
        await windowManager.focus();
      }
    } catch (e) {
      debugPrint('tray toggle window failed: $e');
    }
  }

  // крутить кнопку-шестерёнку: быстро во время коннекта, спокойно в покое/при обрыве.
  // Меняем скорость и перезапускаем ТОЛЬКО если шестерёнка сейчас видна — иначе просто
  // запоминаем длительность (её подхватит _syncAnimations, когда вернёмся на Главную).
  void _spinConn(bool fast) {
    _spin.duration = Duration(milliseconds: fast ? 1400 : 6000);
    _spin.stop();
    if (_foreground && !_locked && tab == 0 && btnStyle == 0) _spin.repeat();
  }

  // Android доставляет deep-link ДВАЖДЫ: плагину app_links (там мы его и разбираем — см.
  // _handleDeepLink) и отдельно в навигацию Flutter, как будто это имя маршрута. Именованных
  // маршрутов у нас нет, поэтому второй путь падал: «Null check operator used on a null value»
  // внутри _onUnknownRoute. Внешне это выглядело так, что по ссылке из автонастройки приложение
  // открывается, но ключ не подставляется — на уже запущенном приложении импорт просто не доходил.
  // На УЖЕ ЗАПУЩЕННОМ приложении ссылка приходит ТОЛЬКО сюда — поток app_links её не отдаёт
  // (проверено на устройстве: вкладка не переключалась, импорт не происходил). Поэтому здесь не
  // просто гасим навигацию, а разбираем ссылку сами тем же обработчиком.
  // Возвращаем true всегда = «обработали»: именованных маршрутов у приложения нет, и любая
  // попытка Flutter перейти по «маршруту» заканчивалась падением.
  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) async {
    final uri = routeInformation.uri;
    if (uri.scheme.toLowerCase() == kUrlScheme) _handleDeepLink(uri);
    return true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // авто-замок при сворачивании. paused (мобильный) + hidden (десктоп свёрнут). НЕ inactive —
    // он срабатывает на ЛЮБУЮ потерю фокуса (в т.ч. открытие внешней ссылки) и ложно блокировал бы.
    final bg = state == AppLifecycleState.paused || state == AppLifecycleState.hidden;
    // inactive = потеря фокуса при ВИДИМОМ окне (клик в браузер/Telegram, в т.ч. наша же ссылка
    // пейринга) — анимации не гасим, иначе шестерёнка/кольца замирают на полукадре и окно
    // выглядит зависшим. Фон для анимаций — только paused/hidden/detached (свёрнуто/скрыто).
    _foreground = state == AppLifecycleState.resumed || state == AppLifecycleState.inactive;
    _syncAnimations(); // свернули → гасим анимации; вернулись → поднимаем нужные
    if (bg && tgl1 && (appPin?.isNotEmpty ?? false) && !_locked) {
      setState(() => _locked = true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_trayReady) trayManager.removeListener(this);
    _linkSub?.cancel();
    _disposeHotkey();
    _onbCtrl.dispose();
    _pinLockTimer?.cancel();
    _conn.dispose();
    _spin.dispose();
    _wave.dispose();
    _twinkle.dispose();
    _support.dispose();
    _loginCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  // ----- persistence: настройки реально сохраняются между запусками -----
  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    // секреты читаем из secure storage ДО setState (там нельзя await); с миграцией/фолбэком внутри
    final secPin = await _secRead(p, 'appPin');
    final secKey = await _secRead(p, 'key');
    final secToken = await _secRead(p, 'appToken');
    final secLogin = await _secRead(p, 'loginSecret');
    final secCfg = await _secRead(p, 'cfg'); // «Свой конфиг» может нести vless-ключ → тоже в secure storage
    // троттлинг PIN переживает рестарт: счётчик ошибок + время окончания локаута (epoch ms)
    final secPinFails = await _secRead(p, 'pinFails');
    final secPinLockUntil = await _secRead(p, 'pinLockUntil');
    // hwid для подписки: создаём при первом запуске и сразу пишем в prefs — не в _save, иначе
    // до первого сохранения настроек каждый запуск занимал бы новый слот устройства.
    var hw = p.getString('hwid') ?? '';
    if (hw.length < 10) {
      hw = genHwid();
      await p.setString('hwid', hw);
    }
    if (!mounted) return;
    // язык: сохранённый выбор, иначе автоопределение по системной локали (ru → ru, иначе en)
    final savedLang = p.getString('lang');
    appLang = savedLang ??
        (WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'ru' ? 'ru' : 'en');
    setState(() {
      phosphorUnlocked = p.getBool('phosphorUnlocked') ?? false;
      // Секретную «Фосфор» можно восстановить, ТОЛЬКО если она уже разблокирована — иначе
      // потерянный флаг оставил бы выбранным недоступный акцент. Клампим к обычным палитрам.
      final maxAccent = phosphorUnlocked ? accentThemes.length - 1 : kPhosphorAccent - 1;
      accentIdx = (p.getInt('accent') ?? 0).clamp(0, maxAccent);
      autoLaunch = p.getBool('autoLaunch') ?? false;
      startMinimized = p.getBool('startMinimized') ?? false;
      hotkeyStr = p.getString('hotkey') ?? kDefaultHotkey;
      btnStyle = (p.getInt('btnStyle') ?? 0).clamp(0, btnStyleNames.length - 1);
      mode = (p.getInt('mode') ?? 0).clamp(0, modeLabels.length - 1);
      themeMode = (p.getInt('themeMode') ?? 0).clamp(0, 2);
      autoConnect = p.getBool('autoConnect') ?? false;
      bestServer = p.getBool('bestServer') ?? true;
      tgl1 = p.getBool('tgl1') ?? false;
      appPin = secPin;
      _pinFails = int.tryParse(secPinFails ?? '') ?? 0; // восстанавливаем счётчик ошибок PIN
      tgl2 = p.getBool('tgl2') ?? true;
      tgl3 = p.getBool('tgl3') ?? true;
      tgl4 = p.getBool('tgl4') ?? false;
      _conn.sessions = p.getInt('sessions') ?? 0;
      customCfg = secCfg;
      keyStr = secKey ?? kDemoKey;
      hwid = hw;
      importedHost = p.getString('host');
      tgId = p.getInt('tgId');
      appToken = secToken;
      loginSecret = secLogin;
      subPlan = p.getString('subPlan');
      subExpires = p.getString('subExpires');
      subName = p.getString('subName');
      subLimit = p.getInt('subLimit');
      subActive = p.getBool('subActive') ?? false;
      // статистика аккаунта: кэш прошлой сессии, чтобы карточка не мигала прочерками до рефреша
      statMemberSince = p.getString('stMember');
      statPaidDays = p.getInt('stDays');
      statRefs = p.getInt('stRefs');
      statTokens = p.getInt('stTokens');
      subStreak = p.getInt('stStreak') ?? 0;
      subNextBonus = p.getInt('stNextBonus') ?? 0;
      subVip = p.getBool('stVip') ?? false;
      // онбординг: показываем при первом запуске; уже залогиненных (обновившихся) не трогаем —
      // им знакомство доступно из Настроек («Показать знакомство»)
      _showOnboarding = !(p.getBool('seen_onboarding') ?? false) && !loggedIn;
      try {
        final dl = jsonDecode(p.getString('devices') ?? '[]');
        devices = (dl is List) ? dl.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : [];
      } catch (e) {
        debugPrint('cached devices decode error: $e');
        devices = [];
      }
      favs
        ..clear()
        ..addAll(p.getStringList('favs') ?? const []);
      final th = accentThemes[accentIdx];
      C.accent = th.$2;
      C.accentSoft = th.$3;
      _applyThemeMode();
      tab = loggedIn ? 0 : 2; // не вошёл → сразу экран входа (Кабинет), а не демо-главная
      _locked = tgl1 && (appPin?.isNotEmpty ?? false);
      server = serverForMode(mode); // сервер согласован с сохранённым режимом (без рассинхрона)
      // Ползунок «лучший сервер» выключен → восстанавливаем РУЧНОЙ выбор пользователя (serverId),
      // иначе после рестарта плашка говорила бы «сервер выбираешь ты», а стоял бы автоподобранный.
      // Фолбэк на serverForMode выше, если сохранённый сервер исчез/стал недоступен.
      if (!bestServer) {
        final saved = p.getString('serverId');
        final match = fleet.where((s) => s.id == saved && s.available);
        if (match.isNotEmpty) server = match.first;
      }
    });
    _syncAnimations(); // применили тему/вкладку/стиль из хранилища → сверяем анимации разом
    // если на прошлой сессии перебор PIN оставил активный локаут — доигрываем оставшийся отсчёт,
    // чтобы блокировка ввода пережила рестарт (иначе перезапуск сбрасывал троттлинг мгновенно).
    if (_locked) {
      final lockUntil = int.tryParse(secPinLockUntil ?? '') ?? 0;
      final remainMs = lockUntil - DateTime.now().millisecondsSinceEpoch;
      if (remainMs > 0) _startPinLock((remainMs / 1000).ceil().clamp(1, 60));
    }
    // Тест-сессия для визуальной самопроверки (ТОЛЬКО debug, зеркало BITAPS_SHOT): env
    // BITAPS_TEST_TG + BITAPS_TEST_TOKEN подставляют вход без ручного ввода — экраны кабинета
    // можно скринить автоматикой. В release kDebugMode==false → ветка мертва и выкидывается.
    if (kDebugMode) {
      final ttg = int.tryParse(Platform.environment['BITAPS_TEST_TG'] ?? '');
      final ttok = Platform.environment['BITAPS_TEST_TOKEN'];
      if (ttg != null && ttok != null && ttok.isNotEmpty) {
        setState(() { tgId = ttg; appToken = ttok; tab = 2; });
      }
    }
    if (loggedIn) _refreshSub(silent: true);
    _loadNodes(); // узлы подписки для экрана «Серверы» — до первого подключения
    // Авто-коннект НЕ должен подниматься сквозь блокировку или без логина: если экран заблокирован
    // (_locked) — стартуем после разблокировки (см. _tryUnlock), иначе пробуем сразу.
    if (!_locked) _maybeAutoConnect();
  }

  // Поднять авто-коннект, только если он включён, туннель выключен, экран разблокирован и есть логин.
  void _maybeAutoConnect() {
    if (!autoConnect || conn != 0 || _locked || !loggedIn) return;
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && autoConnect && conn == 0 && !_locked && loggedIn) toggle();
    });
  }

  // тема: 0 тёмная · 1 светлая · 2 системная (следует за настройкой ОС).
  // Секретный акцент «Фосфор» (accentIdx == kPhosphorAccent) форсит люминофорную тёмную палитру
  // независимо от режима яркости — она сама по себе законченная тема.
  void _applyThemeMode() {
    if (accentIdx == kPhosphorAccent) { C.applyTheme(false, phosphorOn: true); return; }
    final light = themeMode == 1 ||
        (themeMode == 2 &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.light);
    C.applyTheme(light);
  }

  @override
  void didChangePlatformBrightness() {
    // системная тема сменилась в ОС — подхватываем на лету, если выбран режим «Системная»
    if (themeMode == 2 && mounted) { setState(_applyThemeMode); _syncAnimations(); } // starfield только в тёмной
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('accent', accentIdx);
    await p.setBool('phosphorUnlocked', phosphorUnlocked);
    await p.setBool('autoLaunch', autoLaunch);
    await p.setBool('startMinimized', startMinimized);
    await p.setString('hotkey', hotkeyStr);
    await p.setInt('btnStyle', btnStyle);
    await p.setInt('mode', mode);
    await p.setInt('themeMode', themeMode);
    await p.setString('lang', appLang);
    await p.setBool('autoConnect', autoConnect);
    await p.setBool('bestServer', bestServer);
    await p.setString('serverId', server.id); // ручной выбор восстанавливаем в _load при bestServer=false
    await p.setBool('tgl1', tgl1);
    await _secWrite(p, 'appPin', appPin);
    await p.setBool('tgl2', tgl2);
    await p.setBool('tgl3', tgl3);
    await p.setBool('tgl4', tgl4);
    await p.setInt('sessions', sessions);
    await p.setStringList('favs', favs.toList());
    await _secWrite(p, 'cfg', customCfg); // secure storage (может нести vless-ключ), не plaintext
    await _secWrite(p, 'key', keyStr);
    if (tgId != null) { await p.setInt('tgId', tgId!); } else { await p.remove('tgId'); }
    await _secWrite(p, 'appToken', appToken);
    await _secWrite(p, 'loginSecret', loginSecret);
    // при null — УДАЛЯЕМ ключ (иначе после logout остаются данные прежней подписки в prefs)
    if (subPlan != null) { await p.setString('subPlan', subPlan!); } else { await p.remove('subPlan'); }
    if (subExpires != null) { await p.setString('subExpires', subExpires!); } else { await p.remove('subExpires'); }
    if (subName != null) { await p.setString('subName', subName!); } else { await p.remove('subName'); }
    if (subLimit != null) { await p.setInt('subLimit', subLimit!); } else { await p.remove('subLimit'); }
    await p.setBool('subActive', subActive);
    // статистика аккаунта (кэш для карточки «// статистика»; null — удаляем, как и поля подписки)
    if (statMemberSince != null) { await p.setString('stMember', statMemberSince!); } else { await p.remove('stMember'); }
    if (statPaidDays != null) { await p.setInt('stDays', statPaidDays!); } else { await p.remove('stDays'); }
    if (statRefs != null) { await p.setInt('stRefs', statRefs!); } else { await p.remove('stRefs'); }
    if (statTokens != null) { await p.setInt('stTokens', statTokens!); } else { await p.remove('stTokens'); }
    await p.setInt('stStreak', subStreak);
    await p.setInt('stNextBonus', subNextBonus);
    await p.setBool('stVip', subVip);
    await p.setString('devices', jsonEncode(devices));
    if (importedHost != null) {
      await p.setString('host', importedHost!);
    } else {
      await p.remove('host');
    }
  }

  // Пинг сервера: живой замер (кнопка «Пинг» на Серверах), пока его нет — статичный из models.dart.
  int pingOf(Server s) => pingMeasured[s.id] ?? s.ping;

  /// Доступные серверы — ТОЛЬКО узлы подписки. Запасного списка нет намеренно: пустой экран
  /// с объяснением честнее, чем выдуманные серверы, к которым нельзя подключиться.
  List<Server> get fleet =>
      [for (final n in subNodes) serverFromSubNode(n, ping: pingMeasured[n.tag] ?? 0)];

  /// Применить свежий список узлов: обновляем парк и следим, чтобы выбранный сервер
  /// существовал (иначе подключение ушло бы к исчезнувшему узлу).
  void _applyNodes(List<SubNode> ns) {
    if (!mounted || ns.isEmpty) return;
    rebuild(() {
      subNodes = ns;
      if (bestServer || !fleet.any((s) => s.id == server.id)) server = serverForMode(mode);
    });
  }

  // режим реально подбирает сервер: Стрим→мин.нагрузка, Игры/Авто→мин.пинг, Прив→зарубежный (иначе лучший)
  Server serverForMode(int m) {
    final avail = fleet.where((s) => s.available).toList();
    if (avail.isEmpty) return kNoServer;
    if (m == 1) { avail.sort((a, b) => a.load.compareTo(b.load)); return avail.first; }
    if (m == 3) {
      final intl = avail.where((s) => s.country != 'Россия').toList();
      if (intl.isNotEmpty) { intl.sort((a, b) => pingOf(a).compareTo(pingOf(b))); return intl.first; }
    }
    avail.sort((a, b) => pingOf(a).compareTo(pingOf(b)));
    return avail.first;
  }

  // ----- реальные действия -----
  void _toast(String m) {
    if (!mounted) return; // из catch/таймаут-веток может прийти после размонтирования — не падаем
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Row(children: [
          Container(width: 4, height: 30, decoration: BoxDecoration(color: C.accent, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 12),
          // Цвет текста — из текущей темы (C.text): иначе в светлой теме тёмный текст ложился на
          // захардкоженный тёмный фон и был нечитаем.
          // tr() прямо здесь: в тосты приходят и сообщения из движка/сети, которые бросаются
          // исключениями и потому не проходят через tr() на месте. Без перевода они оставались
          // русскими даже в английском интерфейсе. tr() возвращает исходную строку, если её нет
          // в словаре, — для остальных тостов ничего не меняется.
          Expanded(child: Text(tr(m), style: disp(14, w: FontWeight.w600, c: C.text))),
        ]),
        // Фон тоже тема-зависимый (C.bg2): белый в светлой, near-black в тёмной — читается в обеих.
        backgroundColor: C.bg2,
        behavior: SnackBarBehavior.floating,
        // фиксированная ширина вместо margin: на развёрнутом окне тост растягивался во весь экран;
        // width сам центрирует SnackBar (width и margin вместе задавать нельзя)
        width: math.min(420.0, MediaQuery.of(context).size.width - 32),
        elevation: 10,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14), side: BorderSide(color: C.accent.withValues(alpha: 0.45))),
        duration: const Duration(seconds: 3),
      ));
  }

  Future<void> _open(String url) async {
    try {
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok) _toast(tr('Не удалось открыть ссылку'));
    } catch (_) {
      _toast(tr('Не удалось открыть ссылку'));
    }
  }

  Future<void> _copy(String text, String label, {bool secret = false}) async {
    // ждём фактической записи в буфер, потом сообщаем «скопировано» — иначе тост мог опередить запись
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    // Секреты (vpn_key / «Код входа») чистим из системного буфера через 90с — иначе они лежат
    // там бессрочно (Windows Clipboard History, Universal Clipboard, менеджеры буфера). Стираем
    // только если там всё ещё НАШЕ значение (юзер мог скопировать что-то другое). Вставить в
    // роутер/клиент успевают за секунды. Реф-ссылка и прочее (secret:false) не трогаются.
    if (secret) {
      Future.delayed(const Duration(seconds: 90), () async {
        final d = await Clipboard.getData('text/plain');
        if (d?.text == text) await Clipboard.setData(const ClipboardData(text: ''));
      });
    }
    _toast(appLang == 'en' ? '$label · copied to clipboard' : '$label · скопировано в буфер');
  }

  // Хост берём ТЕМ ЖЕ парсером (outboundFromKey), что строит реальный outbound в singbox_config.dart —
  // иначе проверка доверенного хоста и фактический коннект расходятся:
  //   • vless://u@bitaps.app:443@evil.com → outboundFromKey отдаёт u.host = «evil.com» (userinfo до
  //     ПОСЛЕДНЕГО @), а не «bitaps.app» — юзеру не покажут доверенное имя при уходе трафика на злой хост.
  //   • vmess:// и ss:// в base64-форме: Uri.parse().host вернул бы мусорный base64-блоб (и ложное
  //     «это не сервер bitaps» для настоящего ключа); outboundFromKey декодирует тело и даёт реальный server.
  String? _hostOf(String key) {
    try {
      final h = outboundFromKey(key.trim())?['server'] as String?;
      if (h != null && h.isNotEmpty) return h;
    } catch (e) {
      // НЕ логируем сам ключ: FormatException.toString() включает исходную строку (vless://…) → утечка ключа в лог
      debugPrint('_hostOf error: ${e.runtimeType}');
    }
    return null;
  }

  // Доверенный хост = точный домен bitaps, а не любая строка с подстрокой 'bitaps'
  // (иначе bitaps.attacker.com / evil-bitaps.io прошли бы без предупреждения).
  // Делегирует к общей isTrustedBitapsHost (singbox_config.dart) — единый список доменов
  // и логика сравнения с гардом туннеля (_isTrustedTunnelHost), чтобы они не разъезжались.
  bool _isTrustedHost(String host) => isTrustedBitapsHost(host);

  Future<bool?> _confirmForeignHost(String host) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: C.bg2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: C.line)),
        title: Text(tr('Не сервер bitaps'), style: disp(18, w: FontWeight.w700)),
        content: Text(
            appLang == 'en'
                ? '$host is not an official bitaps server. Import the key anyway?'
                : '$host — это не официальный сервер bitaps. Импортировать ключ всё равно?',
            style: mono(13, c: C.muted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Отмена'), style: mono(13, c: C.muted))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Импортировать'), style: mono(13, c: C.accent))),
        ],
      ),
    );
  }

  String get _netErr => tr('Нет связи с сервером — проверь интернет.');
  String _srvErr(int code) =>
      appLang == 'en' ? 'Server unavailable ($code). Try again later.' : 'Сервер недоступен ($code). Попробуй позже.';

  void _doLogout({bool silent = false}) {
    // сброс подключения (гасит поколение/таймеры/статус + возвращает кнопку в покой) — в контроллере,
    // чтобы отложенный коллбэк подключения не «переподключил» после выхода
    _conn.reset();
    setState(() {
      tgId = null;
      appToken = null;
      loginSecret = null;
      subPlan = null;
      subExpires = null;
      subName = null;
      subLimit = null;
      subActive = false;
      devices = [];
      // статистика аккаунта — тоже персональные данные: чистим при выходе
      statMemberSince = null;
      statPaidDays = null;
      statRefs = null;
      statTokens = null;
      subStreak = 0;
      subNextBonus = 0;
      subVip = false;
      keyStr = kDemoKey;
      // сбрасываем импортированный ключ/конфиг — иначе _applySub (гард importedHost==null)
      // не подхватит ключ следующего аккаунта после «тихого» логаута по истечению сессии
      importedHost = null;
      customCfg = null;
    });
    _save();
    _refreshTray(); // сбрасываем «дни/подписка» в меню трея после выхода
    if (!silent) _toast(tr('Вышли из аккаунта'));
  }

  void _logout() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: C.bg2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: C.line)),
        title: Text(tr('Выйти?'), style: disp(18, w: FontWeight.w700)),
        content: Text(tr('Выйдешь из аккаунта на этом устройстве. Подключение отключится, персональные настройки сохранятся.'), style: mono(13, c: C.muted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Отмена'), style: mono(13, c: C.muted))),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              // полный teardown через _doLogout: сбрасывает keyStr=demo (закрывает утечку ключа
              // прошлого аккаунта), conn, spin, и _save() перезаписывает pref 'key' демо-ключом
              _doLogout();
              // явный выход дополнительно чистит импортированный ключ/хост и их prefs
              final p = await SharedPreferences.getInstance();
              await p.remove('cfg'); await p.remove('host');
              if (mounted) setState(() { customCfg = null; importedHost = null; });
            },
            child: Text(tr('Выйти'), style: mono(13, c: C.danger)),
          ),
        ],
      ),
    );
  }

  void _dialog(String title, String body) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: C.bg2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: C.line)),
        title: Text(title, style: disp(18, w: FontWeight.w700)),
        // фикс. ширина: без неё AlertDialog берёт ширину по самой длинной строке (IntrinsicWidth) —
        // на развёрнутом окне однострочный текст растягивал бы диалог в полосу почти во весь экран
        content: SizedBox(width: 360, child: Text(body, style: mono(13, c: C.text))),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Ок'), style: mono(13, c: C.accent)))],
      ),
    );
  }

  // Единая точка смены вкладки: setState(tab) + _syncAnimations(). Звать ВЕЗДЕ вместо голого
  // rebuild(()=>tab=…), иначе анимации (шестерёнка/кольца/starfield) крутятся вхолостую на вкладке
  // без них и жгут батарею (как было у «сменить» на Главной, минуя логику _tabItem).
  void _goTab(int i) {
    setState(() => tab = i);
    _syncAnimations();
  }

  void _pickServer(Server s) {
    // Запрещаем смену и при conn==1 (идёт подключение): конфиг коннекта уже собран со старым
    // сервером — иначе UI показал бы один сервер, а туннель поднимался бы на другой (рассинхрон).
    if (conn != 0) {
      _toast(tr('Отключись, чтобы сменить сервер'));
      return;
    }
    if (!s.available) {
      _toast(appLang == 'en' ? '${tr(s.city)} — soon' : '${tr(s.city)} — скоро');
      return;
    }
    // Выбор конкретного сервера выключает режим «лучший сервер» (ползунок на Главной) —
    // иначе toggle() молча заменил бы только что выбранный сервер на «оптимальный».
    setState(() { server = s; bestServer = false; });
    _save();
    _toast(appLang == 'en' ? 'Server: ${tr(s.city)}' : 'Сервер: ${tr(s.city)}');
  }

  @override
  Widget build(BuildContext context) {
    // _syncAnimations больше НЕ регистрируем пост-фреймом на каждый build (плодило аллокации на
    // частых setState). Вместо этого зовём его событийно у мутаторов, влияющих на видимость анимаций:
    // смена вкладки (_tabItem), темы (_themeChip/didChangePlatformBrightness), стиля кнопки (_styleChip),
    // подключения (слушатель _conn), блокировки (lifecycle/_tryUnlock/_forgotPin) и первично в initState.
    // Статус-бар/системные оверлеи под актуальную тему: в светлой — тёмные иконки, в тёмной — светлые.
    final overlay = (C.light ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light).copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: C.bg,
      systemNavigationBarIconBrightness: C.light ? Brightness.dark : Brightness.light,
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(value: overlay, child: _buildBody());
  }

  Widget _buildBody() {
    if (_locked) return _lockScreen();
    if (_showOnboarding) return _onboarding(); // знакомство поверх всего (после PIN-замка)
    // Строим ТОЛЬКО активный экран: раньше каждый setState (включая посекундный тик таймера
    // подключения) собирал все четыре — вчетверо дороже без какой-либо пользы.
    final screen = switch (tab) { 0 => _home(), 1 => _servers(), 2 => _account(), _ => _settings() };
    // Контентная колонка: центр, максимум 560px (мобильная раскладка не меняется).
    final content = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          child: KeyedSubtree(key: ValueKey(tab), child: screen))));
    // Десктоп-каркас: широкое окно (>720) → слева узкий рейл навигации, справа активный экран;
    // узкое — как раньше (нижний таб-бар). Экраны — те же extension'ы, меняется только каркас.
    return LayoutBuilder(builder: (context, cons) {
      final wide = cons.maxWidth > 720;
      return Scaffold(
        backgroundColor: C.bg,
        body: Stack(children: [
          Positioned.fill(child: ColoredBox(color: C.bg)),
          // RepaintBoundary: starfield анимирует 60 fps — без собственного слоя он инвалидировал
          // бы отрисовку всего экрана каждый кадр; с ним композитор переиспользует остальные слои.
          if (!C.light) Positioned.fill(child: RepaintBoundary(child: AnimatedBuilder(
            animation: _twinkle,
            builder: (_, __) => CustomPaint(painter: StarPainter(_twinkle.value * 2 * math.pi)),
          ))),
          Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
            gradient: RadialGradient(center: const Alignment(0, -0.95), radius: 0.95,
              colors: [C.accent.withValues(alpha: C.light ? 0.16 : 0.17), C.accent.withValues(alpha: 0)])))),
          // синий угловой градиент — только обычная тёмная тема (в Фосфоре синий спорит с зелёным)
          if (!C.light && !C.phosphor) const Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
            gradient: RadialGradient(center: Alignment(1.0, -0.9), radius: 0.8,
              colors: [Color(0x1A2D8BFF), Color(0x002D8BFF)])))),
          // Фоны (Positioned.fill) — во всю ширину; контент — колонкой 560px по центру,
          // на широком десктопе слева добавляется рейл.
          SafeArea(bottom: false, child: wide
            ? Row(children: [_navRail(), Expanded(child: content)])
            : content),
          // CRT-сканлайны — поверх контента, только в теме «Фосфор». IgnorePointer: не перехватывает тапы.
          if (C.phosphor) const Positioned.fill(child: IgnorePointer(
            child: RepaintBoundary(child: CustomPaint(painter: ScanlinePainter())))),
        ]),
        bottomNavigationBar: wide ? null : _bottomBar(),
      );
    });
  }

  // Пункты навигации — общие для нижнего бара и десктоп-рейла.
  List<(String, IconData)> get _navItems => [
    (tr('Главная'), Icons.power_settings_new),
    (tr('Серверы'), Icons.public),
    (tr('Кабинет'), Icons.person_outline),
    (tr('Настройки'), Icons.settings_outlined),
  ];

  // ---------------- DESKTOP NAV RAIL ----------------
  // Узкий стеклянный рейл слева (ширина >720): мини-лого + те же 4 пункта вертикально.
  Widget _navRail() {
    final items = _navItems;
    return ClipRect(child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      child: Container(
        width: 96,
        decoration: BoxDecoration(
          color: C.bg2.withValues(alpha: 0.7),
          border: Border(right: BorderSide(color: C.line))),
        child: Column(children: [
          const SizedBox(height: 18),
          // мини-лого — как в шапке Главной (₿-квадрат с градиентом)
          Container(width: 34, height: 34, alignment: Alignment.center,
            decoration: BoxDecoration(gradient: accentGrad, borderRadius: BorderRadius.circular(10),
              boxShadow: [BoxShadow(color: C.accent.withValues(alpha: 0.5), blurRadius: 12)]),
            child: Text('₿', style: disp(19, w: FontWeight.w900, c: C.bg))),
          const SizedBox(height: 20),
          for (int i = 0; i < items.length; i++) _railItem(items[i].$1, items[i].$2, i),
          const Spacer(),
          // статус-пилюля внизу рейла — то же честное состояние, что и на Главной;
          // FittedBox ужимает «не защищено» в 96px рейла (иначе overflow)
          Padding(padding: const EdgeInsets.only(bottom: 16, left: 6, right: 6),
            child: FittedBox(fit: BoxFit.scaleDown, child: _shieldPill(conn == 2))),
        ]),
      ),
    ));
  }

  Widget _railItem(String label, IconData ic, int i) {
    final sel = tab == i;
    return Semantics(
      button: true,
      selected: sel,
      label: label,
      container: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _goTab(i),
        child: ExcludeSemantics(
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: sel ? C.accent.withValues(alpha: 0.14) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              // рамка задана всегда (прозрачная у невыбранных) — размер пункта не прыгает
              border: Border.all(color: sel ? C.accent.withValues(alpha: 0.45) : Colors.transparent)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(ic, size: 22, color: sel ? C.accent : C.muted),
              const SizedBox(height: 4),
              Text(label, style: mono(10.5, c: sel ? C.accent : C.muted, w: FontWeight.w600),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ),
      ),
    );
  }

  // ---------------- BOTTOM NAV ----------------
  Widget _bottomBar() {
    final items = _navItems;
    return ClipRect(child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      child: Container(
        decoration: BoxDecoration(color: C.bg2.withValues(alpha: 0.7), border: Border(top: BorderSide(color: C.line))),
        // Стеклянная подложка бара — во всю ширину, но сами вкладки держим в той же 560px-колонке,
        // что и контент (иначе на широком окне 4 таба разъезжались бы по краям на сотни px).
        // heightFactor: 1 обязателен. Без него Center забирает ВСЮ доступную высоту, а Scaffold
        // отдаёт нижнему бару столько, сколько тот попросил, — телу остаётся ноль. Внешне это
        // выглядело так: иконки вкладок висят посреди экрана, а весь контент исчез. На десктопе
        // не проявлялось: широкое окно использует боковой рейл, а не нижний бар.
        child: SafeArea(top: false, child: Center(heightFactor: 1, child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            // Expanded на каждую вкладку: при spaceAround с естественной шириной четыре подписи
            // («Настройки» — длинная) не влезали в 360px и обрезались. Теперь вкладки делят
            // ширину поровну, а подпись внутри при нехватке места ужимается.
            child: Row(children: [for (int i = 0; i < 4; i++) Expanded(child: _tabItem(items[i].$1, items[i].$2, i))]),
          ),
        ))),
      ),
    ));
  }

  Widget _tabItem(String label, IconData ic, int i) {
    final sel = tab == i;
    // Semantics для скринридера: элемент навигации как кнопка-вкладка с меткой и признаком выбора.
    // ExcludeSemantics на содержимом — чтобы иконка+текст не дублировали метку.
    return Semantics(
      button: true,
      selected: sel,
      label: label,
      container: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _goTab(i),
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(ic, size: 22, color: sel ? C.accent : C.muted),
              const SizedBox(height: 4),
              // подпись вкладки ужимается, а не обрезается: «Настройки»/«Settings» длиннее ячейки
              FittedBox(fit: BoxFit.scaleDown, child:
                Text(label, maxLines: 1, style: mono(10.5, c: sel ? C.accent : C.muted, w: FontWeight.w600))),
            ]),
          ),
        ),
      ),
    );
  }
}
