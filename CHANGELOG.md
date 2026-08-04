# Changelog

Notable changes per release. The section for a version is used verbatim as the
GitHub release body and can be pasted into the CurseForge changelog field, so
it is written for players rather than for the diff.

## 1.2

The addon now reacts to deaths as well — completely opt-in, nothing changes
until you switch it on.

### New

- **Death reply tab** (opt-in) — post a message when a group member dies, when
  *you* die, or when the whole group wipes. Each of the three has its own
  switch, its own text and its own 0–60 s delay, exactly like the level-up
  messages.
- **Deaths are collected, not spammed.** Deaths rarely come alone, so they are
  gathered for a moment (3 s by default) and answered with a *single* message
  instead of one line per corpse. Out of the box that message is `F {name}`;
  swap in `{names}` and it lists everyone who died: `F Alice, Bob`.
- **Wipe handling.** Once as many people die at once as the wipe threshold
  (3 by default), the individual messages are dropped and only the wipe line is
  posted — or nothing at all, if you leave that line switched off. Set the
  threshold to 0 to never treat anything as a wipe.
- New placeholders in the death messages: `{names}` (everyone who died),
  `{count}` (how many), plus the familiar `{name}` and `{level}`.
- A hunter feigning death is not a death, and a corpse that was already on the
  floor when you joined is not announced either.
- A thank-you on the info tab, right under the author: **Nuiti**, for the ideas.

### New commands

| Command | Description |
|---|---|
| `/gz death` | Toggle announcing a group member's death |
| `/gz selfdeath` | Toggle announcing your own death |
| `/gz wipe` | Toggle the wipe message |
| `/gz deathmsg`, `/gz selfdeathmsg`, `/gz wipemsg` `<text>` | Set the three death messages |
| `/gz delay <death\|selfdeath\|wipe> <sec>` | Set the delay for one of them |

### Changed

- The config window grew a sixth tab and is a little larger to fit it. It now
  also **sizes itself to the tab labels**, so a translation with longer words no
  longer pushes the last tab out through the frame border.
- **The German translation was reworked.** It finally uses real umlauts
  (*Verzögerung* instead of *Verzoegerung*), speaks the game's own vocabulary
  (*Begleiter* instead of *Tiere*, *Levelaufstieg* instead of *Aufstieg*), and
  the quick panel is called *Quick-Panel* everywhere instead of switching
  between two names. The default messages are no longer translated separately —
  German and English clients start from the same "Gz", "ty" and "F".

## 1.1

The config window has been rebuilt from the ground up, and the addon can now do
a lot more than post "gz".

### New

- **Five-tab config window** — Messages, Auto reply, Quick panel, Settings and
  Info. Everything saves itself; the *Save* button is gone.
- **Pets and companions** (opt-in) — congratulate a hunter's or warlock's pet
  as well, with its own message and a new `{owner}` placeholder.
- **A switch and a delay per category** — group members, your own level-ups and
  pets can each be turned on or off separately and given their own 0–60 s delay.
- **Auto reply** (opt-in) — after *your own* level-up the addon listens for
  people saying "gz" and then thanks them all in a single "ty", naming everyone.
  Nobody congratulates you? Nothing is sent.
- **Minimap button** (opt-in) — left-click for the settings, right-click for the
  quick panel, drag it anywhere around the minimap.
- **Addon icon** in the in-game addon list (no more red question mark).
- **Info tab** with version, author and links to CurseForge and GitHub.
- The config window **remembers where you dragged it**.

### Changed

- **Raid chat is now opt-in.** In a 40-man raid an automatic "gz" per level-up
  is spam for most people, so the addon stays silent in raids until you tick
  *Settings → Also use raid chat*. This is the one change that affects how the
  addon behaved in 1.0.
- Long labels moved into a `(?)` tooltip, and every message has a live preview.

### New commands

| Command | Description |
|---|---|
| `/gz group` | Toggle announcing group members |
| `/gz pets` | Toggle announcing pets and companions |
| `/gz petmsg <text>` | Set the message for a pet's level-up |
| `/gz reply` | Toggle the auto reply |
| `/gz raid` | Toggle using raid chat |
| `/gz minimap` | Toggle the minimap button |
| `/gz delay <group\|self\|pets> <sec>` | Set the delay for one category |

### Upgrading from 1.0

Your existing messages and settings are kept. The old single delay is carried
over to all three categories automatically. If you want the addon to keep
posting in raids, enable *Also use raid chat* in the Settings tab.

## 1.0

First release.

- Posts a configurable message to party or raid chat when a group member gains
  a level, with `{name}` and `{level}` placeholders.
- Only fires on real level-ups — never when someone joins the group or comes
  into range.
- Optional separate message for your own level-up.
- Optional delay before sending.
- Movable quick-button panel with configurable **gz** / **ty** buttons.
- In-game config window via `/gz`, plus slash commands for every setting.
- English and German, picked automatically from the client language.
