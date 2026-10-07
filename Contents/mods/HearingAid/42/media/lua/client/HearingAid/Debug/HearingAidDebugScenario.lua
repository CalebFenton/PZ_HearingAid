require "HearingAid/Debug/HearingAidDebug"

-- Listed in the SCENARIOS panel on the main menu when the game runs with -debug
-- (DebugScenarios.lua). Starts a zombie-free world with a hard of hearing character, every
-- hearing aid tier, batteries and the crafting materials.
debugScenarios = debugScenarios or {}

debugScenarios.HearingAidScenario = {
    name = "Hearing Aid",
    startLoc = { x = 10835, y = 10144, z = 0 }, -- Muldraugh; DebugScenarios requires a start location
    setSandbox = function()
        -- DebugScenarios doesn't record the active mods for the new save (see MainScreen.resetLuaIfNeeded).
        ActiveMods.getById("currentGame"):copyFrom(ActiveMods.getById("default"))
        SandboxVars.Zombies = 6 -- none
    end,
    onStart = function()
        HearingAidDebug.setupPlayer(getPlayer())
    end,
}
