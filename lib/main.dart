import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

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

// ============================ TOKENS ============================
class C {
  static Color bg = const Color(0xFF06040C);
  static Color bg2 = const Color(0xFF0C0A14);
  static Color text = const Color(0xFFEDF1F8);
  static Color muted = const Color(0xFF8A93A6);
  static Color line = const Color(0x14FFFFFF);
  static Color fill = const Color(0x0AFFFFFF);   // заливка чипов/строк (тема-зависимая)
  static Color field = const Color(0x59000000);  // фон полей/код-блоков (тема-зависимая)
  static Color accent = const Color(0xFFFF7A1A);
  static Color accentSoft = const Color(0xFFFFB347);
  static const accent2 = Color(0xFF2D8BFF);
  static const ok = Color(0xFF39D98A);
  static const warn = Color(0xFFFFAE3D);
  static const danger = Color(0xFFFF5470);

  static bool light = false;
  static void applyTheme(bool isLight) {
    light = isLight;
    bg = isLight ? const Color(0xFFEAEEF6) : const Color(0xFF06040C);
    bg2 = isLight ? const Color(0xFFFFFFFF) : const Color(0xFF0C0A14);
    text = isLight ? const Color(0xFF0F1828) : const Color(0xFFEDF1F8);
    muted = isLight ? const Color(0xFF5A6781) : const Color(0xFF8A93A6);
    line = isLight ? const Color(0x1A101A30) : const Color(0x14FFFFFF);
    fill = isLight ? const Color(0x0D000000) : const Color(0x0AFFFFFF);
    field = isLight ? const Color(0x0A000000) : const Color(0x59000000);
  }
}

LinearGradient get accentGrad =>
    LinearGradient(colors: [C.accentSoft, C.accent], begin: Alignment.topLeft, end: Alignment.bottomRight);

// Реальные ссылки/бэкенд
const kBot = 'https://t.me/bitaps_vpn_auth_bot';
const kSupport = 'https://t.me/bitapssupport';
const kChannel = 'https://t.me/bitapsvpnofficial';
const kRef = 'https://t.me/bitaps_vpn_auth_bot?start=ref_demo';
const kNotify = 'https://bjkozsukvifkxriojxrz.supabase.co/functions/v1/notify';
const kApiKey = 'sb_publishable_X2CJWgjqeZtbNelAri9ofw_trbfWF9Z';
const kDemoKey = 'vless://3a7c9f1e-0b2d-4e6f-9a1c-7b3e2f8d4c5a@vpn.bitaps.app:443?security=reality&type=tcp&sni=www.microsoft.com&fp=chrome&pbk=DEMObitapsPLACEHOLDERkey00000000000000000000000&sid=88#bitaps%20VPN';
const kAppLogin = 'https://bjkozsukvifkxriojxrz.supabase.co/functions/v1/app-login';
const kAppSub = 'https://bjkozsukvifkxriojxrz.supabase.co/functions/v1/app-sub';
const kAppPair = 'https://bjkozsukvifkxriojxrz.supabase.co/functions/v1/app-pair';

// Персонализация: акцентные темы (имя, основной, мягкий) + стили кнопки
const List<(String, Color, Color)> accentThemes = [
  ('Sunset', Color(0xFFFF7A1A), Color(0xFFFFB347)),
  ('Neon', Color(0xFF2DE2FF), Color(0xFF6AA8FF)),
  ('Emerald', Color(0xFF19D98A), Color(0xFF6FF0BD)),
  ('Lavender', Color(0xFFA779FF), Color(0xFFD0B3FF)),
  ('Crimson', Color(0xFFFF4D6D), Color(0xFFFF9BAD)),
];
const btnStyleNames = ['Шестерёнка', 'Кольцо', 'Орб', 'Пульс'];

TextStyle disp(double s, {FontWeight w = FontWeight.w700, Color? c}) =>
    TextStyle(fontFamily: 'SpaceGrotesk', fontSize: s, fontWeight: w, color: c ?? C.text, letterSpacing: -0.3, height: 1.15);
TextStyle mono(double s, {FontWeight w = FontWeight.w500, Color? c}) =>
    TextStyle(fontFamily: 'JetBrainsMono', fontSize: s, fontWeight: w, color: c ?? C.muted, height: 1.2);

// ============================ MODELS / MOCK ============================
class Server {
  final String id, city, country, flag, proto;
  final int ping, load;
  final bool premium, available;
  const Server(this.id, this.city, this.country, this.flag, this.ping, this.load,
      {this.premium = false, this.available = true, this.proto = 'Reality'});
}

const ruServers = [
  Server('ru-msk', 'Москва', 'Россия', '🇷🇺', 12, 34),
  Server('ru-spb', 'Санкт-Петербург', 'Россия', '🇷🇺', 21, 41),
  Server('ru-ekb', 'Екатеринбург', 'Россия', '🇷🇺', 33, 28),
];
const intlServers = [
  Server('nl-ams', 'Амстердам', 'Нидерланды', '🇳🇱', 48, 22, premium: true, available: false),
  Server('de-fra', 'Франкфурт', 'Германия', '🇩🇪', 52, 18, premium: true, available: false),
  Server('fi-hel', 'Хельсинки', 'Финляндия', '🇫🇮', 45, 27, premium: true, available: false),
  Server('tr-ist', 'Стамбул', 'Турция', '🇹🇷', 63, 31, premium: true, available: false),
];

class Faq {
  final String q, a;
  const Faq(this.q, this.a);
}

const faqs = [
  Faq('Сколько устройств можно подключить?', 'До 10 устройств одновременно по одной подписке.'),
  Faq('Вы ведёте логи?', 'Нет. Мы не храним логи активности — только техническую информацию для работы сервиса.'),
  Faq('Как продлить подписку?', 'В «Кабинете» нажми «Продлить» — оплата через Telegram, СБП или крипту.'),
  Faq('VPN не подключается?', 'Смени локацию или протокол на «Авто», проверь интернет. Не помогло — напиши в поддержку.'),
];

const modeLabels = ['Авто', 'Стрим', 'Игры', 'Прив.'];

// ============================ STARFIELD (premium bg) ============================
class _Star {
  final double x, y, r, o;
  final bool accent;
  const _Star(this.x, this.y, this.r, this.o, this.accent);
}

final List<_Star> _stars = () {
  int seed = 0x9E3779B9;
  double next() {
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
    return seed / 0x7FFFFFFF;
  }
  return List.generate(120, (_) => _Star(next(), next(), 0.4 + next() * 1.6, 0.12 + next() * 0.6, next() > 0.92));
}();

class StarPainter extends CustomPainter {
  final double t;
  StarPainter(this.t);
  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < _stars.length; i++) {
      final s = _stars[i];
      final twinkle = 0.7 + 0.3 * math.sin(t * 0.8 + i * 1.7);
      final col = (s.accent ? C.accent : Colors.white).withOpacity((s.o * twinkle).clamp(0, 1));
      canvas.drawCircle(Offset(s.x * size.width, s.y * size.height), s.r, Paint()..color = col);
    }
  }

  @override
  bool shouldRepaint(StarPainter old) => old.t != t;
}

// Шестерёнка рисуется в коде, чтобы перекрашиваться под выбранную тему
class GearPainter extends CustomPainter {
  final Color col;
  GearPainter(this.col);
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    final p = Paint()
      ..shader = LinearGradient(colors: [C.accentSoft, col], begin: Alignment.topLeft, end: Alignment.bottomRight)
          .createShader(Rect.fromCircle(center: c, radius: r));
    for (int i = 0; i < 10; i++) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(i / 10 * 2 * math.pi);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(0, -r * 0.84), width: r * 0.20, height: r * 0.34),
          Radius.circular(r * 0.05)),
        p);
      canvas.restore();
    }
    canvas.drawCircle(c, r * 0.72, p);
    canvas.drawCircle(c, r * 0.50, Paint()..color = const Color(0xFF0C0A14)); // тёмный медальон в обеих темах
    canvas.drawCircle(c, r * 0.50,
      Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = col.withOpacity(0.45));
  }

  @override
  bool shouldRepaint(GearPainter old) => old.col != col;
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

