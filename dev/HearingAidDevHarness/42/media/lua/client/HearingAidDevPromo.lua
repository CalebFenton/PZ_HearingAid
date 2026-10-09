-- Development only; dev/run-debug-client.sh --promo runs it instead of the tests. It saves the raw
-- art that art/promo/compose.py lays out for the README and the Workshop page: screenshots named
-- promo_<shot>.png in <cachedir>/Screenshots, and <cachedir>/Lua/HearingAidPromo.json, which names
-- the regions of every screenshot. Shots of anything but the world are taken twice, on black
-- (promo_<shot>_k.png) and on white (promo_<shot>_w.png), so that art/promo/extract.py can recover
-- how transparent each pixel is.
require "ISUI/ISUI3DModel"
require "Vehicles/ISUI/ISUI3DScene"
require "HearingAid/Debug/HearingAidDebug"
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
    { name = "battery", fullType = "Base.Battery" },
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

-- JSON -------------------------------------------------------------------------------------------

-- Kahlua has no next(), so an empty table is the one whose pairs() yields nothing.
local function isArray(value)
    if value[1] ~= nil then
        return true
    end
    for _ in pairs(value) do
        return false
    end
    return true
end

local function encode(value, out)
    local kind = type(value)
    if kind == "table" then
        if isArray(value) then
            table.insert(out, "[")
            for i, element in ipairs(value) do
                if i > 1 then
                    table.insert(out, ",")
                end
                encode(element, out)
            end
            table.insert(out, "]")
        else
            local keys = {}
            for key in pairs(value) do
                table.insert(keys, tostring(key))
            end
            table.sort(keys)
            table.insert(out, "{")
            for i, key in ipairs(keys) do
                if i > 1 then
                    table.insert(out, ",")
                end
                encode(key, out)
                table.insert(out, ":")
                encode(value[key], out)
            end
            table.insert(out, "}")
        end
    elseif kind == "string" then
        local escaped = string.gsub(value, '[%c"\\]', function(c)
            return string.format("\\u%04x", string.byte(c))
        end)
        table.insert(out, '"' .. escaped .. '"')
    elseif kind == "number" or kind == "boolean" then
        table.insert(out, tostring(value))
    else
        table.insert(out, "null")
    end
end

local function writeJson(fileName, value)
    local out = {}
    encode(value, out)
    local writer = getFileWriter(fileName, true, false)
    writer:write(table.concat(out))
    writer:close()
end

-- Shots ------------------------------------------------------------------------------------------

local steps = {}
local shots = {}
local tinted = {}
local frozen = false

local function add(step)
    table.insert(steps, step)
end

local function region(name, x, y, w, h)
    return { name = name, x = math.floor(x), y = math.floor(y), w = math.floor(w), h = math.floor(h) }
end

local function elementRegion(name, element)
    return region(name, element:getAbsoluteX(), element:getAbsoluteY(), element:getWidth(), element:getHeight())
end

local function screenshot(file)
    getCore():TakeFullScreenshot(file .. ".png")
    print("HearingAidPromo saved " .. file .. ".png")
end

-- Every tinted element, the backdrop first, takes the backdrop colour.
local function setLevel(level)
    for _, element in ipairs(tinted) do
        element.backgroundColor = { r = level, g = level, b = level, a = 1 }
    end
end

-- Takes the shot on black and on white. regions() runs once the shot is laid out.
local function addMatted(name, regions)
    add(function()
        setLevel(0)
        return 10
    end)
    add(function()
        screenshot("promo_" .. name .. "_k")
        return 10
    end)
    add(function()
        setLevel(1)
        return 10
    end)
    add(function()
        screenshot("promo_" .. name .. "_w")
        table.insert(shots, { name = name, matte = true, regions = regions() })
        return 10
    end)
end

local function addOpaque(name, regions)
    add(function()
        screenshot("promo_" .. name)
        table.insert(shots, { name = name, matte = false, regions = regions() })
        return 10
    end)
end

local function newBackdrop()
    local backdrop = ISPanel:new(0, 0, getCore():getScreenWidth(), getCore():getScreenHeight())
    backdrop:initialise()
    backdrop:addToUIManager()
    backdrop:setVisible(true)
    tinted = { backdrop }
    return backdrop
end

local function removeBackdrop()
    add(function()
        tinted[1]:removeFromUIManager()
        return 1
    end)
end

-- Icons ------------------------------------------------------------------------------------------

local IconSheet = ISPanel:derive("HearingAidDevPromoIconSheet")

