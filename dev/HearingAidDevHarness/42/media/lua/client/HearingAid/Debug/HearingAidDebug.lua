require "PZHarness/TestLib"
require "HearingAid/HearingAid"

-- Setup helpers for the debug scenario, the tests and the art. Development only, in the dev mod.
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

-- Inputs of every hearing aid recipe once, including tools, as PZHarness.Test.give items.
HearingAidDebug.RECIPE_MATERIALS = {}
for _, fullType in ipairs({
    "Base.Screwdriver", "Base.Tweezers", "Base.Glasses_Reading", "Base.Scalpel",
    "Base.Earbuds", "Base.AlcoholWipes", "Base.Glue", "Base.WristWatch_Left_DigitalBlack",
    "Base.Amplifier", "Base.Microphone", "Base.Epoxy",
}) do
    table.insert(HearingAidDebug.RECIPE_MATERIALS, { type = fullType })
end
table.insert(HearingAidDebug.RECIPE_MATERIALS, { type = "Base.ElectricWire", count = 3 })

function HearingAidDebug.addRecipeMaterials(player)
    for _, material in ipairs(HearingAidDebug.RECIPE_MATERIALS) do
        player:getInventory():AddItems(material.type, material.count or 1)
    end
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
    PZHarness.Test.placeWorkTable(player)
end
