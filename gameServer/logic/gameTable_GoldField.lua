local skynet = require "skynet"
local socket = require "skynet.socket"
local sharedata = require "skynet.sharedata"
local json = require("cjson")
local queue = require "skynet.queue"
local GameUser = require("logic/gameUser")

local TAG = "GameTable"

local GameTable = require("logic/gameTable")

local tableStatusMap = {
	TABLE_STATUS_NONE = 0,  -- 无状态，初始完成，玩家可以进来
	TABLE_STATUS_PLAYING = 1, -- 牌局进行中
	TABLE_STATUS_BATTLE_DEAD = 2, -- 等待回收
}

function GameTable:onInitGlodFieldConfig(pData)
	self.m_pCsQueue(function()
		self:setTableStatus(tableStatusMap.TABLE_STATUS_NONE)

		local pCurGlodFieldConfig = skynet.call(self.m_pGameServiceMgr, "lua", "onGetCurGoldFieldConfig", pData.iGoldFieldId)
		-- 合并配置信息
		table.merge(self.m_pCommonConfig, pCurGlodFieldConfig)

		local pRoundPath = nil
		if self.m_pPlaytypeConfig.iGameRoundPath then
			pRoundPath = self.m_pPlaytypeConfig.iGameRoundPath[self:onGetLocalGameType()]
		end

		if not pRoundPath then
			return
		end

		self.m_pGameRound    = require(pRoundPath)
		self.m_pGameRound:init(self, self.m_pScheduleMgr)

		self.m_pPlaytypeStr = self.m_pGameRound.m_pGameRule:onGetPlaytypeStr()

		-- 启动退出没有准备玩家定时器，如果45秒没准备有开始牌局则退出
		local pTime = 1 * 1000
		self:onStartDimissNotReadyTimer(pTime)

		-- 启动检测牌局10分钟不开始，直接解散房间
		self:onStartDimissNotNoramlGoldFieldTimer(20 * 60 * 1000)

		Log.dump(TAG, self.m_pCommonConfig, "self.m_pCommonConfig")
	end)
end

function GameTable:onCheckUserCanLoginTable(pData, pUserId)
	-- 判断房间的状态是否可进
	if not self:onCheckTableStatusCanEnter(pData) then
		return DefineType.ERROR_LOGIN_TABLE_STATUS_ERROR
	end
	-- 判断桌子是否已满
	if self:onGetTableUserCount() >= self:onGetGameTableMaxUserCount() then
		return DefineType.ERROR_LOGIN_TABLE_FULL
	end
	-- 判断该玩家是否已经在这个桌子上
	if self:onGetUserByUserId(pUserId) then
		return DefineType.ERROR_LOGIN_TABLE_FULL
	end
	-- 获取玩家的基本信息
	if not self:onGetUserInfo(pData, pUserId) then
		return DefineType.ERROR_LOGIN_WRONG_DATA
	end
	-- 判断用户的钱是否够进该房间
	if not self:onCheckUserEnoughMoney(pData) then
		return DefineType.ERROR_LOGIN_NOT_ENOUGH_MONEY
	end
	-- 判断用户的钱是否超过该房间的限制
	if not self:onCheckUserTooMuchMoney(pData) then
		return DefineType.ERROR_LOGIN_TOO_MUCH_MONEY
	end

	return nil
end

function GameTable:onClientCmdLoginGame(pData, pUserId)
	return self.m_pCsQueue(function()
		local pStatus = self:onCheckUserCanLoginTable(pData, pUserId)
		-- 登陆成功
		if not pStatus then
			self:onDealUserLoginSuccess(pData, pUserId)
			return true
		else
			local name = "ServerUserLoginGameFail"
			local info = pStatus
			self:onSendPackage(pUserId, name, info)
		end 
		return false
	end)
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

function GameTable:onCheckUserEnoughMoney(pData)
	return pData.iMoney >= self.m_pCommonConfig.iNeedMoney
end

function GameTable:onCheckUserTooMuchMoney(pData)
	return pData.iMoney <= self.m_pCommonConfig.iMaxMoney
end

function GameTable:onCheckUserEnoughRoomCard(pData)
	return true
end

function GameTable:onCheckUserIsInClub(pData)
	return true
end

