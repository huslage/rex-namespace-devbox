-- Rex script that connects a Namespace devbox as a Rex host.
-- Run it through the devbox_up and devbox_down actions in init.lua, or directly:
--
--   rex do ~/.config/rex/devbox.lua mode=up   [name=NAME] [blueprint=rex]
--   rex do ~/.config/rex/devbox.lua mode=down  name=NAME  [stop=false]
--
-- It is a script, not an action body, because config-file actions have a 30 second
-- limit and creating a devbox takes longer.
--
-- The devbox is set up by its blueprint (see README.md): the blueprint's service shares the
-- Rex server with `tailscale serve`. This script runs nothing inside the devbox except one
-- no-op to wake a stopped devbox.
--
-- Needs: the `devbox` CLI (logged in), the blueprint, and a tailnet policy that lets you reach
-- tag:namespace-devbox on tcp:443 (see README.md).

local BLUEPRINT = "rex"
local PATH = (os.getenv("HOME") or "") .. "/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

local function say(msg)
  print(msg)
end

local function fail(msg)
  error(msg, 0)
end

local function run(argv, opts)
  opts = opts or {}
  opts.env = { PATH = PATH }
  local r, err = rex.exec(argv, opts)
  if r == nil then
    fail(argv[1] .. ": " .. tostring(err))
  end
  return r
end

local function must(argv, opts)
  local r = run(argv, opts)
  if not r.ok then
    fail(table.concat(argv, " ") .. " failed: " .. (r.stderr ~= "" and r.stderr or r.stdout))
  end
  return r
end

local function devbox_exists(name)
  local r = must({ "devbox", "list", "-o", "json" }, { timeout = 60 })
  local ok, boxes = pcall(rex.json.decode, r.stdout)
  if not ok or type(boxes) ~= "table" then
    fail("cannot parse `devbox list -o json` output")
  end
  for _, b in ipairs(boxes) do
    if b.name == name then
      return true
    end
  end
  return false
end

-- The devbox's tailnet name: Namespace names the node after the devbox, in this tailnet.
local function tailnet_name(name)
  local r = must({ "tailscale", "status", "--json" }, { timeout = 30 })
  local ok, st = pcall(rex.json.decode, r.stdout)
  if not ok or not st.MagicDNSSuffix or st.MagicDNSSuffix == "" then
    fail("cannot read the tailnet name from `tailscale status --json`")
  end
  return name .. "." .. st.MagicDNSSuffix
end

local function find_host(label)
  local res, err = rex.call("hosts.list")
  if res == nil then
    fail("hosts.list: " .. tostring(err))
  end
  for _, h in ipairs(res.hosts or {}) do
    if h.label == label then
      return h
    end
  end
  return nil
end

local function register_host(label, dns)
  local host = { label = label, endpoints = { "https://" .. dns }, icon = "globe" }
  local old = find_host(label)
  if old then
    host.id = old.id
  end
  local res, err = rex.call("hosts.put", { host = host })
  if res == nil then
    fail("hosts.put: " .. tostring(err))
  end
end

-- Netmap changes take a few seconds to reach this machine.
local function wait_reachable(label, dns)
  local last = ""
  for _ = 1, 40 do
    local ok, server = pcall(rex.server, label)
    if ok then
      local res, err = server.call("server.whoami")
      if res ~= nil then
        return
      end
      last = tostring(err)
    else
      last = tostring(server)
    end
    rex.sleep(3)
  end
  fail(
    "registered host " .. label .. " but cannot reach https://" .. dns .. ".\n"
      .. "If DNS fails (no such host), the tailnet policy probably does not let you reach "
      .. "tag:namespace-devbox on tcp:443.\nLast error: " .. last
  )
end

local function up(args)
  local name = args.name or ("rex-" .. os.date("%m%d-%H%M%S"))
  if devbox_exists(name) then
    say("devbox " .. name .. " exists; making sure it is running ...")
    must({ "devbox", "exec", name, "--", "true" }, { timeout = 180 })
  else
    local blueprint = args.blueprint or BLUEPRINT
    say("creating devbox " .. name .. " from blueprint " .. blueprint .. " ...")
    must({ "devbox", "create", "--name", name, "--blueprint", blueprint }, { timeout = 600 })
  end
  local dns = tailnet_name(name)
  say("registering host " .. name .. " (https://" .. dns .. ") ...")
  register_host(name, dns)
  say("waiting for the devbox to answer ...")
  wait_reachable(name, dns)
  say("connected. Use: rex -S " .. name .. " ...")
  return { label = name, endpoint = "https://" .. dns }
end

local function down(args)
  if not args.name then
    fail("name is required")
  end
  local old = find_host(args.name)
  if old then
    local res, err = rex.call("hosts.remove", { id = old.id })
    if res == nil then
      fail("hosts.remove: " .. tostring(err))
    end
  end
  if args.stop ~= false then
    must({ "devbox", "shutdown", args.name, "--force" }, { timeout = 120 })
  end
  say("disconnected " .. args.name)
  return { label = args.name, host_removed = old ~= nil, stopped = args.stop ~= false }
end

local args = rex.args or {}
if args.mode == "up" then
  return up(args)
elseif args.mode == "down" then
  return down(args)
end
fail("mode must be up or down")
