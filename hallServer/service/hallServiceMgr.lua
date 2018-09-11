
local skynet = require "skynet.manager"
local codecache = require "skynet.codecache"
local cluster = require "skynet.cluster"
local clusterMonitor = require "utils/clusterMonitor"
local json = require("cjson")
local TAG = "HallServiceMgr"

local HallServiceMgr = {}

function HallServiceMgr:init(pGameCode, pIdentify)
	self.m_pServerConfig = require(onGetServerConfigFile(pGameCode))
	self.m_pGameCode = pGameCode
	-- register agent from
	self.m_pAgentToHallServerMap = {}

	self.m_pGateServerMgrTable = {}
	-- self.m_pGameServerMgrTable = {}
	-- self.m_pAllocServiceMgr = nil
	self.m_pLoginServiceMgr = nil

	self.m_redisClientsMgr = require("utils/redisClientsMgr")
	self.m_redisClientsMgr:init()
	-- self.m_redisClientsMgr:addRedisClient(DefineType.REDIS_CLUB, self.m_pServerConfig.iGameIpPortConfig.iClubRedisConfig)

	self.m_pHallServerTable = {}
	-- 启动HallServer
	for i = 1, self.m_pServerConfig.iGameIpPortConfig.iHallServerConfig do
		local pHallServer = skynet.newservice("hallServerService")
		skynet.name(string.format(".HallServer_[%s]", i), pHallServer)
		table.insert(self.m_pHallServerTable, pHallServer)
		Log.d(TAG, "pHallServer = %s", pHallServer)
		local pRet = skynet.call(pHallServer, "lua", "init", pGameCode)
	end

	self.m_pUserIdToAgentMap = {}
	self.m_pAgentToUserIdMap = {}
	self.m_pUserIdToHallServerMap = {}

	-- 确保自身数据初始化完毕再开启结点间链接
	clusterMonitor:onSubscribeNode(self.onConnectChange)
	clusterMonitor:onStart(self.m_pServerConfig.iClusterConfig)
	clusterMonitor:onOpen()

	-- 初始化定时器
	self.m_pScheduleMgr = require("utils/schedulerMgr")
	self.m_pScheduleMgr:init()

end

function HallServiceMgr:onUpdateGateServerData(pAgent, pData)
	self.m_pAgentToHallServerMap[pAgent] = pData
end

function HallServiceMgr:onGetGameServerByLevel(pLevel)
	local pGameServerMgrCount = 0
	for k,v in pairs(self.m_pGameServerMgrTable) do
		if v.enable then
			pGameServerMgrCount = pGameServerMgrCount + 1
		end
	end

	if pGameServerMgrCount > 0 then
		math.randomseed(tostring(os.time()):reverse():sub(1, 6))
		local count = math.random(1, pGameServerMgrCount)
		for k,v in pairs(self.m_pGameServerMgrTable) do
			if v.enable then
				count = count - 1
				if count == 0 then
					return k, cluster.call(k, v.clustername, "onGetGameServerByLevel", pLevel)
				end
			end
		end
	end
end

-- function HallServiceMgr:onUnSubscribeGameServer(pClusterId)
-- 	local pGameServerMgr = self.m_pGameServerMgrTable[pClusterId]
-- 	if pGameServerMgr then
-- 		-- enable为false 表明不能再在这台gmeserver是创建房间，用于gameserver转移玩家并更新
-- 		pGameServerMgr.enable = false
-- 		cluster.call(pClusterId, pGameServerMgr.clustername, "onGameTableClear")
-- 	end
-- end

function HallServiceMgr:onUpdateHallServerData(data)
	local pAgent = self.m_pUserIdToAgentMap[data.iUserId]
	if pAgent and self.m_pAgentToUserIdMap[pAgent] and self.m_pAgentToUserIdMap[pAgent] == data.iUserId then
		self.m_pAgentToUserIdMap[pAgent] = nil
	end
	self.m_pUserIdToAgentMap[data.iUserId] = data.iAgent
	self.m_pAgentToUserIdMap[data.iAgent] = data.iUserId
	self.m_pUserIdToHallServerMap[data.iUserId] = data.iHallServer
	-- self:onPrint("onUpdateHallServerData")
