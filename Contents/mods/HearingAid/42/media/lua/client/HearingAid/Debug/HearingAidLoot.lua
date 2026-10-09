require "HearingAid/HearingAid"

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

-- Sandbox options set while measuring, as in a game with zombies (wristwatches spawn twice as often
-- without them) and away from crowds (the zombie density bonus raises every chance except the
-- aids'). Annotated maps are off because each one uses up a stash of the world. DEFAULT stands for
-- the option's default value.
local DEFAULT = {}
local MEASURE_OPTIONS = {
    Zombies = DEFAULT,
    ["ZombieConfig.PopulationMultiplier"] = DEFAULT,
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

local function newEntry(spec)
    local entry = { key = spec.key, label = spec.label, samples = 0 }
    for _, kind in ipairs(KINDS) do
        entry[kind] = 0
    end
    return entry
end

-- Marks in `found` the kinds of item that the container holds, in bags and boxes inside it too.
local function scan(container, found)
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        local fullType = item:getFullType()
        if isWristWatch(fullType) then
            found.watch = true
        elseif HearingAid.isHearingAid(item) then
            found.any = true
            if HearingAid.isWorking(item) then
                found.working = true
                found.efficient = found.efficient or EFFICIENT_TYPES[fullType] == true
            else
                found.broken = true
            end
        elseif item:IsInventoryContainer() then
            scan(item:getInventory(), found)
        end
    end
end

-- Counts one sample and empties the container.
local function tally(entry, container, wearsWatch)
    local found = { watch = wearsWatch }
    scan(container, found)
    entry.samples = entry.samples + 1
    for _, kind in ipairs(KINDS) do
        if found[kind] then
            entry[kind] = entry[kind] + 1
        end
    end
    container:removeAllItems()
end

local function toShares(entry)
    for _, kind in ipairs(KINDS) do
        entry[kind] = entry[kind] / entry.samples
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

-- ZombiesZoneDefinition.pickDefinition. Mandatory outfits spawn only until a zone has its quota,
-- so in the long run they are left out.
local function pickZoneOutfit(zone, female, room)
    if (zone.maleChance or 0) > 0 and ZombRand(100) < zone.maleChance then
        female = false
    end
    if (zone.femaleChance or 0) > 0 and ZombRand(100) < zone.femaleChance then
        female = true
    end
    local outfits = {}
    for _, outfit in pairs(zone) do
        if type(outfit) == "table" and tostring(outfit.mandatory) ~= "true" and fits(outfit, female, room) then
            table.insert(outfits, outfit)
        end
    end
    local picked = pickByChance(outfits, true)
    return picked and picked.name, female
end

-- ZombiesZoneDefinition.dressInRandomOutfit: the zone table first, and the Default table when it
-- picks nothing.
local function pickOutfit(spec, female)
    if spec.outfit then
        return spec.outfit, female
    end
    if spec.zone then
        local name, zoneFemale = pickZoneOutfit(ZombiesZoneDefinition[spec.zone], female, spec.room)
        if name then
            return name, zoneFemale
        end
    end
    local outfits = {}
    for _, outfit in ipairs(ZombiesZoneDefinition.Default) do
        if fits(outfit, female, spec.room) then
            table.insert(outfits, outfit)
        end
    end
    return pickByChance(outfits, false).name, female
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
    local entry = newEntry(spec)
    local bodies = { [false] = newBody(false), [true] = newBody(true) }
    local defaultLists = {
        [false] = ItemPickerJava.getItemContainer("all", "inventorymale", nil, false),
        [true] = ItemPickerJava.getItemContainer("all", "inventoryfemale", nil, false),
    }
    local corpse = ItemContainer.new()
    for _ = 1, samples do
        local outfitName, female = pickOutfit(spec, ZombRand(2) == 0)
        corpse:setType(female and "inventoryfemale" or "inventorymale")
        local watch = wearsWatch(bodies[female], outfitName)
        fillCorpse(corpse, outfitName, defaultLists[female])
        tally(entry, corpse, watch)
    end
    return toShares(entry)
end

-- Containers ------------------------------------------------------------------------------------

-- ItemPickerJava.getItemContainer finds a ProceduralDistributions list only through a room and
-- container type that roll it. Returns the list and that container type.
local function findProceduralList(listName)
    for roomName, room in pairs(SuburbsDistributions) do
        for containerType, containerTable in pairs(room) do
            if type(containerTable) == "table" and containerTable.procedural then
                for _, choice in ipairs(containerTable.procList or {}) do
                    if choice.name == listName then
                        return ItemPickerJava.getItemContainer(roomName, containerType, listName, false), containerType
                    end
                end
            end
        end
    end
    error("no container rolls ProceduralDistributions list " .. listName)
end

-- A container rolls its list as rollItem does: the junk list, then the items.
local function sampleContainer(spec, samples)
    local list, containerType
    if spec.all then
        list, containerType = ItemPickerJava.getItemContainer("all", spec.key, nil, false), spec.key
    else
        list, containerType = findProceduralList(spec.key)
    end
    local entry = newEntry(spec)
    local container = ItemContainer.new()
    container:setType(containerType)
    for _ = 1, samples do
        ItemPickerJava.rollItem(list, container, true, nil, nil)
        tally(entry, container, false)
    end
    return toShares(entry)
end

-- Report ----------------------------------------------------------------------------------------

-- Runs fn with MEASURE_OPTIONS and the General debug log off: in debug mode ItemPickInfo logs a
-- line for every roll into a container that isn't on a square, which floods console.txt.
local function withMeasureOptions(fn)
    local options = getSandboxOptions()
    local saved = {}
    for name, value in pairs(MEASURE_OPTIONS) do
        local option = options:getOptionByName(name)
        saved[name] = option:getValue()
        option:setValue(value == DEFAULT and option:getDefaultValue() or value)
    end
    local generalLog = DebugType.General:getLogSeverity()
    DebugType.General:setLogSeverity(LogSeverity.Off)
    local ok, result = pcall(fn)
    DebugType.General:setLogSeverity(generalLog)
    for name, value in pairs(saved) do
        options:getOptionByName(name):setValue(value)
    end
    if not ok then
        error(result)
    end
    return result
end

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
    return withMeasureOptions(function()
        return sampleZombies(find(ZOMBIES, key), samples)
    end)
end

function HearingAidLoot.measureContainer(key, samples)
    return withMeasureOptions(function()
        return sampleContainer(find(CONTAINERS, key), samples)
    end)
end

function HearingAidLoot.report(samples)
    return withMeasureOptions(function()
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
