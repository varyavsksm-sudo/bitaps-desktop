part of 'main.dart';

// ============================ STARFIELD (premium bg) ============================
class _Star {
  final double x, y, r, o;
  final bool accent;
  const _Star(this.x, this.y, this.r, this.o, this.accent);
}

final List<_Star> _stars = () {
  int seed = 0x9E3779B9;
  double next() {
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
    return seed / 0x7FFFFFFF;
  }
  return List.generate(120, (_) => _Star(next(), next(), 0.4 + next() * 1.6, 0.12 + next() * 0.6, next() > 0.92));
}();

class StarPainter extends CustomPainter {
  final double t;
  StarPainter(this.t);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint(); // один Paint на кадр вместо 120 аллокаций (painter гоняет 60 fps)
    for (int i = 0; i < _stars.length; i++) {
      final s = _stars[i];
      final twinkle = 0.7 + 0.3 * math.sin(t * 0.8 + i * 1.7);
      p.color = (s.accent ? C.accent : Colors.white).withValues(alpha: (s.o * twinkle).clamp(0, 1));
      canvas.drawCircle(Offset(s.x * size.width, s.y * size.height), s.r, p);
    }
  }

  @override
  bool shouldRepaint(StarPainter old) => old.t != t;
}

// Шестерёнка рисуется в коде, чтобы перекрашиваться под выбранную тему
class GearPainter extends CustomPainter {
  final Color col;
  GearPainter(this.col);
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    final p = Paint()
      ..shader = LinearGradient(colors: [C.accentSoft, col], begin: Alignment.topLeft, end: Alignment.bottomRight)
          .createShader(Rect.fromCircle(center: c, radius: r));
    for (int i = 0; i < 10; i++) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(i / 10 * 2 * math.pi);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(0, -r * 0.84), width: r * 0.20, height: r * 0.34),
          Radius.circular(r * 0.05)),
        p);
      canvas.restore();
    }
    canvas.drawCircle(c, r * 0.72, p);
    canvas.drawCircle(c, r * 0.50, Paint()..color = const Color(0xFF0C0A14)); // тёмный медальон в обеих темах
    canvas.drawCircle(c, r * 0.50,
      Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = col.withValues(alpha: 0.45));
  }

  @override
  bool shouldRepaint(GearPainter old) => old.col != col;
}

// ============================ PHOSPHOR SCANLINES (секретная CRT-тема) ============================
// Тонкие горизонтальные сканлайны + слабое зелёное свечение — только когда активна тема «Фосфор».
// Статичный painter (без анимации, чтобы не жечь батарею и не мельтешить); repaint не нужен.
class ScanlinePainter extends CustomPainter {
  const ScanlinePainter();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0x0A000000);
    // каждые 3px — тёмная линия в 1px: даёт эффект люминофорной развёртки, но текст остаётся читаем
    for (double y = 0; y < size.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), p);
    }
  }

  @override
  bool shouldRepaint(ScanlinePainter old) => false;
}

