; ============================================================
; ScanFlow — Instalador Inno Setup
; Fuente: build\windows\x64\runner\Release\
; Salida: build\installer\scanflow-setup-{#MyAppVersion}.exe
; ============================================================
#define MyAppName "ScanFlow"
#define MyAppPublisher "cl.bodega"
#define MyAppVersion "1.0.1"
#define MyAppExeName "scanflow.exe"
[Setup]
AppId={{FE6004E3-1E52-42F6-8A4B-C23CDC4D2E2C}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\ScanFlow
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\build\installer
OutputBaseFilename=scanflow-setup-{#MyAppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
WizardSizePercent=120
DisableWelcomePage=no
; Opcional: firma Authenticode
;SignTool=MSSigner

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "Crear acceso directo en el escritorio"; GroupDescription: "Accesos directos:"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Iniciar {#MyAppName}"; Flags: nowait postinstall skipifsilent