local skynet    = require "skynet.manager"
local GLConfig = {}

GLConfig.iServerVersion = 1

function GLConfig:isFormalMode()
	local pFormalValue = tonumber(skynet.getenv("normal") or 0) or 0
	return 1 == pFormalValue
end

function GLConfig:onGetServerVersion()
	return GLConfig.iServerVersion
end

function GLConfig:onGetGameCode()
	local pGameCode = tonumber(skynet.getenv("level"))
	return pGameCode
end

return GLConfig