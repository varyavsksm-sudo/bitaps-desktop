part of '../main.dart';

// ============================ SETTINGS ============================
extension ShellSettings on ShellState {
  Widget _accentSwatch(int i) {
    final th = accentThemes[i];
    final sel = accentIdx == i;
    return GestureDetector(
      onTap: () {
        rebuild(() {
          accentIdx = i;
          C.accent = th.$2;
          C.accentSoft = th.$3;
        });
        _save();
      },
      // Semantics: свотч — кнопка с именем акцента (Sunset/Neon/…) и признаком выбора,
      // иначе скринридер слышит 5 безымянных кружков.
      child: Semantics(
        button: true,
        selected: sel,
        label: th.$1,
        child: Container(
          margin: const EdgeInsets.only(right: 12),
          width: 44, height: 44, alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle,
            gradient: LinearGradient(colors: [th.$3, th.$2]),
            border: Border.all(color: sel ? (C.light ? Colors.black : Colors.white) : Colors.transparent, width: 3),
            boxShadow: [BoxShadow(color: th.$2.withValues(alpha: 0.5), blurRadius: sel ? 14 : 6)]),
          child: sel ? Icon(Icons.check, size: 18, color: C.light ? Colors.black : Colors.white) : null,
        ),
      ),
    );
  }

  Widget _styleChip(int i) {
    final sel = btnStyle == i;
    const previews = [Icons.settings, Icons.radio_button_unchecked, Icons.brightness_1, Icons.wifi_tethering];
    return GestureDetector(
      onTap: () { rebuild(() => btnStyle = i); _syncAnimations(); _save(); }, // стиль решает, крутить ли шестерёнку/кольца
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(color: sel ? C.accent.withValues(alpha: 0.16) : C.fill,
          borderRadius: BorderRadius.circular(11), border: Border.all(color: sel ? C.accent : C.line)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(previews[i], size: 15, color: sel ? C.accent : C.muted),
          const SizedBox(width: 7),
          Text(tr(btnStyleNames[i]), style: disp(13, w: FontWeight.w600, c: sel ? C.accent : C.muted)),
        ])),
    );
  }

  Widget _themeChip(int i) {
    const names = ['Тёмная', 'Светлая', 'Системная'];
    const icons = [Icons.dark_mode_outlined, Icons.light_mode_outlined, Icons.brightness_auto_outlined];
    final sel = themeMode == i;
    return GestureDetector(
      onTap: () { rebuild(() { themeMode = i; _applyThemeMode(); }); _syncAnimations(); _save(); }, // starfield только в тёмной
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(color: sel ? C.accent.withValues(alpha: 0.16) : C.fill,
          borderRadius: BorderRadius.circular(11), border: Border.all(color: sel ? C.accent : C.line)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icons[i], size: 15, color: sel ? C.accent : C.muted),
          const SizedBox(width: 7),
          Text(tr(names[i]), style: disp(13, w: FontWeight.w600, c: sel ? C.accent : C.muted)),
        ])),
    );
  }

  // переключатель языка RU/EN — по образцу _themeChip
  Widget _langChip(String code, String label) {
    final sel = appLang == code;
    return GestureDetector(
      onTap: () { rebuild(() { appLang = code; }); _save(); },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(color: sel ? C.accent.withValues(alpha: 0.16) : C.fill,
          borderRadius: BorderRadius.circular(11), border: Border.all(color: sel ? C.accent : C.line)),
        child: Text(label, style: disp(13, w: FontWeight.w600, c: sel ? C.accent : C.muted)),
      ),
    );
  }

  // Честный лейбл протокола: выводим ФАКТИЧЕСКИЙ протокол текущего ключа (парсер умеет
  // vless/trojan/vmess/ss/hysteria2), а не захардкоженный «VLESS + Reality».
  String _protoLabel() {
    final scheme = keyStr.split(':').first.toLowerCase();
    switch (scheme) {
      case 'vless':
        final sec = Uri.tryParse(keyStr)?.queryParameters['security']?.toLowerCase();
        return sec == 'reality' ? 'VLESS + Reality' : 'VLESS';
      case 'trojan':
        return 'Trojan';
      case 'vmess':
        return 'VMess';
      case 'ss':
        return 'Shadowsocks';
      case 'hysteria2':
      case 'hy2':
        return 'Hysteria2';
      default:
        return tr('подбирается автоматически');
    }
  }

  void _showStats() {
    _dialog(tr('Статистика'),
        appLang == 'en'
            ? 'Sessions started: $sessions\nCurrent session: ${conn == 2 ? hms : "not connected"}\nServer: ${tr(server.city)}\nMode: ${tr(modeLabels[mode])}\nFavorite servers: ${favs.length}'
            : 'Сессий запущено: $sessions\nТекущая сессия: ${conn == 2 ? hms : "не подключено"}\nСервер: ${tr(server.city)}\nРежим: ${modeLabels[mode]}\nИзбранных серверов: ${favs.length}');
  }

  void _customConfig() {
    final ctrl = TextEditingController(text: customCfg ?? '');
    // Контроллер живёт, пока открыт диалог; освобождаем ПОСЛЕ закрытия маршрута (иначе TextField
    // ещё смонтирован → в debug «used after being disposed»). onPressed читает ctrl.text до pop.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: C.bg2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: C.line)),
        title: Text(tr('Свой конфиг'), style: disp(18, w: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          style: mono(12, c: C.text),
          cursorColor: C.accent,
          // хинт перечисляет схемы честно: принимаются все kSupportedKeySchemes, не только vless
          decoration: InputDecoration(hintText: tr('Вставь ключ vless://, trojan://, ss://…'), hintMaxLines: 2, hintStyle: mono(12, c: C.muted)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Отмена'), style: mono(13, c: C.muted))),
          TextButton(
            onPressed: () async {
              final t = ctrl.text.trim();
              Navigator.pop(context);
              if (kSupportedKeySchemes.any((s) => t.startsWith(s))) {
                // ТОТ ЖE trusted-host гейт, что и в _importKey: без него «вставь это в Свой конфиг»
                // обходил защиту и при kRealTunnel=true трафик молча ушёл бы на хост атакующего.
                // Принимаем ВСЕ схемы singbox_config (vless/trojan/vmess/ss/hysteria2), а не только
                // vless:// — и реально ПРИМЕНЯЕМ конфиг как ключ подключения (keyStr), а не мёртвый customCfg.
                final host = _hostOf(t);
                if (host == null || !_isTrustedHost(host)) {
                  final ok = await _confirmForeignHost(host ?? tr('неизвестный хост'));
                  if (ok != true) return;
                }
                if (!mounted) return;
                rebuild(() { keyStr = t; importedHost = host; customCfg = t; });
                _save();
                _toast(host != null
                    ? (appLang == 'en' ? 'Key replaced with $host ✓' : 'Ключ заменён на $host ✓')
                    : tr('Ключ заменён ✓'));
              } else if (t.isEmpty) {
                rebuild(() => customCfg = null);
                _save();
                _toast(tr('Конфиг очищен'));
              } else {
                // раньше любой текст «сохранялся» в customCfg с зелёным тостом, но customCfg нигде не
                // читается → фича была мёртвой. Не врём об успехе: честно отклоняем неподдержанный формат.
                _toast(appLang == 'en'
                    ? 'Need a vless:// key (or trojan/vmess/ss/hysteria2). Other formats are not supported.'
                    : 'Нужен ключ vless:// (или trojan/vmess/ss/hysteria2). Другой формат не поддерживается.');
              }
            },
            child: Text(tr('Сохранить'), style: mono(13, c: C.accent)),
          ),
        ],
      ),
    ).then((_) => ctrl.dispose());
  }

  Widget _settings() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(tr('Настройки'), style: disp(26, w: FontWeight.w800)),
          const SizedBox(height: 18),
          _kicker(tr('персонализация')),
          const SizedBox(height: 10),
          _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Цвет акцента'), style: disp(15, w: FontWeight.w600)),
            const SizedBox(height: 12),
            Row(children: [for (int i = 0; i < accentThemes.length; i++) _accentSwatch(i)]),
            const SizedBox(height: 18),
            Text(tr('Кнопка подключения'), style: disp(15, w: FontWeight.w600)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [for (int i = 0; i < btnStyleNames.length; i++) _styleChip(i)]),
            const SizedBox(height: 18),
            Text(tr('Тема'), style: disp(15, w: FontWeight.w600)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [for (int i = 0; i < 3; i++) _themeChip(i)]),
            const SizedBox(height: 18),
            Text(tr('Язык'), style: disp(15, w: FontWeight.w600)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [_langChip('ru', 'RU'), _langChip('en', 'EN')]),
          ])),
          const SizedBox(height: 22),
          _kicker(tr('безопасность')),
          const SizedBox(height: 10),
          _card(child: Column(children: [
            _toggle(tr('Блокировка входа'), tr('PIN при открытии приложения'), tgl1, (v) { if (v) { _enableLock(); } else { _pinFails = 0; _clearPinThrottle(); rebuild(() { tgl1 = false; appPin = null; }); _save(); } }),
            _divider(),
            _toggle(tr('Обрыв соединения'), tr('Уведомлять, если VPN отвалился'), tgl2, (v) { rebuild(() => tgl2 = v); _save(); }),
            _divider(),
            _toggle(tr('Подписка истекает'), tr('Напомнить за пару дней'), tgl3, (v) { rebuild(() => tgl3 = v); _save(); }),
            _divider(),
            _toggle(tr('Лимит трафика'), tr('Сигнал при расходе от 5 ГБ за сессию'), tgl4, (v) { rebuild(() => tgl4 = v); _save(); }),
            _divider(),
            _toggle(tr('Авто-подключение'), tr('Подключаться сразу при запуске'), autoConnect, (v) { rebuild(() => autoConnect = v); _save(); }),
          ])),
          const SizedBox(height: 22),
          _kicker(tr('инструменты')),
          const SizedBox(height: 10),
          _card(padding: 6, child: Column(children: [
            _navRow(Icons.speed, tr('Тест скорости'), _speedTest),
            _divider(),
            _navRow(Icons.bar_chart, tr('Статистика'), _showStats),
            _divider(),
            _navRow(Icons.shield, tr('Проверка утечек'), _leakCheck),
            _divider(),
            _navRow(Icons.upload_file, customCfg == null ? tr('Свой конфиг') : tr('Свой конфиг ✓'), _customConfig),
          ])),
          const SizedBox(height: 22),
          _kicker(tr('подключение')),
          const SizedBox(height: 10),
          // padding 6+8=14 — инсет строки как у _navRow-строк карточки «Инструменты» выше
          _card(padding: 6, child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Row(children: [
              Icon(Icons.bolt, size: 19, color: C.accent),
              const SizedBox(width: 12),
              Text(tr('Протокол'), style: disp(15, w: FontWeight.w500)),
              const Spacer(),
              Text(_protoLabel(), style: mono(13, c: C.muted)),
            ]),
          )),
          const SizedBox(height: 8),
          Text(tr('Протокол подбирается автоматически под твой ключ. Настраивать ничего не нужно.'),
              style: mono(11, c: C.muted)),
          const SizedBox(height: 22),
          _btn(tr('Выйти'), kind: 1, icon: Icons.logout, onTap: _logout),
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

  Widget _toggle(String title, String sub, bool v, ValueChanged<bool> onCh) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        // MergeSemantics: скринридер зачитывает заголовок+подзаголовок+состояние переключателя как один элемент.
        child: MergeSemantics(child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: disp(15, w: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(sub, style: mono(11)),
          ])),
          // activeTrackColor от текущего акцента: дефолтный трек — colorScheme.primary, а он
          // не пересобирается при смене акцента (ThemeData слушает только смену яркости).
          Switch(value: v, onChanged: onCh, activeThumbColor: C.accent, activeTrackColor: C.accent.withValues(alpha: 0.35)),
        ])),
      );
}
