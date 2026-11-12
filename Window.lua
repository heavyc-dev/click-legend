-------------------------------------------------------------------------------
--  ClickLegend - Window.lua
--  The addon's own settings window (/clg) and its entry in the game's
--  AddOns options list.
-------------------------------------------------------------------------------
local _, ns = ...

local ipairs, pairs, type, tostring, pcall = ipairs, pairs, type, tostring, pcall
local floor, max = math.floor, math.max

local db
local activeSource
ns.Subscribe("db", function(value) db = value end)
ns.Subscribe("source", function(value) activeSource = value end)

local Clamp, LongKey, Report, Safe, AllBoundKeys, ACCENT =
    ns.Clamp, ns.LongKey, ns.Report, ns.Safe, ns.AllBoundKeys, ns.ACCENT
local ApplyFont, Refresh, ResolveFont, ApplyPreset =
    ns.ApplyFont, ns.Refresh, ns.ResolveFont, ns.ApplyPreset
local ExportSettings, GetColor, ImportSettings, OPTIONS =
    ns.ExportSettings, ns.GetColor, ns.ImportSettings, ns.OPTIONS
local OptGet, OptSet, PAGES, PANEL_PAGES, PRESETS =
    ns.OptGet, ns.OptSet, ns.PAGES, ns.PANEL_PAGES, ns.PRESETS
local PRESET_NOTE, PRESET_ORDER, RebuildSettingsPages =
    ns.PRESET_NOTE, ns.PRESET_ORDER, ns.RebuildSettingsPages
local ResetSettings, SetColor, SetCustomPosition =
    ns.ResetSettings, ns.SetColor, ns.SetCustomPosition

-------------------------------------------------------------------------------
--  The addon's own settings window. Built from plain frames and textures (no
--  templates), so it works on any client, with or without EllesmereUI.
-------------------------------------------------------------------------------
local window                    -- created on first open
local ToggleWindow, RefreshWindow, OpenShareTab, OpenBindingsTab
-- Things that sit on top of the window and must not outlive it: an open
-- drop-down list (Picker.lua) and the guided setup (Wizard.lua).
local function CloseOverlays()
    if ns.CloseMenu then ns.CloseMenu() end
    if ns.CloseWizard then ns.CloseWizard() end
end
local function GetEditor(parent, width) return ns.GetEditor(parent, width) end     -- Editor.lua
local function RefreshEditor() ns.RefreshEditor() end                              -- Editor.lua

local WIN_W, WIN_H, ROW_H, WIN_PAD = 400, 520, 26, 16
local activeTab = "Display"

local function NewText(parent, size, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    ApplyFont(fs, size)
    fs:SetTextColor(r or 1, g or 1, b or 1)
    return fs
end

local function NewButton(parent, w, h, text)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0.16, 0.17, 0.19, 1)
    b.label = NewText(b, 11)
    b.label:SetPoint("CENTER")
    b.label:SetText(text or "")
    b:SetScript("OnEnter", function(self) self.bg:SetColorTexture(0.26, 0.28, 0.31, 1) end)
    b:SetScript("OnLeave", function(self) self.bg:SetColorTexture(0.16, 0.17, 0.19, 1) end)
    return b
end

-- The game's color picker, in its current form and the older one.
local function OpenColorPicker(r, g, b, a, hasAlpha, onChange)
    local CP = ColorPickerFrame
    if not CP then return end
    local function Apply()
        local nr, ng, nb = CP:GetColorRGB()
        local na = a
        if hasAlpha then
            if CP.GetColorAlpha then
                na = CP:GetColorAlpha()
            elseif OpacitySliderFrame and OpacitySliderFrame.GetValue then
                na = 1 - OpacitySliderFrame:GetValue()
            end
        end
        onChange(nr, ng, nb, na)
    end
    local function Cancel() onChange(r, g, b, a) end
    if CP.SetupColorPickerAndShow then
        CP:SetupColorPickerAndShow({
            r = r, g = g, b = b, opacity = a, hasOpacity = hasAlpha,
            swatchFunc = Apply, opacityFunc = Apply, cancelFunc = Cancel,
        })
    else
        CP.hasOpacity, CP.opacity = hasAlpha, 1 - a
        CP.func, CP.opacityFunc, CP.cancelFunc = Apply, Apply, Cancel
        CP:SetColorRGB(r, g, b)
        CP:Hide()
        CP:Show()
    end
end

local function FormatNumber(o, v)
    if o.step >= 1 then return tostring(floor(v + 0.5)) end
    return ("%.2f"):format(v)
end

