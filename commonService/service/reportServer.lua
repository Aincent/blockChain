local skynet = require "skynet"
local json = require("cjson")

local reportServer = {}

function reportServer:onGetCurDate()
	return os.date("%Y/%m/%d", os.time())
end

function reportServer:init(pGameCode)
	self.m_redisClientsMgr = require("utils/redisClientsMgr")
	self.m_redisClientsMgr:init()
	
	self.m_pServerConfig = require(onGetServerConfigFile(pGameCode))
	-- 初始化userInfoRedis
	self.m_redisClientsMgr:addRedisClient(DefineType.REDIS_MTKEY, self.m_pServerConfig.iGameIpPortConfig.iTableRedisConfig)
end

-- 上报DAU
function reportServer:onDealDAU(pUserId)
	-- 确定日期
	local pDay = self:onGetCurDate()
	local pKey = string.format("UserLoginCount_%s_%s", pUserId, pDay)
	local pRet = self:onExecuteRedisCmd(DefineType.REDIS_MTKEY, "Incr", pKey)
	self:onExecuteRedisCmd(DefineType.REDIS_MTKEY, "EXPIRE", pKey, 2 * 24 * 60 * 60)
	if pRet and 1 == pRet then
		local pKey = string.format("DAUCount_%s", pDay)
		self:onExecuteRedisCmd(DefineType.REDIS_MTKEY, "Incr", pKey)
		self:onExecuteRedisCmd(DefineType.REDIS_MTKEY, "EXPIRE", pKey, 2 * 24 * 60 * 60)
	end
end

-- -- 上报牌局，玩牌人数，局数
-- function reportServer:onDealGameRound(pConf)
-- 	local pDay = self:onGetCurDate()
-- 	for _, kUserId in pairs(pConf.iUserIdTable) do
-- 		local pKey = string.format("UserPlayCount_%s_%s", kUserId, pDay)
-- 		local pRet = self:onExecuteRedisCmd(DefineType.REDIS_MTKEY, "Incr", pKey)
-- 		self:onExecuteRedisCmd(DefineType.REDIS_MTKEY, "EXPIRE", pKey, 2 * 24 * 60 * 60)
-- 		if pRet and 1 == pRet then
-- 			local pKey = string.format("UserCount_%s", pDay)
-- 			self:onExecuteRedisCmd(DefineType.REDIS_MTKEY, "Incr", pKey)
-- 			self:onExecuteRedisCmd(DefineType.REDIS_MTKEY, "EXPIRE", pKey, 2 * 24 * 60 * 60)
-- 		end
-- 	end
-- 	local pKey = string.format("GameCount_%s", pDay)
-- 	self:onExecuteRedisCmd(DefineType.REDIS_MTKEY, "Incrby", pKey, pConf.iBattleCurRound)
-- 	self:onExecuteRedisCmd(DefineType.REDIS_MTKEY, "EXPIRE", pKey, 2 * 24 * 60 * 60)
-- 	pKey = string.format("GameCount_0x%04x_%s", pConf.iLocalGameType, pDay)
-- 	self:onExecuteRedisCmd(DefineType.REDIS_MTKEY, "Incrby", pKey, pConf.iBattleCurRound)
-- 	self:onExecuteRedisCmd(DefineType.REDIS_MTKEY, "EXPIRE", pKey, 2 * 24 * 60 * 60)
-- 	pKey = string.format("GameRoundCount_0x%04x_%s_%s", pConf.iLocalGameType, pConf.iBattleTotalRound, pDay)
-- 	self:onExecuteRedisCmd(DefineType.REDIS_MTKEY, "Incr", pKey)
-- 	self:onExecuteRedisCmd(DefineType.REDIS_MTKEY, "EXPIRE", pKey, 2 * 24 * 60 * 60)
-- end

-- -- 上报在线，在玩
-- function reportServer:onDealOnlineAndPlay(pTable)
-- 	local pDay = self:onGetCurDate()
-- 	local pKey = string.format("OnlineAndPlay_%s", pDay)
-- 	local pJsonStr = json.encode(pTable)
-- 	self:onExecuteRedisCmd(DefineType.REDIS_MTKEY, "LPUSH", pKey, pJsonStr)
-- 	self:onExecuteRedisCmd(DefineType.REDIS_MTKEY, "EXPIRE", pKey, 2 * 24 * 60 * 60)
-- end

-- 上报新增
function reportServer:onDealNewAddUser(pUserId)
	-- 确定日期
	local pDay = self:onGetCurDate()
	local pKey = string.format("NewAddCount_%s", pDay)
	self:onExecuteRedisCmd(DefineType.REDIS_MTKEY, "Incr", pKey)
	self:onExecuteRedisCmd(DefineType.REDIS_MTKEY, "EXPIRE", pKey, 2 * 24 * 60 * 60)
end

----------------------------------- redis ---------------------------------
function reportServer:onExecuteRedisCmd(redis, cmd, ...)
	local pFmt = ""
	local arg = {...}
	for i = 1, #arg do
		pFmt = pFmt.."%s "
	end
	local pStr = string.format(pFmt, ...)
	Log.d(TAG, "onExecuteRedisCmd %s %s %s", redis, cmd, pStr)
	if self.m_redisClientsMgr[cmd] then
		local pRetRedis = self.m_redisClientsMgr[cmd](self.m_redisClientsMgr, redis, ...)
		if pRetRedis and type(pRetRedis) == "table" then
			Log.dump(TAG, pRetRedis, "pRetRedis")
		else
			Log.d(TAG, "pRetRedis[%s]", pRetRedis)
		end
		return pRetRedis
	else
		Log.e(TAG, "unknow cmd[%s]", cmd)
		return -1
	end
end

skynet.start(function()
	skynet.dispatch("lua", function(_, _, command, ...)
		reportServer[command](reportServer, ...)
	end)
end)