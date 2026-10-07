require "Tests/TimedActionsTests"
require "TimedActions/HearingAidAction"
require "TimedActions/ISUnequipAction"
require "TimedActions/ISWearClothing"
require "HearingAid/HearingAidRecipes"
require "HearingAid/Debug/HearingAidDebug"

-- Tests for the vanilla timed action test runner: Debug menu > Dev > Unit Tests > Timed Actions,
-- in debug mode. Before each test the runner empties the inventory and clears worn items, but it
-- keeps traits and player modData, so every test sets the hearing it starts from. The runner calls
-- run(), waits for the action queue to empty, then calls validate(). Each result is also printed
-- to console.txt as "HearingAidTest PASS <name>" or "HearingAidTest FAIL <name>: <reasons>".

local Level = HearingAid.Level
local Mode = HearingAid.DeafnessMode
local BASIC, EFFICIENT, BOOSTED, BROKEN = HearingAid.BASIC, HearingAid.EFFICIENT, HearingAid.BOOSTED, HearingAid.BROKEN

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

local function near(actual, expected, tolerance)
    return math.abs(actual - expected) <= (tolerance or 0.0001)
end

local function hoursNow()
    return getGameTime():getWorldAgeHours()
end

local function queueAidAction(mode, aid, battery)
    ISTimedActionQueue.add(HearingAidAction:new(player(), mode, aid, battery))
end

-- An aid that is worn, switched on and already changing hearing.
local function wearActiveAid(fullType, charge)
    local aid = HearingAidDebug.addAid(player(), fullType, charge or 1, true)
    HearingAidDebug.wear(player(), aid)
    return aid
end

local function expectHearing(expect, expected)
    local actual = HearingAid.getHearingLevel(player())
    expect(actual == expected, "hearing is " .. LEVEL_NAMES[actual] .. ", expected " .. LEVEL_NAMES[expected])
end

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

-- Crafts through the same path as the right-click menu. Returns why the game refused, if it did.
local function craft(recipeName, selectedItem)
    local recipe = getScriptManager():getCraftRecipe(recipeName)
    local refusal = craftRefusal(recipe, selectedItem)
    ISInventoryPaneContextMenu.OnNewCraft(selectedItem, recipe, player():getPlayerNum(), false)
    return refusal
end

-- Appends the reason a craft was refused to a failure message.
local function refused(self)
    return self.refusal and " (refused: " .. self.refusal .. ")" or ""
end

