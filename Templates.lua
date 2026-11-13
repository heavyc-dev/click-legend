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
--      the menu on everything that is not an ally, and Alt + Left and
--      Alt + Right are Target and Menu for everyone. Classes with nothing to
--      cast on allies keep both plain clicks as they are and start on the
--      middle button: a damage spell on plain left click would take away the
--      only way to target from a frame.
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
--
--  A key is { "KEY", rule, rule, ... } and a rule is "conditions=action":
--    conditions: help | harm | dead | alive | combat | nocombat | pet | nopet
--                | form1..form6 | shift | ctrl | alt     (none: anyone, any time)
--    action:     a spell name, or @target @focus @assist @menu @trinket1 @trinket2
--  Spell names are the game's English names; one that does not exist on this
--  client is simply a spell the character does not know.
-------------------------------------------------------------------------------
local _, ns = ...

local ipairs, type, tonumber = ipairs, type, tonumber

-- Target and Menu for everyone, for the templates that use the plain clicks.
local TARGET_KEY = { "ALT-BUTTON1", "=@target" }
local MENU_KEY = { "ALT-BUTTON2", "=@menu" }

local TEMPLATES = {
    { class = "PRIEST", name = "Priest: healer", keys = {
        { "BUTTON1", "help dead=Resurrection", "help=Flash Heal", "help=Heal", "help=Lesser Heal", "=@target" },
        { "BUTTON2", "help=Greater Heal", "help=Heal", "help=Lesser Heal", "=@menu" },
        { "BUTTON3", "help=Renew", "harm=Shadow Word: Pain" },
        { "SHIFT-BUTTON1", "help=Power Word: Shield", "harm=Smite" },
        { "SHIFT-BUTTON2", "=Dispel Magic" },
        { "CTRL-BUTTON1", "help=Abolish Disease", "help=Cure Disease", "harm=Mind Blast" },
        { "CTRL-BUTTON2", "help=Power Word: Fortitude", "harm=Shackle Undead" },
        TARGET_KEY, MENU_KEY,
    } },
    { class = "PRIEST", name = "Priest: shadow", keys = {
        { "BUTTON1", "help=Power Word: Shield", "=@target" },
        { "BUTTON2", "help dead=Resurrection", "help=Flash Heal", "help=Lesser Heal", "=@menu" },
        { "BUTTON3", "harm=Mind Flay", "harm=Smite", "help=Renew" },
        { "SHIFT-BUTTON1", "harm=Mind Blast", "help=Abolish Disease", "help=Cure Disease" },
        { "SHIFT-BUTTON2", "=Dispel Magic" },
        { "CTRL-BUTTON1", "harm=Shadow Word: Pain", "help=Power Word: Fortitude" },
        { "CTRL-BUTTON2", "harm=Silence" },
        TARGET_KEY, MENU_KEY,
    } },
    { class = "PALADIN", name = "Paladin: healer", keys = {
        { "BUTTON1", "help dead=Redemption", "help=Flash of Light", "help=Holy Light", "=@target" },
        { "BUTTON2", "help=Holy Light", "=@menu" },
        { "BUTTON3", "help=Cleanse", "help=Purify", "harm=Hammer of Justice" },
        { "SHIFT-BUTTON1", "=Holy Shock" },
        { "SHIFT-BUTTON2", "help=Blessing of Protection", "harm=Judgement" },
        { "CTRL-BUTTON1", "help=Lay on Hands", "harm=Hammer of Wrath" },
        { "CTRL-BUTTON2", "help=Blessing of Freedom" },
        TARGET_KEY, MENU_KEY,
    } },
    { class = "PALADIN", name = "Paladin: tank or retribution", keys = {
        { "BUTTON1", "help dead=Redemption", "help=Flash of Light", "help=Holy Light", "=@target" },
        { "BUTTON2", "help=Cleanse", "help=Purify", "=@menu" },
        { "BUTTON3", "harm=Judgement", "help=Blessing of Protection" },
        { "SHIFT-BUTTON1", "harm=Hammer of Justice", "help=Blessing of Freedom" },
        { "SHIFT-BUTTON2", "harm=Hammer of Wrath", "help=Lay on Hands" },
        { "CTRL-BUTTON1", "help=Blessing of Sacrifice" },
        TARGET_KEY, MENU_KEY,
    } },
    { class = "DRUID", name = "Druid: healer", keys = {
        { "BUTTON1", "help dead nocombat=Revive", "help dead nocombat=Rebirth", "help=Healing Touch", "=@target" },
        { "BUTTON2", "help=Regrowth", "help=Healing Touch", "=@menu" },
        { "BUTTON3", "help=Rejuvenation", "harm=Moonfire" },
        { "SHIFT-BUTTON1", "help=Swiftmend", "harm=Wrath" },
        { "SHIFT-BUTTON2", "help=Remove Curse", "harm=Entangling Roots" },
        { "CTRL-BUTTON1", "help=Abolish Poison", "help=Cure Poison", "harm=Faerie Fire" },
        { "CTRL-BUTTON2", "help dead=Rebirth", "help=Innervate", "harm=Hibernate" },
        TARGET_KEY, MENU_KEY,
    } },
    { class = "DRUID", name = "Druid: feral or balance", keys = {
        { "BUTTON1", "help dead nocombat=Revive", "help dead nocombat=Rebirth", "help=Rejuvenation", "=@target" },
        { "BUTTON2", "help=Regrowth", "help=Healing Touch", "=@menu" },
        { "BUTTON3", "harm=Moonfire", "help=Remove Curse" },
        { "SHIFT-BUTTON1", "harm=Wrath", "help=Abolish Poison", "help=Cure Poison" },
        { "SHIFT-BUTTON2", "harm=Entangling Roots", "help=Innervate" },
        { "CTRL-BUTTON1", "harm=Faerie Fire", "help=Mark of the Wild" },
        { "CTRL-BUTTON2", "help dead=Rebirth", "harm=Hibernate" },
        TARGET_KEY, MENU_KEY,
    } },
    { class = "SHAMAN", name = "Shaman: healer", keys = {
        { "BUTTON1", "help dead=Ancestral Spirit", "help=Lesser Healing Wave", "help=Healing Wave", "=@target" },
        { "BUTTON2", "help=Healing Wave", "=@menu" },
        { "BUTTON3", "help=Chain Heal", "help=Healing Wave", "harm=Earth Shock" },
        { "SHIFT-BUTTON1", "help=Cure Poison", "harm=Purge" },
        { "SHIFT-BUTTON2", "help=Cure Disease", "harm=Flame Shock" },
        { "CTRL-BUTTON1", "harm=Lightning Bolt" },
        { "CTRL-BUTTON2", "harm=Frost Shock" },
        TARGET_KEY, MENU_KEY,
    } },
    { class = "SHAMAN", name = "Shaman: elemental or enhancement", keys = {
        { "BUTTON1", "help dead=Ancestral Spirit", "help=Lesser Healing Wave", "help=Healing Wave", "=@target" },
        { "BUTTON2", "help=Cure Poison", "=@menu" },
        { "BUTTON3", "harm=Earth Shock", "help=Cure Disease" },
        { "SHIFT-BUTTON1", "harm=Lightning Bolt", "help=Chain Heal", "help=Healing Wave" },
        { "SHIFT-BUTTON2", "harm=Flame Shock" },
        { "CTRL-BUTTON1", "harm=Purge" },
        { "CTRL-BUTTON2", "harm=Frost Shock" },
        TARGET_KEY, MENU_KEY,
    } },
    -- Little or nothing to cast on allies: plain left and right click stay as
    -- they are, so a click on a party member still targets them.
    { class = "MAGE", name = "Mage", keys = {
        { "BUTTON3", "harm=Polymorph", "help=Remove Lesser Curse" },
        { "SHIFT-BUTTON1", "harm=Counterspell", "help=Arcane Intellect" },
        { "SHIFT-BUTTON2", "harm=Frostbolt", "harm=Fireball" },
        { "CTRL-BUTTON1", "harm=Fire Blast" },
    } },
    { class = "WARLOCK", name = "Warlock", keys = {
        { "BUTTON3", "harm=Corruption", "help=Unending Breath" },
        { "SHIFT-BUTTON1", "harm=Curse of Agony" },
        { "SHIFT-BUTTON2", "harm=Immolate" },
        { "CTRL-BUTTON1", "harm=Fear" },
        { "CTRL-BUTTON2", "harm=Banish" },
        { "ALT-BUTTON1", "harm=Drain Life" },
    } },
    { class = "HUNTER", name = "Hunter", keys = {
        { "BUTTON3", "harm=Hunter's Mark", "help=Mend Pet" },
        { "SHIFT-BUTTON1", "harm=Serpent Sting" },
        { "SHIFT-BUTTON2", "harm=Concussive Shot" },
        { "CTRL-BUTTON1", "harm=Scatter Shot" },
        { "CTRL-BUTTON2", "harm=Tranquilizing Shot" },
        { "ALT-BUTTON1", "harm=Distracting Shot" },
    } },
    -- Stances: 1 Battle, 2 Defensive, 3 Berserker. One key is the right
    -- ability for the stance the warrior is in.
    { class = "WARRIOR", name = "Warrior", keys = {
        { "BUTTON3", "harm form1=Charge", "harm form3=Intercept", "harm form2=Taunt" },
        { "SHIFT-BUTTON1", "harm form3=Pummel", "harm=Shield Bash" },
        { "SHIFT-BUTTON2", "harm form2=Taunt", "harm form1=Mocking Blow" },
        { "CTRL-BUTTON1", "harm=Sunder Armor" },
        { "CTRL-BUTTON2", "harm=Hamstring" },
        { "ALT-BUTTON1", "harm=Rend" },
    } },
    { class = "ROGUE", name = "Rogue", keys = {
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
        bindings[#bindings + 1] = { key = key[1], rules = rules }
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

-------------------------------------------------------------------------------
--  Used by the other files
-------------------------------------------------------------------------------
ns.BuildTemplate = BuildTemplate
ns.ListTemplates = ListTemplates
ns.TEMPLATES     = TEMPLATES
