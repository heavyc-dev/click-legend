ClickLegend

Better click casting, on the default raid frames or any unit frames that
support click casting, and a legend that shows your bindings on screen so
you never have to remember them.

The legend

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
  - Show always, only in a group, only in combat, or only while hovering a
    unit frame
  - The row that does not apply to the unit under your cursor dims
  - Every modifier layer at once, if you prefer that to holding the key
  - Bindings that cannot fire (unlearned spell, deleted macro) are greyed out
  - Can attach to your party frames and follow them
  - Custom ally and enemy colors; shared or per-character settings
  - Layout presets, and settings you can export and import as text
  - Its own settings window: type /clg, or click the minimap button

Click casting of its own (optional, off until you switch it on)
  ClickLegend can also do the click casting. Open /clg, Bindings tab:
  - Make a set, press "Add a key", then press the key or mouse button to
    bind, holding Shift, Ctrl or Alt if you want them. Mouse buttons, the
    mouse wheel and keyboard keys all work; keys and the wheel act only
    while the cursor is on a unit frame.
  - Each key has rules, tried from the top; the first that fits is cast.
    Example on one key: dead ally = resurrection, ally = heal, enemy = damage.
  - Conditions: ally or enemy, alive or dead, in or out of combat, your
    stance or form, with or without a pet, an extra modifier.
  - A rule can cast a spell (your highest rank, or one exact rank), use an
    item or trinket, run one of your macros, target, focus, assist, or open
    the unit menu. Spells, macros and items are picked from lists.
  - A rule whose spell you do not know is skipped, so the next one takes over.
  - Sets are shared by all your characters. Each character picks its set.
  - Guided setup: switch on the buttons you want to set up (left, right,
    middle, wheel up and down, your extra mouse buttons: click them to add
    them, and keyboard keys: press them to add them), each plain or with
    Shift, Ctrl or Alt. It then asks, for those only, what each does on an
    ally, a dead ally and an enemy.
  - New... offers a starter set for each class to begin from. The most used
    spells are on the plain clicks, then Shift, Ctrl and Alt. Where a plain
    click has an ally spell, it still targets or opens the menu on everyone
    else, and Alt + Left and Alt + Right are Target and Menu.
  - More... renames or copies a set, exports it as text to share, and
    imports one. Hover a key in the list to read all of its rules.
  - The legend shows what each key would do right now.
  - Works on the game's unit frames (party, raid, player, target, focus,
    pet, boss) and on frames other addons offer for click casting the
    standard way: EllesmereUI, ElvUI and Grid2 among them. VuhDo does once
    you tick "Clique Support" in VuhDo's options (General, Misc) and
    reload. HealBot always does its own click casting on its own frames.
    Run only one click-cast addon on the same frames:
    ClickLegend warns when EllesmereUI HoverCast, Clique or the game's own
    Click Casting is binding them too, and never changes theirs.
  - The starter sets use English spell names. On another language client
    use the guided setup or the editor, which list your own spells.
  - Conditions it cannot offer, because the game hides them from addons in
    combat: health below a percentage, buffs or debuffs, dispellable
    effects, role, range.

Where the bindings come from
  ClickLegend reads the first of these that has bindings, in this order:
    0. Its own bindings, when you have switched them on
    1. EllesmereUI HoverCast (when it is switched on)
    2. Clique
    3. VuhDo
    4. HealBot
    5. The game's own Click Casting
  To use a particular one, pick it under "Bindings from" in the settings
  or type /clg source clique (or own, vuhdo, healbot, eui, blizzard, auto).

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
  /clg setup                    guided setup of its own click casting
  /clg welcome                  show the welcome window again
  /clg minimap                  show or hide the minimap button
  /clg help                     list commands
  /clg config                   settings in EllesmereUI (or the window without it)
  /clg source auto | own | eui | clique | vuhdo | healbot | blizzard
  /clg cast                     its own click casting: status and what each key does
  /clg cast on | off            switch its own click casting on or off
  /clg cast sets                list your binding sets
  /clg cast set <name>          use that set on this character
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

Until you switch its own click casting on, ClickLegend only reads and draws:
it changes no bindings and touches no unit frame. It never changes another
addon's bindings or the game's.