local function AttachTip(row, tip)
    if not tip then return end
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(tip, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

-- One row of the window for one option. row.Update redraws its value.
local function NewOptionRow(parent, o)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(WIN_W - WIN_PAD * 2, ROW_H)
    if o.header then
        local text = NewText(row, 11, ACCENT[1], ACCENT[2], ACCENT[3])
        text:SetPoint("BOTTOMLEFT", 0, 5)
        text:SetText(o.header)
        row.Update = function() end
        return row
    end
    local label = NewText(row, 12)
    label:SetPoint("LEFT")
    label:SetText(o.text)
    AttachTip(row, o.tip)

    if o.kind == "toggle" then
        local b = NewButton(row, 46, 20)
        b:SetPoint("RIGHT")
        b:SetScript("OnClick", function() OptSet(o, not OptGet(o)) end)
        row.Update = function()
            local on = OptGet(o)
            b.label:SetText(on and "On" or "Off")
            if on then
                b.label:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
            else
                b.label:SetTextColor(0.6, 0.6, 0.6)
            end
        end
    elseif o.kind == "choice" then
        -- Left click steps forward through the choices, right click back.
        local b = NewButton(row, 160, 20)
        b:SetPoint("RIGHT")
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(_, button)
            local index = 1
            for i, value in ipairs(o.order) do
                if value == db[o.key] then index = i; break end
            end
            index = index + (button == "RightButton" and -1 or 1)
            if index > #o.order then index = 1 elseif index < 1 then index = #o.order end
            OptSet(o, o.order[index])
        end)
        row.Update = function() b.label:SetText(o.values[db[o.key]] or "?") end
    elseif o.kind == "range" then
        -- Minus and plus step the value; hold Shift for steps of five.
        local plus = NewButton(row, 20, 20, "+")
        plus:SetPoint("RIGHT")
        local value = NewText(row, 12)
        value:SetPoint("RIGHT", plus, "LEFT", -6, 0)
        value:SetWidth(44)
        value:SetJustifyH("CENTER")
        local minus = NewButton(row, 20, 20, "-")
        minus:SetPoint("RIGHT", value, "LEFT", -6, 0)
        local function Step(dir)
            local step = o.step * (IsShiftKeyDown() and 5 or 1)
            OptSet(o, Clamp(db[o.key] + dir * step, o.lo, o.hi))
        end
        plus:SetScript("OnClick", function() Step(1) end)
        minus:SetScript("OnClick", function() Step(-1) end)
        row.Update = function() value:SetText(FormatNumber(o, db[o.key])) end
    elseif o.kind == "color" then
        local b = NewButton(row, 46, 20)
        b:SetPoint("RIGHT")
        b.swatch = b:CreateTexture(nil, "ARTWORK")
        b.swatch:SetPoint("TOPLEFT", 2, -2)
        b.swatch:SetPoint("BOTTOMRIGHT", -2, 2)
        local percent = NewText(row, 11, 0.7, 0.7, 0.7)
        percent:SetPoint("RIGHT", b, "LEFT", -8, 0)
        local prefix = o.prefix
        b:SetScript("OnClick", function()
            local r, g, bl, a = GetColor(prefix)
            OpenColorPicker(r, g, bl, a, o.alpha and true or false,
                function(nr, ng, nb, na) SetColor(prefix, nr, ng, nb, na) end)
        end)
        row.Update = function()
            local r, g, bl, a = GetColor(prefix)
            b.swatch:SetColorTexture(r, g, bl, 1)
            percent:SetText(o.alpha and (floor(a * 100 + 0.5) .. "%") or "")
        end
    end
    return row
end

-- One row per bound key on the Order tab, with Up and Down to move it.
local function NewOrderRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(WIN_W - WIN_PAD * 2, ROW_H)
    row.label = NewText(row, 12)
    row.label:SetPoint("LEFT")
    row.down = NewButton(row, 46, 20, "Down")
    row.down:SetPoint("RIGHT")
    row.up = NewButton(row, 46, 20, "Up")
    row.up:SetPoint("RIGHT", row.down, "LEFT", -6, 0)
    local function Move(delta)
        if not (db and row.key) then return end
        SetCustomPosition(row.key, row.index + delta)
        Refresh(true)
        RebuildSettingsPages()
    end
    row.up:SetScript("OnClick", function() Move(-1) end)
    row.down:SetScript("OnClick", function() Move(1) end)
    return row
end

