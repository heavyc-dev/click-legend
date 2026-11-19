-------------------------------------------------------------------------------
--  ClickLegend - Skin.lua
--  How the settings window, its lists and the cards look: the game's own
--  panel, buttons, tabs, check boxes and edit boxes, so the addon reads as
--  part of the interface. Every piece is made from one of the game's
--  templates when the client has it, and from plain textures when it does
--  not, so the window still opens on a client that lacks one.
--
--  The legend itself (Display.lua) is not drawn from here.
-------------------------------------------------------------------------------
local _, ns = ...

local pcall, rawget, setmetatable, type = pcall, rawget, setmetatable, type

local ApplyFont = ns.ApplyFont

local Skin = {}

-- The interface's own text colors: gold for headings and button text, white
-- for what is picked or switched on, green for "on", grey for what is off.
local GOLD, WHITE, GREEN, GREY = { 1, 0.82, 0 }, { 1, 1, 1 }, { 0.25, 1, 0.25 }, { 0.5, 0.5, 0.5 }
Skin.ACCENT, Skin.NORMAL, Skin.PICKED, Skin.ON, Skin.OFF = GOLD, GOLD, WHITE, GREEN, GREY

local ROCK = "Interface\\FrameGeneral\\UI-Background-Rock"
local HOVER = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
local SELECTED = "Interface\\QuestFrame\\UI-QuestLogTitleHighlight"

-- A frame from one of the game's templates, or nil when this client has no
-- such template (CreateFrame raises an error then). A template that failed
-- once is not tried again.
local missing = {}
local function Make(kind, name, parent, template)
    if missing[template] then return nil end
    local ok, frame = pcall(CreateFrame, kind, name, parent, template)
    if ok and frame then return frame end
    missing[template] = true
    return nil
end

-- A piece a template made (its title text, its close button). A plain field
-- read would do on the client; rawget keeps an object that answers to every
-- name from passing for one.
local function Part(frame, key)
    local part = type(frame) == "table" and rawget(frame, key) or nil
    return type(part) == "table" and part or nil
end

-- Whether the game's look is in use at all: decided once, by the button.
local native
local function Native()
    if native == nil then
        local probe = Make("Button", nil, UIParent, "UIPanelButtonNoTooltipTemplate")
        native = probe ~= nil
        if probe then probe:Hide() end
    end
    return native
end

-- Stands in for a button's background where the template draws the button:
-- the callers that tint it on hover go on working and change nothing.
local function Nothing() end
local NO_TEXTURE = setmetatable({}, { __index = function() return Nothing end })

-------------------------------------------------------------------------------
--  Text
-------------------------------------------------------------------------------
-- The game's font for a size the code asks for, where the client has the
-- font objects; the legend's font otherwise.
local function Font(fs, size)
    local name = (size >= 15 and "GameFontNormalLarge") or (size >= 12 and "GameFontHighlight") or "GameFontHighlightSmall"
    local object = Native() and _G[name]
    if type(object) == "table" and fs.SetFontObject then
        fs:SetFontObject(object)
    else
        ApplyFont(fs, size)
    end
end

-------------------------------------------------------------------------------
--  Buttons
-------------------------------------------------------------------------------
-- A push button with `label` (its text) and `bg`. The text is the button's
-- own font string, not the template's, so a caller can color it to show a
-- state and it stays that color.
local function Button(parent, w, h, text)
    local b = Make("Button", nil, parent, "UIPanelButtonNoTooltipTemplate")
    if b then
        b.native = true
        b.bg = NO_TEXTURE
    else
        b = CreateFrame("Button", nil, parent)
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetAllPoints()
        b.bg:SetColorTexture(0.16, 0.17, 0.19, 1)
        b:SetScript("OnEnter", function(self) self.bg:SetColorTexture(0.26, 0.28, 0.31, 1) end)
        b:SetScript("OnLeave", function(self) self.bg:SetColorTexture(0.16, 0.17, 0.19, 1) end)
    end
    b:SetSize(w, h)
    b.label = b:CreateFontString(nil, "OVERLAY")
    Font(b.label, 11)
    if b.native then b.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) else b.label:SetTextColor(1, 1, 1) end
    b.label:SetPoint("CENTER")
    b.label:SetText(text or "")
    return b
end

