-------------------------------------------------------------------------------
--  ClickLegend - Templates.lua
--  Starter sets of bindings, one or two per class, to make a set from and
--  then change. Data only.
--
--  How they are laid out, and why:
--    * The most used spells sit on the plain clicks, then Shift, then Ctrl,
--      then Alt, with the left, right and middle button. No extra mouse
--      buttons are needed.
--    * A plain click normally targets (left) or opens the menu (right). Where
--      a template puts an ally spell on one, the click still targets or opens
--      the menu on everything else, and Alt + Left and Alt + Right are Target
--      and Menu for everyone.
--    * Every set has its main damage spell on plain left click for enemies,
--      and casters a second one on plain right click (Wrath / Starfire,
--      Frostbolt / Fireball, Shadow Bolt / Searing Pain), for combat only
--      ("harm combat="): out of combat a click on an enemy only targets it,
--      so nothing is pulled by a click. "Enemy spells also target the enemy"
--      makes the click target as it casts. Melee sets and hunters keep plain
--      right click on an enemy as the game's own: it starts the attack.
--      A spell with a cooldown may stand there: what follows it is Target or
--      Menu, and the target is taken anyway.
--    * Plain left and right click of every set also work in the world
--      (`world = true`): on a friendly player's character the ally rules, in
--      combat on an enemy the enemy rules. The provider takes such a click
--      only there (`softEnemy` in Cast.lua), so everything else in the world
--      is clicked as always.
--    * An ally's heal over time and an enemy's damage over time or debuff
--      share a key (Rejuvenation / Faerie Fire, Renew / Shadow Word: Pain).
--    * A key does one job on an ally and a related one on an enemy (heal /
--      damage, dispel / purge), so it is never dead on either kind of frame.
--    * The resurrection is the "dead ally" rule of the main heal key: click
--      the dead player with the key you were healing them with. A combat
--      resurrection is not put there: it has a long cooldown, and a healer
--      clicking on through a death would spend it on whoever died under the
--      cursor. It gets a key that takes a modifier to press.
--    * Where a spell arrives late or comes from a talent, the better spell is
--      listed first and the one it replaces after it. A rule whose spell the
--      character does not know is skipped, so one template serves every level
--      and talent build. A spell with a cooldown is never put in front of a
--      fallback: the game would pick it while it is cooling down and cast
--      nothing.
--    * Each kind of dispel has a key of its own. A dispel casts even when
--      there is nothing to remove, so two on one key would never reach the
--      second.
--    * A healer's dispels are on the mouse wheel, up and down, over a unit
--      frame: the wheel does nothing there in the game, it is the fastest
--      thing to reach, and a turn of it by mistake costs a little mana and
--      nothing else. That is also why nothing with a cooldown, and nothing
--      that changes a fight (a protection, a resurrection), is put on it.
--    * Shift and Ctrl with the middle button carry the buffs and the rarely
--      used spells.
--    * The spells are the ones a level 60 character of this client can learn
--      (its trainer lists were read on 2026-11-19). A few spells that only
--      this client has are not named here: their names are not known.
--
--  A template may have `spec`: a word of the spec's name it is for ("feral"),
--  which the Class Spec Quickstart matches first (`SpecTemplate`).
--  A key is { "KEY", rule, rule, ..., world = true or nil } and a rule is
--  "conditions=action":
--    conditions: help | harm | dead | alive | combat | nocombat | pet | nopet
--                | form1..form6 | shift | ctrl | alt     (none: anyone, any time)
--    action:     a spell name, or @target @focus @assist @menu @trinket1 @trinket2
--  Spell names are the game's English names; one that does not exist on this
--  client is simply a spell the character does not know.
-------------------------------------------------------------------------------
local _, ns = ...

local ipairs, type, tonumber, pcall = ipairs, type, tonumber, pcall

-- Target and Menu for everyone, for the templates that use the plain clicks.
local TARGET_KEY = { "ALT-BUTTON1", "=@target" }
local MENU_KEY = { "ALT-BUTTON2", "=@menu" }

