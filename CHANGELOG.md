# Changelog

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
