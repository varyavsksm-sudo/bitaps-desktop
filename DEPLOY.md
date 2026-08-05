# Раздача Windows-билда: SmartScreen и снятие метки «небезопасный файл»

Билд не подписан Authenticode-сертификатом, поэтому Windows SmartScreen и Chrome
могут помечать `bitaps-setup.exe` / `bitaps-windows-x64.zip` как небезопасные.
Полностью это лечится только подписью кода (см. ниже), но метку с конкретной
сборки можно снять вручную через Microsoft.

## Подача файла в Microsoft WDSI (file submission)

Делает владелец от своей учётной записи Microsoft после каждой заметной смены
хэша релизного файла (метка привязана к хэшу — новая сборка = новая подача,
поэтому имеет смысл подавать стабильный релиз, а не каждую CI-сборку `latest`).

1. Открыть https://www.microsoft.com/en-us/wdsi/filesubmission
2. Войти под учётной записью Microsoft (личной или рабочей).
3. Выбрать тип подачи: **«I believe this file is incorrectly detected»** /
   **false positive** (если спрашивают роль — «software developer / publisher»).
4. Заполнить поля:
   - **Product name**: `bitaps VPN`
   - **File**: приложить `bitaps-setup.exe` из GitHub Releases (или указать его
     SHA256 из `SHA256SUMS.txt` — там эталонный хэш релизной сборки)
   - **Detection / signature name**: `SmartScreen` / «reputation-based warning»
     (если есть конкретное имя детекции из сообщения Windows — указать его)
   - **Is the file signed?**: unsigned («файл не подписан, сертификат в процессе
     приобретения»)
   - **Publisher / company**: `bitaps`
   - **Comments / additional info**: приложение с открытым исходным кодом,
     распространяется через GitHub Releases:
     `https://github.com/<org>/<repo>/releases` — указать реальный URL репозитория;
     сборка воспроизводится публичным workflow `.github/workflows/build.yml`.
5. Отправить и дождаться письма с номером обращения. Обычно разбор занимает от
   нескольких часов до нескольких дней; при отказе подать повторно с комментарием.

Пока метка не снята, пользователю помогает: сверка SHA256 скачанного файла с
`SHA256SUMS.txt` из релиза (`Get-FileHash .\bitaps-setup.exe`) и запуск через
«Подробнее → Выполнить в любом случае» в диалоге SmartScreen.

## Подпись кода (окончательное лекарство)

Репутационная метка SmartScreen окончательно снимается только Authenticode-подписью:

- **EV code-signing сертификат** — даёт мгновенную репутацию SmartScreen без
  накопления истории. Рекомендуемый вариант.
- **OV (стандартный) сертификат** — дешевле, но репутация накапливается
  постепенно по мере установок подписанных билдов.

Инфраструктура подписи в CI уже готова: шаги «Подписать exe (если есть
сертификат)» и «Подписать установщик (если есть сертификат)» в
`.github/workflows/build.yml` подписывают `bitaps_vpn.exe`, `xray.exe` и
`bitaps-setup.exe` через signtool (sha256 + timestamp digicert). Сейчас они
пропускаются, потому что секретов нет. После покупки сертификата владельцу нужно
только добавить в Settings → Secrets and variables → Actions:

- `WINDOWS_CERT_BASE64` — содержимое `.pfx` в base64
  (`base64 -i cert.pfx | pbcopy` на macOS)
- `WINDOWS_CERT_PASSWORD` — пароль от `.pfx`

Никаких правок workflow не потребуется — следующая сборка выйдет подписанной.

## Что уже сделано в сборке для смягчения SmartScreen

- В exe внедряется VERSIONINFO: CompanyName `bitaps`, ProductName `bitaps VPN`,
  FileDescription `bitaps VPN Client`, LegalCopyright, FileVersion/ProductVersion
  из версии приложения (шаг «VERSIONINFO … в Runner.rc» в build.yml).
- В релиз выкладывается `SHA256SUMS.txt` с контрольными суммами артефактов.
- Установщик (Inno Setup) собирается с `AppPublisher=bitaps`, зафиксированным `AppId`
  (обновление встаёт поверх) и версией из pubspec + номера прогона (шаг «AppVersion в
  installer.iss» в build.yml). Деинсталлятор сам прибирает системный прокси (только наш,
  127.0.0.1), автозапуск, схему bitaps:// и процессы из папки установки
  (см. `pkg/installer.iss`, секция [Code]).
