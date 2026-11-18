-------------------------------------------------------------------------------
--  ClickLegend - Launcher.lua
--  Two ways in for someone who has not typed /clg yet: a minimap button with
--  the addon's logo, and a welcome window shown once after installing or
--  updating to 2.0. Someone who has already seen that window gets the same
--  window once more, saying what is new and offering the guided setup again,
--  when an update brings something worth knowing about.
-------------------------------------------------------------------------------
local _, ns = ...

local type, pcall, tonumber = type, pcall, tonumber
local cos, sin, rad, deg, atan2, max = math.cos, math.sin, math.rad, math.deg, math.atan2, math.max

local db
ns.Subscribe("db", function(value) db = value end)

local ACCENT, NewButton, NewText, Safe =
    ns.ACCENT, ns.NewButton, ns.NewText, ns.Safe
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

    -- What it says is set each time it is shown: the welcome, or what is new.
    local title = NewText(f, 16, ACCENT[1], ACCENT[2], ACCENT[3])
    title:SetPoint("TOP", 0, -86)
    local text = NewText(f, 11, 0.85, 0.85, 0.85)
    text:SetPoint("TOP", 0, -112)
    text:SetWidth(340)
    f.title, f.text = title, text

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

local WELCOME_TEXT = "Click casting: click a unit frame to cast on that player, without targeting. "
    .. "Hover casting: press a key to cast on whoever is under your cursor.\n\n"
    .. "One key can do several things (dead ally: resurrect, ally: heal, enemy: damage), "
    .. "and a legend on screen shows what every key does.\n\n"
    .. "The guided setup takes about a minute. /clg opens the settings later."

-- What is new, for someone who already uses the addon. Shown once per
-- account for each NEWS_VERSION; raise it, and rewrite NEWS_TEXT, only when
-- a release has something worth stopping a player for.
local NEWS_VERSION = 4              -- 1: 2.1.0 (a line in chat), 2: 2.1.1 (this window), 3: 2.2.0, 4: hide Target and Menu
local NEWS_TEXT = "New in this version:\n\n"
    .. "The legend can leave out the plain left click that targets and the "
    .. "right click that opens the menu. Both keep working, in Clique or any "
    .. "other addon too; the legend is just shorter.\n\n"
    .. "Switch it on with /clg basics, or in the settings: Display, "
    .. "\"Hide the plain Target and Menu clicks\".\n\n"
    .. "Thank you to dekazakoff for the suggestion."

-- The window, made on first use, saying one thing or the other.
local function ShowCard(height, title, text, justify, guideLabel)
    if not welcome then
        local ok, built = pcall(BuildWelcome)
        if not ok then ns.Report(built); return false end
        welcome = built
    end
    welcome:SetHeight(height)
    welcome.title:SetText(title)
    welcome.text:SetText(text)
    welcome.text:SetJustifyH(justify)
    welcome.guide.label:SetText(guideLabel)
    welcome:Show()
    return true
end

-- Shows the welcome window; `again` shows it even when it has been seen.
local function ShowWelcome(again)
    if type(ClickLegendCastDB) ~= "table" then return false end
    if not again and (ClickLegendCastDB.welcomed or 0) >= WELCOME_VERSION then return false end
    return ShowCard(280, "Welcome to ClickLegend", WELCOME_TEXT, "CENTER", "Guided setup")
end

-- Shows what is new, once; `again` shows it whether or not it has been seen.
-- Someone being shown the welcome window (`welcoming`) is not shown this as
-- well: the welcome says it all, and what is new is new to nobody then.
local function ShowNews(again, welcoming)
    local store = ClickLegendCastDB
    if type(store) ~= "table" then return false end
    local seen = (tonumber(store.news) or 0) >= NEWS_VERSION
    store.news = NEWS_VERSION
    if welcoming or (seen and not again) then return false end
    return ShowCard(300, "What is new in ClickLegend", NEWS_TEXT, "LEFT", "Guided setup")
end

-- At login: the button at once, the welcome a moment later, when the rest
-- of the interface has settled.
local function StartLauncher()
    UpdateMinimapButton()
    local function Greet()
        local welcoming = false
        Safe(function() welcoming = ShowWelcome() end)
        Safe(ShowNews, false, welcoming)
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(3, Greet)
    else
        Greet()
    end
end

-------------------------------------------------------------------------------
--  Used by the other files
-------------------------------------------------------------------------------
ns.GetWelcome          = function() return welcome end
ns.ShowNews            = ShowNews
ns.ShowWelcome         = ShowWelcome
ns.StartLauncher       = StartLauncher
ns.UpdateMinimapButton = UpdateMinimapButton
