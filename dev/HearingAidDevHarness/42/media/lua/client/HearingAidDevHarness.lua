-- Development only, not published; dev/run-debug-client.sh loads it with the shared harness mod
-- (dev/harness), which runs the modes it registers here. Every mode starts the Hearing Aid debug
-- scenario. With --test the harness runs every hearingaid_* test and prints
-- "HearingAidTest DONE passed=<n> failed=<n> skipped=<n>". With --art, HearingAidDevArt saves
-- close-ups and prints "HearingAidArt DONE"; with --promo, HearingAidDevPromo saves the art for the
-- README and prints "HearingAidPromo DONE"; with --loot, HearingAidLoot measures the loot and
-- prints a "HearingAidLootReport" line for each place, then "HearingAidLootReport DONE". Then the
-- game quits. run-debug-client.sh reads those lines from console.txt.
require "PZHarness/Runner"
require "HearingAid/HearingAidRecipes"
require "HearingAid/Debug/HearingAidDebugScenario"
require "HearingAid/Debug/HearingAidLoot"
require "HearingAidDevArt"
require "HearingAidDevPromo"

-- About 50 seconds; report(10000) runs the client out of memory.
local LOOT_SAMPLES = 4000

local function share(fraction)
    if fraction <= 0 then
        return "none"
    end
    return string.format("%.1f%% (1 in %.1f)", fraction * 100, 1 / fraction)
end

local function reportLoot(_, done)
    local report = HearingAidLoot.report(LOOT_SAMPLES)
    for _, group in ipairs({ "zombies", "containers" }) do
        for _, entry in ipairs(report[group]) do
            print(string.format("HearingAidLootReport %s: wristwatch %s, broken aid %s, working aid %s, efficient aid %s, any aid %s",
                entry.label, share(entry.watch), share(entry.broken), share(entry.working), share(entry.efficient), share(entry.any)))
        end
    end
    done()
end

PZHarness.register({
    scenario = "HearingAidScenario",
    prefix = "hearingaid_",
    modes = {
        -- Both wait on the UI's drawings and the zoom rather than on frame counts, so they draw
        -- uncapped, and their world shots show a clear day.
        art = { uncapped = true, clearWeather = true, fastUI = true, run = function(_, done) HearingAidDevArt.capture(done) end },
        promo = { uncapped = true, clearWeather = true, fastUI = true, run = function(_, done) HearingAidDevPromo.capture(done) end },
        loot = { run = reportLoot },
    },
    tests = {
        -- The scenario's hour. Crafting needs light, the world's light catches up with the clock
        -- only some frames after the game starts, and a game kept by --stay runs on into the night.
        hour = 10,
        sandbox = "HearingAid",
        -- The recipes' skill levels follow the *SkillLevel options.
        sandboxChanged = HearingAid.Recipes.applySkillLevels,
        -- Traits and player modData carry over from the test before, so every test starts from the
        -- character's own hearing `spec.hearing` (Hard of Hearing unless set). With
        -- `spec.periodicUpdate = false` the every-minute HearingAid.update() stops until the test
        -- ends, so a test can show that an action drains the battery itself.
        setup = function(self, spec)
            HearingAid.setBaseLevel(getSpecificPlayer(0), spec.hearing or HearingAid.Level.HARD_OF_HEARING)
            if spec.periodicUpdate == false then
                Events.EveryOneMinute.Remove(HearingAid.update)
                PZHarness.Test.defer(self, function() Events.EveryOneMinute.Add(HearingAid.update) end)
            end
        end,
    },
})
