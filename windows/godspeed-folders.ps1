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
# before keeps its old names until an update moves it, and until then it is found under them:
# every script asks Get-GodspeedStateFolder, which looks for the new name first and the old one
# second. The program folder of an old install is found by Windows itself: the setup has
# UsePreviousAppDir, so an update goes into the folder the Apps entry names.
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

# The state folder this PC's notebook keeps: the new name when an install keeps its record there,
# else the old name when an install made before 2.0.0-beta.11 keeps it there, else the new name
# for an install still to be made. An update of an old install so goes on in the old folder and
# never starts a second, empty one beside it.
function Get-GodspeedStateFolder {
    param([string]$LocalAppData = $env:LOCALAPPDATA)
    $names = Get-GodspeedFolderNames
    $new = Join-Path $LocalAppData $names.State
    $old = Join-Path $LocalAppData $names.OldState
    if (Test-Path -LiteralPath (Join-Path $new 'installation.json')) { return $new }
    if (Test-Path -LiteralPath (Join-Path $old 'installation.json')) { return $old }
    return $new
}
