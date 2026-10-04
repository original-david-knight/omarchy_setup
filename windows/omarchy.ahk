#Requires AutoHotkey v2.0 64-bit
#SingleInstance Force
#Warn All, StdOut

; SUPER on Omarchy is the Windows key here. Dependencies live beside this file.
global DesktopDll := A_ScriptDir '\VirtualDesktopAccessor.dll'
global PreviousDesktop := -1
global ObservedDesktop := -1
global HelpWindow := 0

DesktopCall(name, args*) {
    args.Push('Int')
    result := DllCall(DesktopDll '\' name, args*)
    if result < 0
        throw Error('Windows desktop operation failed: ' name)
    return result
}

ObserveDesktop() {
    global PreviousDesktop, ObservedDesktop
    current := DesktopCall('GetCurrentDesktopNumber')
    if current != ObservedDesktop {
        PreviousDesktop := ObservedDesktop
        ObservedDesktop := current
    }
    return current
}

EnsureDesktop(target) {
    count := DesktopCall('GetDesktopCount')
    if target >= 0 && target < count
        return
    if target < 0 || target > 9
        throw Error('Choose a desktop from 1 to 10.')
    while count <= target {
        DesktopCall('CreateDesktop')
        updated := DesktopCall('GetDesktopCount')
        if updated <= count
            throw Error('Windows did not create the requested desktop.')
        count := updated
    }
}

SwitchDesktop(target) {
    ObserveDesktop()
    EnsureDesktop(target)
    DesktopCall('GoToDesktopNumber', 'Int', target)
    ObserveDesktop()
}

MoveToDesktop(target, follow := true) {
    ; Capture the window before creating a desktop can change foreground focus.
    hwnd := AppWindow()
    if !hwnd
        return
    EnsureDesktop(target)
    DesktopCall('MoveWindowToDesktopNumber', 'Ptr', hwnd, 'Int', target)
    if follow {
        SwitchDesktop(target)
        try WinActivate('ahk_id ' hwnd)
    }
}

CycleDesktop(delta) {
    count := DesktopCall('GetDesktopCount')
    SwitchDesktop(Mod(ObserveDesktop() + delta + count, count))
}

FormerDesktop() {
    ObserveDesktop()
    if PreviousDesktop >= 0 && PreviousDesktop < DesktopCall('GetDesktopCount')
        SwitchDesktop(PreviousDesktop)
}

AppWindow() {
    hwnd := WinExist('A')
    if !hwnd || WinGetClass('ahk_id ' hwnd) ~= '^(Progman|WorkerW|Shell_TrayWnd|Shell_SecondaryTrayWnd)$'
        return 0
    return hwnd
}

CloseWindow() {
    if hwnd := AppWindow()
        WinClose('ahk_id ' hwnd)
}

MaximizeWindow() {
    if hwnd := AppWindow() {
        if WinGetMinMax('ahk_id ' hwnd) = 1
            WinRestore('ahk_id ' hwnd)
        else
            WinMaximize('ahk_id ' hwnd)
    }
}

FocusDirection(direction) {
    if !(active := AppWindow())
        return
    WinGetPos(&x, &y, &w, &h, 'ahk_id ' active)
    cx := x + w / 2, cy := y + h / 2
    best := 0, bestScore := 1.0e30
    for hwnd in WinGetList() {
        try {
            if hwnd = active || !WinGetTitle('ahk_id ' hwnd) || WinGetMinMax('ahk_id ' hwnd) = -1
                continue
            if WinGetExStyle('ahk_id ' hwnd) & 0x80 ; tool windows
                continue
            if !DesktopCall('IsWindowOnCurrentVirtualDesktop', 'Ptr', hwnd)
                continue
            cloaked := 0
            DllCall('dwmapi\DwmGetWindowAttribute', 'Ptr', hwnd, 'UInt', 14, 'UInt*', &cloaked, 'UInt', 4)
            if cloaked
                continue
            WinGetPos(&nx, &ny, &nw, &nh, 'ahk_id ' hwnd)
            dx := nx + nw / 2 - cx, dy := ny + nh / 2 - cy
            along := direction = 'Left' ? -dx : direction = 'Right' ? dx : direction = 'Up' ? -dy : dy
            across := direction = 'Left' || direction = 'Right' ? Abs(dy) : Abs(dx)
            if along > 0 && (score := along + 2 * across) < bestScore
                best := hwnd, bestScore := score
        }
    }
    if best
        WinActivate('ahk_id ' best)
}

LaunchInstalled(paths, arguments := '') {
    for path in paths {
        if FileExist(path) {
            Run('"' path '" ' arguments)
            return
        }
    }
    throw Error('This application is not installed at a configured location.')
}

Browser(work := false) {
    LaunchInstalled([
        A_ProgramFiles '\Google\Chrome\Application\chrome.exe',
        EnvGet('LOCALAPPDATA') '\Google\Chrome\Application\chrome.exe'
    ], '--profile-directory="' (work ? 'Profile 1' : 'Default') '" --new-window')
}

Terminal() {
    path := EnvGet('LOCALAPPDATA') '\Microsoft\WindowsApps\wt.exe'
    Run(FileExist(path) ? '"' path '"' : 'powershell.exe')
}

SlackAndObsidian() {
    localApp := EnvGet('LOCALAPPDATA')
    if WinActive('ahk_exe slack.exe') || WinActive('ahk_exe Obsidian.exe') {
        for exe in ['slack.exe', 'Obsidian.exe']
            for hwnd in WinGetList('ahk_exe ' exe)
                WinMinimize('ahk_id ' hwnd)
        return
    }
    for app in [['Obsidian.exe', localApp '\Obsidian\Obsidian.exe'], ['slack.exe', localApp '\slack\slack.exe']] {
        if hwnd := WinExist('ahk_exe ' app[1]) {
            WinRestore('ahk_id ' hwnd)
            WinActivate('ahk_id ' hwnd)
        } else
            LaunchInstalled([app[2]])
    }
}

Unavailable(*) {
    TrayTip('This Omarchy action has no Windows mapping yet. Win+K shows the available shortcuts.', 'Omarchy shortcuts', 1)
}

ShowHelp(*) {
    global HelpWindow
    if HelpWindow {
        HelpWindow.Show()
        return
    }
    HelpWindow := Gui(, 'Omarchy shortcuts on Windows')
    HelpWindow.SetFont('s10', 'Segoe UI')
    HelpWindow.AddText(, '
    (
Win+1..9 / 0     Desktop 1..9 / 10 (created as needed)
Win+Shift+number     Move window and follow
Win+Alt+Shift+number     Move window without following
Win+Tab / Win+Shift+Tab     Next / previous desktop
Win+Ctrl+Tab     Former desktop
Win+arrows     Focus a window in that direction
Win+Enter / E     Terminal / File Explorer
Win+B / Win+Shift+B     Chrome default / Profile 1
Win+D / I     Discord / VS Code
Win+S     Show or minimize Slack and Obsidian
Win+M / Win+Shift+M     YouTube Music / Spotify
Win+Space     Start menu
Win+W     Close window
Win+F / Win+Shift+F     App fullscreen (F11)
Win+Alt+F     Maximize or restore
Win+Shift+T     Task Manager
Ctrl+Shift+S     Region screenshot
Ctrl+Shift+W     Window screenshot to clipboard
Ctrl+Shift+J / K     Volume down / up
Win+Backslash     Play or pause
Win+K     This help
Win+Ctrl+Alt+F12     Suspend or resume all mappings

Win+L still locks Windows. Ctrl+Alt+Delete stays native.
Use the tray icon to exit and restore normal Windows shortcuts.
    )')
    HelpWindow.OnEvent('Close', (*) => HelpWindow.Hide())
    HelpWindow.Show()
}

SafeAction(callback, *) {
    try callback.Call()
    catch Error as err
        TrayTip(err.Message, 'Omarchy shortcuts', 2)
}

Bind(key, callback) {
    ; The keyboard hook swallows the original Windows action as well.
    Hotkey('$' key, SafeAction.Bind(callback))
}

; Validate before registering any shortcuts. --check never registers them.
try {
    initialDesktopCount := DesktopCall('GetDesktopCount')
    initialDesktopNumber := ObserveDesktop()
    if initialDesktopCount < 1 || initialDesktopNumber >= initialDesktopCount
        throw Error('Windows returned an invalid desktop list.')
} catch Error as startupError {
    FileAppend(startupError.Message '`n', '**')
    if !A_Args.Length
        MsgBox(startupError.Message '`nRe-run windows\install.ps1 to diagnose.', 'Omarchy shortcuts', 'Iconx')
    ExitApp(1)
}
if A_Args.Length {
    if A_Args[1] = '--check' {
        FileAppend('Desktop API OK: ' initialDesktopCount ' desktops; current desktop ' (initialDesktopNumber + 1) '.`n', '*')
        ExitApp(0)
    }
    ExitApp(2)
}

Loop 10 {
    index := A_Index - 1
    ; Physical number-row keys match Omarchy's code:10..19, across layouts.
    key := Format('sc{:03X}', A_Index + 1)
    Bind('#' key, SwitchDesktop.Bind(index))
    Bind('#+' key, MoveToDesktop.Bind(index, true))
    Bind('#!+' key, MoveToDesktop.Bind(index, false))
}
Bind('#Tab', CycleDesktop.Bind(1))
Bind('#+Tab', CycleDesktop.Bind(-1))
Bind('#^Tab', FormerDesktop)
for direction in ['Left', 'Right', 'Up', 'Down']
    Bind('#' direction, FocusDirection.Bind(direction))
Bind('#Enter', Terminal)
Bind('#e', (*) => Run('explorer.exe'))
Bind('#b', Browser)
Bind('#+b', Browser.Bind(true))
Bind('#d', (*) => LaunchInstalled([EnvGet('LOCALAPPDATA') '\Discord\Update.exe'], '--processStart Discord.exe'))
Bind('#i', (*) => LaunchInstalled([EnvGet('LOCALAPPDATA') '\Programs\Microsoft VS Code\Code.exe', A_ProgramFiles '\Microsoft VS Code\Code.exe']))
Bind('#s', SlackAndObsidian)
Bind('#m', (*) => Run('https://music.youtube.com/'))
Bind('#+m', (*) => Run('spotify:'))
Bind('#Space', (*) => Send('^{Esc}'))
Bind('#w', CloseWindow)
Bind('#f', (*) => Send('{F11}'))
Bind('#+f', (*) => Send('{F11}'))
Bind('#!f', MaximizeWindow)
Bind('#+t', (*) => Run('taskmgr.exe'))
Bind('^+s', (*) => Send('#+s'))
Bind('^+w', (*) => Send('!{PrintScreen}'))
Bind('^+j', (*) => SoundSetVolume('-3'))
Bind('^+k', (*) => SoundSetVolume('+3'))
Bind('#\', (*) => Send('{Media_Play_Pause}'))
Bind('#k', ShowHelp)
; Swallow common unmapped Omarchy keys instead of opening Windows panels.
for key in ['#a', '#j', '#p', '#t', '#o']
    Bind(key, Unavailable)
Hotkey('#^!F12', (*) => Suspend(-1), 'S')
A_TrayMenu.Insert('1&', 'Shortcut reference (Win+K)', ShowHelp)
A_IconTip := 'Omarchy shortcuts - Win+K for help'
; Track desktop changes made through Task View or native Windows shortcuts too.
PollDesktop() {
    ; Explorer can be temporarily unavailable during a restart. Hotkey actions
    ; report errors on demand; the background observer must not spam notices.
    try ObserveDesktop()
}
SetTimer(PollDesktop, 500)
