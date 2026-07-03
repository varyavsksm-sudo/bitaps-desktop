part of 'main.dart';

// ============================ I18N (RU / EN) ============================
// Лёгкая локализация без внешних пакетов. Весь видимый пользователю русский текст
// проходит через tr(): в режиме 'en' подменяется на английский из _kEn, иначе остаётся русским.
// Строки с интерполяцией ($days, ${s.city} и т.п.) tr() не покрывает — они локализуются
// НА МЕСТЕ выражением `appLang == 'en' ? '<en>' : '<ru>'` (см. вызовы в других part-файлах).
//
// appLang меняется в Настройках (RU/EN) и сохраняется в prefs (ключ 'lang'); при первом
// запуске берётся из системной локали (см. _load в main.dart). Смена языка вызывает setState —
// весь UI перечитывает tr() и перерисовывается на лету.
String appLang = 'ru';

String tr(String ru) => appLang == 'en' ? (_kEn[ru] ?? ru) : ru;

const Map<String, String> _kEn = {
  // ---- main.dart (диалоги/тосты/навигация) ----
  'Не сервер bitaps': 'Not a bitaps server',
  'Отмена': 'Cancel',
  'Импортировать': 'Import',
  'Нет связи с сервером — проверь интернет.': 'No connection to server — check your internet.',
  'Вышли из аккаунта': 'Signed out',
  'Выйти?': 'Sign out?',
  'Выйдешь из аккаунта на этом устройстве. Подключение отключится, персональные настройки сохранятся.':
      "You'll sign out on this device. The connection will stop, your personal settings stay.",
  'Выйти': 'Sign out',
  'Ок': 'OK',
  'Отключитесь, чтобы сменить сервер': 'Disconnect to switch server',
  'Не удалось открыть ссылку': "Couldn't open the link",
  'Главная': 'Home',
  'Серверы': 'Servers',
  'Кабинет': 'Account',
  'Настройки': 'Settings',

  // ---- connection.dart ----
  'Нужен рабочий VPN-ключ': 'Need a working VPN key',
  'Соединение разорвано': 'Connection dropped',

  // ---- widgets.dart ----
  'защищено': 'protected',
  'не защищено': 'unprotected',
  'дн.': 'days',

  // ---- api.dart (сеть, вход, поддержка) ----
  'Минутку…': 'One moment…',
  'Сначала войди': 'Sign in first',
  'Меняю код…': 'Changing code…',
  'Сессия истекла — войди снова': 'Session expired — sign in again',
  'Код входа обновлён ✓': 'Login code updated ✓',
  'Не удалось сменить код': "Couldn't change the code",
  'Вставь ключ из бота или Код входа': 'Paste the key from the bot or your login code',
  'Вставь ключ (vless://…) или Код входа': 'Paste a key (vless://…) or login code',
  'Вхожу…': 'Signing in…',
  'Этот ключ не подошёл. Возьми актуальный ключ в боте.': "This key didn't work. Get a fresh key from the bot.",
  'Слишком много попыток. Подожди минуту и попробуй снова.': 'Too many attempts. Wait a minute and try again.',
  'Вход выполнен ✓': 'Signed in ✓',
  'Ключ не найден. Возьми актуальный ключ в боте.': 'Key not found. Get a fresh key from the bot.',
  'Не удалось начать вход, попробуй ещё раз': "Couldn't start sign-in, try again",
  'Подтверди вход в Telegram': 'Confirm sign-in in Telegram',
  'Открылся бот — нажми «Запустить», затем «✅ Да, это я». Войду сам, как подтвердишь.':
      'The bot opened — tap "Start", then "✅ Yes, it\'s me". I\'ll sign you in once you confirm.',
  'Не дождался подтверждения. Открой бота и нажми «Запустить».':
      "Didn't get confirmation. Open the bot and tap \"Start\".",
  'Не удалось войти': "Couldn't sign in",
  'Закрыть': 'Close',
  'Открыть бота': 'Open the bot',
  'Сначала войди по ключу': 'Sign in with your key first',
  'Удаляю устройство…': 'Removing device…',
  'Обновляю…': 'Refreshing…',
  'Удаление требует «Код входа». Открой его в боте (/start → Код входа) и войди по нему.':
      'Removing needs your login code. Get it in the bot (/start → Login code) and sign in with it.',
  'Не удалось подтвердить «Код входа» для удаления.': "Couldn't confirm the login code for removal.",
  'Сессия истекла — войди заново': 'Session expired — sign in again',
  'Устройство удалено ✓': 'Device removed ✓',
  'Обновлено ✓': 'Updated ✓',
  'Не удалось обновить': "Couldn't refresh",
  'Сначала напиши сообщение': 'Write a message first',
  'Отправляю…': 'Sending…',
  'Пользователь приложения': 'App user',
  'Отправлено в поддержку ✓': 'Sent to support ✓',
  'Проверка утечек': 'Leak check',
  'IP не получен': "Couldn't get IP",
  'Спид-тест': 'Speed test',

  // ---- home.dart ----
  'Доступна новая версия': 'New version available',
  'Нажми, чтобы скачать обновление': 'Tap to download the update',
  'Отключено': 'Disconnected',
  'Подключение…': 'Connecting…',
  'Подключено': 'Connected',
  'под защитой': "you're protected",
  'нажми на кнопку': 'tap the button',
  'Режим подбирает сервер: Авто/Игры — минимальный пинг, Стрим — наименьшая нагрузка, Прив. — зарубежный сервер.':
      'Mode picks the server: Auto/Games — lowest ping, Stream — lowest load, Private — a server abroad.',
  'сменить': 'change',
  'ещё:': 'more:',
  'IP скрыт': 'IP hidden',
  'Демо-режим — скорость и IP показаны для примера': 'Demo mode — speed and IP are shown for example',
  'Отключить': 'Disconnect',
  'Подключиться к быстрейшему серверу': 'Connect to the fastest server',

  // ---- servers.dart ----
  'серверов\nонлайн': 'servers\nonline',
  'локаций': 'locations',
  'аптайм': 'uptime',
  'Быстрый сервер': 'Fast server',
  'АВТО': 'AUTO',
  'Поиск города или страны': 'Search city or country',
  'Ничего не найдено.\nПопробуй город — Москва, Амстердам —\nили страну, либо очисти поиск.':
      'Nothing found.\nTry a city — Moscow, Amsterdam —\nor a country, or clear the search.',
  'результаты': 'results',
  '⭐ избранное': '⭐ favorites',
  '🇷🇺 Россия': '🇷🇺 Russia',
  '🌍 Зарубежные · скоро': '🌍 International · soon',
  'быстрый отклик': 'fast response',
  'средний отклик': 'medium response',
  'медленный отклик': 'slow response',
  'Скоро': 'Soon',

  // ---- account.dart (тарифы/подписка/ключ/устройства) ----
  '1 месяц': '1 month',
  '3 месяца': '3 months',
  '6 месяцев': '6 months',
  '12 месяцев': '12 months',
  'Пробный период': 'Trial period',
  '1 МЕС': '1 MO',
  '3 МЕС': '3 MO',
  '6 МЕС': '6 MO',
  '1 ГОД': '1 YR',
  'ТРИАЛ': 'TRIAL',
  'В буфере нет vless:// или ссылки-подписки': 'No vless:// or subscription link in the clipboard',
  'неизвестный хост': 'unknown host',
  'Ключ заменён ✓': 'Key replaced ✓',
  'Подписка истекла': 'Subscription expired',
  'Подписка истекает': 'Subscription expiring',
  'Продли, чтобы вернуть доступ': 'Renew to restore access',
  'Продлить →': 'Renew →',
  'пригласи друзей': 'invite friends',
  'Приглашай — получай бонусные дни': 'Invite friends — earn bonus days',
  '▸ +14 дней за каждого друга, кто оформит первую подписку\n▸ начисляем автоматически':
      '▸ +14 days for every friend who buys their first subscription\n▸ added automatically',
  'Поделиться ссылкой': 'Share link',
  'Войди, чтобы получить свою реферальную ссылку': 'Sign in to get your referral link',
  'Рефералы — через нашего Telegram-бота': 'Referrals work through our Telegram bot',
  'Реферальная ссылка': 'Referral link',
  'B-box — VPN для всего дома': 'B-box — VPN for the whole home',
  'устройство для дома · 15 000 ₽': 'home device · 15 000 ₽',
  'поддержка': 'support',
  'Опиши проблему…': 'Describe the problem…',
  'Отправить': 'Send',
  'или напиши @bitapssupport': 'or message @bitapssupport',
  'частые вопросы': 'faq',
  'Вход не выполнен': 'Not signed in',
  'Вход по ключу из бота': 'Signed in with a key from the bot',
  'Войди через Telegram, чтобы активировать подписку': 'Sign in with Telegram to activate your subscription',
  'Активна': 'Active',
  'Не активна': 'Inactive',
  'Гость': 'Guest',
  'Нет подписки': 'No subscription',
  'вход': 'sign in',
  'Войди через Telegram — приложение само подхватит твою подписку и ключ. Без ручного копирования.':
      'Sign in with Telegram — the app pulls in your subscription and key automatically. No manual copying.',
  'Войти через Telegram': 'Sign in with Telegram',
  'или вставь ключ вручную:': 'or paste a key manually:',
  'ключ vless://…@host:443 из бота': 'vless://…@host:443 key from the bot',
  'Войти': 'Sign in',
  'Ключ в боте': 'Key in the bot',
  'подписка': 'subscription',
  'истекла': 'expired',
  'активна': 'active',
  'не активна': 'inactive',
  'Продлить': 'Renew',
  'Обновить': 'Refresh',
  'ключ доступа': 'access key',
  'твой ключ из аккаунта': 'your key from the account',
  'для роутера и ручной настройки': 'for routers and manual setup',
  'Скопировать': 'Copy',
  'Вставить': 'Paste',
  'Ключ': 'Key',
  'код входа': 'login code',
  'для входа в приложение — не вставляй в VPN-клиенты': "for signing into the app — don't paste into VPN clients",
  'Код входа': 'Login code',
  'Сменить': 'Change',
  'Пока нет устройств.\nПодключись с устройства — оно появится здесь.':
      "No devices yet.\nConnect from a device — it'll show up here.",
  'Устройство': 'Device',
  'Удалить устройство?': 'Remove device?',
  'Удалить': 'Remove',

  // ---- settings.dart ----
  'Тёмная': 'Dark',
  'Светлая': 'Light',
  'Системная': 'System',
  'Статистика': 'Statistics',
  'Свой конфиг': 'Custom config',
  'Свой конфиг ✓': 'Custom config ✓',
  'Вставь vless:// или другой конфиг': 'Paste vless:// or another config',
  'Сохранить': 'Save',
  'Конфиг очищен': 'Config cleared',
  'Конфиг сохранён ✓': 'Config saved ✓',
  'персонализация': 'personalization',
  'Цвет акцента': 'Accent color',
  'Кнопка подключения': 'Connect button',
  'Тема': 'Theme',
  'Язык': 'Language',
  'безопасность': 'security',
  'Блокировка входа': 'App lock',
  'PIN при открытии приложения': 'PIN when opening the app',
  'Обрыв соединения': 'Connection drop',
  'Уведомлять, если VPN отвалился': 'Notify if the VPN drops',
  'Напомнить за пару дней': 'Remind a couple days ahead',
  'Лимит трафика': 'Traffic limit',
  'Сигнал при расходе от 5 ГБ за сессию': 'Alert at 5 GB+ used per session',
  'Авто-подключение': 'Auto-connect',
  'Подключаться сразу при запуске': 'Connect right at startup',
  'инструменты': 'tools',
  'подключение': 'connection',
  'Авто': 'Auto',
  'Протокол': 'Protocol',
  'Протокол подбирается автоматически под твой ключ. Настраивать ничего не нужно.':
      'The protocol is chosen automatically from your key. Nothing to configure.',
  'Скоро 🙌': 'Soon 🙌',
  'скоро': 'soon',

  // ---- modeLabels (home) ----
  'Стрим': 'Stream',
  'Игры': 'Games',
  'Прив.': 'Private',

  // ---- btnStyleNames (settings) ----
  'Шестерёнка': 'Gear',
  'Кольцо': 'Ring',
  'Орб': 'Orb',
  'Пульс': 'Pulse',

  // ---- lock.dart ----
  'bitaps заблокирован': 'bitaps locked',
  'Введите PIN, чтобы продолжить': 'Enter your PIN to continue',
  'Разблокировать': 'Unlock',
  'Не помню PIN — выйти': 'Forgot PIN — sign out',
  'Неверный PIN': 'Wrong PIN',
  'Блокировка сброшена': 'Lock reset',
  'Задай PIN для входа': 'Set a PIN to unlock',
  'PIN (4–8 цифр)': 'PIN (4–8 digits)',
  'Повтори PIN': 'Repeat PIN',
  'Включить': 'Enable',
  'PIN — минимум 4 цифры': 'PIN must be at least 4 digits',
  'PIN не совпадает': "PINs don't match",

  // ---- faq (account) ----
  'Сколько устройств можно подключить?': 'How many devices can I connect?',
  'До 10 устройств одновременно по одной подписке.': 'Up to 10 devices at once on one subscription.',
  'Вы ведёте логи?': 'Do you keep logs?',
  'Нет. Мы не храним логи активности — только техническую информацию для работы сервиса.':
      "No. We don't store activity logs — only technical info to run the service.",
  'Как продлить подписку?': 'How do I renew my subscription?',
  'В «Кабинете» нажми «Продлить» — оплата через Telegram, СБП или крипту.':
      'In "Account" tap "Renew" — pay via Telegram, SBP or crypto.',
  'VPN не подключается?': "VPN won't connect?",
  'Смени локацию, проверь интернет и что подписка активна. Не помогло — напиши в поддержку.':
      'Switch location, check your internet and that your subscription is active. Still stuck — message support.',
};
