# App Store — ответы App Privacy (секция конфиденциальности в App Store Connect)

Приложение не содержит рекламы, аналитики и трекеров. Продажи — через Telegram-бота/сайт.

## Data Linked to You (связано с вами)
- **Identifiers → User ID**: Telegram ID аккаунта и UUID подписки.
  - Purpose: App Functionality (лицензия, выдача конфигурации).
- **Identifiers → Device ID**: случайная строка x-hwid, генерируемая на устройстве при первом запуске (не IDFA, не hardware fingerprint).
  - Purpose: App Functionality (лимит устройств на аккаунте).

## Data Not Linked to You
- Ничего.

## Data Used to Track You
- НЕТ (не используется для трекинга рекламы — ATT-запрос не требуется).

## Общие ответы
- Собираемые данные не продаются и не передаются третьим сторонам.
- Весь трафик зашифрован в пути.
- Удаление аккаунта и данных — по запросу в поддержку (@bitapssupport); выгрузка — export-data в кабинете.
- Privacy Nutrition Label URL (политика): https://bitapsvpn.com/privacy.html

## Экспортное соответствие (Encryption)
- Вопрос «Does your app use encryption?» — **Да, но подпадает под исключение**: приложение использует
  стандартные протоколы (TLS 1.3, REALITY, AEAD) — массовое/стандартное шифрование
  (ITSAppUsesNonExemptEncryption = **false** в Info.plist, стандартная практика для VPN).
  Если Apple попросит — самоклассификация ERN §740.13(b)(1) (стандартный TLS для аутентификации).
- Добавить в Info.plist приложения: `ITSAppUsesNonExemptEncryption = false`.

## Возрастной рейтинг
- 4+ (нет UGC, нет контента для взрослых).

## Ревью: что приложить
- Demo-аккаунт (тестовая подписка — выдать через админ-панель бота).
- Примечание для ревьюера: «Вход в приложение — кодом из Telegram-бота или демо-аккаунтом
  (вложен). Покупок в приложении нет; подписка управляется в Telegram-боте (внешний сервис,
  как Netflix-style reader app). VpnService/NetworkExtension используется для туннеля (xray-core,
  MPL-2.0/MIT компоненты, список в pkg/THIRD-PARTY.md)».
- Скрин записи подключения (опционально).

## Правовое
- Категория: **Utilities**.
- Требуется аккаунт **Organization** (не Individual!) — Guideline 5.4 для VPN-приложений.
- Версия 1.0.0 (build N) — соответствует CI.