function GameTable:onCheckTableStatusCanEnter(pData)
	Log.d(TAG, "status[%s]", self.m_pTableStatus)
	-- 只有当房间处于未开局的情况下才能进入
	if self:isTableStatusNone() then
		return true
	end
end

function GameTable:onDealUserLoginSuccess(pData, pUserId)
	-- 分配一个座位号
	local pSeatId = self:onAllocSeatId()
	if not pSeatId then return -1 end
	-- 设置用户信息
	local pNewUser = new(GameUser, pData, pUserId, pSeatId)
	if not pNewUser then return -1 end
	self.m_pGameUserLoginCount = self.m_pGameUserLoginCount + 1
	pNewUser:onSetLoginCount(self.m_pGameUserLoginCount)
	self.m_pGameUsers[pSeatId] = pNewUser
	pNewUser:onSetIsOnline(1)
	-- 返回玩家成功进入房间的包
	self:onSendUserLoginSuccess(pNewUser)
	-- 上报给GameServer
	self:onGameTableUpdateData()
	-- 写到账单redis
	-- 将自己的ID和GameServer绑定起来
	local pRet = skynet.call(self.m_pGameServiceMgr, "lua", "onUpdateGameServerData", {
			iGameServer = self.m_pGameServer,
			iUserId = pNewUser:onGetUserId()
		})
	-- 广播房间内的玩家有玩家进入
	self:onBroadcastUserEnterTable(pNewUser)
	if 1 == pNewUser:onGetReady() then
		self:onBroadcastUserReady(pNewUser)
		self:onCheckGameTableStartGame()
	end
end

function GameTable:onServerUserShowHints(pUserId, pType, pMsg)
	local name = "ServerUserShowHints"
	local info = {}
	info.iShowType = pType
	info.iShowMsg = pMsg
	self:onSendPackage(pUserId, name, info)
end

function GameTable:onCheckGameTableStartGame()
	Log.d(TAG, "onCheckGameTableStartGame")
	if self:isTableStatusPlaying() then
		Log.e(TAG, "当前状态不对,iTableId[%s] iTableStatus[%s]", self.m_pCommonConfig.iTableId, self.m_pTableStatus)
		return 
	end
	Log.d(TAG, "onCheckGameTableStartGame ready[%s] max[%s]", self:onGetReadyUserCount(), self:onGetGameTableMaxUserCount())
	-- 监测人数，是否可以开始游戏
	if self:onGetReadyUserCount() == self:onGetGameTableMaxUserCount() then
		self:setTableStatus(tableStatusMap.TABLE_STATUS_PLAYING)
		for _, kUser in pairs(self.m_pGameUsers) do
			kUser:onSetMoney(kUser:onGetMoney() - self.m_pCommonConfig.iServerFee)
			local info = {
				iUserId = kUser:onGetUserId(),
				iTurnMoney = -self.m_pCommonConfig.iServerFee,
			}
			self:onUpdateDataBaseUserMoney(info)
		end

		self.m_pScheduleMgr:unregister(self.m_pDisMissNotReadyTimer)
		-- 检测开始8分钟后未结束，则解散房间
		self:onStartDimissNotNoramlGoldFieldTimer(8 * 60 * 1000)

		self.m_pGameRound:onGameRoundStart()
		self:onGameTableUpdateData()
	end
end

function GameTable:onBroadcastUserReady(pUser)
	if not pUser then return end
	local name = "ServerBCUserReady"
	local info = {}
	info.iUserId = pUser:onGetUserId()
	info.iReady = pUser:onGetReady()
	self:onBroadcastTableUsers(name, info)
end

function GameTable:onSendUserLoginSuccess(pUser, pIsLookback)
	if not pUser then return end
	local name = "ServerUserLoginGameSuccess"
	local info = {}
	info.iGameCode = self.m_pCommonConfig.iGameCode
	info.iRoomType = self.m_pCommonConfig.iRoomType
	info.iRoomOwnerId = 0
	info.iBattleTotalRound = 0
	info.iBattleCurRound = 0
	info.iGameLevel = self.m_pCommonConfig.iGameLevel
	info.iTableName = self.m_pCommonConfig.iTableName
	info.iTableId = self.m_pCommonConfig.iTableId
	info.iBasePoint = self.m_pCommonConfig.iBasePoint
	info.iServerFee = self.m_pCommonConfig.iServerFee
	info.iPlaytype = self.m_pCommonConfig.iPlaytype
	info.iPlaytypeStr = self.m_pPlaytypeStr
	info.iMaxCardCount = self:onGetMaxCardCount()
	info.iMaxUserCount = self:onGetGameTableMaxUserCount()
	info.iOutCardTime = self.m_pCommonConfig.iOutCardTime - 1
	info.iOperationTime = self.m_pCommonConfig.iOperationTime - 1
	info.iUserTable = {}
	for _, kUser in pairs(self.m_pGameUsers) do
		local pTemp = {}
		pTemp.iUserId = kUser:onGetUserId()
		pTemp.iSeatId = kUser:onGetSeatId()
		pTemp.iMoney = kUser:onGetMoney()
		pTemp.iReady = kUser:onGetReady()
		pTemp.iIsOnline = kUser:onGetIsOnline()
		pTemp.iAi = kUser:onGetIsAi()
		pTemp.iUserInfoStr = kUser.m_pUserInfoStr
		info.iUserTable[#info.iUserTable + 1] = pTemp
	end
	info.iLocalGameType = self:onGetLocalGameType()
	info.iRoomOwnerName = ""
	info.iGameRoundInfo = json.encode(self.m_pGameRound:onGetGameRoundInfo())
	
	self:onSendPackage(pUser:onGetUserId(), name, info)
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

function GameTable:onDealUserLogoutTableSuccess(pUserId)
	local pUser = self:onGetUserByUserId(pUserId)
	if not pUser then return -1 end
	-- 广播用户退出房间
	self:onBroadcastUserLogoutTable(pUser)
	-- 移除这个玩家
	self:onRemoveUser(pUser)
	-- 上报用户退出
	self:onGameTableUpdateData()

	if self:onGetTableUserCount() <= 0 then
		self:onDimissGoldFieldRoom()
	end
end

function GameTable:onDimissGoldFieldRoom()
	self.m_pCsQueue(function()
		for _, kUser in pairs(self.m_pGameUsers or {}) do
			self:onDealUserLogoutTableSuccess(kUser:onGetUserId())
		end
		self:onGameTableDeleteData()
		self:onGameTableDeleteGoldField()
		self:setTableStatus(tableStatusMap.TABLE_STATUS_BATTLE_DEAD)
		-- 延时将自己销毁
		self:onDelayedDtorGameTable()
	end)
end

function GameTable:onGameTableDeleteGoldField()
	local pGoldFieldId = self.m_pCommonConfig.iGoldFieldId
	local pTableId = self.m_pCommonConfig.iTableId
	pcall(skynet.call, self.m_pGameServer, "lua", "onGameTableDeleteGoldField", pGoldFieldId, pTableId)
	-- local pRet = skynet.call(self.m_pGameServer, "lua", "onGameTableDeleteData", data)
end

-- 更新数据库用户金币
function GameTable:onUpdateDataBaseUserMoney(info)
	local pRet = skynet.call(self.m_pGameServer, "lua", "onUpdateUserMoney", info)
end

function GameTable:onServerSetBillGoldFieldDetail()
	if self:isTableStatusBattleDead() then
		return
	end
	local info = {}
	info.iGameCode = self.m_pCommonConfig.iGameCode
	info.iGoldFieldId = self.m_pCommonConfig.iGoldFieldId
	info.iGoldFieldName = self.m_pCommonConfig.iGoldFieldName or 0
	info.iGameLevel = self.m_pCommonConfig.iGameLevel
	info.iEndTimeStamp = os.time()
	info.iBattleTotalRound = 1
	info.iLocalGameType = self:onGetLocalGameType()
	info.iUserIdTable = {}
	for _, kUser in pairs(self.m_pGameUsers) do
		table.insert(info.iUserIdTable, kUser:onGetUserId())
	end
	
	skynet.send(self.m_pGameServiceMgr, "lua", "onServerSetBillGoldFieldDetail", json.encode(info))
end

-- 一局结束
function GameTable:onGameRoundStop(result)
	for k, v in pairs(self.m_pGameUsers) do
		v:onSetReady(0)
	end
	-- 上报牌局
	self:onServerSetBillGoldFieldDetail()

	-- 将金币保存到数据库中
	for _, kUser in pairs(self.m_pGameUsers) do
		local pTurnMoney = kUser:onGetTurnMoney()
		if kUser:onGetMoney() < 0 then
			pTurnMoney = pTurnMoney - kUser:onGetMoney()
			kUser:onSetMoney(0)
		end
		local info = {
			iUserId = kUser:onGetUserId(),
			iTurnMoney = pTurnMoney,
		}
		self:onUpdateDataBaseUserMoney(info)
	end
	self:setTableStatus(tableStatusMap.TABLE_STATUS_NONE)
	-- 如果玩家离线则清掉
	for k, v in pairs(self.m_pGameUsers) do
		if 1 ~= v:onGetIsOnline() then
			self:onDealUserLogoutTableSuccess(v:onGetUserId())
		else
			v:onSetLoginTimeStamp(os.time())
		end
	end
	-- 启动退出没有准备玩家定时器，如果1分钟没准备有开始牌局则退出
	self:onStartDimissNotReadyTimer(1 * 1000)
	self:onStartDimissNotNoramlGoldFieldTimer(20 * 60 * 1000)
end

function GameTable:onStartDimissNotReadyTimer(time)
	Log.d(TAG, "onStartDimissNotReadyTimer time[%s]", time)
	self.m_pScheduleMgr:unregister(self.m_pDisMissNotReadyTimer)
	if self:isTableStatusPlaying() then return end
	local pCallback = self.onDimissNotReadyTimer
	self.m_pDisMissNotReadyTimer = self.m_pScheduleMgr:register(pCallback, time, -1, time, self)	
end

function GameTable:onDimissNotReadyTimer()
	local pDismissUsersTable = {}
	for _, kUser in pairs(self.m_pGameUsers) do
		if kUser:onGetReady() == 0 and os.time() - kUser:onGetLoginTimeStamp() > 45 then  --房间内45秒没有准备则移除玩家
			table.insert(pDismissUsersTable, kUser:onGetUserId())
		end
	end

	for _, kUserId in pairs(pDismissUsersTable) do
		self:onDealUserLogoutTableSuccess(kUserId)
	end
end

-- 金币场强制解散规定，防止卡房
-- 1.如果超过30分钟牌局未开始，则解散房间
-- 2.如果牌局开始单局超过8分钟未结束，则解散房间
function GameTable:onStartDimissNotNoramlGoldFieldTimer(pTime)
	Log.d(TAG, "onStartDimissNotNoramlGoldFieldTimer pTime[%s]", pTime)
	self.m_pScheduleMgr:unregister(self.m_pDisMissNotNoramlTimer)
	local pCallback = self.onDimissGoldFieldRoom
	self.m_pDisMissNotNoramlTimer = self.m_pScheduleMgr:register(pCallback, pTime, 1, 0, self)
end

--------------------------------------- redis -----------------------------------



--------------------------------------- 网络包组装函数 -----------------------------
function GameTable:onDisConnect(pUserId)
	self.m_pCsQueue(function()
		Log.d(TAG, "onDisConnect pUserId[%s]", pUserId)
		if not pUserId then return end
		local pUser = self:onGetUserByUserId(pUserId)
		if not pUser then return end
		pUser:onSetIsOnline(0)
		-- 如果是对战场或者金币牌局中，则不清除玩家
		if self:isTableStatusPlaying() then
			self:onServerBCUserIsOnline(pUserId)
		else
			self:onDealUserLogoutTableSuccess(pUserId)
		end
	end)
end

function GameTable:onServerBCUserIsOnline(pUserId)
	local pUser = self:onGetUserByUserId(pUserId)
	if not pUser then return end
	local name = "ServerBCUserIsOnline"
	local info = {}
	info.iUserId = pUserId
	info.iIsOnline = pUser:onGetIsOnline()
	local pRemainTime = -1
	info.iTime = pRemainTime
	self:onBroadcastTableUsers(name, info)
end

function GameTable:onDealNewUserReconnect(pUserId)
	local pUser = self:onGetUserByUserId(pUserId)
	if not pUser then return end 
	-- 设置玩家在线
	pUser:onSetIsOnline(1)

	local name = "ServerNewUserReconnect"
	local info = {}
	info.iGameCode = self.m_pCommonConfig.iGameCode
	info.iRoomType = self.m_pCommonConfig.iRoomType
	info.iRoomOwnerId = 0
	info.iBattleTotalRound = 0
	info.iBattleCurRound = 0
	info.iGameLevel = self.m_pCommonConfig.iGameLevel
	info.iTableId = self.m_pCommonConfig.iTableId
	info.iTableName = self.m_pCommonConfig.iTableName
	info.iBasePoint = self.m_pCommonConfig.iBasePoint
	info.iServerFee = self.m_pCommonConfig.iServerFee
	info.iPlaytype = self.m_pCommonConfig.iPlaytype
	info.iPlaytypeStr = self.m_pPlaytypeStr
	info.iMaxCardCount = self:onGetMaxCardCount()
	info.iMaxUserCount = self:onGetGameTableMaxUserCount()
	info.iOutCardTime = self.m_pCommonConfig.iOutCardTime - 1
	info.iOperationTime = self.m_pCommonConfig.iOperationTime - 1
	info.iIsInGame = self:isTableStatusPlaying() and 1 or 0
	info.iLocalGameType = self:onGetLocalGameType()
	info.iRoomOwnerName = ""
	info.iGameRoundInfo = json.encode(self.m_pGameRound:onGetGameRoundInfo())
	info.iUserTable = {}
	for k, v in pairs(self.m_pGameUsers) do
		local pTemp = {}
		pTemp.iUserId = v:onGetUserId()
		pTemp.iSeatId = v:onGetSeatId()
		pTemp.iMoney = v:onGetMoney()
		pTemp.iReady = v:onGetReady()
		pTemp.iIsOnline = v:onGetIsOnline()
		pTemp.iAi = v:onGetIsAi()
		pTemp.iUserInfoStr = v.m_pUserInfoStr
		pTemp.iUserGameInfo = json.encode(self.m_pGameRound:onGetUserGameInfo(v, pUser))
		pTemp.iExtendInfo = json.encode(self.m_pGameRound:onGetUserExtendInfo(v, pUser))
		info.iUserTable[#info.iUserTable + 1] = pTemp
	end
	self:onSendPackage(pUser:onGetUserId(), name, info)
	self.m_pGameRound:onUserReconnect(pUser)
	self:onServerBCUserIsOnline(pUser:onGetUserId())
end

function GameTable:onUserReconnect(pUserId)
	self.m_pCsQueue(function()
		self:onDealNewUserReconnect(pUserId)
	end)
end

function GameTable:isTableStatusNone()
	return self.m_pTableStatus == tableStatusMap.TABLE_STATUS_NONE
end

function GameTable:isTableStatusPlaying()
	return self.m_pTableStatus == tableStatusMap.TABLE_STATUS_PLAYING
end

function GameTable:isTableStatusBattleDead()
	return self.m_pTableStatus == tableStatusMap.TABLE_STATUS_BATTLE_DEAD
end

-------------------------------------------- socket ------------------------------------------
function GameTable:ClientUserReady(pData, pUserId)
	local pUser = self:onGetUserByUserId(pUserId)
	if not pUser then return end
	if self:isTableStatusPlaying() or self:isTableStatusBattleDead() then
		return
	end
	-- 如果玩家钱不够，则要踢掉
	if pUser:onGetMoney() < self.m_pCommonConfig.iNeedMoney then
		-- self:onDealUserLogoutTableSuccess(pUserId)
		return
	end
	if 1 == pUser:onGetReady() then return end
	pUser:onSetReady(pData.iReady or 0)
	self:onBroadcastUserReady(pUser)
	self:onCheckGameTableStartGame()
end

function GameTable:ClientUserLogoutGame(pData, pUserId)
	Log.d(TAG, "ClientUserLogoutGame pUserId[%s] status[%s]", pUserId, self.m_pTableStatus)
	local pUser = self:onGetUserByUserId(pUserId)
	if not pUser then return end
	if self:isTableStatusPlaying() or self:isTableStatusBattleDead() then return end
	self:onDealUserLogoutTableSuccess(pUserId)
end

return GameTable