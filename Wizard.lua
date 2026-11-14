-------------------------------------------------------------------------------
--  ClickLegend - Wizard.lua
--  Guided setup: another way into the Bindings tab. Six steps, seven with a
--  mouse that has a block of side buttons. Next is the way through and is
--  drawn as such; the short way out of the first page is the lesser button.
--    1. Where to start: a starter set, the set in use, or nothing; and
--       which mouse you have, for the small mouse the legend draws above
--       each spell. "Skip the setup" takes the set as it is and finishes.
--    +  Your side buttons (only with the twelve-button mouse): press each
--       one, so that the legend knows which key it sends.
--    2. Hover casting: unit frames only, any unit under the cursor, or that
--       and else the target. One of three, each with what it means. It is
--       about keyboard keys, the wheel and mouse buttons past the third,
--       and is kept for keys added on the later pages (`hoverPick`).
--    3. Your buttons: every mouse button and the wheel, each with Plain,
--       Shift, Ctrl and Alt switches. Extra mouse buttons are added by
--       clicking them, keyboard keys by pressing them.
--    4. What they do: one line per chosen key, with what it does on an ally,
--       on a dead ally and on an enemy side by side.
--    5. Options: a set for this spec, casting as the button goes down, the
--       legend as one large picture of the mouse, bindings in unit tooltips.
--    6. Done: a summary and the on/off switch.
--  The full editor stays there for everything else.
--
--  Screen only; every change goes through Cast.lua.
-------------------------------------------------------------------------------
local _, ns = ...

local ipairs, type, tonumber = ipairs, type, tonumber

local ACCENT, Safe, NewButton, NewText =
    ns.ACCENT, ns.Safe, ns.NewButton, ns.NewText
local ACTION_NAME, ActionEntry, ActiveSet, AddSet =
    ns.ACTION_NAME, ns.ActionEntry, ns.ActiveSet, ns.AddSet
local BuildTemplate, CastSettings, Edit, KeyName =
    ns.BuildTemplate, ns.CastSettings, ns.CastEdit, ns.CastKeyName
local ListSpells, ListTemplates, NewSet, RankText =
    ns.ListSpells, ns.ListTemplates, ns.NewSet, ns.RankText
local SelectSet, SetCastEnabled, ShowMenu, SlotAction =
    ns.SelectSet, ns.SetCastEnabled, ns.ShowMenu, ns.SlotAction
local CloseMenu, LongKey, ParseKey, KnownButtons, AddKnownButton =
    ns.CloseMenu, ns.LongKey, ns.ParseKey, ns.KnownButtons, ns.AddKnownButton
local KeyboardKeys, SetCastDown, SetSpecOnly, SpecState =
    ns.KeyboardKeys, ns.SetCastDown, ns.SetSpecOnly, ns.SpecState
local ClearSideKeys, SetSettings, SetSideKey, SideKeys =
    ns.ClearSideKeys, ns.SetSettings, ns.SetSideKey, ns.SideKeys
local MOUSE_LAYOUTS, MOUSE_ORDER = ns.MOUSE_LAYOUTS, ns.MOUSE_ORDER
local CopyFromSource, CopySources, Shadowed = ns.CopyFromSource, ns.CopySources, ns.CastShadowed

local db
ns.Subscribe("db", function(value) db = value end)

-- The modifiers a button can be set up with, most used first; the keys are
-- listed with every button plain, then with Shift, and so on.
local MODS = {
    { prefix = "", text = "Plain" }, { prefix = "SHIFT-", text = "Shift" },
    { prefix = "CTRL-", text = "Ctrl" }, { prefix = "ALT-", text = "Alt" },
}
local FIXED_INPUTS = { "BUTTON1", "BUTTON2", "BUTTON3", "MOUSEWHEELUP", "MOUSEWHEELDOWN" }
local MAX_ROWS = 24                 -- the list scrolls
local ROW_H = 24
local SIDE_BUTTONS = 12             -- the buttons of a block of side buttons
local HOVER_NOTE = "A keyboard key does this where the \"Hover casting\" step said: on unit frames only, "
    .. "or on any unit under the cursor."
-- The three ways of hover casting, as the step of that name offers them.
local HOVER_MODES = {
    { id = "frames", text = "Unit frames only",
      note = "Every key casts only while the cursor is on a unit frame (party, raid, target and the like). "
          .. "Nothing is taken from the game: away from a frame your keys do what they always did. The safe choice." },
    { id = "hover", text = "Any unit under the cursor",
      note = "Your keys also cast on a character in the world or on a nameplate, without targeting it. "
          .. "ClickLegend then has those keys all the time: what the game had on them stops, "
          .. "and with nothing under the cursor they do nothing. The wheel still zooms the camera there." },
    { id = "target", text = "Under the cursor, else my target",
      note = "As above, and with nothing fitting under the cursor the same spell goes to your target, "
          .. "so the key always does something. What most people who cast by mouseover want. "
          .. "The wheel is left out of that part: away from a unit it zooms the camera." },
}
local MODIFIER_KEY = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
    LMETA = true, RMETA = true,
}
local SLOTS = {
    { id = "ally", text = "On an ally", color = { 0.05, 0.82, 0.62 } },
    { id = "dead", text = "On a dead ally", color = { 0.75, 0.75, 0.75 } },
    { id = "enemy", text = "On an enemy", color = { 0.90, 0.25, 0.25 } },
}
local KEY_NOTE = {
    BUTTON1 = "Left click normally targets the unit. If you put a spell on it for allies, "
        .. "keep Target for enemies, and put Target on another key so you can still select an ally.",
    BUTTON2 = "Right click normally opens the unit's menu. If you put a spell on it for allies, "
        .. "keep Menu for enemies, and put Menu on another key.",
    MOUSEWHEELUP = "The wheel only does this while the cursor is on a unit frame; elsewhere it zooms as usual.",
    MOUSEWHEELDOWN = "The wheel only does this while the cursor is on a unit frame; elsewhere it zooms as usual.",
}
local SPECIAL = { "dispel", "rez", "target", "menu", "focus", "assist", "trinket1", "trinket2" }
local MOUSE_NUMBER = { LeftButton = 1, RightButton = 2, MiddleButton = 3 }

