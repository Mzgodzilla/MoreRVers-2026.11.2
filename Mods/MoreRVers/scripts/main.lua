-- MoreRVers 1.0.2-compat
-- Host-side fix for RV There Yet? 1.4.x, where the game rewrites
-- GameSession.MaxPlayers back to 4 after the object is constructed.
-- Keeps the value applied at initialization, map load, player login,
-- session-settings updates and (as a safety net) on a short timer.

local VERSION = "1.0.2"

local source = debug.getinfo(1, "S").source:gsub("\\", "/")
local script_dir = source:match("^@(.*/)") or ""

local function log(msg)
  print("[MoreRVers] " .. tostring(msg) .. "\n")
end

-- ---------------------------------------------------------------- config
local cap = 8
do
  local ok, result = pcall(function()
    local file = assert(io.open(script_dir .. "../config.ini", "r"))
    local value = nil
    for raw in file:lines() do
      local line = raw:gsub("^\239\187\191", "")
      local key, number = line:match("^%s*([%w_]+)%s*=%s*(%-?%d+)")
      if key and key:lower() == "maxplayers" then
        value = tonumber(number)
        break
      end
    end
    file:close()
    return value
  end)
  if ok and result then
    cap = math.max(1, math.min(24, math.floor(result)))
  else
    log("config.ini unreadable (" .. tostring(result) .. "); falling back to " .. cap)
  end
end

local writes = 0
local failures_logged = 0

local function valid(object)
  if object == nil then return false end
  local ok, result = pcall(function() return object:IsValid() end)
  return ok and result == true
end

local function name_of(object)
  local ok, name = pcall(function() return object:GetFullName() end)
  if ok then return tostring(name) end
  return "<unknown>"
end

local function note_failure(message)
  if failures_logged >= 6 then return end
  failures_logged = failures_logged + 1
  log(message)
end

local function set_cap(object, reason)
  if not valid(object) then return false end
  local ok_read, before = pcall(function() return object.MaxPlayers end)
  if not ok_read then return false end
  if before == cap then return true end

  local ok_write, err = pcall(function() object.MaxPlayers = cap end)
  if not ok_write then
    note_failure("write failed [" .. reason .. "] " .. tostring(err) .. " on " .. name_of(object))
    return false
  end

  local ok_verify, after = pcall(function() return object.MaxPlayers end)
  if not ok_verify or after ~= cap then
    note_failure("write did not stick [" .. reason .. "] expected " .. cap
      .. " read " .. tostring(after) .. " on " .. name_of(object))
    return false
  end

  writes = writes + 1
  log("MaxPlayers " .. tostring(before) .. " -> " .. tostring(after)
    .. " [" .. reason .. "] " .. name_of(object))
  return true
end

local function apply_all(reason)
  local ok_cdo, cdo = pcall(function()
    return StaticFindObject("/Script/Engine.Default__GameSession")
  end)
  if ok_cdo and cdo then
    set_cap(cdo, reason .. "/cdo")
  end

  local ok_find, sessions = pcall(function() return FindAllOf("GameSession") end)
  if ok_find and type(sessions) == "table" then
    for _, session in ipairs(sessions) do
      set_cap(session, reason)
    end
  end
end

local function unwrap(context)
  if context == nil then return nil end
  local ok, object = pcall(function() return context:get() end)
  if ok and object ~= nil then return object end
  return context
end

-- ------------------------------------------------------------ diagnostics
local dumped = false
local function dump_properties(reason)
  if dumped then return end
  dumped = true
  local ok, err = pcall(function()
    local file = assert(io.open(script_dir .. "session_dump.txt", "w"))
    file:write("MoreRVers " .. VERSION .. " session dump (" .. tostring(reason) .. ")\n")
    local sessions = FindAllOf("GameSession") or {}
    for _, session in ipairs(sessions) do
      file:write("\nOBJECT " .. name_of(session) .. " MaxPlayers="
        .. tostring(session.MaxPlayers) .. "\n")
      local ok_props, props = pcall(function() return session:GetProperties() end)
      if ok_props and props then
        local keys = {}
        for key in pairs(props) do keys[#keys + 1] = tostring(key) end
        table.sort(keys)
        for _, key in ipairs(keys) do
          file:write("  " .. key .. " = " .. tostring(props[key]) .. "\n")
        end
      else
        file:write("  <GetProperties unavailable>\n")
      end
    end
    file:close()
  end)
  if not ok then log("dump failed: " .. tostring(err)) end
end

-- ----------------------------------------------------------------- hooks
local function register(label, fn)
  local ok, err = pcall(fn)
  if ok then
    log("hook ok: " .. label)
  else
    log("hook failed: " .. label .. " -> " .. tostring(err))
  end
  return ok
end

register("InitGameState", function()
  RegisterInitGameStatePostHook(function(context)
    local ok, err = pcall(function()
      local mode = unwrap(context)
      if valid(mode) then
        set_cap(mode.GameSession, "game initialized")
      end
    end)
    if not ok then log("InitGameState error: " .. tostring(err)) end
  end)
end)

register("LoadMap", function()
  RegisterLoadMapPostHook(function()
    local ok, err = pcall(function()
      apply_all("map loaded")
      dump_properties("map loaded")
    end)
    if not ok then log("LoadMap error: " .. tostring(err)) end
    -- Return nothing: the engine's LoadMap result has to be preserved.
  end)
end)

register("K2_PostLogin", function()
  RegisterCustomEvent("K2_PostLogin", function(context)
    local ok, err = pcall(function()
      local mode = unwrap(context)
      if valid(mode) then
        set_cap(mode.GameSession, "player login")
      end
    end)
    if not ok then log("K2_PostLogin error: " .. tostring(err)) end
  end)
end)

register("UpdateSessionSettings", function()
  RegisterHook("/Script/Ride.RGGameSession:UpdateSessionSettings", function(self)
    local ok, err = pcall(function()
      local session = unwrap(self)
      if valid(session) then
        set_cap(session, "session settings")
      end
    end)
    if not ok then log("UpdateSessionSettings error: " .. tostring(err)) end
    return nil
  end)
end)

register("timer", function()
  LoopAsync(1500, function()
    local ok, err = pcall(function()
      ExecuteInGameThread(function()
        local ok_apply, err_apply = pcall(apply_all, "timer")
        if not ok_apply then log("timer apply error: " .. tostring(err_apply)) end
      end)
    end)
    if not ok then log("timer error: " .. tostring(err)) end
  end)
end)

local ok_start, err_start = pcall(function()
  ExecuteInGameThread(function()
    local ok, err = pcall(apply_all, "startup")
    if not ok then log("startup apply error: " .. tostring(err)) end
  end)
end)
if not ok_start then log("ExecuteInGameThread unavailable: " .. tostring(err_start)) end

log("v" .. VERSION .. " loaded; target MaxPlayers=" .. cap)
