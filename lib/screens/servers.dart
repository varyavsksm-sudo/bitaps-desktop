part of '../main.dart';

// ============================ SERVERS ============================
extension ShellServers on ShellState {
  Widget _servers() {
    // Честные цифры из реальных данных (models.dart), а не выдуманные «32 / 12 / 99.9%»:
    // считаем реально доступные серверы и их локации (города). Зарубежные (available:false) не в счёт.
    final avail = [...ruServers, ...intlServers].where((s) => s.available).toList();
    final locations = avail.map((s) => s.city).toSet().length;
    // Пока туннель поднят/поднимается (conn!=0), выбор сервера отбивается тостом. Список при этом
    // выглядит кликабельным → показываем тонкий inline-хинт и приглушаем некликабельные-сейчас строки
    // (текущий сервер остаётся читаемым). Логику/тосты не трогаем — только визуальная подсказка.
    final locked = conn != 0;
    return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(tr('Серверы'), style: disp(26, w: FontWeight.w800)),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: _infoTile('${avail.length}', tr('серверов\nдоступно'))),
            const SizedBox(width: 12),
            Expanded(child: _infoTile('$locations', tr('локаций'))),
          ]),
          const SizedBox(height: 16),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _pickServer(fastestServer),
            child: _card(strong: true, child: Row(children: [
              _gIcon(Icons.bolt),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Text(tr('Быстрый сервер'), style: disp(16, w: FontWeight.w700)),
                  const SizedBox(width: 8), _badge(tr('АВТО'), C.accent)]),
                const SizedBox(height: 3),
                Text('${tr(fastestServer.city)} · ${fastestServer.ping} ms', style: mono(12)),
              ])),
              Icon(Icons.chevron_right, color: C.muted),
            ])),
          ),
          const SizedBox(height: 12),
          _card(padding: 12, child: Row(children: [
            Icon(Icons.search, size: 18, color: C.muted),
            const SizedBox(width: 10),
            // Semantics-метка поля: hint виден глазами, но скринридеру нужна явная текстовая метка.
            Expanded(child: Semantics(textField: true, label: tr('Поиск города или страны'), child: TextField(
              controller: _search,
              onChanged: (v) => rebuild(() => _q = v),
              style: mono(13, c: C.text),
              cursorColor: C.accent,
              decoration: InputDecoration(isDense: true, border: InputBorder.none,
                contentPadding: EdgeInsets.zero, hintText: tr('Поиск города или страны'), hintStyle: mono(13, c: C.muted)),
            ))),
            if (_q.isNotEmpty) GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => rebuild(() { _q = ''; _search.clear(); }),
              child: Icon(Icons.close, size: 16, color: C.muted)),
          ])),
          if (locked) ...[
            const SizedBox(height: 16),
            Row(children: [
              Icon(Icons.lock_outline, size: 14, color: C.muted),
              const SizedBox(width: 6),
              Flexible(child: Text(tr('Отключись, чтобы сменить сервер'), style: mono(12))),
            ]),
          ],
          const SizedBox(height: 22),
          ..._serverSections(locked),
        ],
      );
  }

  List<Widget> _serverSections(bool locked) {
    final all = [...ruServers, ...intlServers];
    final q = _q.trim().toLowerCase();
    if (q.isNotEmpty) {
      // матчим и по исходным RU-строкам (s.city/s.country), и по переведённым (tr(...)) — иначе
      // в EN пользователь ищет «Moscow/Netherlands», а фильтр знает только «Москва/Нидерланды».
      final found = all.where((s) =>
          s.city.toLowerCase().contains(q) ||
          s.country.toLowerCase().contains(q) ||
          tr(s.city).toLowerCase().contains(q) ||
          tr(s.country).toLowerCase().contains(q)).toList();
      if (found.isEmpty) {
        return [
          Padding(padding: const EdgeInsets.symmetric(vertical: 28), child: Column(children: [
            Icon(Icons.travel_explore, size: 32, color: C.muted),
            const SizedBox(height: 10),
            Text(tr('Ничего не найдено.\nПопробуй город — Москва, Амстердам —\nили страну, либо очисти поиск.'),
              textAlign: TextAlign.center, style: mono(12)),
          ])),
        ];
      }
      return [
        _kicker(tr('результаты')),
        const SizedBox(height: 10),
        for (final s in found) _serverRow(s, locked),
      ];
    }
    final favList = all.where((s) => favs.contains(s.id)).toList();
    return [
      if (favList.isNotEmpty) ...[
        _kicker(tr('⭐ избранное')),
        const SizedBox(height: 10),
        for (final s in favList) _serverRow(s, locked),
        const SizedBox(height: 22),
      ],
      _kicker(tr('🇷🇺 Россия')),
      const SizedBox(height: 10),
      for (final s in ruServers) _serverRow(s, locked),
      const SizedBox(height: 22),
      _kicker(tr('🌍 Зарубежные · скоро')),
      const SizedBox(height: 10),
      for (final s in intlServers) _serverRow(s, locked),
    ];
  }

  Widget _serverRow(Server s, bool locked) {
    final sel = s.id == server.id;
    final pingCol = s.ping < 60 ? C.ok : s.ping < 120 ? C.warn : C.danger;
    final pingLabel = s.ping < 60 ? tr('быстрый отклик') : s.ping < 120 ? tr('средний отклик') : tr('медленный отклик');
    // При locked (conn!=0) все строки кроме текущего сервера некликабельны-сейчас → приглушаем их,
    // чтобы список не выглядел обманчиво активным. Текущий сервер (sel) оставляем читаемым.
    final dimmed = (locked && !sel) || !s.available;
    return IgnorePointer(
      ignoring: !s.available,
      child: Opacity(
        opacity: dimmed ? 0.55 : 1,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: s.available ? () => _pickServer(s) : null,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(color: C.fill,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: sel ? C.accent.withValues(alpha: 0.5) : C.line)),
            child: Row(children: [
              Container(width: 40, height: 40, alignment: Alignment.center,
                decoration: BoxDecoration(color: C.fill, borderRadius: BorderRadius.circular(12)),
                child: Text(s.flag, style: const TextStyle(fontSize: 20))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(tr(s.city), style: disp(15, w: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                  if (s.premium) ...[const SizedBox(width: 6), _badge('PRO', C.accentSoft)],
                  if (!s.available) ...[const SizedBox(width: 6), _badge(tr('Скоро'), C.muted)],
                ]),
                const SizedBox(height: 2),
                Text(tr(s.country), style: mono(12)),
              ])),
              Tooltip(message: '$pingLabel · ${s.ping} ms',
                child: Text('${s.ping} ms', style: mono(13, c: pingCol, w: FontWeight.w600))),
              const SizedBox(width: 10),
              Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${s.load}%', style: mono(10, c: C.muted)),
                const SizedBox(height: 3),
                SizedBox(width: 42, child: _loadBar(s.load)),
              ]),
              const SizedBox(width: 2),
              // Тап-таргет звезды ≥40px (было 18px — слишком мелко для касания)
              IconButton(
                onPressed: () { rebuild(() => favs.contains(s.id) ? favs.remove(s.id) : favs.add(s.id)); _save(); },
                iconSize: 19,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                splashRadius: 22,
                tooltip: tr('избранное'),
                icon: Icon(favs.contains(s.id) ? Icons.star : Icons.star_border,
                  color: favs.contains(s.id) ? C.accentSoft : C.muted)),
              const SizedBox(width: 2),
              Icon(sel ? Icons.check_circle : Icons.circle_outlined, size: 20, color: sel ? C.accent : C.muted),
            ]),
          ),
        ),
      ),
    );
  }
}
