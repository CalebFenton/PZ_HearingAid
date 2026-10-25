-- Development only, not published; dev/run-debug-client.sh loads it with the shared harness mod
-- (dev/harness), which runs the mode the script names (--test, or one registered here) in the
-- Hearing Aid debug scenario and then quits the game. The script reads the mode's result from the
-- console.txt lines marked with its TAG or MODE_MARK_* in dev/harness.conf.
require "PZHarness/Runner"
require "HearingAid/Debug/HearingAidDebugScenario"
require "HearingAid/Debug/HearingAidLoot"
require "HearingAidDevArt"
require "HearingAidDevPromo"

-- About 50 seconds.
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
        promo = { uncapped = true, clearWeather = true, fastUI = true, run = HearingAidDevPromo.capture },
        loot = { run = reportLoot },
    },
})
