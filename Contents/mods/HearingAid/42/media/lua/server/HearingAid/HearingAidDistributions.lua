require "Items/Distributions"
require "Items/ProceduralDistributions"
require "HearingAid/HearingAid"

-- Hearing aids spawn where their owners kept them in 1993, and most turn up on the dead. The
-- yardstick is the wristwatch on the same corpse or in the same container, as
-- HearingAidLoot.report() measures both: a broken aid is 3.3 to 5.5 times rarer than a wristwatch,
-- and the weights aim at 4; a working aid is 5.5 to 9.5 times rarer, and they aim at 7. About 29%
-- of ordinary zombies wear a wristwatch, so about 7% carry a broken aid and 4% a working one.
-- Retirees carry an aid three times as often, hospital patients twice as often, with the same split.

-- Weights are { broken, basic, efficient }. Each plain house list is tuned against its own
-- wristwatches, and its classy and redneck variants get the same weights. Lists without
-- wristwatches are weighted relative to the bedside table. Efficient aids are a lucky find: about
-- 1 in 50 working aids on corpses, and the game's smallest chance, 1 in 10,000 per roll, in
-- hospital wardrobes and doctors' desks. Physicians' offices sold about 15% of new hearing aids
-- (MarkeTrak II, 1990), so doctors' desks hold only working ones.
local PROCEDURAL = {
    -- Aids come out every night.
    BedroomSidetable = { 0.174, 0.12, 0 },
    BedroomSidetableClassy = { 0.174, 0.12, 0 },
    BedroomSidetableRedneck = { 0.174, 0.12, 0 },
    BathroomCabinet = { 0.087, 0.06, 0 },
    BathroomCounter = { 0.087, 0.06, 0 },
    -- Spares and replaced aids.
    BedroomDresser = { 0.174, 0.108, 0 },
    BedroomDresserClassy = { 0.174, 0.108, 0 },
    BedroomDresserRedneck = { 0.174, 0.108, 0 },
    LivingRoomSideTable = { 0.168, 0.096, 0 },
    LivingRoomSideTableClassy = { 0.168, 0.096, 0 },
    LivingRoomSideTableRedneck = { 0.168, 0.096, 0 },
    CrateElectronics = { 0.108, 0, 0 },
    -- Patients' bedside belongings.
    HospitalRoomWardrobe = { 1.74, 1.2, 0.01 },
    WaitingRoomDesk = { 0.174, 0.12, 0 },
    LostAndFoundItems = { 0.174, 0.12, 0 },
    MedicalOfficeDesk = { 0, 0.6, 0.01 },
}

-- A corpse rolls the SuburbsDistributions.all list of its outfit, if there is one, and then
-- inventorymale or inventoryfemale, unless the outfit list sets defaultInventoryLoot = false, as the
-- bathrobe and hospital patient lists do.
local ALL = {
    inventorymale = { 11.7, 7.2, 0.15 },
    inventoryfemale = { 11.7, 7.2, 0.15 },
    Outfit_Retiree = { 31.8, 18.6, 0.33 },
    Outfit_HospitalPatient = { 24.6, 15, 0.3 },
    Outfit_HospitalPatientBathrobe = { 24.6, 15, 0.3 },
    Outfit_Bathrobe = { 11.7, 7.2, 0.15 },
    -- Fallbacks for rooms without lists of their own.
    sidetable = { 0.087, 0.06, 0 },
    medicine = { 0.087, 0.06, 0 },
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
