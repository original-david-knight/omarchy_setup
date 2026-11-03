-- This file is deployed only by the laptop profile.
local function send_herdr_next_workspace()
  hl.dispatch(hl.dsp.send_key_state({ mods = "ALT", key = "DOWN", state = "down" }))

  hl.timer(function()
    hl.dispatch(hl.dsp.send_key_state({ mods = "ALT", key = "DOWN", state = "up" }))
  end, { timeout = 50, type = "oneshot" })
end

o.bind("CTRL + SHIFT + SPACE", "Next remote Herdr workspace", send_herdr_next_workspace)
