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
    local battery = player:getInventory():AddItem(HearingAid.BATTERY)
    battery:setCurrentUsesFloat(charge)
    return battery
end

-- Puts the item on at once, without the wear action.
function HearingAidDebug.wear(player, item)
    player:setWornItem(item:getBodyLocation(), item)
    HearingAid.reconcile(player)
end

-- Inputs of every hearing aid recipe once, including tools.
function HearingAidDebug.addRecipeMaterials(player)
    local inventory = player:getInventory()
    for _, fullType in ipairs({
        "Base.Screwdriver", "Base.Tweezers", "Base.Glasses_Reading", "Base.Scalpel",
        "Base.Earbuds", "Base.AlcoholWipes", "Base.Glue", "Base.WristWatch_Left_DigitalBlack",
        "Base.Amplifier", "Base.Microphone", "Base.Epoxy",
    }) do
        inventory:AddItem(fullType)
    end
    inventory:AddItems("Base.ElectricWire", 3)
end

local WORK_TABLE_SPRITE = "carpentry_01_60" -- the Shoddy Table players build, a crafting surface

local function hasWorkTable(square)
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local sprite = objects:get(i):getSprite()
        if sprite and sprite:getName() == WORK_TABLE_SPRITE then
            return true
        end
    end
    return false
end

-- Repairs and upgrades need a table the character can walk to. Puts one on a free square next to
-- the character, with no wall in between, unless one is there already.
function HearingAidDebug.placeWorkTable(player)
    local here = player:getSquare()
    local free
    for _, direction in ipairs({ IsoDirections.N, IsoDirections.W, IsoDirections.S, IsoDirections.E }) do
        local square = here:getAdjacentSquare(direction)
        if square and hasWorkTable(square) then
            return
        end
        if not free and square and square:isFree(false) and not here:isBlockedTo(square) then
            free = square
        end
    end
    assert(free, "HearingAidDebug: no free square next to the character for a table")
    free:AddTileObject(IsoObject.new(free, WORK_TABLE_SPRITE, "Table"))
end

-- A hard of hearing character with Electrical 8, every tier, batteries, recipe materials and a table.
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
    HearingAidDebug.placeWorkTable(player)
end
