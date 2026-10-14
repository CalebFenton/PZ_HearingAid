require "PZHarness/TestLib"
require "TimedActions/HearingAidAction"
require "TimedActions/ISUnequipAction"
require "TimedActions/ISWearClothing"
require "HearingAid/HearingAidRecipes"
local Debug = require "HearingAid/Debug/HearingAidDebug"

-- The mod's in-game tests, on the shared harness's test library
-- (dev/harness/mod/42/media/lua/client/PZHarness/TestLib.lua explains the runner, the restore
-- stack and the rules that keep each test independent of the ones before it). Besides the
-- library's spec fields, a test may set `hearing`, the character's own hearing level, and
-- `periodicUpdate = false`; HearingAidTests.setup applies them. Each result is printed to
-- console.txt as "HearingAidTest PASS <name>" or "HearingAidTest FAIL <name>: <reasons>".
--
-- The same tests run in single player and multiplayer (dev/run-debug-client.sh --test --mp). What
-- only the authority does (give aids, move time on, read hearing and aid state) goes through the
-- handlers in server/HearingAid/Debug/HearingAidTestServer.lua; the tests act as a player does,
-- through actions and menus on this client, check the server's state, and then expect this
-- client to show the same (expectClientAgrees). Everything a test does to the game is queued, so
-- it happens in order once the server has answered.

HearingAidTests = HearingAidTests or {}

local T = PZHarness.Test
local player, expect, expectNear = T.player, T.expect, T.expectNear

local Level = HearingAid.Level
local Mode = HearingAid.DeafnessMode
local BASIC, EFFICIENT, BOOSTED, BROKEN = HearingAid.BASIC, HearingAid.EFFICIENT, HearingAid.BOOSTED, HearingAid.BROKEN
local WORKING = { BASIC, EFFICIENT, BOOSTED }
local BATTERY = HearingAid.BATTERY
local leftEar = HearingAid.leftEarType

local LEVEL_NAMES = {
    [Level.DEAF] = "deaf",
    [Level.HARD_OF_HEARING] = "hard of hearing",
    [Level.NORMAL] = "normal",
    [Level.KEEN] = "keen",
}

-- Battery items store whole uses, about 0.007 of a full charge each, game time passes while an
-- action runs, and the server sends an aid's charge only when its percentage changes.
local CHARGE_TOLERANCE = 0.01
-- How long this client may take to show what the server changed: traits, item fields, clothing.
local SYNC_MS = 5000

local function levelName(level)
    return LEVEL_NAMES[level] or tostring(level)
end

-- Queues a wait until `condition()` holds, for at most SYNC_MS; validate checks what it waited for.
local function waitForSync(condition)
    local sinceMs
    T.waitUntil(function()
        sinceMs = sinceMs or getTimestampMs()
        return condition() or getTimestampMs() - sinceMs > SYNC_MS
    end, math.huge)
end

--- The settings' setup (HearingAidDevHarness.lua): every test starts from the character's own
--- hearing `spec.hearing`, Hard of Hearing unless set, since traits and player modData carry over
--- from the test before; `spec.periodicUpdate = false` stops the every-minute HearingAid.update
--- until the test ends, so a test can show that an action drains the battery itself.
function HearingAidTests.setup(self, spec)
    local level = spec.hearing or Level.HARD_OF_HEARING
    T.server(self, "hearing", { level = level, periodicUpdate = spec.periodicUpdate })
    waitForSync(function() return HearingAid.getHearingLevel(player()) == level end)
end

-- Gives the character hearing aids and batteries the way the server does: each item { type,
-- charge, on, worn } (see giveAids in HearingAidTestServer.lua). This client's copies land in
-- self.items.giveAids, in order, and self.server.giveAids.now is the world age in hours then.
local function giveAids(self, items)
    T.server(self, "giveAids", { items = items })
end

-- This client's copy of the i-th item giveAids gave.
local function given(self, i)
    return self.items.giveAids[i]
end

local function queueAidAction(mode, aid, battery)
    ISTimedActionQueue.add(HearingAidAction:new(player(), mode, aid, battery))
end

-- State ----------------------------------------------------------------------------------------

