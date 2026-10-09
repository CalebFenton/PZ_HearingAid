require "Tests/TimedActionsTests"
require "TimedActions/HearingAidAction"
require "TimedActions/ISUnequipAction"
require "TimedActions/ISWearClothing"
require "HearingAid/HearingAidRecipes"
require "HearingAid/Debug/HearingAidDebug"
require "HearingAid/Debug/HearingAidLoot"

-- Tests for the vanilla timed action test runner: Debug menu > Dev > Unit Tests > Timed Actions,
-- in debug mode. The runner calls run(), waits for the action queue to empty, then calls
-- validate(). Before each test it empties the inventory and clears worn items, but it keeps
-- traits, player modData and sandbox options, so test() sets those. Each result is also printed
-- to console.txt as "HearingAidTest PASS <name>" or "HearingAidTest FAIL <name>: <reasons>".

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

-- Battery items store whole uses, about 0.007 of a full charge each, and game time passes while
-- an action runs.
local CHARGE_TOLERANCE = 0.01

local function player()
    return getSpecificPlayer(0)
end

local function hoursNow()
    return getGameTime():getWorldAgeHours()
end

local function addAid(fullType, charge, on)
    return HearingAidDebug.addAid(player(), fullType, charge, on)
end

local function addBattery(charge)
    return HearingAidDebug.addBattery(player(), charge)
end

-- Adds an aid and puts it on at once, without the wear action.
local function wearAid(fullType, charge, on)
    local aid = addAid(fullType, charge, on)
    HearingAidDebug.wear(player(), aid)
    return aid
end

local function queueAidAction(mode, aid, battery)
    ISTimedActionQueue.add(HearingAidAction:new(player(), mode, aid, battery))
end

-- Expectations ---------------------------------------------------------------------------------

-- Unmet expectations of the test being validated.
local failures = {}

local function expect(condition, message)
    if not condition then
        table.insert(failures, message)
    end
end

local function expectHearing(expected)
    local actual = HearingAid.getHearingLevel(player())
    expect(actual == expected, "hearing is " .. LEVEL_NAMES[actual] .. ", expected " .. LEVEL_NAMES[expected])
end

local function expectNear(label, actual, expected, tolerance)
    expect(math.abs(actual - expected) <= (tolerance or 0.0001), label .. " is " .. actual .. ", expected " .. expected)
end

local function expectCharge(aid, expected, tolerance)
    expectNear(aid:getFullType() .. " charge", HearingAid.getCharge(aid), expected, tolerance)
end

local function expectCount(fullType, expected)
    local actual = player():getInventory():getCountType(fullType)
    expect(actual == expected, actual .. " " .. fullType .. " in the inventory, expected " .. expected)
end

-- Expects exactly one battery in the inventory, holding this charge.
local function expectBattery(charge)
    local batteries = player():getInventory():getAllType(BATTERY)
    expectCount(BATTERY, 1)
    if batteries:size() == 1 then
        expectNear("battery charge", batteries:get(0):getCurrentUsesFloat(), charge, CHARGE_TOLERANCE)
    end
end

-- Registers a test with the runner. Before run(), the character's own hearing becomes
-- `spec.hearing` (Hard of Hearing unless set) and the `spec.sandbox` options take effect, along
-- with the recipe skill levels that follow them; validate() restores the options. With
-- `periodicUpdate = false` the every-minute HearingAid.update() stops until validate() ends, so a
-- test can show that an action drains the battery itself.
local function test(name, spec)
    TimedActionTests.getTests()[name] = {
        run = function(self)
            HearingAid.setBaseLevel(player(), spec.hearing or Level.HARD_OF_HEARING)
            self.savedSandbox = {}
            for option, value in pairs(spec.sandbox or {}) do
                self.savedSandbox[option] = SandboxVars.HearingAid[option]
                SandboxVars.HearingAid[option] = value
            end
            HearingAid.Recipes.applySkillLevels()
            if spec.periodicUpdate == false then
                Events.EveryOneMinute.Remove(HearingAid.update)
            end
            if spec.run then
                spec.run(self)
            end
        end,
        validate = function(self)
            failures = {}
            local ok, err = pcall(spec.validate, self)
            for option, value in pairs(self.savedSandbox) do
                SandboxVars.HearingAid[option] = value
            end
            HearingAid.Recipes.applySkillLevels()
            if spec.periodicUpdate == false then
                Events.EveryOneMinute.Add(HearingAid.update)
            end
            if not ok then
                table.insert(failures, tostring(err))
            end
            if #failures > 0 then
                print("HearingAidTest FAIL " .. name .. ": " .. table.concat(failures, "; "))
                return false
            end
            print("HearingAidTest PASS " .. name)
            return true
        end,
    }
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
        self.aid = wearAid(BOOSTED, 1, false)
        queueAidAction(HearingAidAction.TURN_ON, self.aid)
    end,
    validate = function(self)
        expect(HearingAid.isOn(self.aid), "aid is off")
        expectHearing(Level.DEAF)
    end,
})

