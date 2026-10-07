require "Tests/TimedActionsTests"
require "TimedActions/HearingAidAction"
require "TimedActions/ISUnequipAction"
require "HearingAid/Debug/HearingAidDebug"

-- Registered with the vanilla timed action test runner: Debug menu > Dev > Unit Tests >
-- Timed Actions (debug mode). The runner empties the inventory before run(), waits for the
-- action queue to drain, then calls validate(); a falsy result marks the test failed.
-- Each validate() also prints "HearingAidTest PASS|FAIL <name>" to console.txt.

local Level = HearingAid.Level
local LEVEL_NAMES = { [0] = "deaf", [1] = "hard of hearing", [2] = "normal", [3] = "keen" }

local function player()
    return getSpecificPlayer(0)
end

local function check(name, failures)
    if #failures == 0 then
        print("HearingAidTest PASS " .. name)
        return true
    end
    print("HearingAidTest FAIL " .. name .. ": " .. table.concat(failures, "; "))
    return false
end

local function expectLevel(failures, expected)
    local actual = HearingAid.getHearingLevel(player())
    if actual ~= expected then
        table.insert(failures, "hearing is " .. LEVEL_NAMES[actual] .. ", expected " .. LEVEL_NAMES[expected])
    end
end

local function expect(failures, condition, message)
    if not condition then
        table.insert(failures, message)
    end
end

local function near(a, b)
    return math.abs(a - b) < 0.011
end

local function queue(mode, aid, battery)
    ISTimedActionQueue.add(HearingAidAction:new(player(), mode, aid, battery))
end

-- Wears a charged aid that is already switched on and applied.
local function wearActiveAid(fullType, charge)
    local aid = HearingAidDebug.addAid(player(), fullType, charge or 1.0, true)
    HearingAidDebug.wear(player(), aid)
    return aid
end

-- The mode must hold until the queued action completes, so run() sets it and validate() restores it.
local function setDeafnessMode(test, mode)
    SandboxVars.HearingAid = SandboxVars.HearingAid or {}
    test.previousDeafnessMode = SandboxVars.HearingAid.HandleDeafness
    SandboxVars.HearingAid.HandleDeafness = mode
end

local function restoreDeafnessMode(test)
    SandboxVars.HearingAid.HandleDeafness = test.previousDeafnessMode
end

local tests = {}

tests.hearingaid_insert_battery = {
    run = function(self)
        self.aid = HearingAidDebug.addAid(player(), HearingAid.BASIC, nil, false)
        self.battery = HearingAidDebug.addBattery(player(), 0.5)
        queue(HearingAidAction.INSERT_BATTERY, self.aid, self.battery)
    end,
    validate = function(self)
        local failures = {}
        expect(failures, HearingAid.hasBattery(self.aid), "aid has no battery")
        expect(failures, near(HearingAid.getCharge(self.aid), 0.5), "charge is " .. HearingAid.getCharge(self.aid))
        expect(failures, not player():getInventory():contains(self.battery), "battery still in inventory")
        expect(failures, not HearingAid.isOn(self.aid), "aid switched itself on")
        return check("hearingaid_insert_battery", failures)
    end,
}

tests.hearingaid_turn_on_hard_of_hearing = {
    run = function(self)
        HearingAidDebug.setHearing(player(), Level.HARD_OF_HEARING)
        self.aid = HearingAidDebug.addAid(player(), HearingAid.BASIC, 1.0, false)
        HearingAidDebug.wear(player(), self.aid)
        queue(HearingAidAction.TURN_ON, self.aid)
    end,
    validate = function(self)
        local failures = {}
        expect(failures, HearingAid.isOn(self.aid), "aid is off")
        expectLevel(failures, Level.NORMAL)
        return check("hearingaid_turn_on_hard_of_hearing", failures)
    end,
}

tests.hearingaid_turn_off_restores_trait = {
    run = function(self)
        HearingAidDebug.setHearing(player(), Level.HARD_OF_HEARING)
        self.aid = wearActiveAid(HearingAid.BASIC)
        self.appliedLevel = HearingAid.getHearingLevel(player())
        queue(HearingAidAction.TURN_OFF, self.aid)
    end,
    validate = function(self)
        local failures = {}
        expect(failures, self.appliedLevel == Level.NORMAL, "aid was not applied before switching off")
        expect(failures, not HearingAid.isOn(self.aid), "aid is still on")
        expectLevel(failures, Level.HARD_OF_HEARING)
        expect(failures, player():getModData().HearingAid_baseLevel == nil, "player record not cleared")
        return check("hearingaid_turn_off_restores_trait", failures)
    end,
}

