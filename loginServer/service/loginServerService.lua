
local skynet = require "skynet"
local LoginServer = require("logic/loginServer")

skynet.start(function()
	skynet.dispatch("lua", function(_,_, command, ...)
		skynet.ret(skynet.pack(LoginServer[command](LoginServer,...)))
	end)
end)
