; Bloom Desk installer (Inno Setup 6)
; Build:  flutter build windows   then   ISCC installer\bloom_desk.iss
; CRT_DIR must point at the Visual C++ runtime folder, for example:
;   ISCC /DCRT_DIR="C:\Program Files\Microsoft Visual Studio\18\Community\VC\Redist\MSVC\14.52.37025\x64\Microsoft.VC145.CRT" installer\bloom_desk.iss

#define AppName "Bloom Desk"
#define AppVersion "1.0.0"
#define AppExe "bloom_desk.exe"
#define AppUrl "https://github.com/marwathebest/bloom-desk"

#ifndef CRT_DIR
  #error Pass /DCRT_DIR="...\Microsoft.VC14x.CRT" to ISCC
#endif

[Setup]
AppId={{6B3E2F4A-9C1D-4E7B-8A52-3F0D1C9B7E21}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=marwathebest
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}/issues
AppUpdatesURL={#AppUrl}/releases
; Installs for the current user only: no admin password needed
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\{#AppName}
DisableProgramGroupPage=yes
DisableDirPage=auto
OutputDir=..\dist
OutputBaseFilename=BloomDesk-Setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "arabic"; MessagesFile: "compiler:Languages\Arabic.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Visual C++ runtime, so the app opens on PCs that don't have it
Source: "{#CRT_DIR}\msvcp140.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#CRT_DIR}\vcruntime140.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#CRT_DIR}\vcruntime140_1.dll"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
