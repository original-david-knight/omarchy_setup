-- Personal keybindings migrated from the pre-Quattro Hyprland configuration.
-- Omarchy defaults load first, so existing keys are explicitly unbound before
-- they are replaced here.

local home = os.getenv("HOME") or ""

-- Application launchers.
hl.unbind("SUPER + RETURN") -- Was: Quattro terminal launcher.
o.bind(
  "SUPER + RETURN",
  "Terminal",
  { launch = "ghostty --gtk-single-instance=false" }
)

hl.unbind("SUPER + ALT + RETURN") -- Was: Quattro Work tmux session.
o.bind(
  "SUPER + ALT + RETURN",
  "Tmux",
  'uwsm-app -- xdg-terminal-exec --dir="$(omarchy-cmd-terminal-cwd)" tmux new'
)

o.bind("SUPER + PERIOD", "Mouse Keys", "mousekeys show")
o.bind(
  "SUPER + B",
  "Browser",
  { launch = 'google-chrome-stable --profile-directory="Default" --new-window' }
)

hl.unbind("SUPER + SHIFT + B") -- Was: Quattro default browser.
o.bind(
  "SUPER + SHIFT + B",
  "Browser (Profile 1)",
  { launch = 'google-chrome-stable --profile-directory="Profile 1" --new-window' }
)

o.bind("SUPER + A", "Asteroids", { launch = home .. "/.cargo/bin/asteroids" })
o.bind("SUPER + SHIFT + T", "Activity", { tui = "btop" })
o.bind("SUPER + D", "Discord", { launch = "discord" })
o.bind("SUPER + M", "Music", home .. "/bin/toggle-music")

hl.unbind("SUPER + S") -- Was: Quattro scratchpad.
o.bind("SUPER + S", "Slack + Obsidian", home .. "/bin/toggle-slack-obsidian")

-- Screen agent and capture shortcuts.
o.bind(
  "CTRL + SHIFT + A",
  "Screen agent",
  "systemctl --user start screen-agent.service && systemctl --user kill --kill-whom=main --signal=USR1 screen-agent.service"
)
o.bind(
  "CTRL + SHIFT + R",
  "Screenrecording with microphone",
  "omarchy capture screenrecording --with-microphone-audio"
)
o.bind("CTRL + SHIFT + S", "Screenshot of region", "omarchy capture screenshot region")
o.bind("CTRL + SHIFT + W", "Screenshot of window", "omarchy capture screenshot windows")

-- Web app shortcut retained at its old key. Quattro also provides this on
-- SUPER + SHIFT + CTRL + G.
o.bind(
  "CTRL + SHIFT + G",
  "Google Messages",
  { webapp = "https://messages.google.com/web/conversations", focus = true }
)

-- Quattro-native media and volume commands.
o.bind("code:163", "Next track", "omarchy-shell media next", { locked = true })
o.bind("code:165", "Previous track", "omarchy-shell media previous", { locked = true })
o.bind("code:200", "Play/pause", "omarchy-shell media playPause", { locked = true })
o.bind("code:201", "Play/pause", "omarchy-shell media playPause", { locked = true })
o.bind("SUPER + BACKSLASH", "Play/pause", "omarchy-shell media playPause", { locked = true })
o.bind("CTRL + SHIFT + J", "Volume down", "omarchy-audio-output-volume -3", { locked = true })
o.bind("CTRL + SHIFT + K", "Volume up", "omarchy-audio-output-volume +3", { locked = true })

-- Keep the old full-screen key, replacing Quattro's file-manager binding.
hl.unbind("SUPER + SHIFT + F") -- Was: Quattro file manager.
o.bind(
  "SUPER + SHIFT + F",
  "Full screen",
  hl.dsp.window.fullscreen({ mode = "fullscreen" })
)

-- Emergency mode: CTRL + ALT + DELETE, then R/S/L. Escape or any other key
-- cancels without passing the key through to the focused application.
hl.unbind("CTRL + ALT + DELETE") -- Was: Quattro close-all-windows action.
o.bind("CTRL + ALT + DELETE", "Emergency mode", hl.dsp.submap("emergency"))

hl.define_submap("emergency", function()
  o.bind("R", "Reboot", "systemctl reboot")
  o.bind("S", "Shutdown", "systemctl poweroff")
  o.bind("L", "Log out", hl.dsp.exit())
  o.bind("ESCAPE", "Cancel", hl.dsp.submap("reset"))
  o.bind("catchall", "Cancel", hl.dsp.submap("reset"))
end)

-- IDE selection menu (the helper now uses Quattro's menu instead of Walker).
o.bind("SUPER + I", "IDE menu", home .. "/bin/ide-menu")
