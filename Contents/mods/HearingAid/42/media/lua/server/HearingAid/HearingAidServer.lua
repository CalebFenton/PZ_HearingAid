require "HearingAid/HearingAid"

-- Authority side (single player, or the dedicated server). Server Lua also loads on MP clients;
-- every handler bails out there.

local function onEveryOneMinute()
    HearingAid.update()
end

local function onClothingUpdated(character)
    if not isClient() and instanceof(character, "IsoPlayer") then
        HearingAid.reconcile(character)
    end
end

local function onCreatePlayer(playerNum, player)
    if not isClient() then
        HearingAid.reconcile(player)
    end
end

local function onClientCommand(module, command, player, args)
    if module == "HearingAid" and command == "reconcile" then
        HearingAid.reconcile(player)
    end
end

Events.EveryOneMinute.Add(onEveryOneMinute)
Events.OnClothingUpdated.Add(onClothingUpdated)
Events.OnCreatePlayer.Add(onCreatePlayer)
Events.OnClientCommand.Add(onClientCommand)
