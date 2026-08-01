-- GzLevelUp test suite.
--
--     lua tests/run.lua        (from anywhere; paths are resolved from arg[0])
--
-- Loads the real addon against a stubbed WoW API (tests/harness.lua) and
-- drives it through events, then asserts on what it would have said in chat.
-- Exits non-zero on the first failing run, so CI can gate on it.

local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local harness = dofile(here .. "/harness.lua")
harness.loadAddon(here .. "/..")

local print = testPrint
local fails, total = 0, 0

local function check(label, got, want)
    total = total + 1
    local ok = got == want
    if not ok then fails = fails + 1 end
    print(string.format("%-4s %-46s %s", ok and "ok" or "FAIL", label,
        ok and "" or ("got [" .. tostring(got) .. "] want [" .. tostring(want) .. "]")))
end

local function section(title) print("\n-- " .. title) end
local function lastSent() return sent[#sent] and sent[#sent].msg end
local function reset() sent, timers = {}, {} end

-- Raise a unit's level and deliver the event the game would send.
local function levelUp(unit)
    world[unit].level = world[unit].level + 1
    fire("UNIT_LEVEL", unit)
end

fire("ADDON_LOADED", "GzLevelUp")
fire("GROUP_ROSTER_UPDATE")

section("defaults: group on, self off, pets off")
reset(); levelUp("party1")
check("group member announces", lastSent(), "Gz Alice!")
reset(); levelUp("player")
check("own level-up stays silent", lastSent(), nil)
reset(); levelUp("partypet1")
check("pet stays silent", lastSent(), nil)

section("pets enabled")
GzLevelUpDB.includePets = true
fire("GROUP_ROSTER_UPDATE")
reset(); levelUp("partypet1")
check("pet announces with owner", lastSent(), "Gz Alice's Fluffy!")
reset(); levelUp("pet")
check("own pet silent while self off", lastSent(), nil)

section("self enabled")
GzLevelUpDB.includeSelf = true
reset(); levelUp("player")
check("own level-up announces", lastSent(), "Ding! Level 57")
reset(); levelUp("pet")
check("own pet announces", lastSent(), "Gz Brend's Snuggle!")

section("group switched off independently")
GzLevelUpDB.announceGroup = false
reset(); levelUp("party2")
check("group silent when off", lastSent(), nil)
reset(); levelUp("partypet1")
check("pet still announces", lastSent(), "Gz Alice's Fluffy!")
GzLevelUpDB.announceGroup = true

section("per-category delay")
GzLevelUpDB.petDelay, GzLevelUpDB.groupDelay = 5, 0
reset(); levelUp("party1")
check("group sends immediately", lastSent(), "Gz Alice!")
reset(); levelUp("partypet1")
check("pet is held back", lastSent(), nil)
check("one timer queued", #timers, 1)
check("timer delay is 5s", timers[1].sec, 5)
runTimers()
check("pet arrives after timer", lastSent(), "Gz Alice's Fluffy!")
GzLevelUpDB.petDelay = 0

section("no announce without a real level-up")
reset(); fire("UNIT_LEVEL", "party1")
check("same level is silent", lastSent(), nil)
reset(); fire("UNIT_LEVEL", "target")
check("non-group token ignored", lastSent(), nil)

section("master switch")
GzLevelUpDB.enabled = false
reset(); levelUp("party1")
check("nothing sent while disabled", lastSent(), nil)
GzLevelUpDB.enabled = true

section("slash commands")
local slash = SlashCmdList.GZLEVELUP
slash("delay 7")
check("delay 7 -> group", GzLevelUpDB.groupDelay, 7)
check("delay 7 -> self", GzLevelUpDB.selfDelay, 7)
check("delay 7 -> pets", GzLevelUpDB.petDelay, 7)
slash("delay pets 2")
check("delay pets 2", GzLevelUpDB.petDelay, 2)
check("delay pets left group alone", GzLevelUpDB.groupDelay, 7)
slash("delay self off")
check("delay self off -> 0", GzLevelUpDB.selfDelay, 0)
slash("delay 99")
check("delay clamped to 60", GzLevelUpDB.groupDelay, 60)
slash("delay 0")
slash("group")
check("group toggles off", GzLevelUpDB.announceGroup, false)
slash("group")
check("group toggles back on", GzLevelUpDB.announceGroup, true)
slash("petmsg Grats {owner} - {name} is {level}!")
check("petmsg set", GzLevelUpDB.petMessage, "Grats {owner} - {name} is {level}!")
reset(); levelUp("partypet1")
check("custom pet message used", lastSent(),
      "Grats Alice - Fluffy is " .. world.partypet1.level .. "!")

section("migration from the old global delay")
GzLevelUpDB = { delayEnabled = true, delaySeconds = 4, message = "keep me" }
fire("ADDON_LOADED", "GzLevelUp")
check("old delay -> groupDelay", GzLevelUpDB.groupDelay, 4)
check("old delay -> selfDelay", GzLevelUpDB.selfDelay, 4)
check("old delay -> petDelay", GzLevelUpDB.petDelay, 4)
check("old keys removed (enabled)", GzLevelUpDB.delayEnabled, nil)
check("old keys removed (seconds)", GzLevelUpDB.delaySeconds, nil)
check("existing message preserved", GzLevelUpDB.message, "keep me")
check("new switch defaulted", GzLevelUpDB.announceGroup, true)

GzLevelUpDB = { delayEnabled = false, delaySeconds = 9 }
fire("ADDON_LOADED", "GzLevelUp")
check("disabled old delay -> 0", GzLevelUpDB.groupDelay, 0)

GzLevelUpDB = {}
fire("ADDON_LOADED", "GzLevelUp")
check("fresh install -> delay 0", GzLevelUpDB.groupDelay, 0)
check("fresh install -> group on", GzLevelUpDB.announceGroup, true)
check("fresh install -> pets off", GzLevelUpDB.includePets, false)


section("raid chat is opt-in")
GzLevelUpDB = {}
fire("ADDON_LOADED", "GzLevelUp")
fire("GROUP_ROSTER_UPDATE")
inRaid = true
reset(); levelUp("party1")
check("silent in raid by default", lastSent(), nil)
GzLevelUpDB.useRaidChat = true
reset(); levelUp("party1")
check("announces in raid once allowed", lastSent(), "Gz Alice!")
check("uses RAID channel", sent[#sent].chan, "RAID")
inRaid = false
reset(); levelUp("party1")
check("party still uses PARTY", sent[#sent].chan, "PARTY")

section("auto reply")
GzLevelUpDB = {}
fire("ADDON_LOADED", "GzLevelUp")
fire("GROUP_ROSTER_UPDATE")
GzLevelUpDB.autoReplyEnabled = true

-- levelUp("player") always queues the listening-window timer, so timer counts
-- are compared relative to that baseline.
reset(); levelUp("player")
check("listening window queued", #timers, 1)
check("window timer is 30s", timers[1].sec, 30)
check("no reply before anyone congratulates", lastSent(), nil)
fire("CHAT_MSG_PARTY", "gz!", "Alice")
check("first gz queues the collect timer", #timers, 2)
check("collect timer is 6s", timers[2].sec, 6)
fire("CHAT_MSG_PARTY", "grats dude", "Bob")
check("second gz adds no extra timer", #timers, 2)
runTimers()
check("one reply naming both", lastSent(), "ty Alice, Bob!")
check("exactly one message sent", #sent, 1)
check("reply goes to PARTY", sent[1].chan, "PARTY")

section("auto reply: what does not count")
reset(); levelUp("player")
fire("CHAT_MSG_PARTY", "gz", "Brend")
check("my own message ignored", #timers, 1)
fire("CHAT_MSG_PARTY", "that Bugzapper is nice", "Alice")
check("gz inside a word ignored", #timers, 1)
fire("CHAT_MSG_PARTY", "gzzzz", "Alice")
check("gzzzz counts", #timers, 2)
fire("CHAT_MSG_PARTY", "gz too", "Alice")
runTimers()
check("same person listed once", lastSent(), "ty Alice!")

reset(); levelUp("player")
fire("CHAT_MSG_PARTY", "gz", "Alice-Anotherrealm")
runTimers()
check("realm suffix stripped", lastSent(), "ty Alice!")

section("auto reply: listening window closes")
reset(); levelUp("player")
runTimers() -- nobody said anything, so the window expires
fire("CHAT_MSG_PARTY", "gz", "Alice")
check("late gz queues nothing", #timers, 0)
check("nothing sent", lastSent(), nil)

section("auto reply: channel and switches")
reset(); levelUp("player")
fire("CHAT_MSG_RAID", "gz", "Alice")
check("raid chat ignored while in party", #timers, 1)
runTimers()
check("nothing sent from raid chat", lastSent(), nil)

reset()
GzLevelUpDB.autoReplyEnabled = false
levelUp("player")
check("disabled: no listening window", #timers, 0)
fire("CHAT_MSG_PARTY", "gz", "Alice")
runTimers()
check("disabled: nothing sent", lastSent(), nil)
GzLevelUpDB.autoReplyEnabled = true

section("auto reply: independent of includeSelf")
GzLevelUpDB.includeSelf = false
reset(); levelUp("player")
check("no self announce", lastSent(), nil)
fire("CHAT_MSG_PARTY", "gz", "Alice")
runTimers()
check("but the reply still works", lastSent(), "ty Alice!")

section("auto reply: placeholders and triggers")
GzLevelUpDB.replyMessage = "thx {name} and {count} others"
reset(); levelUp("player")
fire("CHAT_MSG_PARTY", "gz", "Alice")
fire("CHAT_MSG_PARTY", "gz", "Bob")
runTimers()
check("{name} and {count}", lastSent(), "thx Alice and 2 others")

GzLevelUpDB.replyMessage  = "ty {names}!"
GzLevelUpDB.replyTriggers = "  danke ,, WOW  "
reset(); levelUp("player")
fire("CHAT_MSG_PARTY", "gz", "Alice")
check("old trigger no longer counts", #timers, 1)
fire("CHAT_MSG_PARTY", "Wow!", "Bob")
runTimers()
check("custom trigger, case insensitive", lastSent(), "ty Bob!")

section("auto reply in a raid follows the raid switch")
GzLevelUpDB.replyTriggers = "gz"
inRaid = true
reset(); levelUp("player")
check("no window while raid chat is off", #timers, 0)
GzLevelUpDB.useRaidChat = true
reset(); levelUp("player")
fire("CHAT_MSG_RAID", "gz", "Alice")
runTimers()
check("replies in raid once allowed", lastSent(), "ty Alice!")
check("reply goes to RAID", sent[#sent].chan, "RAID")
inRaid = false

section("addon metadata (feeds the info tab)")
local meta = GetAddOnMetadata
check("version present", type(meta("GzLevelUp", "Version")), "string")
check("version looks like a number", (meta("GzLevelUp", "Version") or ""):match("^%d") ~= nil, true)
check("author present", meta("GzLevelUp", "Author"), "BrendTM")
check("curseforge link is a url",
      (meta("GzLevelUp", "X-CurseForge") or ""):match("^https://") ~= nil, true)
check("github link is a url",
      (meta("GzLevelUp", "X-Website") or ""):match("^https://") ~= nil, true)
check("saved variables declared", meta("GzLevelUp", "SavedVariables"), "GzLevelUpDB")

section("addon list icon")
local iconPath = meta("GzLevelUp", "IconTexture")
check("IconTexture declared", iconPath, [[Interface\AddOns\GzLevelUp\icon]])
-- WoW resolves the texture without an extension; the file itself must exist.
local tga = io.open(here .. "/../GzLevelUp/icon.tga", "rb")
check("icon.tga present", tga ~= nil, true)
if tga then
    local head = tga:read(18)
    tga:close()
    local byte = string.byte
    -- 64x64, uncompressed true-color, 32bpp: what the texture loader accepts.
    check("uncompressed true-color", byte(head, 3), 2)
    check("no colour map", byte(head, 2), 0)
    check("width 64", byte(head, 13) + byte(head, 14) * 256, 64)
    check("height 64", byte(head, 15) + byte(head, 16) * 256, 64)
    check("32 bit with alpha", byte(head, 17), 32)
end

print(string.format("\n%d checks, %d failed", total, fails))
os.exit(fails == 0 and 0 or 1)