-- The color a button's text has when nothing is said about it.
local function Plain(button)
    if button.native then
        button.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    else
        button.label:SetTextColor(1, 1, 1)
    end
end

-- A button's text stands out: the one to press, the one picked.
local function Emph(button)
    local color = button.native and WHITE or GOLD
    button.label:SetTextColor(color[1], color[2], color[3])
end

-- A button that is one of several switches: on or off. `lit` says which.
local function Lit(button, on)
    button.lit = on and true or false
    if on then
        Emph(button)
        button.bg:SetColorTexture(0.10, 0.30, 0.25, 1)
        if button.native and button.LockHighlight then button:LockHighlight() end
    else
        button.label:SetTextColor(GREY[1], GREY[2], GREY[3])
        button.bg:SetColorTexture(0.16, 0.17, 0.19, 1)
        if button.native and button.UnlockHighlight then button:UnlockHighlight() end
    end
end

-- A check box: `SetChecked`, `GetChecked`, and an `OnClick` of the caller's.
local function Check(parent)
    local c = CreateFrame("CheckButton", nil, parent)
    c:SetSize(24, 24)
    c:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    c:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    c:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    c:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    return c
end

-- Marks a button as one that opens a list: a small arrow at its right end.
local function Arrow(button)
    if not Native() or rawget(button, "arrow") then return end
    local arrow = button:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(16, 16)
    arrow:SetPoint("RIGHT", -3, 0)
    arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    button.arrow = arrow
    button.label:ClearAllPoints()
    button.label:SetPoint("LEFT", 8, 0)
    button.label:SetPoint("RIGHT", arrow, "LEFT", -2, 0)
    if button.label.SetWordWrap then button.label:SetWordWrap(false) end
end

-- The game's slider, or nil on a client without it: the caller then keeps
-- to its minus and plus.
local function Slider(parent, w)
    local slider = Make("Slider", nil, parent, "UISliderTemplate")
    if not slider then return nil end
    slider:SetSize(w, 16)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    return slider
end

-------------------------------------------------------------------------------
--  Panels
-------------------------------------------------------------------------------
-- A window: the game's metal frame with a title bar, or a flat dark box.
-- `f.top` is how far down its contents may begin.
local function Panel(name, parent, title)
    local f = Make("Frame", name, parent, "DefaultPanelTemplate")
    if f then
        f.native = true
        f.top = 24
        local text = Part(Part(f, "TitleContainer"), "TitleText")
        if text then
            text:SetText(title or "")
            f.title = text
        end
    else
        f = CreateFrame("Frame", name, parent)
        f.top = 30
        local edge = f:CreateTexture(nil, "BACKGROUND")
        edge:SetAllPoints()
        edge:SetColorTexture(0, 0, 0, 1)
        local fill = f:CreateTexture(nil, "BORDER")
        fill:SetPoint("TOPLEFT", 1, -1)
        fill:SetPoint("BOTTOMRIGHT", -1, 1)
        fill:SetColorTexture(0.07, 0.08, 0.09, 0.97)
    end
    if not f.title then
        f.title = f:CreateFontString(nil, "OVERLAY")
        Font(f.title, 12)
        f.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
        f.title:SetPoint("TOP", 0, f.native and -5 or -10)
        f.title:SetText(title or "")
    end
    return f
end

-- The X in a panel's corner.
local function Close(f, onClick)
    local b = f.native and Make("Button", nil, f, "UIPanelCloseButtonDefaultAnchors")
    if not b then
        b = Button(f, 22, 22, "X")
        b:SetPoint("TOPRIGHT", -8, -8)
    end
    b:SetScript("OnClick", onClick)
    return b
end

-- A sunken area behind a list. The caller places it.
local function Inset(parent)
    local f = Make("Frame", nil, parent, "InsetFrameTemplate")
    if not f then
        f = CreateFrame("Frame", nil, parent)
        local fill = f:CreateTexture(nil, "BACKGROUND")
        fill:SetAllPoints()
        fill:SetColorTexture(0, 0, 0, 0.25)
    end
    return f
end

