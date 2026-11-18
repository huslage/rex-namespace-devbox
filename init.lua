-- Rex config: devboxes appear as Rex hosts automatically.
--
-- A background script (devbox-sync.lua) lists your Namespace devboxes that install Rex, sets
-- up ssh access to each, and writes them to a cache file. This file declares a host for each
-- entry. Connect with `rex -S NAME`. The sync reloads this config when the list changes.
--
-- Install: copy init.lua and devbox-sync.lua to ~/.config/rex/ (merge into an existing init.lua).

local HOME = os.getenv("HOME") or ""
local SYNC = HOME .. "/.config/rex/devbox-sync.lua"
local CACHE = HOME .. "/.cache/rex-devbox/hosts"
-- The Rex server's PATH is minimal and misses the rex and devbox CLIs.
local REX_BIN = HOME .. "/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS"
local PATH = REX_BIN .. ":" .. HOME .. "/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

local r = rex.exec({ "cat", CACHE }, { env = { PATH = PATH } })
if r ~= nil and r.ok then
  for line in r.stdout:gmatch("[^\n]+") do
    local name, list = line:match("^(%S+) (%S+)$")
    if name then
      local endpoints = {}
      for endpoint in list:gmatch("[^,]+") do
        endpoints[#endpoints + 1] = endpoint
      end
      rex.host({ label = name, endpoints = endpoints, icon = "globe" })
    end
  end
end

-- The script exits at once when another copy is running.
rex.exec.start({ "rex", "do", SYNC }, { env = { PATH = PATH }, detach = true })
