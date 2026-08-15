-- Extra autostart processes. Optional helpers only launch on machines where
-- their executable has been installed/stowed.
local home = os.getenv("HOME") or ""

local function launch_if_present(path)
  if o.cmd_present(path) then
    o.launch_on_start(o.shell_quote(path))
  end
end

launch_if_present(home .. "/bin/auto-touchpad-toggle")
launch_if_present(home .. "/.local/bin/lifedash-open")