function IconSheet:render()
    for _, icon in ipairs(self.icons) do
        self:drawTextureScaled(icon.texture, icon.x, icon.y, icon.w, icon.h, 1, 1, 1, 1)
    end
end

local function addIcons()
    local sheet
    add(function()
        local backdrop = newBackdrop()
        sheet = IconSheet:new(100, 100, getCore():getScreenWidth() - 200, getCore():getScreenHeight() - 200)
        sheet:noBackground()
        sheet.icons = {}
        local x, y, rowHeight = 0, 0, 0
        local function place(name, texture)
            local w, h = texture:getWidthOrig(), texture:getHeightOrig()
            if x + w > sheet.width then
                x, y, rowHeight = 0, y + rowHeight + 32, 0
            end
            table.insert(sheet.icons, { name = name, texture = texture, x = x, y = y, w = w, h = h })
            x = x + w + 32
            rowHeight = math.max(rowHeight, h)
        end
        for _, icon in ipairs(ICONS) do
            place("icon_" .. icon.name, instanceItem(icon.fullType):getTex())
        end
        for _, trait in ipairs(TRAITS) do
            place("trait_" .. trait.name, CharacterTraitDefinition.getCharacterTraitDefinition(trait.trait):getTexture())
        end
        backdrop:addChild(sheet)
        return 10
    end)
    addMatted("icons", function()
        local regions = {}
        for _, icon in ipairs(sheet.icons) do
            table.insert(regions, region(icon.name, sheet:getAbsoluteX() + icon.x, sheet:getAbsoluteY() + icon.y, icon.w, icon.h))
        end
        return regions
    end)
    removeBackdrop()
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
    tinted[1]:addChild(panel)
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
    add(function()
        newBackdrop()
        local size = math.floor(math.min(getCore():getScreenWidth(), getCore():getScreenHeight()) / 2)
        local left = math.floor((getCore():getScreenWidth() - 2 * size) / 2)
        for i, view in ipairs(VIEWS) do
            panels[i] = newModelPanel(left + ((i - 1) % 2) * size, math.floor((i - 1) / 2) * size, size, player, view)
        end
        return 10
    end)
    for _, look in ipairs(LOOKS) do
        local sex = look.female and "female" or "male"
        local ear = look.female and "left" or "right"
        add(function()
            setLook(player, look)
            return 30
        end)
        for _, tier in ipairs(TIERS) do
            local name = table.concat({ "head", look.name, sex, ear, TIER_NAMES[tier] }, "_")
            add(function()
                frozen = false
                HearingAidDevArt.takeOffAids(player)
                local fullType = look.female and HearingAid.leftEarType(tier) or tier
                HearingAidDebug.wear(player, player:getInventory():AddItem(fullType))
                for i, view in ipairs(VIEWS) do
                    panels[i]:setDirection(view[ear])
                    panels[i]:setCharacter(player)
                end
                return 60
            end)
            add(function()
                frozen = true
                return 5
            end)
            addMatted(name, function()
                local regions = {}
                for i, view in ipairs(VIEWS) do
                    table.insert(regions, elementRegion(name .. "_" .. view.name, panels[i]))
                end
                return regions
            end)
        end
    end
    add(function()
        frozen = false
        HearingAidDevArt.takeOffAids(player)
        return 1
    end)
    removeBackdrop()
end

-- Models -----------------------------------------------------------------------------------------

-- The scene shows 1366 / zoomMult model units across however wide it is, about 0.28 at the closest
-- zoom (UI3DScene.calcMatrices), so a scene as wide as the screen draws the 8 cm aid biggest.
local function addModels()
    for _, tier in ipairs(TIERS) do
        local name = "model_" .. TIER_NAMES[tier]
        local scene
        add(function()
            local backdrop = newBackdrop()
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
            table.insert(tinted, scene)
            return 30
        end)
        addMatted(name, function()
            return { region(name, scene.width / 2 - 400, scene.height / 2 - 400, 800, 800) }
        end)
        removeBackdrop()
    end
end

-- Interface --------------------------------------------------------------------------------------

