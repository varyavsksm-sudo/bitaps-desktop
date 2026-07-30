# bitaps VPN — iOS (App Store): путь к релизу

Этот комплект делает iOS-сборку из Flutter-приложения + NetworkExtension (Xray-core).

## Что уже сделано в репо
- `lib/` — приложение: подписка → `xrayConfigJsonForIos()` (конфиг с tun-входом),
  `engine.dart` (iOS → `NativeTunnel.connect`), `native_tunnel.dart` (контракт канала).
- `native_ios/AppDelegate.swift` — MethodChannel `app.bitaps.vpn/control`: connect (конфиг →
  файл в App Group-контейнере под NSFileProtectionComplete → старт менеджера), disconnect
  (файл конфига удаляется); EventChannel `app.bitaps.vpn/events` — статусы только по факту
  NEVPNStatusDidChange, а не по запросу start/stop.
- `native_ios/PacketTunnel/` — провайдер туннеля (libXray `Invoke(runXrayFromJson)`, fd через
  `env["xray.tun.fd"]`, IPv4 + IPv6 зеркалом), Info.plist, entitlements.
- `native_ios/Runner.entitlements` — packet-tunnel + App Group (ничего лишнего).
- `tools/fetch-libxray.sh` — скачивает `LibXray.xcframework` из релизов XTLS/libXray.
- CI (`build.yml`, job `ios`): генерирует `ios/` заново, накатывает `native_ios/` поверх и
  компилирует без подписи — ловит ошибки сборки раньше Xcode.

Платформенной папки `ios/` в git НЕТ (см. .gitignore): она генерируется `flutter create`,
а наши нативные файлы накатываются поверх из `native_ios/` — ровно как делает CI. Поэтому
путей вида `ios/Runner/...` в репо нет; они появляются после шага 1.

## Что нужно тебе (один раз)
1. **Apple Developer Program — ОРГАНИЗАЦИЯ** ($99/год; для VPN нужна именно организация,
   Guideline 5.4). Если D-U-N-S нет — получить заранее (1–2 недели бесплатно на сайте Apple).
2. Mac с Xcode 16+ (у тебя macOS есть — поставь Xcode из App Store).
3. Клон репо: `git clone https://github.com/varyavsksm-sudo/bitaps-desktop.git`

## Шаги к TestFlight (30–60 минут)
1. Сгенерируй платформенную папку (как в CI, `build.yml` job `ios`):
   `flutter create --org com.bitapsvpn --platforms=ios --project-name bitaps_vpn .`
2. Накати нативную сторону поверх сгенерированного `ios/` (как в CI):
   ```
   cp native_ios/AppDelegate.swift ios/Runner/AppDelegate.swift
   cp native_ios/Runner.entitlements ios/Runner/Runner.entitlements
   cp -R native_ios/PacketTunnel ios/PacketTunnel
   ```
3. В `ios/Runner/Info.plist` пропиши ответ про шифрование (вопрос ревью App Store):
   `<key>ITSAppUsesNonExemptEncryption</key><false/>` — в entitlements этот ключ инертен,
   работает только в Info.plist; шифрование стандартное (TLS/REALITY, §740.13(b)).
4. `bash tools/fetch-libxray.sh` — положит `ios/Frameworks/LibXray.xcframework`.
5. `flutter pub get`, затем почини podspec flutter_v2ray_client (как в CI): пакет переименовал
   плагин, но не podspec — podhelper ищет `flutter_v2ray_client.podspec`, а лежит
   `flutter_v2ray.podspec`, и `pod install` падает:
   ```
   P="$(find ~/.pub-cache/hosted -maxdepth 4 -type d -name ios -path "*flutter_v2ray_client*" | head -1)"
   cp "$P/flutter_v2ray.podspec" "$P/flutter_v2ray_client.podspec"
   ```
6. Открой `ios/Runner.xcworkspace` в Xcode.
7. **Team**: на обоих таргетах (Runner, PacketTunnel) выбери свою команду (автоматическая подпись).
8. **Таргет PacketTunnel**: File → New → Target → Network Extension → Packet Tunnel
   - Bundle ID: `com.bitapsvpn.bitapsVpn.PacketTunnel`
   - Замени его `PacketTunnelProvider.swift` нашим из `ios/PacketTunnel/`, подложи Info.plist
     и PacketTunnel.entitlements (оба уже на месте после шага 2 — назначь в Build Settings/General).
   - В Runner → Frameworks, Libraries: перетащи `LibXray.xcframework` (Embed & Sign) в **PacketTunnel**.
   - Runner → Signing & Capabilities: App Groups → `group.com.bitapsvpn.bitapsVpn`
     (должна совпадать у обоих таргетов — уже в entitlements).
   - В Runner General → Frameworks: добавь PacketTunnel.appex в Embed App Extensions.
9. Product → Archive → Distribute App → App Store Connect → Upload.
10. App Store Connect: новое приложение (bundle `com.bitapsvpn.bitapsVpn`), категория Utilities,
    скопируй листинг из `store/app-store/listing.md`, приватность — из `store/app-store/app-privacy.md`,
    скриншоты — по `store/assets-spec.md`.
11. Ревью: демо-аккаунт — тестовая подписка из админ-панели бота + заметка из app-privacy.md.

## Заметки
- Покупок в приложении НЕТ (подписка и оплата — в Telegram-боте, reader-app модель как у Netflix).
- Если ревью спросит — `ITSAppUsesNonExemptEncryption=false` прописан в `ios/Runner/Info.plist`
  (шаг 3); шифрование стандартное (TLS/REALITY, §740.13(b)).
- Сборка в CI без подписи — дым-тест компиляции; релизная подпись — только через твою команду в Xcode.
