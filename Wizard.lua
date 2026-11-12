-------------------------------------------------------------------------------
--  ClickLegend - Wizard.lua
--  Guided setup: another way into the Bindings tab.
--    1. Where to start: a starter set, the set in use, or nothing.
--    2. Your buttons: every mouse button and the wheel, each with Plain,
--       Shift, Ctrl and Alt switches. Extra mouse buttons are added by
--       clicking them, keyboard keys by pressing them. Only what is switched
--       on is walked through.
--    3. One page per chosen key: what it does on an ally, on a dead ally and
--       on an enemy.
--    4. Done: a summary and the on/off switch.
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

-- The modifiers a button can be walked through with, most used first; the
-- walk goes through every button plain, then with Shift, and so on.
local MODS = {
    { prefix = "", text = "Plain" }, { prefix = "SHIFT-", text = "Shift" },
    { prefix = "CTRL-", text = "Ctrl" }, { prefix = "ALT-", text = "Alt" },
}
local FIXED_INPUTS = { "BUTTON1", "BUTTON2", "BUTTON3", "MOUSEWHEELUP", "MOUSEWHEELDOWN" }
local MAX_ROWS = 24                 -- the list scrolls
local ROW_H = 24
local HOVER_NOTE = "A keyboard key only does this while the cursor is on a unit frame; elsewhere it does its usual job."
local MODIFIER_KEY = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
    LMETA = true, RMETA = true,
}
local SLOTS = {
    { id = "ally", text = "On an ally" },
    { id = "dead", text = "On a dead ally" },
    { id = "enemy", text = "On an enemy" },
}
local KEY_NOTE = {
    BUTTON1 = "Left click normally targets the unit. If you put a spell on it for allies, "
        .. "keep Target for enemies, and put Target on another key so you can still select an ally.",
    BUTTON2 = "Right click normally opens the unit's menu. If you put a spell on it for allies, "
        .. "keep Menu for enemies, and put Menu on another key.",
    MOUSEWHEELUP = "The wheel only does this while the cursor is on a unit frame; elsewhere it zooms as usual.",
    MOUSEWHEELDOWN = "The wheel only does this while the cursor is on a unit frame; elsewhere it zooms as usual.",
}
local SPECIAL = { "target", "menu", "focus", "assist", "trinket1", "trinket2" }
local MOUSE_NUMBER = { LeftButton = 1, RightButton = 2, MiddleButton = 3 }

local panel
local page = 1
local start = nil                   -- what page 1 has picked: "keep" | "empty" | a template
local chosen = nil                  -- [key string] = true: the keys to walk through; nil until page 2 is reached
local keys = {}                     -- the chosen keys in walking order
local heard = nil                   -- feedback from the last click on the "more buttons" box
local typedKeys = {}                -- keyboard keys added during this run, or bound in the set
local listening = false             -- waiting for a keyboard key to add
local Refresh

