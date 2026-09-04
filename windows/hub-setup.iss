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
#define AppVersion     "2.3.1"
; THE PIN. The kit-bootstrap tag this .exe carries and fetches from, so a reader runs
; exactly the code that passed its runs. build-installer.ps1 refuses to build unless this
; tag exists and names the very commit being built, which is what stops it drifting from
; the .exe it labels. install-hub.sh carries the same pin for macOS and Linux.
#define KbPin         "v2.7"
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
    Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\setup-hub.ps1"" -KbBranch ""{#KbPin}"""; \
    Comment: "Bring this PC's hub up to date"
Name: "{group}\Open my hub folder"; Filename: "{code:GetHubDir}"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"

[Run]
Filename: "powershell.exe"; \
    Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\setup-hub.ps1"" -NoPause -Hub ""{code:GetHubDir}"" -RepoUrl ""{code:GetRepoUrl}"" -PromptSources ""{code:GetPromptSources}"" -KbBranch ""{#KbPin}""{code:GetBesideFlag}"; \
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
  BesidePage: TInputOptionWizardPage;
  FoundHub: String;
  { The AI-tools checklist. ToolIds/ToolNames/ToolRows describe only the rows a
    person can tick (the syncable ones); tools this kit cannot read are shown as
    disabled rows so they are seen to be seen, and never tracked here. }
  SyncPage: TInputOptionWizardPage;
  ToolIds: array of String;
  ToolNames: array of String;
  ToolRows: array of Integer;
  ToolCount: Integer;
  RecordedSources: String;

{ Field N of 'a|b|c|d'. Inno's Pascal has no split, so this walks the string. }
function PipeField(const S: String; Index: Integer): String;
var
  i, start, field: Integer;
begin
  Result := '';
  field := 0;
  start := 1;
  for i := 1 to Length(S) do
    if S[i] = '|' then
    begin
      if field = Index then
      begin
        Result := Copy(S, start, i - start);
        exit;
      end;
      field := field + 1;
      start := i + 1;
    end;
  if field = Index then
    Result := Copy(S, start, Length(S) - start + 1);
end;

function InCsv(const Csv, Id: String): Boolean;
begin
  Result := Pos(',' + Id + ',', ',' + Csv + ',') > 0;
end;

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

{ Ask the shared install code which AI tools live on this PC and what this
  device has already recorded about syncing them, same pattern as DetectHub:
  one search, written once, in the shared code. Sources comes back as '(auto)'
  when no choice was ever recorded, else as the recorded comma list ('' = none). }
procedure DetectTools(var Sources: String; var Lines: TArrayOfString);
var
  PsFile, OutFile, Cmd: String;
  Code: Integer;
  Raw: TArrayOfString;
  i, n: Integer;
begin
  Sources := '(auto)';
  SetArrayLength(Lines, 0);
  PsFile  := ExpandConstant('{tmp}\join.ps1');
  OutFile := ExpandConstant('{tmp}\ai-tools.txt');

  Cmd := '-NoProfile -ExecutionPolicy Bypass -Command "'
       + '. ''' + PsFile + ''' -AsLibrary; '
       + '$v = Get-KitDeviceEnvValue ''HUB_PROMPT_SOURCES''; '
       + 'if ($null -eq $v) { $v = ''(auto)'' } elseif ($v.Trim() -eq ''-'') { $v = '''' }; '
       + '$out = @(''sources='' + $v) + @(Find-KitAiTools); '
       + 'Set-Content -LiteralPath ''' + OutFile + ''' -Value $out"';

  if Exec('powershell.exe', Cmd, '', SW_HIDE, ewWaitUntilTerminated, Code) then
    if FileExists(OutFile) then
      if LoadStringsFromFile(OutFile, Raw) then
      begin
        n := 0;
        for i := 0 to GetArrayLength(Raw) - 1 do
          if Copy(Raw[i], 1, 8) = 'sources=' then
            Sources := Copy(Raw[i], 9, Length(Raw[i]) - 8)
          else if Trim(Raw[i]) <> '' then
          begin
            SetArrayLength(Lines, n + 1);
            Lines[n] := Raw[i];
            n := n + 1;
          end;
      end;
end;

{ One tickable row on the checklist. Remembered in the Tool* arrays so
  GetPromptSources can read the ticks back. }
procedure AddSyncRow(const Id, Caption: String);
var
  row: Integer;
begin
  row := SyncPage.Add(Caption);
  if RecordedSources = '(auto)' then
    SyncPage.Values[row] := True
  else
    SyncPage.Values[row] := InCsv(RecordedSources, Id);
  SetArrayLength(ToolIds, ToolCount + 1);
  SetArrayLength(ToolNames, ToolCount + 1);
  SetArrayLength(ToolRows, ToolCount + 1);
  ToolIds[ToolCount] := Id;
  ToolNames[ToolCount] := Copy(Caption, 1, Pos(' - ', Caption) - 1);
  ToolRows[ToolCount] := row;
  ToolCount := ToolCount + 1;
end;

procedure InitializeWizard();
var
  ToolLines: TArrayOfString;
  i, row: Integer;
  id, sync, name, note: String;
begin
  FoundHub := DetectHub();
  DetectTools(RecordedSources, ToolLines);

  { Shown only on a PC that already has a hub. Unticked, so the common path stays
    one click: a returning reader clicks Next and their hub is brought up to date,
    exactly as before this page existed. Ticked, the folder page opens and the run
    leaves all five of this PC's "which hub do I work from" settings alone. }
  BesidePage := CreateInputOptionPage(wpWelcome,
    'You already have a hub',
    'This PC works from a hub already.',
    'Clicking Next brings that hub up to date and re-checks how this PC is wired to it, which is what almost everybody wants.' + #13#10 + #13#10 +
    'Tick the box instead if you want a SECOND hub in another folder: a work hub next to a personal one, or a clean one to try something in. This PC keeps working from the hub it has, so its commands, its daily jobs and the folder your assistant starts in are left alone. The second hub gets its own folders and its own history, and you use it by opening a terminal or an assistant inside it.',
    False, False);
  BesidePage.Add('Make a second hub somewhere else, and leave this PC working from the one it has');
  BesidePage.Values[0] := False;

  HubPage := CreateInputQueryPage(BesidePage.ID,
    'Where your hub goes',
    'This PC has not got a hub yet, so I am about to make one.',
    'A hub is one folder holding everything your AI assistants know about you and your work.' + #13#10 + #13#10 +
    'The suggestion below is the top of your user folder: no administrator needed, private to you, and the same place on every computer. ' +
    'C:\hub also works if you want the shortest possible path. ' +
    'Never Documents, Desktop or Pictures: OneDrive backs those up, and a backed-up hub gets its history corrupted, so I refuse them.' + #13#10 + #13#10 +
    'If you already keep a hub in a git repository, paste its address in the second box and I will fetch that one instead of starting an empty one. Leave the box empty if today is day one.');
  HubPage.Add('Folder on this PC:', False);
  HubPage.Add('Address of a hub you already have (optional):', False);
  HubPage.Values[0] := ExpandConstant('{%USERPROFILE}\hub');
  HubPage.Values[1] := '';

  { The choice page. Everything a ticked row means is said HERE, before it
    happens, because this is the person's one moment to say no: what you type to
    a ticked tool, and what it answers, is copied into the hub folder and pushed
    to its repository. }
  SyncPage := CreateInputOptionPage(HubPage.ID,
    'Your AI tools',
    'Which AI tools may be synced through your hub?',
    'These AI tools were found on this PC. Each ticked one has what you type to it, '
    + 'and what it answers you (and, for Claude Code, what it remembers about you), '
    + 'copied into your hub folder and pushed with your hub to its git repository, so '
    + 'your other machines share it. Untick a tool and its files are not read at all. '
    + 'You can change this any time by running this installer again.',
    False, False);

  ToolCount := 0;

  { Nothing is pre-added here any more. This page used to add a Claude Code row
    on a fresh PC because the installer was about to install Claude Code; since
    Batch AK it installs no assistant at all - Hermes is the taught path and
    Hermes Desktop ships its own installer - so the list is exactly what was
    found on this PC. }
  for i := 0 to GetArrayLength(ToolLines) - 1 do
  begin
    id   := PipeField(ToolLines[i], 0);
    sync := PipeField(ToolLines[i], 1);
    name := PipeField(ToolLines[i], 2);
    note := PipeField(ToolLines[i], 3);
    if sync = 'none' then
    begin
      { Shown so the person knows the tool was seen rather than forgotten, and
        disabled because there is nothing this kit could do with a tick. }
      row := SyncPage.Add(name + ' - cannot sync: ' + note);
      SyncPage.CheckListBox.ItemEnabled[row] := False;
      SyncPage.Values[row] := False;
    end
    else if sync = 'memory+prompts' then
      AddSyncRow(id, name + ' - its memory folder, plus what you type to it and its answers')
    else
      AddSyncRow(id, name + ' - what you type to it, and its answers');
  end;
end;

{ Is this run making a SECOND hub and leaving this PC working from the one it has? }
function Beside: Boolean;
begin
  Result := (FoundHub <> '') and BesidePage.Values[0];
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  { Nothing to sit beside, so nothing to ask. }
  if PageID = BesidePage.ID then
    Result := (FoundHub = '');
  { A PC that already has a hub is not asked where to put one, unless it just said
    it wants a second one somewhere else. }
  if PageID = HubPage.ID then
    Result := (FoundHub <> '') and (not Beside);
end;

{ The folder page introduces itself differently for a second hub, because "this PC has
  not got a hub yet" is then untrue and the reader would rightly not believe the rest. }
procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = HubPage.ID then
  begin
    if Beside then
      WizardForm.PageDescriptionLabel.Caption :=
        'Where the second hub goes. This PC keeps working from ' + FoundHub + '.'
    else
      WizardForm.PageDescriptionLabel.Caption :=
        'This PC has not got a hub yet, so I am about to make one.';
  end;
end;

{ Ask the shared install code whether the typed folder is a place a hub may go, the
  same way DetectHub asks it where the hub is. The rule lives once, in join.ps1, and
  its tests; a second copy in Pascal is how the two would drift. }
function HubPathRefusal(Dir: String): String;
var
  PsFile, OutFile, Cmd: String;
  Code: Integer;
  Lines: TArrayOfString;
begin
  Result := '';
  StringChangeEx(Dir, '''', '''''', True);
  PsFile  := ExpandConstant('{tmp}\join.ps1');
  OutFile := ExpandConstant('{tmp}\hub-refusal.txt');
  DeleteFile(OutFile);
  Cmd := '-NoProfile -ExecutionPolicy Bypass -Command "'
       + '. ''' + PsFile + ''' -AsLibrary; '
       + '$r = Get-KitHubPathRefusal -Path ''' + Dir + '''; '
       + 'if ($r) { Set-Content -LiteralPath ''' + OutFile + ''' -Value $r }"';
  if Exec('powershell.exe', Cmd, '', SW_HIDE, ewWaitUntilTerminated, Code) then
    if FileExists(OutFile) then
      if LoadStringsFromFile(OutFile, Lines) then
        if GetArrayLength(Lines) > 0 then
          Result := Trim(Lines[0]);
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  Why: String;
begin
  Result := True;
  if (CurPageID = HubPage.ID) and ((FoundHub = '') or Beside) then
  begin
    if Trim(HubPage.Values[0]) = '' then
      HubPage.Values[0] := ExpandConstant('{%USERPROFILE}\hub');
    { A second hub cannot be the first one. Compared here rather than left to
      setup-hub.ps1, because a message on the page beats one in a console window
      that closes. }
    if Beside and (CompareText(Trim(HubPage.Values[0]), FoundHub) = 0) then
    begin
      MsgBox('That is the hub this PC already works from, so it cannot sit beside itself.'
        + #13#10 + #13#10 + 'Pick another folder, or go back and untick the box to bring '
        + FoundHub + ' up to date instead.', mbError, MB_OK);
      Result := False;
      Exit;
    end;
    Why := HubPathRefusal(Trim(HubPage.Values[0]));
    if Why <> '' then
    begin
      MsgBox('I will not put the hub there.' + #13#10 + #13#10 + Why, mbError, MB_OK);
      Result := False;
    end;
  end;
end;

function GetHubDir(Param: String): String;
begin
  if Beside then
    Result := Trim(HubPage.Values[0])
  else if FoundHub <> '' then
    Result := FoundHub
  else
    Result := Trim(HubPage.Values[0]);
  if Result = '' then Result := ExpandConstant('{%USERPROFILE}\hub');
end;

function GetRepoUrl(Param: String): String;
begin
  if Beside or (FoundHub = '') then
    Result := Trim(HubPage.Values[1])
  else
    Result := '';
end;

{ Appended to the command line, so one Run entry covers both shapes. A switch cannot be
  given a value through -File, which is why this is the flag itself or nothing at all. }
function GetBesideFlag(Param: String): String;
begin
  if Beside then Result := ' -Beside' else Result := '';
end;

{ The ticked tools, as the comma list setup-hub.ps1 expects. '-' is NONE spelled
  so it survives being passed as a command-line value. }
function GetPromptSources(Param: String): String;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to ToolCount - 1 do
    if SyncPage.Values[ToolRows[i]] then
    begin
      if Result <> '' then Result := Result + ',';
      Result := Result + ToolIds[i];
    end;
  if Result = '' then Result := '-';
end;

{ The same ticks as human names, for the Ready page. }
function GetSyncSummary(): String;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to ToolCount - 1 do
    if SyncPage.Values[ToolRows[i]] then
    begin
      if Result <> '' then Result := Result + ', ';
      Result := Result + ToolNames[i];
    end;
  if Result = '' then Result := 'nothing (every box is unticked)';
end;

{ The Ready page should say which of the two jobs is about to happen, in words a
  person can act on, because this is the last moment they can stop it. }
function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo,
  MemoTypeInfo, MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
begin
  if FoundHub <> '' then
    Result := 'This PC already has a hub, so I am going to UPDATE it:' + NewLine + NewLine
            + Space + FoundHub + NewLine + NewLine
            + 'I will fetch the latest of it and put the hub commands within reach here.'
  else
  begin
    Result := 'This PC has no hub, so I am going to INSTALL one:' + NewLine + NewLine
            + Space + GetHubDir('') + NewLine + NewLine;
    if GetRepoUrl('') <> '' then
      Result := Result + 'It will be fetched from:' + NewLine + Space + GetRepoUrl('') + NewLine + NewLine;
    Result := Result + 'I will also install anything missing that it needs: Git and Node.js. Windows may ask your permission for those, which is normal. Hermes itself is a separate download; if it is not on this PC yet I will say so and tell you where to get it.';
  end;
  Result := Result + NewLine + NewLine
          + 'Synced through your hub from this PC: ' + GetSyncSummary();
end;
