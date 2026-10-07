require "HearingAid/HearingAid"

-- Helpers for the debug scenario and unit tests (debug mode only; nothing here runs on its own).
HearingAidDebug = {}

local Level = HearingAid.Level

-- Sets the character's hearing traits and forgets anything the mod applied.
function HearingAidDebug.setHearing(player, level)
    local traits = player:getCharacterTraits()
    traits:remove(CharacterTrait.DEAF)
    traits:remove(CharacterTrait.HARD_OF_HEARING)
    traits:remove(CharacterTrait.KEEN_HEARING)
    if level == Level.DEAF then
        traits:add(CharacterTrait.DEAF)
    elseif level == Level.HARD_OF_HEARING then
        traits:add(CharacterTrait.HARD_OF_HEARING)
    elseif level == Level.KEEN then
        traits:add(CharacterTrait.KEEN_HEARING)
    end
    local md = player:getModData()
    md.HearingAid_baseLevel = nil
    md.HearingAid_appliedLevel = nil
end

-- Adds a hearing aid with an exact battery state (charge nil = no battery).
function HearingAidDebug.addAid(player, fullType, charge, on)
    local aid = player:getInventory():AddItem(fullType)
    HearingAid.clearBattery(aid)
    if charge then
        HearingAid.setBattery(aid, charge)
        HearingAid.setOn(aid, on)
    end
    return aid
end

function HearingAidDebug.wear(player, item)
    player:setWornItem(item:getBodyLocation(), item)
    HearingAid.reconcile(player)
end

function HearingAidDebug.addBattery(player, charge)
    local battery = player:getInventory():AddItem("Base.Battery")
    battery:setCurrentUsesFloat(charge)
    return battery
end

function HearingAidDebug.addItems(player, fullType, count)
    for _ = 1, count do
        player:getInventory():AddItem(fullType)
    end
end

-- Everything needed to try every feature by hand.
function HearingAidDebug.setupPlayer(player)
    HearingAidDebug.setHearing(player, Level.HARD_OF_HEARING)
    player:setPerkLevelDebug(Perks.Electricity, 8)
    HearingAidDebug.addAid(player, HearingAid.BROKEN, nil, false)
    HearingAidDebug.addAid(player, HearingAid.BASIC, nil, false)
    HearingAidDebug.addAid(player, HearingAid.EFFICIENT, 0.5, false)
    HearingAidDebug.addAid(player, HearingAid.BOOSTED, 1.0, false)
    HearingAidDebug.addBattery(player, 1.0)
    HearingAidDebug.addBattery(player, 0.25)
    HearingAidDebug.addItems(player, "Base.Screwdriver", 1)
    HearingAidDebug.addItems(player, "Base.Scalpel", 1)
    HearingAidDebug.addItems(player, "Base.ElectronicsScrap", 10)
    HearingAidDebug.addItems(player, "Base.Aluminum", 2)
    HearingAidDebug.addItems(player, "Base.Earbuds", 1)
    HearingAidDebug.addItems(player, "Base.Amplifier", 1)
    HearingAidDebug.addItems(player, "Base.ElectricWire", 1)
end
