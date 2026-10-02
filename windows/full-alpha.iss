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
Source: "install-full-alpha.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "start-full-alpha.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "stop-full-alpha.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "ensure-hermes-full-alpha.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "open-hermes-full-alpha.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "vendor\*"; DestDir: "{app}\vendor"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\Godspeed Mission Control Full Alpha"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\start-full-alpha.ps1"""
Name: "{group}\Godspeed Mission Control Full Alpha Assistant"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\open-hermes-full-alpha.ps1"""
[Run]
Filename: "http://127.0.0.1:47831/"; Description: "Open the alpha notebook"; Flags: shellexec postinstall skipifsilent
[UninstallRun]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\stop-full-alpha.ps1"" -Uninstall"; Flags: runhidden waituntilterminated
[Code]
var SetupFailed: Boolean;
function GetCustomSetupExitCode: Integer;
begin
  if SetupFailed then Result := 1 else Result := 0;
end;
function PrepareToInstall(var NeedsRestart: Boolean): String;
var ExitCode: Integer;
begin
  Result := '';
  if FileExists(ExpandConstant('{app}\stop-full-alpha.ps1')) then
    if not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + ExpandConstant('{app}\stop-full-alpha.ps1') + '"', '', SW_HIDE, ewWaitUntilTerminated, ExitCode) or (ExitCode <> 0) then
      Result := 'The existing candidate service could not stop. Its files were preserved.';
end;
procedure CurStepChanged(CurStep: TSetupStep);
var ExitCode: Integer;
begin
  if CurStep = ssPostInstall then
    if not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + ExpandConstant('{app}\install-full-alpha.ps1') + '" -AppRoot "' + ExpandConstant('{app}') + '"', '', SW_HIDE, ewWaitUntilTerminated, ExitCode) or (ExitCode <> 0) then
    begin
      SetupFailed := True;
      RaiseException('Candidate setup did not finish. Check its saved installation log. Your knowledge files remain available.');
    end;
end;
