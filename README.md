# Vital Frame

Easy to see vital character information for Classic and Retail WoW.

Vital Frame is a compact, movable HUD for name, level, XP, reputation, professions, and Classic/Forever skill bars. It is built for Retail, Classic Era, other Classic clients, and WoW Forever.

## Features

- Name, class icon, and level on a small frame
- XP, XP remaining, reputation, and crafting skill bars
- Optional hunter pet XP on Classic clients
- Streamer Mode (shows class name instead of character name)
- Hide the default Blizzard watch bar
- Separate Skills frame on Classic/Forever (professions, secondary skills, weapon skills)
- Edit Mode on Retail; `/vf config` to unlock layout on Classic
- Theme: Auto (silver on Classic/Retail, brown on Forever), or lock Classic / Forever

## Commands

| Command | Action |
| --- | --- |
| `/vitalframe` or `/vf` | Toggle the frame |
| `/vf show` / `/vf hide` | Show or hide |
| `/vf reset` | Reset position and size |
| `/vf config` | Unlock layout on clients without Edit Mode |

On Retail, use **Edit Mode** to move the frames and open options.

## Install

1. Download from CurseForge / WowUp, or clone this repository into `Interface/AddOns/VitalFrame`.
2. Ace3 is optional. If Ace3 is installed, settings use AceDB-3.0. Without it, settings still save in `VitalFrameDB`.
3. Enable **Vital Frame** in the addons list for each client.

## Supported clients

| Client | TOC |
| --- | --- |
| Retail | 120100 |
| WoW Forever | 16001 |
| Classic Era | 11508, 11509 |

## License

MIT. See [LICENSE](LICENSE).
