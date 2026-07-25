part of 'main.dart';

// ============================ CONSTANTS / ENDPOINTS ============================
// Реальные ссылки/бэкенд
const kBot = 'https://t.me/bitaps_vpn_auth_bot';
const kSupport = 'https://t.me/bitapssupport';
// Боевой туннель: ВЫКЛ (демо). Мост к нативному движку уже есть (native_tunnel.dart:
// MethodChannel app.bitaps.vpn/control) и toggle() в боевом режиме реально зовёт sing-box.
// Ставить true, когда на платформе подключена нативная сторона (Apple: PacketTunnelProvider +
// Libbox.xcframework; Android: VpnService + libbox). См. TUNNEL.md. При true без нативной
// стороны connect() честно бросит TunnelUnavailable — фейкового «Подключено» не будет.
const bool kRealTunnel = true;

// Настоящий ли туннель поднят ПРЯМО СЕЙЧАС. kRealTunnel — лишь разрешение пытаться; фактически
// движок есть не на каждой платформе (на десктопе рядом лежит xray, на мобильных нужна нативная
// сторона). Интерфейс красит «защищено» зелёным только по этому флагу, чтобы демо-сессия никогда
// не выглядела как реальная защита.
bool gEngineReal = false;
// Базовый URL edge-функций (functions/v1) — вынесен, чтобы не повторять один и тот же префикс
// в каждом эндпоинте. Значения эндпоинтов идентичны прежним полным литералам.
const kFnBase = 'https://bjkozsukvifkxriojxrz.supabase.co/functions/v1/';
const kNotify = '${kFnBase}notify';
const kApiKey = 'sb_publishable_X2CJWgjqeZtbNelAri9ofw_trbfWF9Z';
const kDemoKey = 'vless://3a7c9f1e-0b2d-4e6f-9a1c-7b3e2f8d4c5a@vpn.bitaps.app:443?security=reality&type=tcp&sni=www.microsoft.com&fp=chrome&pbk=DEMObitapsPLACEHOLDERkey00000000000000000000000&sid=88#bitaps%20VPN';
const kAppLogin = '${kFnBase}app-login';
const kAppSub = '${kFnBase}app-sub';
const kAppPair = '${kFnBase}app-pair';
const kRotateSecret = '${kFnBase}rotate-secret';

// Авто-проверка обновлений: CI вшивает номер сборки через --dart-define и кладёт build_number.txt в релиз.
// Локальная/дев-сборка → 0 (проверку не делаем, чтобы не звать «обновись» в дебаге).
const int kBuildNumber = int.fromEnvironment('BUILD_NUMBER', defaultValue: 0);
// Номер последней сборки и сами файлы отдаём со СВОЕГО сервера: сторонний хостинг для
// пользователя из РФ — лишние редиректы и риск блокировки, а нам не нужен посредник.
const kBuildNumberUrl = 'https://origin.bit-core.online/dl/build_number.txt';
const kDownloadUrl = 'https://bitapsvpn.com/app.html';

// «Что нового»: changelog.json на сайте (репо bitaps-web). Формат: {"entries":[{"build":N,
// "date":"YYYY-MM-DD","ru":["…"],"en":["…"]}]}. Фетч fail-soft: сбой → экран показывает
// последнюю закэшированную версию или дружелюбную заглушку.
const kChangelogUrl = 'https://bitapsvpn.com/changelog.json';

// Кастомная URL-схема приложения (deep-link): bitaps://import?key=… и bitaps://login?secret=…
// Нативная регистрация схемы — CI-патчами платформ (см. build.yml) / .desktop+reg при первом
// запуске; приём — через app_links в ShellState._initDeepLinks().
const kUrlScheme = 'bitaps';

// Дефолтный глобальный хоткей подключения (десктоп): Cmd+Shift+B (macOS) / Ctrl+Shift+B (иначе).
// Хранится в prefs как строка вида "meta+shift+keyB"; рекордер в Настройках переопределяет.
const kDefaultHotkey = 'mod+shift+keyB';

