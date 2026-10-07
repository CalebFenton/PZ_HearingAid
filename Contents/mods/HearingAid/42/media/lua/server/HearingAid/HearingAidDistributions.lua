require "Items/Distributions"
require "Items/ProceduralDistributions"
require "HearingAid/HearingAid"

-- Where hearing aids turn up: bathroom cabinets, nightstands, junk drawers, medical offices,
-- optometrists, and on older zombies. Broken ones are the common find; working ones are rare.
--
-- Weights are per roll, before the Medical loot rarity setting scales them. For scale,
-- Glasses_Reading has weight 1 in BedroomSidetable.

-- { broken, basic, efficient }
local CONTAINERS = {
    -- Homes
    BathroomCabinet = { 0.3, 0.1, 0.02 },
    BedroomSidetable = { 0.4, 0.1, 0.02 },
    BedroomSidetableClassy = { 0.4, 0.1, 0.03 },
    BedroomSidetableRedneck = { 0.4, 0.1, 0.01 },
    BedroomDresser = { 0.1, 0.03, 0 },
    LivingRoomSideTable = { 0.2, 0.05, 0.01 },
    LivingRoomSideTableClassy = { 0.2, 0.05, 0.01 },
    LivingRoomSideTableRedneck = { 0.2, 0.05, 0 },
    KitchenRandom = { 0.2, 0.05, 0 },
    OfficeDeskHome = { 0.1, 0.03, 0 },
    OfficeDeskHomeClassy = { 0.1, 0.03, 0.01 },
    ClosetShelfGeneric = { 0.1, 0.02, 0 },
    CrateElectronics = { 0.3, 0.05, 0 },
    BinBathroom = { 0.05, 0, 0 },
    -- Medical
    HospitalRoomWardrobe = { 0.5, 0.2, 0.05 },
    MedicalOfficeDesk = { 0.3, 0.3, 0.1 },
    MedicalClinicTools = { 0.2, 0.5, 0.2 },
    -- Shops sell new stock, so only working aids
    PharmacyGlasses = { 0, 0.5, 0.1 },
    OptometristGlasses = { 0, 1, 0.3 },
    ElectronicStoreMisc = { 0, 0.3, 0.05 },
}

-- SuburbsDistributions.all.<key>: corpse inventories and the medicine and side table fallbacks.
local ALL = {
    medicine = { 0.2, 0.05, 0.01 },
    sidetable = { 0.2, 0.05, 0.01 },
    inventorymale = { 0.05, 0.01, 0.002 },
    inventoryfemale = { 0.05, 0.01, 0.002 },
    Outfit_Retiree = { 1.0, 0.3, 0.05 },
    Outfit_Bathrobe = { 0.3, 0.1, 0.02 },
    Outfit_HospitalPatient = { 0.3, 0.1, 0.02 },
    Outfit_HospitalPatientBathrobe = { 0.3, 0.1, 0.02 },
}

-- `items` lists are flat name, weight pairs.
local function addItem(items, fullType, weight)
    if weight > 0 then
        table.insert(items, fullType)
        table.insert(items, weight)
    end
end

local function addAids(distribution, weights, brokenMultiplier, workingMultiplier)
    addItem(distribution.items, HearingAid.BROKEN, weights[1] * brokenMultiplier)
    addItem(distribution.items, HearingAid.BASIC, weights[2] * workingMultiplier)
    addItem(distribution.items, HearingAid.EFFICIENT, weights[3] * workingMultiplier)
end

local function addToDistributions()
    local brokenMultiplier = SandboxVars.HearingAid.BrokenLootMultiplier
    local workingMultiplier = SandboxVars.HearingAid.WorkingLootMultiplier

    for name, weights in pairs(CONTAINERS) do
        local distribution = ProceduralDistributions.list[name]
        if distribution then
            addAids(distribution, weights, brokenMultiplier, workingMultiplier)
        else
            print("HearingAid: missing ProceduralDistributions.list." .. name)
        end
    end

    local all = SuburbsDistributions.all
    -- Vanilla has no loot table for retiree zombies (nursing homes, trailer parks, country clubs).
    all.Outfit_Retiree = all.Outfit_Retiree or { rolls = 1, items = {}, junk = { rolls = 1, items = {} } }
    for key, weights in pairs(ALL) do
        local distribution = all[key]
        if distribution then
            addAids(distribution, weights, brokenMultiplier, workingMultiplier)
        else
            print("HearingAid: missing SuburbsDistributions.all." .. key)
        end
    end
end

-- The distribution merge events fire before a continued single player game loads its sandbox
-- options; OnInitGlobalModData is the first event after. The game has already parsed the Lua
-- tables by then, so they are parsed again. Multiplayer clients don't fill containers.
local function onInitGlobalModData(isNewGame)
    if isClient() then
        return
    end
    addToDistributions()
    ItemPickerJava.Parse()
end

Events.OnInitGlobalModData.Add(onInitGlobalModData)
