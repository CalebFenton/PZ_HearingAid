-- Development only, not published. The test library's settings, which the client and the
-- server both read (dev/harness/docs/adopting.md).

require "PZHarness/Fixtures"
require "HearingAid/HearingAidRecipes"

PZHarness.registerTests({
    -- The scenario's hour. Crafting needs light, the world's light catches up with the clock
    -- only some frames after the game starts, and a game kept by --stay runs on into the night.
    hour = 10,
    sandbox = "HearingAid",
    -- The recipes' skill levels follow the *SkillLevel options, on each side.
    sandboxChanged = HearingAid.Recipes.applySkillLevels,
    -- The character's own hearing `spec.hearing` and `spec.periodicUpdate`. In the client's test
    -- file, which loads after this one and which a --stay rerun loads again.
    setup = function(self, spec)
        HearingAidTests.setup(self, spec)
    end,
})
