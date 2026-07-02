# bitaps VPN — нативный туннель (интеграционный контракт)

Клиент (Flutter) больше НЕ рисует фейковый коннект. Подключение идёт через нативный движок
sing-box по каналам платформы. Пока нативная сторона не подключена — `connect()` честно бросает
`TunnelUnavailable`, и UI показывает ошибку вместо «Подключено».

## Как это устроено в Dart

- `lib/native_tunnel.dart` — мост:
  - `MethodChannel('app.bitaps.vpn/control')` — методы `connect({config, server})` и `disconnect()`.
  - `EventChannel('app.bitaps.vpn/events')` — поток `{state, down, up}` от движка (state:
    `connecting|connected|disconnected|error`, down/up — kbps).
- `lib/singbox_config.dart` — генерит sing-box JSON из `vpn_key` (vless/reality и др.). Уже готов.
- `lib/main.dart` → `toggle()`:
  - `kRealTunnel=true` → строит конфиг, зовёт `NativeTunnel.connect`, `conn=2` ТОЛЬКО при реальном
    успехе; скорость/статус берёт из `events()` (без выдуманных чисел); обрыв → снимает «подключено».
  - `kRealTunnel=false` → демо-сессия с явной пометкой «демо» в UI (не защита).
- Переключатель: `lib/models.dart` → `const bool kRealTunnel`. Ставить `true` на платформе, где
  подключена нативная сторона ниже.

Нативная сторона на канале `app.bitaps.vpn/control` должна реализовать:
- `connect`: принять `config` (JSON) + `server`, запустить движок, поднять TUN. Ошибку вернуть как
  `PlatformException` (Dart превратит в `TunnelUnavailable`).
- `disconnect`: остановить движок и TUN.
- слать на `app.bitaps.vpn/events` мапы `{state, down, up}`.

## Что осталось по платформам

### Apple (iOS/macOS) — БЛИЖЕ ВСЕГО к бою
Готовый движок уже собран: `~/bitaps-libbox/Libbox.xcframework` (gomobile-билд sing-box, есть срезы
ios-arm64, ios-sim, macos, tvos). Готовая реализация extension уже написана в Swift-приложении
`~/bitaps-vpn-app`:
- `PacketTunnel/PacketTunnelProvider.swift` — `NEPacketTunnelProvider`, при слинкованной `Libbox`
  делает `LibboxSetup` → `LibboxNewCommandServer` → `startOrReloadService(config)` (реальный туннель),
  а без движка честно отказывается (не блокирует трафик).
- `Sources/Core/Services/SingBoxConfig.swift` — генератор конфига из ключа.

Чтобы завести на этом (Flutter) раннере:
1. Добавить в macOS/iOS-раннер **app-extension таргет** `PacketTunnel` (bundle
   `app.bitaps.vpn.PacketTunnel`), перенести туда файлы из `~/bitaps-vpn-app/PacketTunnel`.
2. Слинковать `Libbox.xcframework` в этот таргет (Embed & Sign).
3. Включить capability **Network Extensions → Packet Tunnel** и **App Group** у раннера и extension.
4. В `macos/Runner`/`ios/Runner` реализовать `FlutterMethodChannel('app.bitaps.vpn/control')`, который
   через `NETunnelProviderManager` стартует/останавливает провайдер и прокидывает `config`
   (та же логика, что `SingBoxTunnel.swift` в Swift-приложении — можно переиспользовать целиком).
5. `EventChannel('app.bitaps.vpn/events')` кормить из `handleAppMessage`/статуса `NEVPNStatus`.

⚠️ Требует **платного Apple Developer**: NetworkExtension-entitlement и подпись extension-таргета
без него не собрать/не запустить. Это единственный внешний блокер Apple-пути — код уже есть.

### Android
1. `VpnService`-подкласс, поднимающий `tun` fd.
2. Движок: gomobile-сборка sing-box `libbox` под Android (`.aar`) — её пока НЕТ в репозитории (в
   отличие от Apple xcframework). Собрать `gomobile bind` из `github.com/SagerNet/sing-box`.
3. `MethodChannel('app.bitaps.vpn/control')` в `MainActivity` → запрос разрешения VPN, старт сервиса,
   передача `config` в libbox; статистику слать в `EventChannel`.

### Windows / Linux (десктоп)
1. Положить рядом бинарь `sing-box`.
2. Нативный плагин запускает процесс `sing-box run -c <config>` (Windows: драйвер `wintun`; Linux:
   `tun` + root/`CAP_NET_ADMIN`), парсит его stats API для `events`.

## Итог
Dart-слой и Swift-extension — код-полные. «Настоящий VPN» упирается в сборочно-подписные шаги
(Apple-аккаунт, gomobile-.aar под Android), которые не делаются из CLI — только в Xcode/Android Studio
на машине разработчика.
