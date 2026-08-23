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

-- Kill / resurrect a unit. The game announces both through UNIT_HEALTH.
local function die(unit)
    world[unit].dead = true
    fire("UNIT_HEALTH", unit)
end

local function revive(...)
    for _, unit in ipairs({ ... }) do
        world[unit].dead = false
        fire("UNIT_HEALTH", unit)
    end
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

section("death reply: off by default")
GzLevelUpDB = {}
fire("ADDON_LOADED", "GzLevelUp")
world.player.dead, world.party1.dead, world.party2.dead, world.party3.dead =
    false, false, false, false
fire("GROUP_ROSTER_UPDATE") -- records everyone as alive
check("member deaths off by default", GzLevelUpDB.announceDeaths, false)
check("own death off by default", GzLevelUpDB.announceSelfDeath, false)
check("wipe line off by default", GzLevelUpDB.announceWipe, false)
check("default names one member", GzLevelUpDB.deathMessage, "F {name}")
reset(); die("party1")
check("nothing happens while it is off", #timers, 0)

section("death reply: a single death")
GzLevelUpDB.announceDeaths = true
reset(); fire("UNIT_HEALTH", "party1")
check("death queues the collect timer", #timers, 1)
check("collect timer is 3s", timers[1].sec, 3)
check("nothing sent before it fires", lastSent(), nil)
runTimers()
check("death announced", lastSent(), "F Alice")

section("death reply: deaths are batched into one message")
-- Batching is about *when* one message is sent, not about how many names it
-- carries. With the default "F {name}" a batch renders as the first of them;
-- the rest still count (towards the wipe threshold) but are not named.
revive("party1", "party2")
reset(); die("party1"); die("party2")
check("both deaths share one timer", #timers, 1)
runTimers()
check("the default names only the first", lastSent(), "F Alice")
check("exactly one message sent", #sent, 1)

-- {names} is what turns the batch into a list.
GzLevelUpDB.deathMessage = "F {names}"
revive("party1", "party2")
reset(); die("party1"); die("party2")
runTimers()
check("{names} lists everyone", lastSent(), "F Alice, Bob")
check("still exactly one message", #sent, 1)

section("death reply: a wipe")
revive("party1", "party2", "party3")
reset(); die("party1"); die("party2"); die("party3")
runTimers()
check("silent while the wipe line is off", lastSent(), nil)

GzLevelUpDB.announceWipe = true
revive("party1", "party2", "party3")
reset(); die("party1"); die("party2"); die("party3")
runTimers()
check("wipe line replaces the single deaths", lastSent(), "Wipe.")
check("exactly one message sent", #sent, 1)

GzLevelUpDB.deathWipeLimit = 0
GzLevelUpDB.deathMessage = "F {names}" -- spelled out: all three have to show up
revive("party1", "party2", "party3")
reset(); die("party1"); die("party2"); die("party3")
runTimers()
check("threshold 0 never counts as a wipe", lastSent(), "F Alice, Bob, Carol")
GzLevelUpDB.deathWipeLimit = 3

section("death reply: my own death")
GzLevelUpDB.announceSelfDeath = true
world.player.dead = true
reset(); fire("PLAYER_DEAD")
runTimers()
check("own death announced", lastSent(), "F")

world.player.dead = false
fire("PLAYER_ALIVE")
world.player.dead = true
reset(); fire("PLAYER_DEAD"); fire("UNIT_HEALTH", "player")
runTimers()
check("reported twice, announced once", #sent, 1)
world.player.dead = false
fire("PLAYER_UNGHOST")

-- My own death counts towards the wipe threshold even though it has its own
-- message, so "two of them plus me" is still a wipe.
revive("party1", "party2")
world.player.dead = true
reset(); die("party1"); die("party2"); fire("PLAYER_DEAD")
runTimers()
check("my death counts towards the wipe", lastSent(), "Wipe.")
check("only the wipe line is sent", #sent, 1)
world.player.dead = false
fire("PLAYER_ALIVE")

section("death reply: what is not a death")
revive("party1")
world.party1.dead, world.party1.feign = true, true
reset(); fire("UNIT_HEALTH", "party1")
check("feign death does not count", #timers, 0)
world.party1.feign = false

revive("party1")
reset(); fire("UNIT_HEALTH", "party1")
check("a living unit does not count", #timers, 0)
reset(); die("party1"); fire("UNIT_HEALTH", "party1")
check("staying dead only counts once", #timers, 1)
runTimers() -- close the batch; reset() below would drop its timer

reset(); fire("UNIT_HEALTH", "target")
check("non-group token ignored", #timers, 0)
revive("party1")
reset(); die("partypet1")
check("a dying pet is not announced", #timers, 0)

section("death reply: a corpse that was already there")
GzLevelUpDB = {}
fire("ADDON_LOADED", "GzLevelUp")
world.party1.dead = true -- dead before we ever saw them
fire("GROUP_ROSTER_UPDATE")
GzLevelUpDB.announceDeaths = true
reset(); fire("UNIT_HEALTH", "party1")
check("a corpse we never saw alive stays silent", #timers, 0)

section("death reply: a member whose data is still loading")
-- Someone we have never grouped with: on joining, the roster lists them while
-- their data is still on its way — nameless, and reported as alive.
world.party4 = { name = "Unknown", guid = "G-dave", level = 0, exists = true }
fire("GROUP_ROSTER_UPDATE")
-- Now the data arrives: they have been lying dead the whole time.
world.party4.name, world.party4.level, world.party4.dead = "Dave", 43, true
reset(); fire("UNIT_NAME_UPDATE", "party4"); fire("UNIT_HEALTH", "party4")
check("a corpse that was still loading stays silent", #timers, 0)
revive("party4")
reset(); die("party4"); runTimers()
check("their next death is announced", lastSent(), "F Dave")

-- Health can arrive before the name does, without any UNIT_NAME_UPDATE in
-- between; that must not leave an "alive" baseline behind either.
runTimers() -- close any open batch, so the timer count below is only ours
world.party4 = { name = "Unknown", guid = "G-erin", level = 0, exists = true }
fire("GROUP_ROSTER_UPDATE")
reset(); fire("UNIT_HEALTH", "party4")
world.party4.name, world.party4.level, world.party4.dead = "Erin", 44, true
fire("UNIT_HEALTH", "party4")
check("no baseline while the name is missing", #timers, 0)
world.party4 = nil

section("death reply: delay and raid chat")
revive("party1")
GzLevelUpDB.deathDelay = 5
reset(); die("party1")
runTimers() -- collect window closes and queues the delayed send
check("nothing sent yet", lastSent(), nil)
check("delay timer queued", timers[1] and timers[1].sec, 5)
runTimers()
check("arrives after the delay", lastSent(), "F Alice")
GzLevelUpDB.deathDelay = 0

inRaid = true
revive("party1")
reset(); die("party1")
check("silent in raid by default", #timers, 0)

-- That death is gone for good: it happened while the addon had no channel, so
-- it takes a fresh one to see anything.
GzLevelUpDB.useRaidChat = true
revive("party1")
reset(); die("party1")
runTimers()
check("announces in raid once allowed", lastSent(), "F Alice")
check("uses the RAID channel", sent[#sent].chan, "RAID")
inRaid = false

section("death reply: placeholders and slash commands")
GzLevelUpDB.deathMessage = "{name} died at {level}, {count} down"
revive("party1", "party2")
reset(); die("party1"); die("party2")
runTimers()
check("{name}/{level}/{count}", lastSent(), "Alice died at " .. world.party1.level .. ", 2 down")

slash("death")
check("death toggles off", GzLevelUpDB.announceDeaths, false)
slash("death")
check("death toggles back on", GzLevelUpDB.announceDeaths, true)
slash("selfdeath")
check("selfdeath toggles on", GzLevelUpDB.announceSelfDeath, true)
slash("selfdeath")
check("selfdeath toggles back off", GzLevelUpDB.announceSelfDeath, false)
slash("wipe")
check("wipe toggles on", GzLevelUpDB.announceWipe, true)
slash("wipemsg Wiped with {count}")
check("wipemsg set", GzLevelUpDB.wipeMessage, "Wiped with {count}")
slash("deathmsg F {names}")
check("deathmsg set", GzLevelUpDB.deathMessage, "F {names}")
slash("delay wipe 4")
check("delay wipe 4", GzLevelUpDB.wipeDelay, 4)
check("other delays untouched", GzLevelUpDB.deathDelay, 0)
slash("delay 2")
check("delay all reaches deaths", GzLevelUpDB.deathDelay, 2)
check("delay all reaches own death", GzLevelUpDB.selfDeathDelay, 2)
check("delay all reaches the wipe", GzLevelUpDB.wipeDelay, 2)
check("delay all still reaches level-ups", GzLevelUpDB.groupDelay, 2)

section("rez reply: a member is back on their feet")
GzLevelUpDB = {}
fire("ADDON_LOADED", "GzLevelUp")
check("member rez off by default", GzLevelUpDB.announceRez, false)
check("own rez off by default", GzLevelUpDB.announceSelfRez, false)
check("default rez message", GzLevelUpDB.rezMessage, "wb {name}")
GzLevelUpDB.announceRez = true

-- Both are lying dead and the addon has seen it.
world.party1.dead, world.party2.dead = true, true
fire("GROUP_ROSTER_UPDATE")
reset(); revive("party1")
check("a rez queues the collect timer", #timers, 1)
runTimers()
check("member rez announced", lastSent(), "wb Alice")

-- Two rezzes inside one window share a message, exactly like deaths do.
world.party1.dead, world.party2.dead = true, true
fire("GROUP_ROSTER_UPDATE")
GzLevelUpDB.rezMessage = "wb {names} ({count})"
reset(); revive("party1"); revive("party2")
check("both rezzes share one timer", #timers, 1)
runTimers()
check("batched into one message", lastSent(), "wb Alice, Bob (2)")
GzLevelUpDB.rezMessage = "wb {name}"

section("rez reply: what is not a rez")
world.party3.dead = false
fire("GROUP_ROSTER_UPDATE")
reset(); fire("UNIT_HEALTH", "party3")
check("a member who never died stays silent", #timers, 0)

-- A hunter who was only feigning was never dead, so getting up is nothing.
world.party1.dead, world.party1.feign = true, true
fire("GROUP_ROSTER_UPDATE")
world.party1.dead, world.party1.feign = false, false
reset(); fire("UNIT_HEALTH", "party1")
check("getting up from feign death is not a rez", #timers, 0)

section("rez reply: my own")
GzLevelUpDB.announceSelfRez = true
GzLevelUpDB.selfRezMessage = "ty {name}"

-- Walking back from the graveyard: nobody got me up, so there is nobody to
-- thank and nothing to say.
world.player.dead = true
fire("GROUP_ROSTER_UPDATE")
reset(); revive("player")
check("a corpse run says nothing", #timers, 0)

-- But an offered resurrect is answered, and it names whoever cast it.
world.player.dead = true
fire("GROUP_ROSTER_UPDATE")
fire("RESURRECT_REQUEST", "Alice-Blackrock") -- cross-realm suffix is stripped
reset(); revive("player")
runTimers()
check("thanks whoever rezzed me", lastSent(), "ty Alice")

-- That offer is used up now.
world.player.dead = true
fire("GROUP_ROSTER_UPDATE")
reset(); revive("player")
check("the offer is not reused", #timers, 0)

-- Declining and taking the spirit healer instead lands you at the graveyard,
-- far from whoever offered — the game reports no "declined", so the distance is
-- what gives it away.
world.player.dead = true
fire("GROUP_ROSTER_UPDATE")
fire("RESURRECT_REQUEST", "Alice")
world.party1.far = true
reset(); revive("player")
check("an offer from far away does not count", #timers, 0)
world.party1.far = false

-- Somebody outside the group cannot be range-checked at all, so their offer is
-- taken at face value rather than dropped.
world.player.dead = true
fire("GROUP_ROSTER_UPDATE")
fire("RESURRECT_REQUEST", "Stranger")
reset(); revive("player")
runTimers()
check("a passer-by still counts", lastSent(), "ty Stranger")

-- And one that is a minute old has expired along with the game's own dialog.
world.player.dead = true
fire("GROUP_ROSTER_UPDATE")
fire("RESURRECT_REQUEST", "Bob")
now = now + 90
reset(); revive("player")
check("a stale offer does not count", #timers, 0)
now = 0

-- My line and the member line are separate, even when the person who rezzed me
-- was rezzed in the same window: my own entry is kept apart from the name list.
world.player.dead, world.party1.dead = true, true
fire("GROUP_ROSTER_UPDATE")
fire("RESURRECT_REQUEST", "Alice")
reset(); revive("player"); revive("party1")
runTimers()
check("both lines go out", #sent, 2)
check("mine first, naming the rezzer", sent[1] and sent[1].msg, "ty Alice")
check("then the member line", sent[2] and sent[2].msg, "wb Alice")

section("rez reply: slash commands")
slash("rez")
check("rez toggles off", GzLevelUpDB.announceRez, false)
slash("rez")
check("rez toggles back on", GzLevelUpDB.announceRez, true)
slash("selfrez")
check("selfrez toggles off", GzLevelUpDB.announceSelfRez, false)
slash("rezmsg wb {names}!")
check("rezmsg set", GzLevelUpDB.rezMessage, "wb {names}!")
slash("selfrezmsg ty {name}!")
check("selfrezmsg set", GzLevelUpDB.selfRezMessage, "ty {name}!")
slash("delay selfrez 6")
check("delay selfrez 6", GzLevelUpDB.selfRezDelay, 6)
check("other delays untouched", GzLevelUpDB.rezDelay, 0)
slash("delay 3")
check("delay all reaches rez", GzLevelUpDB.rezDelay, 3)
check("delay all reaches my rez", GzLevelUpDB.selfRezDelay, 3)

section("quick panel: the button grid")
fire("PLAYER_ENTERING_WORLD")
local panel = GzLevelUpQuickPanel
local PAD, BTN_W, BTN_H, GAP, ROW_GAP, TOP = 8, 62, 24, 8, 4, 22
local function panelW(cols) return PAD * 2 + cols * BTN_W + (cols - 1) * GAP end
local function panelH(rows) return PAD + TOP + rows * BTN_H + (rows - 1) * ROW_GAP end

check("one row of two by default",
      GzLevelUpDB.quickPanelRows .. "x" .. GzLevelUpDB.quickPanelCols, "1x2")
check("with the texts it always had",
      table.concat(GzLevelUpDB.quickPanelButtons, ","), "gz,ty")
check("the panel is the size it always was", panel:GetWidth(), panelW(2))
check("in both directions", panel:GetHeight(), panelH(1))
check("two buttons on screen", panel.buttons[2]:IsShown(), true)
check("and no third one built", panel.buttons[3], nil)

-- Two by three: the panel grows in both directions and fills the new slots.
GzLevelUpDB.quickPanelRows, GzLevelUpDB.quickPanelCols = 2, 3
GzLevelUpDB.quickPanelButtons = { "gz", "ty", "wb", "F", "brb", "omw" }
fire("PLAYER_ENTERING_WORLD")
check("six buttons now", panel.buttons[6]:IsShown(), true)
check("wider", panel:GetWidth(), panelW(3))
check("taller", panel:GetHeight(), panelH(2))

-- Each button sends the text of its own slot, not of the one it was built as.
GzLevelUpDB.quickPanelEnabled = true
reset(); panel.buttons[5]:GetScript("OnClick")()
check("a button sends its own slot's text", lastSent(), "brb")

-- Shrinking hides the leftovers rather than leaving them floating.
GzLevelUpDB.quickPanelRows, GzLevelUpDB.quickPanelCols = 1, 2
fire("PLAYER_ENTERING_WORLD")
check("the extra buttons go away", panel.buttons[6]:IsShown(), false)
check("and the panel is back to its old size", panel:GetWidth(), panelW(2))

-- Neither slider can push the grid somewhere the panel cannot follow.
GzLevelUpDB.quickPanelRows, GzLevelUpDB.quickPanelCols = 0, 99
fire("PLAYER_ENTERING_WORLD")
check("a side of zero counts as one", panel:GetHeight(), panelH(1))
check("and four is the ceiling", panel:GetWidth(), panelW(4))
GzLevelUpDB.quickPanelRows, GzLevelUpDB.quickPanelCols = 1, 2
GzLevelUpDB.quickPanelEnabled = false

section("quick panel: upgrading from the two fixed buttons")
GzLevelUpDB = { gzButtonMessage = "gratz!", tyButtonMessage = "thx" }
GzLevelUpProfilesDB = {}
fire("ADDON_LOADED", "GzLevelUp")
check("both texts move onto the grid",
      table.concat(GzLevelUpDB.quickPanelButtons, ","), "gratz!,thx")
check("still one row of two", GzLevelUpDB.quickPanelCols, 2)
check("and the old keys are dropped", GzLevelUpDB.gzButtonMessage, nil)

section("profiles: upgrading from a version without them")
-- Somebody who has been using the addon for a while: settings in the flat DB,
-- no profile store anywhere. Nothing about that may change for them.
GzLevelUpDB = { message = "Gz {name}, nice one!", includeSelf = true }
GzLevelUpProfilesDB = {}
fire("ADDON_LOADED", "GzLevelUp")
check("their settings survive", GzLevelUpDB.message, "Gz {name}, nice one!")
check("and the rest is defaulted", GzLevelUpDB.announceRez, false)
check("they now have a profile", GzLevelUpProfilesDB.active, "Default")
check("holding the same message", GzLevelUpProfilesDB.profiles.Default.message,
      "Gz {name}, nice one!")
check("bound to this character", GzLevelUpProfilesDB.chars["Brend - Blackrock"], "Default")

section("profiles: creating and switching")
slash("profile new Raid")
check("the new profile is active", GzLevelUpProfilesDB.active, "Raid")
check("and starts as a copy of the old one", GzLevelUpDB.message, "Gz {name}, nice one!")
GzLevelUpDB.message, GzLevelUpDB.useRaidChat = "gz", true
slash("profile Default")
check("switching back restores the text", GzLevelUpDB.message, "Gz {name}, nice one!")
check("and the raid setting", GzLevelUpDB.useRaidChat, false)
slash("profile Raid")
check("the other profile kept its own text", GzLevelUpDB.message, "gz")
check("and its own raid setting", GzLevelUpDB.useRaidChat, true)
slash("profile Nope")
check("an unknown name changes nothing", GzLevelUpProfilesDB.active, "Raid")
slash("profile new Raid")
check("a name cannot be taken twice", GzLevelUpProfilesDB.active, "Raid")

-- The button list is a table, so every profile needs its own: handing the
-- same one to two profiles would let editing one quietly edit the other.
GzLevelUpDB.quickPanelButtons[1] = "yo"
slash("profile Default")
check("Default keeps its own button list", GzLevelUpDB.quickPanelButtons[1], "gz")
slash("profile Raid")
check("and Raid keeps the edit", GzLevelUpDB.quickPanelButtons[1], "yo")

section("profiles: where a window sits is not a setting")
GzLevelUpDB.configPos = { point = "CENTER", x = 12, y = 34 }
slash("profile Default")
check("the window stays where it was", GzLevelUpDB.configPos and GzLevelUpDB.configPos.x, 12)
check("and the profile does not carry it", GzLevelUpProfilesDB.profiles.Raid.configPos, nil)

section("profiles: one per character")
-- Log out and back in as somebody else on the same account.
fire("PLAYER_LOGOUT")
world.player.name = "Zwerg"
fire("ADDON_LOADED", "GzLevelUp")
check("an unknown character keeps what is loaded", GzLevelUpProfilesDB.active, "Default")
check("and is bound to it", GzLevelUpProfilesDB.chars["Zwerg - Blackrock"], "Default")
slash("profile Raid")
fire("PLAYER_LOGOUT")
world.player.name = "Brend"
fire("ADDON_LOADED", "GzLevelUp")
check("the first character is back on its own", GzLevelUpProfilesDB.active, "Default")
check("with its own message", GzLevelUpDB.message, "Gz {name}, nice one!")
check("the other one stays where it was left", GzLevelUpProfilesDB.chars["Zwerg - Blackrock"], "Raid")

section("profiles: deleting")
slash("profile delete Default")
check("the active one is refused", GzLevelUpProfilesDB.profiles.Default ~= nil, true)
slash("profile delete Raid")
check("another one goes", GzLevelUpProfilesDB.profiles.Raid, nil)
check("and its characters are unbound", GzLevelUpProfilesDB.chars["Zwerg - Blackrock"], nil)
check("the live settings are untouched", GzLevelUpDB.message, "Gz {name}, nice one!")

section("profiles: restoring defaults stops at the active profile")
slash("")  -- opening the window is what builds the reset popup
slash("profile new Raid")
GzLevelUpDB.message = "gz"
slash("profile Default")
GzLevelUpDB.quickPanelPos = { point = "CENTER", x = 70, y = 80 }
StaticPopupDialogs["GZLEVELUP_RESET"].OnAccept()
check("the active profile is back to stock", GzLevelUpDB.message, "Gz {name}!")
check("the other one is left alone", GzLevelUpProfilesDB.profiles.Raid.message, "gz")
-- Resetting your messages is no reason to throw the panels across the screen.
check("the panel stays where it was dragged",
      GzLevelUpDB.quickPanelPos and GzLevelUpDB.quickPanelPos.x, 70)
check("and so does the config window",
      GzLevelUpDB.configPos and GzLevelUpDB.configPos.x, 12)

section("profiles: the settings tab")
local menu = dropdownEntries(GzLevelUpProfileDropDown)
check("the menu lists every profile", #menu, 2)
check("in a stable order", (menu[1].text or "") .. "/" .. (menu[2].text or ""), "Default/Raid")
check("with the active one ticked", menu[1].checked, true)
check("and the other one not", menu[2].checked, false)
menu[2].func()
check("clicking an entry switches", GzLevelUpProfilesDB.active, "Raid")
check("and loads its settings", GzLevelUpDB.message, "gz")

-- The new-profile dialog: a name, and a checkbox deciding where the settings
-- come from.
local newDialog = GzLevelUpNewProfileDialog
local function fillNewDialog(name, copyCurrent)
    newDialog.nameBox:SetText(name)
    newDialog.copyCheck:SetChecked(copyCurrent)
    newDialog.Confirm()
end

fillNewDialog("  Dungeon  ", true)
check("the dialog creates a profile", GzLevelUpProfilesDB.profiles.Dungeon ~= nil, true)
check("with the name trimmed", GzLevelUpProfilesDB.active, "Dungeon")
check("taking the current settings over", GzLevelUpDB.message, "gz")

-- Unticked, the new profile starts from what the addon ships with instead.
-- Two settings that are off by default get switched on first, so "back to
-- stock" means more than the message being replaced.
GzLevelUpDB.announceRez, GzLevelUpDB.useRaidChat = true, true
fillNewDialog("Fresh", false)
check("a fresh profile is active", GzLevelUpProfilesDB.active, "Fresh")
check("and starts from the shipped defaults", GzLevelUpDB.message, "Gz {name}!")
check("switches are back to stock too", GzLevelUpDB.announceRez, false)
check("all of them", GzLevelUpDB.useRaidChat, false)
check("the profile we came from kept its message",
      GzLevelUpProfilesDB.profiles.Dungeon.message, "gz")
check("and kept its switches", GzLevelUpProfilesDB.profiles.Dungeon.announceRez, true)

-- A name that is only blanks is no name at all, and nothing is created.
local before = GzLevelUpProfilesDB.active
fillNewDialog("   ", true)
check("an empty name creates nothing", GzLevelUpProfilesDB.active, before)

fillNewDialog("Dungeon", true)
check("an existing name is refused", GzLevelUpProfilesDB.active, before)

-- A profile built from the defaults must get a copy of them, not the defaults
-- themselves: otherwise editing a button would rewrite what "default" means
-- for every profile made from here on.
fillNewDialog("Stock", false)
GzLevelUpDB.quickPanelButtons[3] = "edited"
fillNewDialog("Stock2", false)
check("the shipped defaults cannot be edited through a profile",
      GzLevelUpDB.quickPanelButtons[3], nil)

slash("profile Dungeon")
slash("profile delete Fresh")
slash("profile delete Stock")
slash("profile delete Stock2")

-- Deleting from the tab removes the profile you are on, so it steps aside
-- first - the slash command refuses instead, where you name it yourself.
StaticPopupDialogs["GZLEVELUP_DELETE_PROFILE"].OnAccept()
check("the profile is gone", GzLevelUpProfilesDB.profiles.Dungeon, nil)
check("and we landed on another one", GzLevelUpProfilesDB.active, "Default")
check("whose settings are loaded", GzLevelUpDB.message, "Gz {name}!")

section("addon metadata (feeds the info tab)")
local meta = GetAddOnMetadata
check("version present", type(meta("GzLevelUp", "Version")), "string")
check("version looks like a number", (meta("GzLevelUp", "Version") or ""):match("^%d") ~= nil, true)
check("author present", meta("GzLevelUp", "Author"), "BrendTM")
check("curseforge link is a url",
      (meta("GzLevelUp", "X-CurseForge") or ""):match("^https://") ~= nil, true)
check("github link is a url",
      (meta("GzLevelUp", "X-Website") or ""):match("^https://") ~= nil, true)
check("saved variables declared", meta("GzLevelUp", "SavedVariables"),
      "GzLevelUpDB, GzLevelUpProfilesDB")

section("minimap button")
check("off by default", GzLevelUpDB.minimapEnabled, false)
check("has a default angle", type(GzLevelUpDB.minimapAngle), "number")
slash("minimap")
check("toggles on", GzLevelUpDB.minimapEnabled, true)
slash("minimap")
check("toggles back off", GzLevelUpDB.minimapEnabled, false)
GzLevelUpDB.minimapAngle = 42
fire("ADDON_LOADED", "GzLevelUp")
check("a moved button keeps its angle", GzLevelUpDB.minimapAngle, 42)

section("changelog")
-- A version bump without a changelog entry would ship a release whose notes
-- fall back to a single generic line, so tie the two together here.
local version = meta("GzLevelUp", "Version")
local changelog = io.open(here .. "/../CHANGELOG.md")
check("CHANGELOG.md present", changelog ~= nil, true)
if changelog then
    local text = changelog:read("*a")
    changelog:close()
    local heading = "## " .. version
    check("has a section for the current version",
          text:find(heading, 1, true) ~= nil, true)
end

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

section("config window sizing")
-- Each tab is only as wide as its own label, so a longer translation makes the
-- bar longer. If the window kept a fixed width the last tab would hang out
-- through the frame border, which is exactly what German did. The bar measures
-- itself instead and stretches the window.
--
-- This reloads the addon, so it has to stay the last section: the reload
-- replaces the event handler and the slash command everything above captured.
local function configWidth(locale)
    GetLocale = function() return locale end
    harness.loadAddon(here .. "/..")
    GzLevelUpDB = {}
    fire("ADDON_LOADED", "GzLevelUp")
    SlashCmdList.GZLEVELUP("")  -- opening the window is what builds it
    return GzLevelUpConfigFrame:GetWidth(), GzLevelUpConfigFrame:GetHeight()
end

local enWidth, enHeight = configWidth("enUS")
local deWidth, deHeight = configWidth("deDE")
check("English keeps the minimum width", enWidth, 500)
check("German is wider than English", deWidth > enWidth, true)
-- The harness approximates font metrics, so the exact pixel is meaningless -
-- that the window follows the labels at all is the point.
check("German still fits a sane window", deWidth < 800, true)
check("height is unaffected", enHeight, 430)
check("height is the same in German", deHeight, enHeight)

print(string.format("\n%d checks, %d failed", total, fails))
os.exit(fails == 0 and 0 or 1)
