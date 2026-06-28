import 'dart:async';
import 'package:flutter/material.dart';

void main() => runApp(const BitApp());

// ============================ DESIGN TOKENS ============================
class C {
  static const bg = Color(0xFF06040C);
  static const bg2 = Color(0xFF0A0810);
  static const card = Color(0xFF12101C);
  static const cardHi = Color(0xFF1A1728);
  static const text = Color(0xFFEDF1F8);
  static const muted = Color(0xFF8A93A6);
  static const line = Color(0x14FFFFFF);
  static const accent = Color(0xFFFF7A1A);
  static const accentSoft = Color(0xFFFFB347);
  static const ok = Color(0xFF39D98A);
  static const warn = Color(0xFFFFAE3D);
  static const danger = Color(0xFFFF5470);
}

const LinearGradient accentGrad = LinearGradient(
  colors: [C.accentSoft, C.accent], begin: Alignment.topLeft, end: Alignment.bottomRight);

const List<List<Color>> chipGrads = [
  [Color(0xFFFF9D3D), Color(0xFFFF6A00)],
  [Color(0xFF9B7BFF), Color(0xFF6A4BFF)],
  [Color(0xFF3AD6C0), Color(0xFF14A890)],
  [Color(0xFFFF5D8F), Color(0xFFFF2D6D)],
  [Color(0xFF59B4FF), Color(0xFF2D7BFF)],
];

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
        colorScheme: const ColorScheme.dark(primary: C.accent, surface: C.card),
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

