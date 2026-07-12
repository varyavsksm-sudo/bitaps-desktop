part of 'main.dart';

// ============================ THEME / TOKENS ============================
class C {
  static Color bg = const Color(0xFF06040C);
  static Color bg2 = const Color(0xFF0C0A14);
  static Color text = const Color(0xFFEDF1F8);
  static Color muted = const Color(0xFF8A93A6);
  static Color line = const Color(0x14FFFFFF);
  static Color fill = const Color(0x0AFFFFFF);   // заливка чипов/строк (тема-зависимая)
  static Color field = const Color(0x59000000);  // фон полей/код-блоков (тема-зависимая)
  static Color accent = const Color(0xFFFF7A1A);
  static Color accentSoft = const Color(0xFFFFB347);
  // Статусные цвета тоже тема-зависимые: неоновые ok/warn/danger подобраны под тёмный фон,
  // на светлом #EAEEF6 они выцветали до нечитаемости (контраст <2:1) — в светлой теме затемняем.
  static Color ok = const Color(0xFF39D98A);
  static Color warn = const Color(0xFFFFAE3D);
  static Color danger = const Color(0xFFFF5470);

  static bool light = false;
  static void applyTheme(bool isLight) {
    light = isLight;
    bg = isLight ? const Color(0xFFEAEEF6) : const Color(0xFF06040C);
    bg2 = isLight ? const Color(0xFFFFFFFF) : const Color(0xFF0C0A14);
    text = isLight ? const Color(0xFF0F1828) : const Color(0xFFEDF1F8);
    muted = isLight ? const Color(0xFF5A6781) : const Color(0xFF8A93A6);
    line = isLight ? const Color(0x1A101A30) : const Color(0x14FFFFFF);
    fill = isLight ? const Color(0x0D000000) : const Color(0x0AFFFFFF);
    field = isLight ? const Color(0x0A000000) : const Color(0x59000000);
    ok = isLight ? const Color(0xFF0E9F63) : const Color(0xFF39D98A);
    warn = isLight ? const Color(0xFFB87400) : const Color(0xFFFFAE3D);
    danger = isLight ? const Color(0xFFD8324E) : const Color(0xFFFF5470);
    // Уведомляем Material-слой (MaterialApp выше Shell) о смене яркости — иначе ThemeData
    // остаётся тёмной в светлом режиме (selection handles / курсор / ripple / дефолты диалогов).
    // Обновляем ПОСЛЕ применения C.*, чтобы билд ThemeData читал уже актуальные цвета.
    themeLight.value = isLight;
  }
}

// Глобальный флаг яркости для реактивной темы Material-уровня. BitApp слушает его через
// ValueListenableBuilder и перестраивает ThemeData под актуальную яркость (см. main.dart).
final ValueNotifier<bool> themeLight = ValueNotifier<bool>(false);

LinearGradient get accentGrad =>
    LinearGradient(colors: [C.accentSoft, C.accent], begin: Alignment.topLeft, end: Alignment.bottomRight);

// «Чернильный» вариант accentSoft для светлой темы: пастельные тона палитр (например #FFB347)
// на белых карточках дают контраст ~1.5-2:1 и сливаются с фоном. Затемняем lightness до ≤0.38 —
// это даёт ≥~4:1 на белом для всех пяти палитр, не трогая палитру акцентов глобально.
// В тёмной теме — исходный accentSoft без изменений.
Color get accentSoftInk {
  if (!C.light) return C.accentSoft;
  final h = HSLColor.fromColor(C.accentSoft);
  return h.withLightness(math.min(h.lightness, 0.38)).toColor();
}

TextStyle disp(double s, {FontWeight w = FontWeight.w700, Color? c}) =>
    TextStyle(fontFamily: 'SpaceGrotesk', fontSize: s, fontWeight: w, color: c ?? C.text, letterSpacing: -0.3, height: 1.15);
TextStyle mono(double s, {FontWeight w = FontWeight.w500, Color? c}) =>
    TextStyle(fontFamily: 'JetBrainsMono', fontSize: s, fontWeight: w, color: c ?? C.muted, height: 1.2);
