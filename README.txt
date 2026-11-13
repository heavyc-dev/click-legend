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
  - "Mouse picture" layout: a mouse with each button's spells beside it.
    Four mice to pick from, one with twelve side buttons; the guided setup
    asks you to press those, so it learns what your mouse sends
  - Horizontal or vertical layout, wrapping, ally/enemy filter and order,
    and four ways to sort the buttons, including a custom order
  - Button labels as text (L, R, M4), as small mouse icons, or written on
    the corner of the spell icon
  - Optional background with your own color, opacity and padding
  - Show always, only in a group, only in combat, or only while hovering a
    unit frame
  - The row that does not apply to the unit under your cursor dims, or
    goes away if you prefer
  - A cooldown sweeps over its icon; no mana turns it blue, out of range red
  - An icon flashes when its spell is cast; a spell bound to one exact rank
    shows the rank
  - Every modifier layer at once, if you prefer that to holding the key
  - Bindings that cannot fire (unlearned spell, deleted macro) are greyed out
  - Can attach to your party frames and follow them, or stay beside the
    cursor
  - "Minimal" preset: beside the cursor, only while it is on a unit frame,
    only what works on that unit
  - Custom ally and enemy colors; shared or per-character settings
  - Layout presets, and settings you can export and import as text
  - Its own settings window: type /clg, or click the minimap button

Click casting of its own (optional, off until you switch it on)
  ClickLegend can also do the click casting. Open /clg, Bindings tab.
  The quick way: press Guided setup, pick the ready-made set for your
  class, press "Use it and turn on". Two clicks. Everything below is for
  changing it afterwards.
  - The tab has two halves: your keys on the left, and on the right the
    rules of the key you click. The two icons beside a key are what it
    casts on an ally and on an enemy.
  - Undo takes back the last change. Clicking an icon on the unlocked
    legend opens that key.
  - Make a set, press "Add a key", then press the key or mouse button to
    bind, holding Shift, Ctrl or Alt if you want them. Mouse buttons, the
    mouse wheel and keyboard keys all work; keys and the wheel act only
    while the cursor is on a unit frame, unless you set the key to work
    anywhere (below).
  - Quickbind: lists your spells. Point at one and press a key or a mouse
    button, with Shift, Ctrl or Alt if you like, and the spell is on that
    key: on allies, on enemies or on dead allies, whichever the spell is for.
  - A key can work on any unit under the cursor, not only on unit frames:
    characters in the world and nameplates too. Edit the key and pick
    "Any unit under the cursor". ClickLegend then has that key all the
    time while its click casting is on, so use one you need for nothing
    else. Plain left and right click cannot be set this way.
  - Each key has rules, tried from the top; the first that fits is cast.
    Example on one key: dead ally = resurrection, ally = heal, enemy = damage.
  - Conditions: ally or enemy, alive or dead, in or out of combat, your
    stance or form, with or without a pet, an extra modifier.
  - A rule can cast a spell (your highest rank, or one exact rank), use an
    item or trinket, run one of your macros, target, focus, assist, or open
    the unit menu. Spells, macros and items are picked from lists.
  - A rule can also be macro text you write in the editor (Macro text): it
    uses no macro slot. It runs as written, after the key's other rules.
  - Before cast: a key can stop your current cast, or use a trinket, just
    before one of its spells is cast.
  - Two ready-made actions work on any class: Dispel casts the dispel you
    know, and Resurrect casts your resurrection on a dead ally (the combat
    one while you are in combat). Put Resurrect first on any key and that
    key also brings back the dead.
  - A rule whose spell you do not know is skipped, so the next one takes over.
  - Sets are shared by all your characters. Each character picks its set,
    and a spec can have a set of its own (More..., Use this set for this
    spec only).
  - Guided setup, the long way: switch on the buttons you want to set up
    (left, right, middle, wheel up and down, your extra mouse buttons:
    click them to add them, and keyboard keys: press them to add them),
    each plain or with Shift, Ctrl or Alt. One page then lists those keys
    with what each does on an ally, a dead ally and an enemy; click a box
    to pick. A last page has the usual options.
  - New... offers a starter set for each class to begin from. The most used
    spells are on the plain clicks, then Shift, Ctrl and Alt. Where a plain
    click has an ally spell, it still targets or opens the menu on everyone
    else, and Alt + Left and Alt + Right are Target and Menu.
  - More... renames or copies a set, exports it as text to share, and
    imports one. Hover a key in the list to read all of its rules.
  - "On press": mouse clicks on unit frames cast as the button goes down
    instead of when it is let go.
  - The legend shows what each key would do right now, and dims a spell
    that is on cooldown, that you lack the mana for, or that cannot reach
    the unit under the cursor.
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
  /clg anchor screen | party | cursor
                                drag it freely, attach it to the party frames,
                                or keep it beside the cursor
  /clg side above | below | left | right
  /clg gap <0-60>               gap to the party frames or the cursor
  /clg off dim | hide           spells that do not apply to the hovered unit
  /clg flash                    toggle the flash when a shown spell is cast
  /clg hoverdim                 toggle dimming of the row that does not apply
  /clg missing                  toggle greying of bindings that cannot fire
  /clg usable                   toggle marking spells you cannot cast now
  /clg allycolor <RRGGBB>       ally color (also /clg enemycolor)
  /clg profile                  separate settings for this character, or shared
  /clg preset default | compact | sidebar | full | minimal
  /clg layout horizontal | vertical | mouse
  /clg mouse <96-256>           size of the mouse picture
  /clg mousepic a | b | c | d   which mouse: rounded, angular, simple,
                                twelve side buttons
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
