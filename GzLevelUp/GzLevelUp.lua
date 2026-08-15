local ADDON, ns = ...
local L = ns.L

-- Restored from SavedVariables (or created empty on first launch).
GzLevelUpDB = GzLevelUpDB or {}

local defaults = {
    enabled       = true,
    useRaidChat   = false,                    -- stay quiet in raids unless asked
    -- One switch, one message and one delay per announcement category.
    announceGroup = true,                     -- announce group members?
    includeSelf   = false,                    -- also announce my own level-up?
    includePets   = false,                    -- also announce pets/companions?
    message       = L.DEFAULT_MESSAGE,        -- message for group members
    selfMessage   = L.DEFAULT_SELF_MESSAGE,   -- message for own level-up
    petMessage    = L.DEFAULT_PET_MESSAGE,    -- message for a pet's level-up
    groupDelay    = 0,                        -- seconds before sending, 0 = now
    selfDelay     = 0,
    petDelay      = 0,
    -- Death reply: react when someone in the group (or I myself) dies.
    -- Fully opt-in, including the wipe line.
    announceDeaths    = false,                -- announce a group member's death?
    announceSelfDeath = false,                -- announce my own death?
    announceWipe      = false,                -- say something when the group wipes?
    deathMessage      = L.DEFAULT_DEATH_MESSAGE,
    selfDeathMessage  = L.DEFAULT_SELF_DEATH_MESSAGE,
    wipeMessage       = L.DEFAULT_WIPE_MESSAGE,
    deathDelay        = 0,
    selfDeathDelay    = 0,
    wipeDelay         = 0,
    deathCollect      = 3,                    -- batch deaths for this long
    deathWipeLimit    = 3,                    -- that many at once = a wipe
    -- Resurrection reply: the counterpart, when someone is back on their feet.
    announceRez       = false,                -- announce a group member's rez?
    announceSelfRez   = false,                -- announce that I was rezzed?
    rezMessage        = L.DEFAULT_REZ_MESSAGE,
    selfRezMessage    = L.DEFAULT_SELF_REZ_MESSAGE,
    rezDelay          = 0,
    selfRezDelay      = 0,
    rezCollect        = 3,                    -- batch resurrections for this long
    quickPanelEnabled = false,               -- show floating gz/ty panel?
    quickPanelScale   = 1.0,                 -- panel scale (0.5 - 2.0)
    minimapEnabled    = false,               -- show the minimap button?
    minimapAngle      = 210,                 -- its position around the minimap
    gzButtonMessage   = "gz",                -- text of the left button
    tyButtonMessage   = "ty",                -- text of the right button
    -- Auto reply: say "ty" once after people congratulated my own level-up.
    autoReplyEnabled  = false,
    replyMessage      = L.DEFAULT_REPLY,
    replyTriggers     = L.DEFAULT_TRIGGERS,  -- comma separated words
    replyCollect      = 6,                   -- keep collecting after the 1st gz
    replyWindow       = 30,                  -- give up listening after this
    -- quickPanelPos / configPos are saved when a window is moved
    -- (deliberately not in defaults: "no entry" means "centered").
}

-- Everything that differs between the three announcement categories, in one
-- place: which DB keys hold its switch, its message template and its delay.
local CATEGORY = {
    member = { enabled = "announceGroup", message = "message",     delay = "groupDelay" },
    self   = { enabled = "includeSelf",   message = "selfMessage", delay = "selfDelay"  },
    pet    = { enabled = "includePets",   message = "petMessage",  delay = "petDelay"   },
}

-- Display order of the categories wherever all three are listed.
local CATEGORY_ORDER = { "member", "self", "pet" }

-- The same three keys once more, for the death reply. Deliberately a separate
-- table: these must not show up in the Messages tab or in "/gz test"'s
-- level-up preview.
local DEATH = {
    member = { enabled = "announceDeaths",    message = "deathMessage",     delay = "deathDelay"     },
    self   = { enabled = "announceSelfDeath", message = "selfDeathMessage", delay = "selfDeathDelay" },
    wipe   = { enabled = "announceWipe",      message = "wipeMessage",      delay = "wipeDelay"      },
}

local DEATH_ORDER = { "member", "self", "wipe" }

-- And once more for the resurrection reply. It shares the death tab and the
-- batching, but not the wipe line: coming back is never bad news.
local REZ = {
    member = { enabled = "announceRez",     message = "rezMessage",     delay = "rezDelay"     },
    self   = { enabled = "announceSelfRez", message = "selfRezMessage", delay = "selfRezDelay" },
}

local REZ_ORDER = { "member", "self" }

-- Every category there is, for the commands that address all of them at once.
local ALL_CATEGORIES = {
    CATEGORY.member, CATEGORY.self, CATEGORY.pet,
    DEATH.member,    DEATH.self,    DEATH.wipe,
    REZ.member,      REZ.self,
}

-- What the user may type after "/gz delay" to address a single category.
local DELAY_ALIAS = {
    group     = CATEGORY.member, member = CATEGORY.member,
    self      = CATEGORY.self,
    pets      = CATEGORY.pet,    pet    = CATEGORY.pet,
    death     = DEATH.member,    deaths = DEATH.member,
    selfdeath = DEATH.self,
    wipe      = DEATH.wipe,
    rez       = REZ.member,      rezzes = REZ.member,
    selfrez   = REZ.self,
}

local MAX_DELAY = 60
local MAX_WIPE  = 40              -- a full raid; the largest group there is
local MIN_SCALE, MAX_SCALE = 0.5, 2.0

local function ClampDelay(n)
    n = tonumber(n) or 0
    if n < 0 then n = 0 end
    if n > MAX_DELAY then n = MAX_DELAY end
    return n
end

-- Head count, e.g. "how many deaths at once count as a wipe". 0 = never.
local function ClampCount(n)
    n = tonumber(n) or 0
    if n < 0 then n = 0 end
    if n > MAX_WIPE then n = MAX_WIPE end
    return math.floor(n)
end

local function ClampScale(n)
    n = tonumber(n) or 1
    if n < MIN_SCALE then n = MIN_SCALE end
    if n > MAX_SCALE then n = MAX_SCALE end
    return n
end

-- GUID -> last known level. Keyed by GUID instead of a unit token so that
-- "party1" isn't later mistakenly attributed to a different player.
local knownLevels = {}

-- GUID -> is that unit dead right now? Same reasoning as knownLevels: only the
-- transition alive -> dead is a death. A GUID that is not in here yet has
-- never been seen alive, so it is not announced either.
local knownDead = {}

local PREFIX = "|cff33ff99GzLevelUp|r: "

-- The single global delay (delayEnabled + delaySeconds) became one delay per
-- category. Carry the old value over to all three, then drop the old keys.
local function Migrate()
    if GzLevelUpDB.delaySeconds == nil and GzLevelUpDB.delayEnabled == nil then return end
    local old = GzLevelUpDB.delayEnabled and ClampDelay(GzLevelUpDB.delaySeconds) or 0
    for _, kind in ipairs(CATEGORY_ORDER) do
        local key = CATEGORY[kind].delay
        if GzLevelUpDB[key] == nil then GzLevelUpDB[key] = old end
    end
    GzLevelUpDB.delayEnabled = nil
    GzLevelUpDB.delaySeconds = nil
end

local function ApplyDefaults()
    Migrate()
    for k, v in pairs(defaults) do
        if GzLevelUpDB[k] == nil then
            GzLevelUpDB[k] = v
        end
    end
end

