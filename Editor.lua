-------------------------------------------------------------------------------
--  ClickLegend - Editor.lua
--  The Bindings tab of the settings window: switch ClickLegend's own click
--  casting on, pick or make a set, and edit its keys and their rules.
--
--  Screen only. Every change goes through Cast.lua (ns.CastEdit and friends),
--  which also brings the frames and the legend up to date.
-------------------------------------------------------------------------------
local _, ns = ...

local ipairs, pairs, type, tostring, pcall = ipairs, pairs, type, tostring, pcall
local max = math.max

local ACCENT, Clamp, HeldMods, Safe =
    ns.ACCENT, ns.Clamp, ns.HeldMods, ns.Safe
local ApplyFont, NewButton, NewText =
    ns.ApplyFont, ns.NewButton, ns.NewText
local ACTION_NAME, ActionEntry, ActiveSet, CastConflicts =
    ns.ACTION_NAME, ns.ActionEntry, ns.ActiveSet, ns.CastConflicts
local Edit, KeyName, CastSettings, CompileBinding =
    ns.CastEdit, ns.CastKeyName, ns.CastSettings, ns.CompileBinding
local ConditionValue, CopySet, DeleteSet, NewSet =
    ns.ConditionValue, ns.CopySet, ns.DeleteSet, ns.NewSet
local SelectSet, SetCastEnabled, SetCastFrames, SetNames =
    ns.SelectSet, ns.SetCastEnabled, ns.SetCastFrames, ns.SetNames
local CastChanged, ShowMenu, CloseMenu =
    ns.CastChanged, ns.ShowMenu, ns.CloseMenu
local ListForms, ListItems, ListMacros, ListSpells =
    ns.ListForms, ns.ListItems, ns.ListMacros, ns.ListSpells
local ACTION_ORDER, CONDITION_VALUES, RankText =
    ns.ACTION_ORDER, ns.CONDITION_VALUES, ns.RankText
local AddSet, BuildTemplate, ExportSet, ImportSet =
    ns.AddSet, ns.BuildTemplate, ns.ExportSet, ns.ImportSet
local ListTemplates, RuleUnavailable, RenameSet =
    ns.ListTemplates, ns.RuleUnavailable, ns.RenameSet

local ROW_H, RULE_H = 26, 56
local MACRO_LIMIT = 255

-- What the condition buttons say. The key is the editor value from Cast.lua.
local CONDITIONS = {
    { field = "reaction", tip = "Who the key is used on.",
      text = { [false] = "Anyone", help = "Ally", harm = "Enemy" } },
    { field = "dead", tip = "Whether that unit is alive. Use Dead for a resurrection on the same key.",
      text = { [false] = "Any life", alive = "Alive", dead = "Dead" } },
    { field = "combat", tip = "Whether you are in combat.",
      text = { [false] = "Any time", ["in"] = "In combat", out = "No combat" } },
    { field = "form", tip = "Your stance or shapeshift form. 0 is no form.",
      text = { [false] = "Any form" } },
    { field = "pet", tip = "Whether you have a pet out.",
      text = { [false] = "Pet or not", pet = "Have pet", nopet = "No pet" } },
    { field = "mod", tip = "An extra modifier held with the key, on top of the key's own.",
      text = { [false] = "No extra", shift = "+Shift", ctrl = "+Ctrl", alt = "+Alt" } },
}
local KIND_TEXT = {
    spell = "Spell", item = "Item", macro = "Macro", target = "Target", focus = "Focus",
    assist = "Assist", menu = "Menu", trinket1 = "Trinket 1", trinket2 = "Trinket 2",
}
local NAMED = { spell = true, item = true, macro = true }
local MOUSE_KEY = { LeftButton = "BUTTON1", RightButton = "BUTTON2", MiddleButton = "BUTTON3" }
local MODIFIER_KEY = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
    LMETA = true, RMETA = true,
}

local panel                     -- the tab's frame, built on first use
local editing = nil             -- index of the key whose rules are shown, or nil for the list
local naming = nil              -- "new" | "copy" while a set name is being typed
local capture = nil             -- "add" | "change" while waiting for a key
local message = nil             -- one line of feedback under the set row

local Refresh                   -- defined below

local function Tip(frame, text)
    frame:SetScript("OnEnter", function(self)
        if self.bg then self.bg:SetColorTexture(0.26, 0.28, 0.31, 1) end
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function(self)
        if self.bg then self.bg:SetColorTexture(0.16, 0.17, 0.19, 1) end
        if GameTooltip then GameTooltip:Hide() end
    end)
