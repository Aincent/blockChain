
local skynet = require "skynet"
local ConfigServer = require("logic/configServer")

skynet.start(function()
	skynet.dispatch("lua", function(_, _, command, ...)
		if ConfigServer[command] then
			-- skynet.ret(skynet.pack(ConfigServer[command](ConfigServer,...)))
			ConfigServer[command](ConfigServer, ...)
		end
	end)
end)
