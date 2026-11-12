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
  - The row that does not apply to the unit under your cursor dims
  - Every modifier layer at once, if you prefer that to holding the key
  - Bindings that cannot fire (unlearned spell, deleted macro) are greyed out
  - Can attach to your party frames and follow them
  - Custom ally and enemy colors; shared or per-character settings
  - Layout presets, and settings you can export and import as text
  - Its own settings window: type /clg

Where the bindings come from
  ClickLegend reads the first of these that has bindings, in this order:
    1. EllesmereUI HoverCast (when it is switched on)
    2. Clique
    3. VuhDo
    4. HealBot
    5. The game's own Click Casting
  To use a particular one, pick it under "Bindings from" in the settings
  or type /clg source clique (or vuhdo, healbot, eui, blizzard, auto).

None of these addons is required. Every setting is in the addon's own
window (/clg). With EllesmereUI installed, the legend also uses its font and
gets the same settings as pages in the EllesmereUI options panel (section
"ClickLegend"). ClickLegend is an independent addon and is not affiliated
with any of them.

Install
  1. Copy the ClickLegend folder into your Interface/AddOns folder.
  2. Restart the game and enable the addon.
  3. Drag the legend into place, then type /clg lock. Type /clg for settings.

Commands
  /clg                          open or close the settings window
  /clg help                     list commands
  /clg config                   settings in EllesmereUI (or the window without it)
  /clg source auto | eui | clique | vuhdo | healbot | blizzard
  /clg visible always | group | combat | hover
  /clg layers held | all        modifier layers shown
  /clg anchor screen | party    drag it freely, or attach to the party frames
  /clg side above | below | left | right
  /clg gap <0-60>               gap to the party frames
  /clg hoverdim                 toggle dimming of the row that does not apply
  /clg missing                  toggle greying of bindings that cannot fire
  /clg allycolor <RRGGBB>       ally color (also /clg enemycolor)
  /clg profile                  separate settings for this character, or shared
  /clg preset default | compact | sidebar | full
  /clg export                   your settings as text, ready to copy
  /clg import <text>            use a settings text someone sent you
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