class _ShellState extends State<Shell> with TickerProviderStateMixin {
  int tab = 0;
  int conn = 0; // 0 off, 1 connecting, 2 on
  int secs = 0;
  int mode = 0;
  int proto = 0;
  int sessions = 0;
  Timer? _timer;
  Server server = ruServers[0];
  bool tgl1 = false, tgl2 = true, tgl3 = true, tgl4 = false;
  String? appPin; // PIN блокировки приложения
  bool _locked = false;
  final TextEditingController _pinCtrl = TextEditingController();
  int accentIdx = 0, btnStyle = 0, down = 0, up = 0;
  int themeMode = 0; // тема всегда тёмная (выбор темы убран); ключ хранится для совместимости
  bool autoConnect = false;
  String keyStr = kDemoKey;
  String? customCfg;
  String? importedHost;
  final math.Random _rnd = math.Random();
  final TextEditingController _search = TextEditingController();
  final TextEditingController _support = TextEditingController();
  String _q = '';
  final Set<String> favs = {};
  // вход / подписка / устройства (реальные данные из Supabase)
  int? tgId;
  String? appToken, subPlan, subExpires, subName;
  int? subLimit;
  bool subActive = false;
  bool _subLoading = false;
  List<Map<String, dynamic>> devices = [];
  final TextEditingController _loginCtrl = TextEditingController();
  bool get loggedIn => tgId != null && appToken != null;

  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  late final AnimationController _wave =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat();
  late final AnimationController _twinkle =
      AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
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
    if (!mounted) return;
    setState(() {
      accentIdx = (p.getInt('accent') ?? 0).clamp(0, accentThemes.length - 1);
      btnStyle = (p.getInt('btnStyle') ?? 0).clamp(0, btnStyleNames.length - 1);
      mode = (p.getInt('mode') ?? 0).clamp(0, modeLabels.length - 1);
      proto = (p.getInt('proto') ?? 0).clamp(0, 2);
      themeMode = 0; // тема всегда тёмная — выбор темы убран
      autoConnect = p.getBool('autoConnect') ?? false;
      tgl1 = p.getBool('tgl1') ?? false;
      appPin = p.getString('appPin');
      tgl2 = p.getBool('tgl2') ?? true;
      tgl3 = p.getBool('tgl3') ?? true;
      tgl4 = p.getBool('tgl4') ?? false;
      sessions = p.getInt('sessions') ?? 0;
      customCfg = p.getString('cfg');
      keyStr = p.getString('key') ?? kDemoKey;
      importedHost = p.getString('host');
      tgId = p.getInt('tgId');
      appToken = p.getString('appToken');
      subPlan = p.getString('subPlan');
      subExpires = p.getString('subExpires');
      subName = p.getString('subName');
      subLimit = p.getInt('subLimit');
      subActive = p.getBool('subActive') ?? false;
      try {
        devices = ((jsonDecode(p.getString('devices') ?? '[]')) as List).cast<Map<String, dynamic>>();
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
    });
    if (loggedIn) _refreshSub(silent: true);
    if (autoConnect && conn == 0) {
      Future.delayed(const Duration(milliseconds: 500), () { if (mounted && conn == 0) toggle(); });
    }
  }

  void _applyThemeMode() {
    C.applyTheme(false); // премиум-тема всегда тёмная
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('accent', accentIdx);
    await p.setInt('btnStyle', btnStyle);
    await p.setInt('mode', mode);
    await p.setInt('proto', proto);
    await p.setInt('themeMode', themeMode);
    await p.setBool('autoConnect', autoConnect);
    await p.setBool('tgl1', tgl1);
    if (appPin != null && appPin!.isNotEmpty) { await p.setString('appPin', appPin!); } else { await p.remove('appPin'); }
    await p.setBool('tgl2', tgl2);
    await p.setBool('tgl3', tgl3);
    await p.setBool('tgl4', tgl4);
    await p.setInt('sessions', sessions);
    await p.setStringList('favs', favs.toList());
    if (customCfg != null) await p.setString('cfg', customCfg!);
    await p.setString('key', keyStr);
    if (tgId != null) { await p.setInt('tgId', tgId!); } else { await p.remove('tgId'); }
    if (appToken != null) { await p.setString('appToken', appToken!); } else { await p.remove('appToken'); }
    if (subPlan != null) await p.setString('subPlan', subPlan!);
    if (subExpires != null) await p.setString('subExpires', subExpires!);
    if (subName != null) await p.setString('subName', subName!);
    if (subLimit != null) await p.setInt('subLimit', subLimit!);
    await p.setBool('subActive', subActive);
    await p.setString('devices', jsonEncode(devices));
    if (importedHost != null) {
      await p.setString('host', importedHost!);
    } else {
      await p.remove('host');
    }
  }