tests.hearingaid_remove_battery = {
    run = function(self)
        HearingAidDebug.setHearing(player(), Level.HARD_OF_HEARING)
        self.aid = wearActiveAid(HearingAid.BASIC, 0.3)
        queue(HearingAidAction.REMOVE_BATTERY, self.aid)
    end,
    validate = function(self)
        local failures = {}
        expect(failures, not HearingAid.hasBattery(self.aid), "aid still has a battery")
        expect(failures, not HearingAid.isOn(self.aid), "aid is still on")
        local batteries = player():getInventory():getAllType("Base.Battery")
        expect(failures, batteries:size() == 1, batteries:size() .. " batteries in inventory")
        if batteries:size() == 1 then
            local charge = batteries:get(0):getCurrentUsesFloat()
            expect(failures, near(charge, 0.3), "returned battery has charge " .. charge)
        end
        expectLevel(failures, Level.HARD_OF_HEARING)
        return check("hearingaid_remove_battery", failures)
    end,
}

tests.hearingaid_deaf_basic = {
    run = function(self)
        setDeafnessMode(self, HearingAid.DeafnessMode.ALL_AIDS)
        HearingAidDebug.setHearing(player(), Level.DEAF)
        self.aid = HearingAidDebug.addAid(player(), HearingAid.BASIC, 1.0, false)
        HearingAidDebug.wear(player(), self.aid)
        queue(HearingAidAction.TURN_ON, self.aid)
    end,
    validate = function(self)
        restoreDeafnessMode(self)
        local failures = {}
        expectLevel(failures, Level.HARD_OF_HEARING)
        return check("hearingaid_deaf_basic", failures)
    end,
}

tests.hearingaid_deaf_boosted = {
    run = function(self)
        setDeafnessMode(self, HearingAid.DeafnessMode.ALL_AIDS)
        HearingAidDebug.setHearing(player(), Level.DEAF)
        self.aid = HearingAidDebug.addAid(player(), HearingAid.BOOSTED, 1.0, false)
        HearingAidDebug.wear(player(), self.aid)
        queue(HearingAidAction.TURN_ON, self.aid)
    end,
    validate = function(self)
        restoreDeafnessMode(self)
        local failures = {}
        expectLevel(failures, Level.NORMAL)
        return check("hearingaid_deaf_boosted", failures)
    end,
}

tests.hearingaid_deaf_mode_none = {
    run = function(self)
        setDeafnessMode(self, HearingAid.DeafnessMode.NONE)
        HearingAidDebug.setHearing(player(), Level.DEAF)
        self.aid = HearingAidDebug.addAid(player(), HearingAid.BOOSTED, 1.0, false)
        HearingAidDebug.wear(player(), self.aid)
        queue(HearingAidAction.TURN_ON, self.aid)
    end,
    validate = function(self)
        restoreDeafnessMode(self)
        local failures = {}
        expect(failures, HearingAid.isOn(self.aid), "aid is off")
        expectLevel(failures, Level.DEAF)
        return check("hearingaid_deaf_mode_none", failures)
    end,
}

tests.hearingaid_deaf_mode_boosted_only = {
    run = function(self)
        setDeafnessMode(self, HearingAid.DeafnessMode.BOOSTED_ONLY)
        HearingAidDebug.setHearing(player(), Level.DEAF)
        -- A basic aid, already on, is worn first and must not help...
        local basic = wearActiveAid(HearingAid.BASIC)
        self.basicLevel = HearingAid.getHearingLevel(player())
        player():removeWornItem(basic)
        HearingAid.reconcile(player())
        -- ...then a boosted one is switched on.
        self.aid = HearingAidDebug.addAid(player(), HearingAid.BOOSTED, 1.0, false)
        HearingAidDebug.wear(player(), self.aid)
        queue(HearingAidAction.TURN_ON, self.aid)
    end,
    validate = function(self)
        restoreDeafnessMode(self)
        local failures = {}
        expect(failures, self.basicLevel == Level.DEAF, "basic aid helped a deaf character")
        expectLevel(failures, Level.HARD_OF_HEARING)
        return check("hearingaid_deaf_mode_boosted_only", failures)
    end,
}

