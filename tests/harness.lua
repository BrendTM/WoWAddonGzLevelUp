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
--   world     - the simulated group; edit levels and dead/feign/far flags here
--   inRaid    - flips IsInRaid()
--   realm     - what GetRealmName() returns; with world.player.name it decides
--               which character profiles are bound to
--   now       - what GetTime() returns; move it forward to age things out
--   fire()    - deliver an event to the addon
--   runTimers() - run every queued timer callback
--   dropdownEntries(frame) - what a dropdown menu would offer right now
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
    party3    = { name = "Carol",   guid = "G-carol",  level = 42, exists = true },
}

-- --- Unit API --------------------------------------------------------------
function UnitExists(u) return world[u] ~= nil and world[u].exists end
function UnitGUID(u)   return world[u] and world[u].guid end
function UnitLevel(u)  return world[u] and world[u].level end
function UnitName(u)   return world[u] and world[u].name end

-- Death state. Tests set world.<unit>.dead / .feign and then fire UNIT_HEALTH.
function UnitIsDeadOrGhost(u) return world[u] ~= nil and world[u].dead == true end
function UnitIsFeignDeath(u)  return world[u] ~= nil and world[u].feign == true end

-- Range check, as (inRange, checkedRange). Tests set world.<unit>.far = true to
-- move somebody away; a unit the game does not know cannot be checked at all.
function UnitInRange(u)
    if world[u] == nil then return false, false end
    return not world[u].far, true
end
function IsInGroup()   return true end
function IsInRaid()    return inRaid end
function GetLocale()   return "enUS" end

-- Which character we are logged in as. Together with world.player.name this is
-- what profiles are bound to, so a test can "log in" as somebody else.
realm = "Blackrock"
function GetRealmName() return realm end

-- The clock the addon reads. Tests move `now` forward to let an offer go stale.
now = 0
function GetTime()     return now end

-- --- Chat ------------------------------------------------------------------
function SendChatMessage(msg, chan) sent[#sent + 1] = { msg = msg, chan = chan } end

testPrint = print
function print() end -- the addon's chat output is noise during tests

-- --- Misc globals the addon touches ----------------------------------------
function tinsert(t, v) table.insert(t, v) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function StaticPopup_Show() end

UIParent, StaticPopupDialogs, SlashCmdList, UISpecialFrames = {}, {}, {}, {}
ACCEPT, CANCEL = "Accept", "Cancel"

-- Dropdown menus. The init function is kept so a test can open the menu and
-- click an entry through dropdownEntries() below.
local dropInit = {}
function UIDropDownMenu_Initialize(frame, fn) dropInit[frame] = fn end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_SetText(frame, text) frame._dropText = text end
function UIDropDownMenu_CreateInfo() return {} end
function CloseDropDownMenus() end

-- Collected while the init function runs, so tests see what the menu offers.
local dropButtons
function UIDropDownMenu_AddButton(info) dropButtons[#dropButtons + 1] = info end

-- The entries a dropdown would show right now: { text, checked, func }.
function dropdownEntries(frame)
    dropButtons = {}
    if dropInit[frame] then dropInit[frame](frame, 1) end
    return dropButtons
end
-- The minimap button anchors to this and reads the cursor while dragging.
Minimap = setmetatable({
    GetCenter = function() return 100, 100 end,
    GetEffectiveScale = function() return 1 end,
}, { __index = function() return function() end end })
function GetCursorPosition() return 100, 100 end
YES, NO = "Yes", "No"
GameTooltip = setmetatable({}, { __index = function() return function() end end })

C_Timer = {
    After = function(sec, fn) timers[#timers + 1] = { sec = sec, fn = fn } end,
}

-- Frames are inert: every method is a no-op that hands back another stub, so
-- chains like button:CreateTexture():SetTexture() keep working.
--
-- Three groups of methods are real, because the addon computes with them:
--   SetScript("OnEvent") - captured so tests can deliver events
--   SetText/GetStringWidth - so label-driven layout can be measured
--   SetWidth/SetHeight/SetSize/GetWidth/GetHeight - so a frame that sizes
--   itself from its children can be asserted on
--
-- The string width is an approximation, not the game's font metrics: a fixed
-- pixels-per-character, counting UTF-8 characters rather than bytes so umlauts
-- do not count double. Good enough to tell "German is wider than English"
-- apart, not good enough to predict an exact pixel.
local PX_PER_CHAR = 6

local function utf8len(s)
    local n = 0
    for _ in tostring(s):gmatch("[^\128-\191]") do n = n + 1 end
    return n
end

-- Anything not in `real` yields another stub. That stub is both callable and
-- indexable, so a method call (frame:SetPoint(...)) and a sub-widget lookup
-- (slider.Low:SetText(...)) both work without knowing which one the addon meant.
local function frameStub()
    local self = { _w = 0, _h = 0, _text = "", _children = {}, _scripts = {} }
    local real = {
        SetScript = function(o, script, fn)
            if script == "OnEvent" then handler = fn end
            o._scripts[script] = fn
        end,
        -- Kept so a test can click a button: GetScript("OnClick")().
        GetScript = function(o, script) return o._scripts[script] end,
        SetText   = function(o, s) o._text = s or "" end,
        GetText   = function(o) return o._text end,
        -- Real, because the addon branches on it: an auto-stub would read as
        -- "checked" no matter what.
        SetChecked = function(o, v) o._checked = v and true or false end,
        GetChecked = function(o) return o._checked end,
        -- Same for visibility, so a test can tell which of the pooled quick
        -- panel buttons are actually on screen.
        Show    = function(o) o._shown = true end,
        Hide    = function(o) o._shown = false end,
        IsShown = function(o) return o._shown and true or false end,
        -- Anchors, so a test can read back where a frame was put. Both call
        -- shapes the addon uses: SetPoint(point [, x, y]) and the long
        -- SetPoint(point, relativeTo, relPoint, x, y).
        SetPoint = function(o, point, a, b, c, d)
            if type(a) == "table" then
                o._point, o._relPoint, o._x, o._y = point, b, c or 0, d or 0
            else
                o._point, o._relPoint, o._x, o._y = point, point, a or 0, b or 0
            end
        end,
        GetPoint = function(o) return o._point, nil, o._relPoint, o._x, o._y end,
        ClearAllPoints = function(o)
            o._point, o._relPoint, o._x, o._y = nil, nil, 0, 0
        end,
        SetWidth  = function(o, w) o._w = w end,
        SetHeight = function(o, h) o._h = h end,
        SetSize   = function(o, w, h) o._w, o._h = w, h end,
        GetWidth  = function(o) return o._w end,
        GetHeight = function(o) return o._h end,
        GetStringWidth = function(o) return utf8len(o._text) * PX_PER_CHAR end,
    }
    return setmetatable(self, {
        __call  = function() return frameStub() end,
        __index = function(o, key)
            if real[key] then return real[key] end
            if o._children[key] == nil then o._children[key] = frameStub() end
            return o._children[key]
        end,
    })
end

-- Named frames land in _G, the same way the game does it, so a test can reach
-- the config window as GzLevelUpConfigFrame.
function CreateFrame(_, name)
    local f = frameStub()
    if name then _G[name] = f end
    return f
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
