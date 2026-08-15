-- Personal look-and-feel carried forward from the pre-Quattro config.
hl.config({
  general = {
    gaps_in = 4,
    gaps_out = 6,
  },

  decoration = {
    rounding = 4,
  },

  -- Keep HDR from being activated automatically.
  render = {
    cm_auto_hdr = 0,
  },

  -- Chrome runs through XWayland on this setup, where VRR caused jitter and
  -- dropped frames on the 165 Hz display.
  misc = {
    vrr = 0,
  },
})

-- Override Omarchy's default-opacity rules so every application stays opaque.
o.window(".*", { opacity = "1.0 override 1.0 override 1.0 override" })
