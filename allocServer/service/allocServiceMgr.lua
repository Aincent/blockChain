local skynet = require "skynet.manager"
local codecache = require "skynet.codecache"
local cluster = require "skynet.cluster"
local clusterMonitor = require "utils/clusterMonitor"
local TAG = "AllocServiceMgr"

local AllocServiceMgr = {}

function AllocServiceMgr:init(pGameCode, pIdentify)
	local pServerConfig = require(onGetServerConfigFile(pGameCode))

	self.m_pGameCode = pGameCode

	self.m_pHallServiceMgr = nil
	self.m_pGameServerMgrTable = {}

	self.m_pFriendBattleRoomIdMap = {}
	
	self.m_pGoldFieldIdRoomMap = {}

	self.m_pCurGoldFieldId = 0xFFFFFFF

	-- 俱乐部房间个数表
	self.m_pClubRoomCountTable = {}

	-- 启动BillServer
	self.m_pBillServerTable = {}
	local pBillServer = skynet.newservice("billServer")
	table.insert(self.m_pBillServerTable, pBillServer)
	skynet.send(pBillServer, "lua", "init", pGameCode)

	-- 启动reportServer
	self.m_pReportServerTable = {}
	local pReportServer = skynet.newservice("reportServer")
	table.insert(self.m_pReportServerTable, pReportServer)
	skynet.send(pReportServer, "lua", "init", pGameCode)	

	-- self:onMakeRoomIdList()

	self:onMakeSixRoomIdList()

	-- 启动计时器
	self.m_pScheduleMgr = require('utils/schedulerMgr')
	self.m_pScheduleMgr:init()

	local pCallback = self.onReportOnlineAndPlay
	self.m_pReportTimer = self.m_pScheduleMgr:register(pCallback, 5 * 60 * 1000, -1, 10 * 1000, self)
	
	-- 确保自身数据初始化完毕再开启结点间链接
	clusterMonitor:onSubscribeNode(self.onConnectChange)	
	clusterMonitor:onStart(pServerConfig.iClusterConfig)	
	clusterMonitor:onOpen()
end

