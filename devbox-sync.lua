-- Background sync of Namespace devboxes into Rex hosts. Started by init.lua.
--
--   rex do ~/.config/rex/devbox-sync.lua [once=true]
--
-- Every INTERVAL seconds it lists your devboxes that install Rex, runs `devbox configure-ssh`
-- for new ones, and writes the list to a cache file that init.lua reads. When the list
-- changes, it reloads the Rex config so the hosts appear.
--
-- Needs: the `devbox` CLI (logged in).

local INTERVAL = 30
local HOME = os.getenv("HOME") or ""
local CACHE = HOME .. "/.cache/rex-devbox"
local REX_BIN = HOME .. "/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS"
local PATH = REX_BIN .. ":" .. HOME .. "/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

local function sh(cmd, timeout)
  local r = rex.exec({ "sh", "-c", cmd }, { env = { PATH = PATH }, timeout = timeout or 60 })
  return r
end

local function run(argv, timeout)
  return rex.exec(argv, { env = { PATH = PATH }, timeout = timeout or 60 })
end

local function alive_recently()
  local r = sh('find "' .. CACHE .. '/alive" -mmin -2 2>/dev/null | grep -q .')
  return r ~= nil and r.ok
end

-- The alive file holds the token of the running copy and is rewritten on every loop.
local function claim(token)
  sh('mkdir -p "' .. CACHE .. '" && printf "%s" "' .. token .. '" > "' .. CACHE .. '/alive"')
end

local function owner()
  local r = sh('cat "' .. CACHE .. '/alive" 2>/dev/null')
  return r and r.ok and r.stdout or ""
end

-- True when the devbox installs Rex in its init script (the `rex` blueprint does).
local function installs_rex(box)
  local spec = box.spec or {}
  for _, step in ipairs(spec.on_create or {}) do
    local script = step.run_script and step.run_script.script or ""
    if script:find("pkgs.superlogical.com/rex", 1, true) then
      return true
    end
  end
  return false
end

local function read_cache()
  local r = sh('cat "' .. CACHE .. '/hosts" 2>/dev/null')
  return r and r.ok and r.stdout or ""
end

local function pass()
  local r = run({ "devbox", "list", "-o", "json" }, 60)
  if r == nil or not r.ok then
    print("devbox list failed: " .. tostring(r and r.stderr))
    return
  end
  local ok, boxes = pcall(rex.json.decode, r.stdout)
  if not ok or type(boxes) ~= "table" then
    print("cannot parse `devbox list -o json`")
    return
  end
  local old = read_cache()
  local lines = {}
  for _, box in ipairs(boxes) do
    local name = box.name
    -- The name goes into a shell command below.
    if type(name) == "string" and name:match("^[%w%-_]+$") and installs_rex(box) then
      local user = (box.spec and box.spec.remote_user) or "devbox"
      local endpoint = "ssh://" .. user .. "@" .. name .. ".devbox.namespace"
      if not old:find("^" .. name:gsub("%-", "%%-") .. " ") and not old:find("\n" .. name:gsub("%-", "%%-") .. " ") then
        local c = run({ "devbox", "configure-ssh", name }, 60)
        if c == nil or not c.ok then
          print("configure-ssh " .. name .. " failed: " .. tostring(c and c.stderr))
        end
      end
      lines[#lines + 1] = name .. " " .. endpoint
    end
  end
  table.sort(lines)
  local new = table.concat(lines, "\n")
  if new ~= old:gsub("\n$", "") then
    sh('mkdir -p "' .. CACHE .. '" && printf "%s\\n" \'' .. new:gsub("'", "") .. '\' > "' .. CACHE .. '/hosts"')
    print("devbox hosts changed; reloading the Rex config")
    -- The reload ends this script and starts a new one, which must not see us as running.
    sh('rm -f "' .. CACHE .. '/alive"')
    run({ "rex", "config", "reload" }, 30)
  end
end

local args = rex.args or {}
if args.once then
  pass()
  return "ok"
end
if alive_recently() then
  return "sync already running"
end
local token = tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999))
claim(token)
while true do
  pass()
  -- Another copy took over (after a reload): stop.
  local current = owner()
  if current ~= "" and current ~= token then
    return "replaced"
  end
  claim(token)
  rex.sleep(INTERVAL)
end
