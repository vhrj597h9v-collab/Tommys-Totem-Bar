# Totem Tommys Bars

A movable shaman utility bar addon for **World of Warcraft Classic Era (1.15.x)**. Built for hardcore self-found play — keeps every totem, imbue, Lightning Shield, and utility button one click away with smart "missing buff" alerts so you never wipe because you forgot Mana Spring again.

---

## Features

- **5 dockable bars**
  - 4 totem element buttons (Fire / Water / Earth / Air)
  - Imbue mini-bar (Mainhand / Offhand / Lightning Shield)
  - 2 utility slots (any utility spell from your spellbook)
  - **Totem Sequence** button (castsequence-driven "stomp" macro, customizable per-sequence reset timer)
  - **Totem Stack** preset switcher (one-click swap of all four element defaults)
- **In-combat missing-buff alerts** — wobble / bounce / shake / pulse / spin movement, raid-warning audio, gold/red glow rings, 10% duration red-border warning, configurable per slot and per group
- **Duration timer** (yellow text above the button) and **CD timer** (cooldown swipe + countdown)
- **Linked / paired stacks** — bind a Totem Stack to a Utility Stack so loading one auto-loads the other (bidirectional)
- **Configurable cycle modifier** — bind `Drop Fire Totem` to A, set modifier to Alt, then Alt+A cycles instead of casting
- **Native Blizzard Key Bindings integration** — 20 bindings registered under their own "Totem Tommys Bars" section
- **Minimap button** with LibDataBroker/LibDBIcon support — opens options, shift-click hides every bar
- **Combine bars** — merge any 2 or 3 groups onto a single host frame with per-group scale + layout, or keep each solo
- **Saved Sequences / Totem Stacks / Utility Stacks** (up to 20 each) with paired-with column
- **"Default Settings" button** restores every option to factory; `/ttb savepos` snapshots your current bar layout as your personal default

## Install

1. Download the latest release ZIP from the [Releases](../../releases) page (or clone this repo)
2. Extract into `World of Warcraft/_classic_era_/Interface/AddOns/`
3. The folder must be named `TotemTommysBars` (drop any version suffix from the ZIP)
4. Launch the game, enable **Totem Tommys Bars** in the AddOns list, log in

## Quick start

- **`/ttb`** — open the options panel
- **Minimap button** — left-click opens options, shift-click hides/shows all bars, right-click + drag repositions
- **Right-click any bar button** — pick a different spell for that slot
- **Shift-click any bar button** — cycle that slot through learned spells
- **Drag the bar headers** (unlock first via Bar appearance → "Lock bar")

## Slash commands

| Command | Effect |
|---|---|
| `/ttb` | Open the options panel |
| `/ttb pos` | Print every bar's current screen coordinates |
| `/ttb savepos` | Save current bar positions as your personal defaults |
| `/ttb clearpos` | Clear personal defaults — revert to factory positions |
| `/ttb reset` | Reset just the totem bar position |
| `/ttb macro` | Create a `TTB Stack` macro you can drag onto an action bar |
| `/ttb lock` | Toggle lock |
| `/ttb scale 0.8` | Set global bar scale |
| `/ttb help` | Print the full command list |

## Keybinds

Key bindings live in Blizzard's native **Esc → Key Bindings → Totem Tommys Bars**. Sub-headers group them:
- Sequence (Drop / Cycle Sequence)
- Element Totems (Drop / Cycle Fire / Water / Earth / Air)
- Totem Stack (Load / Cycle Totem Stack)
- Imbues & Shield (Mainhand / Off Hand / Lightning Shield)
- Utility Slots (Slot 1 / Cycle Slot 1 / Slot 2 / Cycle Slot 2)

The **Main Cycle Modifier** in Options → Bar appearance turns any "Drop" binding into the matching "Cycle" action when held. Pick Shift, Alt, Ctrl, or None.

## License

MIT — see [LICENSE](LICENSE).

## Credits

Built for hardcore Classic Era shamans by the addon's author. Pull requests and issue reports welcome.
