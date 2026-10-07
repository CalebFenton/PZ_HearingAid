-- Development only (not published). Drives the vanilla debug tooling the same way you would by
-- hand: the Hearing Aid debug scenario starts as soon as the main menu loads (requires
-- -debug and DebugScenario.ForceLaunch=true in debug-options.ini), then the mod's tests run
-- from Debug menu > Dev > Unit Tests > Timed Actions. Results go to console.txt as
-- "HearingAidTest ..." and "HearingAidCheck ..." lines.
require "HearingAid/Debug/HearingAidDebugScenario"
require "HearingAid/Debug/HearingAidTests"
require "DebugUIs/DebugMenu/UnitTests/UnitTestsDebug"

local SETTLE_TICKS = 180

local scenario = debugScenarios.HearingAidScenario
scenario.forceLaunch = true

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

local function contains(items, fullType)
    for i = 1, #items, 2 do
        if items[i] == fullType then
            return true
        end
    end
    return false
end

-- Content that unit tests don't touch: scripts, registries and loot tables actually loaded.
local function selfCheck()
    local manager = getScriptManager()
    for _, fullType in ipairs({ HearingAid.BROKEN, HearingAid.BASIC, HearingAid.EFFICIENT, HearingAid.BOOSTED }) do
        local script = manager:getItem(fullType)
        print("HearingAidCheck item " .. fullType .. " loaded=" .. tostring(script ~= nil)
            .. " name=" .. tostring(script and script:getDisplayName())
            .. " bodyLocation=" .. tostring(script and script:getBodyLocation()))
    end
    for _, name in ipairs({ "RepairHearingAid", "OptimizeHearingAid", "BoostHearingAid", "DismantleHearingAid" }) do
        local recipe = manager:getCraftRecipe("HearingAid." .. name)
        print("HearingAidCheck recipe " .. name .. " loaded=" .. tostring(recipe ~= nil)
            .. " name=" .. tostring(recipe and getText(recipe:getTranslationName())))
    end
    for _, tier in ipairs({ "Broken", "Basic", "Efficient", "Boosted" }) do
        print("HearingAidCheck model HearingAid_Ground_" .. tier .. " loaded=" .. tostring(manager:getModelScript("HearingAid_Ground_" .. tier) ~= nil))
    end
    local location = ItemBodyLocation.get(ResourceLocation.of("hearingaid:hearingaid"))
    print("HearingAidCheck bodyLocation registered=" .. tostring(location ~= nil)
        .. " inHumanGroup=" .. tostring(location ~= nil and BodyLocations.getGroup("Human"):getLocation(location) ~= nil))
    print("HearingAidCheck loot BathroomCabinet broken=" .. tostring(contains(ProceduralDistributions.list.BathroomCabinet.items, HearingAid.BROKEN))
        .. " basic=" .. tostring(contains(ProceduralDistributions.list.BathroomCabinet.items, HearingAid.BASIC)))
    local retiree = SuburbsDistributions.all.Outfit_Retiree
    print("HearingAidCheck loot Outfit_Retiree broken=" .. tostring(retiree ~= nil and contains(retiree.items, HearingAid.BROKEN)))
    print("HearingAidCheck sandbox BatteryHoursBasic=" .. tostring(HearingAid.sandbox().BatteryHoursBasic)
        .. " HandleDeafness=" .. tostring(HearingAid.sandbox().HandleDeafness))
    print("HearingAidCheck translation " .. getText("IGUI_HearingAid_BatteryDead") .. " | " .. getText("Sandbox_HearingAid_BatteryHoursBasic"))
end

-- Builds the real right-click inventory menu (ISInventoryPaneContextMenu.createMenu) for the
-- scenario's aids and lists the hearing aid options it got.
local function describeMenu(item)
    local context = ISInventoryPaneContextMenu.createMenu(0, true, { item }, 300, 300)
    local wanted = {
        [getText("ContextMenu_AddBattery")] = true,
        [getText("ContextMenu_Remove_Battery")] = true,
        [getText("ContextMenu_Turn_On")] = true,
        [getText("ContextMenu_Turn_Off")] = true,
    }
    local found = {}
    for _, option in ipairs(context.options) do
        if wanted[option.name] then
            local text = option.name
            if option.subOption then
                text = text .. "[" .. context:getSubMenu(option.subOption).numOptions - 1 .. " batteries]"
            end
            if option.notAvailable then
                text = text .. "(disabled)"
            end
            table.insert(found, text)
        end
    end
    context:hideAndChildren()
    return table.concat(found, ", ")
end

local function menuCheck()
    local inventory = getPlayer():getInventory()
    print("HearingAidCheck menu basic(no battery)=" .. describeMenu(inventory:getFirstType(HearingAid.BASIC)))
    print("HearingAidCheck menu efficient(battery, off)=" .. describeMenu(inventory:getFirstType(HearingAid.EFFICIENT)))
end

-- Leaves the character wearing a switched-on boosted aid with one aid of every tier on the
-- ground in front of them, for screenshots.
local function showcase()
    local player = getPlayer()
    HearingAidDebug.setupPlayer(player)
    local inventory = player:getInventory()
    local aid = inventory:getFirstType(HearingAid.BOOSTED)
    HearingAidDebug.wear(player, aid)
    HearingAid.setOn(aid, true)
    HearingAid.reconcile(player)
    local square = player:getCurrentSquare()
    for i, fullType in ipairs({ HearingAid.BROKEN, HearingAid.BASIC, HearingAid.EFFICIENT, HearingAid.BOOSTED }) do
        local dropped = instanceItem(fullType)
        square:AddWorldInventoryItem(dropped, 0.15 + 0.22 * (i - 1), 0.85, 0)
    end
    print("HearingAidCheck showcase worn=" .. tostring(aid:isWorn()) .. " hearing=" .. HearingAid.getHearingLevel(player))
    return aid
end

-- Saves <cachedir>/Screenshots/hearingaid_tests.png (Unit Tests panel with results), then hides
-- the panel, zooms in, pins the worn aid's tooltip and saves hearingaid_showcase.png.
local function screenshots()
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
            print("HearingAidTest SCREENSHOTS hearingaid_tests.png hearingaid_showcase.png")
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
    print("HearingAidTest DONE passed=" .. passed .. " failed=" .. failed)
    screenshots()
end

local ticks = 0
local function startTests()
    ticks = ticks + 1
    if ticks < SETTLE_TICKS then
        return
    end
    Events.OnTick.Remove(startTests)
    selfCheck()
    menuCheck()
    UnitTestsDebug.OnOpenPanel()
    names = testNames()
    print("HearingAidTest START " .. #names)
    for _, name in ipairs(names) do
        TimedActionTests.runOne(name)
    end
    Events.OnTick.Add(reportWhenDone)
end

local originalOnStart = scenario.onStart
scenario.onStart = function()
    originalOnStart()
    Events.OnTick.Add(startTests)
end
