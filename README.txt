ClickLegend

Shows your click-cast bindings on screen so you never have to remember them.

  - Icon grid with one entry per bound key or button: any mouse button, the
    mouse wheel, or any keyboard key. Only bound keys are shown.
  - Green = ally spell, red = enemy spell
  - Hold Shift / Ctrl / Alt to see that modifier's bindings
  - Unit tooltips list the bindings for the hovered frame: ally spells on a
    friendly frame, enemy spells on an attackable one
  - Horizontal or vertical layout, wrapping, ally/enemy filter and order,
    and four ways to sort the buttons, including a custom order
  - Button labels as text (L, R, M4) or as small mouse icons
  - Optional background with your own color, opacity and padding
  - Show always, only in a group, or only in combat
  - Its own settings window: type /clg

Where the bindings come from (picked automatically)
  1. EllesmereUI HoverCast, when it is switched on
  2. The game's own Click Casting, otherwise

EllesmereUI is optional. Every setting is in the addon's own window (/clg).
With EllesmereUI installed, the legend also uses its font and gets the same
settings as pages in the EllesmereUI options panel (section "ClickLegend").
This is an unofficial companion and is not affiliated with EllesmereUI.

Install
  1. Copy the ClickLegend folder into your Interface/AddOns folder.
  2. Restart the game and enable the addon.
  3. Drag the legend into place, then type /clg lock. Type /clg for settings.

Commands
  /clg                          open or close the settings window
  /clg help                     list commands
  /clg config                   settings in EllesmereUI (or the window without it)
  /clg visible always | group | combat
  /clg lock | unlock            lock in place, or unlock to drag
  /clg show | hide              toggle the legend
  /clg layout horizontal | vertical
  /clg rows both | ally | enemy
  /clg flip                     enemy spells first, or ally spells first
  /clg sort mouse | keyboard | alpha | custom
  /clg order <keys>             custom order, e.g. /clg order M4 M5 L R
  /clg reverse                  reverse the order
  /clg wrap <2-24>              buttons per line
  /clg size <16-64>             icon size
  /clg scale <0.5-2>            overall scale
  /clg alpha <0.1-1>            opacity
  /clg labels | bars | tooltip  toggle labels, color bars, tooltip lines
  /clg labelstyle text | icon   text labels, or mouse icons for mouse buttons
  /clg labelsize <7-14>         label size
  /clg bg                       toggle the background
  /clg bgcolor <RRGGBB>         background color, e.g. /clg bgcolor 101418
  /clg bgalpha <0-1>            background opacity
  /clg pad <0-20>               background padding
  /clg list                     print every binding to chat
  /clg reset                    default position and settings

Read-only: it never changes bindings and uses no secure frames.
