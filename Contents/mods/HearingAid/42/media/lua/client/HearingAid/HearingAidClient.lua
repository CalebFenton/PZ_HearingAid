require "HearingAid/HearingAid"

-- MP client side: the server owns hearing traits, so tell it when clothing changes and show
-- the battery warnings it sends back. Single player handles both in HearingAidServer.lua.

local function onClothingUpdated(character)
    if isClient() and instanceof(character, "IsoPlayer") and character:isLocalPlayer() then
        sendClientCommand(character, "HearingAid", "reconcile", {})
    end
end

local function onServerCommand(module, command, args)
    if module ~= "HearingAid" or command ~= "notify" then
        return
    end
    for i = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(i)
        if player and player:getOnlineID() == args.onlineID then
            HaloTextHelper.addBadText(player, getText(args.key))
        end
    end
end

Events.OnClothingUpdated.Add(onClothingUpdated)
Events.OnServerCommand.Add(onServerCommand)
