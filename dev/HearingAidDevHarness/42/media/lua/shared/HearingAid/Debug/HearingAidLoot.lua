require "HearingAid/HearingAid"
require "PZHarness/Loot"

-- Measures how often hearing aids and wristwatches turn up on corpses and in containers, with the
-- game's own outfit dressing and loot rolls on scratch objects that never enter the world. For
-- tuning HearingAidDistributions.lua and for the numbers in the README:
--
--   HearingAidLoot.report(samples).zombies / .containers: lists of { key, label, samples, watch,
--   broken, working, efficient, any }, each share the fraction of samples holding at least one
--   item of that kind. measureZombies(key, samples) and measureContainer(key, samples) measure
--   one entry.

HearingAidLoot = {}

-- Where a zombie stands decides its outfit, and its outfit its corpse loot. `outfit` dresses every
-- sample in that outfit. Otherwise the outfit is picked as for a zombie in the zombie zone `zone`
-- (none if nil) and the room `room` (outdoors if nil).
local ZOMBIES = {
    { key = "ordinary", label = "Most zombies" },
    { key = "retirees", label = "Retirees", outfit = "Retiree" },
    { key = "hospitalPatients", label = "Hospital patients", outfit = "HospitalPatient" },
    { key = "bathrobes", label = "Zombies in bathrobes", outfit = "Bathrobe" },
    { key = "hospitalRooms", label = "Hospital rooms", room = "hospitalroom" },
    { key = "nursingHomes", label = "Nursing homes", zone = "NursingHome" },
    { key = "trailerParks", label = "Trailer parks", zone = "TrailerPark" },
    { key = "richNeighborhoods", label = "Rich neighborhoods", zone = "Rich" },
    { key = "golfCourses", label = "Golf courses", zone = "Golf" },
    { key = "countryClubs", label = "Country clubs", zone = "CountryClub" },
}

-- Keys are ProceduralDistributions lists, or SuburbsDistributions.all lists where `all` is set.
-- Classy lists fill houses in rich neighborhoods, and redneck lists houses in trailer parks.
local CONTAINERS = {
    { key = "BedroomSidetable", label = "Bedside table" },
    { key = "BedroomSidetableClassy", label = "Bedside table (classy)" },
    { key = "BedroomSidetableRedneck", label = "Bedside table (trailer park)" },
    { key = "BedroomDresser", label = "Dresser" },
    { key = "BedroomDresserClassy", label = "Dresser (classy)" },
    { key = "BedroomDresserRedneck", label = "Dresser (trailer park)" },
    { key = "LivingRoomSideTable", label = "Living room side table" },
    { key = "LivingRoomSideTableClassy", label = "Living room side table (classy)" },
    { key = "LivingRoomSideTableRedneck", label = "Living room side table (trailer park)" },
    { key = "BathroomCabinet", label = "Bathroom cabinet" },
    { key = "BathroomCounter", label = "Bathroom counter" },
    { key = "HospitalRoomWardrobe", label = "Hospital room wardrobe" },
    { key = "WaitingRoomDesk", label = "Waiting room desk" },
    { key = "MedicalOfficeDesk", label = "Doctor's desk" },
    { key = "LostAndFoundItems", label = "Lost and found" },
    { key = "CrateElectronics", label = "Electronics crate" },
    { key = "sidetable", label = "Side table in other rooms", all = true },
    { key = "medicine", label = "Medicine cabinet in other rooms", all = true },
}

