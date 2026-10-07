require "HearingAid/HearingAid"
require "TimedActions/HearingAidAction"

HearingAidMenu = {}

local function percent(fraction)
    return math.floor(math.max(0, math.min(1, fraction)) * 100 + 0.5)
end

local function disable(option, tooltipKey)
    option.notAvailable = true
    option.toolTip = ISInventoryPaneContextMenu.addToolTip()
    option.toolTip.description = getText(tooltipKey)
end

function HearingAidMenu.queue(player, mode, aid, battery)
    ISInventoryPaneContextMenu.transferIfNeeded(player, aid)
    if battery then
        ISInventoryPaneContextMenu.transferIfNeeded(player, battery)
    end
    ISTimedActionQueue.add(HearingAidAction:new(player, mode, aid, battery))
end

function HearingAidMenu.addOptions(player, context, aid)
    local queue = HearingAidMenu.queue
    if HearingAid.hasBattery(aid) then
        if HearingAid.isOn(aid) then
            context:addOption(getText("ContextMenu_Turn_Off"), player, queue, HearingAidAction.TURN_OFF, aid)
        else
            local option = context:addOption(getText("ContextMenu_Turn_On"), player, queue, HearingAidAction.TURN_ON, aid)
            if HearingAid.getCharge(aid) <= 0 then
                disable(option, "Tooltip_HearingAid_BatteryDead")
            end
        end
        context:addOption(getText("ContextMenu_Remove_Battery"), player, queue, HearingAidAction.REMOVE_BATTERY, aid)
        return
    end

    local option = context:addOption(getText("ContextMenu_AddBattery"))
    local batteries = HearingAid.findBatteries(player)
    if #batteries == 0 then
        disable(option, "Tooltip_HearingAid_NoBattery")
        return
    end
    local submenu = context:getNew(context)
    context:addSubMenu(option, submenu)
    for _, battery in ipairs(batteries) do
        local label = battery:getDisplayName() .. " (" .. percent(HearingAid.getBatteryCharge(battery)) .. "%)"
        submenu:addOption(label, player, queue, HearingAidAction.INSERT_BATTERY, aid, battery)
    end
end

function HearingAidMenu.onFillInventoryObjectContextMenu(playerNum, context, items)
    local player = getSpecificPlayer(playerNum)
    if not player then
        return
    end
    for _, item in ipairs(ISInventoryPane.getActualItems(items)) do
        if HearingAid.isWorking(item) then
            HearingAidMenu.addOptions(player, context, item)
            return
        end
    end
end

Events.OnFillInventoryObjectContextMenu.Add(HearingAidMenu.onFillInventoryObjectContextMenu)
