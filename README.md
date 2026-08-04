# GzLevelUp

**Never miss a "gz" again.** GzLevelUp automatically posts a congratulations
message to your party or raid chat the moment a group member levels up — so you
can keep questing, fighting, and looting without breaking your flow.

Lightweight, fully configurable, and built for **WoW Classic / Anniversary** realms.

<p align="center">
  <img src="media/logo.png" width="160" alt="GzLevelUp logo">
</p>

<p align="center">
  <a href="https://www.curseforge.com/wow/addons/gzlevelup">Download on CurseForge</a>
</p>

---

## Features

- **Automatic level-up congratulations** — posts your message to party chat the
  moment a group member gains a level (raid chat is opt-in).
- **Smart detection** — only fires on real level-ups, never when a member joins
  the group or comes into range.
- **Separate self message** — optionally announce your own "ding" with a
  different text (opt-in).
- **Pets and companions** (opt-in) — congratulate a hunter's or warlock's pet
  too, with its own message and an `{owner}` placeholder.
- **Customizable messages** with placeholders `{name}` and `{level}`.
- **Per-category delay** — each of the three announcement types has its own
  0–60 s pause before sending (`0` = immediately).
- **Movable quick-button panel** (opt-in) — a floating panel with two buttons
  (**gz** / **ty**) that post to your group with one click. Configurable button
  texts, remembered position, and a size slider (50–200 %).
- **Auto reply** (opt-in) — after *your own* level-up, wait for people to say
  "gz" and then thank them all in a single "ty", naming everyone.
- **Death reply** (opt-in) — say something when a group member dies, when you
  die, or when the group wipes. Deaths are collected for a moment and answered
  with one message naming everyone, and a wipe gets its own line instead of a
  flood of them (or nothing at all, if you leave that line off).
- **Raid-safe** — raid chat is opt-in, so the addon stays quiet in a 40-man raid
  unless you allow it.
- **Minimap button** (opt-in) — drag it anywhere around the minimap; left-click
  opens the settings, right-click toggles the quick panel.
- **In-game config window** (`/gz`) — six tabs, live preview, auto-save, and it
  remembers where you dragged it.
- **Localization** — English by default, German included automatically on
  German clients.
- **Tiny footprint** — no dependencies, no background polling.

---

## Screenshots

The config window (<code>/gz</code>) is split across six tabs:

<table>
  <tr>
    <td align="center" valign="top" width="50%">
      <img src="media/example_messages_panel.jpg" width="380" alt="Messages tab"><br>
      <sub><b>Messages</b> — a switch, a message and a delay per category</sub>
    </td>
    <td align="center" valign="top" width="50%">
      <img src="media/example_auto_reply_panel.jpg" width="380" alt="Auto reply tab"><br>
      <sub><b>Auto reply</b> — thank everyone who congratulated you, in one message</sub>
    </td>
  </tr>
  <tr>
    <td align="center" valign="top" width="50%">
      <img src="media/example_quick_panel_panel.jpg" width="380" alt="Quick panel tab"><br>
      <sub><b>Quick panel</b> — button texts and panel size</sub>
    </td>
    <td align="center" valign="top" width="50%">
      <img src="media/example_settings_panel.jpg" width="380" alt="Settings tab"><br>
      <sub><b>Settings</b> — master switch, raid chat and minimap button</sub>
    </td>
  </tr>
</table>

<p align="center">
  <img src="media/example_quick_panel.jpg" width="200" alt="GzLevelUp quick-buttons panel"><br>
  <sub>The movable quick-buttons panel (gz / ty)</sub>
</p>

---

## Installation

