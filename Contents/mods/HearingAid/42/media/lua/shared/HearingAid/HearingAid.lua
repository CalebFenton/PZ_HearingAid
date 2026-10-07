-- Core hearing aid state and rules. Shared so timed actions (which run on the server in MP)
-- and the client UI use the same accessors.
--
-- Authority: battery drain and hearing trait changes happen only where `not isClient()`
-- (single player, or the dedicated server). MP clients only read state for the UI.
--
-- Item state (item modData, synced to the owner with syncItemFields):
--   HearingAid_charge  0..1 while a battery is inserted, nil when empty
--   HearingAid_on      true while switched on
-- A hearing aid is "active" when it is worn, switched on and has charge left.
--
-- Player state (player modData on the authority):
--   HearingAid_baseLevel     hearing level the character had before the aid changed it
--   HearingAid_appliedLevel  hearing level the aid set
-- Both are nil whenever no aid is active, so the mod never touches traits otherwise.
-- On a dedicated server an in-memory copy guards these against client modData transmits.

HearingAid = HearingAid or {}

HearingAid.BROKEN = "HearingAid.BrokenHearingAid"
HearingAid.BASIC = "HearingAid.HearingAid"
HearingAid.EFFICIENT = "HearingAid.EfficientHearingAid"
HearingAid.BOOSTED = "HearingAid.BoostedHearingAid"

HearingAid.Level = { DEAF = 0, HARD_OF_HEARING = 1, NORMAL = 2, KEEN = 3 }
local Level = HearingAid.Level

HearingAid.DeafnessMode = { NONE = 1, ALL_AIDS = 2, BOOSTED_ONLY = 3 }

-- Fraction of charge at which the wearer is warned once.
HearingAid.LOW_BATTERY = 0.1

local TIERS = {
    [HearingAid.BASIC] = { hoursOption = "BatteryHoursBasic", defaultHours = 48 },
    [HearingAid.EFFICIENT] = { hoursOption = "BatteryHoursEfficient", defaultHours = 144 },
    [HearingAid.BOOSTED] = { hoursOption = "BatteryHoursBoosted", defaultHours = 96, boosted = true },
}

local CHARGE = "HearingAid_charge"
local ON = "HearingAid_on"
-- Always present on spawned working aids. An item saved with empty modData would not overwrite
-- the random OnCreate state a client rolls when it instantiates the item (load() skips empty modData).
local VERSION = "HearingAid_v"
local BASE_LEVEL = "HearingAid_baseLevel"
local APPLIED_LEVEL = "HearingAid_appliedLevel"

HearingAid.ITEM_KEYS = { CHARGE, ON, VERSION }

function HearingAid.sandbox()
    return SandboxVars.HearingAid or {}
end

-- Items ---------------------------------------------------------------------------------------

-- Callers pass whatever a UI holds (tooltips also show fluid containers and resources).
local function fullTypeOf(item)
    return item ~= nil and instanceof(item, "InventoryItem") and item:getFullType() or nil
end

function HearingAid.isHearingAid(item)
    local fullType = fullTypeOf(item)
    return fullType ~= nil and (fullType == HearingAid.BROKEN or TIERS[fullType] ~= nil)
end

function HearingAid.isWorking(item)
    local fullType = fullTypeOf(item)
    return fullType ~= nil and TIERS[fullType] ~= nil
end

function HearingAid.isBoosted(item)
    return fullTypeOf(item) == HearingAid.BOOSTED
end

function HearingAid.hasBattery(item)
    return item:getModData()[CHARGE] ~= nil
end

function HearingAid.getCharge(item)
    return item:getModData()[CHARGE] or 0
end

function HearingAid.isOn(item)
    return item:getModData()[ON] == true
end

function HearingAid.isWorn(item)
    return item:isWorn()
end

function HearingAid.isActive(item)
    return HearingAid.isWorking(item) and HearingAid.isOn(item) and HearingAid.getCharge(item) > 0 and item:isWorn()
end

-- Hours of continuous use one full battery provides for this tier.
function HearingAid.getBatteryHours(item)
    local tier = TIERS[item:getFullType()]
    local hours = tonumber(HearingAid.sandbox()[tier.hoursOption]) or tier.defaultHours
    return math.max(hours, 0.01)
end

function HearingAid.setBattery(item, charge)
    local md = item:getModData()
    md[VERSION] = 1
    md[CHARGE] = math.max(0, math.min(1, charge))
end

function HearingAid.clearBattery(item)
    local md = item:getModData()
    md[VERSION] = 1
    md[CHARGE] = nil
    md[ON] = nil
end

function HearingAid.setOn(item, on)
    local md = item:getModData()
    md[VERSION] = 1
    md[ON] = on and true or nil
end

-- Copies battery and switch state between items (recipe upgrades). Clears any state `to` had.
function HearingAid.copyState(from, to)
    local src, dst = from:getModData(), to:getModData()
    for _, key in ipairs(HearingAid.ITEM_KEYS) do
        dst[key] = src[key]
    end
    dst[VERSION] = 1
end

-- Pushes item modData to the owning client. No-op in single player.
function HearingAid.syncItem(player, item)
    if isServer() then
        syncItemFields(player, item)
    end
end

-- Item script OnCreate for working tiers: a found hearing aid may still hold a used battery.
-- Runs for every instantiation (loot, crafting output, loading); load() and recipe OnCreate
-- overwrite this afterwards where it matters.
function HearingAid.onCreateWorking(item)
    local md = item:getModData()
    md[VERSION] = 1
    md[ON] = nil
    md[CHARGE] = nil
    local chance = tonumber(HearingAid.sandbox().SpawnWithBatteryChance) or 50
    if ZombRand(100) < chance then
        md[CHARGE] = ZombRandFloat(0.05, 1.0)
    end
end

-- Batteries -----------------------------------------------------------------------------------

function HearingAid.isBattery(item)
    return item ~= nil and item:getFullType() == "Base.Battery"
end

function HearingAid.getBatteryCharge(battery)
    return math.max(0, math.min(1, battery:getCurrentUsesFloat()))
end

-- Charged batteries anywhere in the player's inventory (bags included), fullest first.
function HearingAid.findBatteries(player)
    local found = player:getInventory():getAllEvalRecurse(function(item)
        return HearingAid.isBattery(item) and item:getCurrentUsesFloat() > 0
    end)
    local batteries = {}
    for i = 0, found:size() - 1 do
        table.insert(batteries, found:get(i))
    end
    table.sort(batteries, function(a, b) return a:getCurrentUsesFloat() > b:getCurrentUsesFloat() end)
    return batteries
end

-- Hearing traits ------------------------------------------------------------------------------

function HearingAid.getHearingLevel(player)
    if player:hasTrait(CharacterTrait.DEAF) then return Level.DEAF end
    if player:hasTrait(CharacterTrait.HARD_OF_HEARING) then return Level.HARD_OF_HEARING end
    if player:hasTrait(CharacterTrait.KEEN_HEARING) then return Level.KEEN end
    return Level.NORMAL
end

local function setHearingLevel(player, level)
    local traits = player:getCharacterTraits()
    traits:remove(CharacterTrait.DEAF)
    traits:remove(CharacterTrait.HARD_OF_HEARING)
    traits:remove(CharacterTrait.KEEN_HEARING)
    if level == Level.DEAF then
        traits:add(CharacterTrait.DEAF)
    elseif level == Level.HARD_OF_HEARING then
        traits:add(CharacterTrait.HARD_OF_HEARING)
    elseif level == Level.KEEN then
        traits:add(CharacterTrait.KEEN_HEARING)
    end
end

-- Hearing level a character with `base` hearing gets from an active aid of this type.
function HearingAid.getTargetLevel(base, fullType)
    local boosted = TIERS[fullType].boosted
    if base == Level.DEAF then
        local mode = tonumber(HearingAid.sandbox().HandleDeafness) or HearingAid.DeafnessMode.ALL_AIDS
        if mode == HearingAid.DeafnessMode.ALL_AIDS then
            return boosted and Level.NORMAL or Level.HARD_OF_HEARING
        elseif mode == HearingAid.DeafnessMode.BOOSTED_ONLY and boosted then
            return Level.HARD_OF_HEARING
        end
        return Level.DEAF
    end
    if boosted then
        return Level.KEEN
    end
    return math.max(base, Level.NORMAL)
end

-- The worn hearing aid that is currently helping, if any.
function HearingAid.getActiveAid(player)
    local worn = player:getWornItems()
    for i = 0, worn:size() - 1 do
        local item = worn:getItemByIndex(i)
        if item and HearingAid.isActive(item) then
            return item
        end
    end
    return nil
end

-- Dedicated server only: the authoritative record of each online player, keyed by username.
-- Clients send their whole player modData back to the server (ISHotbar does it right after
-- clothing changes), which replaces the server's copy and can drop the record just written;
-- this copy puts it back. Entries are tied to the IsoPlayer object, so a reconnect or a new
-- character starts from the saved player modData instead of a stale entry.
local serverRecords = {}

local function readRecord(player)
    local md = player:getModData()
    if isServer() then
        local cached = serverRecords[player:getUsername()]
        if cached and cached.player == player then
            if md[BASE_LEVEL] ~= cached.base or md[APPLIED_LEVEL] ~= cached.applied then
                md[BASE_LEVEL] = cached.base
                md[APPLIED_LEVEL] = cached.applied
                player:transmitModData()
            end
            return cached.base, cached.applied
        end
    end
    return md[BASE_LEVEL], md[APPLIED_LEVEL]
end

local function writeRecord(player, base, applied)
    local md = player:getModData()
    local changed = md[BASE_LEVEL] ~= base or md[APPLIED_LEVEL] ~= applied
    md[BASE_LEVEL] = base
    md[APPLIED_LEVEL] = applied
    if isServer() then
        serverRecords[player:getUsername()] = { player = player, base = base, applied = applied }
        if changed then
            player:transmitModData()
        end
    end
end

-- Brings the character's hearing traits in line with the worn aid. Idempotent; call it after
-- anything that can change whether an aid is active. Returns true if traits changed.
function HearingAid.reconcile(player)
    if isClient() or not player or player:isDead() then
        return false
    end
    local current = HearingAid.getHearingLevel(player)
    local base, applied = readRecord(player)
    if base == nil or applied ~= current then
        -- Nothing applied yet, or hearing traits were changed behind our back (admin panel,
        -- another mod): treat what the character has now as their own hearing.
        base = current
    end

    local aid = HearingAid.getActiveAid(player)
    local target = aid and HearingAid.getTargetLevel(base, aid:getFullType()) or base
    local traitsChanged = target ~= current
    if traitsChanged then
        setHearingLevel(player, target)
        if isServer() then
            sendSyncPlayerFields(player, 2) -- SyncPlayerFieldsPacket.PF_Traits
        end
    end
    writeRecord(player, aid and base or nil, aid and target or nil)
    return traitsChanged
end

-- Notifications -------------------------------------------------------------------------------

function HearingAid.notify(player, key)
    if isServer() then
        sendServerCommand(player, "HearingAid", "notify", { key = key, onlineID = player:getOnlineID() })
    elseif not isClient() then
        HaloTextHelper.addBadText(player, getText(key))
    end
end

-- Battery drain -------------------------------------------------------------------------------

-- World age (hours) at which each active aid was last drained, keyed by item id. Kept in memory
-- only: an aid that stops being active drops out, and so does everything on load or reconnect,
-- so time spent off the ear, offline or unloaded is never billed.
local lastDrain = {}

local function drain(player, aid, hours)
    if hours <= 0 then
        return
    end
    local before = HearingAid.getCharge(aid)
    local after = math.max(0, before - hours / HearingAid.getBatteryHours(aid))
    aid:getModData()[CHARGE] = after
    if after <= 0 then
        HearingAid.setOn(aid, false)
        HearingAid.notify(player, "IGUI_HearingAid_BatteryDead")
    elseif before > HearingAid.LOW_BATTERY and after <= HearingAid.LOW_BATTERY then
        HearingAid.notify(player, "IGUI_HearingAid_BatteryLow")
    end
    if after <= 0 or math.floor(before * 100) ~= math.floor(after * 100) then
        HearingAid.syncItem(player, aid)
    end
end

-- Bills an aid for use up to now and stops tracking it. Call before switching it off or
-- taking its battery out.
function HearingAid.settle(player, aid, now)
    now = now or getGameTime():getWorldAgeHours()
    local last = lastDrain[aid:getID()]
    lastDrain[aid:getID()] = nil
    if last then
        drain(player, aid, now - last)
    end
end

-- Players whose state this Lua instance owns.
function HearingAid.getAuthoritativePlayers()
    local players = {}
    if isServer() then
        local online = getOnlinePlayers()
        for i = 0, online:size() - 1 do
            table.insert(players, online:get(i))
        end
    elseif not isClient() then
        for i = 0, getNumActivePlayers() - 1 do
            local player = getSpecificPlayer(i)
            if player then
                table.insert(players, player)
            end
        end
    end
    return players
end

-- Periodic tick on the authority: drains active aids and reconciles hearing.
function HearingAid.update(now)
    if isClient() then
        return
    end
    now = now or getGameTime():getWorldAgeHours()
    local seen = {}
    for _, player in ipairs(HearingAid.getAuthoritativePlayers()) do
        if not player:isDead() then
            local aid = HearingAid.getActiveAid(player)
            if aid then
                local last = lastDrain[aid:getID()]
                if last then
                    drain(player, aid, now - last)
                end
                if HearingAid.isActive(aid) then
                    seen[aid:getID()] = now
                end
            end
            HearingAid.reconcile(player)
        end
    end
    lastDrain = seen
end
