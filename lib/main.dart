import 'dart:async';
import 'package:flutter/material.dart';

void main() => runApp(const BitApp());

// ============================ DESIGN TOKENS ============================
class C {
  static const bg = Color(0xFF06040C);
  static const bg2 = Color(0xFF0C0A14);
  static const card = Color(0xFF131120);
  static const cardHi = Color(0xFF1B1830);
  static const text = Color(0xFFE8EDF5);
  static const muted = Color(0xFF8A96AB);
  static const line = Color(0x16FFFFFF);
  static const accent = Color(0xFFFF7A1A);
  static const accentSoft = Color(0xFFFFAE3D);
  static const ok = Color(0xFF39D98A);
  static const warn = Color(0xFFFFAE3D);
  static const danger = Color(0xFFFF5470);
  static const accent2 = Color(0xFF2D8BFF);
}

const LinearGradient accentGrad = LinearGradient(
  colors: [C.accentSoft, C.accent],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

const List<List<Color>> chipGrads = [
  [Color(0xFFFF9D3D), Color(0xFFFF6A00)],
  [Color(0xFF9B7BFF), Color(0xFF6A4BFF)],
  [Color(0xFF3AD6C0), Color(0xFF14A890)],
  [Color(0xFFFF5D8F), Color(0xFFFF2D6D)],
  [Color(0xFF59B4FF), Color(0xFF2D7BFF)],
];

TextStyle disp(double s, {FontWeight w = FontWeight.w700, Color c = C.text}) =>
    TextStyle(fontSize: s, fontWeight: w, color: c, letterSpacing: -0.3, height: 1.15);
TextStyle mono(double s, {FontWeight w = FontWeight.w500, Color c = C.muted}) =>
    TextStyle(fontSize: s, fontWeight: w, color: c, fontFamily: 'monospace', height: 1.2);

// ============================ MODELS / MOCK DATA ============================
class Server {
  final String id, city, country, flag, proto;
  final int ping, load;
  final bool premium, available;
  const Server(this.id, this.city, this.country, this.flag, this.ping, this.load,
      {this.premium = false, this.available = true, this.proto = 'VLESS + Reality'});
}

const ruServers = [
  Server('ru-msk', 'Москва', 'Россия', '🇷🇺', 12, 34),
  Server('ru-spb', 'Санкт-Петербург', 'Россия', '🇷🇺', 21, 41),
];
const intlServers = [
  Server('nl-ams', 'Амстердам', 'Нидерланды', '🇳🇱', 48, 22, premium: true, available: false),
  Server('de-fra', 'Франкфурт', 'Германия', '🇩🇪', 52, 18, premium: true, available: false),
  Server('fi-hel', 'Хельсинки', 'Финляндия', '🇫🇮', 45, 27, premium: true, available: false),
  Server('tr-ist', 'Стамбул', 'Турция', '🇹🇷', 63, 31, premium: true, available: false),
];

class Plan {
  final String title;
  final int months, total, perMonth;
  final bool best;
  const Plan(this.title, this.months, this.total, this.perMonth, {this.best = false});
}

const plans = [
  Plan('1 месяц', 1, 399, 399),
  Plan('3 месяца', 3, 999, 333),
  Plan('6 месяцев', 6, 1790, 298),
  Plan('12 месяцев', 12, 2990, 249, best: true),
];

class Faq {
  final String q, a;
  const Faq(this.q, this.a);
}

const faqs = [
  Faq('Сколько устройств можно подключить?', 'До 10 устройств одновременно по одной подписке.'),
  Faq('Вы ведёте логи?', 'Нет. Мы не храним логи вашей активности — только техническую информацию для работы сервиса.'),
  Faq('Как продлить подписку?', 'В разделе «Кабинет» нажми «Продлить» — оплата через Telegram, СБП или крипту.'),
  Faq('VPN не подключается — что делать?', 'Смени локацию или протокол на «Авто», проверь интернет. Если не помогло — напиши в поддержку.'),
];

const modes = [
  ('Авто', Icons.bolt),
  ('Стриминг', Icons.play_circle_fill),
  ('Игры', Icons.sports_esports),
  ('Приватность', Icons.lock),
  ('Работа', Icons.work),
];

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
        fontFamily: null,
      ),
      home: const Shell(),
    );
  }
}

