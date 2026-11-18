-- Rex script that connects a Namespace devbox as a Rex host.
-- Run it through the devbox_up and devbox_down actions in init.lua, or directly:
--
--   rex do ~/.config/rex/devbox.lua mode=up   [name=NAME] [blueprint=rex] [open=false]
--   rex do ~/.config/rex/devbox.lua mode=down  name=NAME  [stop=false]
--
-- It is a script, not an action body, because config-file actions have a 30 second
-- limit and creating a devbox takes longer.
--
-- The devbox is set up by its blueprint (see README.md): its service runs the Rex server with
-- Rex's built-in Tailscale node, which joins the tailnet as the person who signs in, so Rex
-- admits only that person. The first time, this script opens the sign-in link in the browser.
-- It runs nothing else inside the devbox except one no-op to wake a stopped devbox and a
-- read-only status call to find the sign-in link.
--
-- Needs: the `devbox` CLI (logged in) and the blueprint.

local BLUEPRINT = "rex"
-- The blueprint names the Rex node "rex-<devbox name>". Namespace's own tailnet node already
-- uses the bare devbox name.
local NODE_PREFIX = "rex-"
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

-- The Rex node's tailnet name, in this tailnet.
local function tailnet_name(name)
  local r = must({ "tailscale", "status", "--json" }, { timeout = 30 })
  local ok, st = pcall(rex.json.decode, r.stdout)
  if not ok or not st.MagicDNSSuffix or st.MagicDNSSuffix == "" then
    fail("cannot read the tailnet name from `tailscale status --json`")
  end
  return NODE_PREFIX .. name .. "." .. st.MagicDNSSuffix
end

-- The sign-in link in the devbox's Rex status, or nil. Only a Tailscale login URL is
-- accepted, because the text comes from another machine and is passed to `open`.
local function login_url(name)
  local r = run({ "devbox", "exec", name, "--", "rex", "server", "status", "--json" }, { timeout = 60 })
  if not r.ok then
    return nil
  end
  local text = r.stdout:gsub("\\/", "/"):gsub("\\u0026", "&")
  return text:match("https://login%.tailscale%.com/[%w%-%._~/%?=&%%]+")
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

-- State of the devbox's rex-server service: "running", another status, or nil when unknown.
local function service_status(devbox)
  local r = run({ "devbox", "service", "list", devbox, "-o", "json" }, { timeout = 30 })
  if not r.ok then
    return nil
  end
  local ok, res = pcall(rex.json.decode, r.stdout)
  if not ok or type(res) ~= "table" then
    return nil
  end
  for _, svc in ipairs(res.services or {}) do
    if svc.name == "rex-server" then
      return svc.status
    end
  end
  return "missing"
end

-- Whether the Rex node is online in the tailnet, from the local Tailscale client.
local function node_online(dns)
  local r = run({ "tailscale", "status", "--json" }, { timeout = 30 })
  if not r.ok then
    return false
  end
  local ok, st = pcall(rex.json.decode, r.stdout)
  if not ok or type(st) ~= "table" then
    return false
  end
  for _, peer in pairs(st.Peer or {}) do
    if (peer.DNSName or ""):gsub("%.$", "") == dns then
      return peer.Online == true
    end
  end
  return false
end

local START_SECONDS = 180 -- the service and the node must come up in this time
local SIGNIN_SECONDS = 600 -- time you get to sign in once the link is shown

-- Poll the service and the tailnet node. Fail as soon as the service is not running; open
-- the sign-in link once when one appears.
local function wait_reachable(label, devbox, dns)
  local started = os.time()
  local deadline = started + START_SECONDS
  local opened = nil
  local last = "node is not online in the tailnet"
  while true do
    local status = service_status(devbox)
    if status ~= nil and status ~= "running" then
      fail(
        "the rex-server service on " .. devbox .. " is " .. status .. ".\n"
          .. "Check `devbox service logs " .. devbox .. " rex-server`."
      )
    end
    if node_online(dns) then
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
    else
      local url = login_url(devbox)
      if url and url ~= opened then
        opened = url
        deadline = os.time() + SIGNIN_SECONDS
        say("sign in to Tailscale to own this devbox's Rex node:\n  " .. url)
        run({ "open", url }, { timeout = 15 })
      end
    end
    if os.time() >= deadline then
      fail(
        "registered host " .. label .. " but cannot reach https://" .. dns .. ".\n"
          .. (opened and "Sign in to Tailscale as the user who should own the node.\n" or "")
          .. "Last state: " .. last
      )
    end
    rex.sleep(3)
  end
end

-- Make sure the devbox's Rex server has a session named after the devbox, with one shell.
local function ensure_session(label)
  local server = rex.server(label)
  local res, err = server.call("session.list")
  if res == nil then
    fail("session.list on " .. label .. ": " .. tostring(err))
  end
  for _, sess in ipairs(res.sessions or {}) do
    if sess.label == label then
      return sess.session_id
    end
  end
  local created, cerr = server.call("session.create", {
    label = label,
    initial_windows = {
      { window_label = "shell", layout = { block = { flavor = "com.superlogical.terminal.shell", label = "shell" } } },
    },
  })
  if created == nil then
    fail("session.create on " .. label .. ": " .. tostring(cerr))
  end
  return created.session_id
end

local function up(args)
  local name = args.name or ("dev-" .. os.date("%m%d-%H%M%S"))
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
  say("waiting for the Rex node to answer ...")
  wait_reachable(name, name, dns)
  local session
  if args.open ~= false then
    session = ensure_session(name)
    say("session " .. name .. " is ready on the devbox.")
  end
  say("connected. Use: rex -S " .. name .. " ...")
  return { label = name, endpoint = "https://" .. dns, session_id = session }
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