tests.hearingaid_boosted_gives_keen = {
    run = function(self)
        HearingAidDebug.setHearing(player(), Level.NORMAL)
        self.aid = HearingAidDebug.addAid(player(), HearingAid.BOOSTED, 1.0, false)
        HearingAidDebug.wear(player(), self.aid)
        queue(HearingAidAction.TURN_ON, self.aid)
    end,
    validate = function(self)
        local failures = {}
        expectLevel(failures, Level.KEEN)
        return check("hearingaid_boosted_gives_keen", failures)
    end,
}

tests.hearingaid_not_worn_does_nothing = {
    run = function(self)
        HearingAidDebug.setHearing(player(), Level.HARD_OF_HEARING)
        self.aid = HearingAidDebug.addAid(player(), HearingAid.BASIC, 1.0, false)
        queue(HearingAidAction.TURN_ON, self.aid)
    end,
    validate = function(self)
        local failures = {}
        expect(failures, HearingAid.isOn(self.aid), "aid is off")
        expectLevel(failures, Level.HARD_OF_HEARING)
        return check("hearingaid_not_worn_does_nothing", failures)
    end,
}

tests.hearingaid_unequip_restores_trait = {
    run = function(self)
        HearingAidDebug.setHearing(player(), Level.HARD_OF_HEARING)
        self.aid = wearActiveAid(HearingAid.BASIC)
        self.appliedLevel = HearingAid.getHearingLevel(player())
        ISTimedActionQueue.add(ISUnequipAction:new(player(), self.aid, 50))
    end,
    validate = function(self)
        local failures = {}
        expect(failures, self.appliedLevel == Level.NORMAL, "aid was not applied before taking it off")
        expect(failures, not self.aid:isWorn(), "aid is still worn")
        expectLevel(failures, Level.HARD_OF_HEARING)
        return check("hearingaid_unequip_restores_trait", failures)
    end,
}

tests.hearingaid_battery_runs_out = {
    run = function(self)
        HearingAidDebug.setHearing(player(), Level.HARD_OF_HEARING)
        -- 1% of a basic aid's battery, then two drain ticks an hour of game time apart.
        self.aid = wearActiveAid(HearingAid.BASIC, 0.01)
        local now = getGameTime():getWorldAgeHours()
        HearingAid.update(now)
        HearingAid.update(now + 1)
    end,
    validate = function(self)
        local failures = {}
        expect(failures, HearingAid.getCharge(self.aid) == 0, "charge is " .. HearingAid.getCharge(self.aid))
        expect(failures, HearingAid.hasBattery(self.aid), "dead battery was removed")
        expect(failures, not HearingAid.isOn(self.aid), "aid is still on")
        expectLevel(failures, Level.HARD_OF_HEARING)
        return check("hearingaid_battery_runs_out", failures)
    end,
}

tests.hearingaid_battery_drain_rate = {
    run = function(self)
        HearingAidDebug.setHearing(player(), Level.HARD_OF_HEARING)
        self.aid = wearActiveAid(HearingAid.BASIC, 1.0)
        self.hours = HearingAid.getBatteryHours(self.aid)
        local now = getGameTime():getWorldAgeHours()
        HearingAid.update(now)
        HearingAid.update(now + self.hours / 4)
    end,
    validate = function(self)
        local failures = {}
        expect(failures, near(HearingAid.getCharge(self.aid), 0.75), "a quarter of the battery life left " .. HearingAid.getCharge(self.aid))
        expect(failures, HearingAid.isOn(self.aid), "aid switched off")
        expectLevel(failures, Level.NORMAL)
        return check("hearingaid_battery_drain_rate", failures)
    end,
}

-- Crafting goes through the same path as right-clicking an item and picking the recipe.
local function craft(recipeName, selectedItem)
    local recipe = getScriptManager():getCraftRecipe(recipeName)
    ISInventoryPaneContextMenu.OnNewCraft(selectedItem, recipe, player():getPlayerNum(), false)
end

local function addCraftingMaterials()
    player():setPerkLevelDebug(Perks.Electricity, 8)
    HearingAidDebug.addItems(player(), "Base.Screwdriver", 1)
    HearingAidDebug.addItems(player(), "Base.ElectronicsScrap", 4)
    HearingAidDebug.addItems(player(), "Base.Aluminum", 1)
end

local function onlyItem(fullType)
    local items = player():getInventory():getAllType(fullType)
    return items:size() == 1 and items:get(0) or nil, items:size()
end