  void toggle() {
    if (conn == 1) return;
    if (conn == 0) {
      setState(() => conn = 1);
      _spin.duration = const Duration(milliseconds: 1400);
      _spin.stop();
      _spin.repeat();
      Future.delayed(const Duration(milliseconds: 1700), () {
        if (!mounted) return;
        setState(() {
          conn = 2;
          secs = 0;
          down = 84;
          up = 13;
          sessions++;
        });
        _save();
        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() { secs++; down = 60 + _rnd.nextInt(70); up = 8 + _rnd.nextInt(20); });
        });
      });
    } else {
      _timer?.cancel();
      _spin.duration = const Duration(seconds: 6);
      _spin.stop();
      _spin.repeat();
      setState(() {
        conn = 0;
        secs = 0;
      });
    }
  }

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

  // Инструмент с сетью: окно с крутилкой → результат прямо в окне (видно всегда)
  Future<void> _runTool(String title, Future<String> Function() work) async {
    final fut = work();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => FutureBuilder<String>(
        future: fut,
        builder: (c, snap) {
          final done = snap.connectionState == ConnectionState.done;
          return AlertDialog(
            backgroundColor: C.bg2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: C.line)),
            title: Text(title, style: disp(18, w: FontWeight.w700)),
            content: !done
                ? Row(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: C.accent)),
                    const SizedBox(width: 14),
                    Text('Минутку…', style: mono(13, c: C.muted)),
                  ])
                : Text(snap.hasError ? 'Не удалось выполнить.\n${snap.error}' : (snap.data ?? ''), style: mono(13, c: C.text)),
            actions: done
                ? [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Ок', style: mono(13, c: C.accent)))]
                : null,
          );
        },
      ),
    );
  }

  Future<void> _open(String url) async {
    try {
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok) _toast('Не удалось открыть ссылку');
    } catch (_) {
      _toast('Не удалось открыть ссылку');
    }
  }

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    _toast('$label · скопировано в буфер');
  }

  String _uuid() {
    String h(int n) => List.generate(n, (_) => '0123456789abcdef'[_rnd.nextInt(16)]).join();
    return '${h(8)}-${h(4)}-4${h(3)}-${'89ab'[_rnd.nextInt(4)]}${h(3)}-${h(12)}';
  }

  String _demoKey() =>
      'vless://${_uuid()}@vpn.bitaps.app:443?security=reality&type=tcp&sni=www.microsoft.com&fp=chrome&pbk=DEMObitapsPLACEHOLDERkey00000000000000000000000&sid=88#bitaps%20VPN';

  String? _hostOf(String key) {
    try {
      if (key.startsWith('vless://')) {
        final at = key.indexOf('@');
        final colon = key.indexOf(':', at);
        if (at > 0 && colon > at) return key.substring(at + 1, colon);
      } else {
        return Uri.parse(key).host;
      }
    } catch (e) {
      debugPrint('_hostOf error: $e');
    }
    return null;
  }

  // «Обновить» = перевыпуск ключа (новый UUID в реальном формате bitaps)
  void _rotateKey() {
    setState(() {
      keyStr = _demoKey();
      importedHost = null;
    });
    _save();
    _toast('Ключ перевыпущен — новый UUID ✓');
  }

  // Импорт своего ключа/подписки из буфера (модель Happ)
  Future<void> _importKey() async {
    final data = await Clipboard.getData('text/plain');
    final t = (data?.text ?? '').trim();
    if (!(t.startsWith('vless://') || t.startsWith('http://') || t.startsWith('https://'))) {
      _toast('В буфере нет vless:// или ссылки-подписки');
      return;
    }
    final host = _hostOf(t);
    if (host != null && !host.toLowerCase().contains('bitaps')) {
      final ok = await _confirmForeignHost(host);
      if (ok != true) return;
    }
    setState(() {
      keyStr = t;
      importedHost = host;
    });
    _save();
    _toast(host != null ? 'Ключ заменён на $host ✓' : 'Ключ заменён ✓');
  }

  Future<bool?> _confirmForeignHost(String host) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: C.bg2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: C.line)),
        title: Text('Не сервер bitaps', style: disp(18, w: FontWeight.w700)),
        content: Text('$host — это не официальный сервер bitaps. Импортировать ключ всё равно?', style: mono(13, c: C.muted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Отмена', style: mono(13, c: C.muted))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text('Импортировать', style: mono(13, c: C.accent))),
        ],
      ),
    );
  }

  // ----- вход по ключу / реальная подписка / устройства -----
  void _applySub(Map<String, dynamic> d) {
    subName = d['name'] as String?;
    subPlan = d['plan'] as String?;
    subExpires = d['expires_at'] as String?;
    subLimit = (d['device_limit'] as num?)?.toInt();
    subActive = d['active'] == true;
    if (d['vpn_key'] is String) keyStr = d['vpn_key'] as String;
    devices = ((d['devices'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  int? _daysLeft() {
    if (subExpires == null) return null;
    final e = DateTime.tryParse(subExpires!);
    if (e == null) return null;
    return e.toUtc().difference(DateTime.now().toUtc()).inHours ~/ 24;
  }

  // Русские склонения дней: 1 день / 2-4 дня / 5+ дней
  String _pluralDays(int n) {
    final n10 = n % 10, n100 = n % 100;
    if (n10 == 1 && n100 != 11) return 'день';
    if (n10 >= 2 && n10 <= 4 && (n100 < 12 || n100 > 14)) return 'дня';
    return 'дней';
  }

  // Лимит устройств: число, либо «…» при загрузке, либо «—» если неизвестно
  String get _limitStr => subLimit != null ? '$subLimit' : (_subLoading ? '…' : '—');

  String get _netErr => 'Нет связи с сервером — проверь интернет.';
  String _srvErr(int code) => 'Сервер недоступен ($code). Попробуй позже.';

  Future<void> _login([String? presetKey]) async {
    final key = (presetKey ?? _loginCtrl.text).trim();
    if (key.length < 12) {
      _toast('Вставь свой ключ из бота');
      return;
    }
    if (!(key.startsWith('vless://') || key.startsWith('http://') || key.startsWith('https://'))) {
      _toast('Ключ должен начинаться с vless:// или https://');
      return;
    }
    _toast('Вхожу…');
    try {
      final r = await http
          .post(Uri.parse(kAppLogin),
              headers: {'content-type': 'application/json', 'apikey': kApiKey},
              body: jsonEncode({'key': key}))
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      if (r.statusCode >= 500) {
        _toast(_srvErr(r.statusCode));
        return;
      }
      if (r.statusCode == 401 || r.statusCode == 403) {
        _loginError('Этот ключ не подошёл. Возьми актуальный ключ в боте.');
        return;
      }
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] == true && d['telegram_id'] is num) {
        setState(() {
          tgId = (d['telegram_id'] as num).toInt();
          appToken = d['app_token'] as String?;
          _applySub(d);
          _loginCtrl.clear();
        });
        _save();
        _toast('Вход выполнен ✓');
      } else {
        _loginError('Ключ не найден. Возьми актуальный ключ в боте.');
      }
    } on TimeoutException catch (e) {
      debugPrint('_login timeout: $e');
      _toast(_netErr);
    } catch (e) {
      debugPrint('_login error: $e');
      _toast(_netErr);
    }
  }

  // Авто-вход через бота: старт привязки → открыть бота → опрашивать, пока не подтвердит → войти.
  Future<void> _pairLogin() async {
    String token = '';
    try {
      final r = await http
          .post(Uri.parse(kAppPair),
              headers: {'content-type': 'application/json', 'apikey': kApiKey},
              body: jsonEncode({'action': 'start'}))
          .timeout(const Duration(seconds: 15));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true || d['url'] == null) {
        _toast('Не удалось начать вход, попробуй ещё раз');
        return;
      }
      token = d['token'] as String;
      await _open(d['url'] as String);
    } on TimeoutException {
      _toast(_netErr);
      return;
    } catch (e) {
      debugPrint('_pairLogin start: $e');
      _toast(_netErr);
      return;
    }
    if (!mounted) return;
    bool cancelled = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dctx) => AlertDialog(
        backgroundColor: C.bg2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 6),
          SizedBox(width: 34, height: 34, child: CircularProgressIndicator(color: C.accent, strokeWidth: 3)),
          const SizedBox(height: 16),
          Text('Подтверди вход в Telegram', style: disp(15, w: FontWeight.w700, c: C.text)),
          const SizedBox(height: 6),
          Text('Открылся бот — нажми «Запустить» (Start). Я войду сам, как подтвердишь.',
              textAlign: TextAlign.center, style: mono(12, c: C.muted)),
        ]),
        actions: [
          TextButton(onPressed: () { cancelled = true; Navigator.pop(dctx); }, child: Text('Отмена', style: mono(13, c: C.muted))),
        ],
      ),
    );
    String? key;
    for (int i = 0; i < 40 && !cancelled; i++) {
      await Future.delayed(const Duration(seconds: 3));
      if (cancelled || !mounted) break;
      try {
        final cr = await http
            .post(Uri.parse(kAppPair),
                headers: {'content-type': 'application/json', 'apikey': kApiKey},
                body: jsonEncode({'action': 'check', 'token': token}))
            .timeout(const Duration(seconds: 10));
        final cd = jsonDecode(cr.body) as Map<String, dynamic>;
        if (cd['key'] != null) { key = cd['key'] as String; break; }
        if (cd['pending'] != true && cd['ok'] != true) break; // истёк/ошибка
      } catch (_) {/* сеть моргнула — продолжаем опрос */}
    }
    if (cancelled) return; // окно уже закрыто «Отменой»
    if (mounted && Navigator.canPop(context)) Navigator.pop(context);
    if (key != null) {
      await _login(key);
    } else if (mounted) {
      _toast('Не дождался подтверждения. Открой бота и нажми «Запустить».');
    }
  }

  void _loginError(String msg) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: C.bg2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: C.line)),
        title: Text('Не удалось войти', style: disp(18, w: FontWeight.w700)),
        content: Text(msg, style: mono(13, c: C.muted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Закрыть', style: mono(13, c: C.muted))),
          TextButton(onPressed: () { Navigator.pop(context); _open(kBot); }, child: Text('Открыть бота', style: mono(13, c: C.accent))),
        ],
      ),
    );
  }

  Future<void> _refreshSub({String? del, bool silent = false}) async {
    if (!loggedIn) {
      if (!silent) _toast('Сначала войди по ключу');
      return;
    }
    if (!silent) _toast(del != null ? 'Удаляю устройство…' : 'Обновляю…');
    if (mounted) setState(() => _subLoading = true);
    try {
      final r = await http
          .post(Uri.parse(kAppSub),
              headers: {'content-type': 'application/json', 'apikey': kApiKey},
              body: jsonEncode({'telegram_id': tgId, 'token': appToken, if (del != null) 'del': del}))
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      if (r.statusCode == 401 || r.statusCode == 403) {
        if (!silent) _toast('Сессия истекла — войди заново');
        _doLogout();
        return;
      }
      if (r.statusCode >= 500) {
        if (!silent) _toast(_srvErr(r.statusCode));
        return;
      }
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] == true) {
        setState(() => _applySub(d));
        _save();
        if (!silent) _toast(del != null ? 'Устройство удалено ✓' : 'Обновлено ✓');
      } else if (!silent) {
        _toast('Не удалось обновить');
      }
    } on TimeoutException catch (e) {
      debugPrint('_refreshSub timeout: $e');
      if (!silent) _toast(_netErr);
    } catch (e) {
      debugPrint('_refreshSub error: $e');
      if (!silent) _toast(_netErr);
    } finally {
      if (mounted) setState(() => _subLoading = false);
    }
  }

  void _doLogout() {
    setState(() {
      tgId = null;
      appToken = null;
      subPlan = null;
      subExpires = null;
      subName = null;
      subLimit = null;
      subActive = false;
      devices = [];
      keyStr = kDemoKey;
    });
    _save();
    _toast('Вышли из аккаунта');
  }

  Future<void> _sendSupport() async {
    final msg = _support.text.trim();
    if (msg.isEmpty) {
      _toast('Сначала напиши сообщение');
      return;
    }
    _toast('Отправляю…');
    try {
      final r = await http.post(Uri.parse(kNotify),
          headers: {'content-type': 'application/json', 'apikey': kApiKey},
          body: jsonEncode({
            'type': 'support',
            'name': loggedIn ? (subName != null && subName!.isNotEmpty ? subName! : 'Аккаунт #$tgId') : 'Пользователь приложения',
            'email': '',
            'message': msg,
            'source': 'десктоп-приложение'
          }));
      if (r.statusCode >= 200 && r.statusCode < 300) {
        _support.clear();
        setState(() {});
        _toast('Отправлено в поддержку ✓');
      } else {
        _toast(r.statusCode >= 500 ? _srvErr(r.statusCode) : 'Ошибка отправки (${r.statusCode})');
      }
    } catch (e) {
      debugPrint('_sendSupport error: $e');
      _toast(_netErr);
    }
  }

  Future<void> _leakCheck() => _runTool('Проверка утечек', () async {
        final r = await http.get(Uri.parse('https://api.ipify.org?format=json'));
        if (r.statusCode != 200) throw Exception('сервер вернул ${r.statusCode}');
        final ip = (jsonDecode(r.body) as Map)['ip'];
        if (ip == null) throw Exception('IP не получен');
        return 'Твой текущий внешний IP:\n\n$ip\n\nС включённым VPN он сменится на адрес сервера — так видно, что трафик идёт через туннель.';
      });

  Future<void> _speedTest() => _runTool('Спид-тест', () async {
        final sw = Stopwatch()..start();
        final r = await http.get(Uri.parse('https://speed.cloudflare.com/__down?bytes=4000000'));
        if (r.statusCode != 200) throw Exception('сервер вернул ${r.statusCode}');
        sw.stop();
        final secs = sw.elapsedMilliseconds / 1000.0;
        final mbps = r.bodyBytes.length * 8 / secs / 1e6;
        final mb = r.bodyBytes.length / 1048576;
        return 'Скорость загрузки: ${mbps.toStringAsFixed(1)} Mbps\n\nПолучено ${mb.toStringAsFixed(1)} MB за ${sw.elapsedMilliseconds} мс\n(реальный замер через Cloudflare)';
      });

  void _showStats() {
    _dialog('Статистика',
        'Сессий запущено: $sessions\nТекущая сессия: ${conn == 2 ? hms : "не подключено"}\nСервер: ${server.city}\nРежим: ${modeLabels[mode]}\nИзбранных серверов: ${favs.length}');
  }

  void _customConfig() {
    final ctrl = TextEditingController(text: customCfg ?? '');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: C.bg2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: C.line)),
        title: Text('Свой конфиг', style: disp(18, w: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          style: mono(12, c: C.text),
          cursorColor: C.accent,
          decoration: InputDecoration(hintText: 'Вставь vless:// или другой конфиг', hintStyle: mono(12, c: C.muted)),
        ),
        actions: [
          TextButton(onPressed: () { ctrl.dispose(); Navigator.pop(context); }, child: Text('Отмена', style: mono(13, c: C.muted))),
          TextButton(
            onPressed: () {
              final t = ctrl.text.trim();
              ctrl.dispose();
              Navigator.pop(context);
              if (t.startsWith('vless://') || t.startsWith('http://') || t.startsWith('https://')) {
                setState(() { keyStr = t; importedHost = _hostOf(t); customCfg = t; });
                _save();
                _toast(importedHost != null ? 'Ключ заменён на $importedHost ✓' : 'Ключ заменён ✓');
              } else {
                setState(() => customCfg = t.isEmpty ? null : t);
                _save();
                _toast(t.isEmpty ? 'Конфиг очищен' : 'Конфиг сохранён ✓');
              }
            },
            child: Text('Сохранить', style: mono(13, c: C.accent)),
          ),
        ],
      ),
    );
  }

  void _logout() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: C.bg2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: C.line)),
        title: Text('Выйти?', style: disp(18, w: FontWeight.w700)),
        content: Text('Выйдешь из аккаунта на этом устройстве. Подключение отключится, персональные настройки сохранятся.', style: mono(13, c: C.muted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Отмена', style: mono(13, c: C.muted))),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              _timer?.cancel();
              final p = await SharedPreferences.getInstance();
              for (final k in ['tgId', 'appToken', 'subPlan', 'subExpires', 'subName', 'subLimit', 'subActive', 'devices', 'cfg', 'host']) {
                await p.remove(k);
              }
              if (!mounted) return;
              setState(() {
                conn = 0; secs = 0;
                customCfg = null; importedHost = null;
                tgId = null; appToken = null; subPlan = null; subExpires = null;
                subName = null; subLimit = null; subActive = false; devices = [];
              });
              _toast('Вышли из аккаунта');
            },
            child: Text('Выйти', style: mono(13, c: C.danger)),
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
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text('Ок', style: mono(13, c: C.accent)))],
      ),
    );
  }

  void _pickServer(Server s) {
    if (conn == 2) {
      _toast('Отключитесь, чтобы сменить сервер');
      return;
    }
    if (!s.available) {
      _toast('${s.city} — скоро');
      return;
    }
    setState(() => server = s);
    _toast('Сервер: ${s.city}');
  }

  // ---------------- APP-LOCK (PIN) ----------------
  Widget _lockScreen() {
    return Scaffold(
      backgroundColor: C.bg,
      body: Center(child: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(28),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 72, height: 72, alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: accentGrad,
              boxShadow: [BoxShadow(color: C.accent.withOpacity(0.4), blurRadius: 20)]),
            child: const Icon(Icons.lock_outline, size: 34, color: Colors.white)),
          const SizedBox(height: 20),
          Text('bitaps заблокирован', style: disp(20, w: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('Введите PIN, чтобы продолжить', style: mono(12), textAlign: TextAlign.center),
          const SizedBox(height: 22),
          SizedBox(width: 210, child: TextField(controller: _pinCtrl, obscureText: true, keyboardType: TextInputType.number,
            textAlign: TextAlign.center, maxLength: 8, style: disp(22, w: FontWeight.w700, c: C.text), cursorColor: C.accent, autofocus: true,
            decoration: InputDecoration(counterText: '', hintText: '••••', hintStyle: disp(22, c: C.muted),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: C.line)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: C.accent))),
            onSubmitted: (_) => _tryUnlock())),
          const SizedBox(height: 18),
          SizedBox(width: 210, child: _btn('Разблокировать', kind: 0, icon: Icons.lock_open, onTap: _tryUnlock)),
          const SizedBox(height: 16),
          GestureDetector(behavior: HitTestBehavior.opaque, onTap: _forgotPin,
            child: Text('Не помню PIN — выйти', style: mono(12, c: C.muted))),
        ]))),
      ),
    );
  }

  void _tryUnlock() {
    if (_pinCtrl.text.trim() == appPin) {
      setState(() => _locked = false);
      _pinCtrl.clear();
    } else {
      _toast('Неверный PIN');
      _pinCtrl.clear();
    }
  }

  void _forgotPin() {
    _pinCtrl.clear();
    setState(() { appPin = null; tgl1 = false; _locked = false; });
    _doLogout();
    _save();
    _toast('Блокировка сброшена');
  }

  Future<void> _enableLock() async {
    final c1 = TextEditingController(), c2 = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (dctx) => AlertDialog(
      backgroundColor: C.bg2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text('Задай PIN для входа', style: disp(16, w: FontWeight.w700, c: C.text)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: c1, obscureText: true, keyboardType: TextInputType.number, maxLength: 8,
          style: mono(15, c: C.text), cursorColor: C.accent,
          decoration: InputDecoration(counterText: '', hintText: 'PIN (4–8 цифр)', hintStyle: mono(12, c: C.muted))),
        TextField(controller: c2, obscureText: true, keyboardType: TextInputType.number, maxLength: 8,
          style: mono(15, c: C.text), cursorColor: C.accent,
          decoration: InputDecoration(counterText: '', hintText: 'Повтори PIN', hintStyle: mono(12, c: C.muted))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dctx, false), child: Text('Отмена', style: mono(13, c: C.muted))),
        TextButton(onPressed: () {
          final p1 = c1.text.trim(), p2 = c2.text.trim();
          if (p1.length < 4) { _toast('PIN — минимум 4 цифры'); return; }
          if (p1 != p2) { _toast('PIN не совпадает'); return; }
          appPin = p1;
          Navigator.pop(dctx, true);
        }, child: Text('Включить', style: mono(13, c: C.accent))),
      ],
    ));
    c1.dispose(); c2.dispose();
    setState(() => tgl1 = (ok == true));
    _save();
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
    const items = [
      ('Главная', Icons.power_settings_new),
      ('Серверы', Icons.public),
      ('Кабинет', Icons.person_outline),
      ('Настройки', Icons.settings_outlined),
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

  // ---------------- HOME ----------------
  Widget _home() {
    final connected = conn == 2;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      children: [
        Row(children: [_logo(), const Spacer(), _shieldPill(connected)]),
        const SizedBox(height: 10),
        Center(child: _powerButton()),
        const SizedBox(height: 4),
        Center(child: Text(
          conn == 0 ? 'Отключено' : conn == 1 ? 'Подключение…' : 'Подключено',
          style: disp(22, w: FontWeight.w700, c: connected ? C.accent : (conn == 1 ? C.warn : C.text)))),
        const SizedBox(height: 6),
        Center(child: Text(connected ? hms : '00:00:00',
          style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 38, fontWeight: FontWeight.w700,
            color: connected ? C.accentSoft : C.muted, letterSpacing: 2))),
        const SizedBox(height: 4),
        Center(child: Text(connected ? 'под защитой' : 'нажми на кнопку', style: mono(12))),
        const SizedBox(height: 20),
        Row(children: [
          for (int i = 0; i < 4; i++)
            Expanded(child: Padding(padding: EdgeInsets.only(right: i < 3 ? 8 : 0), child: _modeChip(modeLabels[i], i))),
        ]),
        const SizedBox(height: 10),
        Text('Авто-режим сам подберёт сервер и маршрут. Стрим · Игры · Прив. — скоро.', style: mono(12)),
        const SizedBox(height: 14),
        _card(child: Row(children: [
          Text(server.flag, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(server.city, style: disp(16, w: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('${server.ping} ms · ${server.proto}', style: mono(12)),
          ])),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => tab = 1),
            child: Row(children: [
              Icon(Icons.swap_horiz, size: 17, color: C.accent),
              const SizedBox(width: 5),
              Text('сменить', style: disp(13, w: FontWeight.w700, c: C.accent)),
            ]),
          ),
        ])),
        const SizedBox(height: 10),
        Row(children: [
          Text('ещё:', style: mono(12)),
          const SizedBox(width: 8),
          Expanded(child: SizedBox(height: 32, child: ListView(
            scrollDirection: Axis.horizontal,
            children: [for (final s in [ruServers[1], ruServers[2], ...intlServers]) _miniChip(s)]))),
        ]),
        const SizedBox(height: 12),
        _card(padding: 13, child: Row(children: [
          Text('↓', style: disp(15, c: C.muted)),
          const SizedBox(width: 5),
          Text(connected ? '$down' : '—', style: mono(13, c: C.text, w: FontWeight.w600)),
          const SizedBox(width: 16),
          Text('↑', style: disp(15, c: C.muted)),
          const SizedBox(width: 5),
          Text(connected ? '$up' : '—', style: mono(13, c: C.text, w: FontWeight.w600)),
          const Spacer(),
          Icon(Icons.language, size: 15, color: C.muted),
          const SizedBox(width: 6),
          Text(connected ? '95.142.16.7' : 'IP скрыт', style: mono(12)),
        ])),
        const SizedBox(height: 12),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () { if (conn == 0) _pickServer(fastestServer); toggle(); },
          child: _card(child: Row(children: [
            _gIcon(Icons.bolt),
            const SizedBox(width: 13),
            Text(connected ? 'Отключить' : 'Подключиться к быстрейшему серверу', style: disp(15, w: FontWeight.w600)),
          ])),
        ),
      ],
    );
  }

  Widget _logo() => Row(children: [
        Container(width: 30, height: 30, alignment: Alignment.center,
          decoration: BoxDecoration(gradient: accentGrad, borderRadius: BorderRadius.circular(9),
            boxShadow: [BoxShadow(color: C.accent.withOpacity(0.5), blurRadius: 12)]),
          child: Text('₿', style: disp(17, w: FontWeight.w900, c: C.bg))),
        const SizedBox(width: 9),
        Text('bit', style: disp(22, w: FontWeight.w800)),
        Text('aps', style: disp(22, w: FontWeight.w800, c: C.accent)),
      ]);

  // ---------------- PREMIUM POWER BUTTON ----------------
  Widget _powerButton() {
    final connected = conn == 2;
    final busy = conn == 1;
    final glow = connected ? 0.6 : busy ? 0.35 : 0.0;
    final col = busy ? C.accentSoft : C.accent;
    final showRings = connected || btnStyle == 3;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: toggle,
      child: SizedBox(
        width: 270, height: 270,
        child: Stack(alignment: Alignment.center, children: [
          if (showRings)
            AnimatedBuilder(animation: _wave, builder: (_, __) {
              return Stack(alignment: Alignment.center, children: [
                for (int i = 0; i < 3; i++) _pulseRing((_wave.value + i / 3) % 1.0),
              ]);
            }),
          AnimatedContainer(
            duration: const Duration(milliseconds: 450),
            width: 270, height: 270,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(
              colors: [C.accent.withOpacity(glow), C.accent.withOpacity(0)], stops: const [0.25, 1.0])),
          ),
          _powerInner(col),
        ]),
      ),
    );
  }

  Widget _powerInner(Color col) {
    final on = conn == 2;
    switch (btnStyle) {
      case 1: // кольцо — толстое светящееся кольцо
        return Stack(alignment: Alignment.center, children: [
          Container(width: 214, height: 214,
            decoration: BoxDecoration(shape: BoxShape.circle,
              border: Border.all(color: col, width: 10),
              boxShadow: [BoxShadow(color: col.withOpacity(on ? 0.5 : 0.14), blurRadius: 22)])),
          Container(width: 150, height: 150,
            decoration: BoxDecoration(shape: BoxShape.circle, color: C.bg2, border: Border.all(color: C.line))),
          Icon(Icons.power_settings_new, size: 60, color: col),
        ]);
      case 2: // орб — наполненная светящаяся сфера
        return Container(width: 192, height: 192, alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle,
            gradient: RadialGradient(center: const Alignment(-0.4, -0.4),
              colors: on ? [C.accentSoft, C.accent, C.accent.withOpacity(0.55)] : const [Color(0xFF1A1728), Color(0xFF12101C)]),
            boxShadow: [BoxShadow(color: col.withOpacity(on ? 0.55 : 0.14), blurRadius: 36)]),
          child: Icon(Icons.power_settings_new, size: 62, color: on ? Colors.black.withOpacity(0.85) : col));
      case 3: // пульс — концентрические кольца от ядра
        return Stack(alignment: Alignment.center, children: [
          for (final r in const [220.0, 178.0, 136.0])
            Container(width: r, height: r,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: col.withOpacity(0.22), width: 1.5))),
          Container(width: 96, height: 96, alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: C.bg2, border: Border.all(color: col, width: 2),
              boxShadow: [BoxShadow(color: col.withOpacity(on ? 0.5 : 0.1), blurRadius: 20)]),
            child: Icon(Icons.power_settings_new, size: 44, color: col)),
        ]);
      default: // шестерёнка
        return Stack(alignment: Alignment.center, children: [
          Container(width: 250, height: 250, decoration: BoxDecoration(shape: BoxShape.circle,
            gradient: RadialGradient(colors: [col.withOpacity(C.light ? 0.20 : 0.0), col.withOpacity(0)]))),
          RotationTransition(turns: _spin, child: AnimatedOpacity(
            duration: const Duration(milliseconds: 350), opacity: conn == 0 ? 0.85 : 1,
            child: CustomPaint(size: const Size(212, 212), painter: GearPainter(col)))),
          Text('B', style: disp(60, w: FontWeight.w800, c: Colors.white)),
        ]);
    }
  }

  Widget _pulseRing(double v) {
    return Opacity(
      opacity: ((1 - v) * 0.45).clamp(0, 1),
      child: Container(
        width: 150 + v * 110, height: 150 + v * 110,
        decoration: BoxDecoration(shape: BoxShape.circle,
          border: Border.all(color: C.accent.withOpacity(0.5), width: 2)),
      ),
    );
  }

  Widget _modeChip(String label, int i) {
    final sel = mode == i;
    return GestureDetector(
      onTap: () { setState(() { mode = i; if (conn == 0) server = serverForMode(i); }); _save(); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 40, alignment: Alignment.center,
        decoration: BoxDecoration(
          color: sel ? C.accent.withOpacity(0.16) : C.fill,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: sel ? C.accent : C.line),
        ),
        child: Text(label, style: disp(13, w: FontWeight.w700, c: sel ? C.accent : C.muted)),
      ),
    );
  }

  Widget _miniChip(Server s) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _pickServer(s),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: server.id == s.id ? C.accent.withOpacity(0.16) : C.fill,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: server.id == s.id ? C.accent : C.line)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(s.flag, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
              Text(s.city, style: disp(12, w: FontWeight.w600)),
            ]),
          ),
        ),
      );

  Widget _accentSwatch(int i) {
    final th = accentThemes[i];
    final sel = accentIdx == i;
    return GestureDetector(
      onTap: () {
        setState(() {
          accentIdx = i;
          C.accent = th.$2;
          C.accentSoft = th.$3;
        });
        _save();
      },
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        width: 44, height: 44, alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle,
          gradient: LinearGradient(colors: [th.$3, th.$2]),
          border: Border.all(color: sel ? (C.light ? Colors.black : Colors.white) : Colors.transparent, width: 3),
          boxShadow: [BoxShadow(color: th.$2.withOpacity(0.5), blurRadius: sel ? 14 : 6)]),
        child: sel ? Icon(Icons.check, size: 18, color: C.light ? Colors.black : Colors.white) : null,
      ),
    );
  }

  Widget _styleChip(int i) {
    final sel = btnStyle == i;
    const previews = [Icons.settings, Icons.radio_button_unchecked, Icons.brightness_1, Icons.wifi_tethering];
    return GestureDetector(
      onTap: () { setState(() => btnStyle = i); _save(); },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(color: sel ? C.accent.withOpacity(0.16) : C.fill,
          borderRadius: BorderRadius.circular(11), border: Border.all(color: sel ? C.accent : C.line)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(previews[i], size: 15, color: sel ? C.accent : C.muted),
          const SizedBox(width: 7),
          Text(btnStyleNames[i], style: disp(13, w: FontWeight.w600, c: sel ? C.accent : C.muted)),
        ])),
    );
  }

  // ---------------- SERVERS ----------------
  Widget _servers() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Серверы', style: disp(26, w: FontWeight.w800)),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: _infoTile('32', 'серверов\nонлайн')),
            const SizedBox(width: 12),
            Expanded(child: _infoTile('12', 'локаций')),
            const SizedBox(width: 12),
            Expanded(child: _infoTile('99.9%', 'аптайм')),
          ]),
          const SizedBox(height: 16),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _pickServer(fastestServer),
            child: _card(strong: true, child: Row(children: [
              _gIcon(Icons.bolt),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Text('Быстрый сервер', style: disp(16, w: FontWeight.w700)),
                  const SizedBox(width: 8), _badge('АВТО', C.accent)]),
                const SizedBox(height: 3),
                Text('${fastestServer.city} · ${fastestServer.ping} ms', style: mono(12)),
              ])),
              Icon(Icons.chevron_right, color: C.muted),
            ])),
          ),
          const SizedBox(height: 12),
          _card(padding: 12, child: Row(children: [
            Icon(Icons.search, size: 18, color: C.muted),
            const SizedBox(width: 10),
            Expanded(child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _q = v),
              style: mono(13, c: C.text),
              cursorColor: C.accent,
              decoration: InputDecoration(isDense: true, border: InputBorder.none,
                contentPadding: EdgeInsets.zero, hintText: 'Поиск города или страны', hintStyle: mono(13, c: C.muted)),
            )),
            if (_q.isNotEmpty) GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() { _q = ''; _search.clear(); }),
              child: Icon(Icons.close, size: 16, color: C.muted)),
          ])),
          const SizedBox(height: 22),
          ..._serverSections(),
        ],
      );

  List<Widget> _serverSections() {
    final all = [...ruServers, ...intlServers];
    final q = _q.trim().toLowerCase();
    if (q.isNotEmpty) {
      final found = all.where((s) => s.city.toLowerCase().contains(q) || s.country.toLowerCase().contains(q)).toList();
      if (found.isEmpty) {
        return [
          Padding(padding: const EdgeInsets.symmetric(vertical: 28), child: Column(children: [
            Icon(Icons.travel_explore, size: 32, color: C.muted),
            const SizedBox(height: 10),
            Text('Ничего не найдено.\nПопробуй город — Москва, Амстердам —\nили страну, либо очисти поиск.',
              textAlign: TextAlign.center, style: mono(12)),
          ])),
        ];
      }
      return [
        _kicker('результаты'),
        const SizedBox(height: 10),
        for (final s in found) _serverRow(s),
      ];
    }
    final favList = all.where((s) => favs.contains(s.id)).toList();
    return [
      if (favList.isNotEmpty) ...[
        _kicker('⭐ избранное'),
        const SizedBox(height: 10),
        for (final s in favList) _serverRow(s),
        const SizedBox(height: 22),
      ],
      _kicker('🇷🇺 Россия'),
      const SizedBox(height: 10),
      for (final s in ruServers) _serverRow(s),
      const SizedBox(height: 22),
      _kicker('🌍 Зарубежные · скоро'),
      const SizedBox(height: 10),
      for (final s in intlServers) _serverRow(s),
    ];
  }

  Widget _serverRow(Server s) {
    final sel = s.id == server.id;
    final pingCol = s.ping < 60 ? C.ok : s.ping < 120 ? C.warn : C.danger;
    final pingLabel = s.ping < 60 ? 'быстрый отклик' : s.ping < 120 ? 'средний отклик' : 'медленный отклик';
    return IgnorePointer(
      ignoring: !s.available,
      child: Opacity(
        opacity: s.available ? 1 : 0.55,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: s.available ? () => _pickServer(s) : null,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(color: C.fill,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: sel ? C.accent.withOpacity(0.5) : C.line)),
            child: Row(children: [
              Container(width: 40, height: 40, alignment: Alignment.center,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
                child: Text(s.flag, style: const TextStyle(fontSize: 20))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(s.city, style: disp(15, w: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                  if (s.premium) ...[const SizedBox(width: 6), _badge('PRO', C.accentSoft)],
                  if (!s.available) ...[const SizedBox(width: 6), _badge('Скоро', C.muted)],
                ]),
                const SizedBox(height: 2),
                Text(s.country, style: mono(12)),
              ])),
              Tooltip(message: '$pingLabel · ${s.ping} ms',
                child: Text('${s.ping} ms', style: mono(13, c: pingCol, w: FontWeight.w600))),
              const SizedBox(width: 10),
              Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${s.load}%', style: mono(10, c: C.muted)),
                const SizedBox(height: 3),
                SizedBox(width: 42, child: _loadBar(s.load)),
              ]),
              const SizedBox(width: 8),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () { setState(() => favs.contains(s.id) ? favs.remove(s.id) : favs.add(s.id)); _save(); },
                child: Icon(favs.contains(s.id) ? Icons.star : Icons.star_border, size: 18,
                  color: favs.contains(s.id) ? C.accentSoft : C.muted)),
              const SizedBox(width: 8),
              Icon(sel ? Icons.check_circle : Icons.circle_outlined, size: 20, color: sel ? C.accent : C.muted),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _loadBar(int pct) {
    final col = pct < 50 ? C.ok : pct < 80 ? C.warn : C.danger;
    return ClipRRect(borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(value: pct / 100, minHeight: 4, backgroundColor: C.line, color: col));
  }

  // ---------------- ACCOUNT ----------------
  // баннер-напоминание при близком/истёкшем сроке (тумблер «Подписка истекает»)
  Widget _expiryBanner(int days) {
    final expired = days <= 0;
    return GestureDetector(
      onTap: () => _open(kBot),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(color: C.warn.withOpacity(0.12), borderRadius: BorderRadius.circular(14),
          border: Border.all(color: C.warn.withOpacity(0.5))),
        child: Row(children: [
          Icon(Icons.notifications_active, color: C.warn, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(expired ? 'Подписка истекла' : 'Подписка истекает', style: disp(14, w: FontWeight.w700, c: C.warn)),
            const SizedBox(height: 2),
            Text(expired ? 'Продли, чтобы вернуть доступ' : 'Осталось $days ${_dayWord(days)} — продли заранее',
              style: mono(11, c: C.muted)),
          ])),
          const SizedBox(width: 8),
          Text('Продлить →', style: mono(12, c: C.accent)),
        ]),
      ),
    );
  }

  String _dayWord(int d) {
    final m10 = d % 10, m100 = d % 100;
    if (m10 == 1 && m100 != 11) return 'день';
    if (m10 >= 2 && m10 <= 4 && (m100 < 10 || m100 >= 20)) return 'дня';
    return 'дней';
  }

  Widget _account() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Кабинет', style: disp(26, w: FontWeight.w800)),
          const SizedBox(height: 18),
          _profileCard(),
          const SizedBox(height: 14),
          if (loggedIn && tgl3 && _daysLeft() != null && _daysLeft()! <= 3) ...[_expiryBanner(_daysLeft()!), const SizedBox(height: 14)],
          _subCard(),
          const SizedBox(height: 14),
          _keyCard(),
          if (loggedIn) ...[const SizedBox(height: 14), _devicesCard()],
          const SizedBox(height: 14),
          _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [_gIcon(Icons.card_giftcard), const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _kicker('пригласи друзей'), const SizedBox(height: 3), Text('Приглашай — получай бонусные дни', style: mono(11))]))]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: _miniStat('3', 'позвал')),
              Expanded(child: _miniStat('2', 'оформили')),
              Expanded(child: _miniStat('30', 'дней бонус')),
            ]),
            const SizedBox(height: 12),
            _btn('Поделиться ссылкой', kind: 1, icon: Icons.share, onTap: () { if (loggedIn) { _copy('https://t.me/bitaps_vpn_auth_bot?start=ref$tgId', 'Реферальная ссылка'); } else { _toast('Войди, чтобы получить свою реферальную ссылку'); } }),
          ])),
          const SizedBox(height: 14),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _open(kBot),
            child: _card(strong: true, child: Row(children: [
              _gIcon(Icons.router),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('B-box — VPN для всего дома', style: disp(16, w: FontWeight.w600)),
                const SizedBox(height: 3),
                Text('устройство для дома · 15 000 ₽', style: mono(12, c: C.accent)),
              ])),
              Icon(Icons.chevron_right, color: C.muted),
            ])),
          ),
          const SizedBox(height: 14),
          _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [_gIcon(Icons.forum), const SizedBox(width: 12), _kicker('поддержка')]),
            const SizedBox(height: 12),
            Container(padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: C.field, borderRadius: BorderRadius.circular(10)),
              child: TextField(
                controller: _support,
                maxLines: 3,
                style: mono(13, c: C.text),
                cursorColor: C.accent,
                decoration: InputDecoration(isDense: true, border: InputBorder.none,
                  contentPadding: EdgeInsets.zero, hintText: 'Опиши проблему…', hintStyle: mono(13, c: C.muted)),
              )),
            const SizedBox(height: 12),
            _btn('Отправить', kind: 0, icon: Icons.send, onTap: _sendSupport),
            const SizedBox(height: 10),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _open(kSupport),
              child: Center(child: Text('или напиши @bitapssupport', style: mono(12, c: C.accent)))),
          ])),
          const SizedBox(height: 14),
          _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [_gIcon(Icons.help), const SizedBox(width: 12), _kicker('частые вопросы')]),
            const SizedBox(height: 8),
            for (final f in faqs) _faqRow(f),
          ])),
          const SizedBox(height: 18),
          Center(child: Text('bitaps vpn · v1.0', style: mono(11, c: C.muted))),
        ],
      );

  Widget _profileCard() {
    final name = loggedIn ? ((subName != null && subName!.isNotEmpty) ? subName! : 'Аккаунт (#$tgId)') : 'Вход не выполнен';
    final initial = name.isNotEmpty ? name.substring(0, 1).toUpperCase() : 'A';
    return _card(strong: true, child: Row(children: [
      Container(width: 60, height: 60, alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: accentGrad,
          boxShadow: [BoxShadow(color: C.accent.withOpacity(0.4), blurRadius: 18)]),
        child: Text(initial, style: disp(26, w: FontWeight.w800, c: C.bg))),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, style: disp(20, w: FontWeight.w700)),
        const SizedBox(height: 3),
        Text(loggedIn ? 'Вход по ключу из бота' : 'Войди через Telegram, чтобы активировать подписку', style: mono(11)),
        const SizedBox(height: 6),
        Row(children: loggedIn
            ? [_badge(subActive ? 'Активна' : 'Не активна', subActive ? C.ok : C.muted),
               if (subPlan != null) ...[const SizedBox(width: 6), _badge(subPlan!.toUpperCase(), C.accent)]]
            : [_badge('Гость', C.muted)]),
      ])),
      if (loggedIn) GestureDetector(behavior: HitTestBehavior.opaque, onTap: _doLogout,
        child: Icon(Icons.logout, size: 20, color: C.muted)),
    ]));
  }

  String _planLabel(String? p) {
    if (p == null) return 'Нет подписки';
    if (p == 'trial') return 'Пробный период';
    return 'Тариф «$p»';
  }

  Widget _subCard() {
    if (!loggedIn) {
      return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [_gIcon(Icons.login), const SizedBox(width: 12), _kicker('вход')]),
        const SizedBox(height: 10),
        Text('Войди через Telegram — приложение само подхватит твою подписку и ключ. Без ручного копирования.', style: mono(12)),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: _btn('Войти через Telegram', kind: 0, icon: Icons.send, onTap: _pairLogin)),
        const SizedBox(height: 14),
        Text('или вставь ключ вручную:', style: mono(11, c: C.muted)),
        const SizedBox(height: 8),
        Container(padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: C.field, borderRadius: BorderRadius.circular(10)),
          child: TextField(controller: _loginCtrl, maxLines: 2, style: mono(11, c: C.text), cursorColor: C.accent,
            decoration: InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.zero,
              hintText: 'ключ vless://…@host:443 из бота', hintStyle: mono(12, c: C.muted)))),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _btn('Войти', kind: 1, icon: Icons.login, onTap: _login)),
          const SizedBox(width: 12),
          Expanded(child: _btn('Ключ в боте', kind: 1, icon: Icons.smart_toy, onTap: () => _open(kBot))),
        ]),
      ]));
    }
    final days = _daysLeft();
    final ringVal = (days ?? 0).clamp(0, 30).toInt();
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [_gIcon(Icons.workspace_premium), const SizedBox(width: 12), _kicker('подписка'), const Spacer(),
        GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => _refreshSub(), child: Icon(Icons.refresh, size: 18, color: C.accent))]),
      const SizedBox(height: 16),
      Row(children: [
        _ring(ringVal, 30),
        const SizedBox(width: 20),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_planLabel(subPlan), style: disp(20, w: FontWeight.w700, c: subActive ? C.accent : C.muted)),
          const SizedBox(height: 6),
          Row(children: [Icon(Icons.event, size: 14, color: C.muted), const SizedBox(width: 6),
            Text(days != null ? (days > 0 ? 'осталось $days ${_pluralDays(days)}' : 'истекла') : (subActive ? 'активна' : 'не активна'), style: mono(13))]),
          const SizedBox(height: 4),
          Row(children: [Icon(Icons.devices, size: 14, color: C.muted), const SizedBox(width: 6),
            Text('${devices.length} / $_limitStr устройств', style: mono(13))]),
        ])),
      ]),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: _btn('Продлить', kind: 0, icon: Icons.bolt, onTap: () => _open(kBot))),
        const SizedBox(width: 12),
        Expanded(child: _btn('Обновить', kind: 1, icon: Icons.refresh, onTap: () => _refreshSub())),
      ]),
    ]));
  }

  Widget _keyCard() => _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [_gIcon(Icons.qr_code_2), const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _kicker('ключ доступа'), const SizedBox(height: 3),
            Text(loggedIn ? 'твой ключ из аккаунта' : 'для роутера и ручной настройки', style: mono(11))]))]),
        const SizedBox(height: 12),
        Container(padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: C.field, borderRadius: BorderRadius.circular(10)),
          child: SingleChildScrollView(scrollDirection: Axis.horizontal,
            child: Text(keyStr, style: mono(11, c: C.text), maxLines: 1, softWrap: false))),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _btn('Скопировать', kind: 1, icon: Icons.copy, onTap: () => _copy(keyStr, 'Ключ'))),
          const SizedBox(width: 12),
          Expanded(child: loggedIn
              ? _btn('Обновить', kind: 2, icon: Icons.refresh, onTap: () => _refreshSub())
              : _btn('Вставить', kind: 2, icon: Icons.content_paste, onTap: _importKey)),
        ]),
      ]));

  Widget _devicesCard() => _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [_gIcon(Icons.devices), const SizedBox(width: 12),
          _kicker('устройства · ${devices.length}/$_limitStr'), const Spacer(),
          GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => _refreshSub(), child: Icon(Icons.refresh, size: 18, color: C.accent))]),
        const SizedBox(height: 8),
        if (devices.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Column(children: [
            Icon(Icons.devices_other, size: 30, color: C.muted),
            const SizedBox(height: 8),
            Text('Пока нет устройств.\nПодключись с устройства — оно появится здесь.', textAlign: TextAlign.center, style: mono(12)),
          ]))
        else
          for (final d in devices) _deviceRow(d),
      ]));

  Widget _deviceRow(Map<String, dynamic> d) {
    final name = (d['name'] as String?) ?? 'Устройство';
    final id = d['id'] as String?;
    return Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: Row(children: [
      Icon(Icons.smartphone, size: 18, color: C.muted),
      const SizedBox(width: 10),
      Expanded(child: Text(name, style: disp(14, w: FontWeight.w600), overflow: TextOverflow.ellipsis)),
      GestureDetector(behavior: HitTestBehavior.opaque,
        onTap: id == null ? null : () => _confirmDelDevice(id, name),
        child: Icon(Icons.delete_outline, size: 19, color: C.danger)),
    ]));
  }

  void _confirmDelDevice(String id, String name) {
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: C.bg2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: C.line)),
      title: Text('Удалить устройство?', style: disp(18, w: FontWeight.w700)),
      content: Text('«$name» будет удалено из подписки.', style: mono(13, c: C.muted)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('Отмена', style: mono(13, c: C.muted))),
        TextButton(onPressed: () { Navigator.pop(context); _refreshSub(del: id); }, child: Text('Удалить', style: mono(13, c: C.danger))),
      ],
    ));
  }

  Widget _faqRow(Faq f) => Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 12),
          iconColor: C.accent,
          collapsedIconColor: C.muted,
          title: Text(f.q, style: disp(14, w: FontWeight.w600)),
          children: [Align(alignment: Alignment.centerLeft, child: Text(f.a, style: mono(13)))],
        ),
      );

  // ---------------- SETTINGS ----------------
  Widget _settings() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Настройки', style: disp(26, w: FontWeight.w800)),
          const SizedBox(height: 18),
          _kicker('персонализация'),
          const SizedBox(height: 10),
          _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Цвет акцента', style: disp(15, w: FontWeight.w600)),
            const SizedBox(height: 12),
            Row(children: [for (int i = 0; i < accentThemes.length; i++) _accentSwatch(i)]),
            const SizedBox(height: 18),
            Text('Кнопка подключения', style: disp(15, w: FontWeight.w600)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [for (int i = 0; i < btnStyleNames.length; i++) _styleChip(i)]),
          ])),
          const SizedBox(height: 22),
          _kicker('безопасность'),
          const SizedBox(height: 10),
          _card(child: Column(children: [
            _toggle('Блокировка входа', 'PIN при открытии приложения', tgl1, (v) { if (v) { _enableLock(); } else { setState(() { tgl1 = false; appPin = null; }); _save(); } }),
            _divider(),
            _toggle('Обрыв соединения', 'Уведомлять, если VPN отвалился', tgl2, (v) { setState(() => tgl2 = v); _save(); }, soon: true),
            _divider(),
            _toggle('Подписка истекает', 'Напомнить за пару дней', tgl3, (v) { setState(() => tgl3 = v); _save(); }),
            _divider(),
            _toggle('Лимит трафика', 'Сигнал при большом расходе', tgl4, (v) { setState(() => tgl4 = v); _save(); }, soon: true),
            _divider(),
            _toggle('Авто-подключение', 'Подключаться сразу при запуске', autoConnect, (v) { setState(() => autoConnect = v); _save(); }),
          ])),
          const SizedBox(height: 22),
          _kicker('инструменты'),
          const SizedBox(height: 10),
          _card(padding: 6, child: Column(children: [
            _navRow(Icons.speed, 'Спид-тест', _speedTest),
            _divider(),
            _navRow(Icons.bar_chart, 'Статистика', _showStats),
            _divider(),
            _navRow(Icons.shield, 'Проверка утечек', _leakCheck),
            _divider(),
            _navRow(Icons.upload_file, customCfg == null ? 'Свой конфиг' : 'Свой конфиг ✓', _customConfig),
          ])),
          const SizedBox(height: 22),
          _kicker('подключение'),
          const SizedBox(height: 10),
          _card(child: Column(children: [
            _radioRow('Авто', 0),
            _divider(),
            _radioRow('VLESS + Reality', 1, soon: true),
            _divider(),
            _radioRow('WireGuard', 2, soon: true),
          ])),
          const SizedBox(height: 22),
          _btn('Выйти', kind: 1, icon: Icons.logout, onTap: _logout),
          const SizedBox(height: 16),
          Center(child: Text('bitaps vpn · v1.0', style: mono(11, c: C.muted))),
        ],
      );

  Widget _navRow(IconData ic, String label, VoidCallback onTap) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Row(children: [
            Icon(ic, size: 19, color: C.accent),
            const SizedBox(width: 12),
            Text(label, style: disp(15, w: FontWeight.w500)),
            const Spacer(),
            Icon(Icons.chevron_right, size: 18, color: C.muted),
          ]),
        ),
      );

  Widget _radioRow(String label, int idx, {bool soon = false}) {
    final sel = proto == idx;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () { setState(() => proto = idx); _save(); },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          Text(label, style: disp(15, w: FontWeight.w500)),
          if (soon) ...[const SizedBox(width: 8), _badge('скоро', C.muted)],
          const Spacer(),
          Icon(sel ? Icons.radio_button_checked : Icons.radio_button_off, size: 20, color: sel ? C.accent : C.muted),
        ]),
      ),
    );
  }

  Widget _toggle(String title, String sub, bool v, ValueChanged<bool> onCh, {bool soon = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(title, style: disp(15, w: FontWeight.w600))),
              if (soon) ...[const SizedBox(width: 8), _badge('скоро', C.muted)],
            ]),
            const SizedBox(height: 2),
            Text(sub, style: mono(11)),
          ])),
          Switch(value: v, onChanged: onCh, activeColor: C.accent),
        ]),
      );

  // ---------------- GLASS CARD + SHARED ----------------
  Widget _card({required Widget child, double padding = 16, bool strong = false}) {
    final r = BorderRadius.circular(18);
    final lt = C.light;
    return Container(
      decoration: BoxDecoration(borderRadius: r,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(lt ? 0.10 : 0.44), blurRadius: lt ? 26 : 20, offset: Offset(0, lt ? 8 : 12))]),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: EdgeInsets.all(padding),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: lt
                    ? (strong ? [Colors.white, Colors.white] : [Colors.white, Colors.white.withOpacity(0.96)])
                    : (strong ? [Colors.white.withOpacity(0.13), Colors.white.withOpacity(0.05)] : [Colors.white.withOpacity(0.08), Colors.white.withOpacity(0.025)]),
                begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: r,
              border: Border.all(color: lt ? Colors.black.withOpacity(0.07) : Colors.white.withOpacity(0.14)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _gIcon(IconData ic) => Container(width: 42, height: 42, alignment: Alignment.center,
        decoration: BoxDecoration(color: C.accent.withOpacity(0.12), borderRadius: BorderRadius.circular(13),
          border: Border.all(color: C.accent.withOpacity(0.30))),
        child: Icon(ic, size: 19, color: C.accent));

  Widget _kicker(String t) => Text('// $t', style: mono(12, c: C.accent, w: FontWeight.w600));

  Widget _badge(String t, Color col) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: col.withOpacity(0.16), borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: mono(11, c: col, w: FontWeight.w600)),
      );

  Widget _shieldPill(bool on) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(color: (on ? C.ok : C.muted).withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: on ? C.ok : C.muted,
            boxShadow: on ? [BoxShadow(color: C.ok.withOpacity(0.6), blurRadius: 8)] : null)),
          const SizedBox(width: 7),
          Text(on ? 'защищено' : 'не защищено', style: mono(12, c: on ? C.ok : C.muted, w: FontWeight.w600)),
        ]),
      );

  Widget _infoTile(String val, String label) => _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(val, style: disp(22, w: FontWeight.w800, c: C.accent)),
        const SizedBox(height: 4),
        Text(label, style: mono(11)),
      ]));

  Widget _miniStat(String val, String label) => Column(children: [
        Text(val, style: disp(20, w: FontWeight.w800, c: C.accent)),
        const SizedBox(height: 2),
        Text(label, style: mono(11)),
      ]);

  Widget _ring(int days, int max) => SizedBox(
        width: 78, height: 78,
        child: Stack(alignment: Alignment.center, children: [
          SizedBox(width: 78, height: 78, child: CircularProgressIndicator(
            value: days / max, strokeWidth: 7, backgroundColor: C.line, color: C.accent)),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$days', style: disp(24, w: FontWeight.w800)),
            Text('дн.', style: mono(10)),
          ]),
        ]),
      );

  Widget _divider() => Container(height: 1, color: C.line, margin: const EdgeInsets.symmetric(vertical: 4));

  Widget _btn(String label, {int kind = 0, IconData? icon, VoidCallback? onTap}) {
    final solid = kind == 0;
    final line = kind == 1;
    return GestureDetector(
      onTap: onTap ?? () {},
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: solid ? accentGrad : null,
          color: solid ? null : (line ? Colors.transparent : Colors.white.withOpacity(0.05)),
          borderRadius: BorderRadius.circular(12),
          border: line ? Border.all(color: C.line) : null,
          boxShadow: solid ? [BoxShadow(color: C.accent.withOpacity(0.45), blurRadius: 22)] : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 17, color: solid ? C.bg : C.text), const SizedBox(width: 8)],
          Text(label, style: disp(16, w: FontWeight.w600, c: solid ? C.bg : C.text)),
        ]),
      ),
    );
  }
}