local TEMPLATES = {
    { class = "PRIEST", name = "Priest: healer", keys = {
        { "BUTTON1", "help dead=Resurrection", "help=Flash Heal", "help=Heal", "help=Lesser Heal",
          "harm combat=Smite", "=@target", world = true },
        { "BUTTON2", "help=Greater Heal", "help=Heal", "help=Lesser Heal", "harm combat=Mind Blast", "=@menu", world = true },
        { "BUTTON3", "help=Renew", "harm=Shadow Word: Pain" },
        { "MOUSEWHEELUP", "=Dispel Magic" },
        { "MOUSEWHEELDOWN", "help=Abolish Disease", "help=Cure Disease" },
        { "SHIFT-BUTTON1", "help=Power Word: Shield", "harm=Holy Fire" },
        { "SHIFT-BUTTON2", "help=Power Word: Fortitude", "harm=Mana Burn" },
        { "SHIFT-BUTTON3", "help=Fear Ward", "harm=Shackle Undead" },
        { "CTRL-BUTTON1", "help=Divine Spirit", "harm=Mind Soothe" },
        { "CTRL-BUTTON2", "help=Shadow Protection" },
        TARGET_KEY, MENU_KEY,
    } },
    { class = "PRIEST", name = "Priest: shadow", spec = "shadow", keys = {
        { "BUTTON1", "help=Power Word: Shield", "harm combat=Mind Flay", "harm combat=Smite", "=@target", world = true },
        { "BUTTON2", "help dead=Resurrection", "help=Flash Heal", "help=Lesser Heal", "harm combat=Mind Blast",
          "=@menu", world = true },
        { "BUTTON3", "harm=Shadow Word: Pain", "help=Renew" },
        { "SHIFT-BUTTON1", "harm=Vampiric Embrace", "help=Abolish Disease", "help=Cure Disease" },
        { "SHIFT-BUTTON2", "=Dispel Magic" },
        { "SHIFT-BUTTON3", "harm=Mana Burn", "help=Fear Ward" },
        { "CTRL-BUTTON1", "harm=Shackle Undead", "help=Power Word: Fortitude" },
        { "CTRL-BUTTON2", "harm=Silence" },
        TARGET_KEY, MENU_KEY,
    } },
    { class = "PALADIN", name = "Paladin: healer", keys = {
        { "BUTTON1", "help dead=Redemption", "help=Flash of Light", "help=Holy Light", "harm combat=Judgement",
          "=@target", world = true },
        { "BUTTON2", "help=Holy Light", "harm combat=Holy Shock", "=@menu", world = true },
        { "BUTTON3", "help=Blessing of Freedom", "harm=Hammer of Justice" },
        { "MOUSEWHEELUP", "help=Cleanse", "help=Purify" },
        { "SHIFT-BUTTON1", "help=Holy Shock", "harm=Exorcism" },
        { "SHIFT-BUTTON2", "help=Blessing of Protection" },
        { "SHIFT-BUTTON3", "help=Blessing of Sacrifice" },
        { "CTRL-BUTTON1", "help=Lay on Hands", "harm=Hammer of Wrath" },
        TARGET_KEY, MENU_KEY,
    } },
    -- Plain right click on an enemy stays the game's: it starts the attack.
    { class = "PALADIN", name = "Paladin: tank or retribution", keys = {
        { "BUTTON1", "help dead=Redemption", "help=Flash of Light", "help=Holy Light", "harm combat=Judgement",
          "=@target", world = true },
        { "BUTTON2", "help=Cleanse", "help=Purify", "=@menu", world = true },
        { "BUTTON3", "harm=Exorcism", "help=Blessing of Protection" },
        { "SHIFT-BUTTON1", "harm=Hammer of Justice", "help=Blessing of Freedom" },
        { "SHIFT-BUTTON2", "harm=Hammer of Wrath", "help=Lay on Hands" },
        { "CTRL-BUTTON1", "help=Blessing of Sacrifice" },
        TARGET_KEY, MENU_KEY,
    } },
    { class = "DRUID", name = "Druid: healer", keys = {
        { "BUTTON1", "help dead nocombat=Revive", "help dead nocombat=Rebirth", "help=Healing Touch",
          "harm combat=Wrath", "=@target", world = true },
        { "BUTTON2", "help=Regrowth", "help=Healing Touch", "harm combat=Starfire", "harm combat=Wrath", "=@menu",
          world = true },
        { "BUTTON3", "help=Rejuvenation", "harm=Faerie Fire" },
        { "MOUSEWHEELUP", "help=Remove Curse" },
        { "MOUSEWHEELDOWN", "help=Abolish Poison", "help=Cure Poison" },
        { "SHIFT-BUTTON1", "help=Swiftmend", "harm=Moonfire" },
        { "SHIFT-BUTTON2", "help=Mark of the Wild", "harm=Entangling Roots" },
        { "SHIFT-BUTTON3", "help=Thorns", "harm=Hibernate" },
        { "CTRL-BUTTON1", "help=Innervate", "harm=Insect Swarm" },
        { "CTRL-BUTTON2", "help dead=Rebirth" },
        TARGET_KEY, MENU_KEY,
    } },
    { class = "DRUID", name = "Druid: balance", spec = "balance", keys = {
        { "BUTTON1", "help dead nocombat=Revive", "help dead nocombat=Rebirth", "help=Regrowth", "help=Healing Touch",
          "harm combat=Wrath", "=@target", world = true },
        { "BUTTON2", "help=Healing Touch", "harm combat=Starfire", "harm combat=Wrath", "=@menu", world = true },
        { "BUTTON3", "help=Rejuvenation", "harm=Faerie Fire" },
        { "SHIFT-BUTTON1", "harm=Moonfire", "help=Remove Curse" },
        { "SHIFT-BUTTON2", "harm=Insect Swarm", "help=Abolish Poison", "help=Cure Poison" },
        { "SHIFT-BUTTON3", "harm=Entangling Roots", "help=Innervate" },
        { "CTRL-BUTTON1", "harm=Hibernate", "help=Mark of the Wild" },
        { "CTRL-BUTTON2", "help dead=Rebirth" },
        TARGET_KEY, MENU_KEY,
    } },
    -- Forms: 1 Bear, 3 Cat. Plain right click on an enemy stays the game's:
    -- it starts the attack.
    { class = "DRUID", name = "Druid: feral", spec = "feral", keys = {
        { "BUTTON1", "help dead nocombat=Revive", "help dead nocombat=Rebirth", "help=Regrowth",
          "harm combat form1=Maul", "harm combat form3=Claw", "=@target", world = true },
        { "BUTTON2", "help=Healing Touch", "=@menu", world = true },
        { "BUTTON3", "help=Rejuvenation", "harm=Faerie Fire" },
        { "SHIFT-BUTTON1", "harm form1=Bash", "help=Abolish Poison", "help=Cure Poison" },
        { "SHIFT-BUTTON2", "harm=Entangling Roots", "help=Innervate" },
        { "SHIFT-BUTTON3", "harm form1=Growl", "help=Remove Curse" },
        { "CTRL-BUTTON1", "harm=Hibernate", "help=Mark of the Wild" },
        { "CTRL-BUTTON2", "help dead=Rebirth", "harm=Moonfire" },
        TARGET_KEY, MENU_KEY,
    } },
    { class = "SHAMAN", name = "Shaman: healer", keys = {
        { "BUTTON1", "help dead=Ancestral Spirit", "help=Lesser Healing Wave", "help=Healing Wave",
          "harm combat=Lightning Bolt", "=@target", world = true },
        { "BUTTON2", "help=Healing Wave", "harm combat=Earth Shock", "=@menu", world = true },
        { "BUTTON3", "help=Chain Heal", "help=Healing Wave", "harm=Flame Shock" },
        { "MOUSEWHEELUP", "help=Cure Poison" },
        { "MOUSEWHEELDOWN", "help=Cure Disease" },
        { "SHIFT-BUTTON1", "help=Water Breathing", "harm=Purge" },
        { "SHIFT-BUTTON2", "help=Water Walking", "harm=Frost Shock" },
        { "CTRL-BUTTON1", "harm=Chain Lightning" },
        TARGET_KEY, MENU_KEY,
    } },
    { class = "SHAMAN", name = "Shaman: elemental", spec = "elemental", keys = {
        { "BUTTON1", "help dead=Ancestral Spirit", "help=Lesser Healing Wave", "help=Healing Wave",
          "harm combat=Lightning Bolt", "=@target", world = true },
        { "BUTTON2", "help=Cure Poison", "harm combat=Chain Lightning", "=@menu", world = true },
        { "BUTTON3", "harm=Flame Shock", "help=Cure Disease" },
        { "SHIFT-BUTTON1", "harm=Earth Shock", "help=Chain Heal", "help=Healing Wave" },
        { "SHIFT-BUTTON2", "harm=Frost Shock" },
        { "CTRL-BUTTON1", "harm=Purge" },
        TARGET_KEY, MENU_KEY,
    } },
    -- Plain right click on an enemy stays the game's: it starts the attack.
    { class = "SHAMAN", name = "Shaman: enhancement", spec = "enhancement", keys = {
        { "BUTTON1", "help dead=Ancestral Spirit", "help=Lesser Healing Wave", "help=Healing Wave",
          "harm combat=Earth Shock", "=@target", world = true },
        { "BUTTON2", "help=Cure Poison", "=@menu", world = true },
        { "BUTTON3", "harm=Flame Shock", "help=Cure Disease" },
        { "SHIFT-BUTTON1", "harm=Stormstrike", "help=Chain Heal", "help=Healing Wave" },
        { "SHIFT-BUTTON2", "harm=Frost Shock" },
        { "CTRL-BUTTON1", "harm=Purge" },
        { "CTRL-BUTTON2", "harm=Lightning Bolt" },
        TARGET_KEY, MENU_KEY,
    } },
    -- Classes with little to cast on allies: a plain click on an ally does
    -- what it does in the game (target, menu).
    { class = "MAGE", name = "Mage", keys = {
        { "BUTTON1", "harm combat=Frostbolt", "=@target", world = true },
        { "BUTTON2", "harm combat=Fireball", "=@menu", world = true },
        { "BUTTON3", "harm=Polymorph", "help=Remove Lesser Curse" },
        { "SHIFT-BUTTON1", "harm=Counterspell", "help=Arcane Intellect" },
        { "SHIFT-BUTTON2", "harm=Fire Blast" },
        { "CTRL-BUTTON1", "harm=Arcane Missiles", "help=Dampen Magic" },
        { "CTRL-BUTTON2", "harm=Scorch", "help=Amplify Magic" },
    } },
    { class = "WARLOCK", name = "Warlock", keys = {
        { "BUTTON1", "harm combat=Shadow Bolt", "=@target", world = true },
        { "BUTTON2", "harm combat=Searing Pain", "=@menu", world = true },
        { "BUTTON3", "harm=Corruption", "help=Unending Breath" },
        { "SHIFT-BUTTON1", "harm=Curse of Agony" },
        { "SHIFT-BUTTON2", "harm=Immolate" },
        { "CTRL-BUTTON1", "harm=Fear" },
        { "CTRL-BUTTON2", "harm=Banish" },
        { "ALT-BUTTON1", "harm=Drain Life" },
    } },
    -- Plain right click on an enemy stays the game's: Auto Shot or the attack.
    { class = "HUNTER", name = "Hunter", keys = {
        { "BUTTON1", "harm combat=Arcane Shot", "=@target", world = true },
        { "BUTTON3", "harm=Hunter's Mark", "help=Mend Pet" },
        { "SHIFT-BUTTON1", "harm=Serpent Sting" },
        { "SHIFT-BUTTON2", "harm=Concussive Shot" },
        { "CTRL-BUTTON1", "harm=Scatter Shot" },
        { "CTRL-BUTTON2", "harm=Tranquilizing Shot" },
        { "ALT-BUTTON1", "harm=Distracting Shot" },
    } },
    -- Stances: 1 Battle, 2 Defensive, 3 Berserker. One key is the right
    -- ability for the stance the warrior is in. Plain right click on an
    -- enemy stays the game's: it starts the attack.
    { class = "WARRIOR", name = "Warrior", keys = {
        { "BUTTON1", "harm combat=Heroic Strike", "=@target", world = true },
        { "BUTTON3", "harm form1=Charge", "harm form3=Intercept", "harm form2=Taunt" },
        { "SHIFT-BUTTON1", "harm form3=Pummel", "harm=Shield Bash" },
        { "SHIFT-BUTTON2", "harm form2=Disarm", "harm form1=Mocking Blow" },
        { "CTRL-BUTTON1", "harm=Sunder Armor" },
        { "CTRL-BUTTON2", "harm=Hamstring" },
        { "ALT-BUTTON1", "harm=Rend" },
    } },
    { class = "ROGUE", name = "Rogue", keys = {
        { "BUTTON1", "harm combat=Sinister Strike", "=@target", world = true },
        { "BUTTON3", "harm=Kick" },
        { "SHIFT-BUTTON1", "harm=Blind" },
        { "SHIFT-BUTTON2", "harm=Gouge" },
        { "CTRL-BUTTON1", "harm=Kidney Shot" },
        { "CTRL-BUTTON2", "harm=Sap" },
    } },
}

