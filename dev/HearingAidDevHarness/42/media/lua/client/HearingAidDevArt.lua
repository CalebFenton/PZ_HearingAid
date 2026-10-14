-- Development only; dev/run-debug-client.sh --art runs it instead of the tests. It saves close-ups
-- of the art to <cachedir>/Screenshots: art_<sex>_<item type>.png shows a bald character wearing
-- that aid from each side, drawn by the character preview panel of the character creation
-- screen, and art_ground.png shows each tier on the ground at the closest zoom.
require "ISUI/ISUI3DModel"
local Debug = require "HearingAid/Debug/HearingAidDebug"
local Capture = require "PZHarness/Capture"

HearingAidDevArt = {}

-- The preview panel shows (25 - zoom) / sqrt(2048) model units above and below its centre, and
-- the y offset moves the character down, so these frame the head.
HearingAidDevArt.ZOOM = 19
HearingAidDevArt.Y_OFFSET = -0.88
local DIRECTIONS = { IsoDirections.E, IsoDirections.S, IsoDirections.W, IsoDirections.N }
-- Both ears' items share a ground model, so the ground shows each tier once.
HearingAidDevArt.TIERS = { HearingAid.BROKEN, HearingAid.BASIC, HearingAid.EFFICIENT, HearingAid.BOOSTED }
local TIERS = HearingAidDevArt.TIERS
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

function HearingAidDevArt.takeOffAids(player)
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
function HearingAidDevArt.groundSquare(player)
    local here = player:getCurrentSquare()
    for _, direction in ipairs({ IsoDirections.S, IsoDirections.E, IsoDirections.W, IsoDirections.N }) do
        local square = here:getAdjacentSquare(direction)
        if square and square:isFree(false) and not here:isBlockedTo(square) then
            return square
        end
    end
    return here
end

-- Scrolls the world view to the closest zoom; Capture.zoomSettled() waits until it gets there.
function HearingAidDevArt.zoomToClosest()
    for _ = 1, 8 do
        getCore():doZoomScroll(0, -1)
    end
end

-- UI drawings for a preview to show a new look or model. Models load on another thread, which Lua
-- can't watch, and a preview keeps drawing the old model until the new one has loaded.
HearingAidDevArt.MODEL_FRAMES = 10

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
        panel:setZoom(HearingAidDevArt.ZOOM)
        panel:setYOffset(HearingAidDevArt.Y_OFFSET)
        panel:setCharacter(player)
        table.insert(panels, panel)
    end
    return backdrop, panels
end

function HearingAidDevArt.capture(onDone)
    local run = Capture.new("HearingAidArt")
    local player = getPlayer()
    local backdrop, panels

    run:add(function()
        backdrop, panels = createPanels(player)
        return Capture.drawn(Capture.DRAW_FRAMES)
    end)
    for _, female in ipairs({ false, true }) do
        local sex = female and "female" or "male"
        run:add(function()
            setLook(player, female)
            return Capture.drawn(HearingAidDevArt.MODEL_FRAMES)
        end)
        for _, fullType in ipairs(AIDS) do
            run:add(function()
                HearingAidDevArt.takeOffAids(player)
                Debug.wear(player, player:getInventory():AddItem(fullType))
                for _, panel in ipairs(panels) do
                    panel:setCharacter(player)
                end
                return Capture.drawn(HearingAidDevArt.MODEL_FRAMES)
            end)
            run:add(function()
                run:screenshot("art_" .. sex .. "_" .. string.match(fullType, "%.(.+)$"))
            end)
        end
    end
    run:add(function()
        backdrop:removeFromUIManager()
        HearingAidDevArt.takeOffAids(player)
        local square = HearingAidDevArt.groundSquare(player)
        for i, fullType in ipairs(TIERS) do
            square:AddWorldInventoryItem(instanceItem(fullType), 0.4, 0.15 + 0.22 * (i - 1), 0)
        end
        HearingAidDevArt.zoomToClosest()
        return Capture.zoomSettled()
    end)
    -- The world draws every frame, the item models once they have loaded.
    run:add(function()
        return Capture.DRAW_FRAMES
    end)
    run:add(function()
        run:screenshot("art_ground")
    end)
    run:run(nil, onDone)
end
