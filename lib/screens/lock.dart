part of '../main.dart';

// ============================ APP-LOCK (PIN) ============================
extension ShellLock on _ShellState {
  Widget _lockScreen() {
    return Scaffold(
      backgroundColor: C.bg,
      body: Center(child: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(28),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 72, height: 72, alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: accentGrad,
              boxShadow: [BoxShadow(color: C.accent.withOpacity(0.4), blurRadius: 20)]),
            child: const Icon(Icons.lock_outline, size: 34, color: Colors.white)),
          const SizedBox(height: 20),
          Text(tr('bitaps заблокирован'), style: disp(20, w: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(tr('Введите PIN, чтобы продолжить'), style: mono(12), textAlign: TextAlign.center),
          const SizedBox(height: 22),
          SizedBox(width: 210, child: TextField(controller: _pinCtrl, obscureText: true, keyboardType: TextInputType.number,
            textAlign: TextAlign.center, maxLength: 8, style: disp(22, w: FontWeight.w700, c: C.text), cursorColor: C.accent, autofocus: true,
            decoration: InputDecoration(counterText: '', hintText: '••••', hintStyle: disp(22, c: C.muted),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: C.line)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: C.accent))),
            onSubmitted: (_) => _tryUnlock())),
          const SizedBox(height: 18),
          SizedBox(width: 210, child: _btn(tr('Разблокировать'), kind: 0, icon: Icons.lock_open, onTap: _tryUnlock)),
          const SizedBox(height: 16),
          GestureDetector(behavior: HitTestBehavior.opaque, onTap: _forgotPin,
            child: Text(tr('Не помню PIN — выйти'), style: mono(12, c: C.muted))),
        ]))),
      ),
    );
  }

  void _tryUnlock() {
    if (_pinCtrl.text.trim() == appPin) {
      setState(() => _locked = false);
      _pinCtrl.clear();
    } else {
      _toast(tr('Неверный PIN'));
      _pinCtrl.clear();
    }
  }

  void _forgotPin() {
    _pinCtrl.clear();
    setState(() { appPin = null; tgl1 = false; _locked = false; });
    _doLogout(silent: true);
    _save();
    _toast(tr('Блокировка сброшена'));
  }

  Future<void> _enableLock() async {
    final c1 = TextEditingController(), c2 = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (dctx) => AlertDialog(
      backgroundColor: C.bg2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(tr('Задай PIN для входа'), style: disp(16, w: FontWeight.w700, c: C.text)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: c1, obscureText: true, keyboardType: TextInputType.number, maxLength: 8,
          style: mono(15, c: C.text), cursorColor: C.accent,
          decoration: InputDecoration(counterText: '', hintText: tr('PIN (4–8 цифр)'), hintStyle: mono(12, c: C.muted))),
        TextField(controller: c2, obscureText: true, keyboardType: TextInputType.number, maxLength: 8,
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
    c1.dispose(); c2.dispose();
    setState(() => tgl1 = (ok == true));
    _save();
  }
}
