; =============================================================================
; kit-bootstrap / windows / hub-setup.iss
;
; The wizard. Compiling this file produces HubSetup.exe, which is an ordinary
; Windows installer: double-click it, click Next, it works out for itself
; whether this PC needs a first install or an update.
;
; Why: the only Windows route before this was pasting a long line into
; PowerShell. That is fine for the person who wrote it and a wall for everybody
; else, and readers of the book are everybody else.
;
; It asks for no administrator rights of its own (PrivilegesRequired=lowest).
; That is not politeness, it is correctness: an installer running as a different
; account writes the shared-memory link into the WRONG user's profile, and the
; result looks like it worked. Windows still raises its own prompt when it
; installs Git or Node.js, which is normal and expected.
;
; Build it with:  powershell -File build-installer.ps1
; =============================================================================

#define AppName        "Hub"
#define AppVersion     "1.0.0"
#define AppPublisher   "Michael Zelbel"
#define AppURL         "https://github.com/MichaelZelbel/kit-bootstrap"

[Setup]
AppId={{7B3C1E64-9A55-4E1D-9D6C-2F0B8A4C51D7}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
VersionInfoVersion={#AppVersion}
VersionInfoDescription=Sets up your hub on this PC
DefaultDirName={localappdata}\Hub\installer
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
DisableDirPage=yes
PrivilegesRequired=lowest
OutputBaseFilename=HubSetup
OutputDir=dist
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName={#AppName}
; The wizard says almost nothing on its own. The work prints its own progress in
; a console window, because installing Node.js can take minutes and a still
; progress bar reads as a crash.
SetupLogging=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "setup-hub.ps1"; DestDir: "{app}"; Flags: ignoreversion
; A copy of the shared install code, so a PC with no internet still gets set up.
; At run time the network copy is preferred - see the comment in setup-hub.ps1.
Source: "..\join.ps1";   DestDir: "{app}"; Flags: ignoreversion
; Needed before the wizard starts, to see whether this PC already has a hub.
Source: "..\join.ps1";   DestDir: "{tmp}";  Flags: dontcopy

[Icons]
; So the next update is a Start Menu click and never a typed command again.
Name: "{group}\Update my hub"; Filename: "powershell.exe"; \
    Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\setup-hub.ps1"""; \
    Comment: "Bring this PC's hub up to date"
Name: "{group}\Open my hub folder"; Filename: "{code:GetHubDir}"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"

[Run]
Filename: "powershell.exe"; \
    Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\setup-hub.ps1"" -NoPause -Hub ""{code:GetHubDir}"" -RepoUrl ""{code:GetRepoUrl}"""; \
    StatusMsg: "Setting up your hub. This can take a few minutes, and a window will show what it is doing..."; \
    Flags: waituntilterminated
Filename: "{code:GetHubDir}"; Description: "Open my hub folder"; \
    Flags: postinstall shellexec nowait unchecked

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Messages]
; Said on the last page of the uninstaller, because the one thing people fear
; here is losing the memory, and they should be told plainly that they have not.
ConfirmUninstall=This removes the setup program only.%n%nYour hub folder, and everything your assistants have learned, stays exactly where it is. Nothing you have written is deleted.%n%nRemove the setup program?

[Code]
var
  HubPage: TInputQueryWizardPage;
  FoundHub: String;

{ Ask the shared install code where the hub is, rather than writing a second
  copy of that search in Pascal. Two copies of a search is how they drift. }
function DetectHub(): String;
var
  PsFile, OutFile, Cmd: String;
  Code: Integer;
  Lines: TArrayOfString;
begin
  Result := '';
  ExtractTemporaryFile('join.ps1');
  PsFile  := ExpandConstant('{tmp}\join.ps1');
  OutFile := ExpandConstant('{tmp}\hub-found.txt');

  Cmd := '-NoProfile -ExecutionPolicy Bypass -Command "'
       + '. ''' + PsFile + ''' -AsLibrary; '
       + '$h = Find-KitHub; '
       + 'if ($h) { Set-Content -LiteralPath ''' + OutFile + ''' -Value $h }"';

  if Exec('powershell.exe', Cmd, '', SW_HIDE, ewWaitUntilTerminated, Code) then
    if FileExists(OutFile) then
      if LoadStringsFromFile(OutFile, Lines) then
        if GetArrayLength(Lines) > 0 then
          Result := Trim(Lines[0]);
end;

procedure InitializeWizard();
begin
  FoundHub := DetectHub();

  HubPage := CreateInputQueryPage(wpWelcome,
    'Where your hub goes',
    'This PC has not got a hub yet, so I am about to make one.',
    'A hub is one folder holding everything your AI assistants know about you and your work.' + #13#10 + #13#10 +
    'If you already keep a hub in a git repository, paste its address in the second box and I will fetch that one instead of starting an empty one. Leave the box empty if today is day one.');
  HubPage.Add('Folder on this PC:', False);
  HubPage.Add('Address of a hub you already have (optional):', False);
  HubPage.Values[0] := 'C:\hub';
  HubPage.Values[1] := '';
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  { A PC that already has a hub is never asked where to put one. }
  Result := (PageID = HubPage.ID) and (FoundHub <> '');
end;

function GetHubDir(Param: String): String;
begin
  if FoundHub <> '' then
    Result := FoundHub
  else
    Result := Trim(HubPage.Values[0]);
  if Result = '' then Result := 'C:\hub';
end;

function GetRepoUrl(Param: String): String;
begin
  if FoundHub <> '' then
    Result := ''
  else
    Result := Trim(HubPage.Values[1]);
end;

{ The Ready page should say which of the two jobs is about to happen, in words a
  person can act on, because this is the last moment they can stop it. }
function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo,
  MemoTypeInfo, MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
begin
  if FoundHub <> '' then
    Result := 'This PC already has a hub, so I am going to UPDATE it:' + NewLine + NewLine
            + Space + FoundHub + NewLine + NewLine
            + 'I will fetch the latest of it, make sure this PC shares one memory with your other machines, and put the hub commands within reach here.'
  else
  begin
    Result := 'This PC has no hub, so I am going to INSTALL one:' + NewLine + NewLine
            + Space + GetHubDir('') + NewLine + NewLine;
    if GetRepoUrl('') <> '' then
      Result := Result + 'It will be fetched from:' + NewLine + Space + GetRepoUrl('') + NewLine + NewLine;
    Result := Result + 'I will also install anything missing that it needs: Git, Node.js and Claude Code. Windows may ask your permission for those, which is normal.';
  end;
end;