-------------------------------------------------------------------------------
--  Lists
-------------------------------------------------------------------------------
local function StartItems()
    local items = {}
    local _, name = ActiveSet()
    if name then items[#items + 1] = { text = "The set in use: " .. name, value = "keep" } end
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
--  The buttons and the keys to walk through
-------------------------------------------------------------------------------
-- Left, right, middle, the wheel, then the extra mouse buttons this player has
-- shown ClickLegend, lowest first.
local function Inputs()
    local list = {}
    for i, key in ipairs(FIXED_INPUTS) do list[i] = key end
    for _, n in ipairs(KnownButtons()) do list[#list + 1] = "BUTTON" .. n end
    for _, key in ipairs(typedKeys) do list[#list + 1] = key end
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

local function Last() return #keys + 3 end      -- start, buttons, the keys, done

-------------------------------------------------------------------------------
--  Moving through the pages
-------------------------------------------------------------------------------
-- Leaving the first page makes the set it picked.
local function ApplyStart()
    local value = start or DefaultStart()
    if value == "keep" and ActiveSet() then return true end
    local name
    if type(value) == "table" then
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

local function Go(to)
    CloseMenu()
    heard, listening = nil, false
    if panel then panel.keyBox:EnableKeyboard(false) end
    if page == 1 and to > 1 and not ApplyStart() then return end
    if to >= 2 then
        if not chosen then SeedChosen() end
        BuildKeys()
    end
    local last = to >= 2 and Last() or 2
    page = to < 1 and 1 or (to > last and last or to)
    Refresh()
end

-- Hides it. Window.lua calls this when the window closes or the tab changes.
local function CloseWizard()
    listening = false
    if panel then
        panel.keyBox:EnableKeyboard(false)
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

    -- Page 1: where to start from.
    f.start = NewButton(f, w, 24)
    f.start:SetPoint("TOPLEFT", 0, -130)
    f.start:SetScript("OnClick", function(self)
        ShowMenu(self, StartItems(), function(value)
            start = value
            Refresh()
        end, { width = w })
    end)

    -- Page 2: one row per button, with a switch per modifier. The button's
    -- name switches the whole row.
    f.rows = {}
    local grid = CreateFrame("ScrollFrame", nil, f)
    grid:SetPoint("TOPLEFT", 0, -100)
    grid:SetPoint("BOTTOMRIGHT", 0, 86)
    local list = CreateFrame("Frame", nil, grid)
    list:SetSize(w, 10)
    grid:SetScrollChild(list)
    grid:EnableMouseWheel(true)
    grid:SetScript("OnMouseWheel", function(self, delta)
        local range = (list:GetHeight() or 0) - (self:GetHeight() or 0)
        if range < 0 then range = 0 end
        local to = (self:GetVerticalScroll() or 0) - delta * ROW_H * 2
        self:SetVerticalScroll(to < 0 and 0 or (to > range and range or to))
    end)
    f.grid, f.list = grid, list
    local nameW, gap = 110, 4
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

    -- Key pages: one line per slot.
    f.slots = {}
    for i, slot in ipairs(SLOTS) do
        local label = NewText(f, 12)
        label:SetPoint("TOPLEFT", 0, -130 - (i - 1) * 34 - 5)
        label:SetText(slot.text)
        local b = NewButton(f, w - 110, 24)
        b:SetPoint("TOPLEFT", 110, -130 - (i - 1) * 34)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(18, 18)
        b.icon:SetPoint("LEFT", 3, 0)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.label:ClearAllPoints()
        b.label:SetPoint("LEFT", 26, 0)
        b.label:SetPoint("RIGHT", -4, 0)
        b.label:SetJustifyH("LEFT")
        b:SetScript("OnClick", function(self)
            local key = keys[page - 2]
            if not key then return end
            ShowMenu(self, ActionItems(slot.id), function(action)
                Edit.SetSlot(key, slot.id, action or nil)
                Refresh()
            end, { width = w - 110, search = true })
        end)
        f.slots[i] = { label = label, button = b }
    end
    f.note = NewText(f, 10, 0.95, 0.55, 0.3)
    f.note:SetPoint("TOPLEFT", 0, -240)
    f.note:SetWidth(w)
    f.note:SetJustifyH("LEFT")

    -- Summary page.
    f.enable = NewButton(f, 200, 24)
    f.enable:SetPoint("TOPLEFT", 0, -240)
    f.enable:SetScript("OnClick", function()
        local settings = CastSettings()
        if settings then SetCastEnabled(not settings.enabled); Refresh() end
    end)

    f.back = NewButton(f, 80, 24, "Back")
    f.back:SetPoint("BOTTOMLEFT", 0, 0)
    f.back:SetScript("OnClick", function() Go(page - 1) end)
    f.next = NewButton(f, 100, 24)
    f.next:SetPoint("BOTTOMRIGHT", 0, 0)
    f.next:SetScript("OnClick", function()
        if page >= 2 and page == Last() then Close() else Go(page + 1) end
    end)
    f.skip = NewButton(f, 110, 24, "Skip to the end")
    f.skip:SetPoint("RIGHT", f.next, "LEFT", -6, 0)
    f.skip:SetScript("OnClick", function() Go(Last()) end)
    return f
end

-------------------------------------------------------------------------------
--  Showing a page
-------------------------------------------------------------------------------
local function ShowSlot(row, key, slot)
    local action = SlotAction(key, slot.id)
    local b = row.button
    if action then
        local entry = ActionEntry(action)
        local rank = action.pinned and RankText(action.spellID)
        b.label:SetText(entry.name .. (rank and ("  (" .. rank .. " only)") or ""))
        b.label:SetTextColor(1, 1, 1)
        b.icon:SetTexture(entry.icon)
        b.icon:Show()
    else
        b.label:SetText(slot.id == "dead" and "Nothing special" or "Nothing")
        b.label:SetTextColor(0.55, 0.55, 0.55)
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

Refresh = function()
    local f = panel
    if not f then return end
    local onStart, onButtons = page == 1, page == 2
    local last = page >= 2 and Last() or nil
    local onEnd = last ~= nil and page == last
    local key = (not onButtons and not onEnd) and keys[page - 2] or nil
    f.step:SetText(last and ("Step " .. page .. " of " .. last) or "Step 1")
    f.start:SetShown(onStart)
    f.enable:SetShown(onEnd)
    f.note:SetShown(key ~= nil)
    ShowButtons(f, onButtons)
    for i, slot in ipairs(SLOTS) do
        local row = f.slots[i]
        row.label:SetShown(key ~= nil)
        row.button:SetShown(key ~= nil)
        if key then ShowSlot(row, key, slot) end
    end
    f.back:SetShown(not onStart)
    f.skip:SetShown(not onStart and not onEnd)
    f.next.label:SetText(onEnd and "Finish" or "Next")

    if onStart then
        f.head:SetText("Where to start")
        f.text:SetText("Pick a ready-made set for your class, the set you already use, or nothing. "
            .. "Next you choose which buttons to set up, and then each one is asked about in turn.")
        f.start.label:SetText(StartText(start or DefaultStart()))
    elseif onButtons then
        f.head:SetText("Your buttons")
        f.text:SetText("Switch on what you want to set up: each button on its own (Plain) and with Shift, Ctrl or Alt. "
            .. "Click a button's name for the whole row. " .. #keys .. " to go through.")
    elseif key then
        local _, input = ParseKey(key)
        f.head:SetText(KeyName(key))
        f.text:SetText("Choose what this key does. Click a line to pick from a list; type to search your spells. "
            .. "Leave a line on Nothing if you do not want the key for that.")
        f.note:SetText(KEY_NOTE[input] or (not input:match("^BUTTON%d+$") and HOVER_NOTE) or "")
    else
        local set, name = ActiveSet()
        local settings = CastSettings()
        local on = settings and settings.enabled
        f.head:SetText("Done")
        f.text:SetText((name and (name .. " has " .. #set.bindings .. " keys. ") or "")
            .. "The Bindings tab lists them, and there you can add rules for combat, forms and more.")
        f.enable.label:SetText(on and "Click casting is on" or "Turn click casting on")
        if on then
            f.enable.label:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
        else
            f.enable.label:SetTextColor(1, 1, 1)
        end
    end
end

-- Opens the guided setup over the Bindings tab, at its first page.
local function OpenWizard(parent, w)
    if not panel then panel = Build(parent, w) end
    page, start, chosen, keys, heard, typedKeys, listening = 1, nil, nil, {}, nil, {}, false
    panel.keyBox:EnableKeyboard(false)
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