end

function HallServiceMgr:onDeleteHallServerByUserId(pUserId, pAgent)
	if not pUserId or not pAgent then return end
	local tAgent = self.m_pUserIdToAgentMap[pUserId]

	self.m_pAgentToUserIdMap[pAgent] = nil

	if tAgent and tAgent == pAgent then
		self.m_pAgentToUserIdMap[tAgent] = nil
		self.m_pUserIdToAgentMap[pUserId] = nil
		self.m_pUserIdToHallServerMap[pUserId] = nil
		self:onPrint("onDeleteHallServerByUserId")
		return true
	end
end

function HallServiceMgr:onDeleteHallServerByAgent(pAgent)
	if not pAgent then return end
	local pUserId = self.m_pAgentToUserIdMap[pAgent]
	if pUserId and pUserId > 0 and self.m_pUserIdToAgentMap[pUserId] and pAgent == self.m_pUserIdToAgentMap[pUserId] then
		self.m_pUserIdToAgentMap[pUserId] = nil
		self.m_pUserIdToHallServerMap[pUserId] = nil
		self:onPrint("onDeleteHallServerByAgent")
	end
	self.m_pAgentToUserIdMap[pAgent] = nil
end

function HallServiceMgr:onPrint(name)
	Log.d(TAG, name)
	Log.dump(TAG, self.m_pUserIdToAgentMap, "self.m_pUserIdToAgentMap")
	Log.dump(TAG, self.m_pAgentToUserIdMap, "self.m_pAgentToUserIdMap")
	Log.dump(TAG, self.m_pUserIdToHallServerMap, "self.m_pUserIdToHallServerMap")
	Log.dump(TAG, self.m_pAgentToHallServerMap, "self.m_pAgentToHallServerMap")
	Log.dump(TAG, self.m_pGateServerMgrTable, "self.m_pGateServerMgrTable")
end


function HallServiceMgr:onGetAgentByUserId(pUserId)
	return pUserId and self.m_pUserIdToAgentMap[pUserId] or nil
end

function HallServiceMgr:onGetUserIdByAgent(pAgent)
	return pAgent and self.m_pAgentToUserIdMap[pAgent] or nil
end

