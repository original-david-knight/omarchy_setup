-- Personal input behavior carried forward from the pre-Quattro config.
hl.config({
  input = {
    kb_options = "compose:caps",
    follow_mouse = 0,
    repeat_rate = 40,
    repeat_delay = 600,

    touchpad = {
      natural_scroll = true,
      scroll_factor = 0.4,
    },
  },
})

-- Restore the old touchpad scrolling speed for all terminal-tagged windows.
-- This is loaded after Omarchy's app-specific terminal rules, so it wins.
o.window({ tag = "terminal" }, { scroll_touchpad = 1.5 })
