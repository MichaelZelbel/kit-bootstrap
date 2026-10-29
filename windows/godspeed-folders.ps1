# =============================================================================
# kit-bootstrap / windows / godspeed-folders.ps1
#
# THE ONE PLACE that names the two folders the Windows setup keeps in %LOCALAPPDATA%: the program
# (the notebook program, these scripts and the uninstaller) and the state (the notebook's record
# installation.json, its media, its backups, the assistant's Hermes and what it learned, the logs).
# Every script of the setup dot-sources this file, and build-godspeed-setup.ps1 hands the program
# folder's name to godspeed-setup.iss when it compiles it. Nothing else names them.
#
# Until 2.0.0-beta.11 both names said "Full Alpha", left from when version 2 was a preview to try
# beside the first edition (product issue #6). A new install uses the new names. An install made
# before is moved to them by the first update (move-to-new-folders.ps1), and until then, or when
# that move could not be done, it is found under them: every script asks Get-GodspeedStateFolder,
# which looks for the new name first and the old one second.
# =============================================================================

function Get-GodspeedFolderNames {
    [pscustomobject]@{
        Program    = 'Godspeed Mission Control'
        State      = 'Godspeed Mission Control State'
        # The names of installs made before 2.0.0-beta.11.
        OldProgram = 'Godspeed Mission Control Full Alpha'
        OldState   = 'Godspeed Mission Control Full Alpha State'
    }
}

# The setup's own scripts were named ...-full-alpha.ps1 until 2.0.0-beta.11; each old name with the
# name of the script that does its work now. move-to-new-folders.ps1 uses it to point a shortcut
# that ran an old script at the new one.
function Get-GodspeedOldScriptNames {
    [ordered]@{
        'setup-full-alpha.ps1'         = 'setup-notebook.ps1'
        'invoke-full-alpha-node.ps1'   = 'invoke-notebook-node.ps1'
        'start-full-alpha.ps1'         = 'start-notebook.ps1'
        'stop-full-alpha.ps1'          = 'stop-notebook.ps1'
        'ensure-hermes-full-alpha.ps1' = 'ensure-hermes.ps1'
        'open-hermes-full-alpha.ps1'   = 'open-hermes.ps1'
        'computer-full-alpha.ps1'      = 'computer-helper.ps1'
    }
}

# What a state folder's installation.json is: 'install' (a notebook's record), 'moved' (the note
# move-to-new-folders.ps1 leaves under the old name for an updater from before 2.0.0-beta.11, which
# reads only there; it names the folder the install went to), or $null when there is none.
function Get-GodspeedRecordKind {
    param([Parameter(Mandatory)][string]$Folder)
    $file = Join-Path $Folder 'installation.json'
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    try { if ((Get-Content -LiteralPath $file -Raw -ErrorAction Stop | ConvertFrom-Json).movedTo) { return 'moved' } } catch { }
    return 'install'
}

# The state folder this PC's notebook keeps: the new name when an install keeps its record there,
# else the old name when an install made before 2.0.0-beta.11 keeps it there, else the new name
# for an install still to be made. An update of an old install so goes on in the old folder and
# never starts a second, empty one beside it. The note an update leaves under the old name for an
# older updater is not an install.
function Get-GodspeedStateFolder {
    param([string]$LocalAppData = $env:LOCALAPPDATA)
    $names = Get-GodspeedFolderNames
    $new = Join-Path $LocalAppData $names.State
    $old = Join-Path $LocalAppData $names.OldState
    if (Test-Path -LiteralPath (Join-Path $new 'installation.json')) { return $new }
    if ((Get-GodspeedRecordKind $old) -eq 'install') { return $old }
    return $new
}
