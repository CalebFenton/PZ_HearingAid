require "Items/Distributions"
require "Items/ProceduralDistributions"
require "HearingAid/HearingAid"

-- Where hearing aids turn up: bathroom cabinets, nightstands, junk drawers, medical offices,
-- optometrists, and on older zombies. Broken ones are the common find; working ones are rare.
--
-- Weights are per roll, before vanilla multipliers (Medical loot rarity, rolls, removal list).
-- For scale: Glasses_Reading has weight 1 in BedroomSidetable.
--
-- Applied in OnInitGlobalModData rather than at file load or distribution merge: that is the
-- first point where SandboxVars hold the save's values when continuing a single player game.

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
    -- Shops: stock is new, so working only
    PharmacyGlasses = { 0, 0.5, 0.1 },
    OptometristGlasses = { 0, 1, 0.3 },
    ElectronicStoreMisc = { 0, 0.3, 0.05 },
}

-- SuburbsDistributions.all.<key>: corpse inventories and the medicine/side table fallbacks.
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

local function addItem(items, fullType, weight)
    -- Items lists are flat name/weight pairs; only ever append both.
    if weight > 0 then
        table.insert(items, fullType)
        table.insert(items, weight)
    end
end

local function addAll(distribution, weights, brokenMultiplier, workingMultiplier)
    addItem(distribution.items, HearingAid.BROKEN, weights[1] * brokenMultiplier)
    addItem(distribution.items, HearingAid.BASIC, weights[2] * workingMultiplier)
    addItem(distribution.items, HearingAid.EFFICIENT, weights[3] * workingMultiplier)
end

local applied = false

local function applyDistributions()
    if applied then
        return false
    end
    applied = true

    local sandbox = HearingAid.sandbox()
    local brokenMultiplier = tonumber(sandbox.BrokenLootMultiplier) or 1
    local workingMultiplier = tonumber(sandbox.WorkingLootMultiplier) or 1

    for name, weights in pairs(CONTAINERS) do
        local distribution = ProceduralDistributions.list[name]
        if distribution and distribution.items then
            addAll(distribution, weights, brokenMultiplier, workingMultiplier)
        else
            print("HearingAid: missing ProceduralDistributions.list." .. name)
        end
    end

    local all = SuburbsDistributions.all
    -- Retiree zombies (nursing homes, trailer parks, country clubs) have no outfit loot table.
    all.Outfit_Retiree = all.Outfit_Retiree or { rolls = 1, items = {}, junk = { rolls = 1, items = {} } }
    for key, weights in pairs(ALL) do
        local distribution = all[key]
        if distribution and distribution.items then
            addAll(distribution, weights, brokenMultiplier, workingMultiplier)
        else
            print("HearingAid: missing SuburbsDistributions.all." .. key)
        end
    end
    return true
end

local function onInitGlobalModData(isNewGame)
    if isClient() then
        return -- containers are filled by the server
    end
    if applyDistributions() then
        ItemPickerJava.Parse()
    end
end

Events.OnInitGlobalModData.Add(onInitGlobalModData)
