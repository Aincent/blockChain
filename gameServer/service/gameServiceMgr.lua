
local skynet = require "skynet.manager"
local codecache = require "skynet.codecache"
local cluster = require "skynet.cluster"
local clusterMonitor = require "utils/clusterMonitor"
local TAG = "GameServiceMgr"

local GameServiceMgr = {}

function GameServiceMgr:init(pGameCode, pIdentify)
	local pServerConfig = require(onGetServerConfigFile(pGameCode))
	self.m_pGameCode = pGameCode

	self.m_pHallServiceMgr = nil
	self.m_pAllocServiceMgr = nil

	-- 启动GameServer
	self.m_pGameServerTable = {}
	for _, v in pairs(pServerConfig.iGameRoomConfig) do
		local pGameLevel = v.iGameLevel
		self.m_pGameServerTable[pGameLevel] = {}
		Log.d(TAG, "启动GameServer level[%s]", pGameLevel)
		local pGameServer = skynet.newservice("gameServerService")
		self.m_pGameServerTable[pGameLevel] = pGameServer
		skynet.name(string.format(".GameServer_Level[%s]", pGameLevel), pGameServer)
		Log.d(TAG, "pGameServer = %s", pGameServer)
		local pRet = skynet.call(pGameServer, "lua", "init", pGameCode, pGameLevel)
	end

	Log.dump(TAG, self.m_pGameServerTable, "self.m_pGameServerTable")

	-- 启动reportServer
	self.m_pReportServerTable = {}
	local pReportServer = skynet.newservice("reportServer")
	table.insert(self.m_pReportServerTable, pReportServer)
	skynet.send(pReportServer, "lua", "init", pGameCode)

	self.m_pUserIdToGameServerMap = {}

	-- 启动定时器查看配置
	self.m_pScheduleMgr = require('utils/schedulerMgr')
	self.m_pScheduleMgr:init()

	-- 初始化redis
	self.m_redisClientsMgr = require("utils/redisClientsMgr")
	self.m_redisClientsMgr:init()
	
	self.m_redisClientsMgr:addRedisClient(DefineType.REDIS_USERINFO, pServerConfig.iGameIpPortConfig.iUserRedisConfig)
	self.m_redisClientsMgr:addRedisClient(DefineType.REDIS_MTKEY, pServerConfig.iGameIpPortConfig.iTableRedisConfig)
	self.m_redisClientsMgr:addRedisClient(DefineType.REDIS_CLUB, pServerConfig.iGameIpPortConfig.iClubRedisConfig)

	-- 确保自身数据初始化完毕再开启结点间链接
	clusterMonitor:onSubscribeNode(self.onConnectChange)
	clusterMonitor:onStart(pServerConfig.iClusterConfig)
	self.m_pClusterId =  clusterMonitor:onGetCurrentNodename()
	clusterMonitor:onOpen()
end

function GameServiceMgr:onGetGameServerByLevel(pLevel)
	return self.m_pGameServerTable[pLevel]
end

function GameServiceMgr:onUpdateGameServerData(data)
	self.m_pUserIdToGameServerMap[data.iUserId] = data.iGameServer
	self:onPrint()
end

function GameServiceMgr:onDeleteGameServerByUserId(pUserId)
	self.m_pUserIdToGameServerMap[pUserId] = nil
	self:onPrint("onDeleteGameServerByUserId")
end

function GameServiceMgr:onPrint(name)
	Log.d(TAG, name)
	Log.dump(TAG, self.m_pUserIdToGameServerMap, "self.m_pUserIdToGameServerMap")
end

function GameServiceMgr:onGetGameServerByUserId(pUserId)
	return pUserId and self.m_pUserIdToGameServerMap[pUserId] or nil
end

function GameServiceMgr:onGetGameServiceOnlineAndPlay()
	local pOnlineAndPlay = {
		iOnlineCount = 0,
		iPlayCount = 0,
	}

	for _, kGameServer in pairs(self.m_pGameServerTable) do
		local pRet = skynet.call(kGameServer, "lua", "onGetGameServerOnlineAndPlay")
		pOnlineAndPlay.iOnlineCount = pOnlineAndPlay.iOnlineCount + pRet.iOnlineCount
		pOnlineAndPlay.iPlayCount = pOnlineAndPlay.iPlayCount + pRet.iPlayCount
	end

	return pOnlineAndPlay
end

--------------------------------deal gamesever retire--------------------------------------------
function GameServiceMgr:onUnSubscribeGameServer()
	if self.m_pHallServiceMgr then
		return pcall(skynet.call, self.m_pHallServiceMgr, "lua", "onUnSubscribeGameServer", self.m_pClusterId)
	else
		Log.e(TAG, "hallservice disconnect error ")
	end
