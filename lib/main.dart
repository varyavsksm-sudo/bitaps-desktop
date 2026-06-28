import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  runApp(const BitApp());
}

// ============================ TOKENS ============================
class C {
  static const bg = Color(0xFF06040C);
  static const bg2 = Color(0xFF0C0A14);
  static const text = Color(0xFFEDF1F8);
  static const muted = Color(0xFF8A93A6);
  static const line = Color(0x14FFFFFF);
  static Color accent = const Color(0xFFFF7A1A);
  static Color accentSoft = const Color(0xFFFFB347);
  static const accent2 = Color(0xFF2D8BFF);
  static const ok = Color(0xFF39D98A);
  static const warn = Color(0xFFFFAE3D);
  static const danger = Color(0xFFFF5470);
}

LinearGradient get accentGrad =>
    LinearGradient(colors: [C.accentSoft, C.accent], begin: Alignment.topLeft, end: Alignment.bottomRight);

// Персонализация: акцентные темы (имя, основной, мягкий) + стили кнопки
const List<(String, Color, Color)> accentThemes = [
  ('Sunset', Color(0xFFFF7A1A), Color(0xFFFFB347)),
  ('Neon', Color(0xFF2DE2FF), Color(0xFF6AA8FF)),
  ('Emerald', Color(0xFF19D98A), Color(0xFF6FF0BD)),
  ('Lavender', Color(0xFFA779FF), Color(0xFFD0B3FF)),
  ('Crimson', Color(0xFFFF4D6D), Color(0xFFFF9BAD)),
];
const btnStyleNames = ['Шестерёнка', 'Кольцо', 'Орб', 'Пульс', 'Дуга'];

TextStyle disp(double s, {FontWeight w = FontWeight.w700, Color c = C.text}) =>
    TextStyle(fontFamily: 'SpaceGrotesk', fontSize: s, fontWeight: w, color: c, letterSpacing: -0.3, height: 1.15);
TextStyle mono(double s, {FontWeight w = FontWeight.w500, Color c = C.muted}) =>
    TextStyle(fontFamily: 'JetBrainsMono', fontSize: s, fontWeight: w, color: c, height: 1.2);

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

