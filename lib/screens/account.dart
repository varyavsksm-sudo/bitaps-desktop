part of '../main.dart';

// ============================ ACCOUNT (Кабинет: вход, подписка, ключ, устройства) ============================
// Экран «вход» отдельного виджета не имеет — форма входа встроена в _subCard() при !loggedIn.

// коды тарифов из бэкенда (mo/q/h/yr/trial) → человекочитаемые названия,
// чтобы в кабинете не светился сырой код («Тариф «mo»» / бейдж «MO»)
const Map<String, String> _planNames = {
  'mo': '1 месяц', 'q': '3 месяца', 'h': '6 месяцев', 'yr': '12 месяцев', 'trial': 'Пробный период',
};
const Map<String, String> _planShorts = {
  'mo': '1 МЕС', 'q': '3 МЕС', 'h': '6 МЕС', 'yr': '1 ГОД', 'trial': 'ТРИАЛ',
};
const Map<String, int> _planTotalDays = {'mo': 30, 'q': 90, 'h': 180, 'yr': 365, 'trial': 3};

extension ShellAccount on ShellState {
  // Импорт своего ключа/подписки из буфера (модель Happ)
  Future<void> _importKey() async {
    final data = await Clipboard.getData('text/plain');
    final t = (data?.text ?? '').trim();
    // Принимаем только сам VPN-ключ (vless://). Fetch подписки по http(s)-ссылке не реализован —
    // раньше ссылка молча сохранялась как ключ и коннект падал, поэтому http(s) больше не принимаем.
    if (!t.startsWith('vless://')) {
      _toast(tr('В буфере нет ключа vless://'));
      return;
    }
    final host = _hostOf(t);
    // null/непарсящийся хост = НЕ доверенный → предупреждаем (раньше null молча проходил мимо гейта)
    if (host == null || !_isTrustedHost(host)) {
      final ok = await _confirmForeignHost(host ?? tr('неизвестный хост'));
      if (ok != true) return;
    }
    if (!mounted) return;
    rebuild(() {
      keyStr = t;
      importedHost = host;
    });
    _save();
    _toast(host != null
        ? (appLang == 'en' ? 'Key replaced with $host ✓' : 'Ключ заменён на $host ✓')
        : tr('Ключ заменён ✓'));
  }

  int? _daysLeft() {
    if (subExpires == null) return null;
    final e = DateTime.tryParse(subExpires!);
    if (e == null) return null;
    // округляем ВВЕРХ по минутам: пока есть остаток времени — показываем ≥1 день,
    // «истекла» (≤0) только когда срок реально вышел (раньше 1-23ч флорились в 0 = «истекла» на сутки раньше)
    return (e.toUtc().difference(DateTime.now().toUtc()).inMinutes / 1440).ceil();
  }

  // Русские склонения дней: 1 день / 2-4 дня / 5+ дней
  String _pluralDays(int n) {
    final n10 = n % 10, n100 = n % 100;
    if (n10 == 1 && n100 != 11) return 'день';
    if (n10 >= 2 && n10 <= 4 && (n100 < 12 || n100 > 14)) return 'дня';
    return 'дней';
  }

  // Лимит устройств: число, либо «…» при загрузке, либо «—» если неизвестно
  String get _limitStr => subLimit != null ? '$subLimit' : (_subLoading ? '…' : '—');

  // баннер-напоминание при близком/истёкшем сроке (тумблер «Подписка истекает»)
  // веб-аккаунт (отрицательный telegram_id из app-login по веб-ключу) не может продлить через бота —
  // ведём его на сайт; обычный (положительный) id — в бота
  String get _renewUrl => (tgId != null && tgId! < 0) ? 'https://bitapsvpn.com/pay.html' : kBot;

