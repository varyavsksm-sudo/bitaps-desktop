part of '../main.dart';

// ============================ SETTINGS ============================
extension ShellSettings on _ShellState {
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

  void _showStats() {
    _dialog('Статистика',
        'Сессий запущено: $sessions\nТекущая сессия: ${conn == 2 ? hms : "не подключено"}\nСервер: ${server.city}\nРежим: ${modeLabels[mode]}\nИзбранных серверов: ${favs.length}');
  }

  void _customConfig() {
    final ctrl = TextEditingController(text: customCfg ?? '');
    showDialog(
      context: context,
      barrierDismissible: false,
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
            onPressed: () async {
              final t = ctrl.text.trim();
              ctrl.dispose();
              Navigator.pop(context);
              if (t.startsWith('vless://') || t.startsWith('http://') || t.startsWith('https://')) {
                // ТОТ ЖE trusted-host гейт, что и в _importKey: без него «вставь это в Свой конфиг»
                // обходил защиту и при kRealTunnel=true трафик молча ушёл бы на хост атакующего.
                final host = _hostOf(t);
                if (host == null || !_isTrustedHost(host)) {
                  final ok = await _confirmForeignHost(host ?? 'неизвестный хост');
                  if (ok != true) return;
                }
                setState(() { keyStr = t; importedHost = host; customCfg = t; });
                _save();
                _toast(host != null ? 'Ключ заменён на $host ✓' : 'Ключ заменён ✓');
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
      // «скоро» — не выбираем (функция ещё не работает), показываем тост вместо ложного переключения
      onTap: soon ? () => _toast('Скоро 🙌') : () { setState(() => proto = idx); _save(); },
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
          Switch(value: soon ? false : v, onChanged: soon ? null : onCh, activeColor: C.accent),
        ]),
      );
}
