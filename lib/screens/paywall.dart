part of '../main.dart';

// ============================ PAYWALL («Продлить» внутри приложения) ============================
// Нативная витрина тарифов: 4 канон-тарифа (kPlanDefs = зеркало _shared/plans.ts, 399/999/1790/2990 ₽,
// +50 ₽/мес за доп-устройство, максимум 10) + селектор устройств + стрик-подсказка из app-sub.
// НОВЫХ платёжных рельсов нет: «Оплатить» — deep-link в бота (?start=subscribe_<plan>_<dev>)
// для Telegram-аккаунтов или pay.html?plan=&dev= для веб-аккаунтов (отрицательный tgId).
extension ShellPaywall on ShellState {
  void _openPaywall() {
    // страховка: гостю показывать нечего — его «Продлить» не рисуется (см. _subCard)
    if (!loggedIn) { _open(kBot); return; }
    int sel = kPlanDefs.length - 1; // дефолт — 12 месяцев («выбор большинства»)
    // выбранный сейчас тариф аккаунта логичнее как стартовый, если он из канона
    final cur = kPlanDefs.indexWhere((pl) => pl.code == subPlan);
    if (cur >= 0) sel = cur;
    int dev = (subLimit ?? 1).clamp(1, kMaxDevices); // VIP-лимит 100 → кламп к канон-максимуму
    final webAcc = tgId != null && tgId! < 0; // веб-аккаунт продлевается на сайте, не в боте
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => StatefulBuilder(builder: (ctx, setSt) {
      final plan = kPlanDefs[sel];
      final total = plan.base + (dev - 1) * kExtraPerMonthRub * plan.months;
      final perMo = (total / plan.months).round();
      return Scaffold(
        backgroundColor: C.bg,
        body: Stack(children: [
          Positioned.fill(child: ColoredBox(color: C.bg)),
          Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
            gradient: RadialGradient(center: const Alignment(0, -0.95), radius: 0.95,
              colors: [C.accent.withValues(alpha: C.light ? 0.16 : 0.17), C.accent.withValues(alpha: 0)])))),
          SafeArea(child: Align(alignment: Alignment.topCenter, child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(padding: const EdgeInsets.all(20), children: [
              Row(children: [
                IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  iconSize: 22,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                  splashRadius: 22,
                  tooltip: tr('Закрыть'),
                  icon: Icon(Icons.arrow_back, color: C.text)),
                const SizedBox(width: 6),
                Text(tr('Продлить подписку'), style: disp(24, w: FontWeight.w800)),
              ]),
              const SizedBox(height: 14),
              _kicker(tr('тарифы')),
              const SizedBox(height: 10),
              for (int i = 0; i < kPlanDefs.length; i++) ...[
                _planTile(i, sel, dev, (v) => setSt(() => sel = v)),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 4),
              _kicker(tr('устройства')),
              const SizedBox(height: 10),
              _card(child: Row(children: [
                _gIcon(Icons.devices),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(appLang == 'en' ? '$dev ${dev == 1 ? 'device' : 'devices'}' : '$dev ${_deviceWord(dev)}',
                      style: disp(16, w: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(tr('+50 ₽/мес за каждое доп-устройство · максимум 10'), style: mono(11, c: C.muted)),
                ])),
                _devBtn(Icons.remove, dev > 1 ? () => setSt(() => dev--) : null),
                const SizedBox(width: 8),
                _devBtn(Icons.add, dev < kMaxDevices ? () => setSt(() => dev++) : null),
              ])),
              // стрик-подсказка: реальные данные app-sub (продление ДО истечения даёт +3/+5/+7 дней)
              if (subActive && subNextBonus > 0) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  decoration: BoxDecoration(
                    color: C.ok.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: C.ok.withValues(alpha: 0.45))),
                  child: Row(children: [
                    Icon(Icons.local_fire_department, size: 20, color: C.ok),
                    const SizedBox(width: 12),
                    Expanded(child: Text(
                      appLang == 'en'
                          ? 'Renew before expiry — +$subNextBonus bonus days${subStreak > 0 ? ' (streak ×$subStreak)' : ''}'
                          : 'Продли до истечения — +$subNextBonus ${_pluralDays(subNextBonus)} бонусом${subStreak > 0 ? ' (стрик ×$subStreak)' : ''}',
                      style: mono(12, c: C.ok, w: FontWeight.w600))),
                  ])),
              ],
              const SizedBox(height: 14),
              _card(strong: true, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(tr('Итого'), style: disp(16, w: FontWeight.w600)),
                  const Spacer(),
                  Text('${_fmtRub(total)} ₽', style: TextStyle(fontFamily: 'JetBrainsMono',
                      fontSize: 26, fontWeight: FontWeight.w700, color: C.accent)),
                ]),
                const SizedBox(height: 4),
                Text(appLang == 'en' ? '≈ ${_fmtRub(perMo)} ₽/mo · ${tr(plan.title)}' : '≈ ${_fmtRub(perMo)} ₽/мес · ${plan.title}',
                    style: mono(12, c: C.muted)),
                // VIP платит по цене тарифа на 10 устройств — точный итог посчитает чекаут
                if (subVip) ...[
                  const SizedBox(height: 6),
                  Text(tr('VIP: цена считается по тарифу на 10 устройств — точный итог покажет бот'),
                      style: mono(11, c: C.warn)),
                ],
                const SizedBox(height: 14),
                _btn(tr('Оплатить'), kind: 0, icon: Icons.bolt, onTap: () {
                  _open(webAcc
                      ? '$kPayUrl?plan=${plan.code}&dev=$dev'
                      : '$kBot?start=subscribe_${plan.code}_$dev');
                }),
                const SizedBox(height: 10),
                Center(child: Text(
                  webAcc ? tr('оплата на сайте — СБП или крипта') : tr('оплата в боте — Stars, СБП, крипта или токены'),
                  style: mono(11, c: C.muted))),
              ])),
            ]),
          ))),
        ]),
      );
    })));
  }

  // Карточка тарифа: заголовок + цена/мес + итог; на 12 мес — бейдж «выбор большинства».
  Widget _planTile(int i, int sel, int dev, ValueChanged<int> onPick) {
    final pl = kPlanDefs[i];
    final total = pl.base + (dev - 1) * kExtraPerMonthRub * pl.months;
    final perMo = (total / pl.months).round();
    final selected = i == sel;
    return Semantics(
      button: true,
      selected: selected,
      label: tr(pl.title),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onPick(i),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: selected ? C.accent.withValues(alpha: 0.10) : C.fill,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? C.accent : C.line, width: selected ? 1.6 : 1)),
          child: Row(children: [
            // радио-точка выбора
            Container(width: 20, height: 20, alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle,
                border: Border.all(color: selected ? C.accent : C.muted, width: 2)),
              child: selected
                  ? Container(width: 10, height: 10,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: C.accent))
                  : null),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(tr(pl.title), style: disp(16, w: FontWeight.w700, c: selected ? C.accent : C.text)),
                if (pl.code == 'yr') ...[const SizedBox(width: 8), _badge(tr('выбор большинства'), C.accent)],
              ]),
              const SizedBox(height: 3),
              Text('≈ ${_fmtRub(perMo)} ₽/${appLang == 'en' ? 'mo' : 'мес'}', style: mono(11.5, c: C.muted)),
            ])),
            Text('${_fmtRub(total)} ₽', style: mono(15, c: selected ? C.accent : C.text, w: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }

  // круглая кнопка ➖/➕ селектора устройств (disabled на границах 1 и 10)
  Widget _devBtn(IconData ic, VoidCallback? onTap) => Semantics(
        button: true,
        enabled: onTap != null,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Opacity(
            opacity: onTap == null ? 0.35 : 1,
            child: Container(width: 40, height: 40, alignment: Alignment.center,
              decoration: BoxDecoration(
                color: C.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: C.accent.withValues(alpha: 0.35))),
              child: Icon(ic, size: 19, color: C.accent)),
          ),
        ),
      );

  // 1 234 567 → «1 234 567» (узкий неразрывный пробел как на сайте не нужен — обычный)
  String _fmtRub(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    return b.toString();
  }

  // склонение «устройств» для селектора (1 устройство / 2 устройства / 5 устройств)
  String _deviceWord(int n) {
    final n10 = n % 10, n100 = n % 100;
    if (n10 == 1 && n100 != 11) return 'устройство';
    if (n10 >= 2 && n10 <= 4 && (n100 < 12 || n100 > 14)) return 'устройства';
    return 'устройств';
  }
}
