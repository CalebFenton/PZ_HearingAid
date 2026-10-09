require "Items/Distributions"
require "Items/ProceduralDistributions"
require "HearingAid/HearingAid"

-- Hearing aids spawn where their owners kept them in 1993, and most turn up on the dead. The
-- yardstick is the wristwatch on the same corpse or in the same container, as
-- HearingAidLoot.report() measures both: a broken aid is 4 to 6.5 times rarer than a wristwatch,
-- and the weights aim at 5; a working aid is 6 to 11 times rarer, and they aim at 8. About 29%
-- of ordinary zombies wear a wristwatch, so about 6% carry a broken aid and 3.5% a working one.
-- Retirees carry an aid three times as often, hospital patients twice as often, with the same split.

-- Weights are { broken, basic, efficient }. Each plain house list is tuned against its own
-- wristwatches, and its classy and redneck variants get the same weights. Lists without
-- wristwatches are weighted relative to the bedside table. Efficient aids are a lucky find: about
-- 1 in 50 working aids on corpses, and the game's smallest chance, 1 in 10,000 per roll, in
-- hospital wardrobes and doctors' desks. Physicians' offices sold about 15% of new hearing aids
-- (MarkeTrak II, 1990), so doctors' desks hold only working ones.
local PROCEDURAL = {
    -- Aids come out every night.
    BedroomSidetable = { 0.145, 0.1, 0 },
    BedroomSidetableClassy = { 0.145, 0.1, 0 },
    BedroomSidetableRedneck = { 0.145, 0.1, 0 },
    BathroomCabinet = { 0.0725, 0.05, 0 },
    BathroomCounter = { 0.0725, 0.05, 0 },
    -- Spares and replaced aids.
    BedroomDresser = { 0.145, 0.09, 0 },
    BedroomDresserClassy = { 0.145, 0.09, 0 },
    BedroomDresserRedneck = { 0.145, 0.09, 0 },
    LivingRoomSideTable = { 0.14, 0.08, 0 },
    LivingRoomSideTableClassy = { 0.14, 0.08, 0 },
    LivingRoomSideTableRedneck = { 0.14, 0.08, 0 },
    CrateElectronics = { 0.09, 0, 0 },
    -- Patients' bedside belongings.
    HospitalRoomWardrobe = { 1.45, 1, 0.01 },
    WaitingRoomDesk = { 0.145, 0.1, 0 },
    LostAndFoundItems = { 0.145, 0.1, 0 },
    MedicalOfficeDesk = { 0, 0.5, 0.01 },
}

-- A corpse rolls the SuburbsDistributions.all list of its outfit, if there is one, and then
-- inventorymale or inventoryfemale, unless the outfit list sets defaultInventoryLoot = false, as the
-- bathrobe and hospital patient lists do.
local ALL = {
    inventorymale = { 9.75, 6, 0.125 },
    inventoryfemale = { 9.75, 6, 0.125 },
    Outfit_Retiree = { 26.5, 15.5, 0.275 },
    Outfit_HospitalPatient = { 20.5, 12.5, 0.25 },
    Outfit_HospitalPatientBathrobe = { 20.5, 12.5, 0.25 },
    Outfit_Bathrobe = { 9.75, 6, 0.125 },
    -- Fallbacks for rooms without lists of their own.
    sidetable = { 0.0725, 0.05, 0 },
    medicine = { 0.0725, 0.05, 0 },
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
