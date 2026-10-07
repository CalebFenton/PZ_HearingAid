require "HearingAid/HearingAid"

-- Callbacks of the craftRecipes in media/scripts/HearingAid_recipes.txt. OnCreate runs once, on
-- the authority, after the outputs were already sent to a multiplayer client.
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

-- The repaired or upgraded aid keeps the battery and switch of the one it was made from, which
-- also discards the battery its item OnCreate may have rolled.
function HearingAid.Recipes.transferState(craftRecipeData, character)
    local result = craftRecipeData:getFirstCreatedItem()
    HearingAid.copyState(consumedAid(craftRecipeData), result)
    result:syncItemFields()
end

function HearingAid.Recipes.returnBattery(craftRecipeData, character)
    local aid = consumedAid(craftRecipeData)
    if HearingAid.hasBattery(aid) then
        HearingAid.removeBattery(character, aid)
    end
end

-- OnTest and OnAddToMenu of BoostHearingAid. The game reads OnAddToMenu as a plain global name.
function HearingAid_isBoostEnabled()
    return SandboxVars.HearingAid.EnableBoosted
end