end

function GameServiceMgr:onCheckAbort()
	local isCanAbort = 0
	for _, kGameServer in pairs(self.m_pGameServerTable) do
		isCanAbort = isCanAbort + skynet.call(kGameServer, "lua", "onGateGameTableCount")
		if isCanAbort > 0 then
			break
		end
	end

	if isCanAbort == 0 then
		if self.m_pHallServiceMgr and self.m_pAllocServiceMgr then
			pcall(skynet.call, self.m_pHallServiceMgr, "lua", "onRetireGameServer", self.m_pClusterId)
			pcall(skynet.call, self.m_pAllocServiceMgr, "lua", "onRetireGameServer", self.m_pClusterId)
			--退出当前进程
			skynet.abort()
		end	
	end
end

function GameServiceMgr:onGameTableClear()
	for _, kGameServer in pairs(self.m_pGameServerTable) do
		local pRet = skynet.call(kGameServer, "lua", "onGameTableClear")
	end

	local pCallback = self.onCheckAbort
	self.m_pAbortStopTimer = self.m_pScheduleMgr:register(pCallback, 3 * 1000, -1, 3 * 1000, self)
end

function GameServiceMgr:onExecuteRedisCmd(redis, cmd, ...)
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

---------------------------reportServer------------------------------
function GameServiceMgr:onGetReportServer()
	return self.m_pReportServerTable[#self.m_pReportServerTable]
end

----------------------------------AllocService--------------------------------------------------
function GameServiceMgr:onCreateOneRoomId(pGameServer, pClubId, pPlayId)
	if self.m_pAllocServiceMgr then
		return pcall(skynet.call, self.m_pAllocServiceMgr, "lua", "onCreateOneRoomId", self.m_pClusterId ,pGameServer, pClubId, pPlayId)
	else
		Log.e(TAG, "allocservice disconnect error ")
	end
end

function GameServiceMgr:onDeleteOneRoomId(pRoomId, pClubId)
	if self.m_pAllocServiceMgr then
		pcall(skynet.call, self.m_pAllocServiceMgr, "lua", "onDeleteOneRoomId", pRoomId, pClubId)
	else
		Log.e(TAG, "allocservice disconnect error ")
	end
end

function GameServiceMgr:onGameTableStartGame(pRoomId, pClubId)
	if self.m_pAllocServiceMgr then
		pcall(skynet.call, self.m_pAllocServiceMgr, "lua", "onGameTableStartGame", pRoomId, pClubId)
	else
		Log.e(TAG, "allocservice disconnect error ")
	end
end

function GameServiceMgr:onCreateOneTableId()
	if self.m_pAllocServiceMgr then
		return pcall(skynet.call, self.m_pAllocServiceMgr, "lua", "onCreateOneTableId")
	else
		Log.e(TAG, "allocservice disconnect error ")
	end
end

function GameServiceMgr:onGetANewLookbackId()
	if self.m_pAllocServiceMgr then
		local pStatus, pLookBackId = pcall(skynet.call, self.m_pAllocServiceMgr, "lua", "onGetANewLookbackId") 
		if pStatus then
			return pLookBackId
		end
	else
		Log.e(TAG, "allocservice disconnect error ")
	end
end

function GameServiceMgr:onServerSetBillGoldFieldDetail(pInfoStr)
	if self.m_pAllocServiceMgr then
		pcall(skynet.call, self.m_pAllocServiceMgr, "lua", "onServerSetBillGoldFieldDetail", pInfoStr)
	else
		Log.e(TAG, "allocservice disconnect error ")
	end
end

function GameServiceMgr:onServerUpdateOneBattleBillInfo(pBattleId, pInfoStr)
	if self.m_pAllocServiceMgr then
		pcall(skynet.call, self.m_pAllocServiceMgr, "lua", "onServerUpdateOneBattleBillInfo", pBattleId, pInfoStr)
	else
		Log.e(TAG, "allocservice disconnect error ")
	end
end

function GameServiceMgr:onServerUserSetBillDetail(pBattleId, pInfoStr)
	if self.m_pAllocServiceMgr then
		pcall(skynet.call, self.m_pAllocServiceMgr, "lua", "onServerUserSetBillDetail", pBattleId, pInfoStr)
	else
		Log.e(TAG, "allocservice disconnect error ")
	end
end

function GameServiceMgr:onServerUserSetBillLookback(pLookbackId, pLookbackTable)
	if self.m_pAllocServiceMgr then
		pcall(skynet.call, self.m_pAllocServiceMgr, "lua", "onServerUserSetBillLookback", pLookbackId, pLookbackTable)
	else
		Log.e(TAG, "allocservice disconnect error ")
	end
end

----------------------------------------------------------------------------------------------
function GameServiceMgr:onSendPackageToHallServiceMgr(pName,pUserId, ...)
	Log.d(TAG, "onSendPackageToHallServiceMgr = %s ", pName)
	if self.m_pHallServiceMgr then
		return pcall(skynet.call, self.m_pHallServiceMgr, "lua", pName, pUserId, ...)
	else
		Log.e(TAG, "hallservice disconnect error ")
	end
end

function GameServiceMgr:onHallServerDisconnect(pClusterId)
	for k,v in pairs(self.m_pUserIdToGameServerMap) do
		local pGameSerer = self:onGetGameServerByUserId(k)
		skynet.call(pGameSerer, "lua", "onDisConnect", k)
	end
end

function GameServiceMgr:onConnectChange( conf )
	Log.dump(TAG,conf,"onConnectChange")
	if conf.isonline == 1 then
		if conf.servertype == 2 then
			self.m_pHallServiceMgr = cluster.proxy(conf.nodename, conf.clustername)
		else
			self.m_pAllocServiceMgr = cluster.proxy(conf.nodename, conf.clustername)
		end
	else
		if conf.servertype == 2 then
			self:onHallServerDisconnect(conf.nodename)
			self.m_pHallServiceMgr = nil
		else
			self.m_pAllocServiceMgr = nil
		end
	end
end

function GameServiceMgr:onMonitorNodeChange(conf)
	Log.dump(TAG,conf,"onMonitorNodeChange")
	if not conf then return end
	if not conf.nodename then return end
	local callback = clusterMonitor:onGetSubcribeCallback()
	if not callback then
		return
	end
	return callback(GameServiceMgr,conf)	
end

function GameServiceMgr:onReLoad()
	local modulename = onGetServerConfigFile(self.m_pGameCode)
	package.loaded[modulename] = nil
	codecache.clear()

	local pServerConfig = require(modulename)
	clusterMonitor:onReLoad(pServerConfig.iClusterConfig)
end

function GameServiceMgr:onUpdatePlaytypeConfig(pPlaytypeConfig)
	self.m_pPlaytypeConfig = pPlaytypeConfig
	Log.d(TAG, "---------------------------- 更新玩法配置 -------------------------------")
	Log.dump(TAG, self.m_pPlaytypeConfig, "self.m_pPlaytypeConfig")
	Log.d(TAG, "---------------------------- 更新配置完毕 -------------------------------")
	Log.e(TAG, "---------------------------- 更新玩法处理 -------------------------------")
	-- TODO:
	Log.e(TAG, "---------------------------- 更新处理完毕 -------------------------------")
end

function GameServiceMgr:onUpdateGoldFieldConfig(pGoldFieldConfig)
	self.m_pGoldFieldConfig = pGoldFieldConfig
	Log.d(TAG, "---------------------------- 更新场次配置 -------------------------------")
	Log.dump(TAG, self.m_pGoldFieldConfig, "self.m_pGoldFieldConfig")
	Log.d(TAG, "---------------------------- 更新配置完毕 -------------------------------")
	Log.e(TAG, "---------------------------- 更新玩法处理 -------------------------------")
	Log.e(TAG, "更新GameServer的场次配置")
	for _, kGameServer in pairs(self.m_pGameServerTable) do
		pcall(skynet.call, kGameServer, "lua", "onUpdateGoldFieldConfig", pGoldFieldConfig)
	end
	Log.e(TAG, "---------------------------- 更新处理完毕 -------------------------------")
end

function GameServiceMgr:onGetGoldFieldConfigTable()
	return self.m_pGoldFieldConfig or {}
end

function GameServiceMgr:onGetCurGoldFieldConfig(pGoldFieldId)
	if not self.m_pGoldFieldConfig then return end
	for _, kConfig in pairs(self.m_pGoldFieldConfig.iGoldFieldTable) do
		if kConfig.iGoldFieldId == pGoldFieldId then
			return kConfig
		end
	end
end

function GameServiceMgr:onGetPlaytypeConfig()
	return self.m_pPlaytypeConfig or {}
end

skynet.start(function()
	skynet.dispatch("lua", function(_, _, command, ...)
		Log.d(TAG, "dispatch command[%s]", command )
		skynet.ret(skynet.pack(GameServiceMgr[command](GameServiceMgr, ...)))
	end)
end)
