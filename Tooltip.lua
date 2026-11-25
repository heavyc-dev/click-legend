-------------------------------------------------------------------------------
--  ClickLegend - Tooltip.lua
--  The binding lines added to unit tooltips.
-------------------------------------------------------------------------------
local _, ns = ...

local ipairs, type, tostring, pcall = ipairs, type, tostring, pcall

local db
local layers
ns.Subscribe("db", function(value) db = value end)
ns.Subscribe("layers", function(value) layers = value end)

local HeldMods, LongKey, ModsLong, OrderKeys, Safe =
    ns.HeldMods, ns.LongKey, ns.ModsLong, ns.OrderKeys, ns.Safe
local OverWorld, SideColor =
    ns.OverWorld, ns.SideColor

-------------------------------------------------------------------------------
--  Unit tooltip: the bindings that apply to the unit under the cursor.
--  A friendly unit lists the ally spells, an attackable one the enemy spells,
--  for the modifiers held when the tooltip is built.
-------------------------------------------------------------------------------
local function TooltipUnit(tooltip)
    if UnitExists and UnitExists("mouseover") then return "mouseover" end
    if tooltip.GetUnit then
        local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
        if ok and type(unit) == "string" then return unit end
    end
    return nil
end

local function AddTooltipBindingsNow(tooltip)
    if tooltip ~= GameTooltip or not db or not db.tooltip or not layers then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    if not db.tooltipWorld and OverWorld() then return end
    if db.hideNPC and ns.OverNPC() then return end
    local unit = TooltipUnit(tooltip)
    if not unit then return end
    local ok, hostile = pcall(UnitCanAttack, "player", unit)
    if not ok or (issecretvalue and issecretvalue(hostile)) then return end
    local side = hostile and "enemy" or "ally"
    local r, g, b = SideColor(side)

    local held = HeldMods()
    local layer = layers[held]
    if not layer then return end
    local added = false
    for _, key in ipairs(OrderKeys(layer.keys)) do
        local entry = layer.byKey[key][side]
        if entry then
            if not added then tooltip:AddLine(" "); added = true end
            local keyName = (held ~= "" and (ModsLong(held) .. "+") or "") .. LongKey(key)
            tooltip:AddDoubleLine(keyName,
                "|T" .. tostring(entry.icon) .. ":14:14:0:0:64:64:5:59:5:59|t " .. entry.name
                    .. ((entry.missing and db.flagMissing) and " (not available)" or ""),
                0.7, 0.7, 0.7, r, g, b)
        end
    end
    if added then tooltip:Show() end
end

local function AddTooltipBindings(tooltip)
    Safe(AddTooltipBindingsNow, tooltip)
end

-- Some unit frames (party and raid frames among them) build their tooltip once
-- and never refresh it, so a modifier pressed while hovering would leave the
-- old layer's lines up. Rebuild the unit tooltip when the modifiers change.
local function RefreshUnitTooltipNow()
    local tip = GameTooltip
    if not (tip and db and db.tooltip and layers) then return end
    if tip.IsForbidden and tip:IsForbidden() then return end
    if not (tip.IsShown and tip:IsShown()) then return end
    if not db.tooltipWorld and OverWorld() then return end
    if not tip.GetUnit then return end
    local name, unit = tip:GetUnit()
    if not name then return end                            -- not a unit tooltip
    if tip.RefreshData then
        tip:RefreshData()
    elseif tip.SetUnit then
        if type(unit) ~= "string" then unit = TooltipUnit(tip) end
        if unit then tip:SetUnit(unit) end
    end
end

-- Silent on failure: this runs on every modifier press, and a tooltip that
-- cannot be rebuilt right now just keeps its old lines.
local function RefreshUnitTooltip()
    pcall(RefreshUnitTooltipNow)
end

local function HookTooltip()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, AddTooltipBindings)
    elseif GameTooltip and GameTooltip.HookScript then
        pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", AddTooltipBindings)
    end
end

-------------------------------------------------------------------------------
--  Used by the other files
-------------------------------------------------------------------------------
ns.HookTooltip        = HookTooltip
ns.RefreshUnitTooltip = RefreshUnitTooltip
