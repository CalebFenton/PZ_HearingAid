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

-- Sandbox option with the Electrical level each recipe needs.
local SKILL_OPTIONS = {
    ["HearingAid.RepairHearingAid"] = "RepairSkillLevel",
    ["HearingAid.OptimizeHearingAid"] = "OptimizeSkillLevel",
    ["HearingAid.BoostHearingAid"] = "BoostSkillLevel",
}

local function requiredLevel(recipe)
    if recipe:getRequiredSkillCount() == 0 then
        return 0
    end
    return recipe:getRequiredSkill(0):getLevel()
end

-- The can-craft check, craft time and crafting windows all read the recipe's skill list. Single
-- player, the server and every client each hold their own recipes, rebuilt from the scripts when
-- Lua reloads, so this runs everywhere once options load, and every minute because no event
-- fires when an admin changes sandbox options.
function HearingAid.Recipes.applySkillLevels()
    for recipeName, option in pairs(SKILL_OPTIONS) do
        local recipe = getScriptManager():getCraftRecipe(recipeName)
        local level = SandboxVars.HearingAid[option]
        if requiredLevel(recipe) ~= level then
            recipe:clearRequiredSkills()
            if level > 0 then
                recipe:addRequiredSkill(Perks.Electricity, level)
            end
        end
    end
end

Events.OnInitGlobalModData.Add(HearingAid.Recipes.applySkillLevels)
Events.EveryOneMinute.Add(HearingAid.Recipes.applySkillLevels)
