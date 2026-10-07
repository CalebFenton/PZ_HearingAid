require "TimedActions/ISBaseTimedAction"
require "HearingAid/HearingAid"

-- One action for every hearing aid interaction. In MP the client runs start/update/perform and
-- the server rebuilds the action from new()'s parameters and runs complete(), which owns all
-- state changes. In single player perform() and complete() both run locally.
HearingAidAction = ISBaseTimedAction:derive("HearingAidAction")

HearingAidAction.INSERT_BATTERY = "InsertBattery"
HearingAidAction.REMOVE_BATTERY = "RemoveBattery"
HearingAidAction.TURN_ON = "TurnOn"
HearingAidAction.TURN_OFF = "TurnOff"

local DURATIONS = {
    [HearingAidAction.INSERT_BATTERY] = 60,
    [HearingAidAction.REMOVE_BATTERY] = 60,
    [HearingAidAction.TURN_ON] = 20,
    [HearingAidAction.TURN_OFF] = 20,
}

-- Rules shared by the client menu, isValid and the server-side complete().
function HearingAidAction.canPerform(mode, aid, battery)
    if not HearingAid.isWorking(aid) then
        return false
    end
    if mode == HearingAidAction.INSERT_BATTERY then
        return not HearingAid.hasBattery(aid) and HearingAid.isBattery(battery) and battery:getCurrentUsesFloat() > 0
    elseif mode == HearingAidAction.REMOVE_BATTERY then
        return HearingAid.hasBattery(aid)
    elseif mode == HearingAidAction.TURN_ON then
        return not HearingAid.isOn(aid) and HearingAid.getCharge(aid) > 0
    elseif mode == HearingAidAction.TURN_OFF then
        return HearingAid.isOn(aid)
    end
    return false
end

function HearingAidAction:isValid()
    local inventory = self.character:getInventory()
    if not self.aid or not inventory:containsID(self.aid:getID()) then
        return false
    end
    if self.mode == HearingAidAction.INSERT_BATTERY and (not self.battery or not inventory:containsID(self.battery:getID())) then
        return false
    end
    if isClient() then
        -- The server re-checks in complete(); client modData can lag behind it.
        return true
    end
    return HearingAidAction.canPerform(self.mode, self.aid, self.battery)
end

function HearingAidAction:start()
    if isClient() then
        -- Item objects can be replaced by server syncs while the action waits in the queue.
        local inventory = self.character:getInventory()
        self.aid = inventory:getItemById(self.aid:getID())
        if self.battery then
            self.battery = inventory:getItemById(self.battery:getID())
        end
    end
    if self.aid:isWorn() then
        self:setActionAnim("WearClothing")
        self:setAnimVariable("WearClothingLocation", "Face")
    else
        self:setActionAnim(CharacterActionAnims.Craft)
    end
end

function HearingAidAction:perform()
    if self.mode == HearingAidAction.TURN_ON then
        self.character:playSound("FlashlightOn")
    elseif self.mode == HearingAidAction.TURN_OFF then
        self.character:playSound("FlashlightOff")
    end
    ISInventoryPage.renderDirty = true
    ISBaseTimedAction.perform(self)
end

function HearingAidAction:complete()
    local aid, player = self.aid, self.character
    if not aid or not HearingAidAction.canPerform(self.mode, aid, self.battery) then
        return false
    end

    if self.mode == HearingAidAction.INSERT_BATTERY then
        local battery = self.battery
        local charge = HearingAid.getBatteryCharge(battery)
        local container = battery:getContainer()
        container:Remove(battery)
        sendRemoveItemFromContainer(container, battery)
        HearingAid.setBattery(aid, charge)
    elseif self.mode == HearingAidAction.REMOVE_BATTERY then
        HearingAid.settle(player, aid)
        local battery = instanceItem("Base.Battery")
        battery:setCurrentUsesFloat(HearingAid.getCharge(aid))
        Actions.addOrDropItem(player, battery)
        HearingAid.clearBattery(aid)
    elseif self.mode == HearingAidAction.TURN_ON then
        HearingAid.setOn(aid, true)
    elseif self.mode == HearingAidAction.TURN_OFF then
        HearingAid.settle(player, aid)
        HearingAid.setOn(aid, false)
    end

    HearingAid.syncItem(player, aid)
    HearingAid.reconcile(player)
    return true
end

function HearingAidAction:getDuration()
    if self.character:isTimedActionInstant() then
        return 1
    end
    return DURATIONS[self.mode] or 30
end

-- Parameter names must match the fields set on `o`: the MP server rebuilds the action by
-- reading those fields in parameter order (NetTimedAction).
function HearingAidAction:new(character, mode, aid, battery)
    local o = ISBaseTimedAction.new(self, character)
    o.mode = mode
    o.aid = aid
    o.battery = battery
    o.stopOnWalk = false
    o.stopOnRun = true
    o.ignoreHandsWounds = true
    o.maxTime = o:getDuration()
    return o
end
