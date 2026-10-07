-- Hearing aid state and rules, used by the timed action, recipes, UI and the periodic update.
--
-- Only the authority changes state: single player, or the dedicated server in multiplayer
-- (`not isClient()`). Multiplayer clients read item state for the UI and never touch traits.

HearingAid = HearingAid or {}

HearingAid.BROKEN = "HearingAid.BrokenHearingAid"
HearingAid.BASIC = "HearingAid.HearingAid"
HearingAid.EFFICIENT = "HearingAid.EfficientHearingAid"
HearingAid.BOOSTED = "HearingAid.BoostedHearingAid"
HearingAid.BATTERY = "Base.Battery"

-- The hearing traits as an ordered scale.
HearingAid.Level = { DEAF = 0, HARD_OF_HEARING = 1, NORMAL = 2, KEEN = 3 }
local Level = HearingAid.Level

-- Values of the HandleDeafness sandbox option.
HearingAid.DeafnessMode = { NONE = 1, ALL_AIDS = 2, BOOSTED_ONLY = 3 }
local DeafnessMode = HearingAid.DeafnessMode

-- Working tiers and the sandbox option that holds each one's battery life in hours.
local TIERS = {
    [HearingAid.BASIC] = { batteryHoursOption = "BatteryHoursBasic" },
    [HearingAid.EFFICIENT] = { batteryHoursOption = "BatteryHoursEfficient" },
    [HearingAid.BOOSTED] = { batteryHoursOption = "BatteryHoursBoosted", boosted = true },
}

-- The wearer is warned once when the charge drops to this fraction.
local LOW_CHARGE = 0.1

-- Item modData. CHARGE is 0-1 while a battery is inserted and nil without one.
local CHARGE = "HearingAid_charge"
local ON = "HearingAid_on"
-- Written with every change so that saved modData is never empty: item:load() keeps the random
-- OnCreate state of an item whose saved modData is empty.
local VERSION = "HearingAid_v"

-- Player modData, set only while an aid is active: the character's own hearing level and the
-- level the aid gave them.
local BASE_LEVEL = "HearingAid_baseLevel"
local APPLIED_LEVEL = "HearingAid_appliedLevel"

local SYNC_TRAITS = 2 -- SyncPlayerFieldsPacket.PF_Traits

-- Items ---------------------------------------------------------------------------------------

-- UI code passes non-items too: tooltips also show fluid containers and resources.
local function fullTypeOf(object)
    if instanceof(object, "InventoryItem") then
        return object:getFullType()
    end
    return ""
end

function HearingAid.isHearingAid(item)
    local fullType = fullTypeOf(item)
    return fullType == HearingAid.BROKEN or TIERS[fullType] ~= nil
end

function HearingAid.isWorking(item)
    return TIERS[fullTypeOf(item)] ~= nil
end

function HearingAid.isBattery(item)
    return fullTypeOf(item) == HearingAid.BATTERY
end

function HearingAid.hasBattery(aid)
    return aid:getModData()[CHARGE] ~= nil
end

-- Charge of the inserted battery from 0 to 1; 0 without a battery.
function HearingAid.getCharge(aid)
    return aid:getModData()[CHARGE] or 0
end

function HearingAid.isOn(aid)
    return aid:getModData()[ON] == true
end

-- Only an active aid changes hearing and drains its battery.
function HearingAid.isActive(item)
    return HearingAid.isWorking(item) and item:isWorn() and HearingAid.isOn(item) and HearingAid.getCharge(item) > 0
end

local function writableState(aid)
    local state = aid:getModData()
    state[VERSION] = 1
    return state
end

-- Sets the charge of the inserted battery, inserting one if the aid has none. nil removes the
-- battery, which also switches the aid off.
function HearingAid.setCharge(aid, charge)
    local state = writableState(aid)
    if charge == nil then
        state[CHARGE] = nil
        state[ON] = nil
    else
        state[CHARGE] = math.max(0, math.min(1, charge))
    end
end

function HearingAid.setOn(aid, on)
    writableState(aid)[ON] = on or nil
end

function HearingAid.copyState(from, to)
    HearingAid.setCharge(to, from:getModData()[CHARGE])
    HearingAid.setOn(to, HearingAid.isOn(from))
end

function HearingAid.getBatteryHours(aid)
    return SandboxVars.HearingAid[TIERS[aid:getFullType()].batteryHoursOption]
end

-- OnCreate of the working tiers' item scripts: a found aid may still hold a used battery. It runs
-- on every instantiation, including loading a save and crafting; item:load() and the recipe
-- OnCreate replace this state afterwards.
function HearingAid.onCreate(aid)
    local charge = nil
    if ZombRand(100) < SandboxVars.HearingAid.SpawnWithBatteryChance then
        charge = ZombRandFloat(0.05, 1.0)
    end
    HearingAid.setCharge(aid, charge)
end

-- Hearing -------------------------------------------------------------------------------------

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

-- The hearing level that an active aid of this type gives a character whose own level is `base`.
function HearingAid.getTargetLevel(base, fullType, deafnessMode)
    local boosted = TIERS[fullType].boosted
    if base == Level.DEAF then
        if deafnessMode == DeafnessMode.ALL_AIDS then
            return boosted and Level.NORMAL or Level.HARD_OF_HEARING
        elseif deafnessMode == DeafnessMode.BOOSTED_ONLY and boosted then
            return Level.HARD_OF_HEARING
        end
        return Level.DEAF
    end
    if boosted then
        return Level.KEEN
    end
    return math.max(base, Level.NORMAL)
end

local function activeAid(player)
    local worn = player:getWornItems()
    for i = 0, worn:size() - 1 do
        local item = worn:getItemByIndex(i)
        if HearingAid.isActive(item) then
            return item
        end
    end
    return nil
