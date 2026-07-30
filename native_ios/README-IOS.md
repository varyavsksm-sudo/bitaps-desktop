# bitaps VPN — iOS (App Store): путь к релизу

Этот комплект делает iOS-сборку из Flutter-приложения + NetworkExtension (Xray-core).

## Что уже сделано в репо
- `lib/` — приложение: подписка → `xrayConfigJsonForIos()` (конфиг с tun-входом),
  `engine.dart` (iOS → `NativeTunnel.connect`), `native_tunnel.dart` (контракт канала).
- `ios/Runner/AppDelegate.swift` — MethodChannel `app.bitaps.vpn/control`: connect (конфиг →
  App Group → старт менеджера), disconnect; EventChannel `app.bitaps.vpn/events`.
- `ios/PacketTunnel/` — провайдер туннеля (libXray `Invoke(runXrayFromJson)`, fd через
  `env["xray.tun.fd"]`), Info.plist, entitlements.
- `ios/Runner/Runner.entitlements` — packet-tunnel + App Group + allow-vpn + ITSAppUsesNonExemptEncryption=false.
- `tools/fetch-libxray.sh` — скачивает `LibXray.xcframework` из релизов XTLS/libXray.
- CI (`build.yml`, job `ios`): компилирует приложение без подписи и ловит ошибки сборки раньше Xcode.

## Что нужно тебе (один раз)
1. **Apple Developer Program — ОРГАНИЗАЦИЯ** ($99/год; для VPN нужна именно организация,
   Guideline 5.4). Если D-U-N-S нет — получить заранее (1–2 недели бесплатно на сайте Apple).
2. Mac с Xcode 16+ (у тебя macOS есть — поставь Xcode из App Store).
3. Клон репо: `git clone https://github.com/varyavsksm-sudo/bitaps-desktop.git`

## Шаги к TestFlight (30–60 минут)
1. `bash tools/fetch-libxray.sh` — положит `ios/Frameworks/LibXray.xcframework`.
2. Открой `ios/Runner.xcworkspace` в Xcode.
3. **Team**: на обоих таргетах (Runner, PacketTunnel) выбери свою команду (автоматическая подпись).
4. **Таргет PacketTunnel**: File → New → Target → Network Extension → Packet Tunnel
   - Bundle ID: `com.bitapsvpn.bitapsVpn.PacketTunnel`
   - Замени его `PacketTunnelProvider.swift` нашим из `ios/PacketTunnel/`, подложи Info.plist
     и PacketTunnel.entitlements (оба уже в репо — назначь в Build Settings/General).
   - В Runner → Frameworks, Libraries: перетащи `LibXray.xcframework` (Embed & Sign) в **PacketTunnel**.
   - Runner → Signing & Capabilities: App Groups → `group.com.bitapsvpn.bitapsVpn`
     (должна совпадать у обоих таргетов — уже в entitlements).
   - В Runner General → Frameworks: добавь PacketTunnel.appex в Embed App Extensions.
5. Product → Archive → Distribute App → App Store Connect → Upload.
6. App Store Connect: новое приложение (bundle `com.bitapsvpn.bitapsVpn`), категория Utilities,
   скопируй листинг из `store/app-store/listing.md`, приватность — из `store/app-store/app-privacy.md`,
   скриншоты — по `store/assets-spec.md`.
7. Ревью: демо-аккаунт — тестовая подписка из админ-панели бота + заметка из app-privacy.md.

## Заметки
- Покупок в приложении НЕТ (подписка и оплата — в Telegram-боте, reader-app модель как у Netflix).
- Если ревью спросит — `ITSAppUsesNonExemptEncryption=false` уже в Runner.entitlements;
  шифрование стандартное (TLS/REALITY, §740.13(b)).
- Сборка в CI без подписи — дым-тест компиляции; релизная подпись — только через твою команду в Xcode.
