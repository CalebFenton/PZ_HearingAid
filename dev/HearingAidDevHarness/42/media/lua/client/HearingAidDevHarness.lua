-- Development only, not published; dev/run-debug-client.sh --test, --art, --promo and --loot load
-- it. It drives the vanilla debug tools the way you would by hand: the Hearing Aid debug scenario
-- starts from the main menu (with -debug and DebugScenario.ForceLaunch=true in debug-options.ini).
-- With --test, every hearingaid_* test runs from Debug menu > Dev > Unit Tests > Timed Actions,
-- two screenshots go to <cachedir>/Screenshots, and "HearingAidTest DONE passed=<n> failed=<n>"
-- goes to console.txt. With --art, HearingAidDevArt saves close-ups instead and prints
-- "HearingAidArt DONE"; with --promo, HearingAidDevPromo saves the art for the README and prints
-- "HearingAidPromo DONE"; with --loot, HearingAidLoot measures the loot and prints a
-- "HearingAidLootReport" line for each place. Then the game quits.
require "HearingAid/Debug/HearingAidDebugScenario"
require "HearingAid/Debug/HearingAidTests"
require "DebugUIs/DebugMenu/UnitTests/UnitTestsDebug"
require "HearingAidDevArt"
require "HearingAidDevPromo"
require "HearingAid/Debug/HearingAidLoot"

local SETTLE_TICKS = 180
-- About 50 seconds; report(10000) runs the client out of memory.
local LOOT_SAMPLES = 4000

local scenario = debugScenarios.HearingAidScenario
scenario.forceLaunch = true

-- Single player pauses when the window loses focus, and paused games don't tick, so the tests
-- would stop whenever someone switches to another window.
getCore():setOptionPauseOnFocusloss(false)

local names = {}

local function testNames()
    local result = {}
    for name in pairs(TimedActionTests.getTests()) do
        if string.sub(name, 1, 11) == "hearingaid_" then
            table.insert(result, name)
        end
    end
    table.sort(result)
    return result
end

-- Leaves the character wearing a switched-on boosted aid with one aid of every tier on the
-- ground in front of them, for screenshots.
local function showcase()
    local player = getPlayer()
    HearingAidDebug.setupPlayer(player)
    local aid = player:getInventory():getFirstType(HearingAid.BOOSTED)
    HearingAid.setOn(aid, true)
    HearingAidDebug.wear(player, aid)
    local square = player:getCurrentSquare()
    for i, fullType in ipairs({ HearingAid.BROKEN, HearingAid.BASIC, HearingAid.EFFICIENT, HearingAid.BOOSTED }) do
        local dropped = instanceItem(fullType)
        square:AddWorldInventoryItem(dropped, 0.15 + 0.22 * (i - 1), 0.85, 0)
    end
    return aid
end

-- Saves <cachedir>/Screenshots/hearingaid_tests.png (Unit Tests panel with results), then hides
-- the panel, zooms in, pins the worn aid's tooltip and saves hearingaid_showcase.png. Calls
-- onDone afterwards.
local function screenshots(onDone)
    local step = 0
    local function onTick()
        step = step + 1
        if step == 10 then
            getCore():TakeFullScreenshot("hearingaid_tests.png")
        elseif step == 40 then
            UnitTestsDebug.instance:setVisible(false)
            local aid = showcase()
            for _ = 1, 8 do
                getCore():doZoomScroll(0, -1)
            end
            local tooltip = ISToolTipInv:new(aid)
            tooltip:initialise()
            tooltip.followMouse = false
            tooltip:setX(80)
            tooltip:setY(160)
            tooltip:addToUIManager()
            tooltip:setVisible(true)
        elseif step == 280 then
            getCore():TakeFullScreenshot("hearingaid_showcase.png")
        elseif step == 320 then
            Events.OnTick.Remove(onTick)
            onDone()
        end
    end
    Events.OnTick.Add(onTick)
end

local function reportWhenDone()
    local success, fail = getText("IGUI_UnitTests_Success"), getText("IGUI_UnitTests_Fail")
    local passed, failed = 0, 0
    for _, name in ipairs(names) do
        local label = UnitTestsTimedActionsPanelTestResults[name].resultLabel.name
        if string.sub(label, 1, #success) == success then
            passed = passed + 1
        elseif string.sub(label, 1, #fail) == fail then
            failed = failed + 1
        else
            return
        end
    end
    Events.OnTick.Remove(reportWhenDone)
    screenshots(function()
        print("HearingAidTest DONE passed=" .. passed .. " failed=" .. failed)
        getCore():quitToDesktop()
    end)
end

local ticks = 0
local function startTests()
    ticks = ticks + 1
    if ticks < SETTLE_TICKS then
        return
    end
    Events.OnTick.Remove(startTests)
    -- runOne fails on the panel's result labels unless the panel is open.
    UnitTestsDebug.OnOpenPanel()
    names = testNames()
    print("HearingAidTest START " .. #names)
    for _, name in ipairs(names) do
        TimedActionTests.runOne(name)
    end
    Events.OnTick.Add(reportWhenDone)
end

-- run-debug-client.sh writes the mode to <cachedir>/Lua/HearingAidDevHarness.txt.
local function readMode()
    local reader = getFileReader("HearingAidDevHarness.txt", false)
    if not reader then
        return "test"
    end
    local mode = reader:readLine()
    reader:close()
    return mode
end

-- Runs capture(onDone) once the world has settled, then quits.
local function captureAndQuit(capture, mark)
    local function onTick()
        ticks = ticks + 1
        if ticks < SETTLE_TICKS then
            return
        end
        Events.OnTick.Remove(onTick)
        capture(function()
            print(mark .. " DONE")
            getCore():quitToDesktop()
        end)
    end
    return onTick
end

local function share(fraction)
    if fraction <= 0 then
        return "none"
    end
    return string.format("%.1f%% (1 in %.1f)", fraction * 100, 1 / fraction)
end

local function reportLoot(onDone)
    local report = HearingAidLoot.report(LOOT_SAMPLES)
    for _, group in ipairs({ "zombies", "containers" }) do
        for _, entry in ipairs(report[group]) do
            print(string.format("HearingAidLootReport %s: wristwatch %s, broken aid %s, working aid %s, efficient aid %s, any aid %s",
                entry.label, share(entry.watch), share(entry.broken), share(entry.working), share(entry.efficient), share(entry.any)))
        end
    end
    onDone()
end

local originalOnStart = scenario.onStart
scenario.onStart = function()
    originalOnStart()
    local mode = readMode()
    if mode == "art" then
        Events.OnTick.Add(captureAndQuit(HearingAidDevArt.capture, "HearingAidArt"))
    elseif mode == "promo" then
        Events.OnTick.Add(captureAndQuit(HearingAidDevPromo.capture, "HearingAidPromo"))
    elseif mode == "loot" then
        Events.OnTick.Add(captureAndQuit(reportLoot, "HearingAidLootReport"))
    else
        Events.OnTick.Add(startTests)
    end
end
