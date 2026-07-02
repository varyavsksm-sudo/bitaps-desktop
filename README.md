# bitaps VPN — единый клиент (Flutter, все платформы)

**Это единственная активная кодовая база клиента bitaps VPN.** Один `lib/main.dart` собирается под
**Windows / Linux / macOS / Android / iOS** (сборки — GitHub Actions → [Releases](../../releases/latest)).

> ### Одна база вместо двух
> Раньше существовал параллельный нативный клиент на Swift/SwiftUI (`bitaps-vpn-app`, iOS+macOS).
> Он **заморожен и переведён в архив** — весь продукт ведём здесь, на Flutter, чтобы поддержка не двоилась.
> Swift-репо оставлен только как **референс дизайна и готового нативного PacketTunnel** (пригодится при
> подключении боевого туннеля на Apple, см. `TUNNEL.md`). Ценные фичи, которых тут ещё нет,
> переносим по чек-листу — `PORT-FROM-SWIFT.md`. Новых коммитов в Swift-репо не вносить.

## Скачать
- **Windows:** [bitaps-windows-x64.zip](../../releases/latest/download/bitaps-windows-x64.zip)
- **Linux:** [bitaps-linux-x64.tar.gz](../../releases/latest/download/bitaps-linux-x64.tar.gz)
- **macOS / Android / iOS(Happ):** см. [app.html](https://bitapsvpn.com/app.html)

## Статус
UI готов на всех платформах, импорт ключа/вход через Telegram работают. **Реальное подключение**
(VLESS + Reality через sing-box) включается флагом `kRealTunnel` в `lib/models.dart` — как только на
платформе подключена нативная сторона туннеля (`TUNNEL.md`). Пока боевого сервера нет — демо-режим
с честной пометкой в UI (фейкового «Подключено» не показываем).

## Структура кода
- `lib/main.dart` — `_ShellState`: навигация, вход/подписка, настройки, персонализация.
- `lib/connection.dart` — **`ConnectionController`**: жизненный цикл туннеля (connect/disconnect,
  поколения, таймеры, статистика, лимит трафика). Вынесен из `_ShellState`, чтобы состояние
  подключения не жило в god-object; UI обновляется через `ChangeNotifier`.
- `lib/singbox_config.dart` — генератор sing-box JSON из ключа (vless/reality и др.). Готов.
- `lib/native_tunnel.dart` — мост к нативному движку (`MethodChannel`/`EventChannel`).
- `lib/screens/*` — экраны (Главная / Серверы / Кабинет / Настройки), `part of main.dart`.

## Локальная сборка
```
flutter pub get
flutter run -d macos     # или windows / linux / <device>
```
