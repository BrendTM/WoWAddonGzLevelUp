# GzLevelUp

**Never miss a "gz" again.** GzLevelUp automatically posts a congratulations
message to your party or raid chat the moment a group member levels up — so you
can keep questing, fighting, and looting without breaking your flow.

Lightweight, fully configurable, and built for WoW Classic / Anniversary realms.

---

## Features

- **Automatic level-up congratulations** — when anyone in your group gains a
  level, GzLevelUp posts your message to the correct channel automatically
  (party or raid).
- **Smart detection** — congratulations are only sent for real level-ups, never
  when a member simply joins the group or comes into range.
- **Separate message for your own level-up** — optionally announce your own
  "ding" with a completely different text (opt-in).
- **Customizable messages** with placeholders:
  - `{name}` — the player's name
  - `{level}` — the new level
- **Optional send delay** (opt-in) — add a configurable pause (0–60 seconds)
  before the message is sent, so it feels natural instead of instant.
- **Movable quick-button panel** (opt-in) — a small floating panel with two
  buttons (**gz** / **ty**) that post to your group with a single click. The
  button texts are fully configurable, the panel remembers its position, and
  it can be resized from 50% to 200%.
- **In-game config window** — set everything up with `/gz`, including a live
  preview of your messages.
- **Localization** — English by default, with German included automatically on
  German clients.
- **Tiny footprint** — no dependencies, minimal memory use, no background
  polling.

---

## Getting started

1. Install and log in.
2. Type **`/gz`** to open the configuration window.
3. Customize your messages, or just leave the defaults and play.

That's it — the addon works out of the box.

---

## Configuration window (`/gz`)

- **Message for group members** — sent when someone else levels up.
- **Message for your own level-up** — used only when *you* level up (enable the
  checkbox first).
- **Delay before sending** — opt-in; set the number of seconds.
- **Quick-buttons panel** — opt-in; show the floating gz/ty panel, set the two
  button texts, and adjust the panel size with the slider.
- **Live preview** for both messages, so you see exactly how they'll look.

---

## Slash commands

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

---

## Placeholders

Use these in any message:

- **`{name}`** → the leveling player's name
- **`{level}`** → their new level

Example: `Gz {name}, welcome to level {level}!`

---

## Compatibility

Built for the WoW Classic / Anniversary client. It automatically posts to
**raid** chat when you're in a raid, and to **party** chat otherwise. Nothing is
sent when you're not in a group.

---

## Feedback

Bug reports, suggestions, and translations are welcome — please leave a comment
or open a ticket. Enjoy, and gz! 🎉

*Author: BrendTM*
