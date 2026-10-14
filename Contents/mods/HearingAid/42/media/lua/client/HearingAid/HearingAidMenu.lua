require "Vehicles/ISUI/ISVehicleMechanics"
require "HearingAid/HearingAid"
require "TimedActions/HearingAidAction"

local function queueAction(player, mode, aid, battery)
    ISInventoryPaneContextMenu.transferIfNeeded(player, aid)
    if battery then
        ISInventoryPaneContextMenu.transferIfNeeded(player, battery)
    end
    ISTimedActionQueue.add(HearingAidAction:new(player, mode, aid, battery))
end

local function addActionOption(context, player, labelKey, mode, aid, battery)
    return context:addOption(getText(labelKey), player, queueAction, mode, aid, battery)
end

local function disable(option, description)
    option.notAvailable = true
    option.toolTip = ISInventoryPaneContextMenu.addToolTip()
    option.toolTip.description = description
end

-- What Add Battery lacks with no charged battery carried, listed the way vanilla's mechanics
-- window lists what a job needs (ISVehicleMechanics.doMenuTooltip), in its bad colour.
local function needsBattery()
    return getText("Tooltip_craft_Needs") .. " : <LINE> " .. ISVehicleMechanics.bhs
        .. getItemNameFromFullType(HearingAid.BATTERY) .. " 0/1 <LINE>"
end

-- Batteries anywhere in the inventory, bags included, that can go into the aid, fullest first.
local function insertableBatteries(player, aid)
    local found = player:getInventory():getAllEvalRecurse(function(item)
        return HearingAidAction.canPerform(HearingAidAction.INSERT_BATTERY, aid, item)
    end)
    local batteries = {}
    for i = 0, found:size() - 1 do
        table.insert(batteries, found:get(i))
    end
    table.sort(batteries, function(a, b)
        return a:getCurrentUsesFloat() > b:getCurrentUsesFloat()
    end)
    return batteries
end

local function addBatteryOptions(context, player, aid)
    local option = context:addOption(getText("ContextMenu_AddBattery"))
    local batteries = insertableBatteries(player, aid)
    if #batteries == 0 then
        disable(option, needsBattery())
        return
    end
    local submenu = context:getNew(context)
    context:addSubMenu(option, submenu)
    for _, battery in ipairs(batteries) do
        local label = getText("ContextMenu_HearingAid_BatteryCharge", battery:getDisplayName(), round(battery:getCurrentUsesFloat() * 100))
        submenu:addOption(label, player, queueAction, HearingAidAction.INSERT_BATTERY, aid, battery)
    end
end

local function addOptions(context, player, aid)
    if not HearingAid.hasBattery(aid) then
        addBatteryOptions(context, player, aid)
        return
    end
    if HearingAid.isOn(aid) then
        addActionOption(context, player, "ContextMenu_Turn_Off", HearingAidAction.TURN_OFF, aid)
    else
        local option = addActionOption(context, player, "ContextMenu_Turn_On", HearingAidAction.TURN_ON, aid)
        if not HearingAidAction.canPerform(HearingAidAction.TURN_ON, aid) then
            disable(option, getText("IGUI_HearingAid_BatteryDead"))
        end
    end
    addActionOption(context, player, "ContextMenu_Remove_Battery", HearingAidAction.REMOVE_BATTERY, aid)
end

local function onFillInventoryObjectContextMenu(playerNum, context, items)
    local player = getSpecificPlayer(playerNum)
    for _, item in ipairs(ISInventoryPane.getActualItems(items)) do
        if HearingAid.isWorking(item) then
            addOptions(context, player, item)
            return
        end
    end
end

Events.OnFillInventoryObjectContextMenu.Add(onFillInventoryObjectContextMenu)
