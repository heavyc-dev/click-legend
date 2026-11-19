-------------------------------------------------------------------------------
--  ClickLegend - Editor.lua
--  The Bindings tab of the settings window: switch ClickLegend's own click
--  casting on, pick or make a set, and edit its keys and their rules.
--
--  Two panes. Left: the keys of the set. Right: the rules of the key picked
--  on the left, or the Quickbind list, or a few words on where to begin.
--
--  Screen only. Every change goes through Cast.lua (ns.CastEdit and friends),
--  which also brings the frames and the legend up to date.
-------------------------------------------------------------------------------
local _, ns = ...

local ipairs, pairs, type, tostring, pcall = ipairs, pairs, type, tostring, pcall
local max = math.max

local Skin, Clamp, HeldMods, Safe =
    ns.Skin, ns.Clamp, ns.HeldMods, ns.Safe
local ACCENT = Skin.ACCENT
local NewButton, NewText = ns.NewButton, ns.NewText
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
local CopyFromSource, CopySources = ns.CopyFromSource, ns.CopySources
local BoundKeys, PresetSpell, SetSpecOnly, SpecState =
    ns.BoundKeys, ns.PresetSpell, ns.SetSpecOnly, ns.SpecState
local PRE_ORDER, SetCastDown, CanUndo, Undo =
    ns.PRE_ORDER, ns.SetCastDown, ns.CastCanUndo, ns.CastUndo

-- What "Add a rule" offers, by the ids of RECIPE_ORDER in Cast.lua.
local RECIPE_TEXT = {
    ally = "Heal or help an ally", enemy = "Damage an enemy", rez = "Resurrect a dead ally",
    self = "Else, cast on myself", target = "Cast on my target", focus = "Cast on my focus",
    targettarget = "Cast on my target's target", pet = "Cast on my pet",
    blank = "A blank rule (set the conditions yourself)",
}

local LEFT_W, GAP, TOP = 230, 12, 134           -- the keys pane, the space beside it, where the panes begin
local SWITCH_Y = 106                            -- the line of switches above the panes
local ROW_H, RULE_H, QUICK_H = 24, 52, 22
local MACRO_LIMIT = 255
local ROOM_WARN = 200                           -- the room a key uses is only shown past this

-- The conditions of a rule. The key of `text` is the editor value from
-- Cast.lua; `add` is what the condition is called in the list of ones to add.
local CONDITIONS = {
    { field = "reaction", add = "Ally or enemy", tip = "Who the key is used on.",
      text = { [false] = "Anyone", help = "Ally", harm = "Enemy" } },
    { field = "dead", add = "Alive or dead", tip = "Whether that unit is alive. Use Dead for a resurrection on the same key.",
      text = { [false] = "Any life", alive = "Alive", dead = "Dead" } },
    { field = "combat", add = "In or out of combat", tip = "Whether you are in combat.",
      text = { [false] = "Any time", ["in"] = "In combat", out = "No combat" } },
    { field = "form", add = "Stance or form", tip = "Your stance or shapeshift form. 0 is no form.",
      text = { [false] = "Any form" } },
    { field = "pet", add = "Pet out or not", tip = "Whether you have a pet out.",
      text = { [false] = "Pet or not", pet = "Have pet", nopet = "No pet" } },
    { field = "mod", add = "Extra modifier held", tip = "An extra modifier held with the key, on top of the key's own.",
      text = { [false] = "No extra", shift = "+Shift", ctrl = "+Ctrl", alt = "+Alt" } },
    { field = "unit", add = "Cast on someone else",
      tip = "Who the rule acts on, instead of the unit under the cursor. Ally, enemy, alive and dead are then about that unit.",
      text = { [false] = "Under cursor", player = "On myself", target = "On my target", focus = "On my focus",
               targettarget = "On target's target", pet = "On my pet" } },
}
local KIND_TEXT = {
    spell = "Spell", item = "Item", macro = "Macro", target = "Target", focus = "Focus",
    assist = "Assist", menu = "Menu", trinket1 = "Trinket 1", trinket2 = "Trinket 2",
    dispel = "Dispel", rez = "Resurrect", text = "Macro text",
}
local NAMED = { spell = true, item = true, macro = true, text = true }
local PRE_TEXT = { stop = "Stop my current cast", trinket1 = "Use trinket 1", trinket2 = "Use trinket 2" }
local TEXT_START = "/cast [@mouseover,help] "
local PRESET = { dispel = true, rez = true }
local MOUSE_KEY = { LeftButton = "BUTTON1", RightButton = "BUTTON2", MiddleButton = "BUTTON3" }
local MODIFIER_KEY = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
    LMETA = true, RMETA = true,
}
local ALLY_COLOR, ENEMY_COLOR = { 0.05, 0.82, 0.62 }, { 0.90, 0.25, 0.25 }

local panel                     -- the tab's frame, built on first use
local editing = nil             -- index of the key whose rules are shown, or nil
local naming = nil              -- "new" | "copy" | ... while the text box under the set row is in use
local capture = nil             -- "add" | "change" while waiting for a key
local message = nil             -- one line of feedback
local quick = false             -- true while the Quickbind list is shown
local quickFilter = ""          -- what is typed in the Quickbind search box
local quickRanks = false        -- lower ranks listed in Quickbind
local hovered = nil             -- the Quickbind row under the cursor
local writing = nil             -- index of the rule whose macro text is being written
local openFirst = false         -- a key was just added: open the list of spells for its first rule
local notes = {}                -- every notice, the first of which is on screen
local confirmDelete = nil       -- name of the set the notice line is asking to delete

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
        button.label:SetTextColor(Skin.ON[1], Skin.ON[2], Skin.ON[3])
    else
        button.label:SetTextColor(0.6, 0.6, 0.6)
    end
end

