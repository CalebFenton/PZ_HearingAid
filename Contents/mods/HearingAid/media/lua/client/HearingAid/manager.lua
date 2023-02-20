local versionNumber = 1.0;

if HearingAidManager then
	if HearingAidManager.versionNumber >= versionNumber then
		return;
	end
end

HearingAidManager = ISUIElement:derive("HearingAidManager");
HearingAidManager.versionNumber = versionNumber;
HearingAidManager.managers = {};
HearingAidManager.activeManagers = {};

local HA_WORKING_FULL_TYPES = {"hearing_aid.InefficientHearingAid", "hearing_aid.EfficientHearingAid", "hearing_aid.BoostedHearingAid"}
local HA_CHANGED_TRAITS = "hearing_aid_changed_traits";
local HA_ACTIVE = "hearing_aid_battery_active";
local HA_ACTIVE_TIME = "hearing_aid_battery_active_time";
local HA_INITIALIZED = "hearing_aid_battery_initialized";
local HA_BATTERY_MANAGER_VERSION = "hearing_aid_battery_version";
local HA_HAS_BATTERY = "hearing_aid_has_battery";
local HA_BATTERY_LEVEL = "hearing_aid_battery_level";
local HA_BATTERY_POWER_LEVEL = "hearing_aid_power_level";
local HA_HAS_ALTERNATE_POWER = "hearing_aid_has_alternate_power";

local function isWorkingHearingAid(item)
	local fullType = item:getFullType();
	for _, workingType in ipairs(HA_WORKING_FULL_TYPES) do
		if fullType == workingType then
			return true;
		end
	end
	return false;
end

local function buildActiveIndex(player)
    return player:getDisplayName() .. player:getPlayerNum()
end

local function getItemID(item)
	return item:getType() .. item:getID();
end

local function initializeHearingAid(itemID, player, item)
	local runTime = 400;
	if item:getFullType() == "hearing_aid.InefficientHearingAid" then
		runTime = 48;
	end
	local hearingAid = {
		player = player,
		item = item,
		runTime = runTime,
		target = nil,
		adjustablePower = false,
		itemWeightNoBattery = 0.01,
		itemWeightWithBattery = 0.11,
	};
	HearingAidManager.managers[itemID] = HearingAidManager:new(hearingAid);
	HearingAidManager.managers[itemID]:initialize();
end

local function createMenuHearingAid(playerID, context, items)
	for i, e in ipairs(items) do
        local item;
		local player = getPlayer(playerID);
        if instanceof(e, "InventoryItem") then item = e; else item = e.items[1]; end;

        if isWorkingHearingAid(item) then
            local itemID = getItemID(item);
            if not HearingAidManager.managers[itemID] then
                initializeHearingAid(itemID, player, item);
            end
            if item:isEquipped() then
				HearingAidManager.managers[itemID]:doActionMenu(context);
			end
            -- HearingAidLogic.batteryUIs[itemID]:doPowerLevelMenu(context);
            HearingAidManager.managers[itemID]:doBatteryMenu(context);
        end
    end
end

local function isValid(_, player, item)
	if player and item then
		return item:isEquipped();
	else
		return nil;
	end
	return false;
end