test("hearingaid_turn_on", {
    run = function(self)
        self.aid = wearAid(BASIC, 1, false)
        queueAidAction(HearingAidAction.TURN_ON, self.aid)
    end,
    validate = function(self)
        expect(HearingAid.isOn(self.aid), "aid is off")
        expectHearing(Level.NORMAL)
    end,
})

test("hearingaid_turn_off", {
    sandbox = { BatteryHoursBasic = 10 },
    periodicUpdate = false,
    run = function(self)
        self.aid = wearAid(BASIC, 1, true)
        self.hearingWhileOn = HearingAid.getHearingLevel(player())
        -- The last drain was two hours ago, so turning off bills two of the battery's ten hours.
        HearingAid.update(hoursNow() - 2)
        queueAidAction(HearingAidAction.TURN_OFF, self.aid)
    end,
    validate = function(self)
        expect(self.hearingWhileOn == Level.NORMAL, "aid didn't help while on")
        expect(not HearingAid.isOn(self.aid), "aid is still on")
        expectCharge(self.aid, 0.8, CHARGE_TOLERANCE)
        expectHearing(Level.HARD_OF_HEARING)
    end,
})

test("hearingaid_wear_switched_on_aid", {
    run = function(self)
        self.aid = addAid(BASIC, 1, true)
        HearingAid.update()
        self.hearingBeforeWearing = HearingAid.getHearingLevel(player())
        ISTimedActionQueue.add(ISWearClothing:new(player(), self.aid))
    end,
    validate = function(self)
        expect(self.hearingBeforeWearing == Level.HARD_OF_HEARING, "aid helped before it was worn")
        expect(self.aid:isWorn(), "aid is not worn")
        expectHearing(Level.NORMAL)
    end,
})

test("hearingaid_take_off_switched_on_aid", {
    run = function(self)
        self.aid = wearAid(BASIC, 1, true)
        self.hearingWhileWorn = HearingAid.getHearingLevel(player())
        ISTimedActionQueue.add(ISUnequipAction:new(player(), self.aid, 50))
    end,
    validate = function(self)
        expect(self.hearingWhileWorn == Level.NORMAL, "aid didn't help while worn")
        expect(not self.aid:isWorn(), "aid is still worn")
        expectHearing(Level.HARD_OF_HEARING)
    end,
})

test("hearingaid_wear_broken_aid_over_working_one", {
    run = function(self)
        self.working = wearAid(BASIC, 1, true)
        self.broken = addAid(BROKEN)
        ISTimedActionQueue.add(ISWearClothing:new(player(), self.broken))
    end,
    validate = function(self)
        expect(self.broken:isWorn(), "broken aid is not worn")
        expect(not self.working:isWorn(), "working aid is still worn")
        expectHearing(Level.HARD_OF_HEARING)
    end,
})

test("hearingaid_keeps_outside_trait_changes", {
    run = function(self)
        self.aid = wearAid(BASIC, 1, true)
        -- An admin gives the character Keen Hearing while the aid is on.
        player():getCharacterTraits():add(CharacterTrait.KEEN_HEARING)
        queueAidAction(HearingAidAction.TURN_OFF, self.aid)
    end,
    validate = function(self)
        expectHearing(Level.KEEN)
    end,
})

-- Batteries ------------------------------------------------------------------------------------

test("hearingaid_insert_battery", {
    run = function(self)
        self.aid = addAid(BASIC)
        queueAidAction(HearingAidAction.INSERT_BATTERY, self.aid, addBattery(0.5))
    end,
    validate = function(self)
        expectCharge(self.aid, 0.5, CHARGE_TOLERANCE)
        expectCount(BATTERY, 0)
        expect(not HearingAid.isOn(self.aid), "aid switched itself on")
    end,
})

