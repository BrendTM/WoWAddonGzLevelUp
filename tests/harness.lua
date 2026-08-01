-- Minimal stub of the WoW API, just enough to load the addon outside the game
-- and drive it through real events.
--
-- The addon is loaded unmodified; everything it talks to lives here. Chat
-- output is captured instead of sent, and C_Timer callbacks are queued so a
-- test can decide when time passes.
--
-- Exposed to the tests (globals, so run.lua can use them directly):
--   sent      - list of { msg, chan } that reached SendChatMessage
--   timers    - queued C_Timer.After callbacks, { sec, fn }
--   world     - the simulated group; edit levels here
--   inRaid    - flips IsInRaid()
--   fire()    - deliver an event to the addon
--   runTimers() - run every queued timer callback
--   testPrint - the real print, since the addon's print is silenced

local M = {}

sent, timers, handler = {}, {}, nil
inRaid = false

-- The simulated group. Levels are mutated by the tests to trigger level-ups.
world = {
    player    = { name = "Brend",   guid = "G-me",     level = 55, exists = true },
    pet       = { name = "Snuggle", guid = "G-mypet",  level = 54, exists = true },
    party1    = { name = "Alice",   guid = "G-alice",  level = 40, exists = true },
    partypet1 = { name = "Fluffy",  guid = "G-fluffy", level = 39, exists = true },
    party2    = { name = "Bob",     guid = "G-bob",    level = 41, exists = true },
}

-- --- Unit API --------------------------------------------------------------
function UnitExists(u) return world[u] ~= nil and world[u].exists end
function UnitGUID(u)   return world[u] and world[u].guid end
function UnitLevel(u)  return world[u] and world[u].level end
function UnitName(u)   return world[u] and world[u].name end
function IsInGroup()   return true end
function IsInRaid()    return inRaid end
function GetLocale()   return "enUS" end

-- --- Chat ------------------------------------------------------------------
function SendChatMessage(msg, chan) sent[#sent + 1] = { msg = msg, chan = chan } end

testPrint = print
function print() end -- the addon's chat output is noise during tests

-- --- Misc globals the addon touches ----------------------------------------
function tinsert(t, v) table.insert(t, v) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function StaticPopup_Show() end

UIParent, StaticPopupDialogs, SlashCmdList = {}, {}, {}
YES, NO = "Yes", "No"
GameTooltip = setmetatable({}, { __index = function() return function() end end })

C_Timer = {
    After = function(sec, fn) timers[#timers + 1] = { sec = sec, fn = fn } end,
}

-- Frames are inert: every method is a no-op, except SetScript("OnEvent"),
-- which is captured so tests can deliver events. The config window is only
-- built on /gz, so the stub does not need to be more capable than this.
function CreateFrame()
    local f = {}
    f.RegisterEvent = function() end
    f.SetScript = function(_, script, fn)
        if script == "OnEvent" then handler = fn end
    end
    return setmetatable(f, { __index = function() return function() end end })
end

-- --- Test controls ---------------------------------------------------------

-- Deliver an event to the addon's OnEvent handler.
function fire(event, arg1, arg2) handler(nil, event, arg1, arg2) end

-- Let time pass: run every queued callback once.
function runTimers()
    local due = timers
    timers = {}
    for _, entry in ipairs(due) do entry.fn() end
end

-- Parsed .toc, so GetAddOnMetadata answers the same way it does in the game.
local toc = {}
function GetAddOnMetadata(_, field) return toc[field] end

-- Load the addon files, emulating the "local ADDON, ns = ..." header.
function M.loadAddon(root)
    for line in io.lines(root .. "/GzLevelUp/GzLevelUp.toc") do
        local key, value = line:match("^##%s*([%w%-]+)%s*:%s*(.-)%s*$")
        if key then toc[key] = value end
    end

    local ns = {}
    for _, file in ipairs({ "Locale.lua", "GzLevelUp.lua" }) do
        local path = root .. "/GzLevelUp/" .. file
        assert(loadfile(path), "cannot load " .. path)("GzLevelUp", ns)
    end
end

return M