local function onActivate(_, player, item, manager)
	HearingAidManager.activeManagers[buildActiveIndex(player)] = manager;
	local handleDeafness = SandboxVars.HearingAid.HandleDeafness;
	local isBoosted = item:getFullType() == "hearing_aid.BoostedHearingAid";
    local traits = player:getTraits();
	local modData = item:getModData();
	modData[HA_CHANGED_TRAITS] = nil;
    if traits:contains("Deaf") then
		if handleDeafness == 2 then
			traits:remove("Deaf");
			if isBoosted then
				modData[HA_CHANGED_TRAITS] = {"Deaf", ""};
			else
				modData[HA_CHANGED_TRAITS] = {"Deaf", "HardOfHearing"};
				traits:add("HardOfHearing");
			end
		elseif handleDeafness == 3 then
			if isBoosted then
				modData[HA_CHANGED_TRAITS] = {"Deaf", "HardOfHearing"};
				traits:remove("Deaf");
				traits:add("HardOfHearing");
			end
		end
	elseif traits:contains("HardOfHearing") then
		traits:remove("HardOfHearing");
		if isBoosted then
			modData[HA_CHANGED_TRAITS] = {"HardOfHearing", "KeenHearing"};
			traits:add("KeenHearing");
		else
			modData[HA_CHANGED_TRAITS] = {"HardOfHearing", ""};
		end
	elseif traits:contains("KeenHearing") then
		-- Congrats! You already have great hearing.
	else
		if isBoosted then
			modData[HA_CHANGED_TRAITS] = {"", "KeenHearing"};
			traits:add("KeenHearing");
		else
			modData[HA_CHANGED_TRAITS] = {"", ""};
		end
	end

	if modData[HA_CHANGED_TRAITS] ~= nil then
		modData[HA_CHANGED_TRAITS][3] = player;
	end
end

local function onDeactivate(_, player, item, manager)
	HearingAidManager.activeManagers[buildActiveIndex(player)] = nil;
	local changedTraits = item:getModData()[HA_CHANGED_TRAITS];
	if changedTraits ~= nil then
		local removedTrait, addedTrait, activePlayer = changedTraits[1], changedTraits[2], changedTraits[3];
		if player ~= activePlayer then
			-- I think it's possible for this to happen if a player dies while wearing this
			error("HearingAid for " .. buildActiveIndex(activePlayer) .. " deactivated on " .. buildActiveIndex(player));
		end
		local traits = activePlayer:getTraits();
		if addedTrait ~= "" then
			traits:remove(addedTrait);
		end
		if removedTrait ~= "" then
			traits:add(removedTrait);
		end
	end
end

local function onBatteryDead(_, player, item, manager)
	onDeactivate(_, player, item, manager);
end

local function initHearingAid()
	for _, workingType in ipairs(HA_WORKING_FULL_TYPES) do
		HearingAidInventoryBar.registerItem(workingType, HA_BATTERY_LEVEL, getTextOrNull("IGUI_invpanel_Remaining") or "Remaining: ");
		HearingAidInventoryTooltip.registerItem(workingType, HA_BATTERY_LEVEL, getTextOrNull("IGUI_invpanel_Remaining") or "Remaining: ");
	end

	Events.OnFillInventoryObjectContextMenu.Add(createMenuHearingAid);
end

Events.OnGameStart.Add(initHearingAid);

function HearingAidManager:activate()
	local modData = self.item:getModData();
	if not modData[HA_ACTIVE] then
		modData[HA_ACTIVE] = true;
		modData[HA_ACTIVE_TIME] = getGameTime():getWorldAgeHours();
		onActivate(self.target, self.player, self.item, self);
		self:addToUIManager();
	end
end

function HearingAidManager:deactivate()
	local modData = self.item:getModData();
	if modData[HA_ACTIVE] == true then
		modData[HA_ACTIVE] = false;
		onDeactivate(self.target, self.player, self.item, self);
		self:removeFromUIManager();
	end
end

function HearingAidManager:doAction(action, item, item2, item3, item4, arg1, arg2, arg3, arg4)
	local action = HearingAidAction:new(self.player, self, action, item, item2, item3, item4, arg1, arg2, arg3, arg4);
	ISTimedActionQueue.add(action);
end

function HearingAidManager:doActionMenu(context)
	local isActive = self:isActive();
	local isValid = isValid(self.target, self.player, self.item);
	if not isActive and self:hasBattery() and self:hasPower() then
		context:addOption(getTextOrNull("ContextMenu_Turn_On") or "Activate", self, HearingAidManager.doAction, "Activate");
	elseif isActive then
		context:addOption(getTextOrNull("ContextMenu_Turn_Off") or "Deactivate", self, HearingAidManager.doAction, "Deactivate");
	end
end

local function predicateNotEmpty(item)
	return item:getUsedDelta() > 0
end

