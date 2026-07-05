part of '../main.dart';

// ============================ APP-LOCK (PIN) ============================
extension ShellLock on ShellState {
  Widget _lockScreen() {
    return Scaffold(
      backgroundColor: C.bg,
      body: Center(child: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(28),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 72, height: 72, alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: accentGrad,
              boxShadow: [BoxShadow(color: C.accent.withValues(alpha: 0.4), blurRadius: 20)]),
            child: const Icon(Icons.lock_outline, size: 34, color: Colors.white)),
          const SizedBox(height: 20),
          Text(tr('bitaps заблокирован'), style: disp(20, w: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            _pinLockSecs > 0
                ? (appLang == 'en'
                    ? 'Too many attempts. Wait ${_pinLockSecs}s'
                    : 'Слишком много попыток. Подожди $_pinLockSecs с')
                : tr('Введи PIN, чтобы продолжить'),
            style: mono(12, c: _pinLockSecs > 0 ? C.danger : C.muted),
            textAlign: TextAlign.center),
          const SizedBox(height: 22),
          SizedBox(width: 210, child: TextField(controller: _pinCtrl, obscureText: true, keyboardType: TextInputType.number,
            enabled: _pinLockSecs == 0, // блокируем ввод на время отсчёта
            inputFormatters: [FilteringTextInputFormatter.digitsOnly], // PIN только цифры (number-клавиатура на десктопе не ограничивает ввод)
            textAlign: TextAlign.center, maxLength: 8, style: disp(22, w: FontWeight.w700, c: C.text), cursorColor: C.accent, autofocus: true,
            decoration: InputDecoration(counterText: '', hintText: '••••', hintStyle: disp(22, c: C.muted),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: C.line)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: C.accent))),
            onSubmitted: (_) => _tryUnlock())),
          const SizedBox(height: 18),
          SizedBox(width: 210, child: Opacity(
            opacity: _pinLockSecs > 0 ? 0.45 : 1.0, // во время локаута кнопка приглушена — видно, что она неактивна
            child: _btn(tr('Разблокировать'), kind: 0, icon: Icons.lock_open, onTap: _pinLockSecs > 0 ? null : _tryUnlock))),
          const SizedBox(height: 16),
          GestureDetector(behavior: HitTestBehavior.opaque, onTap: _forgotPin,
            child: Text(tr('Не помню PIN — сбросить'), style: mono(12, c: C.muted))),
        ]))),
      ),
    );
  }

  void _tryUnlock() {
    if (_pinLockSecs > 0) return; // ввод временно заблокирован после серии ошибок
    if (_pinCtrl.text.trim() == appPin) {
      _pinFails = 0;
      _pinLockTimer?.cancel();
      _pinLockSecs = 0;
      _clearPinThrottle(); // успех → стираем сохранённый счётчик/таймер локаута
      rebuild(() => _locked = false);
      _syncAnimations(); // разблокировали → поднимаем анимации, погашенные на замке
      _pinCtrl.clear();
      _maybeAutoConnect(); // отложенный авто-коннект стартует только после разблокировки
    } else {
      _pinFails++;
      _pinCtrl.clear();
      // после 5 подряд ошибок — растущая блокировка ввода (локально, без бэкенда):
      // 5-я ошибка → 5с, каждая следующая +5с, максимум 60с. Тормозит перебор PIN.
      if (_pinFails >= 5) {
        _startPinLock(((_pinFails - 4) * 5).clamp(5, 60));
      } else {
        _savePinThrottle(); // копим счётчик и до порога — эскалация должна пережить рестарт
        _toast(tr('Неверный PIN'));
      }
    }
  }

  // Персист троттлинга PIN в secure storage (та же ОС-крипта, что и сам PIN): счётчик ошибок и
  // время окончания локаута (epoch ms). Fail-open: сбой записи не ломает вход, просто не переживёт рестарт.
  Future<void> _savePinThrottle({int lockUntilMs = 0}) async {
    try {
      final p = await SharedPreferences.getInstance();
      await _secWrite(p, 'pinFails', _pinFails > 0 ? '$_pinFails' : null);
      await _secWrite(p, 'pinLockUntil', lockUntilMs > 0 ? '$lockUntilMs' : null);
    } catch (_) {/* fail-open */}
  }

  Future<void> _clearPinThrottle() async {
    try {
      final p = await SharedPreferences.getInstance();
      await _secWrite(p, 'pinFails', null);
      await _secWrite(p, 'pinLockUntil', null);
    } catch (_) {/* fail-open */}
  }

  void _startPinLock(int secs) {
    _pinLockTimer?.cancel();
    rebuild(() => _pinLockSecs = secs);
    _savePinThrottle(lockUntilMs: DateTime.now().millisecondsSinceEpoch + secs * 1000);
    _pinLockTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      rebuild(() => _pinLockSecs = (_pinLockSecs - 1).clamp(0, 60));
      if (_pinLockSecs <= 0) t.cancel();
    });
  }

  // Забыл PIN → сбрасываем ТОЛЬКО замок (appPin в secure storage чистит _save), НЕ разлогинивая
  // аккаунт: сессия/подписка/ключ сохраняются. Подтверждение оставлено, чтобы случайный тап не снял защиту.
  void _forgotPin() {
    showDialog(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: C.bg2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: C.line)),
        title: Text(tr('Сбросить PIN?'), style: disp(18, w: FontWeight.w700)),
        content: Text(tr('Блокировка отключится, но ты останешься в аккаунте.'), style: mono(13, c: C.muted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx), child: Text(tr('Отмена'), style: mono(13, c: C.muted))),
          TextButton(
            onPressed: () {
              Navigator.pop(dctx);
              _pinCtrl.clear();
              _pinLockTimer?.cancel();
              _pinFails = 0;
              _clearPinThrottle(); // сброс PIN → стираем и сохранённый локаут
              rebuild(() { appPin = null; tgl1 = false; _locked = false; _pinLockSecs = 0; });
              _syncAnimations(); // сняли замок → поднимаем погашенные анимации
              _save(); // _secWrite(appPin=null) удаляет PIN из secure storage
              _toast(tr('Блокировка сброшена'));
              _maybeAutoConnect(); // разблокировались → поднимаем отложенный авто-коннект, если включён
            },
            child: Text(tr('Сбросить'), style: mono(13, c: C.accent)),
          ),
        ],
      ),
    );
  }

  Future<void> _enableLock() async {
    final c1 = TextEditingController(), c2 = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (dctx) => AlertDialog(
      backgroundColor: C.bg2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(tr('Задай PIN для входа'), style: disp(16, w: FontWeight.w700, c: C.text)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: c1, obscureText: true, keyboardType: TextInputType.number, maxLength: 8,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: mono(15, c: C.text), cursorColor: C.accent,
          decoration: InputDecoration(counterText: '', hintText: tr('PIN (4–8 цифр)'), hintStyle: mono(12, c: C.muted))),
        TextField(controller: c2, obscureText: true, keyboardType: TextInputType.number, maxLength: 8,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: mono(15, c: C.text), cursorColor: C.accent,
          decoration: InputDecoration(counterText: '', hintText: tr('Повтори PIN'), hintStyle: mono(12, c: C.muted))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dctx, false), child: Text(tr('Отмена'), style: mono(13, c: C.muted))),
        TextButton(onPressed: () {
          final p1 = c1.text.trim(), p2 = c2.text.trim();
          if (p1.length < 4) { _toast(tr('PIN — минимум 4 цифры')); return; }
          if (p1 != p2) { _toast(tr('PIN не совпадает')); return; }
          appPin = p1;
          Navigator.pop(dctx, true);
        }, child: Text(tr('Включить'), style: mono(13, c: C.accent))),
      ],
    ));
    rebuild(() => tgl1 = (ok == true));
    _save();
    // освобождаем контроллеры ПОСЛЕ того, как маршрут диалога полностью снят (пост-фрейм) —
    // иначе TextField'ы ещё в дереве на выходной анимации → в debug «used after being disposed».
    WidgetsBinding.instance.addPostFrameCallback((_) { c1.dispose(); c2.dispose(); });
  }
}