local panel
local page = 1
local start = nil                   -- what page 1 has picked: "keep" | "empty" | a template
local chosen = nil                  -- [key string] = true: the keys to set up; nil until page 2 is reached
local keys = {}                     -- the chosen keys in order
local heard = nil                   -- feedback from the last click on the "more buttons" box
local typedKeys = {}                -- keyboard keys added during this run, or bound in the set
local listening = false             -- waiting for a keyboard key to add
local noteKey = nil                 -- the key whose line the cursor was last on (step 3)
local sideAt = 1                    -- the side button being asked for; past the last when all are set
local sideHeard = nil               -- feedback on the side buttons page
local sideListening = false         -- the side buttons page hears the keyboard
local quick = false                 -- on the short way: the side buttons page goes straight to the end
local hoverPick = nil               -- what the hover casting page picked in this run; nil: left as the set has it
local Refresh

-------------------------------------------------------------------------------
--  The pages. Which there are depends on the mouse picture picked on the
--  first one.
-------------------------------------------------------------------------------
-- The mouse the legend draws: "a" to "d".
local function MousePick()
    return db and MOUSE_LAYOUTS[db.mousePic] and db.mousePic or "a"
end

local function HasSideBlock()
    return MOUSE_LAYOUTS[MousePick()].grid ~= nil
end

