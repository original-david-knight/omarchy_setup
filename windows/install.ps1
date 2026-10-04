# Run with Windows PowerShell 5.1 or PowerShell 7. No administrator needed.
[CmdletBinding()]
param([switch]$NoStartup, [switch]$NoStart)
$ErrorActionPreference = 'Stop'

if (-not [Environment]::Is64BitProcess -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
    throw 'Run this installer from 64-bit PowerShell on x64 Windows.'
}
$build = [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuild
if ($build -lt 26100) { throw 'Windows 11 24H2 or newer is required.' }

$installDir = Join-Path $env:LOCALAPPDATA 'OmarchyShortcuts'
$stage = Join-Path ([IO.Path]::GetTempPath()) ('omarchy-shortcuts-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $stage | Out-Null
New-Item -ItemType Directory -Force -Path $installDir | Out-Null

function Get-VerifiedFile($Url, $Path, $Hash) {
    Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Path
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $Hash) {
        throw "Download checksum mismatch: $Url"
    }
}

try {
    Get-VerifiedFile 'https://github.com/AutoHotkey/AutoHotkey/releases/download/v2.0.29/AutoHotkey_2.0.29.zip' `
        (Join-Path $stage 'AutoHotkey.zip') 'B2D0200724A6B6AD22C965C939C5E5A2C64A35D1CCB455A3CA3F8CE415C5A296'
    Get-VerifiedFile 'https://github.com/Ciantic/VirtualDesktopAccessor/releases/download/2024-12-16-windows11/VirtualDesktopAccessor.dll' `
        (Join-Path $stage 'VirtualDesktopAccessor.dll') '8740C572A1C000E3B87FFEB1E4C397EAE9AF3BD4A2ABDC3BCFFACAB4493F8FF5'
    Expand-Archive -LiteralPath (Join-Path $stage 'AutoHotkey.zip') -DestinationPath (Join-Path $stage 'ahk')
    Copy-Item -LiteralPath (Join-Path $stage 'ahk\AutoHotkey64.exe') -Destination $stage
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'omarchy.ahk') -Destination $stage
    $probe = Start-Process -FilePath (Join-Path $stage 'AutoHotkey64.exe') `
        -ArgumentList ('/ErrorStdOut "' + (Join-Path $stage 'omarchy.ahk') + '" --check') `
        -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $stage 'check.stdout') `
        -RedirectStandardError (Join-Path $stage 'check.stderr')
    # Cache the handle before waiting so Windows PowerShell 5.1 retains ExitCode.
    $probeHandle = $probe.Handle
    if (-not $probe.WaitForExit(15000)) {
        $probe.Kill()
        $probe.WaitForExit()
        throw 'Desktop compatibility check timed out.'
    }
    $checkOutput = Get-Content (Join-Path $stage 'check.stdout'), (Join-Path $stage 'check.stderr')
    if ($probe.ExitCode -ne 0) { throw "Shortcut validation failed: $checkOutput" }
    Write-Output $checkOutput

    # Stop only this installation, leaving unrelated AutoHotkey scripts alone.
    $exe = Join-Path $installDir 'AutoHotkey64.exe'
    Get-Process -Name AutoHotkey64 -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -eq $exe } | Stop-Process
    foreach ($file in @('AutoHotkey64.exe', 'VirtualDesktopAccessor.dll', 'omarchy.ahk')) {
        Copy-Item -LiteralPath (Join-Path $stage $file) -Destination $installDir -Force
    }
    Copy-Item -LiteralPath (Join-Path $stage 'ahk\license.txt') -Destination (Join-Path $installDir 'AutoHotkey-license.txt') -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'uninstall.ps1') -Destination $installDir -Force

    $startupLink = Join-Path ([Environment]::GetFolderPath('Startup')) 'Omarchy Shortcuts.lnk'
    if ($NoStartup) {
        if (Test-Path -LiteralPath $startupLink) { Remove-Item -LiteralPath $startupLink }
    } else {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($startupLink)
        $shortcut.TargetPath = $exe
        $shortcut.Arguments = '"' + (Join-Path $installDir 'omarchy.ahk') + '"'
        $shortcut.WorkingDirectory = $installDir
        $shortcut.Description = 'Omarchy keyboard shortcuts for Windows'
        $shortcut.Save()
    }
    if (-not $NoStart) {
        $process = Start-Process -FilePath $exe -ArgumentList ('"' + (Join-Path $installDir 'omarchy.ahk') + '"') -WindowStyle Hidden -PassThru
        Start-Sleep -Milliseconds 800
        if ($process.HasExited) { throw 'The shortcut process exited during startup.' }
    }
    Write-Output "Installed in $installDir. Win+K shows shortcuts; Win+Ctrl+Alt+F12 suspends them."
} finally {
    # Only remove the unique temporary directory created by this invocation.
    $resolvedStage = [IO.Path]::GetFullPath($stage)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($resolvedStage.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path $resolvedStage -Leaf) -match '^omarchy-shortcuts-[0-9a-f-]{36}$') {
        Remove-Item -LiteralPath $resolvedStage -Recurse -Force -ErrorAction Continue
    }
}