// ── Тарифы (КАНОН, зеркало _shared/plans.ts бэкенда) ──
// Сетевого источника цен у приложения нет (edge-функции прайс не отдают), поэтому конструктор
// пейвола использует константы канона: 399/999/1790/2990 ₽, +50 ₽/мес за доп-устройство,
// максимум 10 устройств. Менять ТОЛЬКО синхронно с ~/bitaps-vpn/supabase/functions/_shared/plans.ts.
class PlanDef {
  final String code, title; // code = код тарифа бэкенда (mo/q/h/yr), title — по _planNames
  final int months, base;   // months — срок, base — цена за 1 устройство, ₽
  const PlanDef(this.code, this.title, this.months, this.base);
}

const List<PlanDef> kPlanDefs = [
  PlanDef('mo', '1 месяц', 1, 399),
  PlanDef('q', '3 месяца', 3, 999),
  PlanDef('h', '6 месяцев', 6, 1790),
  PlanDef('yr', '12 месяцев', 12, 2990),
];
const int kExtraPerMonthRub = 50; // доп-устройство = +50 ₽ за каждый месяц срока (канон)
const int kMaxDevices = 10;       // максимум устройств («не обсуждается»)
const kPayUrl = 'https://bitapsvpn.com/pay.html'; // веб-оплата (аккаунты с отрицательным tgId)

// Персонализация: акцентные темы (имя, основной, мягкий) + стили кнопки.
// 6-я «Phosphor» (CRT-зелёный) — СЕКРЕТНАЯ: свотч скрыт в Настройках, пока не разблокирована
// пасхалкой (7 тапов по мини-лого шапки). Индекс палитры = kPhosphorAccent.
const List<(String, Color, Color)> accentThemes = [
  ('Sunset', Color(0xFFFF7A1A), Color(0xFFFFB347)),
  ('Neon', Color(0xFF2DE2FF), Color(0xFF6AA8FF)),
  ('Emerald', Color(0xFF19D98A), Color(0xFF6FF0BD)),
  ('Lavender', Color(0xFFA779FF), Color(0xFFD0B3FF)),
  ('Crimson', Color(0xFFFF4D6D), Color(0xFFFF9BAD)),
  ('Phosphor', Color(0xFF33FF66), Color(0xFF8BFFA8)), // секретная — люминофор ЭЛТ
];
// Индекс секретной палитры «Phosphor» в accentThemes (последний элемент). Свотч показывается
// в Настройках только после разблокировки (флаг phosphorUnlocked, персист в prefs).
const int kPhosphorAccent = 5;
const btnStyleNames = ['Шестерёнка', 'Кольцо', 'Орб', 'Пульс'];
// Порог разового предупреждения о большом расходе за сессию (тумблер «Лимит трафика»)
const double kTrafficWarnMB = 5120; // 5 ГБ
// Демо: реального трафика нет, а условные скорости мелкие — порог 5 ГБ иначе НЕДОСТИЖИМ и тумблер
// «Лимит трафика» невозможно продемонстрировать. В демо ускоряем накопление, чтобы за пару минут
// демо-сессии счётчик правдоподобно дошёл до порога. Боевой путь (реальные байты движка) — множитель 1.
const double kDemoTrafficBoost = 1200;

// ============================ TOKENS / SECURE STORAGE ============================
// Секреты (vpn_key/appToken/loginSecret/appPin) храним в зашифрованном хранилище ОС
// (Keychain / DPAPI / libsecret), а не в plaintext SharedPreferences. Defensive: если secure storage
// недоступно (напр. нет libsecret на Linux) — падаем на prefs (как раньше), без локаута/потери сессии.
const _secure = FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));

// Чтение секрета: secure → если пусто, миграция старого plaintext prefs в secure → иначе prefs-фолбэк.
Future<String?> _secRead(SharedPreferences p, String k) async {
  try {
    final v = await _secure.read(key: k);
    if (v != null && v.isNotEmpty) return v;
    final old = p.getString(k); // было в plaintext (старая версия) → перенести и стереть
    if (old != null && old.isNotEmpty) {
      try { await _secure.write(key: k, value: old); await p.remove(k); } catch (_) {}
      return old;
    }
    return null;
  } catch (_) {
    return p.getString(k); // secure недоступно → как раньше
  }
}

