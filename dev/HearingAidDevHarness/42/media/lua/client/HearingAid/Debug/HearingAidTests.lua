require "PZHarness/TestCraft"
require "PZHarness/TestMenus"
require "HearingAid/HearingAid"
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
-- through the right-click menus on this client, check the server's state, and then expect this
-- client to show the same (expectClientAgrees). Everything a test does to the game is queued, so
-- it happens in order once the server has answered.

HearingAidTests = HearingAidTests or {}

local T = PZHarness.Test
local player, expect, expectNear, expectEqual = T.player, T.expect, T.expectNear, T.expectEqual

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
-- Its waits end there without failing; validate checks what they waited for.
local SYNC_MS = 5000

-- The battery life, in hours, that the drain tests give a tier, and the hours of use they bill:
-- a battery loses USED / LIFE of a full charge over them.
local LIFE, USED = 10, 2

local ON_RIGHT_EAR = "ContextMenu_HearingAid_EarRight"
local ON_LEFT_EAR = "ContextMenu_HearingAid_EarLeft"

local function levelName(level)
    return LEVEL_NAMES[level] or tostring(level)
end

-- The settings' setup (HearingAidTestSettings.lua). Traits and player modData carry over from the
-- test before, so every test starts from the character's own hearing `spec.hearing`, Hard of
-- Hearing unless set; the "hearing" handler applies it and `spec.periodicUpdate`.
function HearingAidTests.setup(self, spec)
    local level = spec.hearing or Level.HARD_OF_HEARING
    T.server(self, "hearing", { level = level, periodicUpdate = spec.periodicUpdate })
    T.waitUntil(function() return HearingAid.getHearingLevel(player()) == level end, SYNC_MS, "this client's hearing level")
end

-- Gives the character hearing aids and batteries the way the server does: each item { type,
-- charge, on, worn } (see giveAids in HearingAidTestServer.lua). This client's copies land in
-- self.items.giveAids, in order.
local function giveAids(self, items)
    T.server(self, "giveAids", { items = items })
end

-- This client's copy of the i-th item giveAids gave.
local function given(self, i)
    return self.items.giveAids[i]
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
    T.waitUntil(function()
        self.state = self.server[handler]
        return #disagreements(self.state) == 0
    end, SYNC_MS, "this client agreeing with the server's state")
end

-- readState, keeping the hearing it read as self.hearingBefore: the level before the action under
-- test, which expectHearingChange checks, so that an aid that never helped can't pass for one
-- that stopped helping.
local function readStateBefore(self, handler, args)
    readState(self, handler, args)
    T.step(function()
        self.hearingBefore = self.state.hearing
    end)
end

-- Runs the periodic update `hours` ago and reads the state before the action under test: the
-- worn, switched-on aids are billed from then, so the next drain bills those hours of use.
local function backdateDrain(self, hours)
    readStateBefore(self, "steps", { steps = { { op = "update", at = -hours } } })
end

-- Menus ----------------------------------------------------------------------------------------

-- A `find` for pickAndRead: the option with the text of `textKey`, in the submenu of the option
-- with the text of `submenuKey` when given. Also returns the option's name for a failure.
local function option(textKey, submenuKey)
    return function(context)
        local menu = context
        local label = getText(textKey)
        if submenuKey then
            menu = T.subMenu(context, T.optionNamed(context, getText(submenuKey)))
            label = getText(submenuKey) .. " > " .. label
        end
        return T.optionNamed(menu, getText(textKey)), label
    end
end

-- A `find` for pickAndRead: Add Battery's choice of the i-th item giveAids gave.
local function batteryChoice(self, i)
    return function(context)
        local add = T.optionNamed(context, getText("ContextMenu_AddBattery"))
        return T.optionFor(T.subMenu(context, add), given(self, i)), getText("ContextMenu_AddBattery") .. " > battery " .. i
    end
end

