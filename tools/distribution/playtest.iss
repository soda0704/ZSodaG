#ifndef GameVersion
  #error GameVersion must be supplied by build_playtest.py
#endif
#ifndef PackageName
  #error PackageName must be supplied by build_playtest.py
#endif
#ifndef PayloadDir
  #error PayloadDir must be supplied by build_playtest.py
#endif
#ifndef OutputDir
  #error OutputDir must be supplied by build_playtest.py
#endif

[Setup]
AppId={{D9F859C5-5658-498B-9794-19C15B3B8B2C}
AppName=NorthernLab Playtest
AppVersion={#GameVersion}
AppPublisher=NorthernLab
DefaultDirName={localappdata}\Programs\NorthernLab Playtest
DefaultGroupName=NorthernLab Playtest
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
DisableProgramGroupPage=yes
WizardStyle=modern
SetupIconFile=..\..\assets\ui\application\northernlab.ico
UninstallDisplayIcon={app}\NorthernLab.exe
OutputDir={#OutputDir}
OutputBaseFilename={#PackageName}-Setup
Compression=lzma2
SolidCompression=yes
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#PayloadDir}\*"; DestDir: "{app}"; Excludes: ".audited.json"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\NorthernLab Playtest"; Filename: "{app}\NorthernLab.exe"; WorkingDir: "{app}"
Name: "{group}\{cm:UninstallProgram,NorthernLab Playtest}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\NorthernLab Playtest"; Filename: "{app}\NorthernLab.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\NorthernLab.exe"; WorkingDir: "{app}"; Description: "{cm:LaunchProgram,NorthernLab Playtest}"; Flags: nowait postinstall skipifsilent
