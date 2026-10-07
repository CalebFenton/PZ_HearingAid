require "NPCs/BodyLocations"
require "TimedActions/ISWearClothing"

-- The location is registered in media/registries.lua. It must also exist in the "Human" group,
-- otherwise WornItems.setItem dereferences a missing location when the item is worn.
local location = ItemBodyLocation.get(ResourceLocation.of("hearingaid:hearingaid"))
local group = BodyLocations.getGroup("Human")

group:getOrCreateLocation(location)
-- Render right after earrings (locations are declared in render order).
group:moveLocationToIndex(location, group:indexOf(ItemBodyLocation.EAR_TOP) + 1)
-- Hoods hide it, same as vanilla earrings.
group:setHideModel(ItemBodyLocation.JACKET_HAT, location)
group:setHideModel(ItemBodyLocation.JACKET_HAT_BULKY, location)
group:setHideModel(ItemBodyLocation.SWEATER_HAT, location)

WearClothingAnimations[location] = "Face"