local function describe(battery, charge, on, worn)
    return (battery and string.format("charge %.3f", charge) or "no battery") .. (on and ", on" or ", off")
        .. (worn and ", worn" or "")
end

-- Where this client's copy disagrees with `state`, the server's (HearingAidTestServer.lua): the
-- hearing level, each aid's battery, switch and whether it is worn, and the number of batteries.
local function disagreements(state)
    local found = {}
    local p = player()
    local hearing = HearingAid.getHearingLevel(p)
    if hearing ~= state.hearing then
        table.insert(found, "this client's hearing is " .. levelName(hearing) .. ", the server's " .. levelName(state.hearing))
    end
    local inventory = p:getInventory()
    for _, aid in ipairs(state.aids) do
        local copy = inventory:getItemById(aid.id)
        if not copy then
            table.insert(found, "this client has no " .. aid.type)
        else
            local battery, charge, on = HearingAid.hasBattery(copy), HearingAid.getCharge(copy), HearingAid.isOn(copy)
            local worn = p:getWornItems():contains(copy)
            if battery ~= aid.battery or math.abs(charge - aid.charge) > CHARGE_TOLERANCE or on ~= aid.on or worn ~= aid.worn then
                table.insert(found, "this client's " .. aid.type .. " has " .. describe(battery, charge, on, worn)
                    .. ", the server's " .. describe(aid.battery, aid.charge, aid.on, aid.worn))
            end
        end
    end
    local batteries = inventory:getCountType(BATTERY)
    if batteries ~= #state.batteries then
        table.insert(found, "this client has " .. batteries .. " batteries, the server " .. #state.batteries)
    end
    return found
end

-- Queues a call of the server handler `handler` ("state" unless given) whose reply is the state
-- of the character's hearing and aids, into self.state, and a wait until this client shows the
-- same. Every test that read a state also expects this client to agree with it (see test()).
local function readState(self, handler, args)
    handler = handler or "state"
    T.server(self, handler, args)
    waitForSync(function()
        self.state = self.server[handler]
        return #disagreements(self.state) == 0
    end)
end

-- Expectations ---------------------------------------------------------------------------------

local NO_STATE = { aids = {}, batteries = {}, worn = {} }

-- The state readState read; without one, an empty state and a failure: an action that stops
-- empties the action queue, dropping what was queued after it.
local function stateOf(self)
    if self.state then
        return self.state
    end
    if not self.stateMissed then
        self.stateMissed = true
        expect(false, "the server's state was never read: an action stopped and emptied the action queue")
    end
    return NO_STATE
end

local function expectHearing(self, expected)
    local actual = stateOf(self).hearing
    expect(actual == expected, "hearing is " .. levelName(actual) .. ", expected " .. levelName(expected))
end

-- The server's state of the aid with this id; an empty table, and a failure, if it is gone.
local function aidState(self, id)
    for _, aid in ipairs(stateOf(self).aids) do
        if aid.id == id then
            return aid
        end
    end
    expect(self.stateMissed, "the server has no aid " .. tostring(id))
    return {}
end

-- The server's state of the i-th aid giveAids gave.
local function givenState(self, i)
    return aidState(self, given(self, i):getID())
end

-- The server's states of the aids of this type.
local function aidsOfType(self, fullType)
    local found = {}
    for _, aid in ipairs(stateOf(self).aids) do
        if aid.type == fullType then
            table.insert(found, aid)
        end
    end
    return found
end

local function expectCharge(aid, expected, tolerance)
    expectNear(tostring(aid.type) .. " charge", aid.charge, expected, tolerance)
end

-- Expects the server's state to hold this many aids of the type.
local function expectAids(self, fullType, expected)
    local actual = #aidsOfType(self, fullType)
    expect(actual == expected, actual .. " " .. fullType .. " in the inventory, expected " .. expected)
end

-- Expects exactly one battery in the server's inventory, holding this charge.
local function expectBattery(self, charge)
    local batteries = stateOf(self).batteries
    expect(#batteries == 1, #batteries .. " batteries in the inventory, expected 1")
    if #batteries == 1 then
        expectNear("battery charge", batteries[1], charge, CHARGE_TOLERANCE)
    end
end

local function expectClientAgrees(self)
    for _, problem in ipairs(disagreements(self.state)) do
        expect(false, problem)
    end
end

-- Registers a test. Its timed actions finish in one tick unless `spec.instant` is false: the tests
-- check what an action does, not how long it takes. A test that read the server's state expects
-- this client to show the same.
local function test(name, spec)
    if spec.instant == nil then
        spec.instant = true
    end
    local validate = spec.validate
    spec.validate = function(self)
        if validate then
            validate(self)
        end
        if self.state then
            expectClientAgrees(self)
        end
    end
    T.test(name, spec)
end

-- Hearing --------------------------------------------------------------------------------------

-- What each working tier gives a character with this own hearing level.
local HEARING_WITH_AID = {
    [Level.HARD_OF_HEARING] = { Level.NORMAL, Level.NORMAL, Level.KEEN },
    [Level.NORMAL] = { Level.NORMAL, Level.NORMAL, Level.KEEN },
    [Level.KEEN] = { Level.KEEN, Level.KEEN, Level.KEEN },
}
-- What each working tier gives a deaf character, per HandleDeafness option.
local DEAF_WITH_AID = {
    [Mode.NONE] = { Level.DEAF, Level.DEAF, Level.DEAF },
    [Mode.ALL_AIDS] = { Level.HARD_OF_HEARING, Level.HARD_OF_HEARING, Level.NORMAL },
    [Mode.BOOSTED_ONLY] = { Level.DEAF, Level.DEAF, Level.HARD_OF_HEARING },
}

test("hearingaid_hearing_levels", {
    validate = function(self)
        for mode, deafRow in pairs(DEAF_WITH_AID) do
            for base = Level.DEAF, Level.KEEN do
                local row = base == Level.DEAF and deafRow or HEARING_WITH_AID[base]
                for i, rightEar in ipairs(WORKING) do
                    for _, fullType in ipairs({ rightEar, leftEar(rightEar) }) do
                        local actual = HearingAid.getTargetLevel(base, fullType, mode)
                        expect(actual == row[i], "HandleDeafness " .. mode .. ", " .. LEVEL_NAMES[base] .. ", " .. fullType
                            .. ": got " .. tostring(LEVEL_NAMES[actual]) .. ", expected " .. LEVEL_NAMES[row[i]])
                    end
                end
            end
        end
    end,
})

test("hearingaid_handle_deafness_option", {
    hearing = Level.DEAF,
    sandbox = { HandleDeafness = Mode.NONE },
    run = function(self)
        giveAids(self, { { type = BOOSTED, charge = 1, worn = true } })
        T.step(function()
            queueAidAction(HearingAidAction.TURN_ON, given(self, 1))
            readState(self)
        end)
    end,
    validate = function(self)
        expect(givenState(self, 1).on, "aid is off")
        expectHearing(self, Level.DEAF)
    end,
})

test("hearingaid_turn_on", {
    run = function(self)
        giveAids(self, { { type = BASIC, charge = 1, worn = true } })
        T.step(function()
            queueAidAction(HearingAidAction.TURN_ON, given(self, 1))
            readState(self)
        end)
    end,
    validate = function(self)
        expect(givenState(self, 1).on, "aid is off")
        expectHearing(self, Level.NORMAL)
    end,
})

test("hearingaid_turn_off", {
    sandbox = { BatteryHoursBasic = 10 },
    periodicUpdate = false,
    run = function(self)
        giveAids(self, { { type = BASIC, charge = 1, on = true, worn = true } })
        -- The last drain was two hours ago, so turning off bills two of the battery's ten hours.
        readState(self, "steps", { steps = { { op = "update", at = -2 } } })
        T.step(function()
            self.hearingWhileOn = self.state.hearing
            queueAidAction(HearingAidAction.TURN_OFF, given(self, 1))
            readState(self)
        end)
    end,
    validate = function(self)
        expect(self.hearingWhileOn == Level.NORMAL, "aid didn't help while on")
        local aid = givenState(self, 1)
        expect(not aid.on, "aid is still on")
        expectCharge(aid, 0.8, CHARGE_TOLERANCE)
        expectHearing(self, Level.HARD_OF_HEARING)
    end,
})

test("hearingaid_wear_switched_on_aid", {
    run = function(self)
        giveAids(self, { { type = BASIC, charge = 1, on = true } })
        readState(self, "steps", { steps = { { op = "update", at = 0 } } })
        T.step(function()
            self.hearingBeforeWearing = self.state.hearing
            ISTimedActionQueue.add(ISWearClothing:new(player(), given(self, 1)))
            readState(self)
        end)
    end,
    validate = function(self)
        expect(self.hearingBeforeWearing == Level.HARD_OF_HEARING, "aid helped before it was worn")
        expect(givenState(self, 1).worn, "aid is not worn")
        expectHearing(self, Level.NORMAL)
    end,
})

test("hearingaid_take_off_switched_on_aid", {
    run = function(self)
        giveAids(self, { { type = BASIC, charge = 1, on = true, worn = true } })
        readState(self)
        T.step(function()
            self.hearingWhileWorn = self.state.hearing
            ISTimedActionQueue.add(ISUnequipAction:new(player(), given(self, 1), 50))
            readState(self)
        end)
    end,
    validate = function(self)
        expect(self.hearingWhileWorn == Level.NORMAL, "aid didn't help while worn")
        expect(not givenState(self, 1).worn, "aid is still worn")
        expectHearing(self, Level.HARD_OF_HEARING)
    end,
})

test("hearingaid_wear_broken_aid_over_working_one", {
    run = function(self)
        giveAids(self, { { type = BASIC, charge = 1, on = true, worn = true }, { type = BROKEN } })
        T.step(function()
            ISTimedActionQueue.add(ISWearClothing:new(player(), given(self, 2)))
            readState(self)
        end)
    end,
    validate = function(self)
        expect(givenState(self, 2).worn, "broken aid is not worn")
        expect(not givenState(self, 1).worn, "working aid is still worn")
        expectHearing(self, Level.HARD_OF_HEARING)
    end,
})

test("hearingaid_keeps_outside_trait_changes", {
    run = function(self)
        giveAids(self, { { type = BASIC, charge = 1, on = true, worn = true } })
        -- An admin gives the character Keen Hearing while the aid is on.
        T.server(self, "keenHearing")
        T.step(function()
            queueAidAction(HearingAidAction.TURN_OFF, given(self, 1))
            readState(self)
        end)
    end,
    validate = function(self)
        expectHearing(self, Level.KEEN)
    end,
})

-- Batteries ------------------------------------------------------------------------------------

test("hearingaid_insert_battery", {
    run = function(self)
        giveAids(self, { { type = BASIC }, { type = BATTERY, charge = 0.5 } })
        T.step(function()
            queueAidAction(HearingAidAction.INSERT_BATTERY, given(self, 1), given(self, 2))
            readState(self)
        end)
    end,
    validate = function(self)
        local aid = givenState(self, 1)
        expectCharge(aid, 0.5, CHARGE_TOLERANCE)
        expect(#stateOf(self).batteries == 0, #stateOf(self).batteries .. " batteries in the inventory, expected 0")
        expect(not aid.on, "aid switched itself on")
    end,
})

test("hearingaid_remove_battery", {
    sandbox = { BatteryHoursBasic = 10 },
    periodicUpdate = false,
    run = function(self)
        giveAids(self, { { type = BASIC, charge = 0.5, on = true, worn = true } })
        -- The last drain was two hours ago, so the battery comes out with 0.5 - 2/10 left.
        T.server(self, "steps", { steps = { { op = "update", at = -2 } } })
        T.step(function()
            queueAidAction(HearingAidAction.REMOVE_BATTERY, given(self, 1))
            readState(self)
        end)
    end,
    validate = function(self)
        local aid = givenState(self, 1)
        expect(not aid.battery, "aid still has a battery")
        expect(not aid.on, "aid is still on")
        expectBattery(self, 0.3)
        expectHearing(self, Level.HARD_OF_HEARING)
    end,
})

test("hearingaid_found_battery_chance", {
    sandbox = { SpawnWithBatteryChance = 100 },
    run = function(self)
        T.server(self, "instantiate", { type = BASIC })
        T.step(function()
            self.always = self.server.instantiate
            T.setSandbox(self, "SpawnWithBatteryChance", 0)
            T.server(self, "instantiate", { type = BASIC })
        end)
    end,
    validate = function(self)
        expect(self.always.battery, "no battery at a 100% chance")
        expect(not self.always.battery or self.always.charge > 0, "found battery is dead")
        expect(not self.server.instantiate.battery, "battery at a 0% chance")
    end,
})

-- The tests below move time on through HearingAidTestServer.lua's steps, all in one go on the
-- server, so the periodic update stays out of the way.

test("hearingaid_battery_runs_out", {
    sandbox = { BatteryHoursBasic = 10 },
    periodicUpdate = false,
    run = function(self)
        giveAids(self, { { type = BASIC, charge = 0.05, on = true, worn = true } })
        readState(self, "steps", { steps = { { op = "update", at = 0 }, { op = "update", at = 1 } } })
    end,
    validate = function(self)
        local aid = givenState(self, 1)
        expectCharge(aid, 0)
        expect(aid.battery, "dead battery was removed")
        expect(not aid.on, "aid is still on")
        expectHearing(self, Level.HARD_OF_HEARING)
    end,
})

test("hearingaid_battery_life_per_tier", {
    sandbox = { BatteryHoursBasic = 8, BatteryHoursEfficient = 16, BatteryHoursBoosted = 4 },
    periodicUpdate = false,
    run = function(self)
        local aids = {}
        for _, fullType in ipairs(WORKING) do
            table.insert(aids, { type = fullType, charge = 1, on = true })
        end
        giveAids(self, aids)
        -- Each tier in turn worn for two hours, ten hours apart.
        readState(self, "steps", function()
            local steps = {}
            for i in ipairs(WORKING) do
                table.insert(steps, { op = "wear", id = given(self, i):getID() })
                table.insert(steps, { op = "update", at = 10 * i })
                table.insert(steps, { op = "update", at = 10 * i + 2 })
            end
            return { steps = steps }
        end)
    end,
    validate = function(self)
        -- Two hours of use on 8, 16 and 4 hour batteries.
        for i, expected in ipairs({ 0.75, 0.875, 0.5 }) do
            expectCharge(givenState(self, i), expected)
        end
    end,
})

test("hearingaid_no_drain_while_inactive", {
    sandbox = { BatteryHoursBasic = 10 },
    periodicUpdate = false,
    run = function(self)
        giveAids(self, { { type = BASIC, charge = 1, on = true, worn = true } })
        readState(self, "steps", function()
            local id = given(self, 1):getID()
            return { steps = {
                { op = "update", at = 0 },
                -- Five hours off the ear.
                { op = "takeOff", id = id },
                { op = "update", at = 5 },
                -- Two hours worn but switched off.
                { op = "wear", id = id },
                { op = "switch", id = id, on = false },
                { op = "update", at = 5 },
                { op = "update", at = 7 },
                -- One hour of use, a tenth of the battery.
                { op = "switch", id = id, on = true },
                { op = "update", at = 7 },
                { op = "update", at = 8 },
            } }
        end)
    end,
    validate = function(self)
        expectCharge(givenState(self, 1), 0.9)
    end,
})

-- Crafting -------------------------------------------------------------------------------------

local REPAIR = "HearingAid.RepairHearingAid"
local OPTIMIZE = "HearingAid.OptimizeHearingAid"
local BOOST = "HearingAid.BoostHearingAid"
local DISMANTLE = "HearingAid.DismantleHearingAid"

-- Registers a test that crafts `spec.recipe` the way the right-click menu does, from a new aid of
-- type `spec.aid` with `spec.charge` and `spec.on`. The character has Electrical `spec.electrical`
-- (8 unless set), every recipe material, wearing the one of type `spec.wear` if set, and a table.
-- validate() expects the counts in `spec.counts` in the server's inventory, then runs
-- `spec.validate(self)`. A failing test also reports why the game refused the craft
-- (T.startCraft).
local function craftTest(name, spec)
    local counted = {}
    for fullType in pairs(spec.counts) do
        table.insert(counted, fullType)
    end
    test(name, {
        sandbox = spec.sandbox,
        run = function(self)
            T.setPerk(self, Perks.Electricity, spec.electrical or 8)
            T.placeWorkTable(player())
            local materials = {}
            for _, material in ipairs(Debug.RECIPE_MATERIALS) do
                table.insert(materials, { type = material.type, count = material.count, worn = material.type == spec.wear or nil })
            end
            T.give(self, "materials", materials)
            giveAids(self, { { type = spec.aid, charge = spec.charge, on = spec.on } })
            T.step(function()
                local recipe = T.need(self, getScriptManager():getCraftRecipe(spec.recipe), "the recipe " .. spec.recipe)
                if not recipe then return end
                T.startCraft(self, recipe, given(self, 1))
                T.count(self, "craft", counted)
                readState(self)
            end)
        end,
        validate = function(self)
            for fullType, count in pairs(spec.counts) do
                local actual = self.counts.craft[fullType]
                expect(actual == count, tostring(actual) .. " " .. fullType .. " in the inventory, expected " .. count)
            end
            if spec.validate then
                spec.validate(self)
            end
        end,
    })
end

craftTest("hearingaid_craft_repair", {
    -- At this chance the output's item OnCreate always rolls a battery, which the recipe must
    -- discard because the broken aid had none.
    sandbox = { SpawnWithBatteryChance = 100 },
    recipe = REPAIR,
    aid = BROKEN,
    counts = { [BASIC] = 1, [BROKEN] = 0 },
    validate = function(self)
        local repaired = aidsOfType(self, BASIC)[1]
        expect(not (repaired and repaired.battery), "repair created a battery")
    end,
})

-- People wear their reading glasses for close work, and a worn pair must serve as the magnifier.
craftTest("hearingaid_craft_with_worn_reading_glasses", {
    recipe = REPAIR,
    aid = BROKEN,
    wear = "Base.Glasses_Reading",
    counts = { [BASIC] = 1 },
    validate = function(self)
        local GLASSES = "Base.Glasses_Reading"
        local worn = false
        for _, fullType in ipairs(stateOf(self).worn) do
            worn = worn or fullType == GLASSES
        end
        expect(worn, "reading glasses taken off")
        local wornHere, wornItems = false, player():getWornItems()
        for i = 0, wornItems:size() - 1 do
            wornHere = wornHere or wornItems:getItemByIndex(i):getFullType() == GLASSES
        end
        expect(wornHere, "reading glasses taken off on this client")
    end,
})

local function expectUpgraded(self, fullType)
    local upgraded = aidsOfType(self, fullType)[1]
    if upgraded then
        expectCharge(upgraded, 0.42)
        expect(upgraded.on, "aid was switched off")
    end
end

craftTest("hearingaid_craft_upgrade_keeps_battery", {
    sandbox = { SpawnWithBatteryChance = 0 },
    recipe = OPTIMIZE,
    aid = BASIC,
    charge = 0.42,
    on = true,
    counts = { [EFFICIENT] = 1 },
    validate = function(self)
        expectUpgraded(self, EFFICIENT)
    end,
})

craftTest("hearingaid_craft_upgrade_left_ear_aid", {
    sandbox = { SpawnWithBatteryChance = 0 },
    recipe = OPTIMIZE,
    aid = leftEar(BASIC),
    charge = 0.42,
    on = true,
    counts = { [EFFICIENT] = 1, [leftEar(BASIC)] = 0, [leftEar(EFFICIENT)] = 0 },
    validate = function(self)
        expectUpgraded(self, EFFICIENT)
    end,
})

craftTest("hearingaid_craft_dismantle_returns_battery", {
    recipe = DISMANTLE,
    aid = EFFICIENT,
    charge = 0.6,
    counts = { [EFFICIENT] = 0 },
    validate = function(self)
        expectBattery(self, 0.6)
    end,
})

craftTest("hearingaid_craft_boost", {
    sandbox = { EnableBoosted = true },
    recipe = BOOST,
    aid = EFFICIENT,
    counts = { [BOOSTED] = 1, [EFFICIENT] = 0 },
})

craftTest("hearingaid_craft_boost_disabled", {
    sandbox = { EnableBoosted = false },
    recipe = BOOST,
    aid = EFFICIENT,
    counts = { [BOOSTED] = 0, [EFFICIENT] = 1 },
})

craftTest("hearingaid_craft_skill_level_from_sandbox", {
    sandbox = { RepairSkillLevel = 5 },
    electrical = 4,
    recipe = REPAIR,
    aid = BROKEN,
    counts = { [BASIC] = 0, [BROKEN] = 1 },
    validate = function(self)
        local expected = getScriptManager():getCraftRecipe(REPAIR):getName() .. ": skills too low"
        expect(self.refusal == expected, "refusal was " .. tostring(self.refusal) .. ", expected " .. expected)
    end,
})

craftTest("hearingaid_craft_without_skill_requirement", {
    sandbox = { RepairSkillLevel = 0 },
    electrical = 0,
    recipe = REPAIR,
    aid = BROKEN,
    counts = { [BASIC] = 1 },
})

-- Loot -----------------------------------------------------------------------------------------

-- Measured where the loot is rolled, on the server in multiplayer (HearingAidLoot.lua through
-- HearingAidTestServer.lua's corpseLoot). The test holds what the loot is for, not its tuning:
-- dev/run-debug-client.sh --loot measures the rates.
test("hearingaid_corpse_loot", {
    run = function(self)
        T.server(self, "corpseLoot", { ordinary = 12000, retirees = 1000 })
    end,
    validate = function(self)
        local ordinary, retirees = self.server.corpseLoot.ordinary, self.server.corpseLoot.retirees
        print(string.format(PZHarness.run.tag .. " INFO ordinary corpses: %.2f%% wristwatch, %.2f%% broken aid, %.2f%% working aid,"
            .. " %.2f%% any aid; retirees: %.2f%% any aid", ordinary.watch * 100, ordinary.broken * 100,
            ordinary.working * 100, ordinary.any * 100, retirees.any * 100))
        expect(ordinary.working > 0, "no working aids on ordinary corpses")
        expect(ordinary.broken > ordinary.working, "broken aids on ordinary corpses not more common than working ones")
        expect(retirees.any > ordinary.any, "retirees not more likely than ordinary corpses to carry an aid")
    end,
})

-- Context menu ---------------------------------------------------------------------------------

local MENU_OPTIONS = {
    { name = "AddBattery", textKey = "ContextMenu_AddBattery" },
    { name = "TurnOn", textKey = "ContextMenu_Turn_On" },
    { name = "TurnOff", textKey = "ContextMenu_Turn_Off" },
    { name = "RemoveBattery", textKey = "ContextMenu_Remove_Battery" },
}

-- Builds the real inventory context menu for the item and lists its hearing aid options, for
-- example "TurnOn(disabled), RemoveBattery" or "AddBattery[Battery (75%), Battery (25%)]".
local function describeMenu(item)
    local context = ISInventoryPaneContextMenu.createMenu(0, true, { item }, 300, 300)
    local found = {}
    for _, entry in ipairs(MENU_OPTIONS) do
        local option = context:getOptionFromName(getText(entry.textKey))
        if option then
            local text = entry.name
            if option.notAvailable then
                text = text .. "(disabled)"
            end
            if option.subOption then
                local choices = {}
                for _, choice in ipairs(context:getSubMenu(option.subOption).options) do
                    table.insert(choices, choice.name)
                end
                text = text .. "[" .. table.concat(choices, ", ") .. "]"
            end
            table.insert(found, text)
        end
    end
    context:hideAndChildren()
    return table.concat(found, ", ")
end

test("hearingaid_context_menu", {
    run = function(self)
        -- No empty battery: the game deletes a drainable item as soon as its uses run out
        -- (DrainableComboItem.update), so none ever sits in an inventory.
        giveAids(self, {
            { type = BASIC },
            { type = EFFICIENT, charge = 0.5 },
            { type = BOOSTED, charge = 0.5, on = true },
            { type = BASIC, charge = 0 },
            { type = BROKEN },
            { type = BATTERY, charge = 0.25 },
            { type = BATTERY, charge = 0.75 },
        })
    end,
    validate = function(self)
        local battery = given(self, 6):getDisplayName()
        local cases = {
            { "no battery", given(self, 1), "AddBattery[" .. battery .. " (75%), " .. battery .. " (25%)]" },
            { "switched off", given(self, 2), "TurnOn, RemoveBattery" },
            { "switched on", given(self, 3), "TurnOff, RemoveBattery" },
            { "dead battery", given(self, 4), "TurnOn(disabled), RemoveBattery" },
            { "broken", given(self, 5), "" },
        }
        for _, case in ipairs(cases) do
            local label, aid, expected = case[1], case[2], case[3]
            local actual = describeMenu(aid)
            expect(actual == expected, label .. ": menu is \"" .. actual .. "\", expected \"" .. expected .. "\"")
        end
    end,
})

-- Ears -----------------------------------------------------------------------------------------

local ON_RIGHT_EAR = "ContextMenu_HearingAid_EarRight"
local ON_LEFT_EAR = "ContextMenu_HearingAid_EarLeft"

-- Builds the real inventory context menu for the item. Returns it, to hide once done, and the
-- options of its Wear submenu.
local function openWearMenu(item)
    local context = ISInventoryPaneContextMenu.createMenu(0, true, { item }, 300, 300)
    local wear = context:getOptionFromName(getText("ContextMenu_Wear"))
    local options = wear and wear.subOption and context:getSubMenu(wear.subOption).options or {}
    return context, options
end

-- The Wear submenu of the item, for example "on Right Ear, on Left Ear".
local function describeWearMenu(item)
    local context, options = openWearMenu(item)
    local names = {}
    for _, option in ipairs(options) do
        table.insert(names, option.name)
    end
    context:hideAndChildren()
    return table.concat(names, ", ")
end

-- Picks the Wear submenu option with this text key, as a player would. Returns whether it was
-- there.
local function pickWearOption(item, textKey)
    local context, options = openWearMenu(item)
    local picked = false
    for _, option in ipairs(options) do
        if option.name == getText(textKey) then
            option.onSelect(option.target, option.param1, option.param2, option.param3)
            picked = true
        end
    end
    context:hideAndChildren()
    return picked
end

-- Expects the aid of type `swapped` to have become a worn, switched-on `fullType` with this charge.
local function expectSwappedTo(self, fullType, swapped, charge)
    expectAids(self, fullType, 1)
    expectAids(self, swapped, 0)
    local aid = aidsOfType(self, fullType)[1]
    if aid then
        expect(aid.worn, fullType .. " is not worn")
        expectCharge(aid, charge, CHARGE_TOLERANCE)
        expect(aid.on, fullType .. " is off")
    end
end

test("hearingaid_wear_menu_ears", {
    run = function(self)
        giveAids(self, { { type = EFFICIENT }, { type = leftEar(BROKEN), worn = true } })
    end,
    validate = function(self)
        local right, left = getText(ON_RIGHT_EAR), getText(ON_LEFT_EAR)
        local cases = {
            { "unworn", given(self, 1), right .. ", " .. left },
            { "worn on the left ear", given(self, 2), right },
        }
        for _, case in ipairs(cases) do
            local label, aid, expected = case[1], case[2], case[3]
            local actual = describeWearMenu(aid)
            expect(actual == expected, label .. ": Wear menu is \"" .. actual .. "\", expected \"" .. expected .. "\"")
        end
    end,
})

test("hearingaid_wear_switched_on_aid_on_left_ear", {
    run = function(self)
        giveAids(self, { { type = BASIC, charge = 0.5, on = true } })
        T.step(function()
            self.picked = pickWearOption(given(self, 1), ON_LEFT_EAR)
            readState(self)
        end)
    end,
    validate = function(self)
        expect(self.picked, "no Wear > on Left Ear option")
        expectSwappedTo(self, leftEar(BASIC), BASIC, 0.5)
        expectHearing(self, Level.NORMAL)
    end,
})

test("hearingaid_switch_ears_while_worn", {
    sandbox = { BatteryHoursBoosted = 10 },
    periodicUpdate = false,
    run = function(self)
        giveAids(self, { { type = leftEar(BOOSTED), charge = 1, on = true, worn = true } })
        -- The last drain was two hours ago, so the switch bills two of the battery's ten hours.
        T.server(self, "steps", { steps = { { op = "update", at = -2 } } })
        T.step(function()
            self.picked = pickWearOption(given(self, 1), ON_RIGHT_EAR)
            readState(self)
        end)
    end,
    validate = function(self)
        expect(self.picked, "no Wear > on Right Ear option")
        expectSwappedTo(self, BOOSTED, leftEar(BOOSTED), 0.8)
        expectHearing(self, Level.KEEN)
    end,
})