// Спидометр-дуга для стиля кнопки «Дуга»
class ArcPainter extends CustomPainter {
  final Color col;
  final double v;
  ArcPainter(this.col, this.v);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(7, 7, size.width - 14, size.height - 14);
    const start = math.pi * 0.75;
    const sweep = math.pi * 1.5;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..color = C.line;
    canvas.drawArc(rect, start, sweep, false, track);
    final fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..color = col;
    canvas.drawArc(rect, start, sweep * v.clamp(0.0, 1.0), false, fill);
  }

  @override
  bool shouldRepaint(ArcPainter old) => old.v != v || old.col != col;
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
  Timer? _timer;
  Server server = ruServers[0];
  bool tgl1 = false, tgl2 = true, tgl3 = true, tgl4 = false;
  int accentIdx = 0, btnStyle = 0, down = 0, up = 0;
  final math.Random _rnd = math.Random();

  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  late final AnimationController _wave =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat();
  late final AnimationController _twinkle =
      AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();

  @override
  void dispose() {
    _timer?.cancel();
    _spin.dispose();
    _wave.dispose();
    _twinkle.dispose();
    super.dispose();
  }

  void toggle() {
    if (conn == 1) return;
    if (conn == 0) {
      setState(() => conn = 1);
      _spin.duration = const Duration(milliseconds: 1400);
      _spin.repeat();
      Future.delayed(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        setState(() => conn = 2);
        secs = 0; down = 84; up = 13;
        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() { secs++; down = 60 + _rnd.nextInt(70); up = 8 + _rnd.nextInt(20); });
        });
      });
    } else {
      _timer?.cancel();
      _spin.duration = const Duration(seconds: 6);
      _spin.repeat();
      setState(() {
        conn = 0;
        secs = 0;
      });
    }
  }

  String get hms {
    final h = (secs ~/ 3600).toString().padLeft(2, '0');
    final m = ((secs % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (secs % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final screens = [_home(), _servers(), _account(), _settings()];
    return Scaffold(
      backgroundColor: C.bg,
      body: Stack(children: [
        const Positioned.fill(child: ColoredBox(color: C.bg)),
        Positioned.fill(child: AnimatedBuilder(
          animation: _twinkle,
          builder: (_, __) => CustomPaint(painter: StarPainter(_twinkle.value * 2 * math.pi)),
        )),
        const Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
          gradient: RadialGradient(center: Alignment(0, -0.95), radius: 0.95,
            colors: [Color(0x2BFF7A1A), Color(0x00FF7A1A)])))),
        const Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
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
        decoration: BoxDecoration(color: C.bg2.withOpacity(0.7), border: const Border(top: BorderSide(color: C.line))),
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
          style: disp(22, w: FontWeight.w700, c: connected ? C.accent : C.text))),
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
        Text('Сами подберём лучший сервер и маршрут.', style: mono(12)),
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
          const Icon(Icons.language, size: 15, color: C.muted),
          const SizedBox(width: 6),
          Text(connected ? '95.142.16.7' : 'IP скрыт', style: mono(12)),
        ])),
        const SizedBox(height: 12),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: toggle,
          child: _card(child: Row(children: [
            _gIcon(Icons.bolt),
            const SizedBox(width: 13),
            Text(connected ? 'Отключить' : 'Подключить быстрейший сервер', style: disp(15, w: FontWeight.w600)),
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
    final col = connected ? C.accent : busy ? C.accentSoft : C.muted;
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
      case 4: // дуга — спидометр
        return SizedBox(width: 222, height: 222,
          child: CustomPaint(painter: ArcPainter(col, on ? 0.85 : conn == 1 ? 0.4 : 0.05),
            child: Center(child: Stack(alignment: Alignment.center, children: [
              Container(width: 150, height: 150,
                decoration: BoxDecoration(shape: BoxShape.circle, color: C.bg2, border: Border.all(color: C.line))),
              Icon(Icons.power_settings_new, size: 56, color: col),
            ]))));
      default: // шестерёнка
        return Stack(alignment: Alignment.center, children: [
          RotationTransition(turns: _spin, child: AnimatedOpacity(
            duration: const Duration(milliseconds: 350), opacity: conn == 0 ? 0.82 : 1,
            child: Image.asset('assets/gearring.png', width: 212, height: 212, fit: BoxFit.contain))),
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
      onTap: () => setState(() => mode = i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 40, alignment: Alignment.center,
        decoration: BoxDecoration(
          color: sel ? C.accent.withOpacity(0.16) : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: sel ? C.accent : C.line),
        ),
        child: Text(label, style: disp(13, w: FontWeight.w700, c: sel ? C.accent : C.muted)),
      ),
    );
  }

  Widget _miniChip(Server s) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(20), border: Border.all(color: C.line)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(s.flag, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 6),
            Text(s.city, style: disp(12, w: FontWeight.w600)),
          ]),
        ),
      );

  Widget _accentSwatch(int i) {
    final th = accentThemes[i];
    final sel = accentIdx == i;
    return GestureDetector(
      onTap: () => setState(() {
        accentIdx = i;
        C.accent = th.$2;
        C.accentSoft = th.$3;
      }),
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        width: 44, height: 44, alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle,
          gradient: LinearGradient(colors: [th.$3, th.$2]),
          border: Border.all(color: sel ? Colors.white : Colors.transparent, width: 3),
          boxShadow: [BoxShadow(color: th.$2.withOpacity(0.5), blurRadius: sel ? 14 : 6)]),
        child: sel ? const Icon(Icons.check, size: 18, color: Colors.white) : null,
      ),
    );
  }

  Widget _styleChip(int i) {
    final sel = btnStyle == i;
    return GestureDetector(
      onTap: () => setState(() => btnStyle = i),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(color: sel ? C.accent.withOpacity(0.16) : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(11), border: Border.all(color: sel ? C.accent : C.line)),
        child: Text(btnStyleNames[i], style: disp(13, w: FontWeight.w600, c: sel ? C.accent : C.muted))),
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
          _card(strong: true, child: Row(children: [
            _gIcon(Icons.bolt),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Text('Быстрый сервер', style: disp(16, w: FontWeight.w700)),
                const SizedBox(width: 8), _badge('АВТО', C.accent)]),
              const SizedBox(height: 3),
              Text('Москва · 12 ms', style: mono(12)),
            ])),
            const Icon(Icons.chevron_right, color: C.muted),
          ])),
          const SizedBox(height: 12),
          _card(padding: 12, child: Row(children: [
            const Icon(Icons.search, size: 18, color: C.muted),
            const SizedBox(width: 10),
            Text('Поиск города или страны', style: mono(13, c: C.muted)),
          ])),
          const SizedBox(height: 22),
          _kicker('🇷🇺 Россия'),
          const SizedBox(height: 10),
          for (final s in ruServers) _serverRow(s),
          const SizedBox(height: 22),
          _kicker('🌍 Зарубежные · скоро'),
          const SizedBox(height: 10),
          for (final s in intlServers) _serverRow(s),
        ],
      );

  Widget _serverRow(Server s) {
    final sel = s.id == server.id;
    final pingCol = s.ping < 60 ? C.ok : s.ping < 120 ? C.warn : C.danger;
    return Opacity(
      opacity: s.available ? 1 : 0.55,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: s.available ? () => setState(() => server = s) : null,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.04),
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
            Text('${s.ping} ms', style: mono(13, c: pingCol, w: FontWeight.w600)),
            const SizedBox(width: 12),
            SizedBox(width: 50, child: _loadBar(s.load)),
            const SizedBox(width: 10),
            Icon(sel ? Icons.check_circle : Icons.circle_outlined, size: 20, color: sel ? C.accent : C.muted),
          ]),
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
  Widget _account() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Кабинет', style: disp(26, w: FontWeight.w800)),
          const SizedBox(height: 18),
          _card(strong: true, child: Row(children: [
            Container(width: 60, height: 60, alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, gradient: accentGrad,
                boxShadow: [BoxShadow(color: C.accent.withOpacity(0.4), blurRadius: 18)]),
              child: Text('Д', style: disp(26, w: FontWeight.w800, c: C.bg))),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Демо-режим', style: disp(20, w: FontWeight.w700)),
              const SizedBox(height: 4),
              Row(children: [_badge('Пробный', C.accent), const SizedBox(width: 6), _badge('DEMO', C.muted)]),
            ])),
          ])),
          const SizedBox(height: 14),
          _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [_gIcon(Icons.workspace_premium), const SizedBox(width: 12), _kicker('подписка')]),
            const SizedBox(height: 16),
            Row(children: [
              _ring(3, 30),
              const SizedBox(width: 20),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Пробный период', style: disp(20, w: FontWeight.w700, c: C.accent)),
                const SizedBox(height: 6),
                Row(children: [const Icon(Icons.event, size: 14, color: C.muted), const SizedBox(width: 6), Text('осталось 3 дня', style: mono(13))]),
                const SizedBox(height: 4),
                Row(children: [const Icon(Icons.devices, size: 14, color: C.muted), const SizedBox(width: 6), Text('2 / 10 устройств', style: mono(13))]),
              ])),
            ]),
            const SizedBox(height: 16),
            _btn('Продлить подписку', kind: 0, icon: Icons.bolt),
          ])),
          const SizedBox(height: 14),
          _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [_gIcon(Icons.qr_code_2), const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _kicker('ключ доступа'), const SizedBox(height: 3), Text('для роутера и ручной настройки', style: mono(11))]))]),
            const SizedBox(height: 12),
            Container(padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.35), borderRadius: BorderRadius.circular(10)),
              child: Text('vless://3a7c9f1e…3e2f@msk.bitaps.app:443?security=reality#bitaps-РФ',
                style: mono(11, c: C.text), maxLines: 2, overflow: TextOverflow.ellipsis)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _btn('Скопировать', kind: 1, icon: Icons.copy)),
              const SizedBox(width: 12),
              Expanded(child: _btn('Обновить', kind: 2, icon: Icons.refresh)),
            ]),
          ])),
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
            _btn('Поделиться ссылкой', kind: 1, icon: Icons.share),
          ])),
          const SizedBox(height: 14),
          _card(strong: true, child: Row(children: [
            _gIcon(Icons.router),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('B-box — VPN для всего дома', style: disp(16, w: FontWeight.w600)),
              const SizedBox(height: 3),
              Text('коробочка · 15 000 ₽', style: mono(12, c: C.accent)),
            ])),
            const Icon(Icons.chevron_right, color: C.muted),
          ])),
          const SizedBox(height: 14),
          _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [_gIcon(Icons.forum), const SizedBox(width: 12), _kicker('поддержка')]),
            const SizedBox(height: 12),
            Container(height: 80, padding: const EdgeInsets.all(12), alignment: Alignment.topLeft,
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.35), borderRadius: BorderRadius.circular(10)),
              child: Text('Опиши проблему…', style: mono(13, c: C.muted))),
            const SizedBox(height: 12),
            _btn('Отправить', kind: 0, icon: Icons.send),
            const SizedBox(height: 10),
            Center(child: Text('или напиши @bitapssupport', style: mono(12, c: C.accent))),
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
            _toggle('Блокировка входа', 'Спрашивать Face ID / код при открытии', tgl1, (v) => setState(() => tgl1 = v)),
            _divider(),
            _toggle('Обрыв соединения', 'Уведомлять, если VPN отвалился', tgl2, (v) => setState(() => tgl2 = v)),
            _divider(),
            _toggle('Подписка истекает', 'Напомнить за пару дней', tgl3, (v) => setState(() => tgl3 = v)),
            _divider(),
            _toggle('Лимит трафика', 'Сигнал при большом расходе', tgl4, (v) => setState(() => tgl4 = v)),
          ])),
          const SizedBox(height: 22),
          _kicker('инструменты'),
          const SizedBox(height: 10),
          _card(padding: 6, child: Column(children: [
            _navRow(Icons.speed, 'Спид-тест'),
            _divider(),
            _navRow(Icons.bar_chart, 'Статистика'),
            _divider(),
            _navRow(Icons.shield, 'Проверка утечек'),
            _divider(),
            _navRow(Icons.upload_file, 'Свой конфиг'),
          ])),
          const SizedBox(height: 22),
          _kicker('подключение'),
          const SizedBox(height: 10),
          _card(child: Column(children: [
            _radioRow('Авто', true),
            _divider(),
            _radioRow('VLESS + Reality', false),
            _divider(),
            _radioRow('WireGuard', false),
          ])),
          const SizedBox(height: 22),
          _btn('Выйти', kind: 1, icon: Icons.logout),
          const SizedBox(height: 16),
          Center(child: Text('bitaps vpn · v1.0', style: mono(11, c: C.muted))),
        ],
      );

  Widget _navRow(IconData ic, String label) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(children: [
          Icon(ic, size: 19, color: C.accent),
          const SizedBox(width: 12),
          Text(label, style: disp(15, w: FontWeight.w500)),
          const Spacer(),
          const Icon(Icons.chevron_right, size: 18, color: C.muted),
        ]),
      );

  Widget _radioRow(String label, bool sel) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          Text(label, style: disp(15, w: FontWeight.w500)),
          const Spacer(),
          Icon(sel ? Icons.radio_button_checked : Icons.radio_button_off, size: 20, color: sel ? C.accent : C.muted),
        ]),
      );

  Widget _toggle(String title, String sub, bool v, ValueChanged<bool> onCh) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: disp(15, w: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(sub, style: mono(11)),
          ])),
          Switch(value: v, onChanged: onCh, activeColor: C.accent),
        ]),
      );

  // ---------------- GLASS CARD + SHARED ----------------
  Widget _card({required Widget child, double padding = 16, bool strong = false}) {
    final r = BorderRadius.circular(18);
    return Container(
      decoration: BoxDecoration(borderRadius: r,
        boxShadow: const [BoxShadow(color: Color(0x70000000), blurRadius: 20, offset: Offset(0, 12))]),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: EdgeInsets.all(padding),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: strong
                    ? [Colors.white.withOpacity(0.13), Colors.white.withOpacity(0.05)]
                    : [Colors.white.withOpacity(0.08), Colors.white.withOpacity(0.025)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: r,
              border: Border.all(color: Colors.white.withOpacity(0.14)),
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

  Widget _btn(String label, {int kind = 0, IconData? icon}) {
    final solid = kind == 0;
    final line = kind == 1;
    return GestureDetector(
      onTap: () {},
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
