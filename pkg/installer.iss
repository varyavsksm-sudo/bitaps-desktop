; Inno Setup — установщик bitaps VPN для Windows
[Setup]
; AppId ЗАФИКСИРОВАН: по нему Windows связывает установки — обновление встаёт поверх, а не
; рядом, и деинсталлятор находит именно наше приложение. НЕ МЕНЯТЬ между версиями, иначе
; старая копия перестанет обновляться/удаляться штатно (у пользователя окажется две записи).
AppId={{9E3D25FA-A056-4C77-95BF-966C26FED0AB}
AppName=bitaps VPN
; Версия подставляется CI из pubspec.yaml + номер прогона (шаг «AppVersion в installer.iss»
; в .github/workflows/build.yml) — здесь заглушка для локальной сборки.
AppVersion=1.0.0
AppPublisher=bitaps
DefaultDirName={autopf}\bitaps VPN
DefaultGroupName=bitaps VPN
DisableProgramGroupPage=yes
OutputBaseFilename=bitaps-setup
SourceDir=..
OutputDir=.
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
UninstallDisplayName=bitaps VPN

[Languages]
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs

[Icons]
Name: "{group}\bitaps VPN"; Filename: "{app}\bitaps_vpn.exe"
Name: "{autodesktop}\bitaps VPN"; Filename: "{app}\bitaps_vpn.exe"

[Run]
Filename: "{app}\bitaps_vpn.exe"; Description: "Запустить bitaps VPN"; Flags: nowait postinstall skipifsilent

[Code]
// Уборка при удалении: приложение держит системные настройки ВНЕ папки установки
// (системный прокси, автозапуск, схема bitaps://), и Inno про них не знает — без этого
// после деинсталляции у человека оставался бы прокси в мёртвый порт («нет интернета»),
// мёртвая запись автозапуска и висящая ассоциация схемы.
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ProxyServer: String;
  Ps: String;
  ResultCode: Integer;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    // Системный прокси: снимаем ТОЛЬКО если он наш (указывает на 127.0.0.1) — чужие
    // настройки пользователя не трогаем. ProxyOverride намеренно не чистим: с ProxyEnable=0
    // он инертен, а восстановить чужое значение здесь всё равно неоткуда (снимок жил в
    // памяти приложения).
    if RegQueryStringValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        'ProxyServer', ProxyServer) then
      if Pos('127.0.0.1', ProxyServer) > 0 then
        RegWriteDWordValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Internet Settings',
          'ProxyEnable', 0);
    // Автозапуск при входе (launch_at_startup пишет в HKCU\...\Run; имя значения — AppName
    // из package_info: после VERSIONINFO-патча это «bitaps VPN», до него было «bitaps_vpn» —
    // снимаем оба варианта, чтобы не осталось мёртвой записи ни у одной из версий).
    RegDeleteValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', 'bitaps VPN');
    RegDeleteValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', 'bitaps_vpn');
    // Схема bitaps:// (lib/native.dart регистрирует при первом запуске).
    RegDeleteKeyIncludingSubkeys(HKCU, 'Software\Classes\bitaps');
    // Уцелевшие процессы ИЗ ПАПКИ УСТАНОВКИ: xray.exe мог пережить завершение приложения
    // (туннель-сирота), а сам bitaps_vpn.exe — ещё работать. Добиваем ТОЛЬКО по совпадению
    // пути с {app}: чужой xray (Happ и т.п.) не трогаем. wmic в новых Windows 11 может
    // отсутствовать — PowerShell + CIM, окно скрыто.
    Ps := 'Get-CimInstance Win32_Process | Where-Object { ($_.Name -eq ''xray.exe'' -or ' +
      '$_.Name -eq ''bitaps_vpn.exe'') -and ($_.ExecutablePath -like ''' +
      ExpandConstant('{app}') + '\*'') } | ForEach-Object { Stop-Process -Id $_.ProcessId ' +
      '-Force -ErrorAction SilentlyContinue }';
    Exec('powershell.exe', '-NoProfile -WindowStyle Hidden -Command "' + Ps + '"',
      '', SW_HIDE, ewNoWait, ResultCode);
  end;
end;
