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

- **Automatic level-up congratulations** — posts your message to the correct
  channel automatically (party or raid) when a group member gains a level.
- **Smart detection** — only fires on real level-ups, never when a member joins
  the group or comes into range.
- **Separate self message** — optionally announce your own "ding" with a
  different text (opt-in).
- **Customizable messages** with placeholders `{name}` and `{level}`.
- **Optional send delay** (opt-in) — a configurable 0–60 s pause before sending.
- **Movable quick-button panel** (opt-in) — a floating panel with two buttons
  (**gz** / **ty**) that post to your group with one click. Configurable button
  texts, remembered position, and a size slider (50–200 %).
- **In-game config window** (`/gz`) with a live preview.
- **Localization** — English by default, German included automatically on
  German clients.
- **Tiny footprint** — no dependencies, no background polling.

---

## Screenshots

<table>
  <tr>
    <td align="center" valign="top">
      <img src="media/example_main_panel.jpg" width="320" alt="GzLevelUp configuration window"><br>
      <sub>In-game config window (<code>/gz</code>)</sub>
    </td>
    <td align="center" valign="top">
      <img src="media/example_quick_panel.jpg" width="200" alt="GzLevelUp quick-buttons panel"><br>
      <sub>Movable quick-buttons panel (gz / ty)</sub>
    </td>
  </tr>
</table>

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
| `/gz delay <sec>` | Delay before sending (`0` or `off` disables it) |
| `/gz panel` | Toggle the floating quick-buttons panel |
| `/gz scale <pct>` | Set the quick panel size in percent (50–200) |
| `/gz test` | Preview your current messages (nothing is sent) |

### Placeholders

Use these in any message:

- **`{name}`** → the leveling player's name
- **`{level}`** → their new level

Example: `Gz {name}, welcome to level {level}!`

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
│   └── GzLevelUp.lua     # core logic + config UI + quick panel
├── media/                # logo assets (not shipped with the addon)
├── CURSEFORGE.md         # CurseForge project description
├── LICENSE
└── README.md
```

---

## Building a release package

Zip the `GzLevelUp/` folder so it unpacks as `GzLevelUp/…`:

```bash
zip -r GzLevelUp.zip GzLevelUp
```

The `media/`, `CURSEFORGE.md`, and repository metadata are intentionally left
out of the addon package.

---

## Contributing

Bug reports, suggestions, and translations are welcome — please open an issue or
pull request.

---

## License

Released under the [MIT License](LICENSE).

*Author: BrendTM*
