require "TimedActions/ISBaseTimedAction"
require "HearingAid/HearingAid"

-- Inserts or removes a hearing aid's battery, or switches the aid on or off. In multiplayer the
-- client runs start() and perform(), and the server rebuilds the action from new()'s parameters
-- and runs complete(), which makes every state change. Single player runs both.
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

-- Whether the action applies to the aid's current state. `battery` is only used to insert one.
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
    if not inventory:containsID(self.aid:getID()) then
        return false
    end
    if self.battery and not inventory:containsID(self.battery:getID()) then
        return false
    end
    -- A multiplayer client's item state can lag behind the server, which checks in complete().
    return isClient() or HearingAidAction.canPerform(self.mode, self.aid, self.battery)
end

function HearingAidAction:start()
    if isClient() then
        -- Server syncs can replace the item objects while the action waits in the queue.
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

-- The server never calls isValid(), so this checks the action again.
function HearingAidAction:complete()
    local aid, character = self.aid, self.character
    if not HearingAidAction.canPerform(self.mode, aid, self.battery) then
        return false
    end
    if self.mode == HearingAidAction.INSERT_BATTERY then
        HearingAid.insertBattery(aid, self.battery)
    elseif self.mode == HearingAidAction.REMOVE_BATTERY then
        HearingAid.removeBattery(character, aid)
    elseif self.mode == HearingAidAction.TURN_ON then
        HearingAid.setOn(aid, true)
    else
        HearingAid.drainUntilNow(character, aid)
        HearingAid.setOn(aid, false)
    end
    aid:syncItemFields()
    HearingAid.reconcile(character)
    return true
end

function HearingAidAction:getDuration()
    if self.character:isTimedActionInstant() then
        return 1
    end
    return DURATIONS[self.mode]
end

-- Parameter names must match the fields set on `o`: the multiplayer server rebuilds the action by
-- passing those fields to new() in parameter order (NetTimedAction).
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
