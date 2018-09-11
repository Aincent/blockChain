local skynet = require "skynet"
local json = require("cjson")
local ActivityServer = {}

local TAG = "ActivityServer"

function ActivityServer:init(pGameCode)
	self.m_redisClientsMgr = require("utils/redisClientsMgr")
	self.m_redisClientsMgr:init()
	
	-- self.m_pServerConfig = require(onGetServerConfigFile(pGameCode))

	-- 初始化
	-- self.m_redisClientsMgr:addRedisClient(DefineType.REDIS_BILLLIST, self.m_pServerConfig.iGameIpPortConfig.iBillListRedisConfig)
end

skynet.start(function()
	skynet.dispatch("lua", function(_,_, command, ...)
		if ActivityServer[command] then
			-- skynet.ret(skynet.pack(ActivityServer[command](ActivityServer,...)))
			ActivityServer[command](ActivityServer,...)
		end
	end)
end)
