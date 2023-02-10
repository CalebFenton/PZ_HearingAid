-- This is a little ugly since it's duplicated from manager.
local HA_WORKING_FULL_TYPES = {"hearing_aid.InefficientHearingAid", "hearing_aid.EfficientHearingAid", "hearing_aid.BoostedHearingAid"}

local function isWorkingHearingAid(item)
	local fullType = item:getFullType();
	for _, workingType in ipairs(HA_WORKING_FULL_TYPES) do
		if fullType == workingType then
			return true;
		end
	end
	return false;
end

function HearingAid_DismantleHearingAid(items, result, player)
	for i=1, items:size() do
		local item = items:get(i-1);
		if isWorkingHearingAid(item) and item:getModData()[HA_HAS_BATTERY] == true then
			local battery = InventoryItemFactory.CreateItem("Base.Battery");
			battery:setUsedDelta(item:getModData()[HA_BATTERY_LEVEL]);
			player:getInventory():AddItem(battery);
			break
		end
	end
end
