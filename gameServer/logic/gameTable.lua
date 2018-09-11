local skynet = require "skynet"
local socket = require "skynet.socket"
local sharedata = require "skynet.sharedata"
local json = require("cjson")
local queue = require "skynet.queue"
local GameUser = require("logic/gameUser")

local TAG = "GameTable"

local cs = queue()

local GameTable = {}

function GameTable:onSendPackage(pUserId, pName, pInfo)
	if not pUserId or pUserId <= 0 then
		Log.e(TAG, "onSendPackage pUserId[%s] pName[%s] is not exit!", pUserId, pName)
		return
	end
	pcall(skynet.call, self.m_pGameServiceMgr, "lua", "onSendPackageToHallServiceMgr", "onSendPackage", pUserId, pName, pInfo)
end 

function GameTable:init(pGameServer, pTableId)
	self.m_pCsQueue = cs

	self.m_pCsQueue(function()
		self.m_pCommonConfig = {
			iTableId = pTableId,
		}

		self.m_pGameServiceMgr = skynet.localname(".GameServiceMgr")
		self.m_pGameServer = pGameServer
		
		Log.d(TAG, "[初始化新桌子:pGameServer[%s], pTableId[%s]]", pGameServer, pTableId)
		self.m_pScheduleMgr = require('utils/schedulerMgr')
		self.m_pScheduleMgr:init()

		local pGameCode, pLevel = skynet.call(self.m_pGameServer, "lua", "onGetGameCodeAndLevel")

		local pGameRoomConfig = sharedata.query(string.format("GameRoomConfig_Code[%s]_Level[%s]", pGameCode, pLevel))
		table.merge(self.m_pCommonConfig, pGameRoomConfig)
		assert(pGameRoomConfig)
		Log.dump(TAG, self.m_pCommonConfig, "self.m_pCommonConfig")

		self.m_pGameUsers = {}

		self.m_pPlaytypeConfig = skynet.call(self.m_pGameServiceMgr, "lua", "onGetPlaytypeConfig")
		assert(self.m_pPlaytypeConfig)

		self.m_pGameUserLoginCount = 0
		self.m_pNotDealReceivePackage = false
	end)
end 

function GameTable:onDelayedDtorGameTable()
	self.m_pNotDealReceivePackage = true
	local pCallback = self.onDtorGameTable
	self.m_pDelayedDtorTimer = self.m_pScheduleMgr:registerOnceNow(pCallback, 1000, self)
end

function GameTable:onDtorGameTable()
	self.m_pScheduleMgr:unregister(self.m_pDelayedDtorTimer)
	Log.d(TAG, "onDtorGameTable TableId[%s]", self.m_pCommonConfig.iTableId)
	skynet.exit()
end

function GameTable:onGetUserInfo(pData, pUserId)
	local pKey = string.format("UserInfo_UserId_%s", pUserId)
	local pUserInfo = self:onExecuteRedisCmd(DefineType.REDIS_USERINFO, "GET", pKey)
	if pUserInfo and type(pUserInfo) == "string" then
		pUserInfo = json.decode(pUserInfo)
		pData.iMoney = tonumber(pUserInfo.Money) or 0
		pData.iRoomCardNum = tonumber(pUserInfo.RoomCardNum) or 0
		pData.iNickName = pUserInfo.NickName or ""
		pData.iWinTimes = tonumber(pUserInfo.WinTimes) or 0
		pData.iLoseTimes = tonumber(pUserInfo.LoseTimes) or 0
		pData.iDrawTimes = tonumber(pUserInfo.DrawTimes) or 0
		pData.iIsAgent = tonumber(pUserInfo.IsAgent) or 0 
		return true
	end
	return false
end

function GameTable:onServerUserShowHints(pUserId, pType, pMsg)
	local name = "ServerUserShowHints"
	local info = {}
	info.iShowType = pType
	info.iShowMsg = pMsg
	self:onSendPackage(pUserId, name, info)
end

