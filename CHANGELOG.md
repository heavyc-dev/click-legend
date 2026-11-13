# Changelog

## 2.1.3
New:
- A key that works anywhere can go on to your target: Edit the key, "Under the cursor, else my target". With nothing fitting under the cursor the same spells are cast on your target, so the key is no longer dead away from a unit. The guided setup's "Keyboard keys work on any unit under the cursor" now sets this too. It needs a key whose rules are all spells or items, and room in the key's 255 characters; the editor says when it cannot be done.
- Copy your bindings from another click-cast addon: New... (and the first page of the guided setup) offers "Copy from" for whatever ClickLegend can read right now: Clique, VuhDo, HealBot, EllesmereUI HoverCast, the game's own Click Casting. A spell for allies and another for enemies on one key become two rules. An addon's own actions and anything that is not a spell, a macro, Target or Menu are left out, and you are told how many. Switch the other click casting off before you turn ClickLegend's on.

Fixed:
- After "Use it and turn on", the last page of the guided setup now says what changed: which spell plain left and right click cast on an ally, and which keys target and open the menu instead (Alt + Left and Alt + Right in the starter sets). It also names game key bindings that keys working anywhere have taken over, as the options page now does before you switch that on.
- The button on that page reads "Turn click casting off" when it is on. It used to read "Click casting is on" and switched it off when clicked.
- While ClickLegend waits for a key ("Add a key", "Change the key"), a plain left click on that same button stops it. It used to bind plain left click.
- Keyboard and wheel keys could stop working on the frame under the cursor when some other unit frame hid (a target's target, a pet, a raid member leaving).
- Mouse buttons past the fifth were written to unit frames as clicks, which a frame never receives, so they did nothing. They are bound like keyboard keys now.
- A unit frame made during combat by ElvUI or Grid2 lost every key that also opens the unit menu, which in the starter sets is right click with its heal. Such a key now casts at once and gets its menu when combat ends.
- A key with many rules that also opens the menu or casts an exact rank could be counted as fitting in 255 characters and then run past them. The helper names are short now.
- A set imported from text could carry a spell name with a line break or bracket in it, which put extra macro lines on the key behind a plain spell name. Such a rule is refused.
- The legend re-read every binding each time any raid member's pet changed.
- The legend no longer puts an empty box on screen when nothing is bound anywhere (it shows while the settings window is open, so that it can still be placed), and the "drag the legend" line in chat is said once, not at every login.
- The editor now says when a rule can never fire because a rule above it fits every time it would (an "ally" rule above an "ally, in combat" rule, say).
- Long names no longer run over what stands beside them in the Bindings tab: a set's name, a key's name, the keys in Quickbind. A spell you do not know is marked in front of its name, where it cannot be cut off. The character count is shorter and no longer sits under "Before cast". The welcome and what's-new windows are taller, so their text clears the buttons.

Changed:
- With Clique loaded, ClickLegend's click casting stays off and says why, instead of only warning: both wrote to the same frames, and each ended up with some of them. Switch Clique off in the AddOns list and reload to use ClickLegend's; New... copies your Clique bindings first. The legend still shows your Clique bindings as before.
- The settings window has the Bindings tab first, and opens on it unless the legend is showing another addon's bindings and ClickLegend's click casting is off. The welcome window explains click casting first.
- In the settings window a choice (Layout, Label style, Bindings from, and the rest) now opens a list to pick from. It used to step to the next value on each click.
- Starter sets (for new sets only; a set you already made is not touched): the druid sets no longer put Rebirth on the main heal key, where clicking on through a death would spend it on whoever died under the cursor. It is on Ctrl + Right Click, and plain left click on a dead ally resurrects out of combat only. The mage set leaves plain left and right click alone, so a click on a party member still targets them; Remove Lesser Curse is on the middle button and Arcane Intellect on Shift + Left Click.

Changed for people who already use ClickLegend:
- Once, at your first login with this version: text labels become the small mouse picture (the default since 2.1.2), and a legend that was the large mouse picture goes back to rows. Text labels: Display, Label style. The large picture: Display, Layout. A choice you make after that stays.
- The "Default" preset uses the small mouse labels too.

## 2.1.2
- The small mouse above each spell (label style "Icons") is now a picture of your mouse with the bound button lit, in place of the drawn one. Pick which mouse on the first page of the guided setup, or on the Display tab.
- A new install starts as rows of spell icons with that small mouse above each. The large "Mouse picture" layout, which 2.1.1 started new installs with, is an option again: Display, Layout, or the options page of the guided setup. If you installed 2.1.1 fresh and want the rows, that is where to switch.
- The guided setup's options page can also switch off the bindings in unit tooltips (as the Display tab and `/clg tooltip` already could).

## 2.1.1
- If you already had ClickLegend set up, a window now tells you once what 2.1 added and offers to go through the guided setup again. It starts from the keys you have and changes only what you change. `/clg news` shows it again.
- A new install now starts with the legend as a picture of a mouse (the rounded one) instead of rows of icons. If you already use ClickLegend your layout stays as it is: Display, Layout changes it, and the guided setup asks on its first page.

## 2.1.0
- Keys that work anywhere. A key can be set to work on any unit under the cursor (characters in the world, nameplates), not only on unit frames: edit the key and pick "Any unit under the cursor". ClickLegend then has that key all the time while its click casting is on, and warns when the game uses the key for something else. Plain left and right click stay on unit frames.
- Quickbind: a list of your spells in the Bindings tab. Point at a spell and press a key or a mouse button, with Shift, Ctrl or Alt if you like, and the spell is on that key. Helpful spells go on allies, harmful ones on enemies, resurrections on dead allies.
- A set for each spec: More..., "Use this set for this spec only". Other specs keep the character's set.
- Two ready-made actions that work on any class: Dispel (the dispel you know) and Resurrect (your resurrection on a dead ally; the combat one while in combat). They are in the editor, the guided setup and Quickbind.
- Macro text in a rule: write the macro in the editor instead of saving one in the game's macro window. It uses no macro slot.
- Before cast: a key can stop your current cast or use a trinket just before one of its spells is cast.
- "On press": mouse clicks on unit frames can cast as the button goes down.
- The legend shows when a spell cannot be cast: a cooldown sweeps over its icon, not enough mana turns it blue, out of range of the unit under the cursor turns it red. `/clg usable` or the Display tab switches it off.
- The legend can stay beside the cursor (Display, Attach to), so it is where you are about to click.
- New "Minimal" preset: beside the cursor, only while it is on a unit frame, and only what works on that unit.
- Spells that do not apply to the unit under the cursor can be hidden instead of dimmed.
- New layout, "Mouse picture": a mouse seen from above with each button's spells beside it and a line to the button. Keyboard keys are listed under it. Four mice to pick from (rounded, angular, simple, and one with twelve side buttons), and its size is yours to set.
- The guided setup asks on its first page what the legend should draw: rows of icons, or one of the mice. With the twelve-button mouse it then asks you to press each side button, so that every spell is drawn beside the right one whatever keys your mouse sends.
- New label style: the key written on the corner of the spell icon. A spell bound to one exact rank shows the rank.
- An icon flashes when its spell is cast, and the legend fades in instead of popping up.
- Easier to set up. Guided setup: pick the set for your class and press "Use it and turn on": two clicks. The long way now shows every key on one page, with what it does on an ally, a dead ally and an enemy side by side, instead of one page per key, and ends with the usual options.
- Easier to change. The Bindings tab is wider and has two halves: your keys on the left (with icons for what each casts on an ally and an enemy), the rules of the key you click on the right. A rule shows only the conditions it uses, with "+ condition" to add one. Undo takes back the last change. After you press a new key, the list of spells opens by itself. A line across the top says so when click casting is off, with a button to turn it on.
- Quickbind has a search box, a switch for lower ranks, and an x to take a spell off its keys.
- Click an icon on the unlocked legend to open that key in the editor.
- Group frames made in the middle of a fight by frame addons that follow the click-cast header convention (ElvUI, Grid2 and others) are bound at once, not when combat ends. Keyboard keys and the unit menu on such a frame still start after combat, and so do the game's own raid frames.

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
