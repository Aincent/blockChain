local skynet = require "skynet"
local json = require("cjson")
local BillServer = {}

local TAG = "BillServer"

function BillServer:init(pGameCode)
	self.m_redisClientsMgr = require("utils/redisClientsMgr")
	self.m_redisClientsMgr:init()

	self.m_pServerConfig = require(onGetServerConfigFile(pGameCode))

	-- 初始化
	self.m_redisClientsMgr:addRedisClient(DefineType.REDIS_BILLLIST, self.m_pServerConfig.iGameIpPortConfig.iBillListRedisConfig)

	self.m_pAllocServiceMgr = skynet.localname(".AllocServiceMgr")
	local pLookbackId = 10000000
	local pKey = string.format("BillLookbackId")
	local pRet = self:onExecuteRedisCmd(DefineType.REDIS_BILLLIST, "GET", pKey)
	if pRet and tonumber(pRet) > 0 then
		pLookbackId = tonumber(pRet)
	end
	local pRet = skynet.call(self.m_pAllocServiceMgr, "lua", "onSetLookbackId", pLookbackId)
end

function BillServer:onSetLookbackId(pLookbackId)
	local pKey = string.format("BillLookbackId")
	self:onExecuteRedisCmd(DefineType.REDIS_BILLLIST, "SET", pKey, pLookbackId)
end

function BillServer:ClientUserGetBillList(pAgent, reqest)
end

function BillServer:onServerAddUserOneBattleBill(pUserId, pBattleId)
end

function BillServer:onServerDelUserOneBattleBill(pUserId, pBattleId)
end

function BillServer:onServerUpdateOneBattleBillInfo(pBattleId, pInfoStr)
	if pBattleId and pInfoStr then
		local pKey = string.format("BillList_BattleId_%s", pBattleId)
		self:onExecuteRedisCmd(DefineType.REDIS_BILLLIST, "SET", pKey, pInfoStr)
		self:onExecuteRedisCmd(DefineType.REDIS_BILLLIST, "EXPIRE", pKey, 24 * 60 * 60)
	end
end

function BillServer:onServerUserSetBillDetail(pBattleId, pInfoStr)
	if pBattleId and pInfoStr then
		local pKey = string.format("BillDeatail_BattleId_%s", pBattleId)
		self:onExecuteRedisCmd(DefineType.REDIS_BILLLIST, "SET", pKey, pInfoStr)
		self:onExecuteRedisCmd(DefineType.REDIS_BILLLIST, "EXPIRE", pKey, 24 * 60 * 60)
	end
end

function BillServer:onServerUserSetBillLookback(pLookbackId, pInfoStr)
	if pLookbackId and pInfoStr then
		local pKey = string.format("BillLookback_LookbackId_%s", pLookbackId)
		self:onExecuteRedisCmd(DefineType.REDIS_BILLLIST, "SET", pKey, pInfoStr)
		self:onExecuteRedisCmd(DefineType.REDIS_BILLLIST, "EXPIRE", pKey, 24 * 60 * 60)
	end
end

function BillServer:onServerSetBillGoldFieldDetail(pInfoStr)
	if pInfoStr then
		local pKey = "GoldFieldBillDeatail"
		self:onExecuteRedisCmd(DefineType.REDIS_BILLLIST, "LPUSH", pKey, pInfoStr)
	end
end

----------------------------------- redis ---------------------------------
function BillServer:onExecuteRedisCmd(redis, cmd, ...)
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
	skynet.dispatch("lua", function(_,_, command, ...)
		if BillServer[command] then
			-- skynet.ret(skynet.pack(BillServer[command](BillServer,...)))
			BillServer[command](BillServer, ...)
		end
	end)
end)
