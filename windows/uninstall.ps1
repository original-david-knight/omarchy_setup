[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$installDir = Join-Path $env:LOCALAPPDATA 'OmarchyShortcuts'
$exe = Join-Path $installDir 'AutoHotkey64.exe'
Get-Process -Name AutoHotkey64 -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -eq $exe } | Stop-Process
$link = Join-Path ([Environment]::GetFolderPath('Startup')) 'Omarchy Shortcuts.lnk'
if (Test-Path -LiteralPath $link) { Remove-Item -LiteralPath $link }
# Retain the small installation folder so any local customizations survive.
Write-Output "Omarchy shortcuts stopped and login startup removed. Files retained in $installDir."
