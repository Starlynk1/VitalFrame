# Vital Frame

## Unreleased

- Fonts registered with LibSharedMedia-3.0 appear in every font picker, under a SharedMedia heading.
- Pick a Bar Texture for the main frame and for the Skills frame. Any LibSharedMedia status bar texture can be used.
- Fonts and textures that other addons register after Vital Frame loads become available without a reload.

## [v1.1.4-beta](https://github.com/Starlynk1/VitalFrame/tree/v1.1.4-beta) (2026-11-11)
[Full Changelog](https://github.com/Starlynk1/VitalFrame/commits/v1.1.4-beta) [Previous Releases](https://github.com/Starlynk1/VitalFrame/releases)

- Vertical Layout is a second options tab on the right side of the options panel. Horizontal Layout stays the first tab.
- In Vertical Layout the bars stay horizontal. Each bar can sit on the left or the right of the name, and bars on the same side stack.
- That layout can be as wide as the screen and as short as 40. Its width and height are saved separately from the horizontal frame.
- Name size and level size are separate there, from 8 to 72.
- The level can sit below the name, or to the left or right of it.
- The name can stay two lines, with the smaller surname, or be one line at the name size.
- Horizontal and vertical each remember their own screen position. Switching tabs moves the frame to that spot.

## [v1.1.3](https://github.com/Starlynk1/VitalFrame/tree/v1.1.3) (2026-11-04)
[Full Changelog](https://github.com/Starlynk1/VitalFrame/commits/v1.1.3) [Previous Releases](https://github.com/Starlynk1/VitalFrame/releases)

- Scale the main frame and the Skills frame separately, from 50% to 200%.
- Frame Opacity fades the whole frame. Background Opacity fades only the fill, and 100% is solid.
- Options keep the checkboxes on the left, and frame size, scale, fonts, and opacity on the right.
- The pet bar stays full and shows only the pet level while the pet matches your level. That is the same for every pet class.
- Feral Combat, Poisons, and Lockpicking show on the skills frame with their real skill rank.
- Closing Edit Mode on Forever no longer reports an addon error.

## [v1.1.2](https://github.com/Starlynk1/VitalFrame/tree/v1.1.2) (2026-10-10)
[Full Changelog](https://github.com/Starlynk1/VitalFrame/commits/v1.1.2) [Previous Releases](https://github.com/Starlynk1/VitalFrame/releases)

- The pet bar shows current XP / XP needed and the pet level. When that level is full, or the pet is max level, only the level remains and the bar stays full.
- Skill names in each section are alphabetical.
- The XP Remaining bar is removed.
- Frame positions stay put when the addon is disabled and enabled again. New characters use the account position. A character can keep its own position. Reset to Defaults clears the placement in use.
- The skills frame can sit flush with the bottom of the screen. Grow Down is available when there is room below, and Grow Up when there is room above. Against the top it grows down. Against the bottom it grows up.

## [v1.1.1](https://github.com/Starlynk1/VitalFrame/tree/v1.1.1) (2026-09-26)
[Full Changelog](https://github.com/Starlynk1/VitalFrame/commits/v1.1.1) [Previous Releases](https://github.com/Starlynk1/VitalFrame/releases)

- Classic Era no longer errors while the skills frame updates.
- The class icon shows on Classic Era, with rounded corners and a small border.

## [v1.1.0](https://github.com/Starlynk1/VitalFrame/tree/v1.1.0) (2026-09-25)
[Full Changelog](https://github.com/Starlynk1/VitalFrame/commits/v1.1.0) [Previous Releases](https://github.com/Starlynk1/VitalFrame/releases)

- Choose a font for the name, level, and bar text, and for skill bars.
- Set a maximum size for the name and for bar text. The text still shrinks when the frame or bars get smaller.
- Set the last name as a percentage of the first name size.
- Fade each frame's border and background separately from the text and bars inside it.
- List weapon skills above professions, and choose primary and secondary skills on their own.
- Raise the minimum Vital Frame height so the name and level have room.
- Show the Forever surname as the last name.

## [v1.0.1](https://github.com/Starlynk1/VitalFrame/tree/v1.0.1) (2026-09-19)
[Full Changelog](https://github.com/Starlynk1/VitalFrame/commits/v1.0.1) [Previous Releases](https://github.com/Starlynk1/VitalFrame/releases)

- Rebuild SavedVariables on upgrade so Forever keeps options as 1/0 flags.
- Keep named-frame positions through reload.

## [v1.0.0](https://github.com/Starlynk1/VitalFrame/tree/v1.0.0) (2026-09-19)
[Full Changelog](https://github.com/Starlynk1/VitalFrame/commits/v1.0.0) [Previous Releases](https://github.com/Starlynk1/VitalFrame/releases)

- Add CurseForge project ID and GitHub release packager.
- Merge GitHub README with addon source.
- Publish Vital Frame 1.0.0 for GitHub and CurseForge.
- Initial commit
