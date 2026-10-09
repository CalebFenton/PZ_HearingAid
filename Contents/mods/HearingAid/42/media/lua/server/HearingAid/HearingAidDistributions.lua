require "Items/Distributions"
require "Items/ProceduralDistributions"
require "HearingAid/HearingAid"

-- Hearing aids spawn where their owners kept them in 1993, and most turn up on the dead.
-- hearingaid_corpse_loot holds the corpse weights against the wristwatches on the same corpses, and
-- dev/run-debug-client.sh --loot measures every list here.

-- Weights are { broken, basic, efficient }. Any positive weight spawns at least 1 in 10,000 per
-- roll, so the efficient weight in containers is as small as it gets. Physicians' offices sold new
-- hearing aids (MarkeTrak II, 1990), so doctors' desks hold only working ones.
local PROCEDURAL = {
    -- Aids come out every night.
    BedroomSidetable = { 0.116, 0.08, 0 },
    BedroomSidetableClassy = { 0.116, 0.08, 0 },
    BedroomSidetableRedneck = { 0.116, 0.08, 0 },
    BathroomCabinet = { 0.058, 0.04, 0 },
    BathroomCounter = { 0.058, 0.04, 0 },
    -- Spares and replaced aids.
    BedroomDresser = { 0.116, 0.072, 0 },
    BedroomDresserClassy = { 0.116, 0.072, 0 },
    BedroomDresserRedneck = { 0.116, 0.072, 0 },
    LivingRoomSideTable = { 0.112, 0.064, 0 },
    LivingRoomSideTableClassy = { 0.112, 0.064, 0 },
    LivingRoomSideTableRedneck = { 0.112, 0.064, 0 },
    CrateElectronics = { 0.072, 0, 0 },
    -- Patients' bedside belongings.
    HospitalRoomWardrobe = { 1.16, 0.8, 0.01 },
    WaitingRoomDesk = { 0.116, 0.08, 0 },
    LostAndFoundItems = { 0.116, 0.08, 0 },
    MedicalOfficeDesk = { 0, 0.4, 0.01 },
}

-- A corpse rolls the SuburbsDistributions.all list of its outfit, if there is one, and then
-- inventorymale or inventoryfemale, unless the outfit list sets defaultInventoryLoot = false, as the
-- bathrobe and hospital patient lists do.
local ALL = {
    inventorymale = { 7.8, 4.8, 0.1 },
    inventoryfemale = { 7.8, 4.8, 0.1 },
    Outfit_Retiree = { 21.2, 12.4, 0.22 },
    Outfit_HospitalPatient = { 16.4, 10, 0.2 },
    Outfit_HospitalPatientBathrobe = { 16.4, 10, 0.2 },
    Outfit_Bathrobe = { 7.8, 4.8, 0.1 },
    -- Fallbacks for rooms without lists of their own.
    sidetable = { 0.058, 0.04, 0 },
    medicine = { 0.058, 0.04, 0 },
}

-- `items` lists are flat name, weight pairs.
local function addItem(items, fullType, weight)
    if weight > 0 then
        table.insert(items, fullType)
        table.insert(items, weight)
    end
end

local function addAids(items, weights)
    local working = SandboxVars.HearingAid.WorkingLootMultiplier
    addItem(items, HearingAid.BROKEN, weights[1] * SandboxVars.HearingAid.BrokenLootMultiplier)
    addItem(items, HearingAid.BASIC, weights[2] * working)
    addItem(items, HearingAid.EFFICIENT, weights[3] * working)
end

local function addToLists(lists, listsName, entries)
    for name, entry in pairs(entries) do
        if lists[name] then
            addAids(lists[name].items, entry)
        else
            print("HearingAid: missing " .. listsName .. "." .. name)
        end
    end
end

local function addToDistributions()
    local all = SuburbsDistributions.all
    all.Outfit_Retiree = all.Outfit_Retiree or { rolls = 1, items = {} }
    addToLists(ProceduralDistributions.list, "ProceduralDistributions.list", PROCEDURAL)
    addToLists(all, "SuburbsDistributions.all", ALL)
end

-- The distribution merge events fire before a continued single player game loads its sandbox
-- options; OnInitGlobalModData fires after. The game has already parsed the Lua tables by then, so
-- they are parsed again. Multiplayer clients don't fill containers.
local function onInitGlobalModData(isNewGame)
    if isClient() then
        return
    end
    addToDistributions()
    ItemPickerJava.Parse()
end

Events.OnInitGlobalModData.Add(onInitGlobalModData)
