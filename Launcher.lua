-------------------------------------------------------------------------------
--  ClickLegend - Launcher.lua
--  Two ways in for someone who has not typed /clg yet: a minimap button with
--  the addon's logo, and a welcome window shown once after installing or
--  updating to 2.0.
-------------------------------------------------------------------------------
local _, ns = ...

local type, pcall = type, pcall
local cos, sin, rad, deg, atan2, max = math.cos, math.sin, math.rad, math.deg, math.atan2, math.max

local db
ns.Subscribe("db", function(value) db = value end)

local ACCENT, ApplyFont, NewButton, NewText, Safe =
    ns.ACCENT, ns.ApplyFont, ns.NewButton, ns.NewText, ns.Safe
local OpenGuidedSetup, ToggleWindow =
    ns.OpenGuidedSetup, ns.ToggleWindow

local LOGO = "Interface\\AddOns\\ClickLegend\\ClickLegend-Logo.png"
-- The logo is the legend's grid on a dark square; this is the grid alone.
local LOGO_CROP = { 0.09, 0.91, 0.30, 0.70 }

-------------------------------------------------------------------------------
--  Minimap button. Left click: the settings window. Right click: guided
--  setup. Drag: move it round the minimap.
-------------------------------------------------------------------------------
local button

local function PlaceButton()
    if not (button and db and Minimap) then return end
    local angle = rad(db.minimapAngle)
    local radius = max(Minimap:GetWidth() or 140, Minimap:GetHeight() or 140) / 2 + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", cos(angle) * radius, sin(angle) * radius)
end

local function DragButton()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale() or 1
    if not (mx and my and cx and cy) then return end
    local angle = deg(atan2(cy / scale - my, cx / scale - mx))
    db.minimapAngle = angle < 0 and angle + 360 or angle
    PlaceButton()
end

local function BuildButton()
    local b = CreateFrame("Button", "ClickLegendMinimapButton", Minimap)
    b:SetSize(32, 32)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("AnyUp")
    b:RegisterForDrag("LeftButton")
    local back = b:CreateTexture(nil, "BACKGROUND")
    back:SetSize(24, 24)
    back:SetPoint("CENTER")
    back:SetColorTexture(0.07, 0.08, 0.09, 1)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(22, 11)                        -- the grid is twice as wide as it is tall
    icon:SetPoint("CENTER")
    icon:SetTexture(LOGO)
    icon:SetTexCoord(LOGO_CROP[1], LOGO_CROP[2], LOGO_CROP[3], LOGO_CROP[4])
    local ring = b:CreateTexture(nil, "OVERLAY")
    ring:SetSize(54, 54)
    ring:SetPoint("TOPLEFT")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then Safe(OpenGuidedSetup) else Safe(ToggleWindow) end
    end)
    b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", function() Safe(DragButton) end) end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("ClickLegend", ACCENT[1], ACCENT[2], ACCENT[3])
        GameTooltip:AddLine("Click: settings", 1, 1, 1)
        GameTooltip:AddLine("Right click: guided setup", 1, 1, 1)
        GameTooltip:AddLine("Drag: move this button", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return b
end

-- Shows, hides and places the button to match the settings.
local function UpdateMinimapButton()
    if not (db and Minimap) then return end
    if db.minimap and not button then
        local ok, built = pcall(BuildButton)
        if not ok then ns.Report(built); return end
        button = built
    end
    if button then
        button:SetShown(db.minimap)
        if db.minimap then PlaceButton() end
    end
end

-------------------------------------------------------------------------------
--  Welcome: once per account, the first time a version with its own click
--  casting is run. It offers the two places to begin and never comes back.
-------------------------------------------------------------------------------
local WELCOME_VERSION = 2
local welcome

local function Seen()
    if type(ClickLegendCastDB) == "table" then ClickLegendCastDB.welcomed = WELCOME_VERSION end
    if welcome then welcome:Hide() end
end

local function BuildWelcome()
    local f = CreateFrame("Frame", "ClickLegendWelcome", UIParent)
    f:SetSize(380, 250)
    f:SetPoint("CENTER", 0, 60)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:Hide()
    local edge = f:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints()
    edge:SetColorTexture(0, 0, 0, 1)
    local fill = f:CreateTexture(nil, "BORDER")
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", -1, 1)
    fill:SetColorTexture(0.07, 0.08, 0.09, 0.98)

    local logo = f:CreateTexture(nil, "ARTWORK")
    logo:SetSize(120, 60)
    logo:SetPoint("TOP", 0, -16)
    logo:SetTexture(LOGO)
    logo:SetTexCoord(LOGO_CROP[1], LOGO_CROP[2], LOGO_CROP[3], LOGO_CROP[4])

    local title = NewText(f, 16, ACCENT[1], ACCENT[2], ACCENT[3])
    title:SetPoint("TOP", 0, -86)
    title:SetText("Welcome to ClickLegend")
    local text = NewText(f, 11, 0.85, 0.85, 0.85)
    text:SetPoint("TOP", 0, -112)
    text:SetWidth(340)
    text:SetText("The legend shows what your click-cast keys do. It can also do the click casting itself, "
        .. "with rules like \"dead ally: resurrect, ally: heal, enemy: damage\" on one key.\n\n"
        .. "The guided setup takes a few minutes. You can open either one later with /clg or the minimap button.")

    local guide = NewButton(f, 130, 26, "Guided setup")
    guide:SetPoint("BOTTOMLEFT", 16, 16)
    guide.label:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    guide:SetScript("OnClick", function() Seen(); Safe(OpenGuidedSetup) end)
    local settings = NewButton(f, 110, 26, "Open settings")
    settings:SetPoint("LEFT", guide, "RIGHT", 8, 0)
    settings:SetScript("OnClick", function() Seen(); Safe(ToggleWindow, true) end)
    local later = NewButton(f, 80, 26, "Not now")
    later:SetPoint("BOTTOMRIGHT", -16, 16)
    later:SetScript("OnClick", Seen)
    f.guide, f.settings, f.later = guide, settings, later
    return f
end

-- Shows the welcome window; `again` shows it even when it has been seen.
local function ShowWelcome(again)
    if type(ClickLegendCastDB) ~= "table" then return false end
    if not again and (ClickLegendCastDB.welcomed or 0) >= WELCOME_VERSION then return false end
    if not welcome then
        local ok, built = pcall(BuildWelcome)
        if not ok then ns.Report(built); return false end
        welcome = built
    end
    welcome:Show()
    return true
end

-- At login: the button at once, the welcome a moment later, when the rest
-- of the interface has settled.
local function StartLauncher()
    UpdateMinimapButton()
    if C_Timer and C_Timer.After then
        C_Timer.After(3, function() Safe(ShowWelcome) end)
    else
        Safe(ShowWelcome)
    end
end

-------------------------------------------------------------------------------
--  Used by the other files
-------------------------------------------------------------------------------
ns.GetWelcome          = function() return welcome end
ns.ShowWelcome         = ShowWelcome
ns.StartLauncher       = StartLauncher
ns.UpdateMinimapButton = UpdateMinimapButton