end

-- Dedicated server only: the base and applied levels of each online player, keyed by username.
-- A client's player modData transmit replaces the server's copy (ISHotbar sends one after every
-- clothing change) and can drop the levels just written, so readRecord() puts them back. Entries
-- remember their IsoPlayer, so a reconnect or a new character starts from the saved modData.
local serverRecords = {}

local function readRecord(player)
    local modData = player:getModData()
    if isServer() then
        local record = serverRecords[player:getUsername()]
        if record and record.player == player then
            if modData[BASE_LEVEL] ~= record.base or modData[APPLIED_LEVEL] ~= record.applied then
                modData[BASE_LEVEL] = record.base
                modData[APPLIED_LEVEL] = record.applied
                player:transmitModData()
            end
            return record.base, record.applied
        end
    end
    return modData[BASE_LEVEL], modData[APPLIED_LEVEL]
end

local function writeRecord(player, base, applied)
    local modData = player:getModData()
    local changed = modData[BASE_LEVEL] ~= base or modData[APPLIED_LEVEL] ~= applied
    modData[BASE_LEVEL] = base
    modData[APPLIED_LEVEL] = applied
    if isServer() then
        serverRecords[player:getUsername()] = { player = player, base = base, applied = applied }
        if changed then
            player:transmitModData()
        end
    end
end

-- Brings the character's hearing traits in line with the worn aids. Call it after anything that
-- can change whether an aid is active; extra calls change nothing.
function HearingAid.reconcile(player)
    if isClient() or player:isDead() then
        return
    end
    local current = HearingAid.getHearingLevel(player)
    local base, applied = readRecord(player)
    if base == nil or applied ~= current then
        -- Nothing applied yet, or something else changed the traits (admin panel, another mod):
        -- what the character has now is their own hearing.
        base = current
    end

    local aid = activeAid(player)
    local target = base
    if aid then
        target = HearingAid.getTargetLevel(base, aid:getFullType(), SandboxVars.HearingAid.HandleDeafness)
    end
    if target ~= current then
        setHearingLevel(player, target)
        if isServer() then
            sendSyncPlayerFields(player, SYNC_TRAITS)
        end
    end
    if aid then
        writeRecord(player, base, target)
    else
        writeRecord(player, nil, nil)
    end
end

-- Gives the character `level` as their own hearing and forgets what an aid applied. Used by
-- debug tools; call reconcile() afterwards if an aid may be active.
function HearingAid.setBaseLevel(player, level)
    setHearingLevel(player, level)
    writeRecord(player, nil, nil)
end

-- Shows a warning over the character's head, on the owning client in multiplayer.
function HearingAid.notify(player, textKey)
    if isServer() then
        sendServerCommand(player, "HearingAid", "notify", { key = textKey, onlineID = player:getOnlineID() })
    elseif not isClient() then
        HaloTextHelper.addBadText(player, getText(textKey))
    end
end

-- Battery drain --------------------------------------------------------------------------------

-- World age in hours at which each active aid was last drained, keyed by item id. Kept in memory
-- only: an aid drops out when it stops being active, and everything drops out on load or
-- reconnect, so time off the ear, switched off, offline or unloaded is never billed.
local lastDrain = {}

local function drain(player, aid, hours)
    if hours <= 0 then
        return
    end
    local before = HearingAid.getCharge(aid)
    local after = math.max(0, before - hours / HearingAid.getBatteryHours(aid))
    HearingAid.setCharge(aid, after)
    if after == 0 then
        HearingAid.setOn(aid, false)
        HearingAid.notify(player, "IGUI_HearingAid_BatteryDead")
    elseif before > LOW_CHARGE and after <= LOW_CHARGE then
        HearingAid.notify(player, "IGUI_HearingAid_BatteryLow")
    end
    -- Sync only when the percentage the tooltip shows changes.
    if after == 0 or round(before * 100) ~= round(after * 100) then
        aid:syncItemFields()
    end
end

-- Bills the aid for use since the last update. Call it before an action ends the aid's use, or
-- that time is lost.
function HearingAid.drainUntilNow(player, aid)
    local id = aid:getID()
    local last = lastDrain[id]
    if last then
        local now = getGameTime():getWorldAgeHours()
        drain(player, aid, now - last)
        lastDrain[id] = now
    end
end

local function authoritativePlayers()
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

-- Drains active aids and reconciles hearing. Runs every in-game minute; `now` (world age in
-- hours) lets tests move time forward.
function HearingAid.update(now)
    if isClient() then
        return
    end
    now = now or getGameTime():getWorldAgeHours()
    local tracked = {}
    for _, player in ipairs(authoritativePlayers()) do
        if not player:isDead() then
            local aid = activeAid(player)
            if aid then
                local id = aid:getID()
                if lastDrain[id] then
                    drain(player, aid, now - lastDrain[id])
                end
                if HearingAid.isActive(aid) then
                    tracked[id] = now
                end
            end
            HearingAid.reconcile(player)
        end
    end
    lastDrain = tracked
end

-- Battery items --------------------------------------------------------------------------------

function HearingAid.insertBattery(aid, battery)
    local container = battery:getContainer()
    container:Remove(battery)
    sendRemoveItemFromContainer(container, battery)
    HearingAid.setCharge(aid, battery:getCurrentUsesFloat())
end

-- Gives the aid's battery to the character as a battery item.
function HearingAid.removeBattery(player, aid)
    HearingAid.drainUntilNow(player, aid)
    local battery = instanceItem(HearingAid.BATTERY)
    battery:setCurrentUsesFloat(HearingAid.getCharge(aid))
    Actions.addOrDropItem(player, battery)
    HearingAid.setCharge(aid, nil)
end
