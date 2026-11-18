-- Rex actions for Namespace devboxes. The work happens in devbox.lua, run in a new tab
-- so you can watch it (config-file actions stop after 30 seconds).
--
--   rex do devbox_up   [name=NAME] [blueprint=rex] [open=false]   Create (or reuse) a devbox from the
--                                             blueprint and register it as a Rex host.
--   rex do devbox_down name=NAME [stop=false] Remove the Rex host and stop the devbox.
--
-- After `devbox_up`, connect with: rex -S <name> ...
-- Run `rex config reload` after you edit this file or devbox.lua.

local HOME = os.getenv("HOME") or ""
local SCRIPT = HOME .. "/.config/rex/devbox.lua"
-- The Rex server's PATH is minimal and misses the rex CLI and the devbox CLI.
local REX_BIN = HOME .. "/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS"
local PATH = REX_BIN .. ":" .. HOME .. "/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

local function launch(ctx, label, argv)
  if not ctx.session_id then
    error("no session: run this from a Rex terminal or pass -s SESSION", 0)
  end
  local cmd = { "rex", "run", "-s", ctx.session_id, "--label", label, "--keep-open", "--json", "--" }
  for _, a in ipairs(argv) do
    cmd[#cmd + 1] = a
  end
  local r, err = rex.exec(cmd, { env = { PATH = PATH } })
  if r == nil or not r.ok then
    error("could not open the tab: " .. tostring(err or (r and r.stderr)), 0)
  end
  return { started = label }
end

rex.action({
  name = "devbox_up",
  title = "Devbox: create and connect",
  category = "Devbox",
  description = "Create or reuse a Namespace devbox, start its Rex server, and add it as a Rex host.",
  args = { name = "string?", blueprint = "string?", open = "boolean?" },
  run = function(ctx, args)
    local argv = { "rex", "do", SCRIPT, "mode=up" }
    if args.name then argv[#argv + 1] = "name=" .. args.name end
    if args.blueprint then argv[#argv + 1] = "blueprint=" .. args.blueprint end
    if args.open == false then argv[#argv + 1] = "open=false" end
    return launch(ctx, "devbox up", argv)
  end,
})

rex.action({
  name = "devbox_down",
  title = "Devbox: disconnect and stop",
  category = "Devbox",
  description = "Remove the devbox's Rex host and stop the devbox (stop=false keeps it running).",
  args = { name = "string", stop = "boolean?" },
  run = function(ctx, args)
    local argv = { "rex", "do", SCRIPT, "mode=down", "name=" .. args.name }
    if args.stop == false then argv[#argv + 1] = "stop=false" end
    return launch(ctx, "devbox down", argv)
  end,
})