### CurseForge (recommended)
Install and auto-update via the
[CurseForge app](https://www.curseforge.com/wow/addons/gzlevelup) — search for
**GzLevelUp** or use the app's install button on the addon page.

### Manual
1. Download the latest release.
2. Copy the `GzLevelUp` folder into your WoW `Interface/AddOns/` directory:
   ```
   World of Warcraft/_classic_era_/Interface/AddOns/GzLevelUp/
   ```
3. Restart the game (or enable the addon on the character screen).

### From this repository
The `GzLevelUp/` folder in this repo is install-ready — copy it directly into
your `Interface/AddOns/` directory.

---

## Usage

Type **`/gz`** to open the configuration window. The addon also works out of the
box with sensible defaults.

### Slash commands

| Command | Description |
|---|---|
| `/gz` | Open / close the configuration window |
| `/gz on` \| `off` | Enable or disable the addon |
| `/gz msg <text>` | Set the message for group members |
| `/gz selfmsg <text>` | Set the message for your own level-up |
| `/gz self` | Toggle announcing your own level-up |
| `/gz petmsg <text>` | Set the message for a pet's level-up |
| `/gz group` | Toggle announcing group members |
| `/gz raid` | Toggle using raid chat (off by default) |
| `/gz reply` | Toggle the auto reply after your own level-up |
| `/gz pets` | Toggle announcing pets and companions |
| `/gz death` | Toggle announcing a group member's death |
| `/gz selfdeath` | Toggle announcing your own death |
| `/gz wipe` | Toggle the wipe message |
| `/gz deathmsg <text>` | Set the message for a group member's death |
| `/gz selfdeathmsg <text>` | Set the message for your own death |
| `/gz wipemsg <text>` | Set the wipe message |
| `/gz delay <sec>` | Set the delay for every category (`0` = immediately) |
| `/gz delay <group\|self\|pets\|death\|selfdeath\|wipe> <sec>` | Set the delay for one category |
| `/gz panel` | Toggle the floating quick-buttons panel |
| `/gz minimap` | Toggle the minimap button (off by default) |
| `/gz scale <pct>` | Set the quick panel size in percent (50–200) |
| `/gz test` | Preview your current messages (nothing is sent) |

### Placeholders

In the three level-up messages:

- **`{name}`** → the name of whoever levelled up (player or pet)
- **`{level}`** → their new level
- **`{owner}`** → the pet's owner — only meaningful in the pet message

Example: `Gz {name}, welcome to level {level}!`
Pet example: `Gz {owner}'s {name}!`

In the auto-reply message:

- **`{names}`** → everyone who congratulated you, comma separated
- **`{name}`** → the first one
- **`{count}`** → how many there were

Example: `ty {names}!`

In the three death messages:

- **`{names}`** → everyone who died in this batch, comma separated
- **`{name}`** → the first one
- **`{count}`** → how many there were
- **`{level}`** → their level

The default is `F {name}` — a line about one member. Put `{names}` in instead
and a batch becomes a list: `F Alice, Bob`.

Wipe example: `Wipe — {count} down.`

---

## How the death reply decides what to say

Deaths cluster, so the addon waits a moment before saying anything:

1. The first death opens a collection window (3 s by default).
2. Every further death inside that window joins the same message.
3. When it closes, one of three things happens:
   - fewer deaths than the wipe threshold → one message, plus your own separate
     line if you died too;
   - at least as many as the threshold → only the wipe message;
   - …and if the wipe message is switched off, nothing at all.

Note that step 3 sends **one** message either way. With the default `F {name}`
it names the first of them; use `{names}` if you want all of them listed.

Set the threshold to `0` to never treat anything as a wipe. Deaths are counted
towards the threshold even when their own message is switched off, so "two of
them plus me" still registers as a wipe.

A hunter feigning death does not count, and neither does a corpse that was
already lying there when you joined the group — the addon only reacts to the
moment somebody goes from alive to dead while it is watching.

---

## Localization

The UI language follows your WoW client language. **English** is the default;
**German (deDE)** is included and used automatically on German clients. To add a
language, extend `GzLevelUp/Locale.lua` with a new `if GetLocale() == "xxXX"`
block.

---

## Project structure

```
.
├── GzLevelUp/            # the addon itself (install-ready)
│   ├── GzLevelUp.toc
│   ├── Locale.lua        # localization (enUS + deDE)
│   ├── GzLevelUp.lua     # core logic + config UI + quick panel
│   └── icon.tga          # icon for the in-game addon list
├── tests/                # test suite (not shipped with the addon)
│   ├── harness.lua       # stubbed WoW API
│   └── run.lua           # the tests
├── ci/                   # release tooling
│   ├── build_package.py  # stamps the version and builds the zip
│   └── release_notes.py  # pulls the release body from CHANGELOG.md
├── CHANGELOG.md          # per-release notes
├── media/                # logo assets (not shipped with the addon)
├── CURSEFORGE.md         # CurseForge project description
├── LICENSE
└── README.md
```

---

## Tests

The suite loads the real addon against a stubbed WoW API, drives it through
events (`UNIT_LEVEL`, `CHAT_MSG_PARTY`, …) and asserts on what it would have
said in chat. No game client needed:

```bash
lua5.1 tests/run.lua
```

WoW Classic embeds Lua 5.1, so that is the version CI runs. Any Lua ≥ 5.1 works
locally. The suite exits non-zero on failure and gates both the `test` workflow
(every push) and the `release` workflow (tags).

---

## Releasing

1. Add a `## <version>` section to [CHANGELOG.md](CHANGELOG.md) describing the
   release. The test suite fails if the version in the `.toc` has no section.
2. Bump `## Version:` in `GzLevelUp/GzLevelUp.toc` and commit.
3. Tag and push:

   ```bash
   git tag 1.2 && git push origin 1.2
   ```

The workflow then runs the test suite, stamps the version into the `.toc`,
builds `GzLevelUp-<version>.zip` and publishes a GitHub release using the
changelog section as its body. The same section can be pasted straight into the
CurseForge changelog field.

---

## Building a release package

Zip the `GzLevelUp/` folder so it unpacks as `GzLevelUp/…`:

```bash
zip -r GzLevelUp.zip GzLevelUp
```

The `media/`, `tests/`, `CURSEFORGE.md`, and repository metadata are
intentionally left out of the addon package.

`GzLevelUp/icon.tga` is generated from `media/logo.png` and shows up next to the
addon in the in-game addon list. WoW reads only BLP and TGA — not PNG — so it
has to be a 64×64 uncompressed 32-bit TGA:

```bash
python3 -c "from PIL import Image; \
Image.open('media/logo.png').convert('RGBA').resize((64,64), Image.LANCZOS) \
.save('GzLevelUp/icon.tga', compression=None)"
```

---

## Contributing

Bug reports, suggestions, and translations are welcome — please open an issue or
pull request.

---

## License

Released under the [MIT License](LICENSE).

*Author: BrendTM*