function GameTable:onGameTableUpdateData()
	local data = {}
	data.iTableId = self.m_pCommonConfig.iTableId
	data.iGameTable = skynet.self()
	data.iMaxUserCount = self:onGetGameTableMaxUserCount()
	data.iUserCount = self:onGetTableUserCount()
	data.iTableStatus = 0
	if self:isTableStatusPlaying() then
		data.iTableStatus = 1
	end
	data.iUserTable = {}
	for k, v in pairs(self.m_pGameUsers) do
		data.iUserTable[#data.iUserTable + 1] = v:onGetUserId()
	end
	local pRet = skynet.call(self.m_pGameServer, "lua", "onGameTableUpdateData", data)
end

function GameTable:onGameTableDeleteData()
	local data = {}
	data.iTableId = self.m_pCommonConfig.iTableId
	local pRet = skynet.call(self.m_pGameServer, "lua", "onGameTableDeleteData", data)
end

function GameTable:onBroadcastUserReady(pUser)
	if not pUser then return end
	local name = "ServerBCUserReady"
	local info = {}
	info.iUserId = pUser:onGetUserId()
	info.iReady = pUser:onGetReady()
	self:onBroadcastTableUsers(name, info)
end

function GameTable:onBroadcastUserEnterTable(pUser)
	if not pUser then return end
	local name = "ServerBCUserEnterTable"
	local info = {}
	info.iUserId = pUser:onGetUserId()
	info.iSeatId = pUser:onGetSeatId()
	info.iReady = pUser:onGetReady()
	info.iMoney = pUser:onGetMoney()
	info.iUserInfoStr = pUser.m_pUserInfoStr
	self:onBroadcastTableUsers(name, info, pUser:onGetUserId())
end

--------------------------------------- redis -----------------------------------



--------------------------------------- 网络包组装函数 -----------------------------
-- 如果userId有值，则不包括该userId
function GameTable:onBroadcastTableUsers(pName, pInfo, pUserId)
	pUserId = pUserId or -1
	for _, kUser in pairs(self.m_pGameUsers) do
		if kUser:onGetUserId() ~= pUserId then
			self:onSendPackage(kUser:onGetUserId(), pName, pInfo)
		end
	end
end


function GameTable:onBroadcastUserLogoutTable(pUser)
	Log.d(TAG, "GameTable onBroadcastUserLogoutTable")
	if not pUser then return end
	local name = "ServerBCUserLogoutTable"
	local info = {}
	info.iUserId = pUser:onGetUserId()
	self:onBroadcastTableUsers(name, info)
end

function GameTable:onRemoveUser(pUser)
	Log.d(TAG, "GameTable onRemoveUser")
	if not pUser then
		return -1
	end
	local pRet = skynet.call(self.m_pGameServiceMgr, "lua", "onDeleteGameServerByUserId", pUser:onGetUserId())
	-- 如果当前玩家确实存在，则移除该玩家
	for kIndex, kUser in pairs(self.m_pGameUsers) do
		if kUser == pUser then
			self.m_pGameUsers[kIndex] = nil
			break
		end
	end
	delete(pUser)
	return 0
end

function GameTable:onGetMaxUserCount()
	if self.m_pCommonConfig.pSetBuXianRenShu and self.m_pCommonConfig.pSetBuXianRenShu > 0 then
		return self.m_pCommonConfig.pSetBuXianRenShu
	end 
	return self:onGetGameTableMaxUserCount()
end

function GameTable:onGetGameTableMaxUserCount()
	local pRoundUserCount = self.m_pPlaytypeConfig.iGameUserCardMap.iGameMaxUserCount
	-- 如果设置了最大人数，则用最大人数，如果没有，则用Round支持的最大，实在没有，那就用配置中的
	if self.m_pCommonConfig.pSetUpMaxUserCount and self.m_pCommonConfig.pSetUpMaxUserCount > 0 then
		return self.m_pCommonConfig.pSetUpMaxUserCount
	end
	if self.m_pGameRound.onGetGameRoundMaxUserCount then
		return self.m_pGameRound:onGetGameRoundMaxUserCount()
	end
	return pRoundUserCount
end

function GameTable:onGetMaxCardCount()
	return self.m_pGameRound:onGetMaxCardCount()
end

function GameTable:onGetDealCardCount()
	return self.m_pPlaytypeConfig.iGameUserCardMap.iGameDealCardCount
end

function GameTable:onGetUserByUserId(userId)
	if not userId then return end
	for _, kUser in pairs(self.m_pGameUsers) do
		if kUser:onGetUserId() == userId then
			return kUser
		end
	end
end

function GameTable:onAllocSeatId()
	for i = 1, self:onGetMaxUserCount() do
		if not self.m_pGameUsers[i] then
			return i
		end
	end
end

function GameTable:onGetTableUserCount()
	local pUserCount = 0
	for _, kUser in pairs(self.m_pGameUsers) do
		pUserCount = pUserCount + 1
	end
	return pUserCount
end

function GameTable:onGetLocalGameType()
	return self.m_pCommonConfig.iLocalGameType
end

function GameTable:onGetPlayType()
	return self.m_pCommonConfig.iPlaytype
end

function GameTable:onGetReadyUserCount()
	local pUserCount = 0
	for _, kUser in pairs(self.m_pGameUsers) do
		if 1 == kUser:onGetReady() then 
			pUserCount = pUserCount + 1
		end
	end
	return pUserCount
end

function GameTable:onExecuteRedisCmd(redis, ...)
	return skynet.call(self.m_pGameServiceMgr, "lua", "onExecuteRedisCmd", redis, ...)
end

function GameTable:onGetCommonConfig()
	return self.m_pCommonConfig
end

function GameTable:isOneUserStartGame()
	return self.m_pGameRound.isOneUserStartGame and self.m_pGameRound:isOneUserStartGame()
end

function GameTable:setTableStatus(status)
	self.m_pTableStatus = status
end

function GameTable:isFirendBattleRoom()
	return self.m_pCommonConfig.iRoomType == DefineType.RoomType_Friend
end

function GameTable:isGoldFieldRoom()
	return self.m_pCommonConfig.iRoomType == DefineType.RoomType_GlodField
end

-------------------------------------------- socket ------------------------------------------
function GameTable:ClientUserSendChatFace(pData, pUserId)
	local pUser = self:onGetUserByUserId(pUserId)
	if not pUser then return end
	local name = "ServerBCUserSendChatFace"
	local info = pData
	info.iUserId = pUserId
	self:onBroadcastTableUsers(name, info)
end

function GameTable:ClientUserSendVoiceSlice(pData, pUserId)
	-- 首先告诉该玩家已经收到了
	local name = "ServerUserSendVoiceSlice"
	local info = {}
	info.iUserId = pData.iUserId
	info.iStatus = 1
	info.iIndex = pData.iIndex
	info.iTableId = pData.iTableId
	info.iVoiceId = pData.iVoiceId
	self:onSendPackage(pUserId, name, info)
	-- 广播该语音给所有玩家
	local name = "ServerBCUserSendVoiceSlice"
	local info = pData
	for k, v in pairs(self.m_pGameUsers) do
		self:onSendPackage(v:onGetUserId(), name, info)
	end
end

function GameTable:ClientUserChangeUserInfo(pData, pUserId)
	local pUser = self:onGetUserByUserId(pUserId)
	if not pUser then return end
	local name = "ServerBCUserChangeUserInfo"
	local info = {}
	info.iUserId = pUserId
	info.iUserInfo = pData.iUserInfo
	self:onBroadcastTableUsers(name, info)
end

-- 主动断开某个用户
function GameTable:onActiveCloseConnect(pUserId)
	pcall(skynet.call, self.m_pGameServiceMgr, "lua", "onSendPackageToHallServiceMgr", "onActiveCloseConnect", pUserId)
end

-- 启动计时器，并放入时序中, 这里最多还能接受一个参数
function GameTable:onStartTimerAndDealCsFunc(pTime, pFunc, pTarget, ...)
	local pTimer = self.m_pScheduleMgr:registerOnceNow(self.onDealCsFunc, pTime, self, pFunc, pTarget, ...)
	return pTimer
end

-- 将函数放入到时序中
function GameTable:onDealCsFunc(pFunc, pTarget, ...)
	self.m_pCsQueue(function(...)
		pFunc(pTarget, ...)
	end)
end

-- 取消定时器
function GameTable:unregisterTimer(pTimer)
	self.m_pScheduleMgr:unregister(pTimer)
end

function GameTable:onReceivePackage(pUserId, pName, pData)
	self.m_pCsQueue(function()
		Log.d(TAG, "onReceivePackage pUserId[%s] pName[%s] ", pUserId, pName)
		if self.m_pNotDealReceivePackage then
			Log.e(TAG, "NotDealReceivePackage pUserId[%s] pName[%s]", pUserId, pName)
			return
		end
		if self[pName] then
			return self[pName](self, pData, pUserId)
		elseif self.m_pGameRound[pName] then
			return self.m_pGameRound[pName](self.m_pGameRound, pData, pUserId)
		else
			Log.e(TAG, "onReceivePackage pUserId[%s] pName[%s]")
		end
	end)
end

return GameTable
