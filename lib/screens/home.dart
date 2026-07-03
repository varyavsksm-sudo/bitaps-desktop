part of '../main.dart';

// ============================ HOME (статус / подключение) ============================
extension ShellHome on ShellState {
  // ---------------- HOME ----------------
  Widget _updateBanner() => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _open(kDownloadUrl),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: C.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: C.accent.withValues(alpha: 0.5)),
          ),
          child: Row(children: [
            Icon(Icons.system_update, size: 18, color: C.accent),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Доступна новая версия'), style: disp(13, w: FontWeight.w700, c: C.accent)),
              const SizedBox(height: 2),
              Text(tr('Нажми, чтобы скачать обновление'), style: mono(11, c: C.muted)),
            ])),
            Icon(Icons.download, size: 18, color: C.accent),
          ]),
        ),
      );

  Widget _home() {
    final connected = conn == 2;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      children: [
        if (_updateAvail) ...[_updateBanner(), const SizedBox(height: 12)],
        Row(children: [_logo(), const Spacer(), _shieldPill(connected)]),
        const SizedBox(height: 10),
        Center(child: _powerButton()),
        const SizedBox(height: 4),
        Center(child: Text(
          conn == 0 ? tr('Отключено') : conn == 1 ? tr('Подключение…') : tr('Подключено'),
          style: disp(22, w: FontWeight.w700, c: connected ? C.accent : (conn == 1 ? C.warn : C.text)))),
        const SizedBox(height: 6),
        Center(child: Text(connected ? hms : '00:00:00',
          style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 38, fontWeight: FontWeight.w700,
            color: connected ? C.accentSoft : C.muted, letterSpacing: 2))),
        const SizedBox(height: 4),
        Center(child: Text(connected ? tr('под защитой') : tr('нажми на кнопку'), style: mono(12))),
        const SizedBox(height: 20),
        Row(children: [
          for (int i = 0; i < 4; i++)
            Expanded(child: Padding(padding: EdgeInsets.only(right: i < 3 ? 8 : 0), child: _modeChip(modeLabels[i], i))),
        ]),
        const SizedBox(height: 10),
        Text(tr('Режим подбирает сервер: Авто/Игры — минимальный пинг, Стрим — наименьшая нагрузка, Прив. — быстрый сервер (зарубежные скоро).'), style: mono(12)),
        const SizedBox(height: 14),
        _card(child: Row(children: [
          Text(server.flag, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(server.city), style: disp(16, w: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('${server.ping} ms · ${server.proto}', style: mono(12)),
          ])),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => rebuild(() => tab = 1),
            child: Row(children: [
              Icon(Icons.swap_horiz, size: 17, color: C.accent),
              const SizedBox(width: 5),
              Text(tr('сменить'), style: disp(13, w: FontWeight.w700, c: C.accent)),
            ]),
          ),
        ])),
        const SizedBox(height: 10),
        Row(children: [
          Text(tr('ещё:'), style: mono(12)),
          const SizedBox(width: 8),
          Expanded(child: SizedBox(height: 32, child: ListView(
            scrollDirection: Axis.horizontal,
            children: [for (final s in [ruServers[1], ruServers[2], ...intlServers]) _miniChip(s)]))),
        ]),
        const SizedBox(height: 12),
        _card(padding: 13, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('↓', style: disp(15, c: C.muted)),
            const SizedBox(width: 5),
            Text(connected ? _fmtSpeed(down) : '—', style: mono(13, c: C.text, w: FontWeight.w600)),
            const SizedBox(width: 16),
            Text('↑', style: disp(15, c: C.muted)),
            const SizedBox(width: 5),
            Text(connected ? _fmtSpeed(up) : '—', style: mono(13, c: C.text, w: FontWeight.w600)),
            const Spacer(),
            Icon(Icons.language, size: 15, color: C.muted),
            const SizedBox(width: 6),
            // В боевом режиме (kRealTunnel) реального канала IP из движка нет → не показываем
            // выдуманный статичный адрес (иначе юзер увидел бы неверный IP без пометки «демо»).
            // Демо-IP светим только в демо-режиме, где рядом стоит дисклеймер.
            Text(connected && !kRealTunnel ? '95.142.16.7' : tr('IP скрыт'), style: mono(12)),
          ]),
          // Честно: без боевого туннеля скорость/трафик/IP — демонстрационные.
          if (connected && !kRealTunnel) ...[
            const SizedBox(height: 8),
            Text(tr('Демо-режим — скорость и IP показаны для примера'), style: mono(10, c: C.muted)),
          ],
        ])),
        const SizedBox(height: 12),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () { if (conn == 0) rebuild(() => server = fastestServer); toggle(); },
          child: _card(child: Row(children: [
            _gIcon(Icons.bolt),
            const SizedBox(width: 13),
            Text(connected ? tr('Отключить') : tr('Подключиться к быстрейшему серверу'), style: disp(15, w: FontWeight.w600)),
          ])),
        ),
      ],
    );
  }

  // Скорость движка приходит в kbps: ≥1000 показываем как Mbps, иначе kbps.
  String _fmtSpeed(int kbps) =>
      kbps >= 1000 ? '${(kbps / 1000).toStringAsFixed(1)} Mbps' : '$kbps kbps';

  Widget _logo() => Row(children: [
        Container(width: 30, height: 30, alignment: Alignment.center,
          decoration: BoxDecoration(gradient: accentGrad, borderRadius: BorderRadius.circular(9),
            boxShadow: [BoxShadow(color: C.accent.withValues(alpha: 0.5), blurRadius: 12)]),
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
              colors: [C.accent.withValues(alpha: glow), C.accent.withValues(alpha: 0)], stops: const [0.25, 1.0])),
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
              boxShadow: [BoxShadow(color: col.withValues(alpha: on ? 0.5 : 0.14), blurRadius: 22)])),
          Container(width: 150, height: 150,
            decoration: BoxDecoration(shape: BoxShape.circle, color: C.bg2, border: Border.all(color: C.line))),
          Icon(Icons.power_settings_new, size: 60, color: col),
        ]);
      case 2: // орб — наполненная светящаяся сфера
        return Container(width: 192, height: 192, alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle,
            gradient: RadialGradient(center: const Alignment(-0.4, -0.4),
              colors: on ? [C.accentSoft, C.accent, C.accent.withValues(alpha: 0.55)] : const [Color(0xFF1A1728), Color(0xFF12101C)]),
            boxShadow: [BoxShadow(color: col.withValues(alpha: on ? 0.55 : 0.14), blurRadius: 36)]),
          child: Icon(Icons.power_settings_new, size: 62, color: on ? Colors.black.withValues(alpha: 0.85) : col));
      case 3: // пульс — концентрические кольца от ядра
        return Stack(alignment: Alignment.center, children: [
          for (final r in const [220.0, 178.0, 136.0])
            Container(width: r, height: r,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: col.withValues(alpha: 0.22), width: 1.5))),
          Container(width: 96, height: 96, alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: C.bg2, border: Border.all(color: col, width: 2),
              boxShadow: [BoxShadow(color: col.withValues(alpha: on ? 0.5 : 0.1), blurRadius: 20)]),
            child: Icon(Icons.power_settings_new, size: 44, color: col)),
        ]);
      default: // шестерёнка
        return Stack(alignment: Alignment.center, children: [
          Container(width: 250, height: 250, decoration: BoxDecoration(shape: BoxShape.circle,
            gradient: RadialGradient(colors: [col.withValues(alpha: C.light ? 0.20 : 0.0), col.withValues(alpha: 0)]))),
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
          border: Border.all(color: C.accent.withValues(alpha: 0.5), width: 2)),
      ),
    );
  }

  Widget _modeChip(String label, int i) {
    final sel = mode == i;
    return GestureDetector(
      onTap: () {
        // Смена режима меняет и сервер → запрещаем не только при conn==2, но и при conn==1
        // (конфиг коннекта уже собран), иначе туннель и выбранный режим/сервер разъезжаются.
        if (conn != 0) { _toast(tr('Отключись, чтобы сменить режим')); return; }
        rebuild(() { mode = i; server = serverForMode(i); });
        _save();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 40, alignment: Alignment.center,
        decoration: BoxDecoration(
          color: sel ? C.accent.withValues(alpha: 0.16) : C.fill,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: sel ? C.accent : C.line),
        ),
        child: Text(tr(label), style: disp(13, w: FontWeight.w700, c: sel ? C.accent : C.muted)),
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
              color: server.id == s.id ? C.accent.withValues(alpha: 0.16) : C.fill,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: server.id == s.id ? C.accent : C.line)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(s.flag, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
              Text(tr(s.city), style: disp(12, w: FontWeight.w600)),
            ]),
          ),
        ),
      );
}