test("hearingaid_remove_battery", {
    sandbox = { BatteryHoursBasic = 10 },
    periodicUpdate = false,
    run = function(self)
        self.aid = wearAid(BASIC, 0.5, true)
        -- The last drain was two hours ago, so the battery comes out with 0.5 - 2/10 left.
        HearingAid.update(hoursNow() - 2)
        queueAidAction(HearingAidAction.REMOVE_BATTERY, self.aid)
    end,
    validate = function(self)
        expect(not HearingAid.hasBattery(self.aid), "aid still has a battery")
        expect(not HearingAid.isOn(self.aid), "aid is still on")
        expectBattery(0.3)
        expectHearing(Level.HARD_OF_HEARING)
    end,
})

test("hearingaid_found_battery_chance", {
    sandbox = { SpawnWithBatteryChance = 100 },
    run = function(self)
        local always = instanceItem(BASIC)
        self.alwaysCharge = HearingAid.hasBattery(always) and HearingAid.getCharge(always) or nil
        SandboxVars.HearingAid.SpawnWithBatteryChance = 0
        self.neverHasBattery = HearingAid.hasBattery(instanceItem(BASIC))
    end,
    validate = function(self)
        expect(self.alwaysCharge ~= nil, "no battery at a 100% chance")
        expect(self.alwaysCharge == nil or self.alwaysCharge > 0, "found battery is dead")
        expect(not self.neverHasBattery, "battery at a 0% chance")
    end,
})

test("hearingaid_battery_runs_out", {
    sandbox = { BatteryHoursBasic = 10 },
    run = function(self)
        self.aid = wearAid(BASIC, 0.05, true)
        local now = hoursNow()
        HearingAid.update(now)
        HearingAid.update(now + 1)
    end,
    validate = function(self)
        expectCharge(self.aid, 0)
        expect(HearingAid.hasBattery(self.aid), "dead battery was removed")
        expect(not HearingAid.isOn(self.aid), "aid is still on")
        expectHearing(Level.HARD_OF_HEARING)
    end,
})

test("hearingaid_battery_life_per_tier", {
    sandbox = { BatteryHoursBasic = 8, BatteryHoursEfficient = 16, BatteryHoursBoosted = 4 },
    run = function(self)
        local start = hoursNow()
        self.charges = {}
        for i, fullType in ipairs(WORKING) do
            local aid = wearAid(fullType, 1, true)
            local now = start + 10 * i
            HearingAid.update(now)
            HearingAid.update(now + 2)
            self.charges[fullType] = HearingAid.getCharge(aid)
        end
    end,
    validate = function(self)
        -- Two hours of use on 8, 16 and 4 hour batteries.
        for fullType, expected in pairs({ [BASIC] = 0.75, [EFFICIENT] = 0.875, [BOOSTED] = 0.5 }) do
            expectNear(fullType .. " charge", self.charges[fullType], expected)
        end
    end,
})

test("hearingaid_no_drain_while_inactive", {
    sandbox = { BatteryHoursBasic = 10 },
    run = function(self)
        local aid = wearAid(BASIC, 1, true)
        local now = hoursNow()
        HearingAid.update(now)
        -- Five hours off the ear.
        player():removeWornItem(aid)
        HearingAid.update(now + 5)
        -- Two hours worn but switched off.
        HearingAidDebug.wear(player(), aid)
        HearingAid.setOn(aid, false)
        HearingAid.update(now + 5)
        HearingAid.update(now + 7)
        -- One hour of use, a tenth of the battery.
        HearingAid.setOn(aid, true)
        HearingAid.update(now + 7)
        HearingAid.update(now + 8)
        self.aid = aid
    end,
    validate = function(self)
        expectCharge(self.aid, 0.9)
    end,
})

-- Crafting -------------------------------------------------------------------------------------

local REPAIR = "HearingAid.RepairHearingAid"
local OPTIMIZE = "HearingAid.OptimizeHearingAid"
local BOOST = "HearingAid.BoostHearingAid"
local DISMANTLE = "HearingAid.DismantleHearingAid"

