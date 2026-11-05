# Per-screen bar layouts

The stock Omarchy bar draws the single `bar.layout` from `shell.json` on
every monitor. The desktop layout is sized for the 5120 px center monitor,
so on the two 1440 px portrait side monitors its left, center, and right
sections overlapped and the 440 px webcam spacer was meaningless.

`david.bar` fixes that without forking the bar. It is a bar option (plugin
kind `bar`) that the desktop profile selects through `bar.id`. It loads the
installed stock `Bar.qml` by URL, exactly as `omarchy-shell` would, so Omarchy
updates keep applying to it. For each bar surface whose screen matches an
entry in `bar.screenLayouts`, it rebinds that surface's left, center, and
right module lists to the entry's layout. Screens without a match are never
touched, so the center monitor behaves exactly like the built-in bar. This is
the same wrapping technique as the marketplace-approved Bar Screens plugin.

## Configuration

Everything lives under `bar` in the profile's `shell.json`
(`omarchy_desktop/.config/omarchy/shell.json`):

```json
"bar": {
  "id": "david.bar",
  "layout": { "left": [...], "center": [...], "right": [...] },
  "screenLayouts": [
    {
      "name": "portrait side monitors",
      "match": "portrait",
      "layout": {
        "left": [ { "id": "david.workspaces" } ],
        "center": [ { "id": "omarchy.clock", "format": "HH:mm" } ],
        "right": []
      }
    }
  ]
}
```

`match` is a string or an object:

- `"portrait"` or `"landscape"` matches by the screen's logical shape after
  Hyprland's transform, so a rotated monitor counts as portrait.
- Any other string matches the connector name, such as `"DP-1"`.
- An object may combine `orientation`, `name`, `model`, and `serialNumber`.
  Every key given must match; each key accepts one value or a list of
  alternatives. Comparisons ignore case. Quickshell reports an empty serial
  for the current monitors, so prefer `model` or orientation.

The first matching entry wins. Its `layout` uses the same entry shape as
`bar.layout`, inline settings included. `shell.json` hot-reloads on save.

`omarchy bar move`, `omarchy bar put`, `omarchy bar set`, `omarchy plugin
enable`, and drag-to-reorder only ever change `bar.layout`. Edit
`screenLayouts` by hand. A widget drag on a screen that shows a screen layout
is ignored, with a warning in the shell log, because the stock bar would
otherwise reorder `bar.layout` for the center monitor.

Since Omarchy 4.5 the stock bar builds one widget per `bar.layout` entry into
a pool that each surface shares, and every section shows a list of pool keys.
So a screen layout can only show widgets that `bar.layout` also lists: each
entry picks the pool widget with the same id (from the same section first) and
keeps its `bar.layout` settings, so inline settings in a screen layout are
ignored. An id missing from `bar.layout` is skipped with a warning in the
shell log; `tests/test_bar_screen_layouts.py` checks this for the desktop
profile. A screen layout may also give `centerBegin` and `centerEnd`; omitted
sections are empty on that screen. The 4.5 bar has no `bar.centerAnchor`.

## Deploying and enabling elsewhere

The plugin ships in the `omarchy` stow package, so `stow_all.sh` and
`stow_all.sh --bar-only` deploy it and validate that `bar.id` and every widget
in `screenLayouts` has a plugin in this repository. After changing plugin
code, run `omarchy restart shell`; the shell watches `shell.json` but loads
the plugin's QML once.

The laptop profile keeps the stock bar. To use per-screen layouts there, set
`"id": "david.bar"` under `bar` in `omarchy_laptop/.config/omarchy/shell.json`
and add `screenLayouts` for the docked monitors. When `david.bar` is not
installed, the shell falls back to the stock bar on its own.

## Diagnostics

```bash
# Which layout each screen shows.
omarchy-shell david.bar status

# Wrapper messages and stock bar errors.
qs log -p /usr/share/omarchy/shell -t 300 | grep -i david.bar

# One omarchy-bar surface per monitor, sized to that monitor.
hyprctl layers -j | jq 'to_entries[] | {monitor: .key, bars: [.value.levels[][] | select(.namespace == "omarchy-bar") | {w, h}]}'

# Offline checks: layout matching, profile config, lint, manifest.
python3 -m unittest tests.test_bar_screen_layouts
```

If the stock bar fails to load, a desktop notification names the reason and
`status` reports `failed:`. If an Omarchy update renames the bar internals the
wrapper relies on (`ModuleList` objects carrying `keys`, `region`, and
`fixedEdge`, the center ones inside an item with `active` and `pool`, and
`layoutWidgets` on the bar root), the log says `could not find the ... module
list` and that screen shows the stock layout; adjust `findSections` in
`Bar.qml` and `keysFor` in `ScreenLayouts.js` to the new shape.
