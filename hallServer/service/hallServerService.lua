
local skynet = require "skynet"
local HallServer = require("logic/hallServer")

skynet.start(function()
	skynet.dispatch("lua", function(_,_, command, ...)
		skynet.ret(skynet.pack(HallServer[command](HallServer,...)))
	end)
end)