// ============================ SHARED WIDGET BUILDERS ============================
// Переиспользуемые «строительные блоки» интерфейса (стекло-карточка, кнопки, бейджи и т.д.).
extension ShellWidgets on ShellState {
  // ---------------- GLASS CARD + SHARED ----------------
  Widget _card({required Widget child, double padding = 16, bool strong = false}) {
    final r = BorderRadius.circular(18);
    final lt = C.light;
    // В светлой теме заливка карточки практически непрозрачная (белый/0.96) — блюр за ней
    // не виден, но оплачивается GPU на каждый кадр. Гоняем BackdropFilter только в тёмной,
    // где стекло реально просвечивает звёзды.
    final inner = Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: lt
              ? (strong ? [Colors.white, Colors.white] : [Colors.white, Colors.white.withValues(alpha: 0.96)])
              : (strong ? [Colors.white.withValues(alpha: 0.13), Colors.white.withValues(alpha: 0.05)] : [Colors.white.withValues(alpha: 0.08), Colors.white.withValues(alpha: 0.025)]),
          begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: r,
        border: Border.all(color: lt ? Colors.black.withValues(alpha: 0.07) : Colors.white.withValues(alpha: 0.14)),
      ),
      child: child,
    );
    return Container(
      decoration: BoxDecoration(borderRadius: r,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: lt ? 0.10 : 0.44), blurRadius: lt ? 26 : 20, offset: Offset(0, lt ? 8 : 12))]),
      child: ClipRRect(
        borderRadius: r,
        child: lt ? inner : BackdropFilter(filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16), child: inner),
      ),
    );
  }

  Widget _gIcon(IconData ic) => Container(width: 42, height: 42, alignment: Alignment.center,
        decoration: BoxDecoration(color: C.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(13),
          border: Border.all(color: C.accent.withValues(alpha: 0.30))),
        child: Icon(ic, size: 19, color: C.accent));

  Widget _kicker(String t) => Text('// $t', style: mono(12, c: C.accent, w: FontWeight.w600));

  Widget _badge(String t, Color col) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: col.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: mono(11, c: col, w: FontWeight.w600)),
      );

  // в демо (kRealTunnel=false) подключённое состояние НЕ показываем зелёным «защищено» —
  // это ложный сигнал безопасности без реального туннеля. Демо → нейтральный янтарный «демо».
  Widget _shieldPill(bool on) {
    final green = on && gEngineReal;
    final demo = on && !gEngineReal;
    final col = green ? C.ok : (demo ? C.warn : C.muted);
    final label = green ? tr('защищено') : (demo ? tr('демо') : tr('не защищено'));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(color: col.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: col,
          boxShadow: green ? [BoxShadow(color: C.ok.withValues(alpha: 0.6), blurRadius: 8)] : null)),
        const SizedBox(width: 7),
        Text(label, style: mono(12, c: col, w: FontWeight.w600)),
      ]),
    );
  }

  Widget _infoTile(String val, String label) => _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(val, style: disp(22, w: FontWeight.w800, c: C.accent)),
        const SizedBox(height: 4),
        Text(label, style: mono(11)),
      ]));

  // label — уже готовая строка в центре кольца (число дней или «—» для активной подписки без
  // даты): FittedBox страхует от переполнения, если строка окажется длиннее ожидаемого.
  Widget _ring(String label, double frac) => SizedBox(
        width: 78, height: 78,
        child: Stack(alignment: Alignment.center, children: [
          SizedBox(width: 78, height: 78, child: CircularProgressIndicator(
            value: frac, strokeWidth: 7, backgroundColor: C.line, color: C.accent)),
          Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 46, child: FittedBox(fit: BoxFit.scaleDown,
              child: Text(label, style: disp(24, w: FontWeight.w800)))),
            Text(tr('дн.'), style: mono(10)),
          ]),
        ]),
      );

  Widget _loadBar(int pct) {
    final col = pct < 50 ? C.ok : pct < 80 ? C.warn : C.danger;
    return ClipRRect(borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(value: pct / 100, minHeight: 4, backgroundColor: C.line, color: col));
  }

  Widget _divider() => Container(height: 1, color: C.line, margin: const EdgeInsets.symmetric(vertical: 4));

  Widget _btn(String label, {int kind = 0, IconData? icon, VoidCallback? onTap}) {
    final solid = kind == 0;
    final line = kind == 1;
    // onTap==null трактуем как disabled: гасим кнопку (Opacity), снимаем свечение и делаем её
    // некликабельной (onTap=null, а не пустой колбэк). Активные кнопки (onTap!=null) не меняются.
    final disabled = onTap == null;
    final btn = GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: solid ? accentGrad : null,
          color: solid ? null : (line ? Colors.transparent : C.fill),
          borderRadius: BorderRadius.circular(12),
          border: solid ? null : Border.all(color: C.line),
          boxShadow: (solid && !disabled) ? [BoxShadow(color: C.accent.withValues(alpha: 0.45), blurRadius: 22)] : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 17, color: solid ? C.bg : C.text), const SizedBox(width: 8)],
          Text(label, style: disp(16, w: FontWeight.w600, c: solid ? C.bg : C.text)),
        ]),
      ),
    );
    return disabled ? Opacity(opacity: 0.5, child: btn) : btn;
  }
}
