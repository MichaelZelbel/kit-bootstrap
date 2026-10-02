#ifndef PayloadRoot
  #error PayloadRoot must name the verified full candidate payload
#endif
#ifndef CandidateVersion
  #define CandidateVersion "0.1.0"
#endif
[Setup]
AppId={{9929B7B4-B588-46D2-AC79-01F7EBD7FA92}
AppName=Godspeed Mission Control Full Alpha
AppVersion={#CandidateVersion}
AppPublisher=Michael Zelbel
DefaultDirName={localappdata}\Godspeed Mission Control Full Alpha
DefaultGroupName=Godspeed Mission Control Full Alpha
PrivilegesRequired=lowest
DisableProgramGroupPage=yes
OutputDir=dist
OutputBaseFilename=GodspeedSetup-Full-Alpha
Compression=lzma2
SolidCompression=yes
UninstallDisplayName=Godspeed Mission Control Full Alpha
CloseApplications=no
RestartApplications=no
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
[Files]
Source: "{#PayloadRoot}\*"; DestDir: "{app}\payload"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "setup-full-alpha.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "start-full-alpha.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "stop-full-alpha.ps1"; DestDir: "{app}"; Flags: ignoreversion
[Icons]
Name: "{group}\Godspeed Mission Control Full Alpha"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\start-full-alpha.ps1"""
[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\setup-full-alpha.ps1"" -AppRoot ""{app}"""; Flags: runhidden waituntilterminated
Filename: "http://127.0.0.1:47831/"; Description: "Open the alpha notebook"; Flags: shellexec postinstall skipifsilent
[UninstallRun]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\stop-full-alpha.ps1"" -Uninstall"; Flags: runhidden waituntilterminated