local function addTooltips()
    local player = getPlayer()
    local tooltips = {}
    add(function()
        newBackdrop()
        HearingAidDevArt.takeOffAids(player)
        local worn = HearingAidDebug.addAid(player, HearingAid.BOOSTED, 0.73, true)
        HearingAidDebug.wear(player, worn)
        local aids = {
            { name = "tooltip_broken", item = HearingAidDebug.addAid(player, HearingAid.BROKEN, nil, false) },
            { name = "tooltip_basic", item = HearingAidDebug.addAid(player, HearingAid.BASIC, 0.4, false) },
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
        return 30
    end)
    -- HearingAidTooltip.lua draws the battery strip below the vanilla tooltip, so each region
    -- reaches past it; compose.py trims the transparent margin.
    addMatted("tooltips", function()
        local regions = {}
        for name, tooltip in pairs(tooltips) do
            table.insert(regions, region(name, tooltip:getX(), tooltip:getY(), tooltip:getWidth() + 120, tooltip:getHeight() + 100))
        end
        return regions
    end)
    add(function()
        for _, tooltip in pairs(tooltips) do
            tooltip:removeFromUIManager()
        end
        HearingAidDevArt.takeOffAids(player)
        return 1
    end)
    removeBackdrop()
end

local function addWearMenu()
    local player = getPlayer()
    local context
    add(function()
        newBackdrop()
        local aid = HearingAidDebug.addAid(player, HearingAid.BASIC, 0.8, false)
        -- Away from the mouse, which would otherwise move the highlight.
        local x = getMouseX() < getCore():getScreenWidth() / 2 and 1300 or 300
        context = ISInventoryPaneContextMenu.createMenu(0, true, { aid }, x, 300)
        context:removeOptionByName("Debug")
        local wear = context:getOptionFromName(getText("ContextMenu_Wear"))
        -- ISContextMenu:render shows the submenu of the option at mouseOver while forceVisible is set.
        for i, option in ipairs(context.options) do
            if option == wear then
                context.mouseOver = i
            end
        end
        context.forceVisible = true
        return 30
    end)
    -- The menu with its Wear submenu open beside it.
    addMatted("menu", function()
        local sub = context.subMenu
        local x, y = context:getAbsoluteX(), math.min(context:getAbsoluteY(), sub:getAbsoluteY())
        local right = math.max(context:getAbsoluteX() + context:getWidth(), sub:getAbsoluteX() + sub:getWidth())
        local bottom = math.max(context:getAbsoluteY() + context:getHeight(), sub:getAbsoluteY() + sub:getHeight())
        return { region("menu_wear", x, y, right - x, bottom - y) }
    end)
    add(function()
        context:closeAll()
        return 1
    end)
    removeBackdrop()
end

-- World ------------------------------------------------------------------------------------------

local function squareCentre(square)
    local x, y, z = square:getX() + 0.5, square:getY() + 0.5, square:getZ()
    return isoToScreenX(0, x, y, z), isoToScreenY(0, x, y, z)
end

local function clampedRegion(name, cx, cy, w, h)
    local x = math.max(0, math.min(getCore():getScreenWidth() - w, cx - w / 2))
    local y = math.max(0, math.min(getCore():getScreenHeight() - h, cy - h / 2))
    return region(name, x, y, w, h)
end

-- A corpse next to the character with an aid among its things, and the loot window open on it.
local function addCorpse()
    local player = getPlayer()
    add(function()
        getGameTime():setTimeOfDay(12)
        setLook(player, LOOKS[2])
        HearingAidDebug.wear(player, HearingAidDebug.addAid(player, HearingAid.BASIC, 0.6, true))
        for _ = 1, 8 do
            getCore():doZoomScroll(0, -1)
        end
        return 60
    end)
    add(function()
        local square = HearingAidDevArt.groundSquare(player)
        local body = createRandomDeadBody(square, 0)
        HearingAid.setCharge(body:getContainer():AddItem(HearingAid.BASIC), 0.55)
        local loot = getPlayerLoot(0)
        loot:setVisible(true)
        loot:setPinned()
        local cx, cy = squareCentre(player:getCurrentSquare())
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
        return 240
    end)
    addOpaque("world_corpse", function()
        local x, y = squareCentre(player:getCurrentSquare())
        return { clampedRegion("world_corpse", x + 150, y - 60, 1260, 709) }
    end)
end

function HearingAidDevPromo.capture(onDone)
    -- Hides the HUD, the debug console and every other window; the shots add their own.
    ISUIHandler.setVisibleAllUI(false)
    addIcons()
    addHeads()
    addModels()
    addTooltips()
    addWearMenu()
    addCorpse()
    HearingAidDevArt.runSteps(steps, function()
        writeJson("HearingAidPromo.json", {
            screen = { w = getCore():getScreenWidth(), h = getCore():getScreenHeight() },
            shots = shots,
        })
        onDone()
    end)
end
