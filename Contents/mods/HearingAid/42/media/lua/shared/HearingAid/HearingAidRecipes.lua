require "HearingAid/HearingAid"

-- craftRecipe callbacks (media/scripts/HearingAid_recipes.txt). OnCreate runs once: locally in
-- single player, on the server in MP, after the outputs were already sent to the client.
HearingAid.Recipes = HearingAid.Recipes or {}

local function consumedAid(craftRecipeData)
    local items = craftRecipeData:getAllConsumedItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if HearingAid.isHearingAid(item) then
            return item
        end
    end
    return nil
end

-- Upgrades and repairs carry the battery and switch over. The output's item OnCreate may have
-- rolled a random battery; this overwrites it so crafting never creates batteries.
function HearingAid.Recipes.transferState(craftRecipeData, character)
    local source = consumedAid(craftRecipeData)
    local result = craftRecipeData:getFirstCreatedItem()
    if not source or not result then
        return
    end
    HearingAid.copyState(source, result)
    result:syncItemFields()
end

-- Gives back the battery that was inside the dismantled aid.
function HearingAid.Recipes.dismantle(craftRecipeData, character)
    local source = consumedAid(craftRecipeData)
    if not source or not HearingAid.isWorking(source) or not HearingAid.hasBattery(source) then
        return
    end
    local battery = instanceItem("Base.Battery")
    battery:setCurrentUsesFloat(HearingAid.getCharge(source))
    Actions.addOrDropItem(character, battery)
end

-- OnTest is called for every candidate input item; the sandbox switch gates the whole recipe.
function HearingAid.Recipes.boostEnabled(item, character)
    return HearingAid.sandbox().EnableBoosted ~= false
end

-- OnAddToMenu is looked up with a raw global read, so it cannot live in a table.
function HearingAid_BoostInMenu(params)
    return HearingAid.sandbox().EnableBoosted ~= false
end
