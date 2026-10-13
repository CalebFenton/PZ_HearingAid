require "PZHarness/ServerFixtures"
require "HearingAid/HearingAid"
require "HearingAid/HearingAidRecipes"
require "HearingAid/Debug/HearingAidLoot"

-- Development only, not published. The server's half of HearingAidTests.lua: what only the
-- authority does to the character, its hearing aids and their batteries, called with
-- PZHarness.Test.server (dev/harness/docs/multiplayer.md). On a multiplayer server these act on
-- the server's copy of the character; single player runs them in its one game. A --stay rerun
-- loads this file again, so it only registers handlers.

local handler = PZHarness.serverHandler

-- The recipes' skill levels follow the *SkillLevel options on the server too.
PZHarness.serverSettings.sandboxChanged = HearingAid.Recipes.applySkillLevels

local SYNC_TRAITS = 2 -- SyncPlayerFieldsPacket.PF_Traits

local function aidState(player, item)
    return {
        id = item:getID(),
        type = item:getFullType(),
        battery = HearingAid.hasBattery(item),
        charge = HearingAid.getCharge(item),
        on = HearingAid.isOn(item),
        worn = player:getWornItems():contains(item),
    }
end

-- The character's hearing level, every hearing aid and battery in its inventory (not in bags), and
-- the types of what it wears.
local function state(player)
    local aids, batteries, worn = {}, {}, {}
    local items = player:getInventory():getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if HearingAid.isHearingAid(item) then
            table.insert(aids, aidState(player, item))
        elseif HearingAid.isBattery(item) then
            table.insert(batteries, item:getCurrentUsesFloat())
        end
    end
    local wornItems = player:getWornItems()
    for i = 0, wornItems:size() - 1 do
        table.insert(worn, wornItems:getItemByIndex(i):getFullType())
    end
    return { hearing = HearingAid.getHearingLevel(player), aids = aids, batteries = batteries, worn = worn }
end

-- Every test starts from the character's own hearing `args.level`: traits and player modData carry
-- over from the test before. With `args.periodicUpdate = false` the every-minute HearingAid.update
-- stops until the test ends, so a test can show that an action drains the battery itself.
handler("hearing", function(player, args, defer)
    HearingAid.setBaseLevel(player, args.level)
    sendSyncPlayerFields(player, SYNC_TRAITS)
    if args.periodicUpdate == false then
        Events.EveryOneMinute.Remove(HearingAid.update)
        defer(function() Events.EveryOneMinute.Add(HearingAid.update) end)
    end
    return {}
end)

-- Hearing aids and batteries for the character: `args.items` is a list of { type, charge, on, worn }:
-- an aid with a battery of `charge` (none if nil), switched on if `on`, put on if `worn`; or a
-- battery (HearingAid.BATTERY) holding `charge`. The reply lists them as `given`, and `now` is the
-- world age in hours, a base for "steps".
handler("giveAids", function(player, args)
    local given = {}
    for _, spec in ipairs(args.items or {}) do
        local item = instanceItem(spec.type)
        if HearingAid.isBattery(item) then
            item:setCurrentUsesFloat(spec.charge)
        else
            HearingAid.setCharge(item, spec.charge)
            HearingAid.setOn(item, spec.on)
        end
        table.insert(given, PZHarness.giveItem(player, item, { worn = spec.worn }))
    end
    return { given = given, now = getGameTime():getWorldAgeHours() }
end)

local function aid(player, id)
    local item = player:getInventory():getItemById(id)
    if not HearingAid.isHearingAid(item) then
        error("no hearing aid " .. tostring(id))
    end
    return item
end

-- What the periodic update and the character do over time, in one go so that no periodic update
-- comes in between: `args.steps` is a list of { op = "update", at = hours after `args.base` (the
-- world age now by default) }, { op = "wear", id } and { op = "takeOff", id } (at once, without an
-- action), and { op = "switch", id, on } (without an action). Replies with the state after them.
handler("steps", function(player, args)
    local base = args.base or getGameTime():getWorldAgeHours()
    for _, step in ipairs(args.steps or {}) do
        if step.op == "update" then
            HearingAid.update(base + step.at)
        elseif step.op == "wear" then
            local item = aid(player, step.id)
            player:setWornItem(item:getBodyLocation(), item)
            syncVisuals(player)
            HearingAid.reconcile(player)
        elseif step.op == "takeOff" then
            player:removeWornItem(aid(player, step.id))
            syncVisuals(player)
        elseif step.op == "switch" then
            local item = aid(player, step.id)
            HearingAid.setOn(item, step.on)
            item:syncItemFields()
        else
            error("unknown step " .. tostring(step.op))
        end
    end
    return state(player)
end)

handler("state", function(player)
    return state(player)
end)

-- An admin, or another mod, gives the character Keen Hearing.
handler("keenHearing", function(player)
    player:getCharacterTraits():add(CharacterTrait.KEEN_HEARING)
    sendSyncPlayerFields(player, SYNC_TRAITS)
    return {}
end)

-- A new item of `args.type`, as loot makes them, never given to anyone.
handler("instantiate", function(_, args)
    local item = instanceItem(args.type)
    return { battery = HearingAid.hasBattery(item), charge = HearingAid.getCharge(item) }
end)

-- Corpse loot is rolled by the server in multiplayer, whose loot lists hold the aids.
handler("corpseLoot", function(_, args)
    return {
        ordinary = HearingAidLoot.measureZombies("ordinary", args.ordinary),
        retirees = HearingAidLoot.measureZombies("retirees", args.retirees),
    }
end)