-- Why the right-click menu would refuse to start this craft, or nil if it would start it.
local function craftRefusal(recipe, selectedItem)
    local p = player()
    local logic = HandcraftLogic.new(p, nil, nil)
    logic:setIsoObject(logic:findCraftSurface(p, 2))
    logic:setContainers(ISInventoryPaneContextMenu.getContainers(p))
    logic:setRecipeFromContextClick(recipe, selectedItem)
    if logic:canPerformCurrentRecipe() then
        return nil
    elseif not recipe:characterHasRequiredSkills(p) then
        return "Electrical too low"
    elseif recipe:isAnySurfaceCraft() and not logic:isCharacterInRangeOfWorkbench() then
        return "no table in reach"
    elseif p:tooDarkToRead() then
        return "too dark"
    end
    local missing = {}
    local inputs = recipe:getInputs()
    for i = 0, inputs:size() - 1 do
        if not logic:getRecipeData():getDataForInputScript(inputs:get(i)):isInputItemsSatisfied() then
            table.insert(missing, inputs:get(i):getOriginalLine())
        end
    end
    return "missing " .. table.concat(missing, "; ")
end

-- Registers a test that crafts `spec.recipe` the way the right-click menu does, from a new aid of
-- type `spec.aid` with `spec.charge` and `spec.on`. The character has Electrical `spec.electrical`
-- (8 unless set), every recipe material and a table, and `spec.setup(self)` runs just before the
-- craft. validate() expects the inventory counts in `spec.counts`, then runs `spec.validate(self)`.
-- The menu refuses a craft silently, so a failing test also reports why the game refused.
local function craftTest(name, spec)
    test(name, {
        sandbox = spec.sandbox,
        run = function(self)
            player():setPerkLevelDebug(Perks.Electricity, spec.electrical or 8)
            HearingAidDebug.addRecipeMaterials(player())
            HearingAidDebug.placeWorkTable(player())
            if spec.setup then
                spec.setup(self)
            end
            local recipe = getScriptManager():getCraftRecipe(spec.recipe)
            local aid = addAid(spec.aid, spec.charge, spec.on)
            self.refusal = craftRefusal(recipe, aid)
            ISInventoryPaneContextMenu.OnNewCraft(aid, recipe, player():getPlayerNum(), false)
        end,
        validate = function(self)
            for fullType, count in pairs(spec.counts) do
                expectCount(fullType, count)
            end
            if spec.validate then
                spec.validate(self)
            end
            if #failures > 0 and self.refusal then
                table.insert(failures, "the game refused the craft: " .. self.refusal)
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
        local repaired = player():getInventory():getFirstType(BASIC)
        expect(not (repaired and HearingAid.hasBattery(repaired)), "repair created a battery")
    end,
})

-- People wear their reading glasses for close work, and a worn pair must serve as the magnifier.
craftTest("hearingaid_craft_with_worn_reading_glasses", {
    recipe = REPAIR,
    aid = BROKEN,
    setup = function(self)
        self.glasses = player():getInventory():getFirstType("Base.Glasses_Reading")
        player():setWornItem(self.glasses:getBodyLocation(), self.glasses)
    end,
    counts = { [BASIC] = 1 },
    validate = function(self)
        expect(self.glasses:isWorn(), "reading glasses taken off")
    end,
})

craftTest("hearingaid_craft_upgrade_keeps_battery", {
    sandbox = { SpawnWithBatteryChance = 0 },
    recipe = OPTIMIZE,
    aid = BASIC,
    charge = 0.42,
    on = true,
    counts = { [EFFICIENT] = 1 },
    validate = function(self)
        local upgraded = player():getInventory():getFirstType(EFFICIENT)
        if upgraded then
            expectCharge(upgraded, 0.42)
            expect(HearingAid.isOn(upgraded), "aid was switched off")
        end
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
        local upgraded = player():getInventory():getFirstType(EFFICIENT)
        if upgraded then
            expectCharge(upgraded, 0.42)
            expect(HearingAid.isOn(upgraded), "aid was switched off")
        end
    end,
})