-- Registers a test with the runner. `sandbox` options hold from run() until validate() ends, and
-- recipe skill levels follow them at once rather than at the next game minute. With
-- `periodicUpdate = false` the every-minute HearingAid.update() stops for that time, so a test can
-- show that an action drains the battery itself. validate(self, expect) reports each unmet
-- requirement with expect(condition, message).
local function test(name, spec)
    TimedActionTests.getTests()[name] = {
        run = function(self)
            self.savedSandbox = {}
            for option, value in pairs(spec.sandbox or {}) do
                self.savedSandbox[option] = SandboxVars.HearingAid[option]
                SandboxVars.HearingAid[option] = value
            end
            HearingAid.Recipes.applySkillLevels()
            if spec.periodicUpdate == false then
                Events.EveryOneMinute.Remove(HearingAid.update)
            end
            spec.run(self)
        end,
        validate = function(self)
            local failures = {}
            local ok, err = pcall(spec.validate, self, function(condition, message)
                if not condition then
                    table.insert(failures, message)
                end
            end)
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

-- What each tier (basic, efficient, boosted) gives a character with this own hearing level.
local HEARING_WITH_AID = {
    [Level.HARD_OF_HEARING] = { Level.NORMAL, Level.NORMAL, Level.KEEN },
    [Level.NORMAL] = { Level.NORMAL, Level.NORMAL, Level.KEEN },
    [Level.KEEN] = { Level.KEEN, Level.KEEN, Level.KEEN },
}
-- What each tier gives a deaf character, per HandleDeafness option.
local DEAF_WITH_AID = {
    [Mode.NONE] = { Level.DEAF, Level.DEAF, Level.DEAF },
    [Mode.ALL_AIDS] = { Level.HARD_OF_HEARING, Level.HARD_OF_HEARING, Level.NORMAL },
    [Mode.BOOSTED_ONLY] = { Level.DEAF, Level.DEAF, Level.HARD_OF_HEARING },
}

local function expectedLevels(mode)
    local levels = { [Level.DEAF] = DEAF_WITH_AID[mode] }
    for base, row in pairs(HEARING_WITH_AID) do
        levels[base] = row
    end
    return levels
end

test("hearingaid_hearing_levels", {
    run = function(self) end,
    validate = function(self, expect)
        for mode in pairs(DEAF_WITH_AID) do
            for base, row in pairs(expectedLevels(mode)) do
                for i, fullType in ipairs({ BASIC, EFFICIENT, BOOSTED }) do
                    local actual = HearingAid.getTargetLevel(base, fullType, mode)
                    expect(actual == row[i], "HandleDeafness " .. mode .. ", " .. LEVEL_NAMES[base] .. ", " .. fullType
                        .. ": got " .. tostring(LEVEL_NAMES[actual]) .. ", expected " .. LEVEL_NAMES[row[i]])
                end
            end
        end
    end,
})

test("hearingaid_handle_deafness_option", {
    sandbox = { HandleDeafness = Mode.NONE },
    run = function(self)
        HearingAid.setBaseLevel(player(), Level.DEAF)
        self.aid = HearingAidDebug.addAid(player(), BOOSTED, 1, false)
        HearingAidDebug.wear(player(), self.aid)
        queueAidAction(HearingAidAction.TURN_ON, self.aid)
    end,
    validate = function(self, expect)
        expect(HearingAid.isOn(self.aid), "aid is off")
        expectHearing(expect, Level.DEAF)
    end,
})

test("hearingaid_turn_on", {
    run = function(self)
        HearingAid.setBaseLevel(player(), Level.HARD_OF_HEARING)
        self.aid = HearingAidDebug.addAid(player(), BASIC, 1, false)
        HearingAidDebug.wear(player(), self.aid)
        queueAidAction(HearingAidAction.TURN_ON, self.aid)
    end,
    validate = function(self, expect)
        expect(HearingAid.isOn(self.aid), "aid is off")
        expectHearing(expect, Level.NORMAL)
    end,
})

test("hearingaid_turn_off", {
    sandbox = { BatteryHoursBasic = 10 },
    periodicUpdate = false,
    run = function(self)
        HearingAid.setBaseLevel(player(), Level.HARD_OF_HEARING)
        self.aid = wearActiveAid(BASIC)
        self.hearingWhileOn = HearingAid.getHearingLevel(player())
        -- The last drain was two hours ago.
        HearingAid.update(hoursNow() - 2)
        queueAidAction(HearingAidAction.TURN_OFF, self.aid)
    end,
    validate = function(self, expect)
        expect(self.hearingWhileOn == Level.NORMAL, "aid didn't help while on")
        expect(not HearingAid.isOn(self.aid), "aid is still on")
        expect(near(HearingAid.getCharge(self.aid), 0.8, CHARGE_TOLERANCE),
            "charge is " .. HearingAid.getCharge(self.aid) .. ", expected 0.8 after two of ten hours")
        expectHearing(expect, Level.HARD_OF_HEARING)
    end,
})

test("hearingaid_wear_switched_on_aid", {
    run = function(self)
        HearingAid.setBaseLevel(player(), Level.HARD_OF_HEARING)
        self.aid = HearingAidDebug.addAid(player(), BASIC, 1, true)
        HearingAid.update()
        self.hearingBeforeWearing = HearingAid.getHearingLevel(player())
        ISTimedActionQueue.add(ISWearClothing:new(player(), self.aid))
    end,
    validate = function(self, expect)
        expect(self.hearingBeforeWearing == Level.HARD_OF_HEARING, "aid helped before it was worn")
        expect(self.aid:isWorn(), "aid is not worn")
        expectHearing(expect, Level.NORMAL)
    end,
})

test("hearingaid_take_off_switched_on_aid", {
    run = function(self)
        HearingAid.setBaseLevel(player(), Level.HARD_OF_HEARING)
        self.aid = wearActiveAid(BASIC)
        self.hearingWhileWorn = HearingAid.getHearingLevel(player())
        ISTimedActionQueue.add(ISUnequipAction:new(player(), self.aid, 50))
    end,
    validate = function(self, expect)
        expect(self.hearingWhileWorn == Level.NORMAL, "aid didn't help while worn")
        expect(not self.aid:isWorn(), "aid is still worn")
        expectHearing(expect, Level.HARD_OF_HEARING)
    end,
})

test("hearingaid_wear_broken_aid_over_working_one", {
    run = function(self)
        HearingAid.setBaseLevel(player(), Level.HARD_OF_HEARING)
        self.working = wearActiveAid(BASIC)
        self.broken = HearingAidDebug.addAid(player(), BROKEN, nil, false)
        ISTimedActionQueue.add(ISWearClothing:new(player(), self.broken))
    end,
    validate = function(self, expect)
        expect(self.broken:isWorn(), "broken aid is not worn")
        expect(not self.working:isWorn(), "working aid is still worn")
        expectHearing(expect, Level.HARD_OF_HEARING)
    end,
})

test("hearingaid_keeps_outside_trait_changes", {
    run = function(self)
        HearingAid.setBaseLevel(player(), Level.HARD_OF_HEARING)
        self.aid = wearActiveAid(BASIC)
        -- An admin gives the character Keen Hearing while the aid is on.
        player():getCharacterTraits():add(CharacterTrait.KEEN_HEARING)
        queueAidAction(HearingAidAction.TURN_OFF, self.aid)
    end,
    validate = function(self, expect)
        expectHearing(expect, Level.KEEN)
    end,
})

-- Batteries ------------------------------------------------------------------------------------

test("hearingaid_insert_battery", {
    run = function(self)
        self.aid = HearingAidDebug.addAid(player(), BASIC, nil, false)
        self.battery = HearingAidDebug.addBattery(player(), 0.5)
        queueAidAction(HearingAidAction.INSERT_BATTERY, self.aid, self.battery)
    end,
    validate = function(self, expect)
        expect(near(HearingAid.getCharge(self.aid), 0.5, CHARGE_TOLERANCE), "charge is " .. HearingAid.getCharge(self.aid))
        expect(not player():getInventory():contains(self.battery), "battery is still in the inventory")
        expect(not HearingAid.isOn(self.aid), "aid switched itself on")
    end,
})

test("hearingaid_remove_battery", {
    sandbox = { BatteryHoursBasic = 10 },
    periodicUpdate = false,
    run = function(self)
        HearingAid.setBaseLevel(player(), Level.HARD_OF_HEARING)
        self.aid = wearActiveAid(BASIC, 0.5)
        -- The last drain was two hours ago.
        HearingAid.update(hoursNow() - 2)
        queueAidAction(HearingAidAction.REMOVE_BATTERY, self.aid)
    end,
    validate = function(self, expect)
        expect(not HearingAid.hasBattery(self.aid), "aid still has a battery")
        expect(not HearingAid.isOn(self.aid), "aid is still on")
        local batteries = player():getInventory():getAllType("Base.Battery")
        expect(batteries:size() == 1, batteries:size() .. " batteries in the inventory")
        if batteries:size() == 1 then
            local charge = batteries:get(0):getCurrentUsesFloat()
            expect(near(charge, 0.3, CHARGE_TOLERANCE), "returned battery has charge " .. charge .. ", expected 0.3")
        end
        expectHearing(expect, Level.HARD_OF_HEARING)
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
    validate = function(self, expect)
        expect(self.alwaysCharge ~= nil, "no battery at a 100% chance")
        expect(self.alwaysCharge == nil or self.alwaysCharge > 0, "found battery is dead")
        expect(not self.neverHasBattery, "battery at a 0% chance")
    end,
})

test("hearingaid_battery_runs_out", {
    sandbox = { BatteryHoursBasic = 10 },
    run = function(self)
        HearingAid.setBaseLevel(player(), Level.HARD_OF_HEARING)
        self.aid = wearActiveAid(BASIC, 0.05)
        local now = hoursNow()
        HearingAid.update(now)
        HearingAid.update(now + 1)
    end,
    validate = function(self, expect)
        expect(HearingAid.getCharge(self.aid) == 0, "charge is " .. HearingAid.getCharge(self.aid))
        expect(HearingAid.hasBattery(self.aid), "dead battery was removed")
        expect(not HearingAid.isOn(self.aid), "aid is still on")
        expectHearing(expect, Level.HARD_OF_HEARING)
    end,
})

test("hearingaid_battery_life_per_tier", {
    sandbox = { BatteryHoursBasic = 8, BatteryHoursEfficient = 16, BatteryHoursBoosted = 4 },
    run = function(self)
        HearingAid.setBaseLevel(player(), Level.HARD_OF_HEARING)
        local start = hoursNow()
        self.charges = {}
        for i, fullType in ipairs({ BASIC, EFFICIENT, BOOSTED }) do
            local aid = wearActiveAid(fullType)
            local now = start + 10 * i
            HearingAid.update(now)
            HearingAid.update(now + 2)
            self.charges[fullType] = HearingAid.getCharge(aid)
        end
    end,
    validate = function(self, expect)
        -- Two hours of use on 8, 16 and 4 hour batteries.
        for fullType, expected in pairs({ [BASIC] = 0.75, [EFFICIENT] = 0.875, [BOOSTED] = 0.5 }) do
            local actual = self.charges[fullType]
            expect(near(actual, expected), fullType .. " charge is " .. actual .. ", expected " .. expected)
        end
    end,
})

test("hearingaid_no_drain_while_inactive", {
    sandbox = { BatteryHoursBasic = 10 },
    run = function(self)
        HearingAid.setBaseLevel(player(), Level.HARD_OF_HEARING)
        local aid = wearActiveAid(BASIC)
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
        -- One hour of use.
        HearingAid.setOn(aid, true)
        HearingAid.update(now + 7)
        HearingAid.update(now + 8)
        self.aid = aid
    end,
    validate = function(self, expect)
        expect(near(HearingAid.getCharge(self.aid), 0.9), "charge is " .. HearingAid.getCharge(self.aid) .. ", expected 0.9 after one of ten hours")
    end,
})

-- Crafting -------------------------------------------------------------------------------------

local function prepareToCraft()
    player():setPerkLevelDebug(Perks.Electricity, 8)
    HearingAidDebug.addRecipeMaterials(player())
    HearingAidDebug.placeWorkTable(player())
end

test("hearingaid_craft_repair", {
    -- At this chance the output's item OnCreate always rolls a battery, which the recipe must
    -- discard because the broken aid had none.
    sandbox = { SpawnWithBatteryChance = 100 },
    run = function(self)
        prepareToCraft()
        self.refusal = craft("HearingAid.RepairHearingAid", HearingAidDebug.addAid(player(), BROKEN, nil, false))
    end,
    validate = function(self, expect)
        local inventory = player():getInventory()
        local repaired = inventory:getAllType(BASIC)
        expect(repaired:size() == 1, repaired:size() .. " repaired hearing aids" .. refused(self))
        expect(repaired:size() == 0 or not HearingAid.hasBattery(repaired:get(0)), "repair created a battery")
        expect(inventory:getCountType(BROKEN) == 0, "broken aid not consumed")
    end,
})

-- People wear their reading glasses for close work, and a worn pair must serve as the magnifier.
test("hearingaid_craft_with_worn_reading_glasses", {
    run = function(self)
        prepareToCraft()
        self.glasses = player():getInventory():getFirstType("Base.Glasses_Reading")
        player():setWornItem(self.glasses:getBodyLocation(), self.glasses)
        self.refusal = craft("HearingAid.RepairHearingAid", HearingAidDebug.addAid(player(), BROKEN, nil, false))
    end,
    validate = function(self, expect)
        expect(player():getInventory():getCountType(BASIC) == 1, "not repaired with worn reading glasses" .. refused(self))
        expect(self.glasses:isWorn(), "reading glasses taken off")
    end,
})

test("hearingaid_craft_upgrade_keeps_battery", {
    sandbox = { SpawnWithBatteryChance = 0 },
    run = function(self)
        prepareToCraft()
        self.refusal = craft("HearingAid.OptimizeHearingAid", HearingAidDebug.addAid(player(), BASIC, 0.42, true))
    end,
    validate = function(self, expect)
        local upgraded = player():getInventory():getAllType(EFFICIENT)
        expect(upgraded:size() == 1, upgraded:size() .. " efficient hearing aids" .. refused(self))
        if upgraded:size() == 1 then
            local aid = upgraded:get(0)
            expect(near(HearingAid.getCharge(aid), 0.42), "charge is " .. HearingAid.getCharge(aid))
            expect(HearingAid.isOn(aid), "aid was switched off")
        end
    end,
})

test("hearingaid_craft_dismantle_returns_battery", {
    run = function(self)
        prepareToCraft()
        self.refusal = craft("HearingAid.DismantleHearingAid", HearingAidDebug.addAid(player(), EFFICIENT, 0.6, false))
    end,
    validate = function(self, expect)
        local inventory = player():getInventory()
        expect(inventory:getCountType(EFFICIENT) == 0, "aid not consumed" .. refused(self))
        local batteries = inventory:getAllType("Base.Battery")
        expect(batteries:size() == 1, batteries:size() .. " batteries returned")
        if batteries:size() == 1 then
            local charge = batteries:get(0):getCurrentUsesFloat()
            expect(near(charge, 0.6, CHARGE_TOLERANCE), "returned battery has charge " .. charge)
        end
    end,
})

test("hearingaid_craft_boost", {
    sandbox = { EnableBoosted = true },
    run = function(self)
        prepareToCraft()
        self.refusal = craft("HearingAid.BoostHearingAid", HearingAidDebug.addAid(player(), EFFICIENT, nil, false))
    end,
    validate = function(self, expect)
        local inventory = player():getInventory()
        expect(inventory:getCountType(BOOSTED) == 1, inventory:getCountType(BOOSTED) .. " boosted hearing aids" .. refused(self))
        expect(inventory:getCountType(EFFICIENT) == 0, "efficient aid not consumed")
    end,
})

test("hearingaid_craft_boost_disabled", {
    sandbox = { EnableBoosted = false },
    run = function(self)
        prepareToCraft()
        craft("HearingAid.BoostHearingAid", HearingAidDebug.addAid(player(), EFFICIENT, nil, false))
    end,
    validate = function(self, expect)
        local inventory = player():getInventory()
        expect(inventory:getCountType(BOOSTED) == 0, "boosted aid crafted while disabled")
        expect(inventory:getCountType(EFFICIENT) == 1, "efficient aid consumed")
    end,
})

test("hearingaid_craft_skill_level_from_sandbox", {
    sandbox = { RepairSkillLevel = 5 },
    run = function(self)
        prepareToCraft()
        player():setPerkLevelDebug(Perks.Electricity, 4)
        self.refusal = craft("HearingAid.RepairHearingAid", HearingAidDebug.addAid(player(), BROKEN, nil, false))
    end,
    validate = function(self, expect)
        local inventory = player():getInventory()
        expect(self.refusal == "Electrical too low", "refusal was " .. tostring(self.refusal))
        expect(inventory:getCountType(BASIC) == 0, "repaired below the configured Electrical level")
        expect(inventory:getCountType(BROKEN) == 1, "broken aid consumed")
    end,
})

test("hearingaid_craft_without_skill_requirement", {
    sandbox = { RepairSkillLevel = 0 },
    run = function(self)
        prepareToCraft()
        player():setPerkLevelDebug(Perks.Electricity, 0)
        self.refusal = craft("HearingAid.RepairHearingAid", HearingAidDebug.addAid(player(), BROKEN, nil, false))
    end,
    validate = function(self, expect)
        local inventory = player():getInventory()
        expect(inventory:getCountType(BASIC) == 1, inventory:getCountType(BASIC) .. " repaired hearing aids" .. refused(self))
    end,
})

-- Loot -----------------------------------------------------------------------------------------

-- Fills a scratch container from corpse loot lists, as the game fills a corpse of that outfit, and
-- returns the share of fills that held a hearing aid.
local function shareWithAid(listNames, fills)
    local container = ItemContainer.new()
    local withAid = 0
    for _ = 1, fills do
        for _, listName in ipairs(listNames) do
            local list = ItemPickerJava.getItemContainer("all", listName, nil, false)
            ItemPickerJava.doRollItem(list, container, 0, nil, true, nil)
        end
        for _, fullType in ipairs({ BROKEN, BASIC, EFFICIENT }) do
            if container:getCountType(fullType) > 0 then
                withAid = withAid + 1
                break
            end
        end
        container:removeAllItems()
    end
    return withAid / fills
end

-- About 15% of ordinary zombies wear a digital watch. Hearing aids should be a tenth as common on
-- ordinary corpses and far more common on retirees.
test("hearingaid_corpse_loot", {
    run = function(self)
        self.ordinary = shareWithAid({ "inventorymale" }, 4000)
        self.retiree = shareWithAid({ "Outfit_Retiree", "inventorymale" }, 1000)
    end,
    validate = function(self, expect)
        print(string.format("HearingAidTest INFO corpses with a hearing aid: %.2f%% ordinary, %.2f%% retiree",
            self.ordinary * 100, self.retiree * 100))
        expect(self.ordinary >= 0.15 / 20 and self.ordinary <= 0.15 / 5,
            "ordinary corpses outside 1/20 to 1/5 of the digital watch rate")
        expect(self.retiree >= 3 * self.ordinary, "retirees less than three times as likely as ordinary corpses")
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
        local p = player()
        self.withoutBattery = HearingAidDebug.addAid(p, BASIC, nil, false)
        self.off = HearingAidDebug.addAid(p, EFFICIENT, 0.5, false)
        self.on = HearingAidDebug.addAid(p, BOOSTED, 0.5, true)
        self.dead = HearingAidDebug.addAid(p, BASIC, 0, false)
        self.broken = HearingAidDebug.addAid(p, BROKEN, nil, false)
        self.batteryName = HearingAidDebug.addBattery(p, 0.25):getDisplayName()
        HearingAidDebug.addBattery(p, 0.75)
        HearingAidDebug.addBattery(p, 0)
    end,
    validate = function(self, expect)
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
