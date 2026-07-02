part of '../main.dart';

// ============================ SERVERS ============================
extension ShellServers on _ShellState {
  Widget _servers() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(tr('Серверы'), style: disp(26, w: FontWeight.w800)),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: _infoTile('32', tr('серверов\nонлайн'))),
            const SizedBox(width: 12),
            Expanded(child: _infoTile('12', tr('локаций'))),
            const SizedBox(width: 12),
            Expanded(child: _infoTile('99.9%', tr('аптайм'))),
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
                contentPadding: EdgeInsets.zero, hintText: tr('Поиск города или страны'), hintStyle: mono(13, c: C.muted)),
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
            Text(tr('Ничего не найдено.\nПопробуй город — Москва, Амстердам —\nили страну, либо очисти поиск.'),
              textAlign: TextAlign.center, style: mono(12)),
          ])),
        ];
      }
      return [
        _kicker(tr('результаты')),
        const SizedBox(height: 10),
        for (final s in found) _serverRow(s),
      ];
    }
    final favList = all.where((s) => favs.contains(s.id)).toList();
    return [
      if (favList.isNotEmpty) ...[
        _kicker(tr('⭐ избранное')),
        const SizedBox(height: 10),
        for (final s in favList) _serverRow(s),
        const SizedBox(height: 22),
      ],
      _kicker(tr('🇷🇺 Россия')),
      const SizedBox(height: 10),
      for (final s in ruServers) _serverRow(s),
      const SizedBox(height: 22),
      _kicker(tr('🌍 Зарубежные · скоро')),
      const SizedBox(height: 10),
      for (final s in intlServers) _serverRow(s),
    ];
  }

  Widget _serverRow(Server s) {
    final sel = s.id == server.id;
    final pingCol = s.ping < 60 ? C.ok : s.ping < 120 ? C.warn : C.danger;
    final pingLabel = s.ping < 60 ? tr('быстрый отклик') : s.ping < 120 ? tr('средний отклик') : tr('медленный отклик');
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
                  if (!s.available) ...[const SizedBox(width: 6), _badge(tr('Скоро'), C.muted)],
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
}