-- Sandbox options set while measuring (PZHarness.Loot.withMeasureOptions), as in a game with
-- zombies (wristwatches spawn twice as often without them) and away from crowds (the zombie density
-- bonus raises every chance except the aids'). Annotated maps are off because each one uses up a
-- stash of the world.
local MEASURE_OPTIONS = {
    Zombies = PZHarness.Loot.DEFAULT,
    ["ZombieConfig.PopulationMultiplier"] = PZHarness.Loot.DEFAULT,
    ZombiePopLootEffect = 0,
    AnnotatedMapChance = 1,
}

local KINDS = { "watch", "broken", "working", "efficient", "any" }

local function isWristWatch(fullType)
    return string.find(fullType, "^Base%.WristWatch_") ~= nil
end

local EFFICIENT_TYPES = {
    [HearingAid.EFFICIENT] = true,
    [HearingAid.leftEarType(HearingAid.EFFICIENT)] = true,
}

-- Sets found[kind] to 1 for each kind of item the container holds, in bags and boxes inside it
-- too, and returns `found`: a sample's counts for PZHarness.Loot.sample.
local function kindsIn(container, found)
    found = found or {}
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        local fullType = item:getFullType()
        if isWristWatch(fullType) then
            found.watch = 1
        elseif HearingAid.isHearingAid(item) then
            found.any = 1
            if HearingAid.isWorking(item) then
                found.working = 1
                if EFFICIENT_TYPES[fullType] then
                    found.efficient = 1
                end
            else
                found.broken = 1
            end
        elseif item:IsInventoryContainer() then
            kindsIn(item:getInventory(), found)
        end
    end
    return found
end

-- The report's entry for `spec`: the share of the `samples` that held each kind, from
-- PZHarness.Loot.sample's `shares`.
local function entryOf(spec, samples, shares)
    local entry = { key = spec.key, label = spec.label, samples = samples }
    for _, kind in ipairs(KINDS) do
        entry[kind] = shares[kind] and shares[kind].share or 0
    end
    return entry
end

-- Outfits ---------------------------------------------------------------------------------------

-- ZombiesZoneDefinition.java filters outfits by room with String.contains.
local function fits(outfit, female, room)
    local gender = outfit.gender and string.lower(outfit.gender)
    return (outfit.room == nil or (room ~= nil and string.find(outfit.room, room, 1, true) ~= nil))
        and (gender == nil or (gender == "female") == female)
end

-- ZombiesZoneDefinition.getRandomOutfitInSetList. Zone tables roll up to 100 even when their
-- chances add up to less, and a roll past the last chance picks nothing.
local function pickByChance(outfits, upTo100)
    local total = 0
    for _, outfit in ipairs(outfits) do
        total = total + (outfit.chance or 0)
    end
    local roll = ZombRandFloat(0, (upTo100 and total <= 100) and 100 or total)
    local subtotal = 0
    for _, outfit in ipairs(outfits) do
        subtotal = subtotal + (outfit.chance or 0)
        if roll < subtotal then
            return outfit
        end
    end
    return nil
end

-- The outfits of a ZombiesZoneDefinition table that fit each sex and room, filtered once rather
-- than for every sample. Mandatory outfits spawn only until a zone has its quota
-- (ZombiesZoneDefinition.pickDefinition), so in the long run they are left out.
local fittingCache = {}

local function fittingOutfits(tableName, female, room)
    local key = tableName .. "/" .. tostring(female) .. "/" .. tostring(room)
    local outfits = fittingCache[key]
    if not outfits then
        outfits = {}
        for _, outfit in pairs(ZombiesZoneDefinition[tableName]) do
            if type(outfit) == "table" and tostring(outfit.mandatory) ~= "true" and fits(outfit, female, room) then
                table.insert(outfits, outfit)
            end
        end
        fittingCache[key] = outfits
    end
    return outfits
end

-- ZombiesZoneDefinition.pickDefinition.
local function pickZoneOutfit(zoneName, female, room)
    local zone = ZombiesZoneDefinition[zoneName]
    if (zone.maleChance or 0) > 0 and ZombRand(100) < zone.maleChance then
        female = false
    end
    if (zone.femaleChance or 0) > 0 and ZombRand(100) < zone.femaleChance then
        female = true
    end
    local picked = pickByChance(fittingOutfits(zoneName, female, room), true)
    return picked and picked.name, female
end

-- ZombiesZoneDefinition.dressInRandomOutfit: the zone table first, and the Default table when it
-- picks nothing.
local function pickOutfit(spec, female)
    if spec.outfit then
        return spec.outfit, female
    end
    if spec.zone then
        local name, zoneFemale = pickZoneOutfit(spec.zone, female, spec.room)
        if name then
            return name, zoneFemale
        end
    end
    return pickByChance(fittingOutfits("Default", female, spec.room), false).name, female
end

-- Zombies ---------------------------------------------------------------------------------------

-- A scratch descriptor per sex to dress, never registered with the world.
local function newBody(female)
    local desc = SurvivorDesc.new(true)
    desc:setFemale(female)
    return { visual = desc:getHumanVisual(), visuals = ItemVisuals.new() }
end

local function wearsWatch(body, outfitName)
    body.visual:dressInNamedOutfit(outfitName, body.visuals)
    for i = 0, body.visuals:size() - 1 do
        if isWristWatch(body.visuals:get(i):getItemType()) then
            return true
        end
    end
    return false
end

-- ItemPickerJava.fillContainer for a corpse: the outfit's list, then the list of the corpse's sex
-- unless the outfit's list sets defaultInventoryLoot = false.
local function fillCorpse(corpse, outfitName, defaultList)
    local name = "Outfit_" .. outfitName
    local outfitTable = SuburbsDistributions.all[name]
    if outfitTable then
        ItemPickerJava.rollItem(ItemPickerJava.getItemContainer("all", name, nil, false), corpse, true, nil, nil)
    end
    if not outfitTable or outfitTable.defaultInventoryLoot ~= false then
        ItemPickerJava.rollItem(defaultList, corpse, true, nil, nil)
    end
end

local function sampleZombies(spec, samples)
    local bodies = { [false] = newBody(false), [true] = newBody(true) }
    local defaultLists = {
        [false] = ItemPickerJava.getItemContainer("all", "inventorymale", nil, false),
        [true] = ItemPickerJava.getItemContainer("all", "inventoryfemale", nil, false),
    }
    -- Whether the sample's outfit wears a wristwatch, which goes on the body, not in the corpse.
    local watch
    local function fill(corpse)
        local outfitName, female = pickOutfit(spec, ZombRand(2) == 0)
        corpse:setType(female and "inventoryfemale" or "inventorymale")
        watch = wearsWatch(bodies[female], outfitName)
        fillCorpse(corpse, outfitName, defaultLists[female])
    end
    local function read(corpse)
        return kindsIn(corpse, { watch = watch and 1 or nil })
    end
    return entryOf(spec, samples, PZHarness.Loot.sample(fill, samples, ItemContainer.new(), read))
end

-- Containers ------------------------------------------------------------------------------------

-- A container rolls its list as rollItem does: the junk list, then the items.
local function sampleContainer(spec, samples)
    local list, containerType
    if spec.all then
        list, containerType = ItemPickerJava.getItemContainer("all", spec.key, nil, false), spec.key
    else
        local user
        list, user = PZHarness.Loot.proceduralList(spec.key)
        if not list then
            error("no container rolls ProceduralDistributions list " .. spec.key)
        end
        containerType = user.container
    end
    local container = ItemContainer.new()
    container:setType(containerType)
    return entryOf(spec, samples, PZHarness.Loot.sample(PZHarness.Loot.rollFill(list), samples, container, kindsIn))
end

-- Report ----------------------------------------------------------------------------------------

local function find(specs, key)
    for _, spec in ipairs(specs) do
        if spec.key == key then
            return spec
        end
    end
    error("unknown loot place " .. key)
end

-- One entry of the report, for example HearingAidLoot.measureZombies("ordinary", 1000).
function HearingAidLoot.measureZombies(key, samples)
    return PZHarness.Loot.withMeasureOptions(MEASURE_OPTIONS, function()
        return sampleZombies(find(ZOMBIES, key), samples)
    end)
end

function HearingAidLoot.measureContainer(key, samples)
    return PZHarness.Loot.withMeasureOptions(MEASURE_OPTIONS, function()
        return sampleContainer(find(CONTAINERS, key), samples)
    end)
end

function HearingAidLoot.report(samples)
    return PZHarness.Loot.withMeasureOptions(MEASURE_OPTIONS, function()
        local result = { zombies = {}, containers = {} }
        for _, spec in ipairs(ZOMBIES) do
            table.insert(result.zombies, sampleZombies(spec, samples))
        end
        for _, spec in ipairs(CONTAINERS) do
            table.insert(result.containers, sampleContainer(spec, samples))
        end
        return result
    end)
end