local function BuildWindow()
    ResolveFont()
    local f = CreateFrame("Frame", "ClickLegendOptions", UIParent)
    f:SetSize(WIN_W, WIN_H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    if type(UISpecialFrames) == "table" then
        UISpecialFrames[#UISpecialFrames + 1] = "ClickLegendOptions"      -- Escape closes it
    end

    local edge = f:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints()
    edge:SetColorTexture(0, 0, 0, 1)
    local fill = f:CreateTexture(nil, "BORDER")
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", -1, 1)
    fill:SetColorTexture(0.07, 0.08, 0.09, 0.97)

    local title = NewText(f, 14)
    title:SetPoint("TOPLEFT", WIN_PAD, -12)
    title:SetText("ClickLegend")
    f.source = NewText(f, 10, 0.6, 0.6, 0.6)
    f.source:SetPoint("LEFT", title, "RIGHT", 10, 0)

    local close = NewButton(f, 22, 22, "X")
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function() f:Hide(); CloseOverlays() end)
    f:SetScript("OnHide", CloseOverlays)             -- Escape closes the window too

    f.tabs = {}
    for i, name in ipairs(PANEL_PAGES) do
        local tab = NewButton(f, 70, 22, name)
        tab:SetPoint("TOPLEFT", WIN_PAD + (i - 1) * 74, -40)
        tab:SetScript("OnClick", function()
            CloseOverlays()
            activeTab = name
            f.scroll:SetVerticalScroll(0)
            RefreshWindow()
        end)
        f.tabs[name] = tab
    end

    -- Scrolling area: the Order tab grows with the number of bound keys.
    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", WIN_PAD, -72)
    scroll:SetPoint("BOTTOMRIGHT", -WIN_PAD, 48)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(WIN_W - WIN_PAD * 2, 10)
    scroll:SetScrollChild(content)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = max(0, (content:GetHeight() or 0) - (self:GetHeight() or 0))
        self:SetVerticalScroll(Clamp((self:GetVerticalScroll() or 0) - delta * 40, 0, range))
    end)
    f.scroll, f.content = scroll, content

    f.rows = {}
    for _, name in ipairs(PAGES) do
        f.rows[name] = {}
        for i, o in ipairs(OPTIONS[name]) do
            f.rows[name][i] = NewOptionRow(content, o)
        end
    end
    f.orderHeader = NewOptionRow(content, { header = "CUSTOM ORDER" })
    f.orderRows = {}

    -- Share tab: preset buttons, and a text box to copy the settings out of
    -- or paste them into.
    local share = CreateFrame("Frame", nil, f)
    share:SetPoint("TOPLEFT", WIN_PAD, -72)
    share:SetPoint("BOTTOMRIGHT", -WIN_PAD, 48)
    share:Hide()
    f.share = share
    local inner = WIN_W - WIN_PAD * 2
    local function Heading(text, y)
        local fs = NewText(share, 11, ACCENT[1], ACCENT[2], ACCENT[3])
        fs:SetPoint("TOPLEFT", 0, y)
        fs:SetText(text)
    end
    local function Note(text, y)
        local fs = NewText(share, 10, 0.6, 0.6, 0.6)
        fs:SetPoint("TOPLEFT", 0, y)
        fs:SetWidth(inner)
        fs:SetJustifyH("LEFT")
        fs:SetText(text)
        return fs
    end
    Heading("PRESETS", -4)
    for i, id in ipairs(PRESET_ORDER) do
        local b = NewButton(share, 86, 22, PRESETS[id].name)
        b:SetPoint("TOPLEFT", (i - 1) * 94, -24)
        b:SetScript("OnClick", function()
            if ApplyPreset(id) then share.status:SetText(PRESETS[id].name .. " preset applied.") end
        end)
    end
    Note(PRESET_NOTE, -54)

    Heading("IMPORT / EXPORT", -96)
    local box = CreateFrame("EditBox", nil, share)
    box:SetPoint("TOPLEFT", 0, -116)
    box:SetSize(inner, 24)
    box:SetAutoFocus(false)
    box:SetFont(STANDARD_TEXT_FONT, 11, "")
    box:SetTextInsets(6, 6, 0, 0)
    box:SetMaxLetters(4000)
    box.bg = box:CreateTexture(nil, "BACKGROUND")
    box.bg:SetAllPoints()
    box.bg:SetColorTexture(0, 0, 0, 0.6)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    share.box = box

    local export = NewButton(share, 150, 24, "Export my settings")
    export:SetPoint("TOPLEFT", 0, -148)
    export:SetScript("OnClick", function()
        if not db then return end
        box:SetText(ExportSettings())
        box:SetFocus()
        box:HighlightText()
        share.status:SetText("Copied into the box and selected: press Ctrl+C.")
    end)
    local import = NewButton(share, 150, 24, "Import from the box")
    import:SetPoint("LEFT", export, "RIGHT", 8, 0)
    import:SetScript("OnClick", function()
        if not db then return end
        local _, message = ImportSettings(box:GetText())
        share.status:SetText(message)
        box:ClearFocus()
    end)
    share.status = Note("", -182)
    share.status:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    Note("To share a setup: Export, copy the text, and send it. To use one: paste it into the box "
        .. "with Ctrl+V and press Import. Import replaces the settings in use, including the position.", -206)

    -- Bindings tab: ClickLegend's own click casting. Editor.lua fills it on
    -- first use.
    local bindings = CreateFrame("Frame", nil, f)
    bindings:SetPoint("TOPLEFT", WIN_PAD, -72)
    bindings:SetPoint("BOTTOMRIGHT", -WIN_PAD, 14)
    bindings:Hide()
    f.bindings = bindings

    local reset = NewButton(f, 110, 24, "Reset to defaults")
    reset:SetPoint("BOTTOMLEFT", WIN_PAD, 14)
    reset:SetScript("OnClick", function() if db then ResetSettings() end end)
    f.reset = reset
    f.hint = NewText(f, 10, 0.6, 0.6, 0.6)
    f.hint:SetPoint("BOTTOMRIGHT", -WIN_PAD, 20)
    f.hint:SetText("Shift-click + or - for bigger steps")
    return f
