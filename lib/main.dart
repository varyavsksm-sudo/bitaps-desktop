import 'package:flutter/material.dart';

void main() => runApp(const BitapsApp());

const _navy = Color(0xFF0A1322);
const _card = Color(0xFF11203A);
const _accent = Color(0xFFF5A524);
const _muted = Color(0xFF8AA0C0);

class BitapsApp extends StatelessWidget {
  const BitapsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'bitaps VPN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _navy,
        colorScheme: const ColorScheme.dark(primary: _accent, surface: _card),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _connected = false;
  bool _busy = false;
  final TextEditingController _keyCtrl = TextEditingController();
  final String _server = 'Москва · RU';

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() => _busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() {
      _connected = !_connected;
      _busy = false;
    });
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(),
                  const SizedBox(height: 28),
                  _powerButton(),
                  const SizedBox(height: 18),
                  _status(),
                  const SizedBox(height: 28),
                  _keySection(),
                  const SizedBox(height: 16),
                  _demoBanner(),
                  const SizedBox(height: 18),
                  _footer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() => const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('₿',
              style: TextStyle(
                  color: _accent, fontSize: 30, fontWeight: FontWeight.w900)),
          SizedBox(width: 8),
          Text('bitaps',
              style: TextStyle(
                  color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
          SizedBox(width: 6),
          Text('VPN',
              style: TextStyle(
                  color: _accent, fontSize: 26, fontWeight: FontWeight.w800)),
        ],
      );

  Widget _powerButton() => Center(
        child: GestureDetector(
          onTap: _toggle,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 170,
            height: 170,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _connected ? _accent.withOpacity(0.18) : _card,
              border: Border.all(
                  color: _connected ? _accent : _muted.withOpacity(0.4),
                  width: 3),
              boxShadow: _connected
                  ? [
                      BoxShadow(
                          color: _accent.withOpacity(0.35),
                          blurRadius: 40,
                          spreadRadius: 4)
                    ]
                  : null,
            ),
            child: Icon(Icons.power_settings_new,
                size: 64, color: _connected ? _accent : _muted),
          ),
        ),
      );

  Widget _status() => Column(
        children: [
          Text(
            _busy ? 'Подключаюсь…' : (_connected ? 'Подключено' : 'Отключено'),
            textAlign: TextAlign.center,
            style: TextStyle(
                color: _connected ? _accent : Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            _connected ? '$_server · демо' : 'нажми, чтобы подключиться',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 13),
          ),
        ],
      );

  Widget _keySection() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: _card, borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('🔑 Ключ доступа',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('вставь ключ из бота @bitaps_vpn_auth_bot',
                style: TextStyle(color: _muted, fontSize: 12)),
            const SizedBox(height: 10),
            TextField(
              controller: _keyCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                hintText: 'vless://…',
                hintStyle: const TextStyle(color: _muted),
                filled: true,
                fillColor: _navy,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ],
        ),
      );

  Widget _demoBanner() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: _accent.withOpacity(0.10),
            borderRadius: BorderRadius.circular(10)),
        child: const Text(
          'Демо-режим: реальное подключение включится с запуском сети bitaps.',
          style: TextStyle(color: _accent, fontSize: 12),
        ),
      );

  Widget _footer() => const Column(
        children: [
          SelectableText('bitapsvpn.com',
              style: TextStyle(color: _muted, fontSize: 12)),
          SizedBox(height: 2),
          SelectableText('@bitaps_vpn_auth_bot',
              style: TextStyle(color: _muted, fontSize: 12)),
        ],
      );
}