local WORD = {
    help = { "reaction", "help" }, harm = { "reaction", "harm" },
    dead = { "dead", true }, alive = { "dead", false },
    combat = { "combat", true }, nocombat = { "combat", false },
    pet = { "pet", true }, nopet = { "pet", false },
    shift = { "mod", "shift" }, ctrl = { "mod", "ctrl" }, alt = { "mod", "alt" },
}

local function BuildRule(text)
    local conditions, what = text:match("^(.-)=(.+)$")
    if not what then return nil end
    local when = {}
    for word in conditions:gmatch("%S+") do
        local form = word:match("^form(%d)$")
        local pair = WORD[word]
        if form then
            when.form = tonumber(form)
        elseif pair then
            when[pair[1]] = pair[2]
        end
    end
    local special = what:match("^@(%a+%d?)$")
    return { when = when, action = special and { type = special } or { type = "spell", name = what } }
end

-- A fresh set table for a template, in the saved shape. Cast.lua cleans it
-- like any saved set before it is used.
local function BuildTemplate(template)
    local bindings = {}
    for _, key in ipairs(template.keys) do
        local rules = {}
        for i = 2, #key do
            local rule = type(key[i]) == "string" and BuildRule(key[i])
            if rule then rules[#rules + 1] = rule end
        end
        -- `world`: the key also works on units in the world (mouseover casting).
        bindings[#bindings + 1] = { key = key[1], rules = rules, hover = key.world and true or nil }
    end
    return { version = 1, bindings = bindings }
end

-- The templates, this character's class first.
local function ListTemplates()
    local class
    if UnitClass then
        local ok, _, file = pcall(UnitClass, "player")
        class = ok and file or nil
    end
    local own, others = {}, {}
    for _, template in ipairs(TEMPLATES) do
        local list = template.class == class and own or others
        list[#list + 1] = template
    end
    for _, template in ipairs(others) do own[#own + 1] = template end
    return own, class
end

-- The healing specs by their English names, for a client that gives no role.
local HEALER_SPECS = { Holy = true, Discipline = true, Restoration = true }

-- The character's current spec: its name in lower case and whether it heals
-- (true, false, or nil when the client says no spec: too low a level, or no
-- specs at all).
local function CurrentSpec()
    local S = C_SpecializationInfo
    if not (S and S.GetSpecialization and S.GetSpecializationInfo) then return nil, nil end
    local ok, index = pcall(S.GetSpecialization)
    if not (ok and type(index) == "number" and index > 0) then return nil, nil end
    local ok2, _, name, _, _, role = pcall(S.GetSpecializationInfo, index)
    if not ok2 then return nil, nil end
    name = type(name) == "string" and name or nil
    local heals = nil
    if role == "HEALER" or (name and HEALER_SPECS[name]) then
        heals = true
    elseif type(role) == "string" or name then
        heals = false
    end
    return name and name:lower() or nil, heals
end

-- The starter set that fits this character's class and spec best: the one
-- made for the spec, else the healer set for a healing spec and another one
-- otherwise, else the class's first. Nil for a class with no starter set.
local function SpecTemplate()
    local list, class = ListTemplates()
    local spec, heals = CurrentSpec()
    local own = {}
    for _, template in ipairs(list) do
        if template.class ~= class then break end
        own[#own + 1] = template
    end
    if spec then
        for _, template in ipairs(own) do
            if template.spec and spec:find(template.spec, 1, true) then return template end
        end
    end
    if heals ~= nil then
        for _, template in ipairs(own) do
            if (template.name:find("healer", 1, true) ~= nil) == heals then return template end
        end
    end
    return own[1]
end

-------------------------------------------------------------------------------
--  Used by the other files
-------------------------------------------------------------------------------
ns.BuildTemplate = BuildTemplate
ns.ListTemplates = ListTemplates
ns.SpecTemplate  = SpecTemplate
ns.TEMPLATES     = TEMPLATES
