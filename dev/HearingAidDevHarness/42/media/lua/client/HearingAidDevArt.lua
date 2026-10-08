-- Development only; dev/run-debug-client.sh --art runs it instead of the tests. It saves close-ups
-- of the art to <cachedir>/Screenshots: art_<sex>_<item type>.png shows a bald character wearing
-- that aid from four sides, drawn by the character preview panel of the character creation
-- screen, and art_ground.png shows every aid on the ground at the closest zoom.
require "ISUI/ISUI3DModel"
require "HearingAid/Debug/HearingAidDebug"

HearingAidDevArt = {}

-- The preview panel shows (25 - zoom) / sqrt(2048) model units above and below its centre, and
-- the y offset moves the character down, so these frame the head.
local ZOOM = 19
local Y_OFFSET = -0.88
local DIRECTIONS = { IsoDirections.E, IsoDirections.S, IsoDirections.W, IsoDirections.N }
-- Both ears' items share a ground model, so the ground shows each tier once.
local TIERS = { HearingAid.BROKEN, HearingAid.BASIC, HearingAid.EFFICIENT, HearingAid.BOOSTED }
local AIDS = {}
for _, fullType in ipairs(TIERS) do
    table.insert(AIDS, fullType)
end
for _, fullType in ipairs(TIERS) do
    table.insert(AIDS, HearingAid.leftEarType(fullType))
end

local function setLook(player, female)
    player:setFemale(female)
    player:getDescriptor():setFemale(female)
    local visual = player:getHumanVisual()
    visual:setHairModel("Bald")
    visual:setBeardModel("")
    player:resetModel()
end

local function takeOffAids(player)
    local worn = player:getWornItems()
    for i = worn:size() - 1, 0, -1 do
        local item = worn:get(i):getItem()
        if HearingAid.isHearingAid(item) then
            player:removeWornItem(item, false)
        end
    end
end

-- A free square next to the character that nothing stands between, south and east first: those
-- are in front of the character on screen.
local function groundSquare(player)
    local here = player:getCurrentSquare()
    for _, direction in ipairs({ IsoDirections.S, IsoDirections.E, IsoDirections.W, IsoDirections.N }) do
        local square = here:getAdjacentSquare(direction)
        if square and square:isFree(false) and not here:isBlockedTo(square) then
            return square
        end
    end
    return here
end

-- A row of preview panels on an opaque backdrop across the middle of the screen.
local function createPanels(player)
    local size = math.floor(getCore():getScreenWidth() / #DIRECTIONS)
    local backdrop = ISPanel:new(0, math.floor((getCore():getScreenHeight() - size) / 2), size * #DIRECTIONS, size)
    backdrop.backgroundColor = { r = 0.3, g = 0.3, b = 0.3, a = 1 }
    backdrop:initialise()
    backdrop:addToUIManager()
    local panels = {}
    for i, direction in ipairs(DIRECTIONS) do
        local panel = ISUI3DModel:new((i - 1) * size, 0, size, size)
        panel:setVisible(true)
        backdrop:addChild(panel)
        panel:setState("idle")
        panel:setIsometric(false)
        panel:setDirection(direction)
        panel:setZoom(ZOOM)
        panel:setYOffset(Y_OFFSET)
        panel:setCharacter(player)
        table.insert(panels, panel)
    end
    return backdrop, panels
end

-- Runs each step on its own tick, then waits as many ticks as the step returns.
local function runSteps(steps, onDone)
    local index, wait = 1, 0
    local function onTick()
        if wait > 0 then
            wait = wait - 1
            return
        end
        local step = steps[index]
        if not step then
            Events.OnTick.Remove(onTick)
            onDone()
            return
        end
        index = index + 1
        wait = step() or 0
    end
    Events.OnTick.Add(onTick)
end

function HearingAidDevArt.capture(onDone)
    local player = getPlayer()
    local backdrop, panels
    local steps = {}
    local function add(step)
        table.insert(steps, step)
    end

    add(function()
        backdrop, panels = createPanels(player)
        return 10
    end)
    for _, female in ipairs({ false, true }) do
        local sex = female and "female" or "male"
        add(function()
            setLook(player, female)
            return 30
        end)
        for _, fullType in ipairs(AIDS) do
            add(function()
                takeOffAids(player)
                HearingAidDebug.wear(player, player:getInventory():AddItem(fullType))
                for _, panel in ipairs(panels) do
                    panel:setCharacter(player)
                end
                return 60
            end)
            add(function()
                local itemType = string.match(fullType, "%.(.+)$")
                getCore():TakeFullScreenshot("art_" .. sex .. "_" .. itemType .. ".png")
                print("HearingAidArt saved art_" .. sex .. "_" .. itemType .. ".png")
                return 10
            end)
        end
    end
    add(function()
        backdrop:removeFromUIManager()
        takeOffAids(player)
        local square = groundSquare(player)
        for i, fullType in ipairs(TIERS) do
            square:AddWorldInventoryItem(instanceItem(fullType), 0.4, 0.15 + 0.22 * (i - 1), 0)
        end
        for _ = 1, 8 do
            getCore():doZoomScroll(0, -1)
        end
        return 240
    end)
    add(function()
        getCore():TakeFullScreenshot("art_ground.png")
        print("HearingAidArt saved art_ground.png")
        return 10
    end)
    runSteps(steps, onDone)
end