function AllocServiceMgr:onMakeSixRoomIdList()
	self.m_pRoomIdList = {}
	for i = 100000, 999999 do
		self.m_pRoomIdList[#self.m_pRoomIdList + 1] = {
			iRoomId = i,
			iIsInGame = false,
		}
		self.m_pFriendBattleRoomIdMap[i] = {
			iClusterId = 0,
			iGameServer = 0,
			iIndex = 0,
		}
	end 
	math.randomseed(tostring(os.time()):reverse():sub(1, 6))
	for i = 100000, 999999 do
		local pIndex1 = math.random(1, #self.m_pRoomIdList)
		local pIndex2 = math.random(1, #self.m_pRoomIdList)
		local pTemp = self.m_pRoomIdList[pIndex1]
		self.m_pRoomIdList[pIndex1] = self.m_pRoomIdList[pIndex2]
		self.m_pRoomIdList[pIndex2] = pTemp
	end
	self.m_pCurRoomIndex = 0
	-- Log.dump(TAG, self.m_pRoomIdList, "self.m_pRoomIdList")
end


function AllocServiceMgr:onCreateOneRoomId(pClusterId, pGameServer, pClubId, pPlayId)
	while(true) do
		if self.m_pCurRoomIndex >= #self.m_pRoomIdList then
			self.m_pCurRoomIndex = 0
		end
		self.m_pCurRoomIndex = self.m_pCurRoomIndex + 1
		if self.m_pRoomIdList[self.m_pCurRoomIndex] and not self.m_pRoomIdList[self.m_pCurRoomIndex].iIsInGame then
			self.m_pRoomIdList[self.m_pCurRoomIndex].iIsInGame = true
			local pRoomId = self.m_pRoomIdList[self.m_pCurRoomIndex].iRoomId
			self.m_pFriendBattleRoomIdMap[pRoomId].iPalyId = pPlayId or 0
			self.m_pFriendBattleRoomIdMap[pRoomId].iClusterId = pClusterId
			self.m_pFriendBattleRoomIdMap[pRoomId].iGameServer = pGameServer
			self.m_pFriendBattleRoomIdMap[pRoomId].iIndex = self.m_pCurRoomIndex
			if pClubId and pClubId > 0 then
				if not self.m_pClubRoomCountTable[pClubId] then
					self.m_pClubRoomCountTable[pClubId] = {}
				end
				table.insert(self.m_pClubRoomCountTable[pClubId], pRoomId)
			end
			return pRoomId
		end
	end
end

function AllocServiceMgr:onDeleteOneRoomId(pRoomId, pClubId)
	if pRoomId and self.m_pFriendBattleRoomIdMap[pRoomId] then
		local pIndex = self.m_pFriendBattleRoomIdMap[pRoomId].iIndex or 0
		self.m_pFriendBattleRoomIdMap[pRoomId].iClusterId = 0
		self.m_pFriendBattleRoomIdMap[pRoomId].iGameServer = 0
		self.m_pFriendBattleRoomIdMap[pRoomId].iIndex = 0
		self.m_pFriendBattleRoomIdMap[pRoomId].iPalyId = 0
		
		if pIndex > 0 and self.m_pRoomIdList[pIndex] then
			if self.m_pRoomIdList[pIndex].iIsInGame then
				self.m_pRoomIdList[pIndex].iIsInGame = false
			end
		end
	end

	if pClubId and pClubId > 0 and pRoomId and pRoomId > 0 then
		if self.m_pClubRoomCountTable[pClubId] and #self.m_pClubRoomCountTable[pClubId] > 0 then
			for kIndex, kRoomId in pairs(self.m_pClubRoomCountTable[pClubId]) do
				if pRoomId == kRoomId then
					table.remove(self.m_pClubRoomCountTable[pClubId], kIndex)
					break
				end
			end
		end
	end
end

function AllocServiceMgr:onGameTableStartGame(pRoomId, pClubId)
	if pClubId and pClubId > 0 and pRoomId and pRoomId > 0 then
		if self.m_pClubRoomCountTable[pClubId] and #self.m_pClubRoomCountTable[pClubId] > 0 then
			for kIndex, kRoomId in pairs(self.m_pClubRoomCountTable[pClubId]) do
				if pRoomId == kRoomId then
					table.remove(self.m_pClubRoomCountTable[pClubId], kIndex)
					break
				end
			end
		end
	end
end

function AllocServiceMgr:onCreateOneTableId()
	self.m_pCurGoldFieldId = self.m_pCurGoldFieldId + 1
	if self.m_pCurGoldFieldId == 0x8FFFFFFF then
		self.m_pCurGoldFieldId = 0xFFFFFFF
	end
	return self.m_pCurGoldFieldId
end

function AllocServiceMgr:onGetClubRoomCount(pClubId, pPlayId)
	if pClubId and pClubId > 0 then
		if not pPlayId then
			return self.m_pClubRoomCountTable[pClubId] and #self.m_pClubRoomCountTable[pClubId] or 0
		else
			local pRoomCount = 0
			if not self.m_pClubRoomCountTable[pClubId] then return pRoomCount end
			for _, kRoomId in pairs(self.m_pClubRoomCountTable[pClubId]) do
				local kRoomInfo = self.m_pFriendBattleRoomIdMap[kRoomId]
				if kRoomInfo and kRoomInfo.iPalyId == pPlayId then
					pRoomCount = pRoomCount + 1
				end
			end
			return pRoomCount
		end
	end
	return 0
end

function AllocServiceMgr:onGetGameServerByRoomId(pRoomId)
	if pRoomId and self.m_pFriendBattleRoomIdMap[pRoomId] then
		return self.m_pFriendBattleRoomIdMap[pRoomId].iClusterId, self.m_pFriendBattleRoomIdMap[pRoomId].iGameServer
	end
	return nil
end

function AllocServiceMgr:onPackLookbackTable(pLookbackTable)
	if self.m_pHallServiceMgr then
		return pcall(skynet.call, self.m_pHallServiceMgr, "lua", "onPackLookbackTable", pLookbackTable)
	else
		Log.e(TAG, "hallservice disconnect error ")
	end
end

---------------------------BillServer-------------------------------
function AllocServiceMgr:onGetBillServer()
	return self.m_pBillServerTable[#self.m_pBillServerTable]
end

function AllocServiceMgr:onSetLookbackId(pLookbackId)
	self.m_pLookbackId = pLookbackId or 0
end

function AllocServiceMgr:onGetANewLookbackId()
	self.m_pLookbackId = self.m_pLookbackId + 1
	if self.m_pLookbackId < 10000000 then
		self.m_pLookbackId = 10000000
	elseif self.m_pLookbackId >= 99999999 then
		self.m_pLookbackId = 10000000
	end
	-- 给billserver设置
	skynet.send(self:onGetBillServer(), "lua", "onSetLookbackId", self.m_pLookbackId)
	return self.m_pLookbackId
end

function AllocServiceMgr:onServerSetBillGoldFieldDetail(pInfoStr)
	skynet.send(self:onGetBillServer(), "lua", "onServerSetBillGoldFieldDetail", pInfoStr)
end

function AllocServiceMgr:onServerUpdateOneBattleBillInfo(pBattleId, pInfoStr)
	skynet.send(self:onGetBillServer(), "lua", "onServerUpdateOneBattleBillInfo", pBattleId, pInfoStr)
end

function AllocServiceMgr:onServerUserSetBillDetail(pBattleId, pInfoStr)
	skynet.send(self:onGetBillServer(), "lua", "onServerUserSetBillDetail", pBattleId, pInfoStr)
end

function AllocServiceMgr:onServerUserSetBillLookback(pLookbackId, pLookbackTable)
	if pLookbackId and pLookbackTable then
		local status ,pIsAllOk, pInfoStr = self:onPackLookbackTable(pLookbackTable)
		Log.d(TAG,"onServerUserSetBillLookback status[%s]  pIsAllOk[%s]  pInfoStr[%s] ",status ,pIsAllOk, pInfoStr)
		if status and pIsAllOk then
			skynet.send(self:onGetBillServer(), "lua", "onServerUserSetBillLookback", pLookbackId, pInfoStr)
		end
	end	
end

--------------------------------------------------------------------
---------------------------reportServer------------------------------
function AllocServiceMgr:onGetReportServer()
	return self.m_pReportServerTable[#self.m_pReportServerTable]
end

function AllocServiceMgr:onReportOnlineAndPlay()
	local pOnlineAndPlay = {
		iOnlineCount = 0,
		iPlayCount = 0,
		iTimeStamp = os.time(),
	}
	
	for k,v in pairs(self.m_pGameServerMgrTable) do
		local pStatus,pTempOnlineAndPlay = pcall(cluster.call, k, v, "onGetGameServiceOnlineAndPlay")
		if pStatus then
			pOnlineAndPlay.iOnlineCount = pOnlineAndPlay.iOnlineCount +  pTempOnlineAndPlay.iOnlineCount
			pOnlineAndPlay.iPlayCount = pOnlineAndPlay.iPlayCount +  pTempOnlineAndPlay.iPlayCount
		end	
	end

	local pReportServer = self:onGetReportServer()
	if pReportServer then
		skynet.send(pReportServer, "lua", "onDealOnlineAndPlay", pOnlineAndPlay)
	end
end
----------------------------------------------------------------------
function AllocServiceMgr:onGameServerDisconnect(pClusterId)
	for k,v in pairs(self.m_pFriendBattleRoomIdMap) do
		if v.iClusterId == pClusterId then
			local pIndex = v.iIndex or 0
			v.iClusterId = 0
			v.iGameServer = 0
			v.iIndex = 0

			if pIndex > 0 and self.m_pRoomIdList[pIndex] then
				if self.m_pRoomIdList[pIndex].iIsInGame then
					self.m_pRoomIdList[pIndex].iIsInGame = false
				end
			end

			if k and k > 0 then
				for kClub, kRoomList in pairs(self.m_pClubRoomCountTable) do
					for kIndex, kRoomId in pairs(kRoomList) do
						if k == kRoomId then
							table.remove(self.m_pClubRoomCountTable[kClub], kIndex)
							break
						end
					end
				end
			end
		end
	end
end

--------------------------------deal gameserver retire --------------------------------
function AllocServiceMgr:onRetireGameServer(pClusterId)
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
---------------------------------------------------------------------------------------

function AllocServiceMgr:onConnectChange( conf )
	Log.dump(TAG,conf,"onConnectChange")
	if conf.isonline == 1 then
		if conf.servertype == 2 then
			self.m_pHallServiceMgr = cluster.proxy(conf.nodename, conf.clustername)
		else
			self.m_pGameServerMgrTable[conf.nodename] = conf.clustername
		end
	else
		if conf.servertype == 2 then
			self.m_pHallServiceMgr = nil
		else
			self:onGameServerDisconnect(conf.nodename)
			self.m_pGameServerMgrTable[conf.nodename] = nil
		end
	end
end

function AllocServiceMgr:onMonitorNodeChange(conf)
	Log.dump(TAG,conf,"onMonitorNodeChange")
	if not conf then return end
	if not conf.nodename then return end
	local callback = clusterMonitor:onGetSubcribeCallback()
	if not callback then
		return
	end
	return callback(AllocServiceMgr, conf)
end

function AllocServiceMgr:onReLoad()
	local modulename = onGetServerConfigFile(self.m_pGameCode)
	package.loaded[modulename] = nil
	codecache.clear()

	local pServerConfig = require(modulename)
	clusterMonitor:onReLoad(pServerConfig.iClusterConfig)
end

skynet.start(function()
	skynet.dispatch("lua", function(_, _, command, ...)
		Log.d(TAG, "dispatch command[%s]", command )
		skynet.ret(skynet.pack(AllocServiceMgr[command](AllocServiceMgr, ...)))
	end)
end)



