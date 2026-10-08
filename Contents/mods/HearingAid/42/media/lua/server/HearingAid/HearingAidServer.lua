require "HearingAid/HearingAid"
require "TimedActions/ISWearClothing"
require "TimedActions/ISClothingExtraAction"

-- Event handlers for the authority. Server Lua also loads on multiplayer clients, where
-- HearingAid.update() and HearingAid.reconcile() return without doing anything.

local function onClothingUpdated(character)
    if instanceof(character, "IsoPlayer") then
        HearingAid.reconcile(character)
    end
end

local function onCreatePlayer(playerNum, player)
    HearingAid.reconcile(player)
end

-- ISWearClothing fires OnClothingUpdated from perform(), which runs before complete() puts the
-- item on, and a dedicated server runs only complete(). Wearing a broken aid also matters: it
-- takes the slot from a working one.
local vanillaWearComplete = ISWearClothing.complete

function ISWearClothing:complete()
    local worn = vanillaWearComplete(self)
    if worn and HearingAid.isHearingAid(self.item) then
        HearingAid.reconcile(self.character)
    end
    return worn
end

-- Wear > on Right Ear / on Left Ear replaces the aid with a new item of the chosen ear's type,
-- which takes over its modData and is billed from the next update, so the old item's use is billed
-- first. Vanilla fires OnClothingUpdated once the new item is on, which reconciles hearing.
local vanillaExtraComplete = ISClothingExtraAction.complete

function ISClothingExtraAction:complete()
    if HearingAid.isHearingAid(self.item) then
        HearingAid.drainUntilNow(self.character, self.item)
    end
    return vanillaExtraComplete(self)
end

Events.EveryOneMinute.Add(HearingAid.update)
Events.OnClothingUpdated.Add(onClothingUpdated)
Events.OnCreatePlayer.Add(onCreatePlayer)