-- Something that opens over the window: a list to pick from. The tooltip's
-- border and a dark fill.
local function Popup(name, parent)
    local f = Make("Frame", name, parent, "BackdropTemplate")
    if f then
        f:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        f:SetBackdropColor(0.05, 0.05, 0.06, 0.97)
        f:SetBackdropBorderColor(0.8, 0.8, 0.8, 1)
    else
        f = CreateFrame("Frame", name, parent)
        local edge = f:CreateTexture(nil, "BACKGROUND")
        edge:SetAllPoints()
        edge:SetColorTexture(0, 0, 0, 1)
        local fill = f:CreateTexture(nil, "BORDER")
        fill:SetPoint("TOPLEFT", 1, -1)
        fill:SetPoint("BOTTOMRIGHT", -1, 1)
        fill:SetColorTexture(0.10, 0.11, 0.13, 1)
    end
    return f
end

-- The fill of something that covers part of a panel (the guided setup over
-- the Bindings tab): the panel's own stone, so it reads as the same window.
local function Fill(texture)
    if Native() then
        texture:SetTexture(ROCK, "REPEAT", "REPEAT")
        if texture.SetHorizTile then texture:SetHorizTile(true); texture:SetVertTile(true) end
    else
        texture:SetColorTexture(0.07, 0.08, 0.09, 1)
    end
end

-------------------------------------------------------------------------------
--  Rows, tabs, edit boxes
-------------------------------------------------------------------------------
-- The bar behind a row of a list: under the cursor, or the picked one.
local function Bar(texture, picked)
    if Native() then
        texture:SetTexture(picked and SELECTED or HOVER)
        if texture.SetBlendMode then texture:SetBlendMode("ADD") end
        if picked then texture:SetVertexColor(1, 0.82, 0, 0.9) else texture:SetVertexColor(1, 1, 1, 0.7) end
    elseif picked then
        texture:SetColorTexture(0.10, 0.30, 0.25, 1)
    else
        texture:SetColorTexture(0.26, 0.28, 0.31, 1)
    end
end

-- A one-line edit box.
local function EditBox(parent, w, h)
    local box = Make("EditBox", nil, parent, "InputBoxTemplate")
    if box then
        box.native = true
        box.bg = NO_TEXTURE
    else
        box = CreateFrame("EditBox", nil, parent)
        box:SetFont(STANDARD_TEXT_FONT, 11, "")
        box:SetTextInsets(5, 5, 0, 0)
        box.bg = box:CreateTexture(nil, "BACKGROUND")
        box.bg:SetAllPoints()
        box.bg:SetColorTexture(0, 0, 0, 0.6)
    end
    box:SetSize(w, h or 20)
    box:SetAutoFocus(false)
    return box
end

-- A tab under a panel's bottom edge, the way the character window has them.
-- `after` is the tab to its left.
local function Tab(f, text, after)
    local tab = f.native and Make("Button", nil, f, "PanelTabButtonTemplate")
    if tab then
        tab.native = true
        tab:SetText(text)
        if PanelTemplates_TabResize and Part(tab, "Text") then pcall(PanelTemplates_TabResize, tab, 0) end
        if after then tab:SetPoint("TOPLEFT", after, "TOPRIGHT", 1, 0) else tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 11, 2) end
    else
        tab = Button(f, 70, 22, text)
        if after then tab:SetPoint("TOPLEFT", after, "TOPRIGHT", 4, 0) else tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 8, -2) end
    end
    return tab
end

-- Shows which tab is the open one.
local function PickTab(tab, picked)
    local label = rawget(tab, "label")
    if label then                           -- a plain button standing in for a tab
        local color = picked and (tab.native and WHITE or GOLD) or (tab.native and GOLD or WHITE)
        label:SetTextColor(color[1], color[2], color[3])
    elseif PanelTemplates_SelectTab and Part(tab, "Left") then
        pcall(picked and PanelTemplates_SelectTab or PanelTemplates_DeselectTab, tab)
    end
end

-------------------------------------------------------------------------------
--  Used by the other files
-------------------------------------------------------------------------------
Skin.Arrow    = Arrow
Skin.Bar      = Bar
Skin.Button   = Button
Skin.Check    = Check
Skin.Close    = Close
Skin.EditBox  = EditBox
Skin.Emph     = Emph
Skin.Fill     = Fill
Skin.Font     = Font
Skin.Inset    = Inset
Skin.Lit      = Lit
Skin.Native   = Native
Skin.Panel    = Panel
Skin.PickTab  = PickTab
Skin.Slider   = Slider
Skin.Plain    = Plain
Skin.Popup    = Popup
Skin.Tab      = Tab
ns.Skin       = Skin
