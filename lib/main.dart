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
// чтобы приватные имена (_ShellState, _secRead и т.п.) оставались доступны между файлами.
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
  // window_manager — только десктоп (на Android/iOS его нет → иначе краш на старте)
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    await windowManager.ensureInitialized();
    final opts = WindowOptions(
      size: const Size(440, 900),
      minimumSize: const Size(390, 760),
      center: true,
      backgroundColor: C.bg,
      title: 'bitaps VPN',
    );
    windowManager.waitUntilReadyToShow(opts, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  runApp(const BitApp());
}

// ============================ APP ============================
class BitApp extends StatelessWidget {
  const BitApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'bitaps VPN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: C.bg,
        colorScheme: ColorScheme.dark(primary: C.accent, surface: C.bg2),
        useMaterial3: true,
        fontFamily: 'SpaceGrotesk',
      ),
      home: const Shell(),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with TickerProviderStateMixin, WidgetsBindingObserver {
  int tab = 0;
  int mode = 0;
  int proto = 0;
  Server server = ruServers[0];
  bool tgl1 = false, tgl2 = true, tgl3 = true, tgl4 = false;
  String? appPin; // PIN блокировки приложения
  bool _locked = false;
  final TextEditingController _pinCtrl = TextEditingController();
  int accentIdx = 0, btnStyle = 0;
  int themeMode = 0; // 0 тёмная · 1 светлая · 2 системная
  bool autoConnect = false;
  String keyStr = kDemoKey;
  String? customCfg;
  String? importedHost;
  final TextEditingController _search = TextEditingController();
  final TextEditingController _support = TextEditingController();
  String _q = '';
  final Set<String> favs = {};
  // вход / подписка / устройства (реальные данные из Supabase)
  int? tgId;
  String? appToken, subPlan, subExpires, subName;
  String? loginSecret; // код входа (отдельный от vpn_key credential) — для входа в приложение/кабинет
  int? subLimit;
  bool subActive = false;
  bool _subLoading = false;
  List<Map<String, dynamic>> devices = [];
  final TextEditingController _loginCtrl = TextEditingController();
  bool get loggedIn => tgId != null && appToken != null;

  // Подключение вынесено в ConnectionController (см. connection.dart) — состояние и логика туннеля
  // больше не живут в _ShellState. Ниже тонкие прокси, чтобы экраны читали conn/hms/скорость как раньше.
  late final ConnectionController _conn;
  int get conn => _conn.conn;
  String get hms => _conn.hms;
  int get down => _conn.down;
  int get up => _conn.up;
  int get sessions => _conn.sessions;
  void toggle() => _conn.toggle();

  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  late final AnimationController _wave =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat();
  late final AnimationController _twinkle =
      AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();

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
    _conn.addListener(() { if (mounted) setState(() {}); });
    _load();
    _checkUpdate();
  }

  // крутить кнопку-шестерёнку: быстро во время коннекта, спокойно в покое/при обрыве
  void _spinConn(bool fast) {
    _spin.duration = Duration(milliseconds: fast ? 1400 : 6000);
    _spin.stop();
    _spin.repeat();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // авто-замок при сворачивании. paused (мобильный) + hidden (десктоп свёрнут). НЕ inactive —
    // он срабатывает на ЛЮБУЮ потерю фокуса (в т.ч. открытие внешней ссылки) и ложно блокировал бы.
    final bg = state == AppLifecycleState.paused || state == AppLifecycleState.hidden;
    if (bg && tgl1 && (appPin?.isNotEmpty ?? false) && !_locked) {
      setState(() => _locked = true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _conn.dispose();
    _spin.dispose();
    _wave.dispose();
    _twinkle.dispose();
    _search.dispose();
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
    if (!mounted) return;
    // язык: сохранённый выбор, иначе автоопределение по системной локали (ru → ru, иначе en)
    final savedLang = p.getString('lang');
    appLang = savedLang ??
        (WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'ru' ? 'ru' : 'en');
    setState(() {
      accentIdx = (p.getInt('accent') ?? 0).clamp(0, accentThemes.length - 1);
      btnStyle = (p.getInt('btnStyle') ?? 0).clamp(0, btnStyleNames.length - 1);
      mode = (p.getInt('mode') ?? 0).clamp(0, modeLabels.length - 1);
      proto = (p.getInt('proto') ?? 0).clamp(0, 2);
      themeMode = (p.getInt('themeMode') ?? 0).clamp(0, 2);
      autoConnect = p.getBool('autoConnect') ?? false;
      tgl1 = p.getBool('tgl1') ?? false;
      appPin = secPin;
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
    });
    if (loggedIn) _refreshSub(silent: true);
    if (autoConnect && conn == 0) {
      Future.delayed(const Duration(milliseconds: 500), () { if (mounted && conn == 0) toggle(); });
    }
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
    if (themeMode == 2 && mounted) setState(_applyThemeMode);
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('accent', accentIdx);
    await p.setInt('btnStyle', btnStyle);
    await p.setInt('mode', mode);
    await p.setInt('proto', proto);
    await p.setInt('themeMode', themeMode);
    await p.setString('lang', appLang);
    await p.setBool('autoConnect', autoConnect);
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

  // Быстрейший доступный сервер (минимальный пинг среди ru+intl) — единый источник для Главной и Серверов
  Server get fastestServer {
    final avail = [...ruServers, ...intlServers].where((s) => s.available).toList();
    if (avail.isEmpty) return ruServers[0];
    avail.sort((a, b) => a.ping.compareTo(b.ping));
    return avail.first;
  }

  // режим реально подбирает сервер: Стрим→мин.нагрузка, Игры/Авто→мин.пинг, Прив→зарубежный (иначе лучший)
  Server serverForMode(int m) {
    final avail = [...ruServers, ...intlServers].where((s) => s.available).toList();
    if (avail.isEmpty) return ruServers[0];
    if (m == 1) { avail.sort((a, b) => a.load.compareTo(b.load)); return avail.first; }
    if (m == 3) {
      final intl = avail.where((s) => s.country != 'Россия').toList();
      if (intl.isNotEmpty) { intl.sort((a, b) => a.ping.compareTo(b.ping)); return intl.first; }
    }
    avail.sort((a, b) => a.ping.compareTo(b.ping));
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
          Expanded(child: Text(m, style: disp(14, w: FontWeight.w600, c: C.text))),
        ]),
        backgroundColor: const Color(0xFF221F30),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        elevation: 10,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14), side: BorderSide(color: C.accent.withOpacity(0.45))),
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

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    _toast(appLang == 'en' ? '$label · copied to clipboard' : '$label · скопировано в буфер');
  }

  // Хост берём ТЕМ ЖЕ парсером (Uri.parse().host), что и реальное подключение в singbox_config.dart —
  // иначе проверка доверенного хоста и фактический коннект расходятся: напр.
  //   vless://u@bitaps.app:443@evil.com  →  ручной indexOf дал бы «bitaps.app» (первый @),
  //   а Uri.parse даёт «evil.com» (userinfo до ПОСЛЕДНЕГО @) — юзеру показали бы доверенное имя,
  //   а трафик ушёл бы на злой хост. Uri.parse также корректно отдаёт хост для ключа без :порта.
  String? _hostOf(String key) {
    try {
      final h = Uri.parse(key.trim()).host;
      if (h.isNotEmpty) return h;
    } catch (e) {
      debugPrint('_hostOf error: $e');
    }
    return null;
  }

  // Доверенный хост = точный домен bitaps, а не любая строка с подстрокой 'bitaps'
  // (иначе bitaps.attacker.com / evil-bitaps.io прошли бы без предупреждения).
  bool _isTrustedHost(String host) {
    final h = host.toLowerCase();
    const domains = ['bitaps.app', 'bitapsvpn.com'];
    for (final d in domains) {
      if (h == d || h.endsWith('.$d')) return true;
    }
    return false;
  }

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

  void _pickServer(Server s) {
    if (conn == 2) {
      _toast(tr('Отключитесь, чтобы сменить сервер'));
      return;
    }
    if (!s.available) {
      _toast(appLang == 'en' ? '${s.city} — soon' : '${s.city} — скоро');
      return;
    }
    setState(() => server = s);
    _toast(appLang == 'en' ? 'Server: ${s.city}' : 'Сервер: ${s.city}');
  }

  @override
  Widget build(BuildContext context) {
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
            colors: [C.accent.withOpacity(C.light ? 0.16 : 0.17), C.accent.withOpacity(0)])))),
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
        decoration: BoxDecoration(color: C.bg2.withOpacity(0.7), border: Border(top: BorderSide(color: C.line))),
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => tab = i),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(ic, size: 22, color: sel ? C.accent : C.muted),
          const SizedBox(height: 4),
          Text(label, style: mono(10.5, c: sel ? C.accent : C.muted, w: FontWeight.w600)),
        ]),
      ),
    );
  }
}
