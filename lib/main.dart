import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'singbox_config.dart';
import 'native_tunnel.dart';
import 'package:window_manager/window_manager.dart';

// Приложение разбито на модули; все они — части одной библиотеки (part/part of),
// чтобы приватные имена (_secRead, _load, _conn и т.п.) и extension'ы на ShellState
// оставались доступны между файлами.
part 'i18n.dart';        // локализация RU/EN
part 'theme.dart';       // тема/токены/шрифты
part 'models.dart';      // модели, константы/эндпоинты, токены+secure storage
part 'connection.dart';  // ConnectionController — жизненный цикл VPN-туннеля (вынесен из god-object)
part 'widgets.dart';     // painters + общие виджеты-строители
part 'api.dart';         // сетевые вызовы к edge-функциям + сетевые инструменты
part 'screens/home.dart';
part 'screens/servers.dart';
part 'screens/account.dart';
part 'screens/settings.dart';
part 'screens/lock.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Тему применяем СИНХРОННО до первого кадра и до WindowOptions: иначе backgroundColor окна
  // читает дефолтную тёмную C.bg, и у пользователей светлой темы мелькает тёмный фон на старте.
  await _applyStoredThemeEarly();
  // window_manager — только десктоп (на Android/iOS его нет → иначе краш на старте)
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    await windowManager.ensureInitialized();
    final opts = WindowOptions(
      size: const Size(440, 900),
      minimumSize: const Size(390, 760),
      center: true,
      backgroundColor: C.bg, // уже согласован с сохранённой темой (см. _applyStoredThemeEarly)
      title: 'bitaps VPN',
    );
    windowManager.waitUntilReadyToShow(opts, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  runApp(const BitApp());
}

