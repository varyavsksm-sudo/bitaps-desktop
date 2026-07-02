part of 'main.dart';

// ============================ CONSTANTS / ENDPOINTS ============================
// Реальные ссылки/бэкенд
const kBot = 'https://t.me/bitaps_vpn_auth_bot';
const kSupport = 'https://t.me/bitapssupport';
const kChannel = 'https://t.me/bitapsvpnofficial';
const kRef = 'https://t.me/bitaps_vpn_auth_bot?start=ref_demo';
// Боевой туннель: ВЫКЛ (демо). Мост к нативному движку уже есть (native_tunnel.dart:
// MethodChannel app.bitaps.vpn/control) и toggle() в боевом режиме реально зовёт sing-box.
// Ставить true, когда на платформе подключена нативная сторона (Apple: PacketTunnelProvider +
// Libbox.xcframework; Android: VpnService + libbox). См. TUNNEL.md. При true без нативной
// стороны connect() честно бросит TunnelUnavailable — фейкового «Подключено» не будет.
const bool kRealTunnel = false;
const kNotify = 'https://bjkozsukvifkxriojxrz.supabase.co/functions/v1/notify';
const kApiKey = 'sb_publishable_X2CJWgjqeZtbNelAri9ofw_trbfWF9Z';
const kDemoKey = 'vless://3a7c9f1e-0b2d-4e6f-9a1c-7b3e2f8d4c5a@vpn.bitaps.app:443?security=reality&type=tcp&sni=www.microsoft.com&fp=chrome&pbk=DEMObitapsPLACEHOLDERkey00000000000000000000000&sid=88#bitaps%20VPN';
const kAppLogin = 'https://bjkozsukvifkxriojxrz.supabase.co/functions/v1/app-login';
const kAppSub = 'https://bjkozsukvifkxriojxrz.supabase.co/functions/v1/app-sub';
const kAppPair = 'https://bjkozsukvifkxriojxrz.supabase.co/functions/v1/app-pair';
const kRotateSecret = 'https://bjkozsukvifkxriojxrz.supabase.co/functions/v1/rotate-secret';

// Авто-проверка обновлений: CI вшивает номер сборки через --dart-define и кладёт build_number.txt в релиз.
// Локальная/дев-сборка → 0 (проверку не делаем, чтобы не звать «обновись» в дебаге).
const int kBuildNumber = int.fromEnvironment('BUILD_NUMBER', defaultValue: 0);
const kBuildNumberUrl = 'https://github.com/varyavsksm-sudo/bitaps-desktop/releases/latest/download/build_number.txt';
const kDownloadUrl = 'https://bitapsvpn.com/app.html';

// Персонализация: акцентные темы (имя, основной, мягкий) + стили кнопки
const List<(String, Color, Color)> accentThemes = [
  ('Sunset', Color(0xFFFF7A1A), Color(0xFFFFB347)),
  ('Neon', Color(0xFF2DE2FF), Color(0xFF6AA8FF)),
  ('Emerald', Color(0xFF19D98A), Color(0xFF6FF0BD)),
  ('Lavender', Color(0xFFA779FF), Color(0xFFD0B3FF)),
  ('Crimson', Color(0xFFFF4D6D), Color(0xFFFF9BAD)),
];
const btnStyleNames = ['Шестерёнка', 'Кольцо', 'Орб', 'Пульс'];
// Порог разового предупреждения о большом расходе за сессию (тумблер «Лимит трафика»)
const double kTrafficWarnMB = 5120; // 5 ГБ

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
  try {
    if (v != null && v.isNotEmpty) { await _secure.write(key: k, value: v); } else { await _secure.delete(key: k); }
    await p.remove(k);
  } catch (_) {
    if (v != null && v.isNotEmpty) { await p.setString(k, v); } else { await p.remove(k); }
  }
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

class Faq {
  final String q, a;
  const Faq(this.q, this.a);
}

const faqs = [
  Faq('Сколько устройств можно подключить?', 'До 10 устройств одновременно по одной подписке.'),
  Faq('Вы ведёте логи?', 'Нет. Мы не храним логи активности — только техническую информацию для работы сервиса.'),
  Faq('Как продлить подписку?', 'В «Кабинете» нажми «Продлить» — оплата через Telegram, СБП или крипту.'),
  Faq('VPN не подключается?', 'Смени локацию или протокол на «Авто», проверь интернет. Не помогло — напиши в поддержку.'),
];

const modeLabels = ['Авто', 'Стрим', 'Игры', 'Прив.'];
