require "HearingAid/HearingAid"
require "TimedActions/ISWearClothing"

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

Events.EveryOneMinute.Add(HearingAid.update)
Events.OnClothingUpdated.Add(onClothingUpdated)
Events.OnCreatePlayer.Add(onCreatePlayer)
