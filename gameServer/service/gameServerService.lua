
local skynet = require "skynet"
local GameServer = require("logic/gameServer")

skynet.start(function()
	skynet.dispatch("lua", function(_,_, command, ...)
		if GameServer[command] then
			skynet.ret(skynet.pack(GameServer[command](GameServer,...)))
		end
	end)
end)