// Прочитать сохранённый themeMode (0 тёмная · 1 светлая · 2 системная) и применить тему ДО runApp/окна.
// Дешёвое чтение SharedPreferences; при любой ошибке молча остаёмся на дефолте, старт не блокируем.
Future<void> _applyStoredThemeEarly() async {
  try {
    final p = await SharedPreferences.getInstance();
    final tm = (p.getInt('themeMode') ?? 0).clamp(0, 2);
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
      builder: (_, light, __) => MaterialApp(
        title: 'bitaps VPN',
        debugShowCheckedModeBanner: false,
        theme: _appTheme(light),
        home: const Shell(),
      ),
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

class ShellState extends State<Shell> with TickerProviderStateMixin, WidgetsBindingObserver {
  int tab = 0;
  int mode = 0;
  Server server = ruServers[0];
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
  final TextEditingController _support = TextEditingController();
  final Set<String> favs = {};
  // вход / подписка / устройства (реальные данные из Supabase)
  int? tgId;
  String? appToken, subPlan, subExpires, subName;
  String? loginSecret; // код входа (отдельный от vpn_key credential) — для входа в приложение/кабинет
  int? subLimit;
  bool subActive = false;
  bool _subLoading = false;
  bool _pairing = false; // идёт авто-вход через бота — гвард от двойного тапа (два диалога подряд)
  bool _toolBusy = false; // идёт сетевой инструмент (спид-тест/утечки) — гвард от двойного запуска
  bool _supportSending = false; // идёт отправка в поддержку — гвард от двойной отправки
  bool _loggingIn = false; // идёт вход по ключу — гвард от двойного входа
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
  bool _foreground = true; // приложение на переднем плане (обновляется в didChangeAppLifecycleState)

  // Запускать/останавливать анимации по факту видимости — экономит CPU/GPU/батарею.
  // Вызывается пост-фрейм из build() (ловит смену вкладки/темы/стиля/подключения) и из lifecycle.
  void _syncAnimations() {
    final vis = _foreground && !_locked; // не гоняем, если свёрнуто или заблокировано
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _conn = ConnectionController(
      keyOf: () => keyStr,
      serverOf: () => server,
      dropAlertOn: () => tgl2,
      trafWarnOn: () => tgl4,
      onToast: _toast,
      onPersist: _save,
      onSpin: _spinConn,
    );
    // conn мог смениться (подключение/обрыв/таймер) → пересобираем И сверяем анимации здесь,
    // а не пост-фреймом на каждый build (см. _syncAnimations вызовы у мутаторов tab/тема/стиль).
    _conn.addListener(() { if (mounted) { setState(() {}); _syncAnimations(); } });
    _load();
    _checkUpdate();
    // Одноразовый пост-фрейм: первичная сверка анимаций после первого кадра (дальше — событийно).
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _syncAnimations(); });
  }

  // крутить кнопку-шестерёнку: быстро во время коннекта, спокойно в покое/при обрыве.
  // Меняем скорость и перезапускаем ТОЛЬКО если шестерёнка сейчас видна — иначе просто
  // запоминаем длительность (её подхватит _syncAnimations, когда вернёмся на Главную).
  void _spinConn(bool fast) {
    _spin.duration = Duration(milliseconds: fast ? 1400 : 6000);
    _spin.stop();
    if (_foreground && !_locked && tab == 0 && btnStyle == 0) _spin.repeat();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // авто-замок при сворачивании. paused (мобильный) + hidden (десктоп свёрнут). НЕ inactive —
    // он срабатывает на ЛЮБУЮ потерю фокуса (в т.ч. открытие внешней ссылки) и ложно блокировал бы.
    final bg = state == AppLifecycleState.paused || state == AppLifecycleState.hidden;
    _foreground = state == AppLifecycleState.resumed;
    _syncAnimations(); // свернули → гасим анимации; вернулись → поднимаем нужные
    if (bg && tgl1 && (appPin?.isNotEmpty ?? false) && !_locked) {
      setState(() => _locked = true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    if (!mounted) return;
    // язык: сохранённый выбор, иначе автоопределение по системной локали (ru → ru, иначе en)
    final savedLang = p.getString('lang');
    appLang = savedLang ??
        (WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'ru' ? 'ru' : 'en');
    setState(() {
      accentIdx = (p.getInt('accent') ?? 0).clamp(0, accentThemes.length - 1);
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
      importedHost = p.getString('host');
      tgId = p.getInt('tgId');
      appToken = secToken;
      loginSecret = secLogin;
      subPlan = p.getString('subPlan');
      subExpires = p.getString('subExpires');
      subName = p.getString('subName');
      subLimit = p.getInt('subLimit');
      subActive = p.getBool('subActive') ?? false;
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
        final match = [...ruServers, ...intlServers].where((s) => s.id == saved && s.available);
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
    if (loggedIn) _refreshSub(silent: true);
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

  // тема: 0 тёмная · 1 светлая · 2 системная (следует за настройкой ОС)
  void _applyThemeMode() {
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
    await p.setString('devices', jsonEncode(devices));
    if (importedHost != null) {
      await p.setString('host', importedHost!);
    } else {
      await p.remove('host');
    }
  }

  // Пинг сервера: живой замер (кнопка «Пинг» на Серверах), пока его нет — статичный из models.dart.
  int pingOf(Server s) => pingMeasured[s.id] ?? s.ping;

  // режим реально подбирает сервер: Стрим→мин.нагрузка, Игры/Авто→мин.пинг, Прив→зарубежный (иначе лучший)
  Server serverForMode(int m) {
    final avail = [...ruServers, ...intlServers].where((s) => s.available).toList();
    if (avail.isEmpty) return ruServers[0];
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
          Expanded(child: Text(m, style: disp(14, w: FontWeight.w600, c: C.text))),
        ]),
        // Фон тоже тема-зависимый (C.bg2): белый в светлой, near-black в тёмной — читается в обеих.
        backgroundColor: C.bg2,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 18),
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

  Future<void> _copy(String text, String label) async {
    // ждём фактической записи в буфер, потом сообщаем «скопировано» — иначе тост мог опередить запись
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
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
      keyStr = kDemoKey;
      // сбрасываем импортированный ключ/конфиг — иначе _applySub (гард importedHost==null)
      // не подхватит ключ следующего аккаунта после «тихого» логаута по истечению сессии
      importedHost = null;
      customCfg = null;
    });
    _save();
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
        content: Text(body, style: mono(13, c: C.text)),
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
    final screens = [_home(), _servers(), _account(), _settings()];
    return Scaffold(
      backgroundColor: C.bg,
      body: Stack(children: [
        Positioned.fill(child: ColoredBox(color: C.bg)),
        if (!C.light) Positioned.fill(child: AnimatedBuilder(
          animation: _twinkle,
          builder: (_, __) => CustomPaint(painter: StarPainter(_twinkle.value * 2 * math.pi)),
        )),
        Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
          gradient: RadialGradient(center: const Alignment(0, -0.95), radius: 0.95,
            colors: [C.accent.withValues(alpha: C.light ? 0.16 : 0.17), C.accent.withValues(alpha: 0)])))),
        if (!C.light) const Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
          gradient: RadialGradient(center: Alignment(1.0, -0.9), radius: 0.8,
            colors: [Color(0x1A2D8BFF), Color(0x002D8BFF)])))),
        SafeArea(bottom: false, child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          child: KeyedSubtree(key: ValueKey(tab), child: screens[tab]))),
      ]),
      bottomNavigationBar: _bottomBar(),
    );
  }

  // ---------------- BOTTOM NAV ----------------
  Widget _bottomBar() {
    final items = [
      (tr('Главная'), Icons.power_settings_new),
      (tr('Серверы'), Icons.public),
      (tr('Кабинет'), Icons.person_outline),
      (tr('Настройки'), Icons.settings_outlined),
    ];
    return ClipRect(child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      child: Container(
        decoration: BoxDecoration(color: C.bg2.withValues(alpha: 0.7), border: Border(top: BorderSide(color: C.line))),
        child: SafeArea(top: false, child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [for (int i = 0; i < 4; i++) _tabItem(items[i].$1, items[i].$2, i)]),
        )),
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
              Text(label, style: mono(10.5, c: sel ? C.accent : C.muted, w: FontWeight.w600)),
            ]),
          ),
        ),
      ),
    );
  }
}