-------------------------------------------------------------------------------
--  Lists to pick from
-------------------------------------------------------------------------------
-- A condition's values, the one in use marked. Forms carry the character's
-- own stance or form names. `adding` leaves out "does not matter".
local function ConditionItems(spec, current, adding)
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
        if text and not (adding and value == false) then
            items[#items + 1] = { text = text, value = value, icon = icon, current = value == current }
        end
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
-- Lower ranks are left out unless asked for (the same switch as Quickbind's);
-- the last line of the list asks, unless `plain`.
local function ChoiceItems(kind, plain)
    local items = {}
    if kind == "spell" then
        for _, spell in ipairs(ListSpells()) do
            if quickRanks or not spell.lowRank then
                items[#items + 1] = {
                    text = spell.name, icon = spell.icon, note = spell.lowRank and spell.rank or nil,
                    value = { type = "spell", name = spell.name, spellID = spell.id, pinned = spell.lowRank },
                }
            end
        end
        if not plain then
            items[#items + 1] = { text = quickRanks and "Hide lower ranks" or "Show lower ranks too", value = "ranks" }
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

local CHOICE_HINT = { spell = "Choose a spell", item = "Choose an item", macro = "Choose a macro",
                      text = "Write the macro text" }

-- The first line of a rule's macro text, for the button that opens it.
local function FirstLine(text)
    local line = tostring(text):match("^[^\n]*")
    local more = #line < #text
    if #line > 44 then line, more = line:sub(1, 44), true end
    return line .. (more and " ..." or "")
end

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
    ns.AddScrollBar(scroll, content)
    -- A sunken area behind the list, there while the list is.
    local inset = Skin.Inset(parent)
    inset:SetPoint("TOPLEFT", scroll, "TOPLEFT", -3, 3)
    inset:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 9, -3)
    inset:SetShown(scroll:IsShown() and true or false)
    if scroll.HookScript then
        scroll:HookScript("OnShow", function() inset:Show() end)
        scroll:HookScript("OnHide", function() inset:Hide() end)
    end
    return scroll, content
end

local function NewEditBox(parent, w)
    local box = Skin.EditBox(parent, w, 20)
    box:SetMaxLetters(60)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return box
end

-- A line of text that never wraps, with everything it stands for in a
-- tooltip: `lines()` returns what the tooltip lists.
local function NewLine(parent, w, r, g, b, lines)
    local fs = NewText(parent, 10, r, g, b)
    fs:SetWidth(w)
    fs:SetJustifyH("LEFT")
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    local hit = CreateFrame("Frame", nil, parent)
    hit:SetAllPoints(fs)
    hit:EnableMouse(true)
    hit:SetScript("OnEnter", function(self)
        local all = lines()
        if not (GameTooltip and GameTooltip.SetOwner) or #all == 0 then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        for i, line in ipairs(all) do
            if i == 1 then GameTooltip:SetText(line, r, g, b, 1, true) else GameTooltip:AddLine(line, r, g, b, true) end
        end
        GameTooltip:Show()
    end)
    hit:SetScript("OnLeave", function() if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end end)
    fs.hit = hit
    return fs
end

-- A preset in words: "Dispel: Cleanse", or that this character has none.
local function PresetText(action)
    return ACTION_NAME[action.type] .. ": " .. (PresetSpell(action) or "none known on this character")
end

-- What a rule does, in words: "Rebirth", "Rejuvenation (Rank 3 only)".
local function RuleWhat(rule)
    local action = rule.action
    local what = (NAMED[action.type] and not (action.name or action.spellID or action.itemID or action.text)) and "nothing chosen yet"
        or action.type == "text" and FirstLine(action.text)
        or PRESET[action.type] and PresetText(action)
        or ActionEntry(action).name
    local rank = action.pinned and RankText(action.spellID)
    return what .. (rank and (" (" .. rank .. " only)") or "")
end

-- A rule in words: "Ally, Dead: Rebirth". For the tooltip of a key in the list.
local function RuleLine(rule)
    local words = {}
    for _, spec in ipairs(CONDITIONS) do
        local value = ConditionValue(rule.when, spec.field)
        if value ~= false then words[#words + 1] = spec.text[value] or ("Form " .. tostring(value)) end
    end
    return (#words > 0 and table.concat(words, ", ") or "Anyone") .. ": " .. RuleWhat(rule)
end

-- A key read back as a sentence, one part per rule that can fire, in the
-- order they are tried: "Dead ally: Rebirth", "Ally: Rejuvenation",
-- "Otherwise on you: Rejuvenation". It is how a player would say it, so
-- that a key can be checked without thinking in conditions.
local UNIT_WORDS = { player = "you", target = "your target", focus = "your focus",
                     targettarget = "your target's target", pet = "your pet" }
local MOD_WORDS = { shift = "Shift", ctrl = "Ctrl", alt = "Alt" }
local function Sentence(binding)
    local parts = {}
    for i, rule in ipairs(binding.rules) do
        if not RuleUnavailable(rule) then
            local when = rule.when
            local side = when.reaction == "help" and "ally" or when.reaction == "harm" and "enemy" or nil
            local kind = (when.dead == true and "dead " or when.dead == false and "living " or "") .. (side or "")
            kind = kind:gsub(" $", "")
            local who
            if when.unit then
                who = "on " .. UNIT_WORDS[when.unit] .. (kind ~= "" and (" if " .. kind) or "")
            elseif kind == "" then
                who = "anyone"
            else
                who = side and kind or ("anyone " .. kind)
            end
            local more = {}
            if when.combat ~= nil then more[#more + 1] = when.combat and "in combat" or "out of combat" end
            if when.form then more[#more + 1] = "in form " .. when.form end
            if when.pet ~= nil then more[#more + 1] = when.pet and "with a pet" or "without a pet" end
            if when.mod then more[#more + 1] = "with " .. MOD_WORDS[when.mod] end
            -- A rule that fits whatever is there, after others: what is left over.
            local rest = #parts > 0 and #more == 0 and kind == "" and (when.unit == nil or when.unit == "player")
            if rest then who = when.unit and ("otherwise " .. who) or "otherwise" end
            if #more > 0 then who = who .. ", " .. table.concat(more, ", ") end
            parts[#parts + 1] = who:sub(1, 1):upper() .. who:sub(2) .. ": " .. RuleWhat(rule)
        end
    end
    return parts
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
    if binding.hover then GameTooltip:AddLine("Mouseover casting: also works on units in the world.", ACCENT[1], ACCENT[2], ACCENT[3]) end
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
        if ok then
            editing, quick = result, false
            openFirst = true                    -- straight on to choosing its spell
        end
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
-- What a key mostly does on a side: the first rule for a living unit of that
-- side whose spell the character has; failing that, the first rule for the
-- side at all. Nil when the key does nothing on that side.
local function SummaryRule(binding, side)
    local other = side == "ally" and "harm" or "help"
    local fallback
    for _, rule in ipairs(binding.rules) do
        local a = rule.action
        if rule.when.reaction ~= other and (a.name or a.text or not NAMED[a.type]) then
            if rule.when.dead ~= true and not RuleUnavailable(rule) then return rule end
            fallback = fallback or rule
        end
    end
    return fallback
end

local function SummaryName(rule)
    if not rule then return "-" end
    if rule.action.type == "text" then return ACTION_NAME.text end
    return ActionEntry(rule.action).name
end

-- An icon with a thin line under it in the side's colour.
local function NewSideIcon(row, x, color)
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("LEFT", x, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local line = row:CreateTexture(nil, "ARTWORK")
    line:SetSize(16, 2)
    line:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -1)
    line:SetColorTexture(color[1], color[2], color[3], 1)
    icon.line = line
    return icon
end

local function ShowSideIcon(icon, rule)
    if rule then
        icon:SetTexture(ActionEntry(rule.action).icon)
        icon:SetAlpha(1)
        icon.line:SetAlpha(1)
    else
        icon:SetTexture(nil)
        icon:SetAlpha(0)
        icon.line:SetAlpha(0.25)
    end
end

-- One key in the list: its name, and what it does on an ally and on an
-- enemy as two icons. Clicking it shows its rules on the right.
-- A spell, item or macro held on the cursor (dragged from the spellbook,
-- the bags or the macro window) put on a key: it lands where a spell of its
-- kind belongs, as Quickbind does. Returns true when something was held.
local function DropOnKey(keyStr)
    if not (GetCursorInfo and type(keyStr) == "string") then return false end
    local ok, kind, a, b, c = pcall(GetCursorInfo)
    if not ok or not kind then return false end
    local action = ns.CursorAction(kind, a, b, c)
    if not action then return false end
    local done, where = Edit.Quickbind(keyStr, action)
    if done and ClearCursor then ClearCursor() end
    message = done and (KeyName(keyStr) .. ": " .. ActionEntry(action).name .. ", on " .. where .. ".") or where
    if not (panel and panel:IsVisible()) and message then ns.Print(message) end
    Refresh()
    return true
end

local function NewKeyRow(parent, w)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(w, ROW_H)
    row.sel = row:CreateTexture(nil, "BACKGROUND")
    row.sel:SetAllPoints()
    Skin.Bar(row.sel, true)
    row.sel:Hide()
    row.key = NewText(row, 11)
    row.key:SetPoint("LEFT", 4, 0)
    row.key:SetWidth(108)
    row.key:SetJustifyH("LEFT")
    row.key:SetWordWrap(false)                  -- a long name is cut short; the tooltip has it whole
    row.ally = NewSideIcon(row, 116, ALLY_COLOR)
    row.enemy = NewSideIcon(row, 136, ENEMY_COLOR)
    row.edit = row                              -- the whole row is the way in
    row:SetScript("OnClick", function(self)
        local set = ActiveSet()
        local binding = set and self.index and set.bindings[self.index]
        editing, quick, hovered, writing, message = self.index, false, nil, nil, nil
        if binding and DropOnKey(binding.key) then return end      -- a spell was on the cursor
        Refresh()
    end)
    row:SetScript("OnReceiveDrag", function(self)
        local set = ActiveSet()
        local binding = set and self.index and set.bindings[self.index]
        if binding then
            editing, quick, writing = self.index, false, nil
            Safe(DropOnKey, binding.key)
        end
    end)
    row:SetScript("OnEnter", function(self) Safe(ShowKeyTooltip, self) end)
    row:SetScript("OnLeave", function() if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end end)
    row.remove = NewButton(row, 18, 18, "X")
    row.remove:SetPoint("RIGHT", -2, 0)
    row.remove:SetScript("OnClick", function()
        if not row.index then return end
        if editing == row.index then editing = nil elseif editing and editing > row.index then editing = editing - 1 end
        local ok, why = Edit.RemoveBinding(row.index)
        message = ok and "Key removed. Undo brings it back." or why
        Refresh()
    end)
    row.down = NewButton(row, 16, 18, "v")
    row.down:SetPoint("RIGHT", row.remove, "LEFT", -3, 0)
    row.down:SetScript("OnClick", function()
        if not row.index then return end
        if editing == row.index then editing = editing + 1 elseif editing == row.index + 1 then editing = row.index end
        Say(Edit.MoveBinding(row.index, 1))
    end)
    row.up = NewButton(row, 16, 18, "^")
    row.up:SetPoint("RIGHT", row.down, "LEFT", -2, 0)
    row.up:SetScript("OnClick", function()
        if not row.index then return end
        if editing == row.index then editing = editing - 1 elseif editing == row.index - 1 then editing = row.index end
        Say(Edit.MoveBinding(row.index, -1))
    end)
    return row
end

local function DropOnto(row)
    if not (GetCursorInfo and row.index and editing) then return end
    local ok, kind, a, b, c = pcall(GetCursorInfo)
    if not ok or not kind then return end
    if Edit.SetActionFromCursor(editing, row.index, kind, a, b, c) and ClearCursor then ClearCursor() end
end

-- The list of spells, macros or items for a rule; macro text opens its box.
local OpenChoice
OpenChoice = function(row)
    if not (row.index and editing) then return end
    local kind = row.kindNow
    if kind == "text" then
        writing, message = row.index, nil
        Refresh()
        return
    end
    if GetCursorInfo and GetCursorInfo() then Safe(DropOnto, row); return end
    if not CHOICE_HINT[kind] then return end
    ShowMenu(row.choice, ChoiceItems(kind), function(action)
        if action == "ranks" then
            quickRanks = not quickRanks
            OpenChoice(row)                         -- the list again, with or without them
            return
        end
        Say(Edit.SetAction(editing, row.index, action))
    end, {
        width = 250, search = true,
        -- A name that is not in the list (a spell not learned yet, an item in the bags).
        typed = function(text)
            return { text = 'Use "' .. text .. '"', value = { type = kind, name = text }, note = "typed" }
        end,
    })
end

-- One rule. First line: when it applies, as one small button per condition
-- in use, and a button to add another. Second line: what it does.
local function NewRuleRow(parent, w)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(w, RULE_H)
    row.number = NewText(row, 11, ACCENT[1], ACCENT[2], ACCENT[3])
    row.number:SetPoint("TOPLEFT", 0, -5)
    row.conditions, row.values = {}, {}
    for i, c in ipairs(CONDITIONS) do
        local b = NewButton(row, 60, 20)
        Skin.Font(b.label, 10)
        Skin.Plain(b)                           -- a font brings its own color
        b:SetScript("OnClick", function(self)
            if not (row.index and editing) then return end
            ShowMenu(self, ConditionItems(c, row.values[c.field]), function(value)
                Say(Edit.SetCondition(editing, row.index, c.field, value))
            end, { width = 150 })
        end)
        Tip(b, c.tip .. " Pick the first line of the list to take the condition off.")
        row.conditions[i] = b
    end
    row.always = NewText(row, 10, 0.55, 0.55, 0.55)
    row.always:SetText("Always")
    row.addCond = NewButton(row, 82, 20, "+ condition")
    Skin.Font(row.addCond.label, 10)
    row.addCond.label:SetTextColor(0.6, 0.6, 0.6)
    row.addCond:SetScript("OnClick", function(self)
        if not (row.index and editing) then return end
        local items = {}
        for _, c in ipairs(CONDITIONS) do
            if row.values[c.field] == false then items[#items + 1] = { text = c.add, value = c } end
        end
        ShowMenu(self, items, function(c)
            -- Straight on to that condition's values.
            ShowMenu(self, ConditionItems(c, false, true), function(value)
                Say(Edit.SetCondition(editing, row.index, c.field, value))
            end, { width = 150 })
        end, { width = 170 })
    end)
    Tip(row.addCond, "When this rule applies: ally or enemy, alive or dead, in combat, in a form, with a pet, "
        .. "with an extra modifier held. Also who it is cast on, when that is not the unit under the cursor: "
        .. "yourself, your target, your focus. A rule with no condition always applies.")

    row.kind = NewButton(row, 86, 20)
    row.kind:SetPoint("TOPLEFT", 16, -24)
    row.kind:SetScript("OnClick", function(self)
        if not (row.index and editing) then return end
        ShowMenu(self, KindItems(row.kindNow), function(kind)
            Say(Edit.SetActionType(editing, row.index, kind))
        end, { width = 120 })
    end)
    Tip(row.kind, "What this rule does.")

    -- The spell, item or macro: a button showing the choice, which opens a
    -- list to search and pick from. Something dragged from the spellbook,
    -- bags or macro window can be dropped on it too.
    local choice = NewButton(row, w - 16 - 86 - 4 - 64, 20)
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
    choice:SetScript("OnClick", function() Safe(OpenChoice, row) end)
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
    row.down = NewButton(row, 18, 20, "v")
    row.down:SetPoint("RIGHT", row.remove, "LEFT", -2, 0)
    row.down:SetScript("OnClick", function()
        if row.index and editing then Say(Edit.MoveRule(editing, row.index, 1)) end
    end)
    row.up = NewButton(row, 18, 20, "^")
    row.up:SetPoint("RIGHT", row.down, "LEFT", -2, 0)
    row.up:SetScript("OnClick", function()
        if row.index and editing then Say(Edit.MoveRule(editing, row.index, -1)) end
    end)
    Tip(row.up, "Rules are tried from the top. The first one that fits is the one that fires.")
    return row
end

-------------------------------------------------------------------------------
--  Quickbind: the character's spells in a list. Point at one and press a
--  key or a mouse button, with Shift, Ctrl or Alt if wanted, and that spell
--  is on that key. The wheel scrolls the list, so wheel bindings are made
--  with Add a key.
-------------------------------------------------------------------------------
local function QuickItems()
    local items = {
        { text = "Dispel", note = "whichever you know", action = { type = "dispel" } },
        { text = "Resurrect", note = "the combat one in combat", action = { type = "rez" } },
    }
    for _, item in ipairs(items) do item.icon = ActionEntry(item.action).icon end
    for _, spell in ipairs(ListSpells()) do
        if quickRanks or not spell.lowRank then
            items[#items + 1] = {
                text = spell.name, icon = spell.icon, note = spell.lowRank and spell.rank or nil,
                action = { type = "spell", name = spell.name, spellID = spell.id, pinned = spell.lowRank },
            }
        end
    end
    local typed = quickFilter:match("^%s*(.-)%s*$"):lower()
    if typed == "" then return items end
    local shown = {}
    for _, item in ipairs(items) do
        if item.text:lower():find(typed, 1, true) then shown[#shown + 1] = item end
    end
    return shown
end

local function QuickBind(item, key)
    local mods = HeldMods()
    if mods == "" and (key == "BUTTON1" or key == "BUTTON2") then
        message = "Hold Shift, Ctrl or Alt to put left or right click on a spell here. "
            .. "The plain clicks are set in the list of keys."
        Refresh()
        return
    end
    local ok, where = Edit.Quickbind(mods .. key, item.action)
    message = ok and (KeyName(mods .. key) .. ": " .. item.text .. ", on " .. where .. ".") or where
    Refresh()
end

-- While a row is under the cursor the keyboard is the Quickbind's; otherwise
-- keys go on to the game as usual.
local function PassKeys(on)
    local keys = panel and panel.quickKeys
    if keys and keys.SetPropagateKeyboardInput then pcall(keys.SetPropagateKeyboardInput, keys, on) end
end

local function NewQuickRow(parent, w)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(w, QUICK_H)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    Skin.Bar(row.bg, false)
    row.bg:Hide()
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", 3, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.name = NewText(row, 11)
    row.name:SetPoint("LEFT", 24, 0)
    row.note = NewText(row, 10, 0.6, 0.6, 0.6)
    row.note:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
    -- Takes the spell off every key it is on.
    row.clear = NewButton(row, 16, 16, "x")
    row.clear:SetPoint("RIGHT", -2, 0)
    row.clear:SetScript("OnClick", function()
        if not row.item then return end
        local ok = Edit.RemoveAction(row.item.action)
        message = ok and (row.item.text .. " taken off its keys. Undo brings it back.") or nil
        Refresh()
    end)
    -- Puts another spell in its place on every key it is on.
    row.swap = NewButton(row, 16, 16, ">")
    row.swap:SetPoint("RIGHT", row.clear, "LEFT", -2, 0)
    row.swap:SetScript("OnClick", function(self)
        if not row.item then return end
        local item = row.item
        ShowMenu(self, ChoiceItems("spell", true), function(action)
            local count = Edit.ReplaceAction(item.action, action)
            message = count and (item.text .. " is now " .. ActionEntry(action).name .. " on " .. count
                .. (count == 1 and " key" or " keys") .. ". Undo brings it back.") or nil
            Refresh()
        end, { width = 250, search = true })
    end)
    Tip(row.swap, "Another spell in this one's place, on every key it is on.")
    Tip(row.clear, "Takes this spell off every key it is on.")
    row.keys = NewText(row, 10, ACCENT[1], ACCENT[2], ACCENT[3])
    row.keys:SetPoint("RIGHT", row.swap, "LEFT", -4, 0)
    row.keys:SetWidth(140)
    row.keys:SetJustifyH("RIGHT")
    row.keys:SetWordWrap(false)
    row:RegisterForClicks("AnyUp")
    row:SetScript("OnEnter", function(self)
        hovered = self
        self.bg:Show()
        if panel then panel.quickSearch:ClearFocus() end        -- the keys are for binding now
        PassKeys(false)
    end)
    row:SetScript("OnLeave", function(self)
        if hovered == self then hovered = nil end
        self.bg:Hide()
        PassKeys(true)
    end)
    row:SetScript("OnClick", function(self, mouse)
        local key = MOUSE_KEY[mouse] or (type(mouse) == "string" and mouse:upper()) or nil
        if key and self.item then Safe(QuickBind, self.item, key) end
    end)
    return row
end

-------------------------------------------------------------------------------
--  Building the tab
-------------------------------------------------------------------------------
-- "Add a rule": what the key should also do, by name. (Out here, and not
-- in Build: a Lua function can reach 60 outer locals and Build is at that.
-- GetEditor puts it on the button.)
local function AddRuleMenu(self)
    if not editing then return end
    local items = {}
    for _, id in ipairs(ns.RECIPE_ORDER) do items[#items + 1] = { text = RECIPE_TEXT[id], value = id } end
    ShowMenu(self, items, function(id)
        local ok, at, filled = Edit.AddRule(editing, id)
        if ok and not filled then openFirst = at end        -- straight on to choosing its spell
        Say(ok, at)
    end, { width = 250 })
end

-- The switches that are about click casting as a whole, on a line of their
-- own above the panes: which unit frames it works on, whether a click casts
-- as the button goes down, whether a spell cast on an enemy also targets it.
-- Made outside Build, which has no room for another outer local.
local SWITCHES = {
    { id = "blizzard", text = "Game's unit frames",
      tip = "Click casting works on the game's own party, raid, player, target and pet frames." },
    { id = "registered", text = "Other addons' frames",
      tip = "Click casting works on the unit frames of other addons that offer them for it "
          .. "(ElvUI, Grid2, VuhDo with its Clique support on, and others)." },
    { id = "down", text = "Cast on press",
      tip = "A click casts as the button goes down, not when it is let go. A little faster; "
          .. "a click you start by mistake can no longer be taken back by moving off the frame." },
    { id = "targetEnemy", text = "Enemy spells also target",
      tip = "A spell cast on the enemy under the cursor also makes it your target, on every key. "
          .. "Casting on an ally never changes your target. With this on, a plain left or right click "
          .. "that works in the world casts on living enemies as well: one click targets and casts." },
}

local function SwitchOn(settings, id)
    if id == "blizzard" or id == "registered" then return settings.frames[id] and true or false end
    return settings[id] and true or false
end

local function BuildSwitches(f)
    f.switches = {}
    local cell = f.w / #SWITCHES
    for i, switch in ipairs(SWITCHES) do
        local check = Skin.Check(f)
        check:SetSize(22, 22)
        check:SetPoint("TOPLEFT", (i - 1) * cell - 3, -SWITCH_Y)
        check.id, check.bg = switch.id, false
        check.text = NewText(f, 10)
        check.text:SetPoint("LEFT", check, "RIGHT", 1, 0)
        check.text:SetText(switch.text)
        check:SetScript("OnClick", function()
            local settings = CastSettings()
            if not settings then return end
            message, confirmDelete = nil, nil
            local on = not SwitchOn(settings, switch.id)
            if switch.id == "down" then
                SetCastDown(on)
            elseif switch.id == "targetEnemy" then
                ns.SetCastTargetEnemy(on)
            else
                SetCastFrames(switch.id, on)
            end
        end)
        Tip(check, switch.tip)
        f.switches[i] = check
    end
end

local function ShowSwitches(f, settings)
    for _, check in ipairs(f.switches) do check:SetChecked(SwitchOn(settings, check.id)) end
end

-- Mouseover (hover) casting for every key it is about at once: keyboard
-- keys, the wheel and the extra mouse buttons (`ns.KeyboardKeys`). Left,
-- right and middle click are set one key at a time.
local MOUSEOVER_TIP = "Mouseover (hover) casting: your keys also cast on characters and nameplates under the cursor, "
    .. "without targeting them. This sets every keyboard key, the wheel and the extra mouse buttons at once. "
    .. "Left, right and middle click are set one key at a time: click the key, then \"Works on\"."

local function MouseoverText()
    local count, anywhere, onTarget = ns.KeyboardKeys()
    if count == 0 then return "Mouseover casting: no key for it yet", "none" end
    if anywhere == 0 then return "Mouseover casting: Off", "off" end
    if anywhere < count or (onTarget > 0 and onTarget < count) then return "Mouseover casting: differs by key", "mixed" end
    if onTarget == count then return "Mouseover casting: On, else my target", "target" end
    return "Mouseover casting: On", "on"
end

local function MouseoverMenu(self)
    local _, now = MouseoverText()
    if now == "none" then
        Say(false, "Mouseover casting needs a keyboard key, the wheel or an extra mouse button in this set. "
            .. "For left or right click: click the key, then \"Works on\".")
        return
    end
    ShowMenu(self, {
        { text = "Off: keys cast on unit frames only", value = "off", current = now == "off" },
        { text = "On: also on units in the world", value = "on", current = now == "on" },
        { text = "On, and with no unit there on my target", value = "target", current = now == "target" },
    }, function(value)
        Say(Edit.SetHoverKeys(value ~= "off", value == "target"), "Your keys are set that way already.")
    end, { width = 300 })
end

local function ShowMouseover(f)
    local text, now = MouseoverText()
    f.mouseover.label:SetText(text)
    if now == "on" or now == "target" then
        f.mouseover.label:SetTextColor(Skin.ON[1], Skin.ON[2], Skin.ON[3])
    elseif now == "none" then
        f.mouseover.label:SetTextColor(0.6, 0.6, 0.6)
    else
        Skin.Plain(f.mouseover)
    end
end

local function Build(parent, w)
    local f = CreateFrame("Frame", nil, parent)
    f.w = w
    local x0, rw = LEFT_W + GAP, w - LEFT_W - GAP          -- the right pane: where it starts, how wide
    f.rw = rw

    -- Line 1: on or off; undo; the guided setup.
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
    enableText:SetText("Click casting")
    f.guide = NewButton(f, 96, 20, "Guided setup")
    f.guide:SetPoint("TOPRIGHT", 0, 0)
    f.guide:SetScript("OnClick", function() ns.OpenWizard(parent, w) end)      -- Wizard.lua
    Tip(f.guide, "A few questions, about a minute: a ready-made set for your class, whether your keys also work "
        .. "on units in the world, which buttons you use and what each should do.")
    f.undo = NewButton(f, 60, 20, "Undo")
    f.undo:SetPoint("RIGHT", f.guide, "LEFT", -6, 0)
    f.undo:SetScript("OnClick", function()
        local ok = Undo()
        message = ok and "Last change undone." or nil
        Refresh()
    end)
    Tip(f.undo, "Takes back the last change to this set: a key removed, a rule changed, a spell bound. Up to eight steps.")

    -- Line 2: the set.
    local setText = NewText(f, 12)
    setText:SetPoint("TOPLEFT", 0, -33)
    setText:SetText("Set")
    f.set = NewButton(f, 180, 20)
    f.set:SetPoint("TOPLEFT", 30, -28)
    f.set.label:SetWidth(172)                   -- a long name is cut short, not spilled over New...
    f.set.label:SetWordWrap(false)
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
        end, { width = 180 })
    end)
    Tip(f.set, "The set of bindings this character uses. Sets are shared by all your characters. "
        .. "A spec can have a set of its own: More, Use this set for this spec only.")
    -- New: an empty set, or one that starts from a starter set for a class.
    f.new = NewButton(f, 60, 20, "New...")
    f.new:SetPoint("LEFT", f.set, "RIGHT", 4, 0)
    f.new:SetScript("OnClick", function(self)
        local items = { { text = "Empty set", value = "empty" } }
        -- What another click-cast addon, or the game's own Click Casting, has now.
        for _, source in ipairs(CopySources()) do
            items[#items + 1] = { text = "Copy from " .. source.name, value = { copy = source.id, name = source.name }, note = "what it binds now" }
        end
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
            if value.copy then
                local name, count, left = CopyFromSource(value.copy)
                if name then
                    editing = nil
                    SelectSet(name)
                    -- Short, so that what to do next is not cut off; the rest is in the tooltip.
                    Say(false, "Copied " .. count .. " keys. Turn " .. value.name .. " off before you turn this on."
                        .. (left > 0 and (" " .. left .. " left out: not a spell, a macro, Target or Menu.") or ""))
                else
                    Say(false, count)
                end
                return
            end
            local name = AddSet(value.name, BuildTemplate(value))
            if name then
                editing = nil
                SelectSet(name)
                Say(false, name .. " made from the starter set. Spells you do not know are skipped.")
            end
        end, { width = 230 })
    end)
    Tip(f.new, "Make a set: empty, a copy of what another click-cast addon or the game's Click Casting binds now, "
        .. "or a starter set for a class.")

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
            -- A spec can have a set of its own; the others keep the character's.
            local specID, specName, own = SpecState()
            if specID then
                table.insert(items, 4, own and { text = "Use this set for every spec (the others lose their own)", value = "allspecs" }
                    or { text = "Use this set for " .. specName .. " only", value = "onespec" })
            end
            items[#items + 1] = { text = "Sort the keys: mouse first, then keyboard", value = "sort" }
        end
        -- Where click casting works, and when a click acts: seldom changed.
        local settings = CastSettings()
        if settings then
        end
        ShowMenu(self, items, function(value)
            message, confirmDelete = nil, nil
            if value == "sort" then
                Say(Edit.SortKeys(), "The keys are in that order already.")
                return
            end
            if value == "onespec" or value == "allspecs" then
                local _, specName = SpecState()
                SetSpecOnly(value == "onespec")
                Say(false, value == "onespec"
                    and (specName .. " now has its own set: picking a set changes it for this spec only.")
                    or "Every spec uses this set now.")
                return
            end
            if value == "delete" then
                confirmDelete = name              -- asked on the notice line, with its own two buttons
                Refresh()
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
        end, { width = 320 })
    end)
    Tip(f.more, "Rename, copy, share or delete this set, bring one in from text, give this spec a set of its own, sort the keys.")

    -- A text box that takes the place of line 3 while it is needed: a name for
    -- a new set or a copy, the text of an export, or the text to import.
    f.nameBox = NewEditBox(f, f.w - 100)
    f.nameBox:SetPoint("TOPLEFT", 0, -56)
    f.nameBox:SetMaxLetters(0)
    f.nameOk = NewButton(f, 44, 20, "OK")
    f.nameOk:SetPoint("LEFT", f.nameBox, "RIGHT", 4, 0)
    f.nameCancel = NewButton(f, 52, 20, "Cancel")
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

    -- One line for whatever needs saying: a question with its two buttons,
    -- that click casting is off, or the first notice (the rest in its tooltip).
    f.notice = NewLine(f, w - 220, 0.95, 0.55, 0.3, function() return notes end)
    f.notice:SetPoint("TOPLEFT", 0, -86)
    f.bannerNo = NewButton(f, 70, 20)
    f.bannerNo:SetPoint("TOPRIGHT", 0, -82)
    f.scopeAsk = false                  -- the notice line is asking "this spec only?"
    f.bannerYes = NewButton(f, 120, 20)
    f.bannerYes:SetPoint("RIGHT", f.bannerNo, "LEFT", -4, 0)
    f.bannerYes.label:SetTextColor(1, 1, 1)
    f.bannerYes:SetScript("OnClick", function()
        local name = confirmDelete
        if name then
            confirmDelete, message = nil, nil
            DeleteSet(name)
            editing = nil
            local names = SetNames()
            if names[1] then SelectSet(names[1]) else CastChanged() end
            Say(false, "The set " .. name .. " is deleted.")
        elseif f.scopeAsk then
            message = nil
            ns.CastScopePick()
        else
            message = nil
            SetCastEnabled(true)
        end
    end)
    f.bannerNo:SetScript("OnClick", function()
        confirmDelete = nil
        Refresh()
    end)

    -- Left pane: the keys.
    f.listHead = NewText(f, 11, ACCENT[1], ACCENT[2], ACCENT[3])
    f.listHead:SetPoint("TOPLEFT", 0, -TOP - 5)
    f.listHead:SetText("KEYS")
    f.quick = NewButton(f, 72, 20, "Quickbind")
    f.quick:SetPoint("TOPLEFT", LEFT_W - 72, -TOP)
    f.quick:SetScript("OnClick", function()
        if capture then Captured(nil) end
        quick, editing, writing, message = true, nil, nil, nil
        Refresh()
    end)
    Tip(f.quick, "Lists your spells. Point at one and press a key or a mouse button, with Shift, Ctrl or Alt "
        .. "if you like, and the spell is on that key.")
    f.add = NewButton(f, 108, 20)
    f.add:SetPoint("RIGHT", f.quick, "LEFT", -4, 0)
    f.add:SetScript("OnClick", function()
        if capture then Captured(nil) else StartCapture("add") end
    end)
    Tip(f.add, "Press this, then the key or mouse button you want to bind, holding Shift, Ctrl or Alt if you want them.")
    f.listScroll, f.listContent = NewScroll(f)
    f.listScroll:SetPoint("TOPLEFT", 0, -TOP - 26)
    f.listScroll:SetPoint("BOTTOMLEFT", 0, 14)
    f.listScroll:SetWidth(LEFT_W)
    f.listContent:SetSize(LEFT_W, 10)
    f.keyRows = {}
    f.empty = NewText(f, 11, 0.6, 0.6, 0.6)
    f.empty:SetPoint("TOPLEFT", 0, -TOP - 30)
    f.empty:SetWidth(LEFT_W)
    f.empty:SetJustifyH("LEFT")
    local divider = f:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", LEFT_W + GAP / 2, -TOP)
    divider:SetPoint("BOTTOMLEFT", LEFT_W + GAP / 2, 14)
    divider:SetWidth(1)
    divider:SetColorTexture(0.2, 0.21, 0.23, 1)

    -- Right pane: its heading, and the button that goes with what it shows.
    f.paneHead = NewText(f, 11, ACCENT[1], ACCENT[2], ACCENT[3])
    f.paneHead:SetPoint("TOPLEFT", x0, -TOP - 5)
    f.change = NewButton(f, 150, 20)
    f.change:SetPoint("TOPRIGHT", 0, -TOP)
    f.change:SetScript("OnClick", function()
        if capture then Captured(nil) elseif editing then StartCapture("change") end
    end)
    f.back = NewButton(f, 60, 20, "Done")
    f.back:SetPoint("TOPRIGHT", 0, -TOP)
    f.back:SetScript("OnClick", function()
        editing, quick, hovered, writing, message = nil, false, nil, nil, nil
        Refresh()
    end)
    f.hint = NewText(f, 11, 0.6, 0.6, 0.6)
    f.hint:SetPoint("TOPLEFT", x0, -TOP - 30)
    f.hint:SetWidth(rw)
    f.hint:SetJustifyH("LEFT")

    -- Right pane, Quickbind: a search box, a switch for lower ranks, the
    -- spells, and a frame that hears the keyboard while a spell is under the
    -- cursor.
    f.quickSearch = NewEditBox(f, rw - 130)
    f.quickSearch:SetPoint("TOPLEFT", x0, -TOP - 26)
    f.quickSearch:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        if text ~= quickFilter then quickFilter = text; Refresh() end
    end)
    f.quickSearchHint = NewText(f, 10, 0.5, 0.5, 0.5)
    f.quickSearchHint:SetPoint("LEFT", f.quickSearch, "LEFT", 6, 0)
    f.quickSearchHint:SetText("Type to search your spells")
    f.quickRanks = NewButton(f, 122, 20)
    f.quickRanks:SetPoint("TOPRIGHT", 0, -TOP - 26)
    f.quickRanks:SetScript("OnClick", function()
        quickRanks = not quickRanks
        Refresh()
    end)
    Tip(f.quickRanks, "Lists the lower ranks of your spells too. A lower rank put on a key casts exactly that rank.")
    f.quickScroll, f.quickContent = NewScroll(f)
    f.quickScroll:SetPoint("TOPLEFT", x0, -TOP - 52)
    f.quickScroll:SetPoint("BOTTOMRIGHT", 0, 14)
    f.quickContent:SetSize(rw, 10)
    f.quickRows = {}
    f.quickKeys = CreateFrame("Frame", nil, f)
    f.quickKeys:SetAllPoints(f)
    f.quickKeys:EnableMouse(false)
    f.quickKeys:EnableKeyboard(true)
    f.quickKeys:Hide()
    f.quickKeys:SetScript("OnKeyDown", function(_, key)
        local row = hovered
        if not (row and row.item) then return end
        if key == "ESCAPE" then
            quick, hovered, message = false, nil, nil
            Refresh()
        elseif not MODIFIER_KEY[key] then
            Safe(QuickBind, row.item, key)
        end
    end)

    -- Right pane, one key's rules.
    f.ruleScroll, f.ruleContent = NewScroll(f)
    f.ruleScroll:SetPoint("TOPLEFT", x0, -TOP - 46)
    f.ruleScroll:SetPoint("BOTTOMRIGHT", 0, 64)
    f.ruleContent:SetSize(rw, 10)
    f.ruleRows = {}
    f.addRule = NewButton(f, 84, 20, "Add a rule")
    f.addRule:SetPoint("BOTTOMLEFT", x0, 38)
    Tip(f.addRule, "Say what the key should also do, and the rule is put where it can fire. "
        .. "Rules are tried from the top; the first that fits fires. "
        .. "A rule whose spell you do not know is skipped, so the next one takes over.")
    -- Done just before one of the key's spells is cast.
    f.pre = NewButton(f, 104, 20)
    f.pre:SetPoint("BOTTOMRIGHT", -200, 38)
    f.pre:SetScript("OnClick", function(self)
        local set = ActiveSet()
        local binding = set and editing and set.bindings[editing]
        if not binding then return end
        local items = {}
        for _, what in ipairs(PRE_ORDER) do
            local on = binding.pre and binding.pre[what] and true or false
            items[#items + 1] = { text = PRE_TEXT[what], value = what, current = on, note = on and "on" or nil }
        end
        ShowMenu(self, items, function(what)
            Say(Edit.SetPre(editing, what, not (binding.pre and binding.pre[what])))
        end, { width = 190 })
    end)
    Tip(f.pre, "Done just before a spell of this key is cast: stop the cast in progress, or use a trinket. "
        .. "Pick one to switch it on, pick it again to switch it off. It uses room in the key's "
        .. MACRO_LIMIT .. " characters, and is left out of a key that runs one of your saved macros.")
    -- Where the key works: on unit frames, or on anything under the cursor.
    f.hover = NewButton(f, 196, 20)
    f.hover:SetPoint("BOTTOMRIGHT", 0, 38)
    f.hover:SetScript("OnClick", function(self)
        local set = ActiveSet()
        local binding = set and editing and set.bindings[editing]
        if not binding then return end
        ShowMenu(self, {
            { text = "Unit frames", value = false, current = not binding.hover },
            { text = "Unit frames + units in the world", value = "hover", current = (binding.hover and not binding.orTarget) and true or false },
            { text = "Unit frames + world, else my target", value = "target", current = (binding.hover and binding.orTarget) and true or false },
            { text = "Set every mouseover key like this one", value = "all" },
        }, function(value)
            if value == "all" then
                Say(Edit.SetHoverAll(binding.hover, binding.orTarget), "They are all set like this one already.")
            else
                Say(Edit.SetHover(editing, value ~= false, value == "target"))
            end
        end, { width = 290 })
    end)
    Tip(f.hover, "Mouseover (hover) casting: where this key works. Unit frames: while the cursor is on a unit frame. "
        .. "Units in the world: also on characters and nameplates under the cursor, without targeting them. "
        .. "Else my target: with nothing fitting under the cursor the same spells go to your target, so the key is never dead. "
        .. "With either of the last two, ClickLegend takes this key from the game while click casting is on. "
        .. "A plain left or right click is different: it is taken only while the cursor is on a friendly player's "
        .. "character (in combat, on any living friendly unit), and is the game's own click everywhere else.")
    f.problemLines = {}
    f.problems = NewLine(f, rw, 0.95, 0.4, 0.4, function() return f.problemLines end)
    f.problems:SetPoint("BOTTOMLEFT", x0, 20)
    -- A problem of order comes with its remedy.
    f.fix = NewButton(f, 40, 16, "Fix")
    f.fix:SetPoint("BOTTOMRIGHT", 0, 18)
    f.fix:SetScript("OnClick", function()
        if editing then Say(Edit.FixOrder(editing)) end
    end)
    Tip(f.fix, "Moves the rule to where it can fire. Undo takes it back.")
    -- The key read back in words, above its rules.
    f.sentenceLines = {}
    f.sentence = NewLine(f, rw, 0.78, 0.78, 0.78, function() return f.sentenceLines end)
    f.sentence:SetPoint("TOPLEFT", x0, -TOP - 27)
    f.status = NewText(f, 10, 0.6, 0.6, 0.6)
    f.status:SetPoint("BOTTOMRIGHT", 0, 0)

    -- Writing a rule's macro text: covers the rules while it is open.
    local writer = CreateFrame("Frame", nil, f)
    writer:SetPoint("TOPLEFT", x0, -TOP - 26)
    writer:SetPoint("BOTTOMRIGHT", 0, 14)
    writer:SetFrameLevel((f:GetFrameLevel() or 1) + 10)
    writer:EnableMouse(true)
    writer.bg = writer:CreateTexture(nil, "BACKGROUND")
    writer.bg:SetAllPoints()
    writer.bg:SetColorTexture(0.10, 0.11, 0.13, 1)
    writer.hint = NewText(writer, 10, 0.6, 0.6, 0.6)
    writer.hint:SetPoint("TOPLEFT", 0, -2)
    writer.hint:SetWidth(rw)
    writer.hint:SetJustifyH("LEFT")
    writer.hint:SetText("Macro text, run as written. Use [@mouseover] for the unit under the cursor, "
        .. "for example /cast [@mouseover,help,nodead] Flash Heal. It runs when no earlier rule of the key has fired.")
    writer.box = NewEditBox(writer, rw)
    writer.box:SetPoint("TOPLEFT", 0, -34)
    writer.box:SetPoint("BOTTOMRIGHT", 0, 28)
    writer.box:SetMultiLine(true)
    writer.box:SetMaxLetters(MACRO_LIMIT)
    writer.box:SetJustifyH("LEFT")
    writer.count = NewText(writer, 10, 0.6, 0.6, 0.6)
    writer.count:SetPoint("BOTTOMLEFT", 0, 6)
    writer.box:SetScript("OnTextChanged", function(self)
        writer.count:SetText(#(self:GetText() or "") .. " of " .. MACRO_LIMIT .. " characters")
    end)
    writer.cancel = NewButton(writer, 60, 20, "Cancel")
    writer.cancel:SetPoint("BOTTOMRIGHT", 0, 2)
    writer.ok = NewButton(writer, 60, 20, "OK")
    writer.ok:SetPoint("RIGHT", writer.cancel, "LEFT", -4, 0)
    local function WriterClose()
        writing = nil
        writer.box:ClearFocus()
        writer:Hide()
    end
    writer.ok:SetScript("OnClick", function()
        local index, text = writing, writer.box:GetText()
        WriterClose()
        if not (editing and index) then Refresh(); return end
        local ok = Edit.SetAction(editing, index, { type = "text", text = text })
        Say(ok, "Type the macro text first.")
    end)
    writer.cancel:SetScript("OnClick", function() WriterClose(); Refresh() end)
    writer.box:SetScript("OnEscapePressed", function() WriterClose(); Refresh() end)
    writer:Hide()
    f.writer = writer

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
        -- The catcher lies over the buttons that started it. A plain left click
        -- on one of those is the player stopping, not binding plain left click.
        if mouse == "LeftButton" and HeldMods() == "" then
            for _, button in ipairs({ f.add, f.change, f.quick }) do
                if button:IsShown() and button.IsMouseOver and button:IsMouseOver() == true then
                    Captured(nil)
                    return
                end
            end
        end
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
-- Left pane: every key of the set.
local function ShowKeys(f, set)
    local count = set and #set.bindings or 0
    for i = 1, max(count, #f.keyRows) do
        local row = f.keyRows[i]
        local binding = set and set.bindings[i]
        if binding then
            if not row then
                row = NewKeyRow(f.listContent, LEFT_W)
                f.keyRows[i] = row
            end
            row.index = i
            row.key:SetText(KeyName(binding.key))
            if binding.hover then
                row.key:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])       -- works anywhere
            else
                row.key:SetTextColor(1, 1, 1)
            end
            local ally, enemy = SummaryRule(binding, "ally"), SummaryRule(binding, "enemy")
            ShowSideIcon(row.ally, ally)
            ShowSideIcon(row.enemy, enemy)
            local allyName, enemyName = SummaryName(ally), SummaryName(enemy)
            -- The same in words, for the tests and anything else that reads the list.
            row.summary = (binding.hover and "anywhere: " or "")
                .. (allyName == enemyName and allyName or (allyName .. "  /  " .. enemyName))
            row.sel:SetShown(editing == i)
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
    f.listScroll:SetShown(count > 0)
    f.empty:SetShown(count == 0)
    f.empty:SetText(set and "No keys yet. Press Add a key, then the key or mouse button to bind (hold Shift, Ctrl or Alt with it). "
            .. "Or use Quickbind."
        or "Press Guided setup to be taken through it, or New... to make a set yourself.")
    f.add:SetShown(set ~= nil)
    f.add.label:SetText(capture == "add" and "Press it (Esc)" or "Add a key")
end

-- Right pane, nothing picked: where to begin.
local function ShowHint(f, set)
    f.hint:Show()
    f.paneHead:SetText("")
    if not set and #SetNames() > 0 then
        f.hint:SetText("No set picked for this character.\n\nYour account has " .. #SetNames() .. " already: "
            .. "press the Set button, top left, and pick one. Sets are shared by all your characters.\n\n"
            .. "Or run the Guided setup (top right) to make a new one.")
    elseif not set then
        f.hint:SetText("No set yet.\n\nGuided setup (top right) makes one for your class and asks what your buttons should do. "
            .. "It takes about a minute.\n\n"
            .. "Or press New... to make a set yourself, or Quickbind to put spells on keys straight away.")
    elseif #set.bindings == 0 then
        f.hint:SetText("This set is empty.\n\nAdd a key: press the button, then the key or mouse button.\n\n"
            .. "Quickbind: point at a spell in a list and press the key you want it on.")
    else
        f.hint:SetText("Click a key on the left to see and change what it does.\n\n"
            .. "The two icons beside a key are what it casts on an ally and on an enemy. "
            .. "A key named in gold is a mouseover casting key: it also works on units in the world.\n\n"
            .. "Drag a spell from your spellbook onto a key to put it there.")
    end
end

-- Right pane, Quickbind: every spell, and the keys it is on now.
local function ShowQuick(f)
    f.quickScroll:Show(); f.quickKeys:Show(); f.back:Show(); f.quickSearch:Show(); f.quickRanks:Show()
    f.quickSearchHint:SetShown(quickFilter == "")
    f.quickRanks.label:SetText(quickRanks and "Lower ranks: shown" or "Lower ranks: hidden")
    f.paneHead:SetText("QUICKBIND: point at a spell, press a key")
    local items = QuickItems()
    for i = 1, max(#items, #f.quickRows) do
        local row, item = f.quickRows[i], items[i]
        if item then
            if not row then
                row = NewQuickRow(f.quickContent, f.rw)
                f.quickRows[i] = row
            end
            row.item = item
            row.icon:SetTexture(item.icon)
            row.name:SetText(item.text)
            row.note:SetText(item.note or "")
            local keys = BoundKeys(item.action)
            row.keys:SetText(keys)
            row.clear:SetShown(keys ~= "")
            row.swap:SetShown(keys ~= "")
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", f.quickContent, "TOPLEFT", 0, -(i - 1) * QUICK_H)
            row:Show()
        elseif row then
            row.item = nil
            row:Hide()
        end
    end
    f.quickContent:SetHeight(max(10, #items * QUICK_H))
end

-- Right pane: the rules of one key.
local function ShowRules(f, binding)
    f.ruleScroll:Show(); f.addRule:Show(); f.problems:Show(); f.hover:Show(); f.pre:Show(); f.change:Show()
    f.sentence:Show(); f.sentence.hit:Show()
    f.paneHead:SetText(KeyName(binding.key))
    f.sentenceLines = Sentence(binding)
    f.sentence:SetText(#f.sentenceLines > 0 and (table.concat(f.sentenceLines, ". ") .. ".") or "This key does nothing yet.")
    f.change.label:SetText(capture == "change" and "Press a key (Esc)" or "Change the key")
    f.hover.label:SetText(not binding.hover and "Works on: unit frames"
        or binding.orTarget and "Frames + world, else target" or "Works on: frames + world")
    local extras = 0
    for _, what in ipairs(PRE_ORDER) do
        if binding.pre and binding.pre[what] then extras = extras + 1 end
    end
    f.pre.label:SetText(extras > 0 and ("Before cast: " .. extras) or "Before cast")
    local count = #binding.rules
    for i = 1, max(count, #f.ruleRows) do
        local row = f.ruleRows[i]
        local rule = binding.rules[i]
        if rule then
            if not row then
                row = NewRuleRow(f.ruleContent, f.rw)
                f.ruleRows[i] = row
            end
            row.index = i
            row.number:SetText(tostring(i))
            local action = rule.action
            -- The conditions in use, one after the other, then the way to add one.
            local x, unset = 16, 0
            for c, spec in ipairs(CONDITIONS) do
                local value = ConditionValue(rule.when, spec.field)
                row.values[spec.field] = value
                local button = row.conditions[c]
                if value == false then
                    unset = unset + 1
                    button:Hide()
                else
                    local text = spec.text[value] or ("Form " .. tostring(value))
                    local width = max(44, 14 + #text * 6)
                    button.label:SetText(text)
                    button:SetWidth(width)
                    button:ClearAllPoints()
                    button:SetPoint("TOPLEFT", x, 0)
                    button:Show()
                    x = x + width + 3
                end
            end
            row.always:SetShown(unset == #CONDITIONS)
            row.always:ClearAllPoints()
            row.always:SetPoint("TOPLEFT", x, -5)
            if unset == #CONDITIONS then x = x + 46 end
            row.addCond:SetShown(unset > 0 and action.type ~= "text")
            row.addCond:ClearAllPoints()
            row.addCond:SetPoint("TOPLEFT", x, 0)

            row.kind.label:SetText(KIND_TEXT[action.type] or "?")
            row.kindNow = action.type
            local named = NAMED[action.type] and true or false
            local chosen = named and (action.name or action.spellID or action.itemID or action.text) and true or false
            row.choice:SetShown(named)
            if chosen and action.type == "text" then
                row.shown = FirstLine(action.text)
                row.choice.icon:SetTexture(ActionEntry(action).icon)
                row.choice.icon:Show()
                Skin.Plain(row.choice)
            elseif chosen then
                local entry = ActionEntry(action)
                local rank = action.pinned and RankText(action.spellID)
                row.shown = entry.name .. (rank and ("  (" .. rank .. " only)") or (action.pinned and "  (this rank only)" or ""))
                row.choice.icon:SetTexture(entry.icon)
                row.choice.icon:Show()
                if RuleUnavailable(rule) then
                    row.shown = "(not known) " .. row.shown     -- in front: the end of a long name is cut off
                    row.choice.label:SetTextColor(0.55, 0.55, 0.55)
                else
                    Skin.Plain(row.choice)
                end
            elseif named then
                row.shown = CHOICE_HINT[action.type]
                row.choice.icon:Hide()
                Skin.Emph(row.choice)
            else
                row.shown = nil
            end
            row.choice.label:SetText(row.shown or "")
            row.fixed:SetShown(not named)
            row.fixed:SetText(named and "" or PRESET[action.type] and PresetText(action) or ACTION_NAME[action.type] or "")
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
    -- The room a key uses only matters when it is running out: a line of the problems then.
    local length = compiled.length or 0
    local lines = {}
    for _, problem in ipairs(compiled.problems) do lines[#lines + 1] = problem end
    if compiled.skipped > 0 then
        lines[#lines + 1] = compiled.skipped .. " rule(s) skipped: you do not know the spell."
    end
    if length > ROOM_WARN and not compiled.tooLong then
        lines[#lines + 1] = "Room used: " .. length .. " of " .. MACRO_LIMIT .. " characters."
    end
    f.problemLines = lines
    f.problems:SetText((#lines > 1 and ("(" .. #lines .. ") ") or "") .. table.concat(lines, " "))
    f.fix:SetShown(compiled.fix ~= nil)
    f.problems:SetWidth(compiled.fix and (f.rw - 48) or f.rw)
end

Refresh = function()
    CloseMenu()
    local f = panel
    local settings = CastSettings()
    if not (f and settings) then return end
    local set, name = ActiveSet()
    if editing and not (set and set.bindings[editing]) then editing = nil end
    if editing then quick = false end
    local rule = editing and writing and set.bindings[editing].rules[writing]
    if not (rule and rule.action.type == "text") then writing = nil end
    if writing and not f.writer:IsShown() then
        f.writer.box:SetText(rule.action.text or TEXT_START)
        f.writer:Show()
        f.writer.box:SetFocus()
    elseif not writing then
        f.writer:Hide()
    end
    if not quick then hovered = nil end
    ShowMouseover(f)
    ShowSwitches(f, settings)

    OnOff(f.enable, settings.enabled)
    f.undo:SetShown(CanUndo())
    local _, specName, specOwn = SpecState()
    f.set.label:SetText(name and (name .. (specOwn and ("  [" .. specName .. "]") or ""))
        or (settings.set and (settings.set .. " (missing)")) or "No set")
    if confirmDelete and confirmDelete ~= name then confirmDelete = nil end

    local showName = naming ~= nil
    f.nameBox:SetShown(showName); f.nameOk:SetShown(showName and naming ~= "export"); f.nameCancel:SetShown(showName)
    if naming == "export" then
        message = "Press Ctrl+C to copy the text, then Close. Anyone can bring it in with More, Import."
    elseif naming == "import" then
        message = "Paste the text with Ctrl+V and press OK. It comes in as a new set."
    elseif naming then
        message = "Type a name for the set and press OK."
    end

    local provider = ClickLegendAPI and ClickLegendAPI.provider
    local status = ""
    if settings.enabled and provider and provider.Started() then
        local frames, bound = provider.Count()
        status = provider.Pending() and "changes apply after combat" or (bound .. " of " .. frames .. " frames bound")
    end
    f.status:SetText(status)

    -- The notice line.
    notes = {}
    f.scopeAsk = false
    local yes, no = nil, nil
    if confirmDelete then
        notes[1] = "Delete the set " .. confirmDelete .. " for every character?"
        yes, no = "Delete", "Keep"
    else
        -- The character's set was just changed: every spec uses it, unless
        -- the player keeps it to this one.
        local specName, picked = ns.CastPickScope()
        if specName then
            notes[1] = (message and (message .. " ") or "") .. "Every spec now uses " .. picked .. "."
            yes = "Only " .. specName
            f.scopeAsk = true
        elseif message then
            notes[#notes + 1] = message
        end
        if settings.enabled then
            for _, conflict in ipairs(CastConflicts()) do notes[#notes + 1] = conflict end
        elseif specName then
            -- one question at a time
        elseif not message and ns.CastBlocked() then
            notes[1] = ns.CastBlocked()
        elseif not message and set and #set.bindings > 0 then
            notes[1] = "Click casting is off: these keys do nothing yet."
            yes = "Turn on"
        end
    end
    f.notice:SetText((#notes > 1 and ("(1 of " .. #notes .. ", point here for all) ") or "") .. (notes[1] or ""))
    f.bannerYes:SetShown(yes ~= nil); f.bannerYes.label:SetText(yes or "")
    f.bannerNo:SetShown(no ~= nil); f.bannerNo.label:SetText(no or "")

    ShowKeys(f, set)
    -- The right pane shows one thing at a time.
    f.ruleScroll:Hide(); f.addRule:Hide(); f.problems:Hide(); f.hover:Hide(); f.pre:Hide(); f.change:Hide()
    f.fix:Hide(); f.sentence:Hide(); f.sentence.hit:Hide()
    f.quickScroll:Hide(); f.quickKeys:Hide(); f.back:Hide(); f.quickSearch:Hide(); f.quickSearchHint:Hide(); f.quickRanks:Hide()
    f.hint:Hide()
    for _, row in ipairs(f.ruleRows) do row:Hide() end
    if quick then
        ShowQuick(f)
    elseif editing then
        ShowRules(f, set.bindings[editing])
    else
        ShowHint(f, set)
    end

    -- A key that was just added goes straight on to choosing its spell.
    if openFirst then
        local at = openFirst == true and 1 or openFirst
        openFirst = false
        local first = editing and f.ruleRows[at]
        if first and first:IsShown() and not capture then Safe(OpenChoice, first) end
    end
end

-- Called by Window.lua: the tab's frame, made on first use, filling `parent`.
local function GetEditor(parent, w)
    if not panel then
        panel = Build(parent, w)
        panel.addRule:SetScript("OnClick", AddRuleMenu)      -- here: Build has no room for another outer local
        panel.mouseover = NewButton(panel, 250, 20)
        panel.mouseover:SetPoint("TOPLEFT", 150, 0)
        panel.mouseover:SetScript("OnClick", MouseoverMenu)
        Tip(panel.mouseover, MOUSEOVER_TIP)
        BuildSwitches(panel)
        panel:SetAllPoints(parent)
    end
    return panel
end

local function RefreshEditor()
    if panel and panel:IsShown() then Safe(Refresh) end
end

-- Shows the rules of one key of the set in use (a click on the legend).
local function EditorSelectKey(keyStr)
    local set = ActiveSet()
    if not (panel and set and type(keyStr) == "string") then return false end
    for i, binding in ipairs(set.bindings) do
        if binding.key == keyStr then
            editing, quick, writing, message = i, false, nil, nil
            Safe(Refresh)
            return true
        end
    end
    return false
end

-------------------------------------------------------------------------------
--  Used by the other files
-------------------------------------------------------------------------------
ns.EditorSelectKey = EditorSelectKey
ns.DropOnKey = DropOnKey
ns.GetEditor       = GetEditor
ns.KeyRuleLines    = KeyRuleLines
ns.RefreshEditor   = RefreshEditor
