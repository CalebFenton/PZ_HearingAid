local Debug = require "HearingAid/Debug/HearingAidDebug"

-- Listed in the SCENARIOS panel on the main menu when the game runs with -debug
-- (DebugScenarios.lua). Starts a zombie-free world with the character Debug.setupPlayer equips.
debugScenarios = debugScenarios or {}

debugScenarios.HearingAidScenario = {
    name = "Hearing Aid",
    startLoc = { x = 10835, y = 10144, z = 0 }, -- Muldraugh; DebugScenarios requires a start location
    onStart = function()
        -- Crafting needs light, and the character stands outdoors.
        getGameTime():setTimeOfDay(10)
        Debug.setupPlayer(getPlayer())
    end,
}
