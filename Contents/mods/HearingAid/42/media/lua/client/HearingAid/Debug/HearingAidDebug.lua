require "HearingAid/HearingAid"

-- Setup helpers for the debug scenario and tests. Debug mode only.
HearingAidDebug = {}

-- Adds an aid with an exact battery state; nil charge means no battery.
function HearingAidDebug.addAid(player, fullType, charge, on)
    local aid = player:getInventory():AddItem(fullType)
    HearingAid.setCharge(aid, charge)
    HearingAid.setOn(aid, on)
    return aid
end

function HearingAidDebug.addBattery(player, charge)
    local battery = player:getInventory():AddItem("Base.Battery")
    battery:setCurrentUsesFloat(charge)
    return battery
end

-- Puts the item on at once, without the wear action.
function HearingAidDebug.wear(player, item)
    player:setWornItem(item:getBodyLocation(), item)
    HearingAid.reconcile(player)
end

-- Inputs of every hearing aid recipe, including tools.
function HearingAidDebug.addRecipeMaterials(player)
    local inventory = player:getInventory()
    inventory:AddItems("Base.Screwdriver", 1)
    inventory:AddItems("Base.Scalpel", 1)
    inventory:AddItems("Base.ElectronicsScrap", 4)
    inventory:AddItems("Base.Aluminum", 1)
    inventory:AddItems("Base.Earbuds", 1)
    inventory:AddItems("Base.Amplifier", 1)
    inventory:AddItems("Base.ElectricWire", 1)
end

-- A hard of hearing character with Electrical 8, every tier, batteries and recipe materials.
function HearingAidDebug.setupPlayer(player)
    HearingAid.setBaseLevel(player, HearingAid.Level.HARD_OF_HEARING)
    player:setPerkLevelDebug(Perks.Electricity, 8)
    HearingAidDebug.addAid(player, HearingAid.BROKEN, nil, false)
    HearingAidDebug.addAid(player, HearingAid.BASIC, nil, false)
    HearingAidDebug.addAid(player, HearingAid.EFFICIENT, 0.5, false)
    HearingAidDebug.addAid(player, HearingAid.BOOSTED, 1.0, false)
    HearingAidDebug.addBattery(player, 1.0)
    HearingAidDebug.addBattery(player, 0.25)
    HearingAidDebug.addRecipeMaterials(player)
    player:getInventory():AddItems("Base.ElectronicsScrap", 6)
end
