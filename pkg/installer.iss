; Inno Setup — установщик bitaps VPN для Windows
[Setup]
AppName=bitaps VPN
AppVersion=0.1.0
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