local function Pages()
    local list = { "start" }
    if HasSideBlock() then list[#list + 1] = "side" end
    for _, name in ipairs({ "hover", "buttons", "keys", "options", "done" }) do list[#list + 1] = name end
    return list
end

local function Last() return #Pages() end
local function PageName() return Pages()[page] or "done" end

local function MouseItems()
    local now = MousePick()
    local items = {}
    for _, id in ipairs(MOUSE_ORDER) do
        items[#items + 1] = { text = MOUSE_LAYOUTS[id].name, value = id, current = id == now }
    end
    return items
end

-------------------------------------------------------------------------------
--  Lists
-------------------------------------------------------------------------------
local function StartItems()
    local items = {}
    local _, name = ActiveSet()
    if name then items[#items + 1] = { text = "The set in use: " .. name, value = "keep" } end
    -- What another click-cast addon, or the game's own Click Casting, has now.
    for _, source in ipairs(CopySources()) do
        items[#items + 1] = { text = "A copy of your " .. source.name .. " bindings",
            value = { copy = source.id, name = "A copy of your " .. source.name .. " bindings" } }
    end
    local templates, class = ListTemplates()
    for _, template in ipairs(templates) do
        items[#items + 1] = { text = template.name, value = template,
            note = template.class == class and "your class" or nil }
    end
    items[#items + 1] = { text = "Nothing: an empty set", value = "empty" }
    return items
end

-- What the first page picks when nothing has been picked: the set in use,
-- else the first starter set for this class, else an empty set.
local function DefaultStart()
    local items = StartItems()
    for _, item in ipairs(items) do
        if item.value == "keep" or item.note then return item.value end
    end
    return "empty"
end

local function StartText(value)
    if value == "keep" then
        local _, name = ActiveSet()
        return "The set in use: " .. (name or "?")
    elseif value == "empty" then
        return "Nothing: an empty set"
    end
    return value.name
end

-- What a slot can be set to: nothing, the things that are not spells, then
-- the character's spells.
local function ActionItems(slot)
    local items = { { text = slot == "dead" and "Nothing special (same as a living ally)" or "Nothing", value = false } }
    for _, kind in ipairs(SPECIAL) do
        items[#items + 1] = { text = ACTION_NAME[kind], value = { type = kind } }
    end
    for _, spell in ipairs(ListSpells()) do
        items[#items + 1] = {
            text = spell.name, icon = spell.icon, note = spell.lowRank and spell.rank or nil,
            value = { type = "spell", name = spell.name, spellID = spell.id, pinned = spell.lowRank },
        }
    end
    return items
end

-------------------------------------------------------------------------------
--  The buttons and the keys to set up
-------------------------------------------------------------------------------
-- Left, right, middle, the wheel, then the extra mouse buttons this player has
-- shown ClickLegend, lowest first.
local function Inputs()
    local list = {}
    for i, key in ipairs(FIXED_INPUTS) do list[i] = key end
    for _, n in ipairs(KnownButtons()) do list[#list + 1] = "BUTTON" .. n end
    for _, key in ipairs(typedKeys) do list[#list + 1] = key end
    -- Keyboard keys a block of side buttons sends are buttons to set up too.
    local has = {}
    for _, key in ipairs(list) do has[key] = true end
    local side = SideKeys()
    for n = 1, SIDE_BUTTONS do
        local key = side[n]
        if key and not has[key] then
            has[key] = true
            list[#list + 1] = key
        end
    end
    return list
end

local function AddTypedKey(key)
    for _, known in ipairs(typedKeys) do
        if known == key then return false end
    end
    typedKeys[#typedKeys + 1] = key
    return true
end

-- First visit to the buttons page: switch on what the set already binds
-- (an extra button it uses is added to the list), or the three plain clicks
-- for a set with nothing in reach.
local function SeedChosen()
    chosen = {}
    local set = ActiveSet()
    local any = false
    if set then
        local single = {}
        for _, mod in ipairs(MODS) do single[mod.prefix] = true end
        for _, binding in ipairs(set.bindings) do
            local mods, key = ParseKey(binding.key)
            local n = tonumber(key:match("^BUTTON(%d+)$"))
            if single[mods] then
                if n and n > 3 then
                    AddKnownButton(n)
                elseif not n and key ~= "MOUSEWHEELUP" and key ~= "MOUSEWHEELDOWN" then
                    AddTypedKey(key)                    -- a keyboard key the set binds
                end
                chosen[mods .. key] = true
                any = true
            end
        end
    end
    if not any then
        chosen.BUTTON1, chosen.BUTTON2, chosen.BUTTON3 = true, true, true
    end
end

-- Every button plain, then every button with Shift, and so on.
local function BuildKeys()
    keys = {}
    local inputs = Inputs()
    for _, mod in ipairs(MODS) do
        for _, input in ipairs(inputs) do
            if chosen[mod.prefix .. input] then keys[#keys + 1] = mod.prefix .. input end
        end
    end
end

-------------------------------------------------------------------------------
--  Moving through the pages
-------------------------------------------------------------------------------
-- Leaving the first page makes the set it picked.
local function ApplyStart()
    local value = start or DefaultStart()
    if value == "keep" and ActiveSet() then return true end
    local name
    if type(value) == "table" and value.copy then
        name = CopyFromSource(value.copy) or nil
    elseif type(value) == "table" then
        name = AddSet(value.name, BuildTemplate(value))
    else
        local ok, made = false, nil
        local n = 1
        repeat
            ok, made = NewSet(n == 1 and "My bindings" or ("My bindings " .. n))
            n = n + 1
        until ok or n > 50
        name = ok and made or nil
    end
    if not name then return false end
    SelectSet(name)
    start = "keep"                  -- going back and forward again must not make another
    chosen = nil                    -- a different set: look again at what it binds
    return true
end

-- How the set in use stands on hover casting: what was picked in this run,
-- else what its keys say (all of them, or it counts as unit frames only).
local function HoverMode()
    if hoverPick then return hoverPick end
    local count, anywhere, onTarget = KeyboardKeys()
    if count == 0 or anywhere < count then return "frames" end
    return onTarget == count and "target" or "hover"
end

-- Puts the pick on the keys of the set. Called again whenever a page is
-- left, so that a key added after the pick is treated the same.
local function ApplyHover()
    if not hoverPick or not ActiveSet() then return end
    Edit.SetHoverKeys(hoverPick ~= "frames", hoverPick == "target")
end

local function Go(to)
    CloseMenu()
    heard, listening = nil, false
    if panel then panel.keyBox:EnableKeyboard(false) end
    if page == 1 and to > 1 and not ApplyStart() then return end
    if to >= 2 then
        if not chosen then SeedChosen() end
        BuildKeys()
    end
    local last = Last()
    page = to < 1 and 1 or (to > last and last or to)
    if PageName() ~= "side" then quick = false end
    sideListening = PageName() == "side"
    if panel then panel.sideCatch:EnableKeyboard(sideListening) end
    Refresh()
end

-- The short way: take the set as it is, switch click casting on, and finish.
-- A mouse with a block of side buttons is asked about those on the way.
local function QuickStart()
    if not ApplyStart() then return end
    SetCastEnabled(true)
    if HasSideBlock() then
        Go(2)
        quick = true
    else
        Go(Last())
    end
end

-- The side buttons page: the next button still to be shown, from `from` on.
local function NextSide(from)
    local side = SideKeys()
    for n = from, SIDE_BUTTONS do
        if not side[n] then return n end
    end
    for n = 1, from - 1 do
        if not side[n] then return n end
    end
    return SIDE_BUTTONS + 1                 -- all set
end

-- A key or mouse button pressed on the side buttons page: it is what the
-- side button being asked for sends.
local function SideInput(key)
    if sideAt > SIDE_BUTTONS then
        sideHeard = "All twelve are set. Click a box above to change one."
    elseif key == "BUTTON1" or key == "BUTTON2" then
        sideHeard = "Left and right click are not side buttons."
    else
        local ok, other = SetSideKey(sideAt, key)
        if ok then
            local n = tonumber(key:match("^BUTTON(%d+)$"))
            if n and n > 3 then AddKnownButton(n) end
            sideHeard = "Side button " .. sideAt .. ": " .. LongKey(key) .. "."
            sideAt = NextSide(sideAt + 1 > SIDE_BUTTONS and 1 or sideAt + 1)
        elseif other then
            sideHeard = LongKey(key) .. " is already side button " .. other .. "."
        else
            sideHeard = "That cannot be a side button."
        end
    end
    Refresh()
end

-- Hides it. Window.lua calls this when the window closes or the tab changes.
local function CloseWizard()
    listening = false
    if panel then
        panel.keyBox:EnableKeyboard(false)
        panel.sideCatch:EnableKeyboard(false)
        panel:Hide()
    end
end

local function Close()
    CloseMenu()
    CloseWizard()
    ns.RefreshWindow()
end

-- A key pressed while the "keyboard key" box is listening joins the list.
local function HeardKey(key)
    if MODIFIER_KEY[key] or not (listening and chosen) then return end
    listening = false
    panel.keyBox:EnableKeyboard(false)
    if key ~= "ESCAPE" then
        key = key:upper()
        heard = LongKey(key) .. (AddTypedKey(key) and " added." or " is already in the list.")
        if not chosen[key] then chosen[key] = true end
        BuildKeys()
    end
    Refresh()
end

-- A click on the "more buttons" box: an extra mouse button joins the list.
local function HeardButton(mouse)
    local n = MOUSE_NUMBER[mouse] or (type(mouse) == "string" and tonumber(mouse:match("^Button(%d+)$")))
    if not (n and chosen) then return end
    if n <= 3 then
        heard = LongKey("BUTTON" .. n) .. " is already in the list. Click the box with your other mouse buttons."
    elseif AddKnownButton(n) then
        chosen["BUTTON" .. n] = true                    -- a button just shown is one the player wants
        heard = LongKey("BUTTON" .. n) .. " added."
    else
        heard = LongKey("BUTTON" .. n) .. " is already in the list."
    end
    BuildKeys()
    Refresh()
end

-------------------------------------------------------------------------------
--  Building it
-------------------------------------------------------------------------------
local function Lit(button, on)
    if on then
        button.label:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
        button.bg:SetColorTexture(0.10, 0.30, 0.25, 1)
    else
        button.label:SetTextColor(0.5, 0.5, 0.5)
        button.bg:SetColorTexture(0.16, 0.17, 0.19, 1)
    end
end

local function NewList(f, top, bottom, w)
    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", 0, top)
    scroll:SetPoint("BOTTOMRIGHT", 0, bottom)
    local list = CreateFrame("Frame", nil, scroll)
    list:SetSize(w, 10)
    scroll:SetScrollChild(list)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = (list:GetHeight() or 0) - (self:GetHeight() or 0)
        if range < 0 then range = 0 end
        local to = (self:GetVerticalScroll() or 0) - delta * ROW_H * 2
        self:SetVerticalScroll(to < 0 and 0 or (to > range and range or to))
    end)
    return scroll, list
end

-- Step 3: one line of the list. The key's name, then what it does on an
-- ally, on a dead ally and on an enemy; each opens a list to pick from.
local function NewKeyLine(f, w, nameW, cellW, gap)
    local line = { cells = {} }
    line.name = NewText(f.keyList, 11)
    line.name:SetWidth(nameW - 4)
    line.name:SetJustifyH("LEFT")
    for s, slot in ipairs(SLOTS) do
        local b = NewButton(f.keyList, cellW, 22)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(16, 16)
        b.icon:SetPoint("LEFT", 3, 0)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.label:ClearAllPoints()
        b.label:SetPoint("LEFT", 23, 0)
        b.label:SetPoint("RIGHT", -3, 0)
        b.label:SetJustifyH("LEFT")
        b:SetScript("OnClick", function(self)
            local key = line.key
            if not key then return end
            noteKey = key
            ShowMenu(self, ActionItems(slot.id), function(action)
                Edit.SetSlot(key, slot.id, action or nil)
                Refresh()
            end, { width = 260, search = true })
        end)
        -- What to know about this key shows under the list while the cursor is on its line.
        b:SetScript("OnEnter", function(self)
            self.bg:SetColorTexture(0.26, 0.28, 0.31, 1)
            if line.key and noteKey ~= line.key then
                noteKey = line.key
                Refresh()
            end
        end)
        line.cells[s] = b
    end
    function line.Place(i)
        local y = -(i - 1) * ROW_H
        line.name:ClearAllPoints()
        line.name:SetPoint("TOPLEFT", 2, y - 5)
        for s, b in ipairs(line.cells) do
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", nameW + (s - 1) * (cellW + gap), y)
        end
    end
    function line.SetShown(shown)
        line.name:SetShown(shown)
        for _, b in ipairs(line.cells) do b:SetShown(shown) end
    end
    return line
end

local function Build(parent, w)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    f:SetFrameLevel((parent:GetFrameLevel() or 1) + 10)
    f:EnableMouse(true)                         -- nothing underneath can be clicked through it
    local fill = f:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    fill:SetColorTexture(0.07, 0.08, 0.09, 1)

    local title = NewText(f, 13, ACCENT[1], ACCENT[2], ACCENT[3])
    title:SetPoint("TOPLEFT", 0, -2)
    title:SetText("Guided setup")
    f.step = NewText(f, 10, 0.6, 0.6, 0.6)
    f.step:SetPoint("LEFT", title, "RIGHT", 10, 0)
    local close = NewButton(f, 60, 20, "Close")
    close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", Close)

    f.head = NewText(f, 16)
    f.head:SetPoint("TOPLEFT", 0, -34)
    f.text = NewText(f, 11, 0.8, 0.8, 0.8)
    f.text:SetPoint("TOPLEFT", 0, -58)
    f.text:SetWidth(w)
    f.text:SetJustifyH("LEFT")

    -- Step 1: where to start from, what the legend draws, and the short way
    -- to the end.
    f.startLabel = NewText(f, 12)
    f.startLabel:SetPoint("TOPLEFT", 0, -115)
    f.startLabel:SetText("Start from")
    f.start = NewButton(f, 360, 24)
    f.start:SetPoint("TOPLEFT", 120, -110)
    f.start:SetScript("OnClick", function(self)
        ShowMenu(self, StartItems(), function(value)
            start = value
            Refresh()
        end, { width = 360 })
    end)
    f.mouseLabel = NewText(f, 12)
    f.mouseLabel:SetPoint("TOPLEFT", 0, -149)
    f.mouseLabel:SetText("Your mouse")
    f.mouse = NewButton(f, 360, 24)
    f.mouse:SetPoint("TOPLEFT", 120, -144)
    f.mouse:SetScript("OnClick", function(self)
        ShowMenu(self, MouseItems(), function(value)
            SetSettings({ mousePic = value })
            Refresh()
        end, { width = 360 })
    end)
    f.mouseNote = NewText(f, 10, 0.6, 0.6, 0.6)
    f.mouseNote:SetPoint("LEFT", f.mouse, "RIGHT", 10, 0)
    f.mouseNote:SetWidth(w - 490)
    f.mouseNote:SetJustifyH("LEFT")
    f.mouseNote:SetText("The legend draws it small above each spell, with the button you bound lit up.")
    -- What Next leads to, said large: going through the steps is the way meant.
    f.nextNote = NewText(f, 12)
    f.nextNote:SetPoint("TOPLEFT", 0, -196)
    f.nextNote:SetWidth(w)
    f.nextNote:SetJustifyH("LEFT")
    f.nextNote:SetText("Then press Next, bottom right. The steps ask whether your keys should cast on units in the world, "
        .. "which buttons you use, and what each one should do. About a minute, and you can go back at any step.")
    -- The short way out: there, but not the button that asks to be pressed.
    f.quickStart = NewButton(f, 200, 22, "Skip the setup: use it and turn on")
    f.quickStart:SetPoint("BOTTOMLEFT", 0, 0)
    f.quickStart.label:SetTextColor(0.6, 0.6, 0.6)
    f.quickStart:SetScript("OnClick", function() Safe(QuickStart) end)
    f.quickNote = NewText(f, 10, 0.5, 0.5, 0.5)
    f.quickNote:SetPoint("LEFT", f.quickStart, "RIGHT", 10, 0)
    f.quickNote:SetWidth(w - 370)
    f.quickNote:SetJustifyH("LEFT")
    f.quickNote:SetText("Takes the set as it is. Nothing is asked.")

    -- Hover casting: one of three, each a button with what it means under it.
    f.hoverModes = {}
    for i, mode in ipairs(HOVER_MODES) do
        local y = -104 - (i - 1) * 68
        local pick = NewButton(f, 280, 26, mode.text)
        pick:SetPoint("TOPLEFT", 0, y)
        pick:SetScript("OnClick", function()
            hoverPick = mode.id
            Refresh()
        end)
        pick.mark = NewText(f, 11, ACCENT[1], ACCENT[2], ACCENT[3])
        pick.mark:SetPoint("LEFT", pick, "RIGHT", 10, 0)
        pick.mark:SetText("Picked")
        pick.note = NewText(f, 10, 0.7, 0.7, 0.7)
        pick.note:SetPoint("TOPLEFT", 0, y - 30)
        pick.note:SetWidth(w)
        pick.note:SetJustifyH("LEFT")
        pick.note:SetText(mode.note)
        pick.id = mode.id
        f.hoverModes[i] = pick
    end
    f.hoverFoot = NewText(f, 10, 0.6, 0.6, 0.6)
    f.hoverFoot:SetPoint("TOPLEFT", 0, -312)
    f.hoverFoot:SetWidth(w)
    f.hoverFoot:SetJustifyH("LEFT")
    f.hoverFoot:SetText("This is about keyboard keys, the wheel and extra mouse buttons (the fourth and up). Left, right and "
        .. "middle click stay on unit frames, with or without Shift, Ctrl or Alt: the game needs them in the world. "
        .. "A single key can be set either way later: Bindings tab, click the key.")

    -- Your side buttons: a box per button of the block, and a wide box that
    -- hears the key or mouse button pressed for the one being asked about.
    f.sideBoxes = {}
    for n = 1, SIDE_BUTTONS do
        local col, row = (n - 1) % 3, math.floor((n - 1) / 3)
        local box = NewButton(f, 170, 26)
        box:SetPoint("TOPLEFT", col * 174, -112 - row * 30)
        box.label:ClearAllPoints()
        box.label:SetPoint("LEFT", 8, 0)
        box:SetScript("OnClick", function()
            sideAt, sideHeard = n, nil
            Refresh()
        end)
        box:SetScript("OnEnter", nil)           -- the lit state says which one is being asked for
        box:SetScript("OnLeave", nil)
        f.sideBoxes[n] = box
    end
    f.sideCatch = NewButton(f, 518, 36)
    f.sideCatch:SetPoint("TOPLEFT", 0, -240)
    f.sideCatch:RegisterForClicks("AnyUp")
    f.sideCatch.label:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    f.sideCatch:SetScript("OnClick", function(self, mouse)
        if not sideListening then               -- any click starts it hearing the keyboard again
            sideListening, sideHeard = true, nil
            self:EnableKeyboard(true)
            Refresh()
            return
        end
        local n = MOUSE_NUMBER[mouse] or (type(mouse) == "string" and tonumber(mouse:match("^Button(%d+)$")))
        if n then Safe(SideInput, "BUTTON" .. n) end
    end)
    f.sideCatch:SetScript("OnKeyDown", function(self, key)
        if MODIFIER_KEY[key] or not sideListening then return end
        if key == "ESCAPE" then                 -- hands the keyboard back
            sideListening, sideHeard = false, "Not listening. Click the box to carry on."
            self:EnableKeyboard(false)
            Refresh()
            return
        end
        Safe(SideInput, key:upper())
    end)
    f.sideSkip = NewButton(f, 110, 22, "Skip this one")
    f.sideSkip:SetPoint("TOPLEFT", 0, -284)
    f.sideSkip:SetScript("OnClick", function()
        if sideAt <= SIDE_BUTTONS then
            SetSideKey(sideAt, nil)
            sideAt, sideHeard = sideAt + 1, nil
        end
        Refresh()
    end)
    f.sideReset = NewButton(f, 100, 22, "Start over")
    f.sideReset:SetPoint("LEFT", f.sideSkip, "RIGHT", 6, 0)
    f.sideReset:SetScript("OnClick", function()
        ClearSideKeys()
        sideAt, sideHeard = 1, nil
        Refresh()
    end)
    f.sideDefault = NewButton(f, 250, 22, "Mine are mouse buttons 4 to 15")
    f.sideDefault:SetPoint("LEFT", f.sideReset, "RIGHT", 6, 0)
    f.sideDefault:SetScript("OnClick", function()
        ClearSideKeys()
        sideAt, sideHeard = SIDE_BUTTONS + 1, "Taken to be mouse buttons 4 to 15, top row first."
        Refresh()
    end)
    f.sideHeard = NewText(f, 11, ACCENT[1], ACCENT[2], ACCENT[3])
    f.sideHeard:SetPoint("TOPLEFT", 0, -318)
    f.sideHeard:SetWidth(w)
    f.sideHeard:SetJustifyH("LEFT")

    -- Step 2: one row per button, with a switch per modifier. The button's
    -- name switches the whole row.
    f.rows = {}
    f.grid, f.list = NewList(f, -100, 86, w)
    local list = f.list
    local nameW, gap = 150, 4
    local cellW = (w - nameW - gap * #MODS) / #MODS
    for i = 1, MAX_ROWS do
        local row = { cells = {} }
        local y = -(i - 1) * ROW_H
        row.name = NewButton(list, nameW, 22)
        row.name:SetPoint("TOPLEFT", 0, y)
        row.name.label:ClearAllPoints()
        row.name.label:SetPoint("LEFT", 6, 0)
        row.name:SetScript("OnClick", function()
            if not (row.input and chosen) then return end
            local all = true
            for _, mod in ipairs(MODS) do
                if not chosen[mod.prefix .. row.input] then all = false end
            end
            for _, mod in ipairs(MODS) do chosen[mod.prefix .. row.input] = (not all) or nil end
            BuildKeys()
            Refresh()
        end)
        for m, mod in ipairs(MODS) do
            local cell = NewButton(list, cellW, 22, mod.text)
            cell:SetPoint("TOPLEFT", nameW + gap + (m - 1) * (cellW + gap), y)
            cell:SetScript("OnClick", function()
                if not (row.input and chosen) then return end
                local key = mod.prefix .. row.input
                chosen[key] = (not chosen[key]) or nil
                BuildKeys()
                Refresh()
            end)
            -- The lit state is the switch; the usual hover colour would hide it.
            cell:SetScript("OnEnter", nil)
            cell:SetScript("OnLeave", nil)
            row.cells[m] = cell
        end
        f.rows[i] = row
    end
    -- Extra mouse buttons: clicked on the left box, they join the list.
    -- Keyboard keys: click the right box, then press the key.
    f.heard = NewText(f, 10, ACCENT[1], ACCENT[2], ACCENT[3])
    f.heard:SetPoint("BOTTOMLEFT", 0, 70)
    f.more = NewButton(f, w / 2 - 3, 30)
    f.more:SetPoint("BOTTOMLEFT", 0, 34)
    f.more:RegisterForClicks("AnyUp")
    f.more:SetScript("OnClick", function(_, mouse) Safe(HeardButton, mouse) end)
    f.more.label:SetText("More mouse buttons? Click them here")
    f.keyBox = NewButton(f, w / 2 - 3, 30)
    f.keyBox:SetPoint("BOTTOMRIGHT", 0, 34)
    f.keyBox:SetScript("OnClick", function(self)
        if not chosen then return end
        listening = not listening
        self:EnableKeyboard(listening)
        heard = nil
        Refresh()
    end)
    f.keyBox:SetScript("OnKeyDown", function(_, key) Safe(HeardKey, key) end)

    -- Step 3: every chosen key on a line of its own, the three sides beside it.
    local keyNameW, keyGap = 140, 4
    local keyCellW = (w - keyNameW - keyGap * (#SLOTS - 1)) / #SLOTS
    f.keyHeads = {}
    for s, slot in ipairs(SLOTS) do
        local head = NewText(f, 11, slot.color[1], slot.color[2], slot.color[3])
        head:SetPoint("TOPLEFT", keyNameW + (s - 1) * (keyCellW + keyGap) + 2, -98)
        head:SetText(slot.text)
        f.keyHeads[s] = head
    end
    f.keyGrid, f.keyList = NewList(f, -116, 74, w)
    f.keyLines = {}
    f.NewKeyLine = function() return NewKeyLine(f, w, keyNameW, keyCellW, keyGap) end
    f.note = NewText(f, 10, 0.95, 0.55, 0.3)
    f.note:SetPoint("BOTTOMLEFT", 0, 34)
    f.note:SetWidth(w)
    f.note:SetJustifyH("LEFT")

    -- Step 4: the options most people ask about, each a switch with a line
    -- of explanation.
    f.opts = {}
    local function Option(id, y, onClick)
        local opt = {}
        opt.button = NewButton(f, 46, 22)
        opt.button:SetPoint("TOPLEFT", 0, y)
        opt.button:SetScript("OnClick", function() Safe(onClick); Refresh() end)
        opt.label = NewText(f, 12)
        opt.label:SetPoint("LEFT", opt.button, "RIGHT", 8, 0)
        opt.note = NewText(f, 10, 0.6, 0.6, 0.6)
        opt.note:SetPoint("TOPLEFT", 54, y - 23)
        opt.note:SetWidth(w - 54)
        opt.note:SetJustifyH("LEFT")
        function opt.SetShown(shown)
            opt.button:SetShown(shown); opt.label:SetShown(shown); opt.note:SetShown(shown)
        end
        f.opts[id] = opt
        return opt
    end
    Option("spec", -100, function()
        local _, _, own = SpecState()
        SetSpecOnly(not own)
    end)
    Option("down", -156, function()
        local settings = CastSettings()
        if settings then SetCastDown(not settings.down) end
    end)
    Option("picture", -212, function()
        SetSettings({ layout = db.layout == "mouse" and "horizontal" or "mouse" })
    end)
    Option("tooltip", -268, function()
        SetSettings({ tooltip = not db.tooltip })
    end)

    -- Step 5: the summary. The button says what a click on it does; the
    -- line beside it says how things stand.
    f.enable = NewButton(f, 200, 28)
    f.enable:SetPoint("TOPLEFT", 0, -130)
    f.enable:SetScript("OnClick", function()
        local settings = CastSettings()
        if settings then SetCastEnabled(not settings.enabled); Refresh() end
    end)
    f.state = NewText(f, 12)
    f.state:SetPoint("LEFT", f.enable, "RIGHT", 12, 0)
    -- What is different from now on: the plain clicks, and keys taken from the game.
    f.changes = NewText(f, 11, 0.85, 0.85, 0.85)
    f.changes:SetPoint("TOPLEFT", 0, -176)
    f.changes:SetWidth(w)
    f.changes:SetJustifyH("LEFT")

    f.back = NewButton(f, 80, 24, "Back")
    f.back:SetPoint("BOTTOMLEFT", 0, 0)
    f.back:SetScript("OnClick", function() Go(page - 1) end)
    f.next = NewButton(f, 130, 28)
    f.next.label:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    f.next:SetPoint("BOTTOMRIGHT", 0, 0)
    f.next:SetScript("OnClick", function()
        if page >= Last() then
            Close()
        elseif quick and PageName() == "side" then
            Go(Last())                          -- the short way picks up where it left off
        else
            Go(page + 1)
        end
    end)
    f.skip = NewButton(f, 110, 24, "Skip to the end")
    f.skip:SetPoint("RIGHT", f.next, "LEFT", -6, 0)
    f.skip:SetScript("OnClick", function() Go(Last()) end)
    return f
end

-------------------------------------------------------------------------------
--  Showing a page
-------------------------------------------------------------------------------
local function ShowSlot(b, key, slot)
    local action = SlotAction(key, slot.id)
    if action then
        local entry = ActionEntry(action)
        local rank = action.pinned and RankText(action.spellID)
        b.label:SetText(entry.name .. (rank and ("  (" .. rank .. ")") or ""))
        b.label:SetTextColor(1, 1, 1)
        b.icon:SetTexture(entry.icon)
        b.icon:Show()
    else
        b.label:SetText(slot.id == "dead" and "Nothing special" or "Nothing")
        b.label:SetTextColor(0.5, 0.5, 0.5)
        b.icon:Hide()
    end
end

local function ShowButtons(f, shown)
    local inputs = shown and Inputs() or {}
    for i, row in ipairs(f.rows) do
        local input = inputs[i]
        row.input = input
        row.name:SetShown(input ~= nil)
        if input then row.name.label:SetText(LongKey(input)) end
        for m, mod in ipairs(MODS) do
            row.cells[m]:SetShown(input ~= nil)
            if input then Lit(row.cells[m], chosen[mod.prefix .. input]) end
        end
    end
    f.grid:SetShown(shown)
    f.list:SetHeight(#inputs * ROW_H > 10 and #inputs * ROW_H or 10)
    f.more:SetShown(shown)
    f.keyBox:SetShown(shown)
    f.heard:SetShown(shown)
    if shown then
        f.heard:SetText(heard or "")
        f.keyBox.label:SetText(listening and "Press the key (Esc cancels)" or "Add a keyboard key")
    end
end

local function ShowKeys(f, shown)
    f.keyGrid:SetShown(shown)
    f.note:SetShown(shown)
    for _, head in ipairs(f.keyHeads) do head:SetShown(shown) end
    local count = shown and #keys or 0
    for i = 1, (count > #f.keyLines) and count or #f.keyLines do
        local line = f.keyLines[i]
        local key = shown and keys[i] or nil
        if key then
            if not line then
                line = f.NewKeyLine()
                f.keyLines[i] = line
            end
            line.key = key
            line.name:SetText(KeyName(key))
            line.Place(i)
            line.SetShown(true)
            for s, slot in ipairs(SLOTS) do ShowSlot(line.cells[s], key, slot) end
        elseif line then
            line.key = nil
            line.SetShown(false)
        end
    end
    f.keyList:SetHeight(count * ROW_H > 10 and count * ROW_H or 10)
    if shown then
        local known = false
        for _, key in ipairs(keys) do known = known or key == noteKey end
        local _, input = ParseKey(known and noteKey or "")
        f.note:SetText(known and (KEY_NOTE[input] or (not input:match("^BUTTON%d+$") and HOVER_NOTE)) or "")
    end
end

local function ShowSide(f, shown)
    for _, box in ipairs(f.sideBoxes) do box:SetShown(shown) end
    f.sideCatch:SetShown(shown); f.sideSkip:SetShown(shown); f.sideReset:SetShown(shown)
    f.sideDefault:SetShown(shown); f.sideHeard:SetShown(shown)
    if not shown then return end
    local side = SideKeys()
    for n, box in ipairs(f.sideBoxes) do
        box.label:SetText(n .. ":  " .. (side[n] and LongKey(side[n]) or "not shown yet"))
        Lit(box, n == sideAt)
        if n ~= sideAt and side[n] then box.label:SetTextColor(1, 1, 1) end
    end
    f.sideCatch.label:SetText(not sideListening and "Click here to carry on"
        or sideAt > SIDE_BUTTONS and "Done. Click a box above to change one."
        or ("Press side button " .. sideAt .. " now"))
    f.sideHeard:SetText(sideHeard or "")
end

-- The key of the set in use whose first rule does `kind` ("target", "menu")
-- for everyone, by name; nil when there is none.
local function KeyThatDoes(kind)
    local set = ActiveSet()
    for _, binding in ipairs(set and set.bindings or {}) do
        local rule = binding.rules[1]
        if rule and rule.action.type == kind and next(rule.when) == nil then return KeyName(binding.key) end
    end
    return nil
end

-- "1 (Action Button 1), 2 (Action Button 2) and 3 more": the game's key
-- bindings that keys working anywhere have taken over. "" when there are none.
local function TakenText()
    local taken = Shadowed()
    local parts = {}
    for i = 1, #taken < 4 and #taken or 4 do
        parts[i] = taken[i].key .. " (" .. taken[i].action .. ")"
    end
    if #parts == 0 then return "" end
    return table.concat(parts, ", ") .. (#taken > 4 and (" and " .. (#taken - 4) .. " more") or "")
end

-- What the player has to know before the first click: a plain click that now
-- casts, and where targeting and the menu went; keys the game no longer has.
local PLAIN_CLICKS = {
    { key = "BUTTON1", name = "Left click", kind = "target", does = "targets" },
    { key = "BUTTON2", name = "Right click", kind = "menu", does = "opens the menu" },
}
local function ChangesText(on)
    local out = {}
    for _, click in ipairs(PLAIN_CLICKS) do
        local action = SlotAction(click.key, "ally")
        if action and action.type ~= click.kind then
            local other = KeyThatDoes(click.kind)
            out[#out + 1] = click.name .. " on an ally is now " .. ActionEntry(action).name .. ". "
                .. (other and (other .. " " .. click.does .. ".") or ("No key of this set " .. click.does .. " any more."))
        end
    end
    local taken = TakenText()
    if taken ~= "" then
        out[#out + 1] = "Keys that work anywhere are ClickLegend's all the time. The game had these on them: " .. taken .. "."
    end
    if not on and ns.CastBlocked() then out[#out + 1] = ns.CastBlocked() end
    if on then
        local provider = ClickLegendAPI and ClickLegendAPI.provider
        local waiting = provider and provider.Pending and provider.Pending()
        out[#out + 1] = waiting and "You are in combat: the keys start working when it ends."
            or "Try it: click your own unit frame."
    end
    return table.concat(out, "\n")
end

local function ShowOptions(f, shown)
    for _, opt in pairs(f.opts) do opt.SetShown(false) end
    if not shown then return end
    local function Set(opt, on, label, note)
        opt.SetShown(true)
        opt.button.label:SetText(on and "On" or "Off")
        if on then
            opt.button.label:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
        else
            opt.button.label:SetTextColor(0.6, 0.6, 0.6)
        end
        opt.label:SetText(label)
        opt.note:SetText(note)
    end
    local specID, specName, own = SpecState()
    if specID then
        Set(f.opts.spec, own, "Use this set for " .. specName .. " only",
            "On: your other specs keep the set they had, and each can be given its own. Off: every spec uses this set.")
    end
    local settings = CastSettings()
    Set(f.opts.down, settings and settings.down, "Cast as the mouse button goes down",
        "On: a click on a unit frame casts at once. Off: when you let the button go, as the game does.")
    if db then
        Set(f.opts.picture, db.layout == "mouse", "Show the legend as one large picture of your mouse",
            "On: a large mouse with each button's spells beside it. Off: rows of spell icons, a small mouse above each.")
        Set(f.opts.tooltip, db.tooltip, "List your bindings in unit tooltips",
            "On: the tooltip of a unit frame under the cursor lists what each key does there. Off: tooltips are left alone.")
    end
end

-- The hover casting page: the three ways, the one in force marked.
local function ShowHover(f, shown)
    local now = shown and HoverMode()
    for _, pick in ipairs(f.hoverModes) do
        pick:SetShown(shown); pick.note:SetShown(shown)
        pick.mark:SetShown(shown and pick.id == now)
        if shown then
            Lit(pick, pick.id == now)
            if pick.id ~= now then pick.label:SetTextColor(0.85, 0.85, 0.85) end
        end
    end
    f.hoverFoot:SetShown(shown)
    if not shown then return end
    -- Said here, before it is switched on for good: the keys this takes from the game.
    local taken = now ~= "frames" and TakenText() or ""
    f.note:SetText(taken ~= "" and ("The game had these on your keys: " .. taken .. ".") or "")
    f.note:SetShown(taken ~= "")
end

Refresh = function()
    local f = panel
    if not f then return end
    ApplyHover()                        -- a key added since the pick is treated the same
    local name = PageName()
    local onStart, onSide, onButtons = name == "start", name == "side", name == "buttons"
    local onHover = name == "hover"
    local onKeys, onOptions, onEnd = name == "keys", name == "options", name == "done"
    f.step:SetText("Step " .. page .. " of " .. Last())
    local value = start or DefaultStart()
    f.start:SetShown(onStart); f.startLabel:SetShown(onStart)
    f.mouse:SetShown(onStart); f.mouseLabel:SetShown(onStart); f.mouseNote:SetShown(onStart)
    ShowSide(f, onSide)
    f.quickStart:SetShown(onStart and value ~= "empty")
    f.quickNote:SetShown(onStart and value ~= "empty")
    f.nextNote:SetShown(onStart)
    f.enable:SetShown(onEnd); f.state:SetShown(onEnd); f.changes:SetShown(onEnd)
    ShowButtons(f, onButtons)
    ShowKeys(f, onKeys)
    ShowOptions(f, onOptions)
    ShowHover(f, onHover)
    f.back:SetShown(not onStart)
    f.skip:SetShown(not onStart and not onEnd)
    f.next.label:SetText(onEnd and "Finish" or "Next  >")

    if onStart then
        f.head:SetText("Where to start")
        f.text:SetText("Pick a ready-made set for your class, the set you already use, or nothing.")
        f.start.label:SetText(StartText(value))
        f.mouse.label:SetText(MOUSE_LAYOUTS[MousePick()].name)
    elseif onSide then
        f.head:SetText("Your side buttons")
        f.text:SetText("Press each of the twelve side buttons in turn: top row first, left to right. "
            .. "That shows ClickLegend what each one sends, so that every spell is drawn beside the right button.")
    elseif onHover then
        f.head:SetText("Hover casting")
        f.text:SetText("Should your keys cast only on unit frames, or on any unit the cursor is on? Pick one.")
    elseif onButtons then
        f.head:SetText("Your buttons")
        f.text:SetText("Switch on what you want to set up: each button on its own (Plain) and with Shift, Ctrl or Alt. "
            .. "Click a button's name for the whole row. " .. #keys .. " switched on.")
    elseif onKeys then
        f.head:SetText("What they do")
        f.text:SetText(#keys > 0 and ("Click a box to pick what the key does there; type to search your spells. "
                .. "Leave a box on Nothing if you do not want the key for that.")
            or "Nothing is switched on. Go back and switch on the buttons you want to set up.")
    elseif onOptions then
        f.head:SetText("Options")
        f.text:SetText("Things people often ask for. Leave them as they are if you are not sure; "
            .. "all of them can be changed later in the Bindings tab.")
    else
        local set, name = ActiveSet()
        local settings = CastSettings()
        local on = settings and settings.enabled
        f.head:SetText("Done")
        f.text:SetText((name and (name .. " has " .. #set.bindings .. " keys. ") or "")
            .. "The Bindings tab lists them: click a key there to change it, or to add rules for combat, forms and more. "
            .. "Undo takes back the last change.")
        f.enable.label:SetText(on and "Turn click casting off" or "Turn click casting on")
        f.state:SetText(on and "Click casting is on." or "Click casting is off.")
        if on then
            f.enable.label:SetTextColor(0.75, 0.75, 0.75)
            f.state:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
        else
            f.enable.label:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
            f.state:SetTextColor(0.75, 0.75, 0.75)
        end
        f.changes:SetText(ChangesText(on))
    end
end

-- Opens the guided setup over the Bindings tab, at its first page.
local function OpenWizard(parent, w)
    if not panel then panel = Build(parent, w) end
    page, start, chosen, keys, heard, typedKeys, listening, noteKey = 1, nil, nil, {}, nil, {}, false, nil
    sideAt, sideHeard, sideListening, quick = NextSide(1), nil, false, false
    hoverPick = nil
    panel.keyBox:EnableKeyboard(false)
    panel.sideCatch:EnableKeyboard(false)
    panel:Show()
    Safe(Refresh)
end

local function WizardShown()
    return panel ~= nil and panel:IsShown()
end

-------------------------------------------------------------------------------
--  Used by the other files
-------------------------------------------------------------------------------
ns.CloseWizard   = CloseWizard
ns.GetWizard     = function() return panel end
ns.OpenWizard    = OpenWizard
ns.RefreshWizard = function() if WizardShown() then Safe(Refresh) end end
ns.WizardShown   = WizardShown