tests.hearingaid_craft_repair = {
    run = function(self)
        addCraftingMaterials()
        local broken = HearingAidDebug.addAid(player(), HearingAid.BROKEN, nil, false)
        craft("HearingAid.RepairHearingAid", broken)
    end,
    validate = function(self)
        local failures = {}
        local aid, count = onlyItem(HearingAid.BASIC)
        expect(failures, aid ~= nil, count .. " repaired hearing aids")
        expect(failures, aid == nil or not HearingAid.hasBattery(aid), "repair created a battery")
        expect(failures, player():getInventory():getCountType(HearingAid.BROKEN) == 0, "broken aid not consumed")
        return check("hearingaid_craft_repair", failures)
    end,
}

tests.hearingaid_craft_optimize_keeps_battery = {
    run = function(self)
        addCraftingMaterials()
        local aid = HearingAidDebug.addAid(player(), HearingAid.BASIC, 0.42, true)
        craft("HearingAid.OptimizeHearingAid", aid)
    end,
    validate = function(self)
        local failures = {}
        local aid, count = onlyItem(HearingAid.EFFICIENT)
        expect(failures, aid ~= nil, count .. " efficient hearing aids")
        if aid then
            expect(failures, near(HearingAid.getCharge(aid), 0.42), "charge is " .. HearingAid.getCharge(aid))
            expect(failures, HearingAid.isOn(aid), "switch state lost")
        end
        return check("hearingaid_craft_optimize_keeps_battery", failures)
    end,
}

tests.hearingaid_craft_dismantle_returns_battery = {
    run = function(self)
        addCraftingMaterials()
        local aid = HearingAidDebug.addAid(player(), HearingAid.EFFICIENT, 0.6, false)
        craft("HearingAid.DismantleHearingAid", aid)
    end,
    validate = function(self)
        local failures = {}
        expect(failures, player():getInventory():getCountType(HearingAid.EFFICIENT) == 0, "aid not consumed")
        expect(failures, player():getInventory():getCountType("Base.ElectronicsScrap") == 5, "no electronics scrap returned")
        local battery, count = onlyItem("Base.Battery")
        expect(failures, battery ~= nil, count .. " batteries returned")
        if battery then
            expect(failures, near(battery:getCurrentUsesFloat(), 0.6), "battery charge " .. battery:getCurrentUsesFloat())
        end
        return check("hearingaid_craft_dismantle_returns_battery", failures)
    end,
}

tests.hearingaid_craft_boost_disabled = {
    run = function(self)
        SandboxVars.HearingAid = SandboxVars.HearingAid or {}
        self.previous = SandboxVars.HearingAid.EnableBoosted
        SandboxVars.HearingAid.EnableBoosted = false
        addCraftingMaterials()
        HearingAidDebug.addItems(player(), "Base.Scalpel", 1)
        HearingAidDebug.addItems(player(), "Base.Earbuds", 1)
        HearingAidDebug.addItems(player(), "Base.Amplifier", 1)
        HearingAidDebug.addItems(player(), "Base.ElectricWire", 1)
        local aid = HearingAidDebug.addAid(player(), HearingAid.EFFICIENT, nil, false)
        craft("HearingAid.BoostHearingAid", aid)
    end,
    validate = function(self)
        SandboxVars.HearingAid.EnableBoosted = self.previous
        local failures = {}
        expect(failures, player():getInventory():getCountType(HearingAid.BOOSTED) == 0, "boosted aid crafted while disabled")
        expect(failures, player():getInventory():getCountType(HearingAid.EFFICIENT) == 1, "efficient aid consumed")
        return check("hearingaid_craft_boost_disabled", failures)
    end,
}

tests.hearingaid_craft_boost = {
    run = function(self)
        addCraftingMaterials()
        HearingAidDebug.addItems(player(), "Base.Scalpel", 1)
        HearingAidDebug.addItems(player(), "Base.Earbuds", 1)
        HearingAidDebug.addItems(player(), "Base.Amplifier", 1)
        HearingAidDebug.addItems(player(), "Base.ElectricWire", 1)
        local aid = HearingAidDebug.addAid(player(), HearingAid.EFFICIENT, nil, false)
        craft("HearingAid.BoostHearingAid", aid)
    end,
    validate = function(self)
        local failures = {}
        local aid, count = onlyItem(HearingAid.BOOSTED)
        expect(failures, aid ~= nil, count .. " boosted hearing aids")
        expect(failures, player():getInventory():getCountType("Base.Scalpel") == 1, "scalpel consumed")
        return check("hearingaid_craft_boost", failures)
    end,
}

local registry = TimedActionTests.getTests()
for name, test in pairs(tests) do
    registry[name] = test
end
