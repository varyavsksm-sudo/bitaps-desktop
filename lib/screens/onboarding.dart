part of '../main.dart';

// ============================ ONBOARDING (первый запуск) ============================
// Три карточки-знакомства в общем glass-токен-языке: что такое bitaps → способы входа →
// демо-режим + кнопки входа и «Посмотреть без входа» (гость → Главная в демо).
// Показывается один раз (флаг seen_onboarding в prefs) и по «Показать знакомство» из Настроек.
// Формулировки про сеть/туннель — ТОЛЬКО существующие в приложении («Демо-режим»,
// «демо — без реального туннеля»); новых обещаний не добавляем.
extension ShellOnboarding on ShellState {
  // Закрыть знакомство: пометить просмотренным, перейти на нужную вкладку, затем — доп. действие
  // (например, старт Telegram-пейринга). then зовётся пост-фреймом, когда онбординг уже снят,
  // чтобы его диалоги открывались над обычным UI, а не над закрывающимся экраном.
  void _finishOnboarding({int? gotoTab, VoidCallback? then}) {
    rebuild(() {
      _showOnboarding = false;
      if (gotoTab != null) tab = gotoTab;
    });
    _syncAnimations(); // онбординг снят → поднимаем анимации активной вкладки
    SharedPreferences.getInstance()
        .then((p) => p.setBool('seen_onboarding', true))
        .then((_) {}, onError: (e) { debugPrint('seen_onboarding save failed: $e'); });
    if (then != null) WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) then(); });
  }

  // Открыть знакомство заново (пункт «Показать знакомство» в Настройках).
  void _replayOnboarding() {
    rebuild(() { _showOnboarding = true; _onbPage = 0; });
    _syncAnimations(); // фоновые анимации вкладок под онбордингом не гоняем
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _onbCtrl.hasClients) _onbCtrl.jumpToPage(0);
    });
  }

  Widget _onboarding() {
    return Scaffold(
      backgroundColor: C.bg,
      body: Stack(children: [
        Positioned.fill(child: ColoredBox(color: C.bg)),
        // тот же верхний акцентный градиент, что и в основном каркасе (_buildBody)
        Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
          gradient: RadialGradient(center: const Alignment(0, -0.95), radius: 0.95,
            colors: [C.accent.withValues(alpha: C.light ? 0.16 : 0.17), C.accent.withValues(alpha: 0)])))),
        SafeArea(child: Align(alignment: Alignment.topCenter, child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Row(children: [
                _logo(),
                const Spacer(),
                // skip доступен всегда: гость попадает на Главную в демо
                Semantics(button: true, child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _finishOnboarding(gotoTab: loggedIn ? 0 : 2),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Text(tr('Пропустить'), style: mono(13, c: C.muted, w: FontWeight.w600))))),
              ]),
            ),
            Expanded(child: PageView(
              controller: _onbCtrl,
              onPageChanged: (i) => rebuild(() => _onbPage = i),
              children: [_onbCardAbout(), _onbCardLogin(), _onbCardDemo()],
            )),
            // точки-индикатор
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (int i = 0; i < 3; i++) AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: _onbPage == i ? 22 : 8, height: 8,
                decoration: BoxDecoration(
                  color: _onbPage == i ? C.accent : C.line,
                  borderRadius: BorderRadius.circular(4))),
            ]),
            const SizedBox(height: 14),
            // на первых двух карточках — «Далее»; на последней кнопки внутри карточки
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: _onbPage < 2
                  ? _btn(tr('Далее'), kind: 0, icon: Icons.arrow_forward, onTap: () {
                      if (_onbCtrl.hasClients) {
                        _onbCtrl.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
                      }
                    })
                  : const SizedBox(height: 0),
            ),
          ]),
        ))),
      ]),
    );
  }

  // Общий каркас карточки: скролл на низких окнах + glass-карточка по центру.
  Widget _onbShell(List<Widget> children) => Center(child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
        child: _card(padding: 22, child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: children)),
      ));

  // строка-пункт с иконкой (для списков в карточках)
  Widget _onbRow(IconData ic, String title, String sub) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _gIcon(ic),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: disp(15, w: FontWeight.w600)),
            const SizedBox(height: 3),
            Text(sub, style: mono(11.5, c: C.muted)),
          ])),
        ]),
      );

  // Карточка 1: что такое bitaps — только реальные механики (ключ, устройства, оплата).
  Widget _onbCardAbout() => _onbShell([
        _kicker(tr('что такое bitaps')),
        const SizedBox(height: 14),
        Text(tr('VPN по одному ключу'), style: disp(24, w: FontWeight.w800)),
        const SizedBox(height: 10),
        Text(tr('Подписка живёт в Telegram-боте, а этот клиент — её пульт: ключ, устройства и кабинет в одном окне.'),
            style: mono(12.5, c: C.muted)),
        const SizedBox(height: 8),
        _onbRow(Icons.qr_code_2, tr('Личный VPN-ключ'), tr('один ключ — до 10 устройств на одной подписке')),
        _onbRow(Icons.devices, tr('Все платформы'), tr('Windows, macOS, Linux, Android — одно приложение')),
        _onbRow(Icons.payments_outlined, tr('Оплата как удобно'), tr('Telegram Stars, СБП или крипта — в пару тапов')),
      ]);

  // Карточка 2: три способа входа (иконки те же, что в Кабинете).
  Widget _onbCardLogin() => _onbShell([
        _kicker(tr('три способа входа')),
        const SizedBox(height: 14),
        Text(tr('Входи как удобно'), style: disp(24, w: FontWeight.w800)),
        const SizedBox(height: 8),
        _onbRow(Icons.send, tr('Через Telegram'), tr('бот сам подтвердит вход — без ручного копирования')),
        _onbRow(Icons.vpn_key, tr('По VPN-ключу'), tr('вставь свой ключ (vless://…) — это и есть вход в аккаунт')),
        _onbRow(Icons.lock_outline, tr('По Коду входа'), tr('короткий код из бота — если ключ не под рукой')),
        const SizedBox(height: 6),
        Text(tr('Всё это — на вкладке «Кабинет».'), style: mono(11.5, c: C.muted)),
      ]);

  // Карточка 3: демо-режим (текущие формулировки приложения) + кнопки входа и гость.
  Widget _onbCardDemo() => _onbShell([
        _kicker(tr('демо')),
        const SizedBox(height: 14),
        Text(tr('Демо-режим'), style: disp(24, w: FontWeight.w800)),
        const SizedBox(height: 10),
        Text(tr('Подключение сейчас — демо, без реального туннеля. Интерфейс можно посмотреть целиком, вход не обязателен.'),
            style: mono(12.5, c: C.muted)),
        const SizedBox(height: 16),
        _btn(tr('Войти через Telegram'), kind: 0, icon: Icons.send,
            onTap: () => _finishOnboarding(gotoTab: 2, then: _pairLogin)),
        const SizedBox(height: 10),
        _btn(tr('VPN-ключ / Код входа'), kind: 1, icon: Icons.vpn_key,
            onTap: () => _finishOnboarding(gotoTab: 2)),
        const SizedBox(height: 10),
        _btn(tr('Посмотреть без входа'), kind: 2, icon: Icons.visibility_outlined,
            onTap: () => _finishOnboarding(gotoTab: 0)),
      ]);
}