-- Queues a right-click on the i-th item giveAids gave, a click on the option `find(context)`
-- finds, as a player's, and a read of the server's state. An option the menu doesn't offer fails
-- the test, naming it.
local function pickAndRead(self, aidIndex, find)
    T.step(function()
        local context = T.need(self, T.inventoryMenu(given(self, aidIndex)), "a context menu for the aid")
        if not context then
            return
        end
        local choice, label = find(context)
        local offered = T.need(self, T.offered(choice), "an offered " .. label .. " option")
        if offered then
            T.choose(choice)
        end
        context:hideAndChildren()
        if offered then
            readState(self)
        end
    end)
end

-- Queues putting on the i-th item giveAids gave as a double-click in the inventory does
-- (ISInventoryPane:doContextualDblClick), through ISWearClothing, and a read of the server's state.
-- The Wear menu's ear options swap the item through ISClothingExtraAction instead.
local function doubleClickAndRead(self, i)
    T.step(function()
        ISInventoryPaneContextMenu.onWearItems({ given(self, i) }, player():getPlayerNum())
        readState(self)
    end)
end

-- Expectations ---------------------------------------------------------------------------------

local NO_STATE = { aids = {}, batteries = {} }

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
    expectEqual("hearing", levelName(stateOf(self).hearing), levelName(expected))
end

