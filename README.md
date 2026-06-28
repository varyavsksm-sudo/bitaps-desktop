# bitaps VPN — десктоп-клиент (Windows / Linux)

Кроссплатформенный клиент bitaps VPN на Flutter. Сборки собираются в GitHub Actions и публикуются в [Releases](../../releases/latest).

## Скачать
- **Windows:** [bitaps-windows-x64.zip](../../releases/latest/download/bitaps-windows-x64.zip)
- **Linux:** [bitaps-linux-x64.tar.gz](../../releases/latest/download/bitaps-linux-x64.tar.gz)

## Статус
UI готов, импорт ключа есть. Реальное подключение (VLESS + Reality через sing-box) подключается вместе с запуском боевого VPN-сервера bitaps — сейчас демо-режим.

## Локальная сборка
```
flutter pub get
flutter run -d windows   # или -d linux
```