end

local function Say(ok, why)
    message = (not ok and why) or nil
    Refresh()
end

local function OnOff(button, on)
    button.label:SetText(on and "On" or "Off")
    if on then
        button.label:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    else
        button.label:SetTextColor(0.6, 0.6, 0.6)
    end
end

-------------------------------------------------------------------------------
--  Lists to pick from
-------------------------------------------------------------------------------
-- A condition's values, the one in use marked. Forms carry the character's
-- own stance or form names.
local function ConditionItems(spec, current)
    local items, forms = {}, nil
    if spec.field == "form" then
        forms = {}
        for _, form in ipairs(ListForms()) do forms[form.index] = form end
    end
    for _, value in ipairs(CONDITION_VALUES[spec.field]) do
        local text, icon = spec.text[value], nil
        if not text then
            local form = forms and forms[value]
            if value == 0 then
                text = "No form"
            elseif form then
                text, icon = value .. ": " .. form.name, form.icon
            elseif not forms or #forms == 0 then
                text = "Form " .. value
            end
        end
        if text then items[#items + 1] = { text = text, value = value, icon = icon, current = value == current } end
    end
    return items
end

local function KindItems(current)
    local items = {}
    for _, kind in ipairs(ACTION_ORDER) do
        items[#items + 1] = { text = KIND_TEXT[kind], value = kind, current = kind == current }
    end
    return items
end

-- The spells, macros or usable items of this character, as actions.
local function ChoiceItems(kind)
    local items = {}
    if kind == "spell" then
        for _, spell in ipairs(ListSpells()) do
            items[#items + 1] = {
                text = spell.name, icon = spell.icon, note = spell.lowRank and spell.rank or nil,
                value = { type = "spell", name = spell.name, spellID = spell.id, pinned = spell.lowRank },
            }
        end
    elseif kind == "macro" then
        for _, macro in ipairs(ListMacros()) do
            items[#items + 1] = { text = macro.name, icon = macro.icon, value = { type = "macro", name = macro.name } }
        end
    elseif kind == "item" then
        for _, item in ipairs(ListItems()) do
            items[#items + 1] = { text = item.name, icon = item.icon,
                value = { type = "item", name = item.name, itemID = item.id } }
        end
    end
    return items
end

local CHOICE_HINT = { spell = "Choose a spell", item = "Choose an item", macro = "Choose a macro" }

local function NewScroll(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(10, 10)
    scroll:SetScrollChild(content)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = max(0, (content:GetHeight() or 0) - (self:GetHeight() or 0))
        self:SetVerticalScroll(Clamp((self:GetVerticalScroll() or 0) - delta * 40, 0, range))
    end)
    return scroll, content
end

local function NewEditBox(parent, w)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetSize(w, 20)
    box:SetAutoFocus(false)
    box:SetFont(STANDARD_TEXT_FONT, 11, "")
    box:SetTextInsets(5, 5, 0, 0)
    box:SetMaxLetters(60)
    box.bg = box:CreateTexture(nil, "BACKGROUND")
    box.bg:SetAllPoints()
    box.bg:SetColorTexture(0, 0, 0, 0.6)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return box
end

-- A rule in words: "Ally, Dead: Rebirth". For the tooltip of a key in the list.
local function RuleLine(rule)
    local words = {}
    for _, spec in ipairs(CONDITIONS) do
        local value = ConditionValue(rule.when, spec.field)
        if value ~= false then words[#words + 1] = spec.text[value] or ("Form " .. tostring(value)) end
    end
    local action = rule.action
    local what = (NAMED[action.type] and not (action.name or action.spellID or action.itemID)) and "nothing chosen yet"
        or ActionEntry(action).name
    local rank = action.pinned and RankText(action.spellID)
    return (#words > 0 and table.concat(words, ", ") or "Anyone") .. ": " .. what .. (rank and (" (" .. rank .. " only)") or "")
end

-- Every rule of a key, in order: { text, skipped }.
local function KeyRuleLines(binding)
    local lines = {}
    for i, rule in ipairs(binding.rules) do
        lines[i] = { text = i .. ". " .. RuleLine(rule), skipped = RuleUnavailable(rule) }
    end
    return lines
end

local function ShowKeyTooltip(row)
    local set = ActiveSet()
    local binding = set and row.index and set.bindings[row.index]
    if not (binding and GameTooltip and GameTooltip.SetOwner) then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(KeyName(binding.key), ACCENT[1], ACCENT[2], ACCENT[3])
    for _, line in ipairs(KeyRuleLines(binding)) do
        if line.skipped then
            GameTooltip:AddLine(line.text .. "  (not known: skipped)", 0.55, 0.55, 0.55)
        else
            GameTooltip:AddLine(line.text, 1, 1, 1)
        end
    end
    GameTooltip:AddLine("The first rule that fits is the one that fires.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

-------------------------------------------------------------------------------
--  Waiting for a key: the next key press, mouse button or wheel turn over
--  the window becomes the key. Escape cancels.
-------------------------------------------------------------------------------
local function Captured(key)
    local mode = capture
    capture = nil
    panel.catcher:Hide()
    if not key then Refresh(); return end
    local keyStr = HeldMods() .. key
    if mode == "change" and editing then
        Say(Edit.SetKey(editing, keyStr))
    else
        local ok, result = Edit.AddBinding(keyStr)
        if ok then editing = result end
        Say(ok, result)
    end
end

local function StartCapture(mode)
    capture = mode
    message = nil
    panel.catcher:Show()
    Refresh()
end

-------------------------------------------------------------------------------
--  Rows
-------------------------------------------------------------------------------
-- One key in the list: its name, what it does on an ally and on an enemy.
local function NewKeyRow(parent, w)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(w, ROW_H)
    row.key = NewText(row, 12)
    row.key:SetPoint("LEFT")
    row.key:SetWidth(96)
    row.key:SetJustifyH("LEFT")
    row.what = NewText(row, 11, 0.8, 0.8, 0.8)
    row.what:SetPoint("LEFT", 100, 0)
    row.what:SetWidth(w - 100 - 122)
    row.what:SetJustifyH("LEFT")
    row:EnableMouse(true)                       -- hovering the row lists every rule of the key
    row:SetScript("OnEnter", function(self) Safe(ShowKeyTooltip, self) end)
    row:SetScript("OnLeave", function() if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end end)
    row.remove = NewButton(row, 22, 20, "X")
    row.remove:SetPoint("RIGHT")
    row.remove:SetScript("OnClick", function()
        if row.index then Say(Edit.RemoveBinding(row.index)) end
    end)
    row.edit = NewButton(row, 46, 20, "Edit")
    row.edit:SetPoint("RIGHT", row.remove, "LEFT", -4, 0)
    row.edit:SetScript("OnClick", function()
        editing, message = row.index, nil
        Refresh()
    end)
    row.down = NewButton(row, 20, 20, "v")
    row.down:SetPoint("RIGHT", row.edit, "LEFT", -4, 0)
    row.down:SetScript("OnClick", function()
        if row.index then Say(Edit.MoveBinding(row.index, 1)) end
    end)
    row.up = NewButton(row, 20, 20, "^")
    row.up:SetPoint("RIGHT", row.down, "LEFT", -2, 0)
    row.up:SetScript("OnClick", function()
        if row.index then Say(Edit.MoveBinding(row.index, -1)) end
    end)
    return row
end

local function DropOnto(row)
    if not (GetCursorInfo and row.index and editing) then return end
    local ok, kind, a, b, c = pcall(GetCursorInfo)
    if not ok or not kind then return end
    if Edit.SetActionFromCursor(editing, row.index, kind, a, b, c) and ClearCursor then ClearCursor() end
end

-- One rule: its six conditions on the first line, what it does on the second.
local function NewRuleRow(parent, w)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(w, RULE_H)
    row.number = NewText(row, 11, ACCENT[1], ACCENT[2], ACCENT[3])
    row.number:SetPoint("TOPLEFT", 0, -5)
    row.conditions = {}
    local cw = (w - 16 - 5 * 2) / 6
    for i, c in ipairs(CONDITIONS) do
        local b = NewButton(row, cw, 20)
        b:SetPoint("TOPLEFT", 16 + (i - 1) * (cw + 2), 0)
        ApplyFont(b.label, 10)                   -- six of these share one line
        b.label:SetWidth(cw - 2)
        b:SetScript("OnClick", function(self)
            if not (row.index and editing) then return end
            ShowMenu(self, ConditionItems(c, row.values[c.field]), function(value)
                Say(Edit.SetCondition(editing, row.index, c.field, value))
            end, { width = 130 })
        end)
        Tip(b, c.tip)
        row.conditions[i] = b
    end
    row.values = {}
    row.kind = NewButton(row, 70, 20)
    row.kind:SetPoint("TOPLEFT", 16, -24)
    row.kind:SetScript("OnClick", function(self)
        if not (row.index and editing) then return end
        ShowMenu(self, KindItems(row.kindNow), function(kind)
            Say(Edit.SetActionType(editing, row.index, kind))
        end, { width = 110 })
    end)
    Tip(row.kind, "What this rule does.")

    -- The spell, item or macro: a button showing the choice, which opens a
    -- list to search and pick from. Something dragged from the spellbook,
    -- bags or macro window can be dropped on it too.
    local choice = NewButton(row, w - 16 - 70 - 4 - 70, 20)
    choice:SetPoint("LEFT", row.kind, "RIGHT", 4, 0)
    choice.icon = choice:CreateTexture(nil, "ARTWORK")
    choice.icon:SetSize(16, 16)
    choice.icon:SetPoint("LEFT", 3, 0)
    choice.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    choice.label:ClearAllPoints()
    choice.label:SetPoint("LEFT", 24, 0)
    choice.label:SetPoint("RIGHT", -4, 0)
    choice.label:SetJustifyH("LEFT")
    choice:RegisterForDrag("LeftButton")
    choice:SetScript("OnReceiveDrag", function() Safe(DropOnto, row) end)
    choice:SetScript("OnClick", function(self)
        if not (row.index and editing) then return end
        if GetCursorInfo and GetCursorInfo() then Safe(DropOnto, row); return end
        local kind = row.kindNow
        ShowMenu(self, ChoiceItems(kind), function(action)
            Say(Edit.SetAction(editing, row.index, action))
        end, {
            width = 230, search = true,
            -- A name that is not in the list (a spell not learned yet, an item in the bags).
            typed = function(text)
                return { text = 'Use "' .. text .. '"', value = { type = kind, name = text }, note = "typed" }
            end,
        })
    end)
    Tip(choice, "Click to pick from a list (type to search), or drop a spell, item or macro here. "
        .. "Picking a lower rank of a spell casts exactly that rank.")
    row.choice = choice
    row.fixed = NewText(row, 11, 0.8, 0.8, 0.8)         -- for actions with nothing to choose
    row.fixed:SetPoint("LEFT", row.kind, "RIGHT", 8, 0)

    row.remove = NewButton(row, 20, 20, "X")
    row.remove:SetPoint("TOPRIGHT", 0, -24)
    row.remove:SetScript("OnClick", function()
        if row.index and editing then Say(Edit.RemoveRule(editing, row.index)) end
    end)
    row.down = NewButton(row, 20, 20, "v")
    row.down:SetPoint("RIGHT", row.remove, "LEFT", -2, 0)
    row.down:SetScript("OnClick", function()
        if row.index and editing then Say(Edit.MoveRule(editing, row.index, 1)) end
    end)
    row.up = NewButton(row, 20, 20, "^")
    row.up:SetPoint("RIGHT", row.down, "LEFT", -2, 0)
    row.up:SetScript("OnClick", function()
        if row.index and editing then Say(Edit.MoveRule(editing, row.index, -1)) end
    end)
    Tip(row.up, "Rules are tried from the top. The first one that fits is the one that fires.")
    return row
end

-------------------------------------------------------------------------------
--  Building the tab
-------------------------------------------------------------------------------
local function Build(parent, w)
    local f = CreateFrame("Frame", nil, parent)
    f.w = w

    -- Line 1: on or off.
    f.enable = NewButton(f, 46, 20)
    f.enable:SetPoint("TOPLEFT", 0, 0)
    f.enable:SetScript("OnClick", function()
        local settings = CastSettings()
        if settings then message = nil; SetCastEnabled(not settings.enabled) end
    end)
    Tip(f.enable, "On: clicks and keys on unit frames cast the bindings below. "
        .. "Off: ClickLegend only shows bindings and changes nothing.")
    local enableText = NewText(f, 12)
    enableText:SetPoint("LEFT", f.enable, "RIGHT", 8, 0)
    enableText:SetText("ClickLegend click casting")
    f.guide = NewButton(f, 96, 20, "Guided setup")
    f.guide:SetPoint("TOPRIGHT", 0, 0)
    f.guide:SetScript("OnClick", function() ns.OpenWizard(parent, w) end)      -- Wizard.lua
    Tip(f.guide, "Goes through the usual keys one at a time and asks what each should do on an ally, "
        .. "a dead ally and an enemy. Starts from a ready-made set for your class if you like.")
    f.status = NewText(f, 10, 0.6, 0.6, 0.6)
    f.status:SetPoint("BOTTOMRIGHT", 0, 0)

    -- Line 2: the set.
    local setText = NewText(f, 12)
    setText:SetPoint("TOPLEFT", 0, -33)
    setText:SetText("Set")
    f.set = NewButton(f, 150, 20)
    f.set:SetPoint("TOPLEFT", 30, -28)
    f.set:SetScript("OnClick", function(self)
        local _, current = ActiveSet()
        local items = {}
        for _, name in ipairs(SetNames()) do
            items[#items + 1] = { text = name, value = name, current = name == current }
        end
        if #items == 0 then return end
        ShowMenu(self, items, function(name)
            editing, message = nil, nil
            SelectSet(name)
        end, { width = 150 })
    end)
    Tip(f.set, "The set of bindings this character uses. Sets are shared by all your characters.")
    -- New: an empty set, or one that starts from a template for a class.
    f.new = NewButton(f, 60, 20, "New...")
    f.new:SetPoint("LEFT", f.set, "RIGHT", 4, 0)
    f.new:SetScript("OnClick", function(self)
        local items = { { text = "Empty set", value = "empty" } }
        local templates, class = ListTemplates()
        for _, template in ipairs(templates) do
            items[#items + 1] = { text = template.name, value = template,
                note = template.class == class and "your class" or nil }
        end
        ShowMenu(self, items, function(value)
            if value == "empty" then
                naming, message = "new", nil
                Refresh()
                f.nameBox:SetFocus()
                return
            end
            local name = AddSet(value.name, BuildTemplate(value))
            if name then
                editing = nil
                SelectSet(name)
                Say(false, name .. " made from the template. Rules for spells you do not know are skipped; change anything you like.")
            end
        end, { width = 230 })
    end)
    Tip(f.new, "Make a set: empty, or starting from a template for a class.")

    -- More: what can be done with the set in use.
    f.more = NewButton(f, 60, 20, "More...")
    f.more:SetPoint("LEFT", f.new, "RIGHT", 4, 0)
    f.more:SetScript("OnClick", function(self)
        local _, name = ActiveSet()
        local items = { { text = "Import a set from text", value = "import" } }
        if name then
            table.insert(items, 1, { text = "Rename this set", value = "rename" })
            table.insert(items, 2, { text = "Copy this set", value = "copy" })
            table.insert(items, 3, { text = "Export this set as text", value = "export" })
            items[#items + 1] = { text = "Delete this set", value = "delete" }
        end
        ShowMenu(self, items, function(value)
            message = nil
            if value == "delete" then
                if f.confirmDelete ~= name then
                    f.confirmDelete = name
                    Say(false, "Pick Delete again to remove the set " .. name .. " for every character.")
                    return
                end
                f.confirmDelete = nil
                DeleteSet(name)
                editing = nil
                local names = SetNames()
                if names[1] then SelectSet(names[1]) else CastChanged() end
                Say(true)
                return
            end
            naming = value
            Refresh()
            if value == "export" then
                f.nameBox:SetText(ExportSet(name) or "")
                f.nameBox:HighlightText()
            elseif value == "rename" then
                f.nameBox:SetText(name)
                f.nameBox:HighlightText()
            end
            f.nameBox:SetFocus()
        end, { width = 190 })
    end)

    -- A text box that takes the place of line 3 while it is needed: a name for
    -- a new set or a copy, the text of an export, or the text to import.
    f.nameBox = NewEditBox(f, f.w - 100)
    f.nameBox:SetPoint("TOPLEFT", 0, -56)
    f.nameBox:SetMaxLetters(0)
    f.nameOk = NewButton(f, 44, 20, "OK")
    f.nameOk:SetPoint("LEFT", f.nameBox, "RIGHT", 4, 0)
    f.nameCancel = NewButton(f, 44, 20, "Close")
    f.nameCancel:SetPoint("LEFT", f.nameOk, "RIGHT", 4, 0)
    local function NameClose()
        naming, message = nil, nil
        f.nameBox:SetText("")
        f.nameBox:ClearFocus()
    end
    local function NameDone()
        local mode, text = naming, f.nameBox:GetText()
        NameClose()
        local ok, name, why
        if mode == "copy" or mode == "rename" then
            local _, current = ActiveSet()
            ok, name = (mode == "copy" and CopySet or RenameSet)(current, text)
            why = "Type a name that is not already used."
        elseif mode == "import" then
            name, why = ImportSet(text)
            ok = name and true or false
        elseif mode == "new" then
            ok, name = NewSet(text)
            why = "Type a name that is not already used."
        else
            Refresh()                -- export: nothing to do but close
            return
        end
        if ok then
            editing = nil
            SelectSet(name)
            Say(true)
        else
            Say(false, why)
        end
    end
    f.nameOk:SetScript("OnClick", NameDone)
    f.nameCancel:SetScript("OnClick", function() NameClose(); Refresh() end)
    f.nameBox:SetScript("OnEnterPressed", NameDone)
    f.nameBox:SetScript("OnEscapePressed", function() NameClose(); Refresh() end)

    -- Line 3: which frames.
    f.blizzard = NewButton(f, 46, 20)
    f.blizzard:SetPoint("TOPLEFT", 0, -56)
    f.blizzard:SetScript("OnClick", function()
        local settings = CastSettings()
        if settings then SetCastFrames("blizzard", not settings.frames.blizzard) end
    end)
    f.blizzardText = NewText(f, 11)
    f.blizzardText:SetPoint("LEFT", f.blizzard, "RIGHT", 6, 0)
    f.blizzardText:SetText("Game's unit frames")
    f.registered = NewButton(f, 46, 20)
    f.registered:SetPoint("TOPLEFT", w / 2, -56)
    f.registered:SetScript("OnClick", function()
        local settings = CastSettings()
        if settings then SetCastFrames("registered", not settings.frames.registered) end
    end)
    Tip(f.registered, "Unit frames from other addons that offer themselves for click casting, EllesmereUI's among them.")
    f.registeredText = NewText(f, 11)
    f.registeredText:SetPoint("LEFT", f.registered, "RIGHT", 6, 0)
    f.registeredText:SetText("Other addons' frames")

    -- Feedback and warnings.
    f.notice = NewText(f, 10, 0.95, 0.55, 0.3)
    f.notice:SetPoint("TOPLEFT", 0, -82)
    f.notice:SetWidth(w)
    f.notice:SetJustifyH("LEFT")

    -- The list of keys.
    f.listHead = NewText(f, 11, ACCENT[1], ACCENT[2], ACCENT[3])
    f.listHead:SetPoint("TOPLEFT", 0, -124)
    f.add = NewButton(f, 170, 20)
    f.add:SetPoint("TOPRIGHT", 0, -119)
    f.add:SetScript("OnClick", function()
        if capture then Captured(nil) else StartCapture(editing and "change" or "add") end
    end)
    f.back = NewButton(f, 50, 20, "Back")
    f.back:SetPoint("RIGHT", f.add, "LEFT", -4, 0)
    f.back:SetScript("OnClick", function() editing, message = nil, nil; Refresh() end)

    f.listScroll, f.listContent = NewScroll(f)
    f.listScroll:SetPoint("TOPLEFT", 0, -146)
    f.listScroll:SetPoint("BOTTOMRIGHT", 0, 14)
    f.listContent:SetSize(w, 10)
    f.keyRows = {}
    f.empty = NewText(f, 11, 0.6, 0.6, 0.6)
    f.empty:SetPoint("TOPLEFT", 0, -150)
    f.empty:SetWidth(w)
    f.empty:SetJustifyH("LEFT")

    -- One key's rules.
    f.ruleScroll, f.ruleContent = NewScroll(f)
    f.ruleScroll:SetPoint("TOPLEFT", 0, -146)
    f.ruleScroll:SetPoint("BOTTOMRIGHT", 0, 44)
    f.ruleContent:SetSize(w, 10)
    f.ruleRows = {}
    f.addRule = NewButton(f, 80, 20, "Add a rule")
    f.addRule:SetPoint("BOTTOMLEFT", 0, 20)
    f.addRule:SetScript("OnClick", function()
        if editing then Say(Edit.AddRule(editing)) end
    end)
    Tip(f.addRule, "Rules are tried from the top; the first that fits fires. "
        .. "A rule whose spell you do not know is skipped, so the next one takes over.")
    f.room = NewText(f, 10, 0.6, 0.6, 0.6)
    f.room:SetPoint("LEFT", f.addRule, "RIGHT", 8, 0)
    f.problems = NewText(f, 10, 0.95, 0.4, 0.4)
    f.problems:SetPoint("BOTTOMLEFT", 0, 0)
    f.problems:SetWidth(w)
    f.problems:SetJustifyH("LEFT")

    -- Catches the next key, click or wheel turn while a key is being picked.
    local catcher = CreateFrame("Button", nil, f)
    catcher:SetAllPoints(parent)
    catcher:SetFrameLevel((f:GetFrameLevel() or 1) + 20)
    catcher:EnableKeyboard(true)
    catcher:EnableMouseWheel(true)
    catcher:RegisterForClicks("AnyUp")
    catcher:Hide()
    catcher:SetScript("OnKeyDown", function(_, key)
        if key == "ESCAPE" then Captured(nil) elseif not MODIFIER_KEY[key] then Captured(key) end
    end)
    catcher:SetScript("OnClick", function(_, mouse)
        Captured(MOUSE_KEY[mouse] or (type(mouse) == "string" and mouse:upper()) or nil)
    end)
    catcher:SetScript("OnMouseWheel", function(_, delta)
        Captured(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN")
    end)
    f.catcher = catcher
    return f
end

-------------------------------------------------------------------------------
--  Showing the current state
-------------------------------------------------------------------------------
-- What a key mostly does on a side, for the list of keys: the first rule for
-- a living unit of that side whose spell the character has; failing that, the
-- first rule for the side at all.
local function RuleSummary(binding, side)
    local other = side == "ally" and "harm" or "help"
    local fallback
    for _, rule in ipairs(binding.rules) do
        if rule.when.reaction ~= other and (rule.action.name or not NAMED[rule.action.type]) then
            if rule.when.dead ~= true and not RuleUnavailable(rule) then return ActionEntry(rule.action).name end
            fallback = fallback or rule
        end
    end
    return fallback and ActionEntry(fallback.action).name or "-"
end

local function ShowList(f, set)
    f.ruleScroll:Hide(); f.addRule:Hide(); f.room:Hide(); f.problems:Hide(); f.back:Hide()
    for _, row in ipairs(f.ruleRows) do row:Hide() end
    f.listScroll:Show(); f.status:Show()
    f.listHead:SetText("KEYS")
    f.add.label:SetText(capture and "Press a key or button (Esc)" or "Add a key")
    local count = set and #set.bindings or 0
    for i = 1, max(count, #f.keyRows) do
        local row = f.keyRows[i]
        local binding = set and set.bindings[i]
        if binding then
            if not row then
                row = NewKeyRow(f.listContent, f.w)
                f.keyRows[i] = row
            end
            row.index = i
            row.key:SetText(KeyName(binding.key))
            local ally, enemy = RuleSummary(binding, "ally"), RuleSummary(binding, "enemy")
            row.what:SetText(ally == enemy and ally or (ally .. "  /  " .. enemy))
            row.up:SetShown(i > 1)
            row.down:SetShown(i < count)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", f.listContent, "TOPLEFT", 0, -(i - 1) * ROW_H)
            row:Show()
        elseif row then
            row:Hide()
        end
    end
    f.listContent:SetHeight(max(10, count * ROW_H))
    f.empty:SetShown(count == 0)
    f.empty:SetText(set and "No keys yet. Press Add a key, then press the key or mouse button to bind (hold Shift, Ctrl or Alt with it)."
        or "Press Guided setup to be taken through it, or New... to make a set yourself. "
            .. "A set holds the keys for one kind of character, and any of your characters can use it.")
end

local function ShowRules(f, binding)
    f.listScroll:Hide(); f.empty:Hide(); f.status:Hide()
    for _, row in ipairs(f.keyRows) do row:Hide() end
    f.ruleScroll:Show(); f.addRule:Show(); f.room:Show(); f.problems:Show(); f.back:Show()
    f.listHead:SetText(KeyName(binding.key))
    f.add.label:SetText(capture and "Press a key or button (Esc)" or "Change the key")
    local count = #binding.rules
    for i = 1, max(count, #f.ruleRows) do
        local row = f.ruleRows[i]
        local rule = binding.rules[i]
        if rule then
            if not row then
                row = NewRuleRow(f.ruleContent, f.w)
                f.ruleRows[i] = row
            end
            row.index = i
            row.number:SetText(tostring(i))
            for c, spec in ipairs(CONDITIONS) do
                local value = ConditionValue(rule.when, spec.field)
                row.values[spec.field] = value
                local button = row.conditions[c]
                button.label:SetText(spec.text[value] or ("Form " .. tostring(value)))
                if value == false then
                    button.label:SetTextColor(0.55, 0.55, 0.55)
                else
                    button.label:SetTextColor(1, 1, 1)
                end
            end
            local action = rule.action
            row.kind.label:SetText(KIND_TEXT[action.type] or "?")
            row.kindNow = action.type
            local named = NAMED[action.type] and true or false
            local chosen = named and (action.name or action.spellID or action.itemID) and true or false
            row.choice:SetShown(named)
            if chosen then
                local entry = ActionEntry(action)
                local rank = action.pinned and RankText(action.spellID)
                row.shown = entry.name .. (rank and ("  (" .. rank .. " only)") or (action.pinned and "  (this rank only)" or ""))
                row.choice.icon:SetTexture(entry.icon)
                row.choice.icon:Show()
                if RuleUnavailable(rule) then
                    row.shown = row.shown .. "  (not known: skipped)"
                    row.choice.label:SetTextColor(0.55, 0.55, 0.55)
                else
                    row.choice.label:SetTextColor(1, 1, 1)
                end
            elseif named then
                row.shown = CHOICE_HINT[action.type]
                row.choice.icon:Hide()
                row.choice.label:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
            else
                row.shown = nil
            end
            row.choice.label:SetText(row.shown or "")
            row.fixed:SetShown(not named)
            row.fixed:SetText(not named and (ACTION_NAME[action.type] or "") or "")
            row.up:SetShown(i > 1)
            row.down:SetShown(i < count)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", f.ruleContent, "TOPLEFT", 0, -(i - 1) * RULE_H)
            row:Show()
        elseif row then
            row:Hide()
        end
    end
    f.ruleContent:SetHeight(max(10, count * RULE_H))
    local compiled = CompileBinding(binding)
    f.room:SetText(compiled.length and (compiled.length .. " of " .. MACRO_LIMIT .. " characters used") or "")
    local lines = {}
    for _, problem in ipairs(compiled.problems) do lines[#lines + 1] = problem end
    if compiled.skipped > 0 then
        lines[#lines + 1] = compiled.skipped .. " rule(s) skipped: you do not know the spell."
    end
    f.problems:SetText(table.concat(lines, " "))
end

Refresh = function()
    CloseMenu()
    local f = panel
    local settings = CastSettings()
    if not (f and settings) then return end
    local set, name = ActiveSet()
    if editing and not (set and set.bindings[editing]) then editing = nil end

    OnOff(f.enable, settings.enabled)
    OnOff(f.blizzard, settings.frames.blizzard)
    OnOff(f.registered, settings.frames.registered)
    f.set.label:SetText(name or (settings.set and (settings.set .. " (missing)")) or "No set")
    if f.confirmDelete and f.confirmDelete ~= name then f.confirmDelete = nil end

    local showName = naming ~= nil
    f.nameBox:SetShown(showName); f.nameOk:SetShown(showName and naming ~= "export"); f.nameCancel:SetShown(showName)
    if naming == "export" then
        message = "Press Ctrl+C to copy the text, then Close. Anyone can bring it in with More, Import."
    elseif naming == "import" then
        message = "Paste the text with Ctrl+V and press OK. It comes in as a new set."
    elseif naming then
        message = "Type a name for the set and press OK."
    end
    f.blizzard:SetShown(not showName); f.blizzardText:SetShown(not showName)
    f.registered:SetShown(not showName); f.registeredText:SetShown(not showName)

    local provider = ClickLegendAPI and ClickLegendAPI.provider
    local status = ""
    if settings.enabled and provider and provider.Started() then
        local frames, bound = provider.Count()
        status = provider.Pending() and "changes apply after combat" or (bound .. " of " .. frames .. " frames bound")
    end
    f.status:SetText(status)

    local notes = {}
    if message then notes[#notes + 1] = message end
    if settings.enabled then
        for _, conflict in ipairs(CastConflicts()) do notes[#notes + 1] = conflict end
    end
    f.notice:SetText(table.concat(notes, "\n"))

    f.add:SetShown(set ~= nil)
    if editing then ShowRules(f, set.bindings[editing]) else ShowList(f, set) end
end

-- Called by Window.lua: the tab's frame, made on first use, filling `parent`.
local function GetEditor(parent, w)
    if not panel then
        panel = Build(parent, w)
        panel:SetAllPoints(parent)
    end
    return panel
end

local function RefreshEditor()
    if panel and panel:IsShown() then Safe(Refresh) end
end

-------------------------------------------------------------------------------
--  Used by the other files
-------------------------------------------------------------------------------
ns.GetEditor     = GetEditor
ns.KeyRuleLines  = KeyRuleLines
ns.RefreshEditor = RefreshEditor