// ============================ SHELL (sidebar nav) ============================
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int tab = 0;
  int conn = 0; // 0 disconnected, 1 connecting, 2 connected
  int secs = 0;
  int mode = 0;
  Timer? _timer;
  Server server = ruServers[0];

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

  String get timeStr {
    final m = (secs ~/ 60).toString().padLeft(2, '0');
    final s = (secs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final screens = [_home(), _servers(), _account(), _settings()];
    return Scaffold(
      body: Row(
        children: [
          _sidebar(),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -1.1),
                  radius: 1.4,
                  colors: [Color(0x22FF7A1A), C.bg],
                  stops: [0, 0.7],
                ),
              ),
              child: SafeArea(child: screens[tab]),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- SIDEBAR ----------------
  Widget _sidebar() {
    final items = [
      ('Главная', Icons.bolt),
      ('Серверы', Icons.public),
      ('Кабинет', Icons.person),
      ('Настройки', Icons.settings),
    ];
    return Container(
      width: 210,
      color: C.bg2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 26, 20, 26),
            child: Row(children: [
              const Text('₿', style: TextStyle(color: C.accent, fontSize: 26, fontWeight: FontWeight.w900)),
              const SizedBox(width: 8),
              Text('bitaps', style: disp(20, w: FontWeight.w800)),
              const SizedBox(width: 4),
              Text('VPN', style: disp(20, w: FontWeight.w800, c: C.accent)),
            ]),
          ),
          for (int i = 0; i < items.length; i++) _navItem(items[i].$1, items[i].$2, i),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(
                shape: BoxShape.circle, color: conn == 2 ? C.ok : C.muted)),
              const SizedBox(width: 8),
              Text(conn == 2 ? 'защищено' : 'не защищено', style: mono(12, c: conn == 2 ? C.ok : C.muted)),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _navItem(String label, IconData ic, int i) {
    final sel = tab == i;
    return InkWell(
      onTap: () => setState(() => tab = i),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: sel ? C.accent.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: sel ? C.accent.withOpacity(0.30) : Colors.transparent),
        ),
        child: Row(children: [
          Icon(ic, size: 20, color: sel ? C.accent : C.muted),
          const SizedBox(width: 12),
          Text(label, style: disp(15, w: FontWeight.w600, c: sel ? C.text : C.muted)),
        ]),
      ),
    );
  }

  // ---------------- HOME ----------------
  Widget _home() {
    final connected = conn == 2;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(children: [
          Text('Главная', style: disp(26, w: FontWeight.w800)),
          const Spacer(),
          _pill('🛡 7дн.', C.accent),
          const SizedBox(width: 8),
          _shieldPill(connected),
        ]),
        const SizedBox(height: 28),
        Center(child: _powerButton()),
        const SizedBox(height: 18),
        Center(child: Text(
          conn == 0 ? 'Отключено' : conn == 1 ? 'Подключение…' : 'Подключено',
          style: disp(22, w: FontWeight.w700, c: connected ? C.accent : C.text))),
        const SizedBox(height: 4),
        Center(child: Text(connected ? timeStr : 'нажми, чтобы подключиться',
            style: mono(connected ? 26 : 13, c: connected ? C.accentSoft : C.muted))),
        const SizedBox(height: 24),
        SizedBox(height: 40, child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (int i = 0; i < modes.length; i++) _modeChip(modes[i].$1, modes[i].$2, i),
          ],
        )),
        const SizedBox(height: 18),
        _bitCard(child: Row(children: [
          Container(width: 44, height: 44, alignment: Alignment.center,
            decoration: BoxDecoration(color: C.cardHi, borderRadius: BorderRadius.circular(13)),
            child: Text(server.flag, style: const TextStyle(fontSize: 22))),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(server.city, style: disp(16, w: FontWeight.w600)),
            const SizedBox(height: 3),
            Text('${server.ping} ms · быстрый узел', style: mono(12)),
          ])),
          _badge(server.proto, C.accent),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, color: C.muted),
        ])),
        const SizedBox(height: 14),
        _bitCard(child: Row(children: [
          _stat('↓', connected ? '84.2' : '—', 'Мбит/с'),
          const SizedBox(width: 20),
          _stat('↑', connected ? '12.7' : '—', 'Мбит/с'),
          const Spacer(),
          const Icon(Icons.language, size: 16, color: C.muted),
          const SizedBox(width: 6),
          Text(connected ? '185.244.214.10' : 'скрыт', style: mono(12)),
        ])),
        const SizedBox(height: 14),
        _bitCard(child: Row(children: [
          _gIcon(Icons.shield_outlined, 0),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Проверить защиту', style: disp(16, w: FontWeight.w600)),
            const SizedBox(height: 3),
            Text('Мой IP · DNS / WebRTC утечки', style: mono(12)),
          ])),
          const Icon(Icons.chevron_right, color: C.muted),
        ])),
        const SizedBox(height: 24),
        Center(child: Text('демо-режим · реальный коннект — с запуском сети bitaps',
            style: mono(11, c: C.muted), textAlign: TextAlign.center)),
      ],
    );
  }

  Widget _powerButton() {
    final connected = conn == 2;
    final busy = conn == 1;
    final col = connected ? C.accent : busy ? C.accentSoft : C.muted;
    return GestureDetector(
      onTap: toggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        width: 200, height: 200,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: connected ? C.accent.withOpacity(0.14) : C.card,
          border: Border.all(color: col.withOpacity(connected ? 1 : 0.45), width: 4),
          boxShadow: connected
              ? [BoxShadow(color: C.accent.withOpacity(0.45), blurRadius: 48, spreadRadius: 6)]
              : null,
        ),
        child: Icon(Icons.power_settings_new, size: 76, color: col),
      ),
    );
  }

  Widget _modeChip(String label, IconData ic, int i) {
    final sel = mode == i;
    return GestureDetector(
      onTap: () => setState(() => mode = i),
      child: Container(
        margin: const EdgeInsets.only(right: 9),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: sel ? C.accent.withOpacity(0.14) : C.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: sel ? C.accent.withOpacity(0.4) : C.line),
        ),
        child: Row(children: [
          Icon(ic, size: 15, color: sel ? C.accent : C.muted),
          const SizedBox(width: 6),
          Text(label, style: disp(13, w: FontWeight.w600, c: sel ? C.text : C.muted)),
        ]),
      ),
    );
  }

  // ---------------- SERVERS ----------------
  Widget _servers() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Серверы', style: disp(26, w: FontWeight.w800)),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: _infoTile('32', 'серверов онлайн')),
          const SizedBox(width: 12),
          Expanded(child: _infoTile('12', 'локаций')),
          const SizedBox(width: 12),
          Expanded(child: _infoTile('99.9%', 'аптайм')),
        ]),
        const SizedBox(height: 18),
        _bitCard(strong: true, child: Row(children: [
          _gIcon(Icons.bolt, 0),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('Быстрый сервер', style: disp(16, w: FontWeight.w600)),
              const SizedBox(width: 8),
              _badge('АВТО', C.accent),
            ]),
            const SizedBox(height: 3),
            Text('Москва · 12 ms', style: mono(12)),
          ])),
          const Icon(Icons.chevron_right, color: C.muted),
        ])),
        const SizedBox(height: 14),
        _bitCard(padding: 12, child: Row(children: [
          const Icon(Icons.search, size: 18, color: C.muted),
          const SizedBox(width: 10),
          Expanded(child: Text('Поиск города или страны', style: mono(13, c: C.muted))),
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
        onTap: s.available ? () => setState(() => server = s) : null,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: C.card,
            borderRadius: BorderRadius.circular(14),
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
            SizedBox(width: 60, child: _loadBar(s.load)),
            const SizedBox(width: 10),
            Icon(sel ? Icons.check_circle : Icons.circle_outlined,
                size: 20, color: sel ? C.accent : C.muted),
          ]),
        ),
      ),
    );
  }

  Widget _loadBar(int pct) {
    final col = pct < 50 ? C.ok : pct < 80 ? C.warn : C.danger;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(value: pct / 100, minHeight: 4,
            backgroundColor: C.cardHi, color: col),
      ),
      const SizedBox(height: 3),
      Text('$pct%', style: mono(10)),
    ]);
  }

  // ---------------- ACCOUNT ----------------
  Widget _account() {
    return ListView(
      padding: const EdgeInsets.all(24),
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
              Row(children: [const Icon(Icons.event, size: 14, color: C.muted), const SizedBox(width: 6),
                Text('осталось 3 дня', style: mono(13))]),
              const SizedBox(height: 4),
              Row(children: [const Icon(Icons.devices, size: 14, color: C.muted), const SizedBox(width: 6),
                Text('2 / 10 устройств', style: mono(13))]),
            ])),
          ]),
          const SizedBox(height: 16),
          _btn('Продлить подписку', kind: 0, icon: Icons.bolt),
        ])),
        const SizedBox(height: 14),
        _bitCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [_gIcon(Icons.qr_code_2, 4), const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _kicker('ключ доступа'),
              const SizedBox(height: 3),
              Text('для роутера и ручной настройки', style: mono(11)),
            ]))]),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(10)),
            child: Text('vless://3a7c9f1e…3e2f@msk.bitaps.app:443?security=reality#bitaps-РФ',
                style: mono(11, c: C.text), maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
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
              _kicker('пригласи друзей'),
              const SizedBox(height: 3),
              Text('Приглашай — получай бонусные дни', style: mono(11)),
            ]))]),
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
          Container(
            height: 84,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(10)),
            alignment: Alignment.topLeft,
            child: Text('Опиши проблему…', style: mono(13, c: C.muted)),
          ),
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
        const SizedBox(height: 20),
        Center(child: Text('bitaps vpn · v1.0', style: mono(11, c: C.muted))),
      ],
    );
  }

  Widget _faqRow(Faq f) {
    return Theme(
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
  }

  // ---------------- SETTINGS ----------------
  bool tgl1 = false, tgl2 = true, tgl3 = true, tgl4 = false;
  Widget _settings() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Настройки', style: disp(26, w: FontWeight.w800)),
        const SizedBox(height: 20),
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
          Icon(sel ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 20, color: sel ? C.accent : C.muted),
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

  // ---------------- SHARED WIDGETS ----------------
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
        color: g[1].withOpacity(0.14),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: g[0].withOpacity(0.35)),
      ),
      child: Icon(ic, size: 19, color: g[0]));
  }

  Widget _kicker(String t) => Text('// $t', style: mono(12, c: C.accent, w: FontWeight.w600));

  Widget _badge(String t, Color col) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: col.withOpacity(0.14), borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: mono(11, c: col, w: FontWeight.w600)),
      );

  Widget _pill(String t, Color col) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: C.card, borderRadius: BorderRadius.circular(20),
          border: Border.all(color: col.withOpacity(0.30)),
        ),
        child: Text(t, style: mono(12, c: col, w: FontWeight.w600)),
      );

  Widget _shieldPill(bool on) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: (on ? C.ok : C.muted).withOpacity(0.12), borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: on ? C.ok : C.muted)),
          const SizedBox(width: 7),
          Text(on ? 'защищено' : 'не защищено', style: mono(12, c: on ? C.ok : C.muted, w: FontWeight.w600)),
        ]),
      );

  Widget _stat(String arrow, String val, String unit) => Row(mainAxisSize: MainAxisSize.min, children: [
        Text(arrow, style: disp(18, w: FontWeight.w700, c: C.accent)),
        const SizedBox(width: 6),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(val, style: mono(15, c: C.text, w: FontWeight.w600)),
          Text(unit, style: mono(10)),
        ]),
      ]);

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
