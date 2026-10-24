-- Development only; dev/run-debug-client.sh --promo runs it instead of the tests. It saves the raw
-- art that art/promo/compose.py lays out for the README and the Workshop page: screenshots named
-- promo_<shot>.png in <cachedir>/Screenshots, and <cachedir>/Lua/HearingAidPromo.json, which names
-- the regions of every screenshot and holds the item and option names in the game's language.
-- Shots of anything but the world are taken twice, on black and on white (PZHarness/Capture.lua).
-- The shots come in groups (dev/harness.conf's MODE_GROUPS_promo), and PROMO=<group>,... shoots
-- only those, so the extraction replaces only their captures.
require "ISUI/ISUI3DModel"
require "Vehicles/ISUI/ISUI3DScene"
local Debug = require "HearingAid/Debug/HearingAidDebug"
local Capture = require "PZHarness/Capture"
local Stage = require "PZHarness/Stage"
require "HearingAidDevArt"

HearingAidDevPromo = {}

local TIERS = HearingAidDevArt.TIERS
local TIER_NAMES = {
    [HearingAid.BROKEN] = "broken",
    [HearingAid.BASIC] = "basic",
    [HearingAid.EFFICIENT] = "efficient",
    [HearingAid.BOOSTED] = "boosted",
}
local GREY = ImmutableColor.new(0.78, 0.77, 0.74, 1)
-- A man wears his aid on the right ear and a woman hers on the left. The bald man shows the aid
-- best, and the grey-haired pair show it as it looks in play.
local LOOKS = {
    { name = "plain", female = false, hair = "Bald" },
    {
        name = "styled",
        female = false,
        hair = "Picard",
        colour = GREY,
        clothes = { "Base.Jumper_VNeck", "Base.Trousers_Suit", "Base.Shoes_Brown" },
    },
    {
        name = "styled",
        female = true,
        hair = "Bun",
        colour = GREY,
        clothes = { "Base.Jumper_RoundNeck", "Base.Skirt_Normal", "Base.Shoes_Black" },
    },
}
-- Preview panels in a two by two grid. The character faces these ways to show the ear from the
-- side, from behind and from the front, and the last panel zooms in on it from behind.
local HEAD_ZOOM = 20
local CLOSE_ZOOM = 23
local CLOSE_Y_OFFSET = -0.895
local VIEWS = {
    { name = "side", right = IsoDirections.E, left = IsoDirections.W },
    { name = "back", right = IsoDirections.NE, left = IsoDirections.NW },
    { name = "front", right = IsoDirections.SE, left = IsoDirections.SW },
    { name = "back_close", right = IsoDirections.NE, left = IsoDirections.NW, close = true },
}
local ICONS = {
    { name = "broken", fullType = HearingAid.BROKEN },
    { name = "basic", fullType = HearingAid.BASIC },
    { name = "efficient", fullType = HearingAid.EFFICIENT },
    { name = "boosted", fullType = HearingAid.BOOSTED },
    { name = "battery", fullType = HearingAid.BATTERY },
    { name = "screwdriver", fullType = "Base.Screwdriver" },
    { name = "tweezers", fullType = "Base.Tweezers" },
    { name = "reading_glasses", fullType = "Base.Glasses_Reading" },
    { name = "loupe", fullType = "Base.Loupe" },
    { name = "magnifying_glass", fullType = "Base.MagnifyingGlass" },
    { name = "scalpel", fullType = "Base.Scalpel" },
    { name = "earbuds", fullType = "Base.Earbuds" },
    { name = "alcohol_wipes", fullType = "Base.AlcoholWipes" },
    { name = "alcohol_cotton_balls", fullType = "Base.AlcoholedCottonBalls" },
    { name = "glue", fullType = "Base.Glue" },
    { name = "digital_watch", fullType = "Base.WristWatch_Left_DigitalBlack" },
    { name = "electric_wire", fullType = "Base.ElectricWire" },
    { name = "amplifier", fullType = "Base.Amplifier" },
    { name = "speaker", fullType = "Base.Speaker" },
    { name = "microphone", fullType = "Base.Microphone" },
    { name = "epoxy", fullType = "Base.Epoxy" },
    { name = "electronics_scrap", fullType = "Base.ElectronicsScrap" },
}
local TRAITS = {
    { name = "deaf", trait = CharacterTrait.DEAF },
    { name = "hard_of_hearing", trait = CharacterTrait.HARD_OF_HEARING },
    { name = "keen_hearing", trait = CharacterTrait.KEEN_HEARING },
}

-- Shots ------------------------------------------------------------------------------------------

-- The run whose steps are being added; HearingAidDevPromo.capture makes it.
local run
local region, elementRegion = Capture.region, Capture.elementRegion
local frozen = false

-- Icons ------------------------------------------------------------------------------------------

local function addIcons()
    run:addIconSheet("icons", function()
        local icons = {}
        for _, icon in ipairs(ICONS) do
            table.insert(icons, { name = "icon_" .. icon.name, texture = instanceItem(icon.fullType):getTex() })
        end
        for _, trait in ipairs(TRAITS) do
            local texture = CharacterTraitDefinition.getCharacterTraitDefinition(trait.trait):getTexture()
            table.insert(icons, { name = "trait_" .. trait.name, texture = texture })
        end
        return icons
    end)
end

-- Heads ------------------------------------------------------------------------------------------

local function newModelPanel(x, y, size, player, view)
    local panel = ISUI3DModel:new(x, y, size, size)
    -- The preview animates (breathes) unless the game is paused, and both mattes need the same pose.
    panel.prerender = function(self)
        ISUIElement.prerender(self)
        self.javaObject:setAnimate(not frozen)
    end
    panel:setVisible(true)
    run.tinted[1]:addChild(panel)
    panel:setState("idle")
    panel:setIsometric(false)
    panel:setZoom(view.close and CLOSE_ZOOM or HEAD_ZOOM)
    panel:setYOffset(view.close and CLOSE_Y_OFFSET or HearingAidDevArt.Y_OFFSET)
    -- Without a character before the first draw, AnimatedModel.updateInternal throws every frame.
    panel:setCharacter(player)
    return panel
end

-- Dresses the character in nothing but look.clothes, so that the scenario's random clothes and
-- glasses stay out of the shots.
local function setLook(player, look)
    player:setFemale(look.female)
    player:getDescriptor():setFemale(look.female)
    local visual = player:getHumanVisual()
    visual:setHairModel(look.hair)
    visual:setBeardModel("")
    if look.colour then
        visual:setHairColor(look.colour)
    end
    player:clearWornItems()
    for _, fullType in ipairs(look.clothes or {}) do
        local item = player:getInventory():AddItem(fullType)
        player:setWornItem(item:getBodyLocation(), item)
    end
    player:resetModel()
end

local function addHeads()
    local player = getPlayer()
    local panels = {}
    run:add(function()
        run:newBackdrop()
        local size = math.floor(math.min(getCore():getScreenWidth(), getCore():getScreenHeight()) / 2)
        local left = math.floor((getCore():getScreenWidth() - 2 * size) / 2)
        for i, view in ipairs(VIEWS) do
            panels[i] = newModelPanel(left + ((i - 1) % 2) * size, math.floor((i - 1) / 2) * size, size, player, view)
        end
        return Capture.drawn(Capture.DRAW_FRAMES)
    end)
    for _, look in ipairs(LOOKS) do
        local sex = look.female and "female" or "male"
        local ear = look.female and "left" or "right"
        run:add(function()
            setLook(player, look)
            return Capture.drawn(HearingAidDevArt.MODEL_FRAMES)
        end)
        for _, tier in ipairs(TIERS) do
            local name = table.concat({ "head", look.name, sex, ear, TIER_NAMES[tier] }, "_")
            run:add(function()
                frozen = false
                HearingAidDevArt.takeOffAids(player)
                local fullType = look.female and HearingAid.leftEarType(tier) or tier
                Debug.wear(player, player:getInventory():AddItem(fullType))
                for i, view in ipairs(VIEWS) do
                    panels[i]:setDirection(view[ear])
                    panels[i]:setCharacter(player)
                end
                return Capture.drawn(HearingAidDevArt.MODEL_FRAMES)
            end)
            run:add(function()
                frozen = true
                return Capture.drawn(Capture.DRAW_FRAMES)
            end)
            run:addMatted(name, function()
                local regions = {}
                for i, view in ipairs(VIEWS) do
                    table.insert(regions, elementRegion(name .. "_" .. view.name, panels[i]))
                end
                return regions
            end)
        end
    end
    run:add(function()
        frozen = false
        HearingAidDevArt.takeOffAids(player)
        return 1
    end)
    run:removeBackdrop()
end

-- Models -----------------------------------------------------------------------------------------

-- The scene shows 1366 / zoomMult model units across however wide it is, about 0.28 at the closest
-- zoom (UI3DScene.calcMatrices), so a scene as wide as the screen draws the 8 cm aid biggest.
local function addModels()
    for _, tier in ipairs(TIERS) do
        local name = "model_" .. TIER_NAMES[tier]
        local scene
        run:add(function()
            local backdrop = run:newBackdrop()
            scene = ISUI3DScene:new(0, 0, backdrop.width, backdrop.height)
            backdrop:addChild(scene)
            scene.borderColor = { r = 0, g = 0, b = 0, a = 0 }
            scene:setView("UserDefined")
            scene.javaObject:fromLua1("setMaxZoom", 20)
            scene.javaObject:fromLua1("setZoom", 20)
            scene.javaObject:fromLua3("setViewRotation", 50.0, 30.0, 0.0)
            scene.javaObject:fromLua1("setDrawGrid", false)
            scene.javaObject:fromLua1("setGizmoVisible", "none")
            scene.javaObject:fromLua2("createModel", "aid", "Base.HearingAid_Ground_" .. string.gsub(TIER_NAMES[tier], "^%l", string.upper))
            run:tint(scene)
            return Capture.drawn(HearingAidDevArt.MODEL_FRAMES)
        end)
        run:addMatted(name, function()
            return { region(name, scene.width / 2 - 400, scene.height / 2 - 400, 800, 800) }
        end)
        run:removeBackdrop()
    end
end

-- Interface --------------------------------------------------------------------------------------

local function addTooltips()
    local player = getPlayer()
    local tooltips = {}
    run:add(function()
        run:newBackdrop()
        HearingAidDevArt.takeOffAids(player)
        local worn = Debug.addAid(player, HearingAid.BOOSTED, 0.73, true)
        Debug.wear(player, worn)
        local aids = {
            { name = "tooltip_broken", item = Debug.addAid(player, HearingAid.BROKEN, nil, false) },
            { name = "tooltip_basic", item = Debug.addAid(player, HearingAid.BASIC, 0.4, false) },
            { name = "tooltip_boosted", item = worn },
        }
        for i, aid in ipairs(aids) do
            local tooltip = ISToolTipInv:new(aid.item)
            tooltip:initialise()
            tooltip.followMouse = false
            tooltip:setX(100 + (i - 1) * 650)
            tooltip:setY(300)
            tooltip:addToUIManager()
            tooltip:setVisible(true)
            tooltips[aid.name] = tooltip
        end
        return Capture.drawn(Capture.DRAW_FRAMES)
    end)
    -- HearingAidTooltip.lua draws the battery strip below the vanilla tooltip, so each region
    -- reaches past it; compose.py trims the transparent margin.
    run:addMatted("tooltips", function()
        local regions = {}
        for name, tooltip in pairs(tooltips) do
            table.insert(regions, region(name, tooltip:getX(), tooltip:getY(), tooltip:getWidth() + 120, tooltip:getHeight() + 100))
        end
        return regions
    end)
    run:add(function()
        for _, tooltip in pairs(tooltips) do
            tooltip:removeFromUIManager()
        end
        HearingAidDevArt.takeOffAids(player)
        return 1
    end)
    run:removeBackdrop()
end

-- The menu with its Wear submenu open beside it.
local function addWearMenu()
    Stage.addMenuShot(run, "menu_wear", function()
        local aid = Debug.addAid(getPlayer(), HearingAid.BASIC, 0.8, false)
        local context = ISInventoryPaneContextMenu.createMenu(0, true, { aid }, 300, 300)
        local wear = Stage.openSubMenu(context, getText("ContextMenu_Wear"))
        if not wear then
            return nil, "the hearing aid's Wear submenu"
        end
        return { context, wear }
    end)
end

-- World ------------------------------------------------------------------------------------------

local CORPSE_W, CORPSE_H = 1260, 709

-- A corpse next to the character with an aid among its things, and the loot window open on it.
local function addCorpse()
    local player = getPlayer()
    run:add(function()
        setLook(player, LOOKS[2])
        Debug.wear(player, Debug.addAid(player, HearingAid.BASIC, 0.6, true))
        return Stage.zoomOut(0)
    end)
    run:add(function()
        local square = HearingAidDevArt.groundSquare(player)
        local body = createRandomDeadBody(square, 0)
        HearingAid.setCharge(body:getContainer():AddItem(HearingAid.BASIC), 0.55)
        local loot = getPlayerLoot(0)
        loot:setVisible(true)
        loot:setPinned()
        local cx, cy = Stage.onScreen(player:getCurrentSquare())
        loot:setX(cx + 110)
        loot:setY(cy - 330)
        loot:setWidth(400)
        loot:setHeight(340)
        loot:refreshBackpacks()
        for _, button in ipairs(loot.backpacks) do
            if button.inventory == body:getContainer() then
                loot:selectContainer(button)
            end
        end
        return Capture.drawn(HearingAidDevArt.MODEL_FRAMES)
    end)
    run:addOpaque("world_corpse", function()
        local x, y = Stage.onScreen(player:getCurrentSquare())
        x, y = x + 150 - CORPSE_W / 2, y - 60 - CORPSE_H / 2
        return { Stage.screenRegion("world_corpse", x, y, x + CORPSE_W, y + CORPSE_H) }
    end)
end

-- The groups of dev/harness.conf's MODE_GROUPS_promo, and what adds their steps.
local GROUPS = {
    icons = addIcons,
    heads = addHeads,
    models = addModels,
    tooltips = addTooltips,
    menu = addWearMenu,
    world = addCorpse,
}

-- Shoots the groups named in `selection`, comma-separated in the order to shoot them, which
-- run-client.sh gives every group of MODE_GROUPS_promo when PROMO names none, and calls onDone.
function HearingAidDevPromo.capture(selection, onDone)
    run = Capture.new("HearingAidPromo")
    -- The layout's text, in the game's words, so a renamed item or option shows in the images. It
    -- comes with every run, since it costs no shot.
    local names = {}
    for _, icon in ipairs(ICONS) do
        names[icon.name] = getItemNameFromFullType(icon.fullType)
    end
    local data = {
        names = names,
        strings = {
            modName = getText("Sandbox_HearingAid"),
            rightEar = getText("ContextMenu_HearingAid_EarRight"),
            leftEar = getText("ContextMenu_HearingAid_EarLeft"),
            electrical = Perks.Electricity:getName(),
        },
    }
    -- Noon from the start: the world's light takes most of a second to follow the clock, and the
    -- world shot comes last.
    Stage.runGroups(run, selection, GROUPS, function()
        Stage.addWorldSettings(run, { hour = 12 })
    end, data, onDone)
end