-- Expects the hearing to have been `before` when readStateBefore read it and `after` now.
local function expectHearingChange(self, before, after)
    expectEqual("hearing before", levelName(self.hearingBefore), levelName(before))
    expectHearing(self, after)
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
    expectEqual(fullType .. " in the inventory", #aidsOfType(self, fullType), expected)
end

-- Expects the server's inventory to hold exactly one battery with this charge, or none if nil.
local function expectBattery(self, charge)
    local batteries = stateOf(self).batteries
    expectEqual("batteries in the inventory", #batteries, charge and 1 or 0)
    if charge and #batteries == 1 then
        expectNear("battery charge", batteries[1], charge, CHARGE_TOLERANCE)
    end
end

local function expectClientAgrees(self)
    for _, problem in ipairs(disagreements(self.state)) do
        expect(false, problem)
    end
end

-- `validate` (if any), then, for a test that read the server's state, the expectation that this
-- client shows the same.
local function withClientCheck(validate)
    return function(self)
        if validate then
            validate(self)
        end
        if self.state then
            expectClientAgrees(self)
        end
    end
end

-- Registers a test. Its timed actions finish in one tick unless `spec.instant` is false: the tests
-- check what an action does, not how long it takes.
local function test(name, spec)
    if spec.instant == nil then
        spec.instant = true
    end
    spec.validate = withClientCheck(spec.validate)
    T.test(name, spec)
end

-- Hearing --------------------------------------------------------------------------------------

-- The README's table, the players' contract: the level an active aid of each tier gives a
-- character by their own hearing, and a deaf one by the HandleDeafness option.
local BASIC_GIVES = {
    hearing = { [Level.HARD_OF_HEARING] = Level.NORMAL, [Level.NORMAL] = Level.NORMAL, [Level.KEEN] = Level.KEEN },
    deaf = { [Mode.NONE] = Level.DEAF, [Mode.ALL_AIDS] = Level.HARD_OF_HEARING, [Mode.BOOSTED_ONLY] = Level.DEAF },
}
local GIVES = {
    [BASIC] = BASIC_GIVES,
    -- Efficient differs from Basic only in battery life.
    [EFFICIENT] = BASIC_GIVES,
    [BOOSTED] = {
        hearing = { [Level.HARD_OF_HEARING] = Level.KEEN, [Level.NORMAL] = Level.KEEN, [Level.KEEN] = Level.KEEN },
        deaf = { [Mode.NONE] = Level.DEAF, [Mode.ALL_AIDS] = Level.NORMAL, [Mode.BOOSTED_ONLY] = Level.HARD_OF_HEARING },
    },
}

-- Every cell, on the rule itself, for either ear's aid; the tests below show that wearing and
-- switching an aid applies it.
test("hearingaid_hearing_levels", {
    validate = function(self)
        for tier, gives in pairs(GIVES) do
            for _, fullType in ipairs({ tier, leftEar(tier) }) do
                for _, mode in pairs(Mode) do
                    local function check(own, expected)
                        expectEqual(fullType .. ", HandleDeafness " .. mode .. ", " .. levelName(own),
                            levelName(HearingAid.getTargetLevel(own, fullType, mode)), levelName(expected))
                    end
                    check(Level.DEAF, gives.deaf[mode])
                    for own, expected in pairs(gives.hearing) do
                        check(own, expected)
                    end
                end
            end
        end
    end,
})

-- The worn aid reads the option: under None a Boosted aid, which helps a deaf character under the
-- other modes, switches on and leaves them deaf.
test("hearingaid_handle_deafness_none_keeps_deaf", {
    hearing = Level.DEAF,
    sandbox = { HandleDeafness = Mode.NONE },
    run = function(self)
        giveAids(self, { { type = BOOSTED, charge = 1, worn = true } })
        pickAndRead(self, 1, option("ContextMenu_Turn_On"))
    end,
    validate = function(self)
        expect(givenState(self, 1).on, "aid is off")
        expectHearing(self, Level.DEAF)
    end,
})

test("hearingaid_turn_on", {
    run = function(self)
        giveAids(self, { { type = BASIC, charge = 1, worn = true } })
        pickAndRead(self, 1, option("ContextMenu_Turn_On"))
    end,
    validate = function(self)
        expect(givenState(self, 1).on, "aid is off")
        expectHearing(self, Level.NORMAL)
    end,
})

-- Switching off bills the use since the last periodic update.
test("hearingaid_turn_off", {
    sandbox = { BatteryHoursBasic = LIFE },
    periodicUpdate = false,
    run = function(self)
        giveAids(self, { { type = BASIC, charge = 1, on = true, worn = true } })
        backdateDrain(self, USED)
        pickAndRead(self, 1, option("ContextMenu_Turn_Off"))
    end,
    validate = function(self)
        local aid = givenState(self, 1)
        expect(not aid.on, "aid is still on")
        expectCharge(aid, 1 - USED / LIFE, CHARGE_TOLERANCE)
        expectHearingChange(self, Level.NORMAL, Level.HARD_OF_HEARING)
    end,
})

test("hearingaid_wear_switched_on_aid", {
    run = function(self)
        giveAids(self, { { type = BASIC, charge = 1, on = true } })
        -- A periodic update first: off the ear the aid must not help.
        readStateBefore(self, "steps", { steps = { { op = "update", at = 0 } } })
        doubleClickAndRead(self, 1)
    end,
    validate = function(self)
        expect(givenState(self, 1).worn, "aid is not worn")
        expectHearingChange(self, Level.HARD_OF_HEARING, Level.NORMAL)
    end,
})

-- Taking the aid off bills the use since the last periodic update.
test("hearingaid_take_off_switched_on_aid", {
    sandbox = { BatteryHoursBasic = LIFE },
    periodicUpdate = false,
    run = function(self)
        giveAids(self, { { type = BASIC, charge = 1, on = true, worn = true } })
        backdateDrain(self, USED)
        pickAndRead(self, 1, option("ContextMenu_Unequip"))
    end,
    validate = function(self)
        local aid = givenState(self, 1)
        expect(not aid.worn, "aid is still worn")
        expectCharge(aid, 1 - USED / LIFE, CHARGE_TOLERANCE)
        expectHearingChange(self, Level.NORMAL, Level.HARD_OF_HEARING)
    end,
})

-- A broken aid put on the ear takes the place of the working one, which stops helping and is
-- billed for its use since the last periodic update.
test("hearingaid_wear_broken_aid_over_working_one", {
    sandbox = { BatteryHoursBasic = LIFE },
    periodicUpdate = false,
    run = function(self)
        giveAids(self, { { type = BASIC, charge = 1, on = true, worn = true }, { type = BROKEN } })
        backdateDrain(self, USED)
        doubleClickAndRead(self, 2)
    end,
    validate = function(self)
        local working = givenState(self, 1)
        expect(givenState(self, 2).worn, "broken aid is not worn")
        expect(not working.worn, "working aid is still worn")
        expectCharge(working, 1 - USED / LIFE, CHARGE_TOLERANCE)
        expectHearingChange(self, Level.NORMAL, Level.HARD_OF_HEARING)
    end,
})

-- An admin, or another mod, gives the character Keen Hearing while the aid is on: switched off,
-- the aid leaves them that rather than the level they had before it.
test("hearingaid_keeps_outside_trait_changes", {
    run = function(self)
        giveAids(self, { { type = BASIC, charge = 1, on = true, worn = true } })
        readStateBefore(self)
        T.server(self, "keenHearing")
        pickAndRead(self, 1, option("ContextMenu_Turn_Off"))
    end,
    validate = function(self)
        expectHearingChange(self, Level.NORMAL, Level.KEEN)
    end,
})

-- Batteries ------------------------------------------------------------------------------------

test("hearingaid_insert_battery", {
    run = function(self)
        giveAids(self, { { type = BASIC }, { type = BATTERY, charge = 0.5 } })
        pickAndRead(self, 1, batteryChoice(self, 2))
    end,
    validate = function(self)
        local aid = givenState(self, 1)
        expectCharge(aid, 0.5, CHARGE_TOLERANCE)
        expectBattery(self, nil)
        expect(not aid.on, "aid switched itself on")
    end,
})

-- Taking the battery out bills the use since the last periodic update and switches the aid off.
test("hearingaid_remove_battery", {
    sandbox = { BatteryHoursBasic = LIFE },
    periodicUpdate = false,
    run = function(self)
        giveAids(self, { { type = BASIC, charge = 0.5, on = true, worn = true } })
        backdateDrain(self, USED)
        pickAndRead(self, 1, option("ContextMenu_Remove_Battery"))
    end,
    validate = function(self)
        local aid = givenState(self, 1)
        expect(not aid.battery, "aid still has a battery")
        expect(not aid.on, "aid is still on")
        expectBattery(self, 0.5 - USED / LIFE)
        expectHearingChange(self, Level.NORMAL, Level.HARD_OF_HEARING)
    end,
})

-- A found aid holds a battery on a roll just under the found-battery chance and none at it; the
-- lowest charge roll still leaves the battery some charge. Not the option's default, so a chance
-- read from anywhere else fails.
local FOUND_BATTERY_PERCENT = 30

test("hearingaid_found_battery_chance", {
    sandbox = { SpawnWithBatteryChance = FOUND_BATTERY_PERCENT },
    run = function(self)
        local chance = FOUND_BATTERY_PERCENT / 100
        T.forceRoll(self, { chance - T.UNDER, 0 })
        T.server(self, "instantiate", { type = BASIC })
        T.step(function()
            self.under = self.server.instantiate
            T.forceRoll(self, { chance })
            T.server(self, "instantiate", { type = BASIC })
        end)
    end,
    validate = function(self)
        local under, at = self.under or {}, self.server.instantiate or {}
        if expect(under.battery, "no battery on a roll just under the chance") then
            expect(under.charge > 0, "the found battery is dead")
        end
        expect(not at.battery, "a battery on a roll at the chance")
    end,
})

-- The tests below move time on through HearingAidTestServer.lua's steps, all in one go on the
-- server, so the periodic update stays out of the way.

test("hearingaid_battery_runs_out", {
    sandbox = { BatteryHoursBasic = LIFE },
    periodicUpdate = false,
    run = function(self)
        -- Half the charge the span uses.
        giveAids(self, { { type = BASIC, charge = USED / LIFE / 2, on = true, worn = true } })
        readState(self, "steps", { steps = { { op = "update", at = 0 }, { op = "update", at = USED } } })
    end,
    validate = function(self)
        local aid = givenState(self, 1)
        expectCharge(aid, 0)
        expect(aid.battery, "dead battery was removed")
        expect(not aid.on, "aid is still on")
        expectHearing(self, Level.HARD_OF_HEARING)
    end,
})

-- Distinct lives, so a tier that read another's option fails.
local TIER_LIFE = { [BASIC] = 8, [EFFICIENT] = 16, [BOOSTED] = 4 }

test("hearingaid_battery_life_per_tier", {
    sandbox = {
        BatteryHoursBasic = TIER_LIFE[BASIC],
        BatteryHoursEfficient = TIER_LIFE[EFFICIENT],
        BatteryHoursBoosted = TIER_LIFE[BOOSTED],
    },
    periodicUpdate = false,
    run = function(self)
        local aids = {}
        for _, fullType in ipairs(WORKING) do
            table.insert(aids, { type = fullType, charge = 1, on = true })
        end
        giveAids(self, aids)
        -- Each tier in turn worn and on for the same span, with unbilled time off the ear between.
        readState(self, "steps", function()
            local steps = {}
            for i in ipairs(WORKING) do
                table.insert(steps, { op = "wear", id = given(self, i):getID() })
                table.insert(steps, { op = "update", at = 10 * i })
                table.insert(steps, { op = "update", at = 10 * i + USED })
            end
            return { steps = steps }
        end)
    end,
    validate = function(self)
        for i, fullType in ipairs(WORKING) do
            expectCharge(givenState(self, i), 1 - USED / TIER_LIFE[fullType])
        end
    end,
})

test("hearingaid_no_drain_while_inactive", {
    sandbox = { BatteryHoursBasic = LIFE },
    periodicUpdate = false,
    run = function(self)
        giveAids(self, { { type = BASIC, charge = 1, on = true, worn = true } })
        readState(self, "steps", function()
            local id = given(self, 1):getID()
            return { steps = {
                { op = "update", at = 0 },
                -- Off the ear.
                { op = "takeOff", id = id },
                { op = "update", at = 5 },
                -- Worn but switched off.
                { op = "wear", id = id },
                { op = "switch", id = id, on = false },
                { op = "update", at = 5 },
                { op = "update", at = 7 },
                -- In use: the only span billed.
                { op = "switch", id = id, on = true },
                { op = "update", at = 7 },
                { op = "update", at = 7 + USED },
            } }
        end)
    end,
    validate = function(self)
        expectCharge(givenState(self, 1), 1 - USED / LIFE)
    end,
})

-- Crafting -------------------------------------------------------------------------------------

local REPAIR = "HearingAid.RepairHearingAid"
local OPTIMIZE = "HearingAid.OptimizeHearingAid"
local BOOST = "HearingAid.BoostHearingAid"
local DISMANTLE = "HearingAid.DismantleHearingAid"

local function setOptions(self, options)
    for key, value in pairs(options) do
        T.setSandbox(self, key, value)
    end
end

local function describeOptions(options)
    local parts = {}
    for key, value in pairs(options) do
        table.insert(parts, key .. " = " .. tostring(value))
    end
    return table.concat(parts, ", ")
end

-- With each of spec.refusedWith's options set in turn, asks the game whether it would start the
-- craft from the aid, as a right-click would, then puts the test's options back. The answers land
-- in self.refusals, false where the game would start it.
local function askRefusals(self, spec)
    local recipe = getScriptManager():getCraftRecipe(spec.recipe)
    local options = SandboxVars.HearingAid
    self.refusals = {}
    for i, case in ipairs(spec.refusedWith) do
        local before = {}
        for key in pairs(case.sandbox) do
            before[key] = options[key]
        end
        setOptions(self, case.sandbox)
        self.refusals[i] = T.craftRefusal(recipe, given(self, 1)) or false
        setOptions(self, before)
    end
end

local function expectRefusals(self, spec)
    for i, case in ipairs(spec.refusedWith or {}) do
        local refusal = self.refusals and self.refusals[i]
        if expect(refusal, "the game would start the craft with " .. describeOptions(case.sandbox)) and case.reason then
            expect(refusal:find(case.reason, 1, true), "refused for another reason: " .. refusal)
        end
    end
end

-- Adds hearing-aid fixtures and synchronized state assertions to the shared craft lifecycle.
-- Preparation stays explicit: aids need authority-owned battery and switch state rather than
-- ordinary recipe inputs, and the Electrical level is the test's (`spec.electrical`), not the
-- recipe's. `spec.refusedWith` is a list of { sandbox = options, reason }: with each one's options
-- set, before the craft, the game must refuse it, for `reason` when given; the craft then runs
-- with the test's own options, so one craft checks both sides of an option.
local function craftTest(name, spec)
    T.craftTest(name, {
        sandbox = spec.sandbox,
        recipe = spec.recipe,
        from = spec.aid,
        counts = spec.counts,
        instant = true,
        dropped = false,
        prepare = function(self)
            T.setPerk(self, Perks.Electricity, spec.electrical or Debug.ELECTRICAL_LEVEL)
            T.give(self, "materials", Debug.RECIPE_MATERIALS)
            giveAids(self, { { type = spec.aid, charge = spec.charge, on = spec.on } })
        end,
        setup = spec.refusedWith and function(self) askRefusals(self, spec) end,
        after = readState,
        validate = withClientCheck(function(self)
            expectRefusals(self, spec)
            if spec.validate then
                spec.validate(self)
            end
        end),
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

-- The optimized aid keeps the battery and switch of the aid it was made from, a left-ear one here,
-- which the recipe's callback must find among the inputs as well. Found aids hold no battery at
-- this chance, so the output's charge can only come from the input.
local UPGRADE_CHARGE = 0.42

craftTest("hearingaid_craft_upgrade_keeps_battery", {
    sandbox = { SpawnWithBatteryChance = 0 },
    recipe = OPTIMIZE,
    aid = leftEar(BASIC),
    charge = UPGRADE_CHARGE,
    on = true,
    counts = { [EFFICIENT] = 1, [leftEar(BASIC)] = 0 },
    validate = function(self)
        local upgraded = aidsOfType(self, EFFICIENT)[1]
        if upgraded then
            expectCharge(upgraded, UPGRADE_CHARGE)
            expect(upgraded.on, "aid was switched off")
        end
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

craftTest("hearingaid_craft_boost_only_when_enabled", {
    sandbox = { EnableBoosted = true },
    refusedWith = { { sandbox = { EnableBoosted = false } } },
    recipe = BOOST,
    aid = EFFICIENT,
    counts = { [BOOSTED] = 1, [EFFICIENT] = 0 },
})

-- The recipe asks for the Electrical level its option sets, and 0 drops the requirement, on the
-- server too: refused at Electrical 0 while the option asks for 1, crafted once it is 0.
craftTest("hearingaid_craft_skill_level_from_sandbox", {
    sandbox = { RepairSkillLevel = 0 },
    refusedWith = { { sandbox = { RepairSkillLevel = 1 }, reason = "skills too low" } },
    electrical = 0,
    recipe = REPAIR,
    aid = BROKEN,
    counts = { [BASIC] = 1 },
})

-- Context menu ---------------------------------------------------------------------------------

local MENU_OPTIONS = {
    { name = "AddBattery", textKey = "ContextMenu_AddBattery" },
    { name = "TurnOn", textKey = "ContextMenu_Turn_On" },
    { name = "TurnOff", textKey = "ContextMenu_Turn_Off" },
    { name = "RemoveBattery", textKey = "ContextMenu_Remove_Battery" },
}

-- "battery <i>" for the i-th item giveAids gave, which a menu option acts on.
local function nameGiven(self, item)
    for i, gave in ipairs(self.items.giveAids) do
        if instanceof(item, "InventoryItem") and gave:getID() == item:getID() then
            return "battery " .. i
        end
    end
    return tostring(item)
end

-- Builds the real inventory context menu for the item and lists its hearing aid options, for
-- example "TurnOn(disabled), RemoveBattery" or "AddBattery[battery 7, battery 6]", naming each
-- battery Add Battery offers by nameGiven.
local function describeMenu(self, item)
    local context = T.inventoryMenu(item)
    if not context then
        return "no menu"
    end
    local found = {}
    for _, entry in ipairs(MENU_OPTIONS) do
        local option = T.optionNamed(context, getText(entry.textKey))
        if option then
            local text = entry.name
            if option.notAvailable then
                text = text .. "(disabled)"
            end
            local choices = T.subMenu(context, option)
            if choices then
                local batteries = {}
                for _, choice in ipairs(choices.options) do
                    table.insert(batteries, nameGiven(self, choice.param3))
                end
                text = text .. "[" .. table.concat(batteries, ", ") .. "]"
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
        local cases = {
            -- Fullest first.
            { "no battery", given(self, 1), "AddBattery[battery 7, battery 6]" },
            { "switched off", given(self, 2), "TurnOn, RemoveBattery" },
            { "switched on", given(self, 3), "TurnOff, RemoveBattery" },
            { "dead battery", given(self, 4), "TurnOn(disabled), RemoveBattery" },
            { "broken", given(self, 5), "" },
        }
        for _, case in ipairs(cases) do
            local label, aid, expected = case[1], case[2], case[3]
            expectEqual(label .. ": the menu", describeMenu(self, aid), expected)
        end
    end,
})

-- Ears -----------------------------------------------------------------------------------------

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

-- Wear > on Right Ear on a right-ear aid also replaces it with a new item, of the same type. It
-- keeps the aid's battery and switch, not what the new item's OnCreate rolled: at this chance that
-- is always a battery, switched off.
test("hearingaid_wear_switched_on_aid_on_right_ear", {
    sandbox = { SpawnWithBatteryChance = 100 },
    run = function(self)
        giveAids(self, { { type = BASIC, charge = 0.5, on = true } })
        pickAndRead(self, 1, option(ON_RIGHT_EAR, "ContextMenu_Wear"))
    end,
    validate = function(self)
        expectAids(self, BASIC, 1)
        local aid = aidsOfType(self, BASIC)[1]
        if aid then
            expect(aid.worn, "aid is not worn")
            expectCharge(aid, 0.5, CHARGE_TOLERANCE)
            expect(aid.on, "aid is off")
        end
        expectHearing(self, Level.NORMAL)
    end,
})

-- Wear > on Left Ear swaps the aid for its left-ear twin, which keeps its battery and switch.
test("hearingaid_wear_switched_on_aid_on_left_ear", {
    run = function(self)
        giveAids(self, { { type = BASIC, charge = 0.5, on = true } })
        pickAndRead(self, 1, option(ON_LEFT_EAR, "ContextMenu_Wear"))
    end,
    validate = function(self)
        expectSwappedTo(self, leftEar(BASIC), BASIC, 0.5)
        expectHearing(self, Level.NORMAL)
    end,
})

-- Swapping ears bills the old item's use, and the twin's from the swap on, so the next update
-- bills the hours since the swap.
test("hearingaid_switch_ears_while_worn", {
    sandbox = { BatteryHoursBoosted = LIFE },
    periodicUpdate = false,
    run = function(self)
        giveAids(self, { { type = leftEar(BOOSTED), charge = 1, on = true, worn = true } })
        backdateDrain(self, USED)
        pickAndRead(self, 1, option(ON_RIGHT_EAR, "ContextMenu_Wear"))
        T.step(function()
            self.swapped = self.state
            readState(self, "steps", { steps = { { op = "update", at = USED } } })
        end)
    end,
    validate = function(self)
        local afterUpdate = self.state
        self.state = self.swapped
        expectSwappedTo(self, BOOSTED, leftEar(BOOSTED), 1 - USED / LIFE)
        self.state = afterUpdate
        expectSwappedTo(self, BOOSTED, leftEar(BOOSTED), 1 - 2 * USED / LIFE)
        expectHearingChange(self, Level.KEEN, Level.KEEN)
    end,
})
