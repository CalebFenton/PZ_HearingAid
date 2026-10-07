require "Items/Distributions"
require "Items/ProceduralDistributions"
require "HearingAid/HearingAid"

-- Hearing aids spawn where their owners kept them in 1993. People wear them, so most turn up on the
-- dead, and retirees carry them far more often than anyone else: in 1994, 1 in 60 Americans used a
-- hearing aid, and 1 in 10 of those over 65 (NCHS Advance Data 292). The yardstick is the vanilla
-- digital watch, which about 15% of ordinary zombies wear and which home side tables and dressers
-- list with a total weight of 0.3. Ordinary corpses carry an aid a tenth as often as a digital watch.

-- Shares of { broken, basic, efficient } aids.
local USED = { 0.75, 0.2, 0.05 }
-- Physicians' offices sold about 15% of new hearing aids (MarkeTrak II, 1990).
local NEW = { 0, 0.8, 0.2 }
local BROKEN = { 1, 0, 0 }

-- { total weight, shares } per ProceduralDistributions list.
local PROCEDURAL = {
    -- Aids come out every night.
    BedroomSidetable = { 0.1, USED },
    BedroomSidetableClassy = { 0.1, USED },
    BedroomSidetableRedneck = { 0.1, USED },
    BathroomCabinet = { 0.05, USED },
    BathroomCounter = { 0.05, USED },
    -- Spares and replaced aids.
    BedroomDresser = { 0.03, USED },
    BedroomDresserClassy = { 0.03, USED },
    BedroomDresserRedneck = { 0.03, USED },
    LivingRoomSideTable = { 0.03, USED },
    LivingRoomSideTableClassy = { 0.03, USED },
    LivingRoomSideTableRedneck = { 0.03, USED },
    CrateElectronics = { 0.05, BROKEN },
    -- Patients' bedside belongings.
    HospitalRoomWardrobe = { 1, USED },
    WaitingRoomDesk = { 0.1, USED },
    LostAndFoundItems = { 0.1, USED },
    MedicalOfficeDesk = { 0.1, NEW },
}

-- { total weight, shares } per SuburbsDistributions.all list. A corpse rolls the list of its outfit,
-- if there is one, and then inventorymale or inventoryfemale, unless the outfit list sets
-- defaultInventoryLoot = false, as the bathrobe and hospital patient lists do.
local ALL = {
    inventorymale = { 2.5, USED },
    inventoryfemale = { 2.5, USED },
    Outfit_Retiree = { 15, USED },
    Outfit_HospitalPatient = { 7.5, USED },
    Outfit_HospitalPatientBathrobe = { 7.5, USED },
    Outfit_Bathrobe = { 2.5, USED },
    -- Fallbacks for rooms without lists of their own.
    sidetable = { 0.05, USED },
    medicine = { 0.05, USED },
}

-- `items` lists are flat name, weight pairs.
local function addItem(items, fullType, weight)
    if weight > 0 then
        table.insert(items, fullType)
        table.insert(items, weight)
    end
end

local function addAids(items, total, shares)
    local broken = total * shares[1] * SandboxVars.HearingAid.BrokenLootMultiplier
    local working = total * SandboxVars.HearingAid.WorkingLootMultiplier
    addItem(items, HearingAid.BROKEN, broken)
    addItem(items, HearingAid.BASIC, working * shares[2])
    addItem(items, HearingAid.EFFICIENT, working * shares[3])
end

local function addToLists(lists, listsName, entries)
    for name, entry in pairs(entries) do
        if lists[name] then
            addAids(lists[name].items, entry[1], entry[2])
        else
            print("HearingAid: missing " .. listsName .. "." .. name)
        end
    end
end

local function addToDistributions()
    local all = SuburbsDistributions.all
    all.Outfit_Retiree = all.Outfit_Retiree or { rolls = 1, items = {}, junk = { rolls = 1, items = {} } }
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