function HearingAidManager:doBatteryMenu(context)
	if self:hasBattery() then
		context:addOption(getTextOrNull("ContextMenu_Remove_Battery") or "Remove Battery", self, HearingAidManager.doAction, "RemoveBattery");
	else
		if self.player:getInventory():containsTypeRecurse("Battery") then
			local battery, batteryLevel;
			local addedSubmenu = false;
			local addBatteryOption = context:addOption(getTextOrNull("ContextMenu_AddBattery") or "Add Battery", self.item);
			local subcontext = context:getNew(context);
			context:addSubMenu(addBatteryOption, subcontext);

			local batteries = self.player:getInventory():getAllTypeEvalRecurse("Battery", predicateNotEmpty);
			for i = 0, batteries:size() - 1 do
				battery = batteries:get(i);
				batteryLevel = math.floor(battery:getUsedDelta() * 100);
				if batteryLevel > 0 then
					subcontext:addOption(battery:getName() .. " (" .. batteryLevel .. "%)", self, HearingAidManager.doAction, "AddBattery", battery);
					addedSubmenu = true;
				end
			end
			if not addedSubmenu then context:removeLastOption(); end;
		end
	end
end

-- function HearingAidManager:doPowerLevelMenu(_context)
-- 	if self.adjustablePower then
-- 		local powerLevel;
-- 		local powerOption = _context:addOption(getTextOrNull("IGUI_RadioPower") or "Power", self.item);
-- 		local subcontext = _context:getNew(_context);
-- 		_context:addSubMenu(powerOption, subcontext);
-- 		for i = 1, 10 do
-- 			powerLevel = i / 10;
-- 			if self.item:getModData()[BATTERY_UI_POWER_LEVEL] == powerLevel then
-- 				subcontext:addOption("["..(i * 10).."%]", self, HearingAidManager.doAction, "SetPowerLevel", nil, nil, nil, nil, powerLevel);
-- 			else
-- 				subcontext:addOption((i * 10).."%", self, HearingAidManager.doAction, "SetPowerLevel", nil, nil, nil, nil, powerLevel);
-- 			end;
-- 		end;
-- 	end;
-- end

function HearingAidManager:getPlayer()
	return self.player;
end

function HearingAidManager:getItem()
	return self.item;
end

function HearingAidManager:hasAlternatePower()
	return self.item:getModData()[HA_HAS_ALTERNATE_POWER] or false;
end

function HearingAidManager:isActive()
	return self.item:getModData()[HA_ACTIVE] == true;
end

function HearingAidManager:hasPower()
	return self.item:getModData()[HA_BATTERY_LEVEL] > 0 or false;
end

function HearingAidManager:hasBattery()
	return self.item:getModData()[HA_HAS_BATTERY] or false;
end

function HearingAidManager:addBattery(battery)
	self.item:getModData()[HA_HAS_BATTERY] = true;
	self.item:getModData()[HA_BATTERY_LEVEL] = battery:getUsedDelta();
	self.item:setActualWeight(self.itemWeightWithBattery);
	self.item:setCustomWeight(true);
	self.player:getInventory():DoRemoveItem(battery);
end

-- function HearingAidManager:updateActiveState()
-- 	local isActive = self.isActive(self.target, self.player, self.item);
-- 	if (self.item:getModData()[HA_ACTIVE] == true) and not isActive then
-- 		self:deactivate();
-- 		isActive = false;
-- 	end
-- 	self.item:getModData()[HA_ACTIVE] = isActive;
-- 	return isActive;
-- end

function HearingAidManager:removeBattery()
	local battery = InventoryItemFactory.CreateItem("Base.Battery");
	battery:setUsedDelta(self.item:getModData()[HA_BATTERY_LEVEL]);
	self.player:getInventory():AddItem(battery);
	self.item:getModData()[HA_HAS_BATTERY] = false;
	self.item:getModData()[HA_BATTERY_LEVEL] = 0;
	self.item:setActualWeight(self.itemWeightNoBattery);
	self.item:setCustomWeight(true);
	self:deactivate();
end

