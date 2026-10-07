require "Items/Distributions"
require "Items/ProceduralDistributions"
require "HearingAid/HearingAid"

-- Hearing aids spawn where their owners kept them in 1993. People wear them, so most turn up on the
-- dead, and retirees carry them far more often than anyone else: in 1994, 1 in 60 Americans used a
-- hearing aid, and 1 in 10 of those over 65 (NCHS Advance Data 292). The yardstick is the vanilla
-- digital watch, which about 15% of ordinary zombies wear and which home side tables and dressers
-- list with a total weight of 0.3. Ordinary corpses carry an aid a tenth as often as a digital watch.

-- Weights are { broken, basic, efficient }. Four in five aids that people left behind are broken.
-- Efficient aids are a lucky find: only corpses, hospital bedsides and doctors' desks hold them,
-- mostly with a weight of 0.01, which the game rounds up to its smallest chance, 1 in 10,000 per
-- roll. Physicians' offices sold about 15% of new hearing aids (MarkeTrak II, 1990), so doctors'
-- desks hold only working ones.
local PROCEDURAL = {
    -- Aids come out every night.
    BedroomSidetable = { 0.08, 0.02, 0 },
    BedroomSidetableClassy = { 0.08, 0.02, 0 },
    BedroomSidetableRedneck = { 0.08, 0.02, 0 },
    BathroomCabinet = { 0.04, 0.01, 0 },
    BathroomCounter = { 0.04, 0.01, 0 },
    -- Spares and replaced aids.
    BedroomDresser = { 0.025, 0.005, 0 },
    BedroomDresserClassy = { 0.025, 0.005, 0 },
    BedroomDresserRedneck = { 0.025, 0.005, 0 },
    LivingRoomSideTable = { 0.025, 0.005, 0 },
    LivingRoomSideTableClassy = { 0.025, 0.005, 0 },
    LivingRoomSideTableRedneck = { 0.025, 0.005, 0 },
    CrateElectronics = { 0.05, 0, 0 },
    -- Patients' bedside belongings.
    HospitalRoomWardrobe = { 0.8, 0.2, 0.01 },
    WaitingRoomDesk = { 0.08, 0.02, 0 },
    LostAndFoundItems = { 0.08, 0.02, 0 },
    MedicalOfficeDesk = { 0, 0.1, 0.01 },
}

-- A corpse rolls the SuburbsDistributions.all list of its outfit, if there is one, and then
-- inventorymale or inventoryfemale, unless the outfit list sets defaultInventoryLoot = false, as the
-- bathrobe and hospital patient lists do.
local ALL = {
    inventorymale = { 2, 0.5, 0.01 },
    inventoryfemale = { 2, 0.5, 0.01 },
    Outfit_Retiree = { 12, 3, 0.1 },
    Outfit_HospitalPatient = { 6, 1.5, 0.01 },
    Outfit_HospitalPatientBathrobe = { 6, 1.5, 0.01 },
    Outfit_Bathrobe = { 2, 0.5, 0.01 },
    -- Fallbacks for rooms without lists of their own.
    sidetable = { 0.04, 0.01, 0 },
    medicine = { 0.04, 0.01, 0 },
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
