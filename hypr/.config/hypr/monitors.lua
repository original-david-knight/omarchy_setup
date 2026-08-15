-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and supported resolutions with: hyprctl monitors all

local omarchy_gdk_scale = 2
local omarchy_monitor_scale = "auto"

hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })

-- Preserve the pre-Quattro three-monitor layout using stable EDID descriptions.
hl.monitor({
  output = "desc:LG Electronics LG ULTRAGEAR+ 509RMDZ52650",
  mode = "5120x2160@165.00",
  position = "0x0",
  scale = 1,
})

hl.monitor({
  output = "desc:ASUSTek COMPUTER INC VG27AQL1A L7LMQS155211",
  mode = "2560x1440@120.00",
  position = "5120x0",
  scale = 1,
  transform = 3,
})

hl.monitor({
  output = "desc:ASUSTek COMPUTER INC VG27AQL1A L7LMQS155226",
  mode = "2560x1440@120.00",
  position = "-1440x0",
  scale = 1,
  transform = 1,
})

-- Keep the pre-Quattro workspace layout alive and pinned to the same monitors.
local primary_monitor = "desc:LG Electronics LG ULTRAGEAR+ 509RMDZ52650"
local right_monitor = "desc:ASUSTek COMPUTER INC VG27AQL1A L7LMQS155211"
local left_monitor = "desc:ASUSTek COMPUTER INC VG27AQL1A L7LMQS155226"

for workspace = 1, 5 do
  hl.workspace_rule({
    workspace = tostring(workspace),
    monitor = primary_monitor,
    persistent = true,
    default = workspace == 1,
  })
end

for workspace = 6, 7 do
  hl.workspace_rule({
    workspace = tostring(workspace),
    monitor = right_monitor,
    persistent = true,
    default = workspace == 6,
  })
end

for workspace = 8, 9 do
  hl.workspace_rule({
    workspace = tostring(workspace),
    monitor = left_monitor,
    persistent = true,
    default = workspace == 8,
  })
end