-- function HearingAidManager:getPowerLevel()
-- 	return self.item:getModData()[BATTERY_UI_POWER_LEVEL];
-- end

-- function HearingAidManager:setPowerLevel(powerLevel)
-- 	self.item:getModData()[BATTERY_UI_POWER_LEVEL] = powerLevel;
-- end

function HearingAidManager:prerender()
	--TODO: HUD battery meter?
end

function HearingAidManager:render()
	--TODO: HUD battery meter?
end

LuaEventManager.AddEvent("UI_Update");

function HearingAidManager:update()
	local isValid = isValid(self.target, self.player, self.item);
	if not isValid then self:deactivate(isValid == nil); return; end;
	if self:isActive() then
		-- local powerLevel = self.item:getModData()[BATTERY_UI_POWER_LEVEL] or 1;
		local powerLevel = 1;
		local batteryLevel = self.item:getModData()[HA_BATTERY_LEVEL] or 0;
		local reductionThisFrame = 0;

		local isPaused = UIManager.getSpeedControls() and UIManager.getSpeedControls():getCurrentGameSpeed() == 0;
		if isPaused then
			return
		end
		if batteryLevel > 0 then
			local worldTime = getGameTime():getWorldAgeHours();
			local activeTime = self.item:getModData()[HA_ACTIVE_TIME];
			-- TODO: make runtime configurable
			reductionThisFrame = powerLevel * ((worldTime - activeTime) / self.runTime);
			batteryLevel = batteryLevel - reductionThisFrame;
			if batteryLevel < 0 then batteryLevel = 0; end;
			if batteryLevel == 0 then
				self.item:getModData()[HA_ACTIVE] = false;
				onBatteryDead(self.target, self.player, self.item, self);
			end
			self.item:getModData()[HA_BATTERY_LEVEL] = batteryLevel;
			self.item:getModData()[HA_ACTIVE_TIME] = worldTime;
			-- print("activeTime " ..activeTime);
			-- print("worldTime " ..worldTime);
			-- print("powerLevel = "..powerLevel);
			-- print("batterylevel = "..batterylevel);
			-- print("reductionThisFrame = "..reductionThisFrame);
		end
	end

	triggerEvent("UI_Update");
end

function HearingAidManager:initialize()
	-- EURO SPELLING DETECTED
	ISUIElement.initialise(self);
	local modData = self.item:getModData();
	local alreadyInitialized = modData[HA_INITIALIZED];
	local shouldUpgrade = not modData[HA_BATTERY_MANAGER_VERSION] or modData[HA_BATTERY_MANAGER_VERSION] < versionNumber;
	if not alreadyInitialized or shouldUpgrade then
		-- May have had battery when upgrading
		local hadBattery = modData[HA_HAS_BATTERY];
		local hasBattery = hadBattery or (alreadyInitialized and ZombRandBetween(0, 10) < 2);
		modData[HA_BATTERY_MANAGER_VERSION] = versionNumber;
		modData[HA_ACTIVE] = false;
		modData[HA_HAS_BATTERY] = hasBattery;
		modData[HA_BATTERY_LEVEL] = (hadBattery and 1) or (hasBattery and (ZombRandBetween(0, 10) / 10));
		modData[HA_BATTERY_POWER_LEVEL] = 1;
		modData[HA_INITIALIZED] = true;
	end
	if self:hasBattery() then
		self.item:setActualWeight(self.itemWeightWithBattery);
	else
		self.item:setActualWeight(self.itemWeightNoBattery);
	end
	self.item:setCustomWeight(true);
end

function HearingAidManager:new(item)
	local x, y, width, height = 0, 0, 0, 0;
	local o = ISUIElement:new(x, y, width, height);
	setmetatable(o, self);
	self.__index = self;
	for k, v in pairs(item) do o[k] = v; end;
	o.target = o.target or {};
	return o;
end

HearingAidManager.DismantleHearingAid = function(items, result, player)
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

HearingAidManager.IsBoostValid = function(item)
	return SandboxVars.HearingAid.EnableBoosted == true;
end
