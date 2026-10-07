-- Shows the battery warnings that a multiplayer server sends with HearingAid.notify().

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

Events.OnServerCommand.Add(onServerCommand)