-- Replace {name}/{level}/{owner} in a template. When a name list is passed in,
-- {names} and {count} work too — {names} has to go first, otherwise {name}
-- would already have eaten its prefix.
local function Format(template, name, level, owner, names)
    local text = template or ""
    if names then
        text = text:gsub("{names}", table.concat(names, ", "))
                   :gsub("{count}", tostring(#names))
    end
    return (text
        :gsub("{name}", name or "?")
        :gsub("{level}", tostring(level or 0))
        :gsub("{owner}", owner or "?"))
end

-- "Brend-Realm" -> "Brend". Cross-realm names arrive with a realm suffix,
-- both from chat and from a resurrect offer.
local function ShortName(name)
    if not name or name == "" then return nil end
    return name:match("^([^-]+)") or name
end

-- Remembers where the user dragged a frame to, under the given DB key.
-- Anchoring is always relative to UIParent so the value survives a reload.
local function SavePos(frame, key)
    local point, _, relPoint, x, y = frame:GetPoint()
    GzLevelUpDB[key] = { point = point, relPoint = relPoint, x = x, y = y }
end

-- Counterpart to SavePos; centers the frame if there is nothing stored yet.
local function RestorePos(frame, key)
    local pos = GzLevelUpDB[key]
    frame:ClearAllPoints()
    if pos and pos.point then
        frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        frame:SetPoint("CENTER")
    end
end

-- ---------------------------------------------------------------------------
-- Core logic: detect a level-up and send "gz"
-- ---------------------------------------------------------------------------

-- Maps a unit token to its category — anything else (target, mouseover, ...)
-- yields nil. Ignores the on/off switches, so it also answers "is this unit
-- worth tracking at all?".
local function UnitCategory(unit)
    if unit == "player" then return "self" end
    if unit == "pet" then return "pet" end
    if unit:match("^party[1-4]$") or unit:match("^raid%d+$") then return "member" end
    if unit:match("^partypet[1-4]$") or unit:match("^raidpet%d+$") then return "pet" end
    return nil
end

-- Applies the switches on top: returns the category only if it may announce.
local function ClassifyUnit(unit)
    local kind = UnitCategory(unit)
    if not kind then return nil end
    -- My own pet additionally follows the "my own level-ups" switch.
    if unit == "pet" and not GzLevelUpDB.includeSelf then return nil end
    return GzLevelUpDB[CATEGORY[kind].enabled] and kind or nil
end

-- "partypet2" -> "party2", "raidpet7" -> "raid7", "pet" -> "player".
local function OwnerOf(petUnit)
    if petUnit == "pet" then return "player" end
    return (petUnit:gsub("pet", "", 1))
end

-- "party2" -> "partypet2", "raid7" -> "raidpet7", "player" -> "pet".
local function PetOf(ownerUnit)
    if ownerUnit == "player" then return "pet" end
    local prefix, index = ownerUnit:match("^(party)([1-4])$")
    if not prefix then prefix, index = ownerUnit:match("^(raid)(%d+)$") end
    return prefix and (prefix .. "pet" .. index) or nil
end

local function RecordLevel(unit)
    if not unit or not UnitExists(unit) then return end
    local guid = UnitGUID(unit)
    local lvl  = UnitLevel(unit)
    if guid and lvl and lvl > 0 then
        knownLevels[guid] = lvl
    end
end

-- A hunter who feigns death is reported as dead by the unit API, which would
-- be an embarrassing false alarm — so that case is filtered out explicitly.
local function IsDead(unit)
    if UnitIsFeignDeath and UnitIsFeignDeath(unit) then return false end
    return UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) and true or false
end

-- Right after joining, the roster already lists a member while their unit data
-- is still on its way: the name reads as "Unknown" and the health API claims
-- they are alive. Taking that as the alive/dead baseline turned a member who
-- had been lying dead the whole time into a fresh death seconds later — and
-- announced them as "Unknown" on top. So a unit only counts once its name has
-- actually arrived.
local UNKNOWN = UNKNOWNOBJECT or "Unknown"

local function UnitReady(unit)
    local name = UnitName(unit)
    return name ~= nil and name ~= "" and name ~= UNKNOWN
end

local function RecordDead(unit)
    if not unit or not UnitExists(unit) then return end
    if not UnitReady(unit) then return end
    local guid = UnitGUID(unit)
    if guid then knownDead[guid] = IsDead(unit) end
end

-- Silently read every member's current level and alive/dead state, so joining
-- a group, summoning a pet or walking up to a corpse never produces a message.
-- Pets are recorded even when the option is off; that way turning it on later
-- can't misfire on a stale level. Only players get a death state — a pet dying
-- is not worth announcing.
local function SyncGroup()
    RecordLevel("player")
    RecordLevel("pet")
    RecordDead("player")
    if IsInRaid() then
        for i = 1, 40 do
            RecordLevel("raid" .. i)
            RecordLevel("raidpet" .. i)
            RecordDead("raid" .. i)
        end
    elseif IsInGroup() then
        for i = 1, 4 do
            RecordLevel("party" .. i)
            RecordLevel("partypet" .. i)
            RecordDead("party" .. i)
        end
    end
end

-- The same snapshot for a single unit whose data reached us only after
-- SyncGroup had already run. It fills gaps only: an entry that is already
-- there is a real observation and must survive, otherwise a death could be
-- overwritten away between the two events.
local function SyncLateUnit(unit)
    if not unit then return end
    local kind = UnitCategory(unit)
    if not kind or not UnitExists(unit) then return end

    local guid = UnitGUID(unit)
    if not guid then return end
    if knownLevels[guid] == nil then RecordLevel(unit) end
    if kind ~= "pet" and knownDead[guid] == nil then RecordDead(unit) end
end

-- The chat channel the addon may use right now, or nil to stay quiet.
-- Raids are opt-in: in a 40-man raid an automatic "gz" per level-up is spam
-- for most people, so the addon says nothing there unless useRaidChat is set.
local function GroupChannel()
    if IsInRaid() then
        return GzLevelUpDB.useRaidChat and "RAID" or nil
    end
    if IsInGroup() then return "PARTY" end
    return nil
end

-- Sends the (already formatted) message to party/raid chat.
-- Channel and conditions are only checked at the actual moment of sending,
-- since the group may have changed during a delay.
local function SendNow(msg)
    if not GzLevelUpDB.enabled then return end
    local channel = GroupChannel()
    if not channel then return end
    SendChatMessage(msg, channel)
end

-- Fills in one category's template and sends it after that category's delay.
-- The placeholders are substituted NOW (at the moment of the event), only the
-- sending waits.
local function Dispatch(cat, name, level, owner, names)
    local msg   = Format(GzLevelUpDB[cat.message], name, level, owner, names)
    local delay = ClampDelay(GzLevelUpDB[cat.delay])
    if delay > 0 then
        C_Timer.After(delay, function() SendNow(msg) end)
    else
        SendNow(msg)
    end
end

local function Announce(unit, kind)
    if not GzLevelUpDB.enabled then return end
    if not GroupChannel() then return end

    local owner = (kind == "pet") and UnitName(OwnerOf(unit)) or nil
    Dispatch(CATEGORY[kind], UnitName(unit), UnitLevel(unit), owner)
end

-- ---------------------------------------------------------------------------
-- Death and resurrection reply: react when a group member, or I myself, goes
-- down — and when someone is back on their feet
-- ---------------------------------------------------------------------------

-- Neither comes alone: a pull goes wrong and half the group is on the floor,
-- then the healer picks them all back up. Both are therefore collected for a
-- moment and answered with a single message. `session` invalidates the timer
-- of an earlier batch, since C_Timer.After cannot be cancelled.
local function NewBatch()
    return {
        session = 0, open = false,
        all = {},     -- everyone in this batch, me included
        others = {},  -- everyone except me
        seen = {}, mine = false, who = nil, level = 0,
    }
end

local deaths, rezzes = NewBatch(), NewBatch()

local function FlushDeaths(session)
    if deaths.session ~= session then return end
    deaths.open = false
    if #deaths.all == 0 then return end

    -- Too many at once is a wipe. Then there is exactly one thing to say about
    -- it — or, if the wipe line is switched off, nothing at all.
    local limit = ClampCount(GzLevelUpDB.deathWipeLimit)
    if limit > 0 and #deaths.all >= limit then
        if GzLevelUpDB.announceWipe then
            Dispatch(DEATH.wipe, deaths.all[1], deaths.level, nil, deaths.all)
        end
        return
    end

    if deaths.mine and GzLevelUpDB.announceSelfDeath then
        Dispatch(DEATH.self, UnitName("player"), UnitLevel("player"))
    end
    if #deaths.others > 0 and GzLevelUpDB.announceDeaths then
        Dispatch(DEATH.member, deaths.others[1], deaths.level, nil, deaths.others)
    end
end

-- Who offered me the last resurrect, so my own line can thank them by name.
-- Only another player's spell fires RESURRECT_REQUEST — a spirit healer or a
-- soulstone does not — which is exactly the line between "somebody got me up"
-- and "I got myself up".
local rezOffer = { name = nil, at = 0 }
local REZ_OFFER_WINDOW = 60 -- the in-game dialog does not last any longer

local function RememberRezOffer(caster)
    rezOffer.name, rezOffer.at = ShortName(caster), GetTime and GetTime() or 0
end

-- The group unit token of a player by name, or nil when they are not in the
-- group at all — a passer-by can pick you up just as well.
local function GroupUnitByName(name)
    if not name then return nil end
    local prefix, count = "party", 4
    if IsInRaid() then prefix, count = "raid", 40 end
    for i = 1, count do
        local unit = prefix .. i
        if UnitExists(unit) and ShortName(UnitName(unit)) == name then return unit end
    end
    return nil
end

-- Accepting a resurrect puts you back at your corpse, next to whoever cast it;
-- taking the spirit healer instead puts you at the graveyard, far from them.
-- So the caster still being in range is what separates the two — the game
-- itself never tells an addon that an offer was declined.
--
-- Only a clear "out of range" counts against it. Someone outside the group
-- cannot be range-checked at all, and dropping those would cost more than it
-- saves.
local function StillNearby(name)
    if not UnitInRange then return true end
    local unit = GroupUnitByName(name)
    if not unit then return true end

    local inRange, checked = UnitInRange(unit)
    if not checked then return true end
    return inRange and true or false
end

-- Hands out the pending offer once: whoever got me up, or nil if nobody did.
-- An offer that has gone stale, or whose caster is no longer anywhere near,
-- does not count.
local function ClaimRezOffer()
    local who, when = rezOffer.name, rezOffer.at
    rezOffer.name = nil
    if not who then return nil end
    if GetTime and (GetTime() - when) > REZ_OFFER_WINDOW then return nil end
    if not StillNearby(who) then return nil end
    return who
end

local function FlushRezzes(session)
    if rezzes.session ~= session then return end
    rezzes.open = false
    if #rezzes.all == 0 then return end

    -- {name} in my own line is whoever got me up, not me: "ty {name}" is the
    -- whole point of the line.
    if rezzes.mine and GzLevelUpDB.announceSelfRez then
        Dispatch(REZ.self, rezzes.who, UnitLevel("player"))
    end
    if #rezzes.others > 0 and GzLevelUpDB.announceRez then
        Dispatch(REZ.member, rezzes.others[1], rezzes.level, nil, rezzes.others)
    end
end

-- Adds one name to a batch, opening a new one if needed. Every death is
-- collected regardless of its own switch, so that a death nobody wants
-- announced still counts towards the wipe threshold.
local function Collect(batch, collectKey, flush, kind, name, level)
    if not GzLevelUpDB.enabled then return end
    if not GroupChannel() then return end
    if not name then return end

    if not batch.open then
        batch.open    = true
        batch.session = batch.session + 1
        batch.all, batch.others, batch.seen = {}, {}, {}
        batch.mine, batch.who, batch.level = false, nil, 0

        local session = batch.session
        C_Timer.After(ClampDelay(GzLevelUpDB[collectKey]), function() flush(session) end)
    end

    -- My own entry is kept apart from the name list: for a resurrect `name` is
    -- the person who rezzed me, and that one may well be in the list too.
    if kind == "self" then
        if batch.mine then return end
        batch.mine, batch.who = true, name
    else
        if batch.seen[name] then return end
        batch.seen[name] = true
        batch.others[#batch.others + 1] = name
    end

    batch.all[#batch.all + 1] = name
    if #batch.all == 1 then batch.level = level end
end

local function QueueDeath(kind, name, level)
    Collect(deaths, "deathCollect", FlushDeaths, kind, name, level)
end

local function QueueRez(kind, name, level)
    Collect(rezzes, "rezCollect", FlushRezzes, kind, name, level)
end

-- Edge detector on top of the unit API: alive -> dead is a death, dead -> alive
-- a resurrect. Both directions run through the same flag, so each of them is
-- answered exactly once no matter how many events report it.
local function CheckDeathOrRez(unit)
    -- Cheapest possible exit: UNIT_HEALTH fires constantly during combat.
    if not (GzLevelUpDB.announceDeaths or GzLevelUpDB.announceSelfDeath
            or GzLevelUpDB.announceWipe or GzLevelUpDB.announceRez
            or GzLevelUpDB.announceSelfRez) then
        return
    end
    if not unit or not UnitExists(unit) then return end
    -- No name yet means no usable state either: neither a baseline worth
    -- keeping nor a death worth announcing.
    if not UnitReady(unit) then return end

    local kind = UnitCategory(unit)
    if kind ~= "member" and kind ~= "self" then return end

    local guid = UnitGUID(unit)
    if not guid then return end

    local dead, was = IsDead(unit), knownDead[guid]
    knownDead[guid] = dead
    -- `was` is nil for a unit we have never seen either way (joined mid-fight),
    -- and neither direction may be answered from a guess.
    if was == nil or dead == was then return end

    if dead then
        -- A fresh corpse of mine invalidates whatever was offered on the old one.
        if kind == "self" then rezOffer.name = nil end
        QueueDeath(kind, UnitName(unit), UnitLevel(unit))
    elseif GzLevelUpDB.announceRez or GzLevelUpDB.announceSelfRez then
        -- Unlike a death, a resurrect nobody wants announced is not collected
        -- either: there is no threshold left for it to count towards.
        if kind == "self" then
            -- My own comeback is only worth a message when somebody actually
            -- got me up. Walking back from the graveyard leaves nobody to thank.
            local who = ClaimRezOffer()
            if who then QueueRez(kind, who, UnitLevel(unit)) end
        else
            QueueRez(kind, UnitName(unit), UnitLevel(unit))
        end
    end
end

-- ---------------------------------------------------------------------------
-- Auto reply: after my own level-up, thank whoever congratulates me
-- ---------------------------------------------------------------------------

-- State of the current listening window. `session` invalidates timers from an
-- earlier window, since C_Timer.After cannot be cancelled.
local reply = { session = 0, listening = false, pending = false, names = {}, seen = {} }

-- Chat events we listen to, mapped to the channel a reply would go to.
local REPLY_EVENTS = {
    CHAT_MSG_PARTY        = "PARTY",
    CHAT_MSG_PARTY_LEADER = "PARTY",
    CHAT_MSG_RAID         = "RAID",
    CHAT_MSG_RAID_LEADER  = "RAID",
}

-- Splits the configured trigger list into lowercase words.
local function TriggerWords()
    local words = {}
    for raw in (GzLevelUpDB.replyTriggers or ""):gmatch("[^,]+") do
        local word = raw:match("^%s*(.-)%s*$"):lower()
        if word ~= "" then words[#words + 1] = word end
    end
    return words
end

-- True if any word in the message starts with one of the triggers, so "gzzz"
-- and "gz!" count but "Bugzapper" does not.
local function IsCongratulation(text)
    if not text or text == "" then return false end
    -- Punctuation becomes whitespace so that word starts are easy to find.
    local padded = " " .. text:lower():gsub("[%p%s]+", " ") .. " "
    for _, word in ipairs(TriggerWords()) do
        if padded:find(" " .. word, 1, true) then return true end
    end
    return false
end

local function FormatReply(template, names)
    return Format(template, names[1], nil, nil, names)
end

local function SendReply(session)
    if reply.session ~= session then return end
    reply.listening, reply.pending = false, false
    if #reply.names == 0 then return end
    if not GzLevelUpDB.enabled or not GzLevelUpDB.autoReplyEnabled then return end
    -- Re-check the channel: the group may have changed while we collected.
    local channel = GroupChannel()
    if not channel then return end
    SendChatMessage(FormatReply(GzLevelUpDB.replyMessage, reply.names), channel)
end

-- Opens the listening window after my own level-up. Deliberately independent
-- of includeSelf: you may want to thank people without announcing yourself.
local function StartReplyWindow()
    if not GzLevelUpDB.enabled or not GzLevelUpDB.autoReplyEnabled then return end
    if not GroupChannel() then return end

    reply.session   = reply.session + 1
    reply.listening = true
    reply.pending   = false
    reply.names, reply.seen = {}, {}

    -- Give up if nobody says anything within the listening window.
    local session = reply.session
    C_Timer.After(ClampDelay(GzLevelUpDB.replyWindow), function()
        if reply.session == session and not reply.pending then
            reply.listening = false
        end
    end)
end

local function OnGroupChat(event, text, sender)
    if not reply.listening then return end
    -- Only react in the channel the addon is allowed to use.
    if REPLY_EVENTS[event] ~= GroupChannel() then return end

    local who = ShortName(sender)
    if not who or who == ShortName(UnitName("player")) then return end
    if not IsCongratulation(text) then return end

    if not reply.seen[who] then
        reply.seen[who] = true
        reply.names[#reply.names + 1] = who
    end

    -- The first congratulation starts the collection timer; later ones simply
    -- join the same reply.
    if not reply.pending then
        reply.pending = true
        local session = reply.session
        C_Timer.After(ClampDelay(GzLevelUpDB.replyCollect), function() SendReply(session) end)
    end
end

local function OnUnitLevel(unit)
    if not UnitCategory(unit) then return end
    local guid = UnitGUID(unit)
    if not guid then return end
    local newLevel = UnitLevel(unit)
    if not newLevel or newLevel <= 0 then return end

    local old = knownLevels[guid]
    knownLevels[guid] = newLevel
    if not old or newLevel <= old then return end

    if unit == "player" then StartReplyWindow() end

    local kind = ClassifyUnit(unit)
    if kind then Announce(unit, kind) end
end

-- ---------------------------------------------------------------------------
-- Floating quick-buttons panel (gz / ty)
-- ---------------------------------------------------------------------------
local quickPanel

-- Manual send via button: uses the same channel logic as auto mode.
local function ManualSend(text)
    if not text or text == "" then return end
    local channel = GroupChannel()
    if channel then
        SendChatMessage(text, channel)
    else
        print(PREFIX .. L.NOT_IN_GROUP)
    end
end

local function RefreshQuickButtons()
    if not quickPanel then return end
    quickPanel.gzBtn:SetText(GzLevelUpDB.gzButtonMessage)
    quickPanel.tyBtn:SetText(GzLevelUpDB.tyButtonMessage)
end

local function CreateQuickPanel()
    if quickPanel then return quickPanel end

    local p = CreateFrame("Frame", "GzLevelUpQuickPanel", UIParent, "BackdropTemplate")
    p:SetSize(148, 54)
    p:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    p:SetFrameStrata("MEDIUM")
    p:SetClampedToScreen(true)
    p:SetMovable(true)
    p:EnableMouse(true)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePos(self, "quickPanelPos")
    end)
    p:Hide()

    -- Title bar acts as the drag handle.
    local handle = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    handle:SetPoint("TOP", 0, -8)
    handle:SetText("GzLevelUp")

    local gzBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    gzBtn:SetSize(62, 24)
    gzBtn:SetPoint("BOTTOMLEFT", 8, 8)
    gzBtn:SetScript("OnClick", function() ManualSend(GzLevelUpDB.gzButtonMessage) end)

    local tyBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    tyBtn:SetSize(62, 24)
    tyBtn:SetPoint("BOTTOMRIGHT", -8, 8)
    tyBtn:SetScript("OnClick", function() ManualSend(GzLevelUpDB.tyButtonMessage) end)

    p.gzBtn = gzBtn
    p.tyBtn = tyBtn

    quickPanel = p
    p:SetScale(ClampScale(GzLevelUpDB.quickPanelScale))
    RestorePos(p, "quickPanelPos")
    RefreshQuickButtons()
    return p
end

local function UpdateQuickPanel()
    local p = CreateQuickPanel()
    RefreshQuickButtons()
    if GzLevelUpDB.quickPanelEnabled then p:Show() else p:Hide() end
end

-- ---------------------------------------------------------------------------
-- Minimap button (opt-in)
-- ---------------------------------------------------------------------------
local minimapButton
local ToggleConfig -- defined further down, once the config window exists

-- Distance from the minimap's centre; 80 puts the button just outside the ring.
local MINIMAP_RADIUS = 80

local function PlaceMinimapButton()
    if not minimapButton then return end
    local angle = tonumber(GzLevelUpDB.minimapAngle) or 210
    local rad = math.rad(angle)
    minimapButton:SetPoint("CENTER", Minimap, "CENTER",
        MINIMAP_RADIUS * math.cos(rad), MINIMAP_RADIUS * math.sin(rad))
end

-- While dragging, convert the cursor position into an angle around the minimap.
local function DragMinimapButton(self)
    local cx, cy = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local px, py = GetCursorPosition()
    px, py = px / scale, py / scale
    GzLevelUpDB.minimapAngle = math.deg(math.atan2(py - cy, px - cx))
    self:ClearAllPoints()
    PlaceMinimapButton()
end

local function CreateMinimapButton()
    if minimapButton then return minimapButton end

    local b = CreateFrame("Button", "GzLevelUpMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetMovable(true)

    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\icon")
    icon:SetSize(20, 20)
    -- Horizontally centred; the ring in MiniMap-TrackingBorder sits one pixel
    -- low, so the icon is nudged up to match (same offset LibDBIcon uses).
    icon:SetPoint("CENTER", 0, 1)
    -- Trim the logo's rounded corners so it sits better inside the round ring.
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", DragMinimapButton)
    end)
    b:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            GzLevelUpDB.quickPanelEnabled = not GzLevelUpDB.quickPanelEnabled
            UpdateQuickPanel()
        else
            ToggleConfig()
        end
    end)

    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(ADDON)
        GameTooltip:AddLine(L.MINIMAP_LEFT, 1, 1, 1)
        GameTooltip:AddLine(L.MINIMAP_RIGHT, 1, 1, 1)
        GameTooltip:AddLine(L.MINIMAP_DRAG, 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    minimapButton = b
    PlaceMinimapButton()
    return b
end

local function UpdateMinimapButton()
    local b = CreateMinimapButton()
    if GzLevelUpDB.minimapEnabled then b:Show() else b:Hide() end
end

-- ---------------------------------------------------------------------------
-- Settings profiles
-- ---------------------------------------------------------------------------
-- GzLevelUpDB stays exactly what it has always been: one flat table holding the
-- settings that are in effect right now. The profile store lives beside it and
-- keeps a named copy of every profile plus which character uses which, so the
-- rest of the addon never has to know that profiles exist at all.
--
-- That also means an older version of the addon still finds everything where it
-- expects it, and it settles who wins after a crash: GzLevelUpDB is written on
-- every change, the copy in the store only at the points below, so the live
-- table is always the newer of the two for the profile named in `active`.
GzLevelUpProfilesDB = GzLevelUpProfilesDB or {}

-- Where a window was dragged to is not a setting. Carrying those along would
-- make the panels jump across the screen on every switch, so they stay put.
local NOT_IN_PROFILE = {
    configPos = true, quickPanelPos = true, minimapAngle = true,
}

local ReloadConfigUI -- set by BuildConfig, once the window exists

local function CopySettings(from, into)
    for k, v in pairs(from) do
        if not NOT_IN_PROFILE[k] then into[k] = v end
    end
    return into
end

-- Replaces the live settings wholesale: keys the incoming profile does not have
-- must disappear rather than linger from the profile before it.
local function LoadSettings(profile)
    for k in pairs(GzLevelUpDB) do
        if not NOT_IN_PROFILE[k] then GzLevelUpDB[k] = nil end
    end
    CopySettings(profile, GzLevelUpDB)
    ApplyDefaults()
end

-- Profiles are bound per character, and two realms can have a "Brend".
local function CharKey()
    local name = UnitName("player") or "?"
    local realm = GetRealmName and GetRealmName() or ""
    if realm == "" then return name end
    return name .. " - " .. realm
end

local function ActiveProfile()
    return GzLevelUpProfilesDB.active
end

local function ProfileNames()
    local names = {}
    for name in pairs(GzLevelUpProfilesDB.profiles or {}) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

-- Writes the live settings back into the profile they belong to.
local function StoreActive()
    local s = GzLevelUpProfilesDB
    if s.active then s.profiles[s.active] = CopySettings(GzLevelUpDB, {}) end
end

local function ApplyProfileEverywhere()
    UpdateQuickPanel()
    if quickPanel then quickPanel:SetScale(ClampScale(GzLevelUpDB.quickPanelScale)) end
    UpdateMinimapButton()
    PlaceMinimapButton()
    if ReloadConfigUI then ReloadConfigUI() end
end

-- Called on every load. For someone who has been using the addon all along
-- this is invisible: their settings simply become their first profile.
local function InitProfiles()
    local s = GzLevelUpProfilesDB
    s.profiles = s.profiles or {}
    s.chars    = s.chars or {}

    if s.active == nil or s.profiles[s.active] == nil then
        s.active = s.active or L.PROFILE_DEFAULT
        s.profiles[s.active] = CopySettings(GzLevelUpDB, {})
    end

    -- Whatever is live belongs to the profile we left off with, whether we got
    -- here through a clean logout or through a crash.
    StoreActive()

    local me = CharKey()
    local want = s.chars[me]
    if want == nil or s.profiles[want] == nil then
        -- A character we have not seen before keeps using what is loaded.
        s.chars[me], want = s.active, s.active
    end

    if want ~= s.active then
        LoadSettings(s.profiles[want])
        s.active = want
    end
end

-- Switching is a user action, so it also binds this character to the profile.
local function SwitchProfile(name)
    local s = GzLevelUpProfilesDB
    if not name or not s.profiles[name] then return false end
    s.chars[CharKey()] = name
    if name ~= s.active then
        StoreActive()
        LoadSettings(s.profiles[name])
        s.active = name
        ApplyProfileEverywhere()
    end
    return true
end

-- A new profile starts as a copy of what is configured right now: you almost
-- always want "like this one, but ...", and a blank slate is one /gz reset away.
local function CreateProfile(name)
    local s = GzLevelUpProfilesDB
    if not name or name == "" or s.profiles[name] then return false end
    StoreActive()
    s.profiles[name] = CopySettings(GzLevelUpDB, {})
    s.chars[CharKey()] = name
    s.active = name
    return true
end

-- The active profile cannot be deleted - there would be nothing left to fall
-- back to for the settings that are currently in effect.
local function DeleteProfile(name)
    local s = GzLevelUpProfilesDB
    if not name or not s.profiles[name] or name == s.active then return false end
    s.profiles[name] = nil
    for char, used in pairs(s.chars) do
        if used == name then s.chars[char] = nil end
    end
    return true
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("UNIT_LEVEL")
f:RegisterEvent("UNIT_PET")
-- Fires when a unit's data finally arrives, i.e. exactly when SyncGroup was
-- too early for it.
f:RegisterEvent("UNIT_NAME_UPDATE")
-- Death and resurrect detection: UNIT_HEALTH covers the group, the PLAYER_*
-- events cover me (they also fire when nobody's health is being tracked, e.g.
-- after a release). RESURRECT_REQUEST tells me who is offering to pick me up.
f:RegisterEvent("UNIT_HEALTH")
f:RegisterEvent("PLAYER_DEAD")
f:RegisterEvent("PLAYER_ALIVE")
f:RegisterEvent("PLAYER_UNGHOST")
f:RegisterEvent("RESURRECT_REQUEST")
-- The last chance to copy the live settings into the active profile.
f:RegisterEvent("PLAYER_LOGOUT")
for event in pairs(REPLY_EVENTS) do f:RegisterEvent(event) end
f:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON then
            ApplyDefaults()
            InitProfiles()
        end
    elseif event == "PLAYER_LOGOUT" then
        StoreActive()
    elseif REPLY_EVENTS[event] then
        OnGroupChat(event, arg1, arg2) -- arg1 = text, arg2 = sender
    elseif event == "UNIT_LEVEL" then
        OnUnitLevel(arg1)
    elseif event == "UNIT_HEALTH" then
        CheckDeathOrRez(arg1)
    elseif event == "RESURRECT_REQUEST" then
        RememberRezOffer(arg1) -- arg1 = who is casting it
    elseif event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        -- All three run through the same edge detector, so a death that both
        -- UNIT_HEALTH and PLAYER_DEAD report is still announced only once.
        CheckDeathOrRez("player")
    elseif event == "UNIT_NAME_UPDATE" then
        SyncLateUnit(arg1)
    elseif event == "UNIT_PET" then
        -- A pet was summoned or swapped: record its level right away, so the
        -- next level-up has something to compare against.
        RecordLevel(PetOf(arg1))
    else -- PLAYER_ENTERING_WORLD, GROUP_ROSTER_UPDATE
        SyncGroup()
        if event == "PLAYER_ENTERING_WORLD" then
            UpdateQuickPanel()
            UpdateMinimapButton()
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Configuration window
-- ---------------------------------------------------------------------------
local configFrame

local WHITE = "Interface\\Buttons\\WHITE8X8"

-- Small helper: labeled checkbox. The label is exposed as cb.label so callers
-- can anchor to it and grey it out.
local function CreateCheck(parent, label)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    fs:SetText(label)
    cb.label = fs
    return cb
end

-- One announcement category as a three-line block:
--   [x] <label>                              [ delay ]
--   [ message template                                ]
--   Preview: "..."
-- Height is BLOCK_HEIGHT, so blocks can simply be stacked.
local BLOCK_HEIGHT = 81

local function CreateCategoryBlock(parent, y, labelText)
    local cb = CreateCheck(parent, labelText)
    cb:SetPoint("TOPLEFT", 26, y)

    local delay = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    delay:SetSize(38, 22)
    delay:SetPoint("TOPRIGHT", -48, y - 3)
    delay:SetAutoFocus(false)
    delay:SetNumeric(true)
    delay:SetMaxLetters(2)
    delay:SetJustifyH("CENTER")

    -- Anchored on both sides instead of a fixed width, so the whole tab
    -- follows the window width.
    local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    edit:SetHeight(26)
    edit:SetPoint("TOPLEFT", 36, y - 28)
    edit:SetPoint("TOPRIGHT", -32, y - 28)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(240)

    local preview = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    preview:SetPoint("TOPLEFT", 38, y - 59)
    preview:SetPoint("TOPRIGHT", -34, y - 59)
    preview:SetJustifyH("LEFT")

    return { cb = cb, delay = delay, edit = edit, preview = preview }
end

-- Reads a field from the .toc, so version/author/links have a single source.
local function AddonMeta(field)
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local value = get and get(ADDON, field)
    if value == nil or value == "" then return nil end
    return value
end

-- A label with a read-only URL underneath. WoW cannot open a browser, so the
-- field exists purely to be selected and copied: focusing it selects the whole
-- URL, and typing into it is undone.
local function CreateLinkRow(parent, y, labelText, url)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 36, y)
    label:SetText(labelText)

    local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    edit:SetHeight(24)
    edit:SetPoint("TOPLEFT", 36, y - 20)
    edit:SetPoint("TOPRIGHT", -32, y - 20)
    edit:SetAutoFocus(false)
    edit:SetText(url)
    edit:SetCursorPosition(0)

    edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    edit:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(url)
            self:HighlightText()
        end
    end)
    edit:SetScript("OnEnterPressed", edit.ClearFocus)
    edit:SetScript("OnEscapePressed", edit.ClearFocus)

    return edit
end

-- Small helper: "<label>  [ nn ] s" on one line, for the reply timings.
-- unitText overrides the trailing "s" (the wipe threshold counts players).
local function CreateSecondsRow(parent, y, labelText, unitText)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 36, y)
    label:SetText(labelText)

    local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    edit:SetSize(38, 22)
    edit:SetPoint("TOPRIGHT", -48, y + 4)
    edit:SetAutoFocus(false)
    edit:SetNumeric(true)
    edit:SetMaxLetters(2)
    edit:SetJustifyH("CENTER")

    local unit = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    unit:SetPoint("LEFT", edit, "RIGHT", 6, 0)
    unit:SetText(unitText or L.REPLY_SECONDS)

    return { label = label, edit = edit, unit = unit }
end

-- Greys out a block's fields while its category is switched off. The checkbox
-- itself stays usable, otherwise it could never be switched back on.
local function SetBlockEnabled(block, on)
    for _, e in ipairs({ block.edit, block.delay }) do
        e:EnableMouse(on)
        if on then
            e:SetTextColor(1, 1, 1)
        else
            e:ClearFocus()
            e:SetTextColor(0.5, 0.5, 0.5)
        end
    end
    if on then
        block.cb.label:SetTextColor(1, 0.82, 0)
        block.preview:SetTextColor(1, 1, 1)
    else
        block.cb.label:SetTextColor(0.5, 0.5, 0.5)
        block.preview:SetTextColor(0.5, 0.5, 0.5)
    end
end

-- Small helper: a "(?)" hotspot showing a tooltip.
local function CreateHelpIcon(parent, title, body)
    local h = CreateFrame("Frame", nil, parent)
    h:SetSize(20, 18)
    h:EnableMouse(true)
    local fs = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("CENTER")
    fs:SetText("|cff9d9d9d(?)|r")
    h:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title)
        GameTooltip:AddLine(body, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    h:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return h
end

-- Small helper: a flat tab button. The active one is underlined.
local function CreateTab(parent, text)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(22)

    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("CENTER", 0, 1)
    fs:SetText(text)
    b:SetWidth(math.max(50, fs:GetStringWidth() + 14))

    b:SetHighlightTexture(WHITE)
    local hl = b:GetHighlightTexture()
    if hl then hl:SetVertexColor(1, 1, 1, 0.08) end

    local line = b:CreateTexture(nil, "OVERLAY")
    line:SetTexture(WHITE)
    line:SetHeight(2)
    line:SetPoint("BOTTOMLEFT", 6, 0)
    line:SetPoint("BOTTOMRIGHT", -6, 0)
    line:SetVertexColor(1, 0.82, 0)

    b.label, b.line = fs, line
    return b
end

-- Marks a tab as selected (gold + underline) or not (grey).
local function SetTabActive(tab, active)
    if active then
        tab.label:SetTextColor(1, 0.82, 0)
        tab.line:Show()
    else
        tab.label:SetTextColor(0.6, 0.6, 0.6)
        tab.line:Hide()
    end
end

local function BuildConfig()
    if configFrame then return configFrame end

    local frame = CreateFrame("Frame", "GzLevelUpConfigFrame", UIParent, "BackdropTemplate")
    -- Tall enough for the three blocks of the death tab plus its two settings
    -- rows. The width is the minimum: the tab bar below measures itself and
    -- widens the window if the translated labels need more room.
    frame:SetSize(500, 430)
    frame:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true) -- a stored position must stay reachable
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePos(self, "configPos")
    end)
    RestorePos(frame, "configPos")
    frame:Hide()
    tinsert(UISpecialFrames, "GzLevelUpConfigFrame") -- closes with ESC

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("GzLevelUp")

    -- Tab bar ----------------------------------------------------------------
    -- Every tab is as wide as its own label, so the bar grows with the
    -- translation - German needs noticeably more room than English. Rather than
    -- picking a width that happens to fit today, the bar adds itself up and
    -- stretches the window when the labels do not fit. The pages are anchored
    -- to both edges, so their contents follow along for free.
    local TAB_MARGIN, TAB_GAP = 16, 6
    local tabs, barWidth = {}, TAB_MARGIN * 2
    for i, label in ipairs({ L.TAB_MESSAGES, L.TAB_REPLY, L.TAB_DEATH,
                             L.TAB_PANEL, L.TAB_SETTINGS, L.TAB_INFO }) do
        local tab = CreateTab(frame, label)
        if i == 1 then
            tab:SetPoint("TOPLEFT", TAB_MARGIN, -42)
        else
            tab:SetPoint("LEFT", tabs[i - 1], "RIGHT", TAB_GAP, 0)
            barWidth = barWidth + TAB_GAP
        end
        barWidth = barWidth + tab:GetWidth()
        tabs[i] = tab
    end
    if barWidth > frame:GetWidth() then frame:SetWidth(barWidth) end

    local sep = frame:CreateTexture(nil, "ARTWORK")
    sep:SetTexture(WHITE)
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", 20, -64)
    sep:SetPoint("TOPRIGHT", -20, -64)
    sep:SetVertexColor(1, 1, 1, 0.15)

    -- One container per tab; only the active one is shown.
    local function CreatePage()
        local p = CreateFrame("Frame", nil, frame)
        p:SetPoint("TOPLEFT", 0, -78)
        p:SetPoint("BOTTOMRIGHT", 0, 20)
        return p
    end
    local msgPage, replyPage, deathPage, panelPage, settingsPage, infoPage =
        CreatePage(), CreatePage(), CreatePage(), CreatePage(), CreatePage(), CreatePage()

    -- === Tab 1: messages ==================================================
    -- Column heading for the delay fields, plus one tooltip covering both the
    -- placeholders and what the delay column means.
    local delayHeader = msgPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    delayHeader:SetPoint("TOPRIGHT", -48, 0)
    delayHeader:SetText(L.DELAY_HEADER)

    local help = CreateHelpIcon(msgPage, L.PLACEHOLDER_TITLE,
        L.PLACEHOLDER_HELP .. "\n\n" .. L.DELAY_HELP)
    help:SetPoint("TOPRIGHT", -24, 2)

    local BLOCK_LABEL = {
        member = L.OPT_GROUP,
        self   = L.OPT_INCLUDE_SELF,
        pet    = L.OPT_INCLUDE_PETS,
    }

    -- One identical block per category, stacked.
    local blocks = {}
    for i, kind in ipairs(CATEGORY_ORDER) do
        local cat   = CATEGORY[kind]
        local block = CreateCategoryBlock(msgPage, -18 - (i - 1) * BLOCK_HEIGHT, BLOCK_LABEL[kind])
        block.kind = kind
        block.cb:SetScript("OnClick", function(self)
            GzLevelUpDB[cat.enabled] = self:GetChecked() and true or false
            SetBlockEnabled(block, GzLevelUpDB[cat.enabled])
        end)
        blocks[i] = block
    end

    -- === Tab 2: auto reply ================================================
    local replyCB = CreateCheck(replyPage, L.OPT_AUTOREPLY)
    replyCB:SetPoint("TOPLEFT", 26, 0)

    local replyHelp = CreateHelpIcon(replyPage, L.REPLY_HELP_TITLE, L.REPLY_HELP)
    replyHelp:SetPoint("TOPRIGHT", -24, 2)

    local replyMsgLabel = replyPage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    replyMsgLabel:SetPoint("TOPLEFT", 36, -36)
    replyMsgLabel:SetText(L.REPLY_MESSAGE_LABEL)

    local replyEdit = CreateFrame("EditBox", nil, replyPage, "InputBoxTemplate")
    replyEdit:SetHeight(26)
    replyEdit:SetPoint("TOPLEFT", 36, -56)
    replyEdit:SetPoint("TOPRIGHT", -32, -56)
    replyEdit:SetAutoFocus(false)
    replyEdit:SetMaxLetters(240)

    local replyPreview = replyPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    replyPreview:SetPoint("TOPLEFT", 38, -87)
    replyPreview:SetPoint("TOPRIGHT", -34, -87)
    replyPreview:SetJustifyH("LEFT")

    local triggerLabel = replyPage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    triggerLabel:SetPoint("TOPLEFT", 36, -114)
    triggerLabel:SetText(L.REPLY_TRIGGERS_LABEL)

    local triggerEdit = CreateFrame("EditBox", nil, replyPage, "InputBoxTemplate")
    triggerEdit:SetHeight(26)
    triggerEdit:SetPoint("TOPLEFT", 36, -134)
    triggerEdit:SetPoint("TOPRIGHT", -32, -134)
    triggerEdit:SetAutoFocus(false)
    triggerEdit:SetMaxLetters(240)

    local collectRow = CreateSecondsRow(replyPage, -172, L.REPLY_COLLECT_LABEL)
    local windowRow  = CreateSecondsRow(replyPage, -200, L.REPLY_WINDOW_LABEL)

    -- Greys out the whole tab while auto reply is off.
    local function SetReplyEnabled(on)
        for _, e in ipairs({ replyEdit, triggerEdit, collectRow.edit, windowRow.edit }) do
            e:EnableMouse(on)
            if on then
                e:SetTextColor(1, 1, 1)
            else
                e:ClearFocus()
                e:SetTextColor(0.5, 0.5, 0.5)
            end
        end
        local r, g, b = 1, 0.82, 0
        if not on then r, g, b = 0.5, 0.5, 0.5 end
        for _, fs in ipairs({ replyMsgLabel, triggerLabel, collectRow.label, windowRow.label }) do
            fs:SetTextColor(r, g, b)
        end
        if on then
            replyPreview:SetTextColor(1, 1, 1)
        else
            replyPreview:SetTextColor(0.5, 0.5, 0.5)
        end
    end

    replyCB:SetScript("OnClick", function(self)
        GzLevelUpDB.autoReplyEnabled = self:GetChecked() and true or false
        SetReplyEnabled(GzLevelUpDB.autoReplyEnabled)
    end)

    -- === Tab 3: death reply ===============================================
    -- Same three-line blocks as the messages tab, so both read identically.
    -- Five of them would not fit, so the tab is split into two sub-pages -
    -- deaths and resurrections are separate concerns anyway, and each of them
    -- keeps the layout this tab always had. The delay header and the help icon
    -- belong to both, so they stay on the page itself, sharing the header line
    -- with the sub-tab row.
    local deathDelayHeader = deathPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    deathDelayHeader:SetPoint("TOPRIGHT", -48, 0)
    deathDelayHeader:SetText(L.DELAY_HEADER)

    local deathHelp = CreateHelpIcon(deathPage, L.DEATH_HELP_TITLE, L.DEATH_HELP)
    deathHelp:SetPoint("TOPRIGHT", -24, 2)

    -- One container per sub-page, both covering the whole tab: only the
    -- selected one is shown, so both can use the same offsets.
    local function CreateSubPage()
        local p = CreateFrame("Frame", nil, deathPage)
        p:SetAllPoints(deathPage)
        return p
    end
    local deathSub, rezSub = CreateSubPage(), CreateSubPage()

    -- The sub-tab row shares the header line with the delay column on the
    -- right, which is what keeps the window the height it has always been.
    local deathSubTabs = {}
    for i, label in ipairs({ L.SUBTAB_DEATH, L.SUBTAB_REZ }) do
        local t = CreateTab(deathPage, label)
        if i == 1 then
            t:SetPoint("TOPLEFT", 26, 6)
        else
            t:SetPoint("LEFT", deathSubTabs[i - 1], "RIGHT", 6, 0)
        end
        deathSubTabs[i] = t
    end

    local function SelectDeathSub(index)
        for i, t in ipairs(deathSubTabs) do SetTabActive(t, i == index) end
        if index == 1 then deathSub:Show() else deathSub:Hide() end
        if index == 2 then rezSub:Show()   else rezSub:Hide()   end
    end

    for i, t in ipairs(deathSubTabs) do
        t:SetScript("OnClick", function() SelectDeathSub(i) end)
    end
    SelectDeathSub(1)

    -- A thin line between the blocks of a sub-page and its settings rows.
    local function CreateSubSep(page, y)
        local line = page:CreateTexture(nil, "ARTWORK")
        line:SetTexture(WHITE)
        line:SetHeight(1)
        line:SetPoint("TOPLEFT", 36, y)
        line:SetPoint("TOPRIGHT", -32, y)
        line:SetVertexColor(1, 1, 1, 0.15)
        return line
    end

    -- Every block of both sub-pages in one list, since saving, loading and the
    -- live preview do not care which page a block sits on. The two flags only
    -- steer the preview: `meName` is the line that is about me, `oneName` the
    -- one that never lists more than one person - my own resurrect names
    -- whoever got me up, and that is always a single player.
    local deathBlocks = {}
    local function AddBlocks(page, entries)
        for i, entry in ipairs(entries) do
            local block = CreateCategoryBlock(page, -18 - (i - 1) * BLOCK_HEIGHT, entry.label)
            block.cat = entry.cat
            block.meName, block.oneName = entry.meName, entry.oneName
            deathBlocks[#deathBlocks + 1] = block
        end
    end

    AddBlocks(deathSub, {
        { cat = DEATH.member, label = L.OPT_DEATH_GROUP },
        { cat = DEATH.self,   label = L.OPT_DEATH_SELF, meName = true },
        { cat = DEATH.wipe,   label = L.OPT_DEATH_WIPE  },
    })
    AddBlocks(rezSub, {
        { cat = REZ.member,   label = L.OPT_REZ_GROUP },
        { cat = REZ.self,     label = L.OPT_REZ_SELF, oneName = true },
    })

    CreateSubSep(deathSub, -262)
    local collectDeathRow = CreateSecondsRow(deathSub, -276, L.DEATH_COLLECT_LABEL)
    local wipeLimitRow    = CreateSecondsRow(deathSub, -304, L.DEATH_WIPE_LABEL, L.DEATH_WIPE_UNIT)

    CreateSubSep(rezSub, -186)
    local collectRezRow = CreateSecondsRow(rezSub, -200, L.REZ_COLLECT_LABEL)

    -- Greys a settings row out while its whole group is switched off.
    local function SetRowEnabled(row, on)
        row.edit:EnableMouse(on)
        if on then
            row.edit:SetTextColor(1, 1, 1)
            row.label:SetTextColor(1, 0.82, 0)
        else
            row.edit:ClearFocus()
            row.edit:SetTextColor(0.5, 0.5, 0.5)
            row.label:SetTextColor(0.5, 0.5, 0.5)
        end
    end

    -- True while at least one category out of the given table is announced.
    local function AnyEnabled(group, order)
        for _, kind in ipairs(order) do
            if GzLevelUpDB[group[kind].enabled] then return true end
        end
        return false
    end

    -- The rows below each group belong to all of its categories, so they are
    -- only greyed out once nothing in that group is announced at all.
    local function SetDeathTimingEnabled()
        local deathOn = AnyEnabled(DEATH, DEATH_ORDER)
        SetRowEnabled(collectDeathRow, deathOn)
        SetRowEnabled(wipeLimitRow, deathOn)
        SetRowEnabled(collectRezRow, AnyEnabled(REZ, REZ_ORDER))
    end

    for _, block in ipairs(deathBlocks) do
        local cat = block.cat
        block.cb:SetScript("OnClick", function(self)
            GzLevelUpDB[cat.enabled] = self:GetChecked() and true or false
            SetBlockEnabled(block, GzLevelUpDB[cat.enabled])
            SetDeathTimingEnabled()
        end)
    end

    -- === Tab 4: quick panel ===============================================
    local quickCB = CreateCheck(panelPage, L.OPT_QUICKPANEL)
    quickCB:SetPoint("TOPLEFT", 26, 0)
    quickCB:SetScript("OnClick", function(self)
        GzLevelUpDB.quickPanelEnabled = self:GetChecked() and true or false
        UpdateQuickPanel()
    end)

    local gzLabel = panelPage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    gzLabel:SetPoint("TOPLEFT", 36, -42)
    gzLabel:SetText(L.QUICK_GZ_LABEL)

    local gzEdit = CreateFrame("EditBox", nil, panelPage, "InputBoxTemplate")
    gzEdit:SetSize(80, 22)
    gzEdit:SetPoint("TOPLEFT", 42, -62)
    gzEdit:SetAutoFocus(false)
    gzEdit:SetMaxLetters(40)

    local tyLabel = panelPage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tyLabel:SetPoint("TOPLEFT", panelPage, "TOP", 12, -42)
    tyLabel:SetText(L.QUICK_TY_LABEL)

    local tyEdit = CreateFrame("EditBox", nil, panelPage, "InputBoxTemplate")
    tyEdit:SetSize(80, 22)
    tyEdit:SetPoint("TOPLEFT", panelPage, "TOP", 18, -62)
    tyEdit:SetAutoFocus(false)
    tyEdit:SetMaxLetters(40)

    -- Live-update the button labels in the panel.
    gzEdit:SetScript("OnTextChanged", function(self)
        if quickPanel then quickPanel.gzBtn:SetText(self:GetText()) end
    end)
    tyEdit:SetScript("OnTextChanged", function(self)
        if quickPanel then quickPanel.tyBtn:SetText(self:GetText()) end
    end)

    local scaleSlider = CreateFrame("Slider", "GzLevelUpScaleSlider", panelPage, "OptionsSliderTemplate")
    scaleSlider:SetPoint("TOPLEFT", 40, -130)
    scaleSlider:SetPoint("TOPRIGHT", -40, -130)
    scaleSlider:SetMinMaxValues(MIN_SCALE, MAX_SCALE)
    scaleSlider:SetValueStep(0.05)
    scaleSlider:SetObeyStepOnDrag(true)

    local scaleLow  = _G["GzLevelUpScaleSliderLow"]  or scaleSlider.Low
    local scaleHigh = _G["GzLevelUpScaleSliderHigh"] or scaleSlider.High
    local scaleText = _G["GzLevelUpScaleSliderText"] or scaleSlider.Text
    if scaleLow  then scaleLow:SetText("50%") end
    if scaleHigh then scaleHigh:SetText("200%") end

    scaleSlider:SetScript("OnValueChanged", function(self, value)
        value = ClampScale(value)
        GzLevelUpDB.quickPanelScale = value
        if quickPanel then quickPanel:SetScale(value) end
        if scaleText then
            scaleText:SetText(L.SCALE_LABEL .. ": " .. math.floor(value * 100 + 0.5) .. "%")
        end
    end)

    -- Greys out the panel details while the panel itself is off.
    local function SetQuickEnabled(on)
        local r, g, b = 1, 0.82, 0
        if not on then r, g, b = 0.5, 0.5, 0.5 end
        gzLabel:SetTextColor(r, g, b)
        tyLabel:SetTextColor(r, g, b)
        for _, e in ipairs({ gzEdit, tyEdit }) do
            e:EnableMouse(on)
            if on then
                e:SetTextColor(1, 1, 1)
            else
                e:ClearFocus()
                e:SetTextColor(0.5, 0.5, 0.5)
            end
        end
        if on then scaleSlider:Enable() else scaleSlider:Disable() end
        if scaleText then scaleText:SetTextColor(r, g, b) end
    end

    quickCB:HookScript("OnClick", function()
        SetQuickEnabled(GzLevelUpDB.quickPanelEnabled)
    end)

    -- === Tab 5: settings ==================================================
    local enabledCB = CreateCheck(settingsPage, L.OPT_ENABLED)
    enabledCB:SetPoint("TOPLEFT", 26, 0)
    enabledCB:SetScript("OnClick", function(self)
        GzLevelUpDB.enabled = self:GetChecked() and true or false
    end)

    -- Raids are opt-in for everything the addon sends.
    local raidCB = CreateCheck(settingsPage, L.OPT_USE_RAID)
    raidCB:SetPoint("TOPLEFT", 26, -30)
    raidCB:SetScript("OnClick", function(self)
        GzLevelUpDB.useRaidChat = self:GetChecked() and true or false
    end)

    local minimapCB = CreateCheck(settingsPage, L.OPT_MINIMAP)
    minimapCB:SetPoint("TOPLEFT", 26, -60)
    minimapCB:SetScript("OnClick", function(self)
        GzLevelUpDB.minimapEnabled = self:GetChecked() and true or false
        UpdateMinimapButton()
    end)

    -- The reset button lives here too; it is wired up further down, once the
    -- confirmation popup and LoadValues() exist.
    local resetBtn = CreateFrame("Button", nil, settingsPage, "UIPanelButtonTemplate")
    resetBtn:SetSize(160, 24)
    resetBtn:SetPoint("TOPLEFT", 30, -104)
    resetBtn:SetText(L.BTN_RESET)

    -- === Tab 6: info ======================================================
    -- Everything here comes from the .toc, so a release only has to stamp the
    -- version in one place.
    local infoName = infoPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    infoName:SetPoint("TOP", 0, -4)
    infoName:SetText(ADDON)

    local infoVersion = infoPage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    infoVersion:SetPoint("TOP", 0, -30)
    infoVersion:SetText(L.INFO_VERSION:format(AddonMeta("Version") or L.INFO_UNKNOWN))

    local infoAuthor = infoPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    infoAuthor:SetPoint("TOP", 0, -50)
    infoAuthor:SetText(L.INFO_AUTHOR:format(AddonMeta("Author") or L.INFO_UNKNOWN))

    -- Whoever the .toc credits, right below the author and in the same font.
    -- Leave X-Credits empty and the line is not created at all - the rows below
    -- keep their place either way, so the tab does not jump around.
    local credits = AddonMeta("X-Credits")
    if credits and credits ~= "" then
        local thanks = infoPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        thanks:SetPoint("TOP", 0, -68)
        thanks:SetText(L.INFO_THANKS:format(credits))
    end

    CreateLinkRow(infoPage, -96, L.INFO_CURSEFORGE,
        AddonMeta("X-CurseForge") or "")
    CreateLinkRow(infoPage, -146, L.INFO_GITHUB,
        AddonMeta("X-Website") or "")

    local copyHint = infoPage:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    copyHint:SetPoint("TOPLEFT", 38, -194)
    copyHint:SetText(L.INFO_COPY_HINT)

    -- === Tab switching =====================================================
    -- Same order as the tab bar above.
    local pages = {
        { tabs[1], msgPage },
        { tabs[2], replyPage },
        { tabs[3], deathPage },
        { tabs[4], panelPage },
        { tabs[5], settingsPage },
        { tabs[6], infoPage },
    }

    local function SelectTab(index)
        for i, entry in ipairs(pages) do
            SetTabActive(entry[1], i == index)
            if i == index then entry[2]:Show() else entry[2]:Hide() end
        end
    end

    for i, entry in ipairs(pages) do
        entry[1]:SetScript("OnClick", function() SelectTab(i) end)
    end

    -- === Live preview ======================================================
    local function UpdatePreview()
        local me    = UnitName("player") or L.PLAYER
        local level = (UnitLevel("player") or 1) + 1
        for _, block in ipairs(blocks) do
            -- The pet preview uses a stand-in pet name and the player as owner.
            local name, owner = me, nil
            if block.kind == "pet" then
                name, owner = UnitName("pet") or L.PET, me
            end
            block.preview:SetText(L.PREVIEW_LABEL .. " \""
                .. Format(block.edit:GetText(), name, level, owner) .. "\"")
        end
        -- Reply preview: pretend two people congratulated us.
        local sample = { L.PREVIEW_NAME_1, L.PREVIEW_NAME_2 }
        replyPreview:SetText(L.PREVIEW_LABEL .. " \""
            .. FormatReply(replyEdit:GetText(), sample) .. "\"")

        -- Death preview: two names for the group and the wipe line, so {names}
        -- and {count} actually show what they do. My own death is about me, and
        -- my own resurrect about the single person who got me up.
        local lvl = UnitLevel("player") or 1
        for _, block in ipairs(deathBlocks) do
            local names = sample
            if block.meName then
                names = { me }
            elseif block.oneName then
                names = { L.PREVIEW_NAME_1 }
            end
            block.preview:SetText(L.PREVIEW_LABEL .. " \""
                .. Format(block.edit:GetText(), names[1], lvl, nil, names) .. "\"")
        end
    end

    -- === Saving ============================================================
    -- Everything is saved automatically: checkboxes and the slider write
    -- through on change, text fields when they lose focus or the window closes.
    local function Commit()
        for _, block in ipairs(blocks) do
            local cat = CATEGORY[block.kind]
            GzLevelUpDB[cat.message] = block.edit:GetText()
            GzLevelUpDB[cat.delay]   = ClampDelay(block.delay:GetText())
        end
        for _, block in ipairs(deathBlocks) do
            GzLevelUpDB[block.cat.message] = block.edit:GetText()
            GzLevelUpDB[block.cat.delay]   = ClampDelay(block.delay:GetText())
        end
        GzLevelUpDB.deathCollect    = ClampDelay(collectDeathRow.edit:GetText())
        GzLevelUpDB.deathWipeLimit  = ClampCount(wipeLimitRow.edit:GetText())
        GzLevelUpDB.rezCollect      = ClampDelay(collectRezRow.edit:GetText())
        GzLevelUpDB.replyMessage    = replyEdit:GetText()
        GzLevelUpDB.replyTriggers   = triggerEdit:GetText()
        GzLevelUpDB.replyCollect    = ClampDelay(collectRow.edit:GetText())
        GzLevelUpDB.replyWindow     = ClampDelay(windowRow.edit:GetText())
        GzLevelUpDB.gzButtonMessage = gzEdit:GetText()
        GzLevelUpDB.tyButtonMessage = tyEdit:GetText()
        RefreshQuickButtons()
    end

    local function WireBlock(block, cat)
        block.edit:SetScript("OnTextChanged", UpdatePreview)
        block.edit:SetScript("OnEditFocusLost", Commit)
        block.edit:SetScript("OnEnterPressed", block.edit.ClearFocus)
        block.edit:SetScript("OnEscapePressed", block.edit.ClearFocus)

        -- Delay fields additionally normalise their text to the clamped value.
        block.delay:SetScript("OnEditFocusLost", function(self)
            Commit()
            self:SetText(tostring(GzLevelUpDB[cat.delay]))
            self:SetCursorPosition(0)
        end)
        block.delay:SetScript("OnEnterPressed", block.delay.ClearFocus)
        block.delay:SetScript("OnEscapePressed", block.delay.ClearFocus)
    end

    for _, block in ipairs(blocks)      do WireBlock(block, CATEGORY[block.kind]) end
    for _, block in ipairs(deathBlocks) do WireBlock(block, block.cat)            end

    replyEdit:SetScript("OnTextChanged", UpdatePreview)

    for _, e in ipairs({ gzEdit, tyEdit, replyEdit, triggerEdit }) do
        e:SetScript("OnEditFocusLost", Commit)
        e:SetScript("OnEnterPressed", e.ClearFocus)
        e:SetScript("OnEscapePressed", e.ClearFocus)
    end

    -- The numeric rows normalise their text to whatever Commit() stored, so
    -- an out-of-range entry snaps back to the clamped value.
    for _, row in ipairs({
        { collectRow,      "replyCollect" },
        { windowRow,       "replyWindow" },
        { collectDeathRow, "deathCollect" },
        { wipeLimitRow,    "deathWipeLimit" },
        { collectRezRow,   "rezCollect" },
    }) do
        local edit, key = row[1].edit, row[2]
        edit:SetScript("OnEditFocusLost", function(self)
            Commit()
            self:SetText(tostring(GzLevelUpDB[key]))
            self:SetCursorPosition(0)
        end)
        edit:SetScript("OnEnterPressed", edit.ClearFocus)
        edit:SetScript("OnEscapePressed", edit.ClearFocus)
    end

    -- Load the current values into all widgets.
    local function LoadValues()
        for _, block in ipairs(blocks) do
            local cat = CATEGORY[block.kind]
            local on  = GzLevelUpDB[cat.enabled] and true or false
            block.edit:SetText(GzLevelUpDB[cat.message])
            block.edit:SetCursorPosition(0)
            block.delay:SetText(tostring(ClampDelay(GzLevelUpDB[cat.delay])))
            block.delay:SetCursorPosition(0)
            block.cb:SetChecked(on)
            SetBlockEnabled(block, on)
        end
        for _, block in ipairs(deathBlocks) do
            local on = GzLevelUpDB[block.cat.enabled] and true or false
            block.edit:SetText(GzLevelUpDB[block.cat.message])
            block.edit:SetCursorPosition(0)
            block.delay:SetText(tostring(ClampDelay(GzLevelUpDB[block.cat.delay])))
            block.delay:SetCursorPosition(0)
            block.cb:SetChecked(on)
            SetBlockEnabled(block, on)
        end
        collectDeathRow.edit:SetText(tostring(ClampDelay(GzLevelUpDB.deathCollect)))
        collectDeathRow.edit:SetCursorPosition(0)
        wipeLimitRow.edit:SetText(tostring(ClampCount(GzLevelUpDB.deathWipeLimit)))
        wipeLimitRow.edit:SetCursorPosition(0)
        collectRezRow.edit:SetText(tostring(ClampDelay(GzLevelUpDB.rezCollect)))
        collectRezRow.edit:SetCursorPosition(0)
        SetDeathTimingEnabled()

        enabledCB:SetChecked(GzLevelUpDB.enabled)
        raidCB:SetChecked(GzLevelUpDB.useRaidChat)
        minimapCB:SetChecked(GzLevelUpDB.minimapEnabled)

        replyCB:SetChecked(GzLevelUpDB.autoReplyEnabled)
        replyEdit:SetText(GzLevelUpDB.replyMessage)
        replyEdit:SetCursorPosition(0)
        triggerEdit:SetText(GzLevelUpDB.replyTriggers)
        triggerEdit:SetCursorPosition(0)
        collectRow.edit:SetText(tostring(ClampDelay(GzLevelUpDB.replyCollect)))
        collectRow.edit:SetCursorPosition(0)
        windowRow.edit:SetText(tostring(ClampDelay(GzLevelUpDB.replyWindow)))
        windowRow.edit:SetCursorPosition(0)
        SetReplyEnabled(GzLevelUpDB.autoReplyEnabled)

        quickCB:SetChecked(GzLevelUpDB.quickPanelEnabled)
        gzEdit:SetText(GzLevelUpDB.gzButtonMessage)
        gzEdit:SetCursorPosition(0)
        tyEdit:SetText(GzLevelUpDB.tyButtonMessage)
        tyEdit:SetCursorPosition(0)
        SetQuickEnabled(GzLevelUpDB.quickPanelEnabled)
        scaleSlider:SetValue(ClampScale(GzLevelUpDB.quickPanelScale))
        UpdatePreview()
    end

    -- === Restore defaults ==================================================
    StaticPopupDialogs["GZLEVELUP_RESET"] = {
        text = L.RESET_CONFIRM,
        button1 = YES,
        button2 = NO,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnAccept = function()
            -- Only the active profile: the others are none of this button's
            -- business, and deleting one is a separate action.
            wipe(GzLevelUpDB) -- also drops both stored window positions
            ApplyDefaults()
            StoreActive()
            UpdateQuickPanel()
            if quickPanel then
                quickPanel:SetScale(ClampScale(GzLevelUpDB.quickPanelScale))
                RestorePos(quickPanel, "quickPanelPos")
            end
            RestorePos(frame, "configPos")
            UpdateMinimapButton()
            PlaceMinimapButton()
            LoadValues()
            print(PREFIX .. L.MSG_RESET)
        end,
    }

    resetBtn:SetScript("OnClick", function() StaticPopup_Show("GZLEVELUP_RESET") end)

    frame:SetScript("OnShow", LoadValues)
    frame:SetScript("OnHide", Commit) -- catches a field that still had focus

    SelectTab(1)
    configFrame = frame
    return frame
end

-- Assigned to the forward declaration near the minimap button.
function ToggleConfig()
    local frame = BuildConfig()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

-- ---------------------------------------------------------------------------
-- Slash commands: /gz
-- ---------------------------------------------------------------------------
local function StateText(v)
    return v and L.STATE_ON or L.STATE_OFF
end

SLASH_GZLEVELUP1 = "/gz"
SlashCmdList.GZLEVELUP = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = msg:match("^(%S*)%s*(.*)$")
    cmd = cmd:lower()

    if cmd == "" or cmd == "config" or cmd == "menu" or cmd == "options" then
        ToggleConfig()
    elseif cmd == "on" then
        GzLevelUpDB.enabled = true
        print(PREFIX .. L.ENABLED_ON)
    elseif cmd == "off" then
        GzLevelUpDB.enabled = false
        print(PREFIX .. L.ENABLED_OFF)
    elseif cmd == "reply" then
        GzLevelUpDB.autoReplyEnabled = not GzLevelUpDB.autoReplyEnabled
        print(PREFIX .. L.AUTOREPLY_SET:format(tostring(GzLevelUpDB.autoReplyEnabled)))
    elseif cmd == "raid" then
        GzLevelUpDB.useRaidChat = not GzLevelUpDB.useRaidChat
        print(PREFIX .. L.USE_RAID_SET:format(tostring(GzLevelUpDB.useRaidChat)))
    elseif cmd == "group" then
        GzLevelUpDB.announceGroup = not GzLevelUpDB.announceGroup
        print(PREFIX .. L.ANNOUNCE_GROUP_SET:format(tostring(GzLevelUpDB.announceGroup)))
    elseif cmd == "self" then
        GzLevelUpDB.includeSelf = not GzLevelUpDB.includeSelf
        print(PREFIX .. L.INCLUDE_SELF_SET:format(tostring(GzLevelUpDB.includeSelf)))
    elseif cmd == "msg" then
        if rest ~= "" then
            GzLevelUpDB.message = rest
            print(PREFIX .. L.MESSAGE_SET:format(rest))
        else
            print(PREFIX .. L.MESSAGE_CURRENT:format(GzLevelUpDB.message))
        end
    elseif cmd == "selfmsg" then
        if rest ~= "" then
            GzLevelUpDB.selfMessage = rest
            print(PREFIX .. L.SELF_MESSAGE_SET:format(rest))
        else
            print(PREFIX .. L.SELF_MESSAGE_CURRENT:format(GzLevelUpDB.selfMessage))
        end
    elseif cmd == "pets" then
        GzLevelUpDB.includePets = not GzLevelUpDB.includePets
        print(PREFIX .. L.INCLUDE_PETS_SET:format(tostring(GzLevelUpDB.includePets)))
    elseif cmd == "petmsg" then
        if rest ~= "" then
            GzLevelUpDB.petMessage = rest
            print(PREFIX .. L.PET_MESSAGE_SET:format(rest))
        else
            print(PREFIX .. L.PET_MESSAGE_CURRENT:format(GzLevelUpDB.petMessage))
        end
    elseif cmd == "death" then
        GzLevelUpDB.announceDeaths = not GzLevelUpDB.announceDeaths
        print(PREFIX .. L.DEATH_SET:format(tostring(GzLevelUpDB.announceDeaths)))
    elseif cmd == "selfdeath" then
        GzLevelUpDB.announceSelfDeath = not GzLevelUpDB.announceSelfDeath
        print(PREFIX .. L.SELF_DEATH_SET:format(tostring(GzLevelUpDB.announceSelfDeath)))
    elseif cmd == "wipe" then
        GzLevelUpDB.announceWipe = not GzLevelUpDB.announceWipe
        print(PREFIX .. L.WIPE_SET:format(tostring(GzLevelUpDB.announceWipe)))
    elseif cmd == "rez" then
        GzLevelUpDB.announceRez = not GzLevelUpDB.announceRez
        print(PREFIX .. L.REZ_SET:format(tostring(GzLevelUpDB.announceRez)))
    elseif cmd == "selfrez" then
        GzLevelUpDB.announceSelfRez = not GzLevelUpDB.announceSelfRez
        print(PREFIX .. L.SELF_REZ_SET:format(tostring(GzLevelUpDB.announceSelfRez)))
    elseif cmd == "deathmsg" or cmd == "selfdeathmsg" or cmd == "wipemsg"
        or cmd == "rezmsg" or cmd == "selfrezmsg" then
        local key = (cmd == "deathmsg" and "deathMessage")
                 or (cmd == "selfdeathmsg" and "selfDeathMessage")
                 or (cmd == "rezmsg" and "rezMessage")
                 or (cmd == "selfrezmsg" and "selfRezMessage")
                 or "wipeMessage"
        if rest ~= "" then
            GzLevelUpDB[key] = rest
            print(PREFIX .. L.DEATH_MESSAGE_SET:format(cmd, rest))
        else
            print(PREFIX .. L.DEATH_MESSAGE_CURRENT:format(cmd, GzLevelUpDB[key]))
        end
    elseif cmd == "delay" then
        -- "/gz delay <sec>" sets them all; "/gz delay <category> <sec>" one.
        local who, value = rest:match("^(%S*)%s*(.*)$")
        local single = DELAY_ALIAS[who:lower()]
        if rest == "" then
            print(PREFIX .. L.DELAY_CURRENT:format(
                tostring(ClampDelay(GzLevelUpDB.groupDelay)),
                tostring(ClampDelay(GzLevelUpDB.selfDelay)),
                tostring(ClampDelay(GzLevelUpDB.petDelay)),
                tostring(ClampDelay(GzLevelUpDB.deathDelay)),
                tostring(ClampDelay(GzLevelUpDB.selfDeathDelay)),
                tostring(ClampDelay(GzLevelUpDB.wipeDelay)),
                tostring(ClampDelay(GzLevelUpDB.rezDelay)),
                tostring(ClampDelay(GzLevelUpDB.selfRezDelay))))
        elseif single then
            local n = (value:lower() == "off") and 0 or ClampDelay(value)
            GzLevelUpDB[single.delay] = n
            print(PREFIX .. L.DELAY_SET_ONE:format(who:lower(), tostring(n)))
        else
            local n = (rest:lower() == "off") and 0 or ClampDelay(rest)
            for _, cat in ipairs(ALL_CATEGORIES) do
                GzLevelUpDB[cat.delay] = n
            end
            print(PREFIX .. L.DELAY_SET:format(tostring(n)))
        end
    elseif cmd == "profile" then
        -- "new" and "delete" are the only reserved words here; anything else is
        -- taken as a profile name, spaces and all.
        local verb, name = rest:match("^(%S*)%s*(.*)$")
        if verb:lower() == "new" or verb:lower() == "delete" then
            verb = verb:lower()
        else
            verb, name = "use", rest
        end

        if verb == "new" then
            if name == "" then
                print(PREFIX .. L.PROFILE_NEEDS_NAME)
            elseif CreateProfile(name) then
                print(PREFIX .. L.PROFILE_CREATED:format(name))
            else
                print(PREFIX .. L.PROFILE_EXISTS:format(name))
            end
        elseif verb == "delete" then
            if DeleteProfile(name) then
                print(PREFIX .. L.PROFILE_DELETED:format(name))
            elseif name == ActiveProfile() then
                print(PREFIX .. L.PROFILE_KEEP_ACTIVE)
            else
                print(PREFIX .. L.PROFILE_UNKNOWN:format(name))
            end
        elseif name == "" then
            print(PREFIX .. L.PROFILE_LIST)
            for _, entry in ipairs(ProfileNames()) do
                local mark = (entry == ActiveProfile()) and L.PROFILE_ACTIVE_MARK or "   "
                print(mark .. entry)
            end
        elseif SwitchProfile(name) then
            print(PREFIX .. L.PROFILE_SWITCHED:format(name))
        else
            print(PREFIX .. L.PROFILE_UNKNOWN:format(name))
        end
    elseif cmd == "minimap" then
        GzLevelUpDB.minimapEnabled = not GzLevelUpDB.minimapEnabled
        UpdateMinimapButton()
        print(PREFIX .. L.MINIMAP_SET:format(tostring(GzLevelUpDB.minimapEnabled)))
    elseif cmd == "panel" then
        GzLevelUpDB.quickPanelEnabled = not GzLevelUpDB.quickPanelEnabled
        UpdateQuickPanel()
        print(PREFIX .. (GzLevelUpDB.quickPanelEnabled and L.PANEL_SHOWN or L.PANEL_HIDDEN))
    elseif cmd == "scale" then
        local n = tonumber(rest)
        if n then
            if n > 5 then n = n / 100 end -- allow a percentage like 120
            n = ClampScale(n)
            GzLevelUpDB.quickPanelScale = n
            if quickPanel then quickPanel:SetScale(n) end
            print(PREFIX .. L.SCALE_SET:format(math.floor(n * 100 + 0.5)))
        else
            print(PREFIX .. L.SCALE_SET:format(math.floor(ClampScale(GzLevelUpDB.quickPanelScale) * 100 + 0.5)))
        end
    elseif cmd == "test" then
        local me    = UnitName("player")
        local level = (UnitLevel("player") or 1) + 1
        for _, kind in ipairs(CATEGORY_ORDER) do
            local cat = CATEGORY[kind]
            if GzLevelUpDB[cat.enabled] then
                local name, owner = me, nil
                if kind == "pet" then
                    name, owner = UnitName("pet") or L.PET, me
                end
                print(PREFIX .. L.PREVIEW_PREFIX .. Format(GzLevelUpDB[cat.message], name, level, owner))
            end
        end
        -- The death lines use two sample names, so {names}/{count} are visible.
        -- Only my own death is about me; my own resurrect names whoever got me
        -- up, so that one takes a sample name as well.
        local sample = { L.PREVIEW_NAME_1, L.PREVIEW_NAME_2 }
        for _, entry in ipairs({
            { DEATH.member, sample }, { DEATH.self, { me } }, { DEATH.wipe, sample },
            { REZ.member,   sample }, { REZ.self,   { L.PREVIEW_NAME_1 } },
        }) do
            local cat, names = entry[1], entry[2]
            if GzLevelUpDB[cat.enabled] then
                print(PREFIX .. L.PREVIEW_PREFIX
                    .. Format(GzLevelUpDB[cat.message], names[1], UnitLevel("player"), nil, names))
            end
        end
    else
        print(PREFIX .. L.HELP_HEADER)
        print(L.HELP_CONFIG)
        print(L.HELP_ONOFF:format(StateText(GzLevelUpDB.enabled)))
        print(L.HELP_MSG)
        print(L.HELP_SELFMSG)
        print(L.HELP_PETMSG)
        print(L.HELP_DELAY)
        print(L.HELP_DELAY_ONE)
        print(L.HELP_PANEL)
        print(L.HELP_MINIMAP:format(tostring(GzLevelUpDB.minimapEnabled)))
        print(L.HELP_SCALE)
        print(L.HELP_REPLY:format(tostring(GzLevelUpDB.autoReplyEnabled)))
        print(L.HELP_DEATH:format(tostring(GzLevelUpDB.announceDeaths)))
        print(L.HELP_SELFDEATH:format(tostring(GzLevelUpDB.announceSelfDeath)))
        print(L.HELP_WIPE:format(tostring(GzLevelUpDB.announceWipe)))
        print(L.HELP_DEATHMSG)
        print(L.HELP_REZ:format(tostring(GzLevelUpDB.announceRez)))
        print(L.HELP_SELFREZ:format(tostring(GzLevelUpDB.announceSelfRez)))
        print(L.HELP_REZMSG)
        print(L.HELP_RAID:format(tostring(GzLevelUpDB.useRaidChat)))
        print(L.HELP_GROUP:format(tostring(GzLevelUpDB.announceGroup)))
        print(L.HELP_SELF:format(tostring(GzLevelUpDB.includeSelf)))
        print(L.HELP_PETS:format(tostring(GzLevelUpDB.includePets)))
        print(L.HELP_PROFILE:format(tostring(ActiveProfile())))
        print(L.HELP_TEST)
    end
end
