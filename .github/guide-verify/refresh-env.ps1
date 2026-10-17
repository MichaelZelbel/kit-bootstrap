<#
  Give this PowerShell the environment a program gets when the reader starts it from Explorer
  or the Start menu after an earlier install: every machine and user variable as the registry
  holds it now, PATH being the machine's followed by the user's. A GitHub job step keeps the
  environment it started with, so without this a second installer in the same job never sees
  GODSPEED_DIR, which the first install set as a user variable, and behaves as if this PC had
  no mission control (which a real PC, signed in again or simply after the install, does not).

    . ./.github/guide-verify/refresh-env.ps1
#>
foreach ($scope in 'Machine', 'User') {
  $vars = [Environment]::GetEnvironmentVariables($scope)
  foreach ($name in $vars.Keys) { if ($name -ne 'Path') { Set-Item -Path "Env:$name" -Value $vars[$name] } }
}
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
$env:PSModulePath = [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine')
"environment as a new Explorer process gets it; GODSPEED_DIR=$env:GODSPEED_DIR"
