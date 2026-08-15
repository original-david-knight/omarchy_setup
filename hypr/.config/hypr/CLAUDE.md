# CLAUDE.md

This directory is the user-owned Hyprland configuration for Omarchy Quattro.
It is deployed to `~/.config/hypr/` with GNU Stow.

## Configuration layering

`hyprland.lua` loads configuration in this order:

1. `/usr/share/omarchy/default/hypr/bootstrap.lua`
2. `default.hypr.omarchy`, containing packaged Omarchy defaults and the active
   theme
3. User modules in this directory
4. Omarchy's dynamic toggle state

Never edit `/usr/share/omarchy/`. Local behavior belongs in the user modules
loaded after the defaults.

## Files

| File | Responsibility |
| --- | --- |
| `hyprland.lua` | Entrypoint and personal application window routing |
| `monitors.lua` | EDID-based monitor geometry and persistent workspaces |
| `input.lua` | Keyboard, pointer, touchpad, and terminal scrolling overrides |
| `bindings.lua` | Personal keybindings |
| `looknfeel.lua` | Gaps, rounding, HDR, VRR, and opacity overrides |
| `autostart.lua` | Optional personal startup programs |
| `hyprsunset.conf` | Hyprsunset profiles; restart with `omarchy restart hyprsunset` |
| `xdph.conf` | XDG desktop portal screen-sharing configuration |

The retired pre-Quattro `.conf` entrypoint and its sourced fragments must not
be reintroduced.

## Lua patterns

```lua
o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh host")
o.window("^org.example.App$", { workspace = "2" })
o.launch_on_start("my-service")
```

Before replacing an Omarchy keybinding, inspect
`omarchy menu keybindings --print` and call `hl.unbind` first.

Window class regexes fully match and are case-sensitive. Check live values with
`hyprctl clients -j`; current Hyprland window-rule documentation is at
<https://wiki.hypr.land/Configuring/Basics/Window-Rules/>.

## Validation

After every Lua change:

```bash
hyprctl reload
hyprctl configerrors
```

Useful inspection commands:

```bash
hyprctl monitors all
hyprctl clients -j
omarchy menu keybindings --print
```
