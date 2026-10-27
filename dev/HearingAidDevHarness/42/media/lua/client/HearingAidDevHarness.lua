-- Development only, not published; dev/run-debug-client.sh loads it with the shared harness mod
-- (dev/harness), which runs the mode the script names (--test, or one registered here) in the
-- Hearing Aid debug scenario and then quits the game. The script reads the mode's result from the
-- console.txt lines marked with the run's mark (PZHarness.run.mark).
require "PZHarness/Runner"
require "PZHarness/Loot"
require "HearingAid/Debug/HearingAidDebugScenario"
require "HearingAid/Debug/HearingAidLoot"
require "HearingAidDevArt"
require "HearingAidDevPromo"

-- About 50 seconds.
local LOOT_SAMPLES = 4000

local function share(fraction)
    return PZHarness.Loot.share(fraction, 1, 1)
end

local function reportLoot(_, done)
    local report = HearingAidLoot.report(LOOT_SAMPLES)
    for _, group in ipairs({ "zombies", "containers" }) do
        for _, entry in ipairs(report[group]) do
            print(string.format("%s %s: wristwatch %s, broken aid %s, working aid %s, efficient aid %s, any aid %s",
                PZHarness.run.mark, entry.label, share(entry.watch), share(entry.broken), share(entry.working),
                share(entry.efficient), share(entry.any)))
        end
    end
    done()
end

PZHarness.register({
    scenario = "HearingAidScenario",
    prefix = "hearingaid_",
    modes = {
        -- Both wait on the UI's drawings and the zoom rather than on frame counts, and their world
        -- shots show a clear day.
        art = { capture = true, run = function(_, done) HearingAidDevArt.capture(done) end },
        promo = { capture = true, run = HearingAidDevPromo.capture },
        loot = { run = reportLoot },
    },
})