craftTest("hearingaid_craft_dismantle_returns_battery", {
    recipe = DISMANTLE,
    aid = EFFICIENT,
    charge = 0.6,
    counts = { [EFFICIENT] = 0 },
    validate = function(self)
        expectBattery(0.6)
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
        expect(self.refusal == "Electrical too low", "refusal was " .. tostring(self.refusal))
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

-- The bounds are wide enough that sampling noise fails this test less than once in a million runs.
test("hearingaid_corpse_loot", {
    run = function(self)
        self.ordinary = HearingAidLoot.measureZombies("ordinary", 12000)
        self.retirees = HearingAidLoot.measureZombies("retirees", 1000)
    end,
    validate = function(self)
        local ordinary, retirees = self.ordinary, self.retirees
        print(string.format("HearingAidTest INFO ordinary corpses: %.2f%% wristwatch, %.2f%% broken aid, %.2f%% working aid,"
            .. " %.2f%% any aid; retirees: %.2f%% any aid", ordinary.watch * 100, ordinary.broken * 100,
            ordinary.working * 100, ordinary.any * 100, retirees.any * 100))
        expect(ordinary.broken >= ordinary.watch / 8 and ordinary.broken <= ordinary.watch / 4.8,
            "broken aids on ordinary corpses not 4.8 to 8 times rarer than wristwatches")
        expect(ordinary.working >= ordinary.watch / 14 and ordinary.working <= ordinary.watch / 7.5,
            "working aids on ordinary corpses not 7.5 to 14 times rarer than wristwatches")
        expect(retirees.any >= 2 * ordinary.any, "retirees less than twice as likely as ordinary corpses to carry an aid")
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
        self.withoutBattery = addAid(BASIC)
        self.off = addAid(EFFICIENT, 0.5, false)
        self.on = addAid(BOOSTED, 0.5, true)
        self.dead = addAid(BASIC, 0, false)
        self.broken = addAid(BROKEN)
        self.batteryName = addBattery(0.25):getDisplayName()
        addBattery(0.75)
        addBattery(0)
    end,
    validate = function(self)
        local battery = self.batteryName
        local cases = {
            { "no battery", self.withoutBattery, "AddBattery[" .. battery .. " (75%), " .. battery .. " (25%)]" },
            { "switched off", self.off, "TurnOn, RemoveBattery" },
            { "switched on", self.on, "TurnOff, RemoveBattery" },
            { "dead battery", self.dead, "TurnOn(disabled), RemoveBattery" },
            { "broken", self.broken, "" },
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
local function expectSwappedTo(fullType, swapped, charge)
    expectCount(fullType, 1)
    expectCount(swapped, 0)
    local aid = player():getInventory():getFirstType(fullType)
    if aid then
        expect(aid:isWorn(), fullType .. " is not worn")
        expectCharge(aid, charge, CHARGE_TOLERANCE)
        expect(HearingAid.isOn(aid), fullType .. " is off")
    end
end

test("hearingaid_wear_menu_ears", {
    run = function(self)
        self.unworn = addAid(EFFICIENT)
        self.wornLeft = wearAid(leftEar(BROKEN))
    end,
    validate = function(self)
        local right, left = getText(ON_RIGHT_EAR), getText(ON_LEFT_EAR)
        expect(right ~= ON_RIGHT_EAR, ON_RIGHT_EAR .. " has no text")
        expect(left ~= ON_LEFT_EAR, ON_LEFT_EAR .. " has no text")
        local cases = {
            { "unworn", self.unworn, right .. ", " .. left },
            { "worn on the left ear", self.wornLeft, right },
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
        local aid = addAid(BASIC, 0.5, true)
        self.picked = pickWearOption(aid, ON_LEFT_EAR)
    end,
    validate = function(self)
        expect(self.picked, "no Wear > on Left Ear option")
        expectSwappedTo(leftEar(BASIC), BASIC, 0.5)
        expectHearing(Level.NORMAL)
    end,
})

test("hearingaid_switch_ears_while_worn", {
    sandbox = { BatteryHoursBoosted = 10 },
    periodicUpdate = false,
    run = function(self)
        local aid = wearAid(leftEar(BOOSTED), 1, true)
        -- The last drain was two hours ago, so the switch bills two of the battery's ten hours.
        HearingAid.update(hoursNow() - 2)
        self.picked = pickWearOption(aid, ON_RIGHT_EAR)
    end,
    validate = function(self)
        expect(self.picked, "no Wear > on Right Ear option")
        expectSwappedTo(BOOSTED, leftEar(BOOSTED), 0.8)
        expectHearing(Level.KEEN)
    end,
})
