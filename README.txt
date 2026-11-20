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
  - "Mouse picture" layout, if you prefer it to rows: one large mouse with
    each button's spells beside it
  - One of the mice has twelve side buttons; the guided setup asks you to
    press those, so it learns what your mouse sends
  - Horizontal or vertical layout, wrapping, ally/enemy filter and order,
    and four ways to sort the buttons, including a custom order
  - Button labels as a small picture of your mouse with the bound button
    lit (four mice to pick from), as text (L, R, M4), or written on the
    corner of the spell icon
  - Optional background with your own color, opacity and padding
  - Show always, only in a group, only in combat, or only while hovering a
    unit frame
  - The row that does not apply to the unit under your cursor dims, or
    goes away if you prefer
  - A cooldown sweeps over its icon; no mana turns it blue, out of range orange
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
  Press Guided setup, pick the ready-made set for your class and press
  Next: the steps ask which buttons you use, what each should do, and
  whether your keys should also cast on units in the world (hover
  casting). The last step switches click casting on. In a hurry: "Skip
  the setup: use it and turn on" takes the set as it is.
  Quickest of all: the welcome window's "Class Spec Quickstart" picks
  the starter set for your class and spec (change it in the list), and
  one click on "Okay, set it up" switches click casting on with
  mouseover casting, enemy spells that also target, and the default
  legend (a column, small mouse pictures, a thin border on dark grey).
  Everything below is for changing it afterwards.
  - The tab has two halves: your keys on the left, and on the right the
    rules of the key you click. The two icons beside a key are what it
    casts on an ally and on an enemy.
  - Undo takes back the last change, up to eight of them. Clicking an
    icon on the unlocked legend opens that key.
  - Make a set, press "Add a key", then press the key or mouse button to
    bind, holding Shift, Ctrl or Alt if you want them. Mouse buttons, the
    mouse wheel and keyboard keys all work; keys and the wheel act only
    while the cursor is on a unit frame, unless you set the key to work
    anywhere (below).
  - Quickbind: lists your spells. Point at one and press a key or a mouse
    button, with Shift, Ctrl or Alt if you like, and the spell is on that
    key: on allies, on enemies or on dead allies, whichever the spell is for.
  - Mouseover (hover) casting: a key can work on units in the world too,
    not only on unit frames: characters and nameplates under the cursor.
    The row "Mouseover casting" at the top of the Bindings tab sets every
    keyboard key, the wheel and the extra mouse buttons at once: Off, On,
    or On and else my target. One key at a time: click the key, then
    "Works on". ClickLegend then has that key all the time while its click
    casting is on, so use one you need for nothing else.
  - "Else my target": with nothing fitting under the cursor the same
    spells are cast on your target, so the key is never dead.
  - Plain left and right click can be mouseover keys too, one key at a
    time. They are taken only while the cursor is on a friendly player's
    character in the world, so that you can heal or buff someone by
    clicking them; everywhere else they turn the camera, select, loot and
    talk as always. In combat the game cannot tell a player from a
    friendly NPC, so a friendly NPC takes the click as well then.
  - "Enemy spells also target" (a check box above the keys, on unless
    you switch it off): a spell cast on the enemy under the cursor also
    makes it your target, on every key. With
    it on, a plain left or right click that works in the world casts on
    living enemies as well: one click targets and casts. Casting on an
    ally never changes your target.
  - Each key has rules, tried from the top; the first that fits is cast.
    Example on one key: dead ally = resurrection, ally = heal, enemy = damage.
  - Conditions: ally or enemy, alive or dead, in or out of combat, your
    stance or form, with or without a pet, an extra modifier.
  - A rule can cast on someone other than the unit under the cursor:
    yourself, your target, your focus, your target's target or your pet
    ("+ condition", "Cast on someone else").
  - "Add a rule" asks what the key should also do (heal an ally, damage an
    enemy, resurrect, else cast on myself...) and puts the rule where it
    can fire. A line above the rules reads the key back in plain words.
    A rule that can never fire comes with a Fix button.
  - Drag a spell from your spellbook onto a key, or onto an icon of the
    unlocked legend, to put it there.
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
  - Guided setup, mouseover casting: off (unit frames only), on (also
    units in the world), or on and else your target. It covers keyboard
    keys, the wheel and extra mouse buttons (the fourth and up); left,
    right and middle click are set one key at a time in the editor. The
    step comes after your keys, and only when you have a key it is about.
  - A wheel key that also works on units in the world is ClickLegend's
    only while a unit is there. The rest of the time the wheel zooms the
    camera as usual. Not with "else my target": there it casts.
  - Guided setup, your buttons: switch on the buttons you want to set up
    (left, right, middle, wheel up and down, your extra mouse buttons:
    click them to add them, and keyboard keys: press them to add them),
    each plain or with Shift, Ctrl or Alt. One page then lists those keys
    with what each does on an ally, a dead ally and an enemy, and what it
    casts on you when none of those fits; click a box to pick. A button
    you switch off is taken out of the set.
  - New... also offers "Copy from" for each click-cast addon ClickLegend
    can read right now (Clique, VuhDo, HealBot, EllesmereUI HoverCast, the
    game's own Click Casting): its bindings become a set of your own. An
    addon's own actions are left out. From Clique, hovercast bindings
    become hover casting keys, out-of-combat ones keep that condition, and
    macro text comes along. Switch the other click casting off before you
    turn ClickLegend's on.
  - New... offers a starter set for each class to begin from. The most used
    spells are on the plain clicks, then Shift, Ctrl and Alt. Where a plain
    click has an ally spell, it still targets or opens the menu on everyone
    else, and Alt + Left and Alt + Right are Target and Menu. In combat,
    plain left click on an enemy casts your main damage spell and targets
    the enemy (casters: right click a second one); out of combat it only
    targets, so nothing is pulled by a click. Melee and hunters keep right
    click on an enemy as the attack.
  - More... renames or copies a set, exports it as text to share, imports
    one, and sorts the keys. Hover a key in the list to read all of its
    rules. It also holds which unit frames click casting works on, and
    "Cast on press": mouse clicks on unit frames cast as the button goes
    down instead of when it is let go.
  - Picking another set changes it for every spec; the line that says so
    has a button to keep it to the spec you are in.
  - Quickbind: the > on a spell's row puts another spell in its place on
    every key it is on; the x takes it off them.
  - The legend shows what each key would do right now, and dims a spell
    that is on cooldown, that you lack the mana for, or that cannot reach
    the unit under the cursor.
  - Works on the game's unit frames (party, raid, player, target, focus,
    pet, boss) and on frames other addons offer for click casting the
    standard way: EllesmereUI, ElvUI and Grid2 among them. VuhDo does once
    you tick "Clique Support" in VuhDo's options (General, Misc) and
    reload. HealBot always does its own click casting on its own frames.
    Run only one click-cast addon on the same frames. With Clique loaded,
    ClickLegend's click casting stays off (switch Clique off in the AddOns
    list and reload). It warns when EllesmereUI HoverCast or the game's own
    Click Casting is binding the same frames, and never changes theirs.
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
  /clg news                     show what is new again
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
  /clg basics                   hide or show the plain left click "Target"
                                and right click "Menu" (they keep working)
  /clg npc                      hide the legend while the cursor is on a
                                friendly NPC in the world, or not
  /clg unlearned                hide or show bindings whose spell you have
                                not learned yet
  /clg hoverdim                 toggle dimming of the row that does not apply
  /clg missing                  toggle greying of bindings that cannot fire
  /clg usable                   toggle marking spells you cannot cast now
  /clg allycolor <RRGGBB>       ally color (also /clg enemycolor)
  /clg rangecolor <RRGGBB>      tint of a spell out of range (also
                                /clg manacolor, /clg cooldowncolor)
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
  /clg tint                     toggle button frames colored ally / enemy
                                (with the action button icon frame)
  /clg labelstyle text | icon   text labels, or mouse icons for mouse buttons
  /clg labelsize <7-14>         label size
  /clg bg                       toggle the background
  /clg border none | tooltip | dialog
                                the game's own frame around the legend
  /clg iconstyle button | flat  the action bar's frame around each icon,
                                or a thin black edge
  /clg bgcolor <RRGGBB>         background color, e.g. /clg bgcolor 101418
  /clg bgalpha <0-1>            background opacity
  /clg pad <0-20>               background padding
  /clg list                     print every binding to chat
  /clg reset                    default position and settings

Until you switch its own click casting on, ClickLegend only reads and draws:
it changes no bindings and touches no unit frame. It never changes another
addon's bindings or the game's.