end

local function RefreshWindowNow()
    local f = window
    f.source:SetText(activeSource and ("showing " .. activeSource) or "no bindings found")
    for name, tab in pairs(f.tabs) do
        if name == activeTab then
            tab.label:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
        else
            tab.label:SetTextColor(1, 1, 1)
        end
    end

    local y = 0
    local function Place(row)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -y)
        row:Show()
        y = y + ROW_H
    end
    for name, rows in pairs(f.rows) do
        for _, row in ipairs(rows) do
            if name == activeTab then
                row.Update()
                Place(row)
            else
                row:Hide()
            end
        end
    end

    f.orderHeader:Hide()
    for _, row in ipairs(f.orderRows) do row:Hide() end
    if activeTab == "Order" then
        local bound = AllBoundKeys()
        if #bound > 0 then Place(f.orderHeader) end
        for i, key in ipairs(bound) do
            local row = f.orderRows[i]
            if not row then
                row = NewOrderRow(f.content)
                f.orderRows[i] = row
            end
            row.key, row.index = key, i
            row.label:SetText(i .. ".  " .. LongKey(key))
            Place(row)
        end
    end

    f.content:SetHeight(max(y, 10))
    local range = max(0, y - (f.scroll:GetHeight() or 0))
    if (f.scroll:GetVerticalScroll() or 0) > range then f.scroll:SetVerticalScroll(range) end
    f.hint:SetShown(activeTab == "Display" or activeTab == "Look")
    f.share:SetShown(activeTab == "Share")
    f.scroll:SetShown(activeTab ~= "Share" and activeTab ~= "Bindings")
    f.reset:SetShown(activeTab ~= "Bindings")        -- it resets the display settings, not bindings
    f.bindings:SetShown(activeTab == "Bindings")
    if activeTab == "Bindings" then
        GetEditor(f.bindings, WIN_W - WIN_PAD * 2):Show()
        RefreshEditor()
    end
end

RefreshWindow = function()
    if window and window:IsShown() and db then Safe(RefreshWindowNow) end
end

-- Opens the window, or closes it when it is already open (unless forced open).
ToggleWindow = function(forceOpen)
    if not db then return end
    if not window then
        local ok, built = pcall(BuildWindow)
        if not ok then Report(built); return end
        window = built
    end
    if window:IsShown() and not forceOpen then
        window:Hide()
        CloseOverlays()
        return
    end
    window:Show()
    RefreshWindow()
end

OpenShareTab = function()
    activeTab = "Share"
    ToggleWindow(true)
end

OpenBindingsTab = function()
    activeTab = "Bindings"
    ToggleWindow(true)
end

-- The Bindings tab with the guided setup open on top of it.
local function OpenGuidedSetup()
    OpenBindingsTab()
    if window and window:IsShown() then ns.OpenWizard(window.bindings, WIN_W - WIN_PAD * 2) end     -- Wizard.lua
end

-- An entry in the game's own AddOns options list that opens the window.
local function RegisterGameOptions()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    local holder = CreateFrame("Frame")
    holder:Hide()
    local text = NewText(holder, 13)
    text:SetPoint("TOPLEFT", 16, -16)
    text:SetText("ClickLegend settings open in their own window.")
    local open = NewButton(holder, 200, 26, "Open ClickLegend settings")
    open:SetPoint("TOPLEFT", 16, -44)
    open:SetScript("OnClick", function() ToggleWindow(true) end)
    local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, holder, "ClickLegend")
    if ok and category then pcall(Settings.RegisterAddOnCategory, category) end
end

function ns.GetWindow() return window end

-------------------------------------------------------------------------------
--  Used by the other files
-------------------------------------------------------------------------------
ns.NewButton           = NewButton
ns.NewText             = NewText
ns.OpenBindingsTab     = OpenBindingsTab
ns.OpenGuidedSetup     = OpenGuidedSetup
ns.OpenShareTab        = OpenShareTab
ns.RefreshWindow       = RefreshWindow
ns.RegisterGameOptions = RegisterGameOptions
ns.ToggleWindow        = ToggleWindow
