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

hl.unbind("SUPER + PERIOD") -- Was: Mouse Keys. Nodi binds this key.
o.bind(
  "SUPER + E",
  "Yazi file manager",
  { launch = "ghostty --gtk-single-instance=false --class=org.omarchy.yazi -e yazi" }
)
o.bind(
  "SUPER + B",
  "Browser",
  { launch = 'google-chrome-stable --profile-directory="Default" --new-window' }
)

hl.unbind("SUPER + SHIFT + B") -- Was: Quattro default browser.
o.bind(
  "SUPER + SHIFT + B",
  "Chrome work profile",
  { launch = 'google-chrome-stable --profile-directory="Profile 1" --new-window' }
)

o.bind("SUPER + A", "Asteroids", { launch = home .. "/.cargo/bin/asteroids" })
o.bind("SUPER + SHIFT + T", "Activity", { tui = "btop" })
o.bind("SUPER + D", "Discord", { launch = "discord" })
hl.unbind("SUPER + M") -- Was: YouTube Music special workspace.
o.bind("SUPER + M", "Listening", "omarchy-shell shell toggle david.podcasts")
hl.unbind("SUPER + SHIFT + M") -- Was: Spotify launcher/focus.
o.bind("SUPER + SHIFT + M", "Spotify workspace", home .. "/.config/omarchy/plugins/david.podcasts/spotify-window toggle")

hl.unbind("SUPER + S") -- Was: Quattro scratchpad.
o.bind("SUPER + S", "Slack", home .. "/bin/toggle-slack")

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
-- Ctrl + the media Next key cycles Herdr workspaces, including the custom keycode.
o.bind("CTRL + XF86AudioNext", "Next Herdr workspace", home .. "/bin/herdr-tmux workspace next")
o.bind("CTRL + code:163", "Next Herdr workspace", home .. "/bin/herdr-tmux workspace next")
-- Shift + media Next cycles Herdr agents, or sessions while the Claude desktop
-- app has focus. Ctrl + Shift + ] is the app's own next-session shortcut; the
-- down/up split follows Omarchy's default/hypr/bindings/clipboard.lua.
local function next_agent_or_claude_session()
  local window = hl.get_active_window()
  if window and window.class == "com.anthropic.Claude" then
    local key = { mods = "CTRL SHIFT", key = "bracketright" }
    hl.dispatch(hl.dsp.send_key_state({ mods = key.mods, key = key.key, state = "down" }))
    hl.timer(function()
      hl.dispatch(hl.dsp.send_key_state({ mods = key.mods, key = key.key, state = "up" }))
    end, { timeout = 50, type = "oneshot" })
  else
    hl.exec_cmd(home .. "/bin/herdr-tmux agent next")
  end
end
o.bind("SHIFT + XF86AudioNext", "Next Herdr agent or Claude session", next_agent_or_claude_session)
o.bind("SHIFT + code:163", "Next Herdr agent or Claude session", next_agent_or_claude_session)
hl.unbind("XF86AudioPause") -- Was: Omarchy media play/pause.
hl.unbind("XF86AudioPlay") -- Was: Omarchy media play/pause.
o.bind("XF86AudioPause", "Play/pause", home .. "/bin/media-play-pause", { locked = true })
o.bind("XF86AudioPlay", "Play/pause", home .. "/bin/media-play-pause", { locked = true })
o.bind("code:200", "Play/pause", home .. "/bin/media-play-pause", { locked = true })
o.bind("code:201", "Play/pause", home .. "/bin/media-play-pause", { locked = true })
o.bind("SUPER + BACKSLASH", "Play/pause", home .. "/bin/media-play-pause", { locked = true })
o.bind("CTRL + SHIFT + J", "Volume down", "omarchy-audio-output-volume -3", { locked = true })
o.bind("CTRL + SHIFT + K", "Volume up", "omarchy-audio-output-volume +3", { locked = true })

-- Drop Omarchy's per-workspace window-width bookmarks. The feature was never
-- used and Super + Home kept firing a "No saved width" notification in games.
hl.unbind("SUPER + Home") -- Was: Omarchy restore window width.
hl.unbind("SUPER + ALT + Home") -- Was: Omarchy save window width.

-- Keep the old full-screen key, replacing Quattro's file-manager binding.
hl.unbind("SUPER + SHIFT + F") -- Was: Quattro file manager.
o.bind(
  "SUPER + SHIFT + F",
  "Full screen",
  hl.dsp.window.fullscreen({ mode = "fullscreen" })
)

hl.unbind("SUPER + ALT + SHIFT + F") -- Was: Quattro file manager in the active terminal's cwd.
o.bind(
  "SUPER + ALT + SHIFT + F",
  "Yazi file manager (cwd)",
  { launch = 'ghostty --gtk-single-instance=false --class=org.omarchy.yazi -e yazi "$(omarchy-cmd-terminal-cwd)"' }
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

-- Laptop-only bindings, deployed by the omarchy_laptop stow package.
local laptop_bindings_path = home .. "/.config/hypr/laptop-bindings.lua"
local laptop_bindings = io.open(laptop_bindings_path, "r")
if laptop_bindings then
  laptop_bindings:close()
  dofile(laptop_bindings_path)
end

-- Dictation keys from before Alt + Space and Right Alt became the defaults.
-- Remove these lines to give the keys back to applications.
if o.dictation_installed and o.dictation_installed() then
  o.bind("SUPER + CTRL + X", "Toggle dictation", "omarchy-dictation toggle")
  o.bind_hold("F9", "Start dictation (push-to-talk)", "omarchy-dictation start", "Stop dictation (push-to-talk)", "omarchy-dictation stop")
end

-- Omarchy 4.5 numbers workspaces per monitor (Super + 3 = slot 3 of the focused
-- monitor, in blocks of ten). Keep global numbers instead, on the desktop and
-- laptop alike: the desktop pins 1-5, 6-7 and 8-9 to its monitors in
-- monitors.lua, and a laptop places them wherever they are opened. Stop the
-- reconciler, which would renumber workspaces into monitor blocks, and bind
-- the number keys straight to workspace ids. o.rebind replaces the stock
-- binding; o.bind would add a second one that still fires. Both bar layouts
-- use david.workspaces to match.
o.workspaces.reconcile = function() end

for workspace = 1, 10 do
  local key = "code:" .. tostring(workspace + 9)
  local id = tostring(workspace)
  o.rebind("SUPER + " .. key, "Switch to workspace " .. workspace, hl.dsp.focus({ workspace = id }))
  o.rebind("SUPER + SHIFT + " .. key, "Move window to workspace " .. workspace, hl.dsp.window.move({ workspace = id }))
  o.rebind("SUPER + SHIFT + ALT + " .. key, "Move window silently to workspace " .. workspace, hl.dsp.window.move({ workspace = id, follow = false }))
end

for _, direction in ipairs({ { "LEFT", "l", "left" }, { "RIGHT", "r", "right" }, { "UP", "u", "up" }, { "DOWN", "d", "down" } }) do
  o.rebind("SUPER + SHIFT + ALT + " .. direction[1], "Move workspace to " .. direction[3] .. " monitor", hl.dsp.workspace.move({ monitor = direction[2] }))
end