  Widget _expiryBanner(int days) {
    final expired = days <= 0;
    return GestureDetector(
      onTap: () => _open(_renewUrl),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(color: C.warn.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14),
          border: Border.all(color: C.warn.withValues(alpha: 0.5))),
        child: Row(children: [
          const Icon(Icons.notifications_active, color: C.warn, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(expired ? tr('Подписка истекла') : tr('Подписка истекает'), style: disp(14, w: FontWeight.w700, c: C.warn)),
            const SizedBox(height: 2),
            Text(
              expired
                  ? tr('Продли, чтобы вернуть доступ')
                  : (appLang == 'en'
                      ? '$days ${days == 1 ? 'day' : 'days'} left — renew early'
                      : 'Осталось $days ${_pluralDays(days)} — продли заранее'),
              style: mono(11, c: C.muted)),
          ])),
          const SizedBox(width: 8),
          Text(tr('Продлить →'), style: mono(12, c: C.accent)),
        ]),
      ),
    );
  }

  Widget _account() {
    final daysLeft = _daysLeft(); // считаем один раз за билд (tryParse+арифметика), переиспользуем ниже
    return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(tr('Кабинет'), style: disp(26, w: FontWeight.w800)),
          const SizedBox(height: 18),
          _profileCard(),
          const SizedBox(height: 14),
          if (loggedIn && tgl3 && daysLeft != null && daysLeft <= 3) ...[_expiryBanner(daysLeft), const SizedBox(height: 14)],
          _subCard(),
          const SizedBox(height: 14),
          _keyCard(),
          if (loggedIn) ...[const SizedBox(height: 14), _devicesCard()],
          const SizedBox(height: 14),
          _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [_gIcon(Icons.card_giftcard), const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _kicker(tr('пригласи друзей')), const SizedBox(height: 3), Text(tr('Приглашай — получай бонусные дни'), style: mono(11))]))]),
            const SizedBox(height: 10),
            Text(tr('▸ +14 дней за каждого друга, кто оформит первую подписку\n▸ начисляем автоматически'), style: mono(12, c: C.muted)),
            const SizedBox(height: 12),
            _btn(tr('Поделиться ссылкой'), kind: 1, icon: Icons.share, onTap: () {
              if (!loggedIn) { _toast(tr('Войди, чтобы получить свою реферальную ссылку')); return; }
              if (tgId != null && tgId! < 0) { _toast(tr('Рефералы — через нашего Telegram-бота')); _open(kBot); return; } // веб-аккаунт: реф работает только в Telegram
              _copy('https://t.me/bitaps_vpn_auth_bot?start=ref$tgId', tr('Реферальная ссылка'));
            }),
          ])),
          const SizedBox(height: 14),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _open(kBot),
            child: _card(strong: true, child: Row(children: [
              _gIcon(Icons.router),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('B-box — VPN для всего дома'), style: disp(16, w: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(tr('устройство для дома · 15 000 ₽'), style: mono(12, c: C.accent)),
              ])),
              Icon(Icons.chevron_right, color: C.muted),
            ])),
          ),
          const SizedBox(height: 14),
          _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [_gIcon(Icons.forum), const SizedBox(width: 12), _kicker(tr('поддержка'))]),
            const SizedBox(height: 12),
            Container(padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: C.field, borderRadius: BorderRadius.circular(10)),
              child: TextField(
                controller: _support,
                maxLines: 3,
                style: mono(13, c: C.text),
                cursorColor: C.accent,
                decoration: InputDecoration(isDense: true, border: InputBorder.none,
                  contentPadding: EdgeInsets.zero, hintText: tr('Опиши проблему…'), hintStyle: mono(13, c: C.muted)),
              )),
            const SizedBox(height: 12),
            _btn(tr('Отправить'), kind: 0, icon: Icons.send, onTap: _supportSending ? null : _sendSupport),
            const SizedBox(height: 10),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _open(kSupport),
              child: Center(child: Text(tr('или напиши @bitapssupport'), style: mono(12, c: C.accent)))),
          ])),
          const SizedBox(height: 14),
          _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [_gIcon(Icons.help), const SizedBox(width: 12), _kicker(tr('частые вопросы'))]),
            const SizedBox(height: 8),
            for (final f in faqs) _faqRow(f),
          ])),
          const SizedBox(height: 18),
          Center(child: Text('bitaps vpn · v1.0', style: mono(11, c: C.muted))),
        ],
      );
  }

  Widget _profileCard() {
    final name = loggedIn
        ? ((subName != null && subName!.isNotEmpty)
            ? subName!
            : (appLang == 'en' ? 'Account (#$tgId)' : 'Аккаунт (#$tgId)'))
        : tr('Вход не выполнен');
    final initial = name.isNotEmpty ? name.substring(0, 1).toUpperCase() : 'A';
    return _card(strong: true, child: Row(children: [
      Container(width: 60, height: 60, alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: accentGrad,
          boxShadow: [BoxShadow(color: C.accent.withValues(alpha: 0.4), blurRadius: 18)]),
        child: Text(initial, style: disp(26, w: FontWeight.w800, c: C.bg))),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, style: disp(20, w: FontWeight.w700)),
        const SizedBox(height: 3),
        Text(loggedIn ? tr('Вход по ключу из бота') : tr('Войди через Telegram, чтобы активировать подписку'), style: mono(11)),
        const SizedBox(height: 6),
        Row(children: loggedIn
            ? [_badge(subActive ? tr('Активна') : tr('Не активна'), subActive ? C.ok : C.muted),
               if (subPlan != null) ...[const SizedBox(width: 6), _badge(_planShort(subPlan!), C.accent)]]
            : [_badge(tr('Гость'), C.muted)]),
      ])),
      if (loggedIn) GestureDetector(behavior: HitTestBehavior.opaque, onTap: _logout,
        child: Icon(Icons.logout, size: 20, color: C.muted)),
    ]));
  }

  String _planLabel(String? p) {
    if (p == null) return tr('Нет подписки');
    if (p == 'trial') return tr('Пробный период');
    final n = _planNames[p] ?? p;
    return appLang == 'en' ? 'Plan "${tr(n)}"' : 'Тариф «$n»';
  }
  String _planShort(String p) => tr(_planShorts[p] ?? p.toUpperCase());

  Widget _subCard() {
    if (!loggedIn) {
      return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [_gIcon(Icons.login), const SizedBox(width: 12), _kicker(tr('вход'))]),
        const SizedBox(height: 10),
        Text(tr('Войди через Telegram — приложение само подхватит твою подписку и ключ. Без ручного копирования.'), style: mono(12)),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: _btn(tr('Войти через Telegram'), kind: 0, icon: Icons.send, onTap: _pairLogin)),
        const SizedBox(height: 14),
        // Вход по VPN-ключу отключён на сервере — приглашаем вставлять только «Код входа» (UUID),
        // который реально принимает бэкенд (app-login по {secret}). Раньше форма звала вставить
        // vless-ключ → он уходил как {key} и всегда получал 403.
        Text(tr('или вставь Код входа:'), style: mono(11, c: C.muted)),
        const SizedBox(height: 8),
        Container(padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: C.field, borderRadius: BorderRadius.circular(10)),
          child: TextField(controller: _loginCtrl, maxLines: 2, style: mono(11, c: C.text), cursorColor: C.accent,
            decoration: InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.zero,
              hintText: tr('Код входа (UUID из бота или письма)'), hintStyle: mono(12, c: C.muted)))),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _btn(tr('Войти'), kind: 1, icon: Icons.login, onTap: _loggingIn ? null : () => _login())),
          const SizedBox(width: 12),
          Expanded(child: _btn(tr('Ключ в боте'), kind: 1, icon: Icons.smart_toy, onTap: () => _open(kBot))),
        ]),
      ]));
    }
    final days = _daysLeft();
    final dleft = (days ?? 0).clamp(0, 100000).toInt();
    final total = _planTotalDays[subPlan] ?? 30;
    final ringFrac = total > 0 ? (dleft / total).clamp(0.0, 1.0) : 0.0;
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [_gIcon(Icons.workspace_premium), const SizedBox(width: 12), _kicker(tr('подписка')), const Spacer(),
        GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => _refreshSub(),
          child: _subLoading
              ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.accent))
              : Icon(Icons.refresh, size: 18, color: C.accent))]),
      const SizedBox(height: 16),
      Row(children: [
        _ring(dleft, ringFrac),
        const SizedBox(width: 20),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_planLabel(subPlan), style: disp(20, w: FontWeight.w700, c: subActive ? C.accent : C.muted)),
          const SizedBox(height: 6),
          Row(children: [Icon(Icons.event, size: 14, color: C.muted), const SizedBox(width: 6),
            Text(
              days != null
                  ? (days > 0
                      ? (appLang == 'en' ? '$days ${days == 1 ? 'day' : 'days'} left' : 'осталось $days ${_pluralDays(days)}')
                      : tr('истекла'))
                  : (subActive ? tr('активна') : tr('не активна')),
              style: mono(13))]),
          const SizedBox(height: 4),
          Row(children: [Icon(Icons.devices, size: 14, color: C.muted), const SizedBox(width: 6),
            Text(appLang == 'en' ? '${devices.length} / $_limitStr devices' : '${devices.length} / $_limitStr устройств', style: mono(13))]),
        ])),
      ]),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: _btn(tr('Продлить'), kind: 0, icon: Icons.bolt, onTap: () => _open(_renewUrl))),
        const SizedBox(width: 12),
        Expanded(child: _btn(tr('Обновить'), kind: 1, icon: Icons.refresh, onTap: () => _refreshSub())),
      ]),
    ]));
  }

  Widget _keyCard() => _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [_gIcon(Icons.qr_code_2), const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _kicker(tr('ключ доступа')), const SizedBox(height: 3),
            Text(loggedIn ? tr('твой ключ из аккаунта') : tr('для роутера и ручной настройки'), style: mono(11))]))]),
        const SizedBox(height: 12),
        Container(padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: C.field, borderRadius: BorderRadius.circular(10)),
          child: SingleChildScrollView(scrollDirection: Axis.horizontal,
            child: Text(keyStr, style: mono(11, c: C.text), maxLines: 1, softWrap: false))),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _btn(tr('Скопировать'), kind: 1, icon: Icons.copy, onTap: () => _copy(keyStr, tr('Ключ')))),
          const SizedBox(width: 12),
          Expanded(child: loggedIn
              ? _btn(tr('Обновить'), kind: 2, icon: Icons.refresh, onTap: () => _refreshSub())
              : _btn(tr('Вставить'), kind: 2, icon: Icons.content_paste, onTap: _importKey)),
        ]),
        if (loggedIn && loginSecret != null) ...[
          const SizedBox(height: 12),
          _divider(), // единый разделитель как в остальном UI (было голое Divider(...))
          const SizedBox(height: 10),
          Row(children: [_gIcon(Icons.lock_outline), const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _kicker(tr('код входа')), const SizedBox(height: 3),
              Text(tr('для входа в приложение — не вставляй в VPN-клиенты'), style: mono(11))]))]),
          const SizedBox(height: 10),
          Container(padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: C.field, borderRadius: BorderRadius.circular(10)),
            child: Text(loginSecret!, style: mono(11, c: C.text), maxLines: 1, overflow: TextOverflow.ellipsis)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _btn(tr('Скопировать'), kind: 1, icon: Icons.copy, onTap: () => _copy(loginSecret!, tr('Код входа')))),
            const SizedBox(width: 12),
            Expanded(child: _btn(tr('Сменить'), kind: 2, icon: Icons.refresh, onTap: _rotateSecret)),
          ]),
        ],
      ]));

  Widget _devicesCard() => _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [_gIcon(Icons.devices), const SizedBox(width: 12),
          _kicker(appLang == 'en' ? 'devices · ${devices.length}/$_limitStr' : 'устройства · ${devices.length}/$_limitStr'), const Spacer(),
          GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => _refreshSub(),
            child: _subLoading
                ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.accent))
                : Icon(Icons.refresh, size: 18, color: C.accent))]),
        const SizedBox(height: 8),
        if (devices.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Column(children: [
            Icon(Icons.devices_other, size: 30, color: C.muted),
            const SizedBox(height: 8),
            Text(tr('Пока нет устройств.\nПодключись с устройства — оно появится здесь.'), textAlign: TextAlign.center, style: mono(12)),
          ]))
        else
          for (final d in devices) _deviceRow(d),
      ]));

  Widget _deviceRow(Map<String, dynamic> d) {
    final name = (d['name'] as String?) ?? tr('Устройство');
    final id = d['id'] as String?;
    return Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: Row(children: [
      Icon(Icons.smartphone, size: 18, color: C.muted),
      const SizedBox(width: 10),
      Expanded(child: Text(name, style: disp(14, w: FontWeight.w600), overflow: TextOverflow.ellipsis)),
      // Тап-таргет удаления ≥40px (было 19px)
      IconButton(
        onPressed: id == null ? null : () => _confirmDelDevice(id, name),
        iconSize: 19,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        splashRadius: 22,
        tooltip: tr('Удалить'),
        icon: const Icon(Icons.delete_outline, color: C.danger)),
    ]));
  }

  void _confirmDelDevice(String id, String name) {
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: C.bg2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: C.line)),
      title: Text(tr('Удалить устройство?'), style: disp(18, w: FontWeight.w700)),
      content: Text(appLang == 'en' ? '"$name" will be removed from the subscription.' : '«$name» будет удалено из подписки.', style: mono(13, c: C.muted)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Отмена'), style: mono(13, c: C.muted))),
        TextButton(onPressed: () { Navigator.pop(context); _refreshSub(del: id); }, child: Text(tr('Удалить'), style: mono(13, c: C.danger))),
      ],
    ));
  }

  Widget _faqRow(Faq f) => Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 12),
          iconColor: C.accent,
          collapsedIconColor: C.muted,
          title: Text(tr(f.q), style: disp(14, w: FontWeight.w600)),
          children: [Align(alignment: Alignment.centerLeft, child: Text(tr(f.a), style: mono(13)))],
        ),
      );
}