// Запись секрета: в secure + удаляем plaintext-копию из prefs. Сбой secure → пишем в prefs (не теряем сессию).
Future<void> _secWrite(SharedPreferences p, String k, String? v) async {
  // Раздельные try: plaintext-фолбэк выполняется ТОЛЬКО при сбое самой secure-записи, а НЕ при
  // сбое очистки prefs. Иначе (secure записал, а p.remove упал) в catch дописывался plaintext —
  // секрет оказывался И в secure, И в открытых prefs, ровно та утечка, что _secWrite предотвращает.
  bool secureOk = false;
  try {
    if (v != null && v.isNotEmpty) { await _secure.write(key: k, value: v); } else { await _secure.delete(key: k); }
    secureOk = true;
  } catch (_) {
    // secure реально недоступно (напр. нет libsecret) → фолбэк в prefs, чтобы не потерять сессию
    if (v != null && v.isNotEmpty) { await p.setString(k, v); } else { await p.remove(k); }
  }
  // secure-запись прошла → только чистим plaintext-копию; её отсутствие НЕ триггерит дозапись секрета
  if (secureOk) { try { await p.remove(k); } catch (_) {/* не критично: секрет уже в secure */} }
}

// ============================ ИДЕНТИФИКАТОР УСТРОЙСТВА ============================
// Сервис подписки считает устройства по заголовку x-hwid: сколько разных hwid обратилось за
// подпиской, столько устройств занято по тарифу. Значит идентификатор обязан быть СТАБИЛЬНЫМ
// для установки (иначе каждый запуск съедал бы новый слот) и не нести ничего о железе
// пользователя — просто случайное число, живущее в prefs рядом с остальными настройками.
// Формат — hex: сервис принимает только [A-Za-z0-9=-], hex попадает в этот алфавит гарантированно.
String genHwid() {
  final r = math.Random.secure();
  return List<int>.generate(16, (_) => r.nextInt(256))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}

// ============================ MODELS / MOCK ============================
class Server {
  final String id, city, country, flag, proto;
  final int ping, load;
  final bool premium, available;
  const Server(this.id, this.city, this.country, this.flag, this.ping, this.load,
      {this.premium = false, this.available = true, this.proto = 'Reality'});
}

const ruServers = [
  Server('ru-msk', 'Москва', 'Россия', '🇷🇺', 12, 34),
  Server('ru-spb', 'Санкт-Петербург', 'Россия', '🇷🇺', 21, 41),
  Server('ru-ekb', 'Екатеринбург', 'Россия', '🇷🇺', 33, 28),
];
const intlServers = [
  Server('nl-ams', 'Амстердам', 'Нидерланды', '🇳🇱', 48, 22, premium: true, available: false),
  Server('de-fra', 'Франкфурт', 'Германия', '🇩🇪', 52, 18, premium: true, available: false),
  Server('fi-hel', 'Хельсинки', 'Финляндия', '🇫🇮', 45, 27, premium: true, available: false),
  Server('tr-ist', 'Стамбул', 'Турция', '🇹🇷', 63, 31, premium: true, available: false),
];

/// Узел подписки → строка списка серверов. Раньше список был захардкожен (Москва/СПб/…),
/// то есть показывал пользователю несуществующие серверы; теперь берём реальные узлы выдачи.
/// Метка вида «🇫🇮 Финляндия» / «🛡️ Нидерланды · БС» — флаг отделяем от названия по первому пробелу.
Server serverFromSubNode(SubNode n, {int ping = 0}) {
  final parts = n.remark.trim().split(' ');
  final flag = parts.isNotEmpty ? parts.first : '🌐';
  final city = parts.length > 1 ? parts.sublist(1).join(' ') : n.remark;
  return Server(
    n.tag, city, '', flag, ping, 0,
    proto: n.singboxReady ? 'Reality' : 'БС · CDN',
  );
}

class Faq {
  final String q, a;
  const Faq(this.q, this.a);
}

const faqs = [
  Faq('Сколько устройств можно подключить?', 'До 10 устройств одновременно по одной подписке.'),
  Faq('Вы ведёте логи?', 'Нет. Мы не храним логи активности — только техническую информацию для работы сервиса.'),
  Faq('Как продлить подписку?', 'В «Кабинете» нажми «Продлить» — оплата через Telegram, СБП или крипту.'),
  Faq('VPN не подключается?', 'Смени локацию, проверь интернет и что подписка активна. Не помогло — напиши в поддержку.'),
];

const modeLabels = ['Авто', 'Стрим', 'Игры', 'Прив.'];
