# Changelog

## 2.0.0
- ClickLegend can now do the click casting itself. It is off until you switch it on (Bindings tab, or `/clg cast on`); with it off, nothing changes from 1.6.0 and no unit frame is touched.
- Rules instead of one spell per key. Each key has a short list of rules and the first one that fits is cast: for example dead ally, then ally, then enemy, all on Shift + Left Click. No macros to write.
- Conditions: ally or enemy, alive or dead, in or out of combat, your stance or form, with or without a pet, an extra modifier. A rule whose spell you do not know is skipped, so the next rule takes over.
- Binds mouse buttons, the mouse wheel and keyboard keys, with any modifiers. Keys and the wheel act only while the cursor is on a unit frame.
- What a rule can do: a spell (the highest rank you know, or one exact rank), an item, a trinket, one of your macros, target, focus, assist, or the unit menu.
- Binding sets are shared by all your characters: make one, copy it, pick which one a character uses.
- Starter sets for every class (healer and damage or tank versions for priest, paladin, druid and shaman). The most used spells are on the plain clicks, then Shift, Ctrl and Alt. They list the better spell first and the one it replaces after it, so the same set works at any level and with any talents.
- Guided setup: pick which buttons you want (left, right, middle, wheel up and down, any extra mouse buttons, which you add by clicking them, and keyboard keys, which you add by pressing them), each plain or with Shift, Ctrl or Alt. It then asks, for those only, what each should do on an ally, a dead ally and an enemy.
- Export a binding set as text and import one someone sent you.
- New Bindings tab in the settings window: pick spells, macros and items from searchable lists, press the key you want to bind. The EllesmereUI panel gets a Bindings page too.
- The legend follows the rules: it shows what each key would do right now, such as the resurrection while the cursor is on a dead ally.
- A minimap button (click: settings, right click: guided setup; it can be hidden) and a welcome window the first time, offering the guided setup or the settings.
- Works on the game's own unit frames and on frames other addons offer for click casting: EllesmereUI's when its HoverCast is off, ElvUI's, Grid2's, and VuhDo's when its Clique Support option is ticked.
- Fixed: spells bound in current versions of HealBot were missing from the legend.
- Warns when EllesmereUI HoverCast, Clique or the game's own Click Casting is binding the same frames or the same key. It never changes their bindings.
- Nothing is changed on a frame during combat; changes made in combat apply when it ends.

## 1.6.0
- Reads bindings from Clique, VuhDo and HealBot, as well as EllesmereUI HoverCast and the game's own click casting.
- New "Bindings from" setting: Automatic (the first source that has bindings) or one source of your choice. Also `/clg source`.
- VuhDo and HealBot hostile-target assignments show on the enemy row; Clique's friend and enemy binding sets are respected.
- Hover-aware rows: with the cursor on a friendly unit the enemy spells dim, and the other way round.
- Modifier layers: show only the held modifier's bindings (as before) or every layer at once, stacked.
- Bindings that cannot fire (spell not learned, macro deleted) are greyed out and marked in tooltips and `/clg list`.
- New visibility choice: only while hovering a unit frame.
- Attach the legend to the party frames (above, below, left or right, with a gap). It falls back to the dragged position when no party frames are on screen.
- Icon label style now draws keyboard keys as keycaps.
- While unlocked, hovering a legend icon shows the spell and its key.
- Custom ally and enemy colors.
- Optional separate settings per character.
- Layout presets: Default, Compact, Sidebar and Everything.
- Export your settings as text and import someone else's (`/clg export`, `/clg import`).
- Settings are now split into Display, Look, Order and Share pages.

## 1.5.1
- The unlocked marker is now a thin green outline instead of a green fill, so the background color, opacity and on/off setting show correctly while the legend is unlocked.

## 1.5.0
- New label style: Icons. Mouse buttons get a small mouse glyph with the bound button lit (left, right, middle, wheel up, wheel down, side buttons) in place of the text label. Keyboard keys keep their text.

## 1.4.1
- Fixed tooltip lines not switching to the modifier layer when Shift, Ctrl or Alt is pressed while already hovering a party or raid frame.

## 1.4.0
- The addon has its own settings window (`/clg`), so every option works without EllesmereUI. It is also listed in the game's AddOns options.
- Background: on or off, your own color and opacity, and padding.
- Visibility: always, only in a group, or only in combat.
- Label size, and a toggle for the ally / enemy color bars.

## 1.3.0
- Any bound key shows up: extra mouse buttons, the mouse wheel and keyboard keys, each with a short label.
- New layout options: horizontal or vertical, buttons per line (wrapping), ally only / enemy only, enemy first.
- New sort options: mouse buttons first, keyboard keys first, alphabetical, or a custom order (settings page or `/clg order`).
- Settings are split into Display and Order pages in the EllesmereUI panel.
- Removed the title text shown above the legend while it is unlocked.
- Hardening: saved settings are validated on load, modifier order is normalised, and errors in one refresh can no longer repeat every second or break a tooltip.

## 1.2.0
- Supports the game's own Click Casting, used automatically when EllesmereUI HoverCast is off or EllesmereUI is not installed.
- EllesmereUI is now optional.

## 1.1.0
- Settings page inside the EllesmereUI options panel.
- Unit tooltips list the bindings for the hovered frame (ally or enemy).

## 1.0.0
- Icon legend for EllesmereUI HoverCast bindings with ally and enemy rows and modifier layers.
