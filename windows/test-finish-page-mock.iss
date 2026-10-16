; A stand-in for GodspeedSetup.exe, only for checking windows/test-finish-page.ps1 itself: the same
; wizard shape (a folder page, the Ready page, a step that runs, the finish page with the three
; lines and the "Open my mission control folder" box), and nothing installed but one empty folder.
; Compiled with /DFit it fits the finish label to its words as godspeed-setup.iss does; without
; it the label keeps the stock text's height, and the check must notice.
[Setup]
AppName=Godspeed Mission Control
AppVersion=0.0.0
DefaultDirName={localappdata}\Godspeed finish page check
PrivilegesRequired=lowest
DisableProgramGroupPage=yes
DisableDirPage=yes
Uninstallable=no
WizardStyle=modern
OutputDir=dist
#ifdef Fit
OutputBaseFilename=mock-fit
#else
OutputBaseFilename=mock-nofit
#endif

[Run]
Filename: "{cmd}"; Parameters: "/c ping -n 6 127.0.0.1 >nul"; Flags: runhidden waituntilterminated
Filename: "{app}"; Description: "Open my mission control folder"; Flags: postinstall shellexec nowait unchecked

[Code]
var
  FolderPage: TInputQueryWizardPage;

procedure InitializeWizard();
begin
  FolderPage := CreateInputQueryPage(wpWelcome, 'Where your mission control goes', 'A stand-in page.', 'Nothing is made here.');
  FolderPage.Add('Folder on this PC:', False);
  FolderPage.Values[0] := ExpandConstant('{%USERPROFILE}\godspeed-v2');
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpFinished then
  begin
    WizardForm.FinishedLabel.Caption := 'Your mission control is in ' + FolderPage.Values[0] + '.' + #13#10 + #13#10 +
      'To talk to it, open your notebook: Start menu, Open my notebook. The first time, connect your own AI account in Settings.' + #13#10 + #13#10 +
      'I write about what it does and what broke, free: https://michaelzelbel.substack.com/subscribe';
#ifdef Fit
    WizardForm.AdjustLabelHeight(WizardForm.FinishedLabel);
#endif
    WizardForm.RunList.Top := WizardForm.FinishedLabel.Top + WizardForm.FinishedLabel.Height + ScaleY(12);
  end;
end;