function HallServiceMgr:onGetHallServerByUserId(pUserId)
	if pUserId and self.m_pUserIdToHallServerMap[pUserId] then 
		return self.m_pUserIdToHallServerMap[pUserId] 
	end

	math.randomseed(tostring(os.time()):reverse():sub(1, 6))
	return self.m_pHallServerTable[math.random(1, #self.m_pHallServerTable)]
end

-- function HallServiceMgr:onGetGameServerByUserId(pUserId)
-- 	for k, v in pairs(self.m_pGameServerMgrTable) do
-- 		local pStatus, pGameServer = pcall(cluster.call, k, v.clustername, "onGetGameServerByUserId", pUserId)
-- 		if pStatus and pGameServer then
-- 			return k, pGameServer
-- 		end
-- 	end	

-- 	return nil
-- end


-- function HallServiceMgr:onClubAutoCreateFriendRoom(pUserId, pClubId, pGameCode)
-- 	local pHallServer = self:onGetHallServerByUserId(pUserId)
-- 	if pHallServer then
-- 		pcall(skynet.call, pHallServer, "lua", "onClubAutoCreateFriendRoom", pClubId, pGameCode)
-- 	end	
-- end

-- function HallServiceMgr:onClubAutoCreateFriendRoomMore(pUserId, pClubId, pGameCode)
-- 	local pHallServer = self:onGetHallServerByUserId(pUserId)
-- 	if pHallServer then
-- 		pcall(skynet.call, pHallServer, "lua", "onClubAutoCreateFriendRoomMore", pClubId, pGameCode)
-- 	end	
-- end

----------------------------------------AllocService------------------------------------------------
-- function HallServiceMgr:onGetClubRoomCount(pClubId, pPlayId)
-- 	if self.m_pAllocServiceMgr then
-- 		return pcall(skynet.call, self.m_pAllocServiceMgr, "lua", "onGetClubRoomCount", pClubId, pPlayId)
-- 	else
-- 		Log.e(TAG, "allocservice disconnect error")
-- 	end
-- end

-- function HallServiceMgr:onGetGameServerByRoomId(pTableId)
-- 	if self.m_pAllocServiceMgr then
-- 		return skynet.call(self.m_pAllocServiceMgr, "lua", "onGetGameServerByRoomId", pTableId)
-- 	else
-- 		Log.e(TAG, "allocservice disconnect error ")
-- 	end
-- end

--------------------------------------LoginService--------------------------------------------
function HallServiceMgr:onDeleteUserInfoRedis(pUserId)
	if self.m_pLoginServiceMgr then
		pcall(skynet.call, self.m_pLoginServiceMgr, "lua", "onReceivePackage", "onDeleteUserInfoRedis", pUserId)
	else
		Log.e(TAG, "loginservice disconnect error ")
	end
end

function HallServiceMgr:onUpdateUserMoney(info)
	if self.m_pLoginServiceMgr then
		pcall(skynet.call, self.m_pLoginServiceMgr, "lua", "onReceivePackage", "onUpdateUserMoney", info)
	else
		Log.e(TAG, "loginservice disconnect error ")
	end
end

function HallServiceMgr:onExecuteRedisCmd(redis, cmd, ...)
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
	end

	return -1
end

function HallServiceMgr:ClientUserLoginHall(request)
	if self.m_pLoginServiceMgr then
		local pStatus, pUserId, pInfo = pcall(skynet.call, self.m_pLoginServiceMgr, "lua", "onReceivePackage", "ClientUserLoginHall", request)
		if pStatus then
			return pUserId, pInfo 
		end
	else
		Log.e(TAG, "loginservice disconnect error ")
		return
	end

	-- Log.dump(TAG, request, "request")

	-- local pUserInfo = {}
	-- -- 生成默认的信息
	-- pUserInfo.UserType = 0
	-- pUserInfo.Sex = 0
	-- pUserInfo.MachineId = "123456"
	-- pUserInfo.PlatformId = "1234567"
	-- pUserInfo.Level = 0
	-- pUserInfo.Money = 3000
	-- pUserInfo.NickName = "Wang"
	-- pUserInfo.RegisterTime = os.time()
	-- pUserInfo.LastLoginTime = os.time()
	-- pUserInfo.HeadUrl = "http://5b0988e595225.cdn.sohucs.com/images/20180814/3cc4c90654be4b6a98f6c8170a26f7ee.jpeg"
	-- pUserInfo.ClientIp = request.ClientIp
	-- pUserInfo.iServerVersion = 0

	-- local info = {}
	-- info.iStatus = 0
	-- info.iLoginMsg = "恭喜你，登陆成功！"
	-- info.iUserInfo = json.encode(pUserInfo)

	-- return 1, info 
end

----------------------------------------------------------------------------------------------
function HallServiceMgr:onReceivePackage(agent, name, request)
	local pUserId = self:onGetUserIdByAgent(agent)
	local pHallServer = self:onGetHallServerByUserId(pUserId)
	if pHallServer then
		skynet.call(pHallServer, "lua", "onReceivePackage", agent, name, request)
	else
		Log.e(TAG, "onReceivePackage [%s] pUserId[%s] error", name, pUserId)
	end
end

function HallServiceMgr:onSendPackage(pAgent, name, info)
	local Temp = pAgent
	if pAgent and type(pAgent) == "number" then
		pAgent = self:onGetAgentByUserId(pAgent)
	end

	if pAgent and self.m_pAgentToHallServerMap[pAgent] then
		local data = self.m_pAgentToHallServerMap[pAgent]
		Log.d(TAG, "onSendPackage [%s]  agent[%s] iClusterId[%s]", name, pAgent, data.iClusterId)
		pcall(cluster.call, data.iClusterId, data.iAgent, "onSendPackage", name, info)
	end
end

function HallServiceMgr:onActiveCloseConnect(pUserId)
	local pAgent = self:onGetAgentByUserId(pUserId)

	if pAgent and self.m_pAgentToHallServerMap[pAgent] then
		local data = self.m_pAgentToHallServerMap[pAgent]
		Log.d(TAG, "onSendPackage [%s]  agent[%s] iClusterId[%s]", "onActiveCloseConnect", pAgent, data.iClusterId)
		pcall(cluster.call, data.iClusterId, data.iAgent, "close")
	else
		Log.e(TAG, "onActiveCloseConnect agent[%s] pUserId[%s] error", pAgent, pUserId)
	end
end

function HallServiceMgr:onGetClientIp(pAgent)
	if pAgent and self.m_pAgentToHallServerMap[pAgent] then
		local data = self.m_pAgentToHallServerMap[pAgent]
		local pStatus, iClientIp = pcall(cluster.call, data.iClusterId, data.iAgent, "onGetClientIp")
		if pStatus then
			return iClientIp
		end
	else
		Log.e(TAG, "onGetClientIp agent[%s]", pAgent)
	end
end

function HallServiceMgr:onCloseAgent(pAgent)
	if pAgent and self.m_pAgentToHallServerMap[pAgent] then
		local data = self.m_pAgentToHallServerMap[pAgent]
		return pcall(cluster.call, data.iClusterId, data.iAgent, "close")
	else
		Log.e(TAG, "onCloseAgent agent[%s] error", pAgent)
	end
end

function HallServiceMgr:onDisConnect(pAgent, pClearRedis)
	local pUserId = self:onGetUserIdByAgent(pAgent)
	local pHallServer = self:onGetHallServerByUserId(pUserId)
	if pHallServer then
		Log.d(TAG, "onDisConnect agent[%s]", pAgent)
		--clear pAgent from
		self.m_pAgentToHallServerMap[pAgent] = nil
		
		skynet.call(pHallServer, "lua", "onDisConnect", pAgent, pClearRedis)
	else
		Log.e(TAG, "onDisConnect agent[%s] error", pAgent)
	end

	self:onPrint("onDisConnect")
end

------------------------------deal gameserver retire ------------------------------
function HallServiceMgr:onCheckRetireGameServer()
	local pGameServerMgrCount = 0
	for k,v in pairs(self.m_pGameServerMgrTable) do
		if v.enable then
			pGameServerMgrCount = pGameServerMgrCount + 1
		end
	end

	-- local pServerConfig = require(onGetServerConfigFile(self.m_pGameCode))
	for k,v in pairs(self.m_pServerConfig.iClusterConfig) do
		if v.servertype == 3 and v.retire and v.retire == 1 then
			pGameServerMgrCount = pGameServerMgrCount - 1
		end
	end

	if pGameServerMgrCount > 0 then
		for k,v in pairs(self.m_pServerConfig.iClusterConfig) do
			if v.servertype == 3 and v.retire and v.retire == 1 then
				self:onUneableGameServer(v.nodename)
			end
		end
	end
end

function HallServiceMgr:onUneableGameServer(pClusterId)
	local pGameServerMgr = self.m_pGameServerMgrTable[pClusterId]
	if pGameServerMgr then
		cluster.call(pClusterId, pGameServerMgr.clustername, "onUnSubscribeGameServer")
	else
		Log.e(TAG, "onUneableGameServer pClusterId[%s] error", pClusterId)
	end
end

function HallServiceMgr:onRetireGameServer(pClusterId)
	if self.m_pGameServerMgrTable[pClusterId] then
		local pServerConfig = require(onGetServerConfigFile(self.m_pGameCode))
		for k,v in pairs(pServerConfig.iClusterConfig) do
			if v.nodename == pClusterId then
				-- 删掉将要退休的结点
				pServerConfig.iClusterConfig[k] = nil
				break
			end
		end

		--reload
		clusterMonitor:onReLoad(pServerConfig.iClusterConfig)
	else
		Log.e(TAG, "onRetireGameServer pClusterId[%s] error", pClusterId)
	end
end
--------------------------------------------------------------------------------------
-- clear GateServer connection
function HallServiceMgr:onGateServerDisconnect(pClusterId)
	for k,v in pairs(self.m_pAgentToHallServerMap) do
		if v.iClusterId == pClusterId then
			self:onDisConnect(k, false)
		end
	end

	for k,v in pairs(self.m_pGateServerMgrTable) do
		if k == pClusterId then
			self.m_pGateServerMgrTable[k] = nil
		end
	end
end

function HallServiceMgr:onConnectChange( conf )
	Log.dump(TAG, conf, "onConnectChange")
	if conf.isonline == 1 then
		if conf.servertype == 1 then
			self.m_pGateServerMgrTable[conf.nodename] = conf.clustername
			if self.m_pProto then
				pcall(cluster.call, conf.nodename, conf.clustername, "onUpdateProto", self.m_pProto)
			end
		elseif conf.servertype == 3 then
			local pGameServerMgr = {}
			pGameServerMgr.clustername = conf.clustername
			pGameServerMgr.enable = true
			self.m_pGameServerMgrTable[conf.nodename] = pGameServerMgr
			-- 当GameServer连接上的时候，要将玩法配置传过去
			if self.m_pPlaytypeConfig then
				pcall(cluster.call, conf.nodename, conf.clustername, "onUpdatePlaytypeConfig", self.m_pPlaytypeConfig)
			end
			if self.m_pGoldFieldConfig then
				pcall(cluster.call, conf.nodename, conf.clustername, "onUpdateGoldFieldConfig", self.m_pGoldFieldConfig)
			end

		elseif conf.servertype == 4 then
			self.m_pAllocServiceMgr = cluster.proxy(conf.nodename, conf.clustername)
		else
			self.m_pLoginServiceMgr = cluster.proxy(conf.nodename, conf.clustername)
			pcall(skynet.call, self.m_pLoginServiceMgr, "lua", "onUpdatePlaytypeConfig", self.m_pPlaytypeConfig)
		end
	else
		if conf.servertype == 1 then
			self:onGateServerDisconnect(conf.nodename)
		elseif conf.servertype == 3 then
			self.m_pGameServerMgrTable[conf.nodename] = nil
		elseif conf.servertype == 4 then
			self.m_pAllocServiceMgr = nil
		else
			self.m_pLoginServiceMgr = nil
		end
	end
end

function HallServiceMgr:onMonitorNodeChange(conf)
	-- Log.dump(TAG,conf,"onMonitorNodeChange")
	if not conf then return end
	if not conf.nodename then return end
	local callback = clusterMonitor:onGetSubcribeCallback()
	if not callback then
		return
	end
	return callback(HallServiceMgr, conf)	
end

function HallServiceMgr:onReLoad()
	local modulename = onGetServerConfigFile(self.m_pGameCode)
	package.loaded[modulename] = nil
	codecache.clear()

	local pServerConfig = require(modulename)
	clusterMonitor:onReLoad(pServerConfig.iClusterConfig)

	for k,v in pairs(self.m_pGateServerMgrTable) do
		pcall(cluster.call, k, v, "onReLoad")
	end

	for k,v in pairs(self.m_pGameServerMgrTable) do
		pcall(cluster.call, k, v.clustername, "onReLoad")
	end	

	if self.m_pAllocServiceMgr then
		pcall(skynet.call, self.m_pAllocServiceMgr, "lua", "onReLoad")
	else
		Log.e(TAG, "allocservice disconnect error")
	end

	if self.m_pLoginServiceMgr then
		pcall(skynet.call, self.m_pLoginServiceMgr, "lua", "onReLoad")
	else
		Log.e(TAG, "loginservice disconnect error ")
	end

	self.m_pServerConfig = pServerConfig
end

skynet.start(function()
	skynet.dispatch("lua", function(_, _, command, ...)
		Log.d(TAG, "dispatch command[%s]", command )
		skynet.ret(skynet.pack(HallServiceMgr[command](HallServiceMgr, ...)))
	end)
end)