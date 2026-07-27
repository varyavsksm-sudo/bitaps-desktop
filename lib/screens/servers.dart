part of '../main.dart';

// ============================ SERVERS ============================
extension ShellServers on ShellState {
  Widget _servers() {
    // Честные цифры из реальных данных (models.dart), а не выдуманные «32 / 12 / 99.9%»:
    // считаем реально доступные серверы и их локации (города). Зарубежные (available:false) не в счёт.
    final avail = fleet.where((s) => s.available).toList();
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
          // IntrinsicHeight + stretch: плитки одной высоты (тексты в 1 и 2 строки давали рваные края)
          IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: _infoTile('${avail.length}', appLang == 'en'
                ? (avail.length == 1 ? 'server\navailable' : 'servers\navailable')
                : '${_ruPlural(avail.length, 'сервер', 'сервера', 'серверов')}\nдоступно')),
            const SizedBox(width: 12),
            Expanded(child: _infoTile('$locations', appLang == 'en'
                ? (locations == 1 ? 'location' : 'locations')
                : _ruPlural(locations, 'локация', 'локации', 'локаций'))),
          ])),
          const SizedBox(height: 16),
          // Кнопка «Пинг»: живой замер отклика по всем доступным серверам (_pingServers в api.dart).
          // Semantics: во время замера кнопка неактивна — сообщаем это и скринридеру.
          Semantics(
            button: true,
            enabled: !_pinging,
            label: tr('Проверить серверы'),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _pinging ? null : _pingServers,
              child: _card(strong: true, child: Row(children: [
                _gIcon(Icons.network_ping),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('Проверить серверы'), style: disp(16, w: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(_pinging ? tr('проверяю, где идёт трафик…') : tr('проверить, через какие серверы реально идёт трафик'), style: mono(12)),
                ])),
                _pinging
                    ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: C.accent))
                    : Icon(Icons.play_arrow, color: C.accent),
              ])),
            ),
          ),
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

  // Русские склонения для счётчиков плиток: 1 сервер / 2-4 сервера / 5+ серверов
  // (тот же алгоритм, что _pluralDays в account.dart).
  String _ruPlural(int n, String one, String few, String many) {
    final n10 = n % 10, n100 = n % 100;
    if (n10 == 1 && n100 != 11) return one;
    if (n10 >= 2 && n10 <= 4 && (n100 < 12 || n100 > 14)) return few;
    return many;
  }

  // Секция сортируется по фактическому пингу (живой замер приоритетнее статичного):
  // лучшие сверху; во время замера «Пинг» строки пересортировываются на лету —
  // rebuild после каждого замеренного сервера в _pingServers.
  List<Server> _byPing(Iterable<Server> src) {
    final l = src.toList();
    l.sort((a, b) => pingOf(a).compareTo(pingOf(b)));
    return l;
  }

  List<Widget> _serverSections(bool locked) {
    final all = fleet;
    final favList = _byPing(all.where((s) => favs.contains(s.id)));
    // Узлы «белого списка» (через CDN) показываем отдельной группой: они нужны, когда прямые
    // адреса недоступны, но обычно медленнее — пользователю честнее видеть это разделение.
    final direct = _byPing(all.where((s) => !s.proto.startsWith('LTE')));
    final bs = _byPing(all.where((s) => s.proto.startsWith('LTE')));
    return [
      if (favList.isNotEmpty) ...[
        _kicker(tr('⭐ избранное')),
        const SizedBox(height: 10),
        for (final s in favList) _serverRow(s, locked),
        const SizedBox(height: 22),
      ],
      if (direct.isNotEmpty) ...[
        _kicker(tr('прямые серверы')),
        const SizedBox(height: 10),
        for (final s in direct) _serverRow(s, locked),
      ],
      if (bs.isNotEmpty) ...[
        const SizedBox(height: 22),
        _kicker(tr('анти-глушилка · CDN')),
        const SizedBox(height: 10),
        for (final s in bs) _serverRow(s, locked),
      ],
      // Пустой список объясняем: чаще всего это занятый лимит устройств или истёкшая подписка,
      // и человек должен видеть причину прямо здесь, а не гадать.
      if (all.isEmpty) _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Текст от сервиса выдачи приходит по-русски — прогоняем через tr(), иначе в английском
        // интерфейсе он остался бы русским.
        Text(tr(subNotice ?? 'Войди в аккаунт — здесь появятся твои серверы'),
            style: disp(15, w: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(
          !loggedIn
              ? tr('Список серверов приходит вместе с подпиской.')
              // сверяем с РУССКИМ оригиналом: сервис отвечает на русском независимо от языка приложения
              : (subNotice ?? '').contains('Лимит')
                  ? tr('Отключи лишнее устройство в «Кабинете» или расширь лимит — и серверы появятся.')
                  : tr('Проверь подписку в «Кабинете» и обнови список.'),
          style: mono(12.5, c: C.muted)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _btn(tr('Обновить'), kind: 1, icon: Icons.refresh,
              onTap: _subLoading ? null : () => _refreshSub())),
          const SizedBox(width: 12),
          Expanded(child: _btn(tr('Кабинет'), kind: 0, icon: Icons.person_outline, onTap: () => _goTab(2))),
        ]),
      ])),
    ];
  }

  Widget _serverRow(Server s, bool locked) {
    final sel = s.id == server.id;
    final ping = pingOf(s);
    final st = stateOf(s.id);
    // Число показываем ТОЛЬКО у проверенных узлов и только сквозное — время ответа через сам
    // туннель. Раньше здесь стоял TCP-коннект до адреса: при глушении интернета он проходит,
    // а трафик — нет, и человек видел зелёный отклик у сервера, через который ничего не грузится.
    final measured = st == NodeState.works && ping > 0;
    final pingCol = st == NodeState.blocked
        ? C.danger
        : !measured ? C.muted : ping < 60 ? C.ok : ping < 120 ? C.warn : C.danger;
    final pingLabel = switch (st) {
      NodeState.blocked => tr('через этот сервер трафик не идёт'),
      NodeState.unknown => tr('не проверен'),
      NodeState.works => ping < 60 ? tr('быстрый отклик') : ping < 120 ? tr('средний отклик') : tr('медленный отклик'),
    };
    // При locked (conn!=0) все строки кроме текущего сервера некликабельны-сейчас → приглушаем их,
    // чтобы список не выглядел обманчиво активным. Текущий сервер (sel) оставляем читаемым.
    final dimmed = (locked && !sel) || !s.available;
    return Opacity(
      opacity: dimmed ? 0.55 : 1,
      // Semantics: строка — кнопка выбора сервера с признаком выбора (как кнопка «Пинг» выше);
      // лейбл (город/страна/пинг) собирается из дочерних текстов автоматически.
      child: Semantics(
        button: true,
        selected: sel,
        enabled: s.available,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Недоступную строку раньше глушил IgnorePointer — тап проваливался в тишину. Тап
          // отдаём всегда: _pickServer сам объяснит и «сервер пока недоступен», и «сначала отключись».
          onTap: () => _pickServer(s),
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
              // Город — отдельной строкой (на окне 390px бейджи в одной строке с городом
              // схлопывали его до «А…»), бейджи — к строке страны: PRO и «скоро» для строк,
              // которые выбрать пока нельзя (без бейджа приглушённая строка выглядела просто
              // блёклой, и человек жал её впустую).
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(s.city), style: disp(15, w: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Row(children: [
                  // У узлов подписки поля «страна» нет (название узла — уже страна), и строка
                  // оставалась пустой. Пишем рельсу: в «⭐ избранном» прямые узлы и узлы через
                  // CDN лежат вперемешку без заголовков групп, и отличить их иначе нечем.
                  Flexible(child: Text(
                    s.country.isNotEmpty ? tr(s.country)
                      : tr(s.proto.startsWith('LTE') ? 'через CDN' : 'прямой узел'),
                    style: mono(12), overflow: TextOverflow.ellipsis)),
                  if (s.premium) ...[const SizedBox(width: 6), _badge('PRO', accentSoftInk)],
                  if (st == NodeState.blocked) ...[const SizedBox(width: 6), _badge(tr('не работает'), C.danger)]
                  else if (!s.available) ...[const SizedBox(width: 6), _badge(tr('скоро'), C.muted)],
                ]),
              ])),
              Tooltip(message: measured ? '$pingLabel · $ping ms' : pingLabel,
                child: Text(st == NodeState.blocked ? '✕' : measured ? '$ping ms' : '—',
                    style: mono(13, c: pingCol, w: FontWeight.w600))),
              // Нагрузку узла подписка не сообщает — «0 %» с пустой полоской читались как
              // «сервер совершенно свободен». Показываем колонку, только когда число настоящее.
              if (s.load > 0) ...[
                const SizedBox(width: 10),
                Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${s.load}%', style: mono(10, c: C.muted)),
                  const SizedBox(height: 3),
                  SizedBox(width: 42, child: _loadBar(s.load)),
                ]),
              ],
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
                  color: favs.contains(s.id) ? accentSoftInk : C.muted)),
              const SizedBox(width: 2),
              Icon(sel ? Icons.check_circle : Icons.circle_outlined, size: 20, color: sel ? C.accent : C.muted),
            ]),
          ),
        ),
      ),
    );
  }
}