class _ShellState extends State<Shell> {
  int tab = 0;
  int conn = 0; // 0 off, 1 connecting, 2 on
  int secs = 0;
  int mode = 0;
  Timer? _timer;
  Server server = ruServers[0];
  bool tgl1 = false, tgl2 = true, tgl3 = true, tgl4 = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void toggle() {
    if (conn == 1) return;
    if (conn == 0) {
      setState(() => conn = 1);
      Future.delayed(const Duration(milliseconds: 800), () {
        if (!mounted) return;
        setState(() => conn = 2);
        secs = 0;
        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() => secs++);
        });
      });
    } else {
      _timer?.cancel();
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.72), radius: 1.05,
            colors: [Color(0x3AFF7A1A), C.bg], stops: [0, 0.55],
          ),
        ),
        child: SafeArea(bottom: false, child: Center(
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: screens[tab]),
        )),
      ),
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
    return Container(
      decoration: const BoxDecoration(color: C.bg2, border: Border(top: BorderSide(color: C.line))),
      child: SafeArea(top: false, child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          for (int i = 0; i < 4; i++) _tabItem(items[i].$1, items[i].$2, i),
        ]),
      )),
    );
  }

  Widget _tabItem(String label, IconData ic, int i) {
    final sel = tab == i;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => tab = i),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(ic, size: 22, color: sel ? C.accent : C.muted),
          const SizedBox(height: 4),
          Text(label, style: mono(11, c: sel ? C.accent : C.muted, w: FontWeight.w600)),
        ]),
      ),
    );
  }

  // ---------------- HOME ----------------
  Widget _home() {
    final connected = conn == 2;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Row(children: [_logo(), const Spacer(), _shieldPill(connected)]),
        const SizedBox(height: 16),
        Center(child: _gearButton()),
        const SizedBox(height: 8),
        Center(child: Text(
          conn == 0 ? 'Отключено' : conn == 1 ? 'Подключение…' : 'Подключено',
          style: disp(22, w: FontWeight.w700, c: connected ? C.accent : C.text))),
        const SizedBox(height: 6),
        Center(child: Text(connected ? hms : '00:00:00',
          style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 40, fontWeight: FontWeight.w700,
            color: connected ? C.accentSoft : C.muted, letterSpacing: 2))),
        const SizedBox(height: 4),
        Center(child: Text(connected ? 'под защитой' : 'нажми на кнопку', style: mono(12))),
        const SizedBox(height: 22),
        Row(children: [
          for (int i = 0; i < 4; i++)
            Expanded(child: Padding(
              padding: EdgeInsets.only(right: i < 3 ? 8 : 0),
              child: _modeChip(modeLabels[i], i))),
        ]),
        const SizedBox(height: 10),
        Text('Сами подберём лучший сервер и маршрут.', style: mono(12)),
        const SizedBox(height: 16),
        _bitCard(child: Row(children: [
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
              const Icon(Icons.swap_horiz, size: 17, color: C.accent),
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
            children: [for (final s in [ruServers[1], ruServers[2], ...intlServers]) _miniChip(s)],
          ))),
        ]),
        const SizedBox(height: 12),
        _bitCard(padding: 13, child: Row(children: [
          Text('↓', style: disp(15, c: C.muted)),
          const SizedBox(width: 5),
          Text(connected ? '84' : '—', style: mono(13, c: C.text, w: FontWeight.w600)),
          const SizedBox(width: 16),
          Text('↑', style: disp(15, c: C.muted)),
          const SizedBox(width: 5),
          Text(connected ? '13' : '—', style: mono(13, c: C.text, w: FontWeight.w600)),
          const Spacer(),
          const Icon(Icons.language, size: 15, color: C.muted),
          const SizedBox(width: 6),
          Text(connected ? '95.142.16.7' : 'IP скрыт', style: mono(12)),
        ])),
        const SizedBox(height: 12),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: toggle,
          child: _bitCard(child: Row(children: [
            _gIcon(Icons.bolt, 0),
            const SizedBox(width: 13),
            Text(connected ? 'Отключить' : 'Подключить быстрейший сервер',
                style: disp(15, w: FontWeight.w600)),
          ])),
        ),
      ],
    );
  }

  Widget _logo() => Row(children: [
        Container(width: 30, height: 30, alignment: Alignment.center,
          decoration: BoxDecoration(gradient: accentGrad, borderRadius: BorderRadius.circular(9)),
          child: Text('₿', style: disp(17, w: FontWeight.w900, c: C.bg))),
        const SizedBox(width: 9),
        Text('bit', style: disp(22, w: FontWeight.w800)),
        Text('aps', style: disp(22, w: FontWeight.w800, c: C.accent)),
      ]);

  Widget _gearButton() => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: toggle,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 250),
          scale: conn == 2 ? 1.0 : 0.94,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            opacity: conn == 0 ? 0.8 : 1,
            child: Image.asset('assets/gear.png', width: 232, height: 232, fit: BoxFit.contain),
          ),
        ),
      );

  Widget _modeChip(String label, int i) {
    final sel = mode == i;
    return GestureDetector(
      onTap: () => setState(() => mode = i),
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: sel ? C.accent.withOpacity(0.14) : C.card,
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
          decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: C.line)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(s.flag, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 6),
            Text(s.city, style: disp(12, w: FontWeight.w600)),
          ]),
        ),
      );

  // ---------------- SERVERS ----------------
  Widget _servers() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Серверы', style: disp(26, w: FontWeight.w800)),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: _infoTile('32', 'серверов онлайн')),
          const SizedBox(width: 12),
          Expanded(child: _infoTile('12', 'локаций')),
          const SizedBox(width: 12),
          Expanded(child: _infoTile('99.9%', 'аптайм')),
        ]),
        const SizedBox(height: 16),
        _bitCard(strong: true, child: Row(children: [
          _gIcon(Icons.bolt, 0),
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
        _bitCard(padding: 12, child: Row(children: [
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
  }

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
          decoration: BoxDecoration(
            color: C.card, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: sel ? C.accent.withOpacity(0.5) : C.line),
          ),
          child: Row(children: [
            Container(width: 40, height: 40, alignment: Alignment.center,
              decoration: BoxDecoration(color: C.cardHi, borderRadius: BorderRadius.circular(12)),
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
            SizedBox(width: 56, child: _loadBar(s.load)),
            const SizedBox(width: 10),
            Icon(sel ? Icons.check_circle : Icons.circle_outlined, size: 20, color: sel ? C.accent : C.muted),
          ]),
        ),
      ),
    );
  }

  Widget _loadBar(int pct) {
    final col = pct < 50 ? C.ok : pct < 80 ? C.warn : C.danger;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(value: pct / 100, minHeight: 4, backgroundColor: C.cardHi, color: col)),
      const SizedBox(height: 3),
      Text('$pct%', style: mono(10)),
    ]);
  }

  // ---------------- ACCOUNT ----------------
  Widget _account() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Кабинет', style: disp(26, w: FontWeight.w800)),
        const SizedBox(height: 18),
        _bitCard(strong: true, child: Row(children: [
          Container(width: 60, height: 60, alignment: Alignment.center,
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: accentGrad),
            child: Text('Д', style: disp(26, w: FontWeight.w800, c: C.bg))),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Демо-режим', style: disp(20, w: FontWeight.w700)),
            const SizedBox(height: 4),
            Row(children: [_badge('Пробный', C.accent), const SizedBox(width: 6), _badge('DEMO', C.muted)]),
          ])),
        ])),
        const SizedBox(height: 14),
        _bitCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [_gIcon(Icons.workspace_premium, 1), const SizedBox(width: 12), _kicker('подписка')]),
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
        _bitCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [_gIcon(Icons.qr_code_2, 4), const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _kicker('ключ доступа'), const SizedBox(height: 3), Text('для роутера и ручной настройки', style: mono(11))]))]),
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(10)),
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
        _bitCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [_gIcon(Icons.card_giftcard, 3), const SizedBox(width: 12),
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
        _bitCard(strong: true, child: Row(children: [
          _gIcon(Icons.router, 0),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('B-box — VPN для всего дома', style: disp(16, w: FontWeight.w600)),
            const SizedBox(height: 3),
            Text('коробочка · 15 000 ₽', style: mono(12, c: C.accent)),
          ])),
          const Icon(Icons.chevron_right, color: C.muted),
        ])),
        const SizedBox(height: 14),
        _bitCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [_gIcon(Icons.forum, 2), const SizedBox(width: 12), _kicker('поддержка')]),
          const SizedBox(height: 12),
          Container(height: 80, padding: const EdgeInsets.all(12), alignment: Alignment.topLeft,
            decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(10)),
            child: Text('Опиши проблему…', style: mono(13, c: C.muted))),
          const SizedBox(height: 12),
          _btn('Отправить', kind: 0, icon: Icons.send),
          const SizedBox(height: 10),
          Center(child: Text('или напиши @bitapssupport', style: mono(12, c: C.accent))),
        ])),
        const SizedBox(height: 14),
        _bitCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [_gIcon(Icons.help, 0), const SizedBox(width: 12), _kicker('частые вопросы')]),
          const SizedBox(height: 8),
          for (final f in faqs) _faqRow(f),
        ])),
        const SizedBox(height: 18),
        Center(child: Text('bitaps vpn · v1.0', style: mono(11, c: C.muted))),
      ],
    );
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
  Widget _settings() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Настройки', style: disp(26, w: FontWeight.w800)),
        const SizedBox(height: 18),
        _kicker('безопасность'),
        const SizedBox(height: 10),
        _bitCard(child: Column(children: [
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
        _bitCard(padding: 6, child: Column(children: [
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
        _bitCard(child: Column(children: [
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
  }

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

  // ---------------- SHARED ----------------
  Widget _bitCard({required Widget child, double padding = 16, bool strong = false}) => Container(
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(
          color: strong ? C.cardHi : C.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: C.line),
          boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 18, offset: Offset(0, 10))],
        ),
        child: child,
      );

  Widget _gIcon(IconData ic, int idx) {
    final g = chipGrads[idx % chipGrads.length];
    return Container(width: 42, height: 42, alignment: Alignment.center,
      decoration: BoxDecoration(
        color: g[1].withOpacity(0.14), borderRadius: BorderRadius.circular(13),
        border: Border.all(color: g[0].withOpacity(0.35))),
      child: Icon(ic, size: 19, color: g[0]));
  }

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
          Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: on ? C.ok : C.muted)),
          const SizedBox(width: 7),
          Text(on ? 'защищено' : 'не защищено', style: mono(12, c: on ? C.ok : C.muted, w: FontWeight.w600)),
        ]),
      );

  Widget _infoTile(String val, String label) => _bitCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
            value: days / max, strokeWidth: 7, backgroundColor: C.cardHi, color: C.accent)),
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
          color: solid ? null : (line ? Colors.transparent : C.cardHi),
          borderRadius: BorderRadius.circular(12),
          border: line ? Border.all(color: C.line) : null,
          boxShadow: solid ? [BoxShadow(color: C.accent.withOpacity(0.4), blurRadius: 20)] : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 17, color: solid ? C.bg : C.text), const SizedBox(width: 8)],
          Text(label, style: disp(16, w: FontWeight.w600, c: solid ? C.bg : C.text)),
        ]),
      ),
    );
  }
}
