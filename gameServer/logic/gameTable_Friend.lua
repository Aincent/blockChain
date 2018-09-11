local skynet = require "skynet"
local socket = require "skynet.socket"
local sharedata = require "skynet.sharedata"
local json = require("cjson")
local GameUser = require("logic/gameUser")
local queue = require "skynet.queue"
local TAG = "GameTable"

local GameTable = require("logic/gameTable")

local tableStatusMap = {
	TABLE_STATUS_NONE = 0,  -- 无状态，初始完成，玩家可以进来
	TABLE_STATUS_PLAYING = 1, -- 牌局进行中
	TABLE_STATUS_ROUND_STOP = 2, -- 对战一局牌局完成
	TABLE_STATUS_BATTLE_STOP = 3, -- 对战牌局完成
	TABLE_STATUS_BATTLE_DEAD = 4, -- 死亡状态，等待回收
}

function GameTable:onInitFriendBattleConfig(data)
	self.m_pCsQueue(function()
		self:setTableStatus(tableStatusMap.TABLE_STATUS_NONE)
		self.m_pCommonConfig.iPlaytype = data.iPlaytype or 0
		self.m_pFriendBattleConfig = {}
		self.m_pFriendBattleConfig.iPayType = data.iPayType or 0
		self.m_pFriendBattleConfig.iRoomOwnerId = data.iUserId
		self.m_pFriendBattleConfig.iPlayId = data.iPlayId or 0
		self.m_pFriendBattleConfig.iBattleTotalRound = math.floor(data.iBattleTotalRound)
		self.m_pFriendBattleConfig.iBattleCurRound = 0
		self.m_pFriendBattleConfig.iCreateForOther = data.iCreateForOther or 0
		-- 如果是代开房，则必须是房主支付
		if 1 == self.m_pFriendBattleConfig.iCreateForOther then
			self.m_pFriendBattleConfig.iPayType = DefineType.ROOMCARD_PAYTYPE_OWNER
		end
		self.m_pFriendBattleConfig.iStartGameUserId = 0
		local pTimeStamp = os.time()
		self.m_pFriendBattleConfig.iTimeStamp = pTimeStamp
		self.m_pFriendBattleConfig.iBattleId = string.format("%s%s", self.m_pCommonConfig.iTableId, pTimeStamp)

		local pIsOk, pExtendTable = pcall(json.decode, data.iExtendInfo or "{}")
		self.m_pFriendBattleConfig.iExtendTable = pIsOk and pExtendTable or {}
		-- json.decode(data.iExtendInfo or "{}")
		-- 设置房主信息
		local pIsOk, pUserInfo = pcall(json.decode, data.iUserInfoStr or "{}")
		self.m_pFriendBattleConfig.iRoomUserInfo = pIsOk and pUserInfo or {}
		-- 设置游戏中的type
		local pLocalGameType = math.floor(tonumber(self.m_pFriendBattleConfig.iExtendTable.iLocalGameType) or 0x0101)
		self.m_pCommonConfig.iLocalGameType = pLocalGameType

		if self.m_pFriendBattleConfig.iExtendTable.iBasePoint and self.m_pFriendBattleConfig.iExtendTable.iBasePoint >= 1 then
			self.m_pCommonConfig.iBasePoint = math.floor(self.m_pFriendBattleConfig.iExtendTable.iBasePoint)
		end
		-- 俱乐部
		self.m_pFriendBattleConfig.iClubId = 0
		if data.iClubId and data.iClubId > 0 then
			self.m_pFriendBattleConfig.iClubId = data.iClubId
		end

		-- 设置高级选项
		self.m_pFriendBattleConfig.iGaoJiXuanXiang = 0
		if self.m_pFriendBattleConfig.iExtendTable.iGaoJiXuanXiang and self.m_pFriendBattleConfig.iExtendTable.iGaoJiXuanXiang >= 1 then
			self.m_pFriendBattleConfig.iGaoJiXuanXiang = math.floor(self.m_pFriendBattleConfig.iExtendTable.iGaoJiXuanXiang)
		end

		local pRoundPath = nil
		if self.m_pPlaytypeConfig.iGameRoundPath then
			pRoundPath = self.m_pPlaytypeConfig.iGameRoundPath[self:onGetLocalGameType()]
		end

		if not pRoundPath then
			self:onDismissFriendBattleRoom()
			return
		end

		self.m_pGameRound    = require(pRoundPath)
		self.m_pGameRound:init(self, self.m_pScheduleMgr)

		-- 设置牌局人数
		if self.m_pFriendBattleConfig.iExtendTable then
			local pUserCount = self.m_pFriendBattleConfig.iExtendTable.iUserCount
			local pTableUserCount = self:onGetGameTableMaxUserCount()
			if pUserCount and pUserCount >= 2 and pUserCount <= pTableUserCount then
				self.m_pCommonConfig.pSetUpMaxUserCount = pUserCount
			elseif self.m_pGameRound.isCanBuXianRenShu and self.m_pGameRound:isCanBuXianRenShu() then
				self.m_pCommonConfig.pSetBuXianRenShu = pTableUserCount
			end 
		end

		local pUserCount = self:onGetGameTableMaxUserCount()
		self.m_pFriendBattleConfig.iPlaytypeStr = self.m_pGameRound.m_pGameRule:onGetPlaytypeStr(self.m_pFriendBattleConfig, pUserCount)

		self.m_pFriendBattleConfig.iDismissBattleTable = nil
		self.m_pFriendBattleConfig.iBattleTurnMoneyTable = {}

		self.m_pFriendBattleConfig.iDisConnetTimeTable = {}

		self.m_pFriendBattleConfig.iPreRoundGameStopTable = {}

		-- 房间内的钻石消耗
		self.m_pFriendBattleConfig.iUpdateRoomCardTable = {}

		-- 启动销毁房间定时器，如果30分钟没有开始牌局则解散
		local pTime = 30 * 60 * 1000
		if 1 == self.m_pFriendBattleConfig.iCreateForOther then
			pTime = 1 * 60 * 60 * 1000
		end
		self:onStartDimissFriendBattleTimer(pTime)
		
		Log.dump(TAG, data, "data")
		Log.dump(TAG, self.m_pFriendBattleConfig, "self.m_pFriendBattleConfig")
		Log.dump(TAG, self.m_pCommonConfig, "self.m_pCommonConfig")
	end)
end

function GameTable:onCheckUserCanLoginTable(data, userId)
	-- 判断房间的状态是否可进
	if not self:onCheckTableStatusCanEnter(data) then
		return DefineType.ERROR_LOGIN_TABLE_STATUS_ERROR
	end
	-- 判断桌子是否已满
	if self:onGetTableUserCount() >= self:onGetGameTableMaxUserCount() then
		return DefineType.ERROR_LOGIN_TABLE_FULL
	end
	-- 判断该玩家是否已经在这个桌子上
	if self:onGetUserByUserId(userId) then
		return DefineType.ERROR_LOGIN_TABLE_FULL
	end

	-- 获取玩家的基本信息
	if not self:onGetUserInfo(data, userId) then
		return DefineType.ERROR_LOGIN_WRONG_DATA
	end

	-- 判断玩家房卡是否满足
	if not self:onCheckUserEnoughRoomCard(data) then
		if data.iCreateForOther and 1 == data.iCreateForOther then
			return DefineType.ERROR_LOGIN_CREATE_FOR_OTHER
		else
			return DefineType.ERROR_LOGIN_NOT_ENOUGH_ROOMCARD
		end
	end

	-- 判断如果是俱乐部，玩家是否在这个俱乐部中
	if not self:onCheckUserIsInClub(data) then
		-- 如果自己是房主，则无法创建
		if self:isRoomOwner(data.iUserId) then
			return DefineType.ERROR_LOGIN_CREATE_NOT_IN_CLUB
		else
			return DefineType.ERROR_LOGIN_USER_NOT_IN_CLUB
		end
	end

	return nil
end

-- 退钻石
function GameTable:onServerSendBackRoomCard()
	Log.d(TAG, "onServerSendBackRoomCard")
	-- 如果还不需要付房费，如果是代开房且已经付了房费，则退回房费
	if not self.m_pFriendBattleConfig.iNeedPayRoomCard and 1 == self.m_pFriendBattleConfig.iCreateForOther 
		and self.m_pFriendBattleConfig.iIsRoomPaid then

		local pUserId = self.m_pFriendBattleConfig.iRoomOwnerId
		local info = {
			iUserId = pUserId,
			iRoomCardNum = self:onGetNeedRoomCardCount(),
		}

		local pRet = skynet.call(self.m_pGameServer, "lua", "onUpdateUserRoomCard", info)
		if pRet then
			-- 删掉该玩家的钻石消耗
			for kIndex, kUpdateInfo in pairs(self.m_pFriendBattleConfig.iUpdateRoomCardTable) do
				if kUpdateInfo.iUserId == pUserId then
					table.remove(self.m_pFriendBattleConfig.iUpdateRoomCardTable, kIndex)
					break
				end
			end
		end
		self.m_pFriendBattleConfig.iIsRoomPaid = false
	end
end

function GameTable:onClientCmdLoginGame(data, userId)
	return self.m_pCsQueue(function()
		local pStatus = self:onCheckUserCanLoginTable(data, userId)
		-- Log.dump(TAG, data, "data")
		-- 登陆成功
		if not pStatus then
			-- 如果是代开房间,且该玩家必须是代理
			if data.iCreateForOther and 1 == data.iCreateForOther then
				if 1 ~= data.iIsAgent and 2 ~= data.iIsAgent and 3 ~= data.iIsAgent then
					self:onDismissFriendBattleRoom()
					return
				end
				if not data.iServerAuto then
					local name = "ServerUserCreateForOther"
					local info = {}
					info.iUserId = userId
					info.iTableId = self.m_pCommonConfig.iTableId
					info.iRoomCardNum = self:onGetNeedRoomCardCount()
					info.iPlaytypeStr = self.m_pFriendBattleConfig.iPlaytypeStr
					local pGameInfoTable = {}
					pGameInfoTable.iLocalGameType = self:onGetLocalGameType()
					info.iGameInfo = json.encode(pGameInfoTable)
					self:onSendPackage(userId, name, info)
				end
				self:onGameTableUpdateData()
				self:onServerUpdateOneBattleBillInfo()
				local pNeedRoomCard = self:onGetNeedRoomCardCount()
				self:onUserPayRoomCard(self.m_pFriendBattleConfig.iRoomOwnerId, pNeedRoomCard)
				self.m_pFriendBattleConfig.iIsRoomPaid = true
				self.m_pIsClubAutoOpenGameTable = true
				return true
			end
			self:onDealUserLoginSuccess(data, userId)
			self.m_pIsClubAutoOpenGameTable = true
			return true
		else
			if not data.iServerAuto then
				local name = "ServerUserLoginGameFail"
				local info = pStatus
				self:onSendPackage(userId, name, info)
			else
				Log.e(TAG, "自动创建失败的原因 %s %s", pStatus.iErrorType, pStatus.iErrorMsg)
			end
			-- 如果是对战场,且房主登陆失败,则解散该房间
			if self:isRoomOwner(userId) then
				self:onDismissFriendBattleRoom()
			end
		end 
		return false
	end)
end

function GameTable:onStartDimissFriendBattleTimer(time)
	Log.d(TAG, "onStartDimissFriendBattleTimer time[%s]", time)
	self.m_pScheduleMgr:unregister(self.m_pHalfwayStopTimer)
	self.m_pScheduleMgr:unregister(self.m_pDisMissBattleTimer)
	self.m_pScheduleMgr:unregister(self.m_pGameRoundDisconnetTimer)
	if self:isTableStatusPlaying() then return end
	if self:isTableStatusBattleDead() then return end
	local pCallback = self.onDismissFriendBattleRoom
	self.m_pDisMissBattleTimer = self.m_pScheduleMgr:registerOnceNow(pCallback, time, self)
end

function GameTable:onForcedDismissFriendBattleRoom(pUserId)
	if self.m_pFriendBattleConfig.iClubId == nil or self.m_pFriendBattleConfig.iClubId <= 0 then
		local pMsg = "非茶馆房间不能强制解散！"
		self:onServerUserShowHints(pUserId, 1, pMsg)
		return
	end
	if not self:isRoomOwner(pUserId) then 
		local pMsg = "非房主不能强制解散该房间！"
		self:onServerUserShowHints(pUserId, 1, pMsg)
		return 
	end
	if self:isTableStatusPlaying() or self:isTableStatusRoundStop() then
		local pMsg = "强制解散房间成功！"
		self:onServerUserShowHints(self.m_pFriendBattleConfig.iRoomOwnerId, 0, pMsg)

		pMsg = "本房间已被群主解散！"
		for k, v in pairs(self.m_pGameUsers or {}) do
			local kUserId = v:onGetUserId()
			if pMsg and not self:isRoomOwner(kUserId) then
				self:onServerUserShowHints(kUserId, 0, pMsg)
			end
		end
		self.m_pGameRound:onGameRoundStop(2)
	elseif not self:isTableStatusBattleStop() then
		self:onDismissFriendBattleRoom(2)
	end
end

function GameTable:onDismissFriendBattleRoom(pType)
	self.m_pCsQueue(function()
		if not self:isTableStatusBattleStop() and not self:isTableStatusNone() then 
			local pMsg = "该房间正在游戏中，无法解散！"
			self:onServerUserShowHints(self.m_pFriendBattleConfig.iRoomOwnerId, 0, pMsg)
			return 
		end

		if pType == 2 then --强制解散
			local pMsg = "强制解散房间成功！"
			self:onServerUserShowHints(self.m_pFriendBattleConfig.iRoomOwnerId, 0, pMsg)
		end

		Log.d(TAG, "onDismissFriendBattleRoom pTableId[%s]", self.m_pCommonConfig.iTableId)
		self.m_pScheduleMgr:unregister(self.m_pHalfwayStopTimer)
		self.m_pScheduleMgr:unregister(self.m_pDisMissBattleTimer)
		self.m_pScheduleMgr:unregister(self.m_pGameRoundDisconnetTimer)
		Log.d(TAG, "onDismissFriendBattleRoom pTableId[%s] self.m_pTableStatus[%s]", self.m_pCommonConfig.iTableId, self.m_pTableStatus)
		
		self:onServerSendBackRoomCard()

		local pMsg
		-- 房主代开房间解散
		if 1 == pType then
			pMsg = "房主主动解散房间！"
		elseif 2 == pType then
			pMsg = "本房间已被群主解散！"
		end
		for k, v in pairs(self.m_pGameUsers or {}) do
			local pUserId = v:onGetUserId()
			self:onDealUserLogoutTableSuccess(v:onGetUserId())
			if pMsg and not self:isRoomOwner(pUserId) then
				self:onServerUserShowHints(pUserId, 0, pMsg)
			end
		end
		self:onGameTableDeleteData()
		if self:isTableStatusNone() then
			self:onServerUpdateOneBattleBillInfo(1)
		end
		self:setTableStatus(tableStatusMap.TABLE_STATUS_BATTLE_DEAD)
		-- 将它从表中移除
		local pTableId = self.m_pCommonConfig.iTableId
		local pClubId = self.m_pFriendBattleConfig.iClubId
		skynet.call(self.m_pGameServiceMgr, "lua", "onDeleteOneRoomId", pTableId, pClubId)
		local pRoomUserId = self.m_pFriendBattleConfig.iRoomOwnerId
		Log.d(TAG, "self.m_pIsClubAutoOpenGameTable[%s]", self.m_pIsClubAutoOpenGameTable)
		if self.m_pIsClubAutoOpenGameTable then
			pcall(skynet.call, self.m_pGameServiceMgr, "lua", "onSendPackageToHallServiceMgr", "onClubAutoCreateFriendRoomMore", pRoomUserId, pClubId, self.m_pCommonConfig.iGameCode)
		end
		-- 延时将自己销毁
		self:onDelayedDtorGameTable()
	end)
end

function GameTable:onGetUserInfo(data, userId)
	local pKey = string.format("UserInfo_UserId_%s", userId)
	local pUserInfo = self:onExecuteRedisCmd(DefineType.REDIS_USERINFO, "GET", pKey)
	if pUserInfo and type(pUserInfo) == "string" then
		pUserInfo = json.decode(pUserInfo)
		-- data.iMoney = tonumber(pUserInfo.Money) or 0
		-- 好友场金币设置为0
		data.iMoney = 0
		data.iRoomCardNum = tonumber(pUserInfo.RoomCardNum) or 0
		data.iNickName = pUserInfo.NickName or ""
		data.iWinTimes = tonumber(pUserInfo.WinTimes) or 0
		data.iLoseTimes = tonumber(pUserInfo.LoseTimes) or 0
		data.iDrawTimes = tonumber(pUserInfo.DrawTimes) or 0
		data.iIsAgent = tonumber(pUserInfo.IsAgent) or 0 
		return true
	end
	return false
end

function GameTable:onCheckUserEnoughRoomCard(data)
	if self.m_pFriendBattleConfig.iIsRoomPaid then
		return true
	end
	local pNeedRoomCard = self:onGetNeedRoomCardCount()
	Log.d(TAG, "onCheckUserEnoughRoomCard data.iRoomCardNum[%s] , pNeedRoomCard[%s]", data.iRoomCardNum, pNeedRoomCard)
	if self:isOwnerPay() then
		if self:isRoomOwner(data.iUserId) then
			return data.iRoomCardNum >= pNeedRoomCard
		end
	elseif self:isWinnerPay() then
		return data.iRoomCardNum >= pNeedRoomCard
	elseif self:isSharePay() then
		return data.iRoomCardNum >= math.floor(pNeedRoomCard)
	end
	return true
end

function GameTable:onCheckUserIsInClub(data)
	if self.m_pFriendBattleConfig.iClubId > 0 then 
		return skynet.call(self.m_pGameServer, "lua", "onCheckUserIdInClub", data.iUserId, self.m_pFriendBattleConfig.iClubId)
	end
	return true
end

function GameTable:onCheckTableStatusCanEnter(data)
	Log.d(TAG, "onCheckTableStatusCanEnter status[%s]", self.m_pTableStatus)
	-- 只有当房间处于未开局的情况下才能进入
	if self:isTableStatusNone() then
		return true
	end
end

function GameTable:onUserPayRoomCard(pUserId, pNeedRoomCard)
	if self.m_pFriendBattleConfig.iIsRoomPaid then
		return true
	end
	local info = {
		iUserId = pUserId,
		iRoomCardNum = -pNeedRoomCard,
	}

	table.insert(self.m_pFriendBattleConfig.iUpdateRoomCardTable, info)

	local pRet = skynet.call(self.m_pGameServer, "lua", "onUpdateUserRoomCard", info)
end

function GameTable:onGetNeedRoomCardCount()
	local pTotolRound = self.m_pFriendBattleConfig.iBattleTotalRound
	local pMaxUserCount = self:onGetGameTableMaxUserCount()
	local pPayType = self.m_pFriendBattleConfig.iPayType
	return self.m_pGameRound:onGetGameRule():onGetNeedRoomCardCount(self.m_pPlaytypeConfig, pTotolRound, pMaxUserCount, pPayType)
end

function GameTable:isOwnerPay()
	return DefineType.ROOMCARD_PAYTYPE_OWNER == self.m_pFriendBattleConfig.iPayType
end

function GameTable:isWinnerPay()
	return DefineType.ROOMCARD_PAYTYPE_WINNER == self.m_pFriendBattleConfig.iPayType
end

function GameTable:isSharePay()
	return DefineType.ROOMCARD_PAYTYPE_SHARE == self.m_pFriendBattleConfig.iPayType
end

function GameTable:isRoomOwner(pUserId)
	return pUserId == self.m_pFriendBattleConfig.iRoomOwnerId
end

function GameTable:onDealUserLoginSuccess(data, userId)
	-- 分配一个座位号
	local seatId = self:onAllocSeatId()
	if not seatId then return -1 end
	-- 设置用户信息
	local newUser = new(GameUser, data, userId, seatId)
	if not newUser then return -1 end
	self.m_pGameUserLoginCount = self.m_pGameUserLoginCount + 1
	newUser:onSetLoginCount(self.m_pGameUserLoginCount)
	self.m_pGameUsers[seatId] = newUser
	newUser:onSetIsOnline(1)
	-- 将当前玩牌桌子加入到redis中
	self:onDealUserLoginTableRedis(newUser)
	-- 返回玩家成功进入房间的包
	self:onSendUserLoginSuccess(newUser)
	-- 上报给GameServer
	self:onGameTableUpdateData()
	-- 写到账单redis
	self:onServerUpdateOneBattleBillInfo()
	-- 如果有相同IP则提示
	-- self:onServerDealUserSameIp(newUser:onGetUserId())
	-- 将自己的ID和GameServer绑定起来
	local pRet = skynet.call(self.m_pGameServiceMgr, "lua", "onUpdateGameServerData", {
			iGameServer = self.m_pGameServer,
			iUserId = newUser:onGetUserId()
		})
	-- 如果是好友对战，且可以默认准备
	if not self:isOneUserStartGame()
		and self.m_pGameRound.m_pGameRule.isAutoReady and self.m_pGameRound.m_pGameRule:isAutoReady() then
		newUser:onSetReady(1)
	end
	-- 广播房间内的玩家有玩家进入
	self:onBroadcastUserEnterTable(newUser)
	if 1 == newUser:onGetReady() then
		self:onBroadcastUserReady(newUser)
		self:onCheckGameTableStartGame()
	end
	if self:isOneUserStartGame() then
		self:onServerUserStartGameUserId(userId)
	end
end

function GameTable:onServerUserStartGameUserId(pUserId)
	if not self:isOneUserStartGame() then return end
	if self.m_pFriendBattleConfig.iStartGameUserId <= 0 then
		self.m_pFriendBattleConfig.iStartGameUserId = pUserId
		local name = "ServerUserStartGameUserId"
		local info = {}
		info.iUserId = self.m_pFriendBattleConfig.iStartGameUserId
		info.iNeedCount = 2
		self:onSendPackage(info.iUserId, name, info)
	end
end

function GameTable:onServerUserShowHints(pUserId, pType, pMsg)
	local name = "ServerUserShowHints"
	local info = {}
	info.iShowType = pType
	info.iShowMsg = pMsg
	self:onSendPackage(pUserId, name, info)
end

function GameTable:onServerDealUserSameIp(pUserId)
	local pUser = self:onGetUserByUserId(pUserId)
	if not pUser then return end
	for k, v in pairs(self.m_pGameUsers) do
		Log.d(TAG, "onServerDealUserSameIp pUserId[%s] IP[%s]", v:onGetUserId(), v:onGetClientIp())
	end
	-- 如果该玩家和别的玩家同IP，则提示所有人
	local pSameIpTable = {}
	for k, v in pairs(self.m_pGameUsers) do
		if v ~= pUser and pUser:onGetClientIp() == v:onGetClientIp() and pUser:onGetClientIp() ~= "" then
			pSameIpTable[#pSameIpTable + 1] = v
		end
	end
	if #pSameIpTable > 0 then
		pSameIpTable[#pSameIpTable + 1] = pUser
		local pMsg = "玩家"
		for k, v in pairs(pSameIpTable) do
			pMsg = string.format("%s %s", pMsg, v:onGetNickName())
		end
		pMsg = string.format("%s %s", pMsg, " 处于同一IP!")
		for k, v in pairs(self.m_pGameUsers) do
			self:onServerUserShowHints(v:onGetUserId(), 1, pMsg)
		end
		return
	end
	-- 如果该玩家在进入之前，已经有玩家同IP,则提示该玩家
	for k, v in pairs(self.m_pGameUsers) do
		for p, q in pairs(self.m_pGameUsers) do
			if v ~= q and v:onGetClientIp() == q:onGetClientIp() and v:onGetClientIp() ~= "" then
				pSameIpTable[#pSameIpTable + 1] = q
			end
		end
		if #pSameIpTable > 0 then
			pSameIpTable[#pSameIpTable + 1] = v
			local pMsg = "玩家"
			for k, v in pairs(pSameIpTable) do
				pMsg = string.format("%s %s", pMsg, v:onGetNickName())
			end
			pMsg = string.format("%s %s", pMsg, " 处于同一IP!")
			self:onServerUserShowHints(pUser:onGetUserId(), 1, pMsg)
			return
		end
	end
end

function GameTable:onServerUpdateOneBattleBillInfo(pIsDissBattle)
	if self:isTableStatusBattleDead() then
		return
	end
	local pHasGameRule = self.m_pGameRound and self.m_pGameRound.m_pGameRule
	local info = {}
	info.iGameCode = self.m_pCommonConfig.iGameCode
	info.iPlayId = self.m_pFriendBattleConfig.iPlayId
	info.iBattleId = self.m_pFriendBattleConfig.iBattleId
	info.iTableId = self.m_pCommonConfig.iTableId
	info.iGameLevel = self.m_pCommonConfig.iGameLevel
	info.iRoomOwnerId = self.m_pFriendBattleConfig.iRoomOwnerId
	info.iTimeStamp = self.m_pFriendBattleConfig.iTimeStamp
	info.iPlaytypeStr = self.m_pFriendBattleConfig.iPlaytypeStr
	info.iPaytypeStr = pHasGameRule and self.m_pGameRound.m_pGameRule:onGetPaytypeStr(self.m_pFriendBattleConfig)
	info.iEndTimeStamp = os.time()
	info.iBattleTotalRound = self.m_pFriendBattleConfig.iBattleTotalRound
	info.iBattleCurRound = self.m_pFriendBattleConfig.iBattleCurRound
	info.iBattleStatus = 1
	info.iBattleStopUserTable = self.m_pGameRound and self.m_pGameRound:onGetFriendBattleGameOverUserTable() or {}
	info.iCreateForOther = self.m_pFriendBattleConfig.iCreateForOther
	info.iPlaytypeStr = self.m_pFriendBattleConfig.iPlaytypeStr
	info.iRoomOwnerName = self.m_pFriendBattleConfig.iRoomUserInfo.name or ""
	info.iLocalGameType = self:onGetLocalGameType()
	info.iIsDissBattle = pIsDissBattle or 0
	info.iClubId = self.m_pFriendBattleConfig.iClubId
	info.iRoomCardNum = self:onGetNeedRoomCardCount()
	info.iMaxUserCount = self:onGetMaxUserCount()
	info.iGameName = (self.m_pGameRound and self.m_pGameRound.m_pGameRule) and self.m_pGameRound.m_pGameRule:onGetGameName()
	info.iUpdateRoomCardTable = {}
	if self:isTableStatusBattleStop() then
		info.iBattleStatus = 0
		info.iUpdateRoomCardTable = self.m_pFriendBattleConfig.iUpdateRoomCardTable
	elseif not self:isTableStatusNone() then
		info.iBattleStatus = 2
	end

	skynet.send(self.m_pGameServiceMgr, "lua", "onServerUpdateOneBattleBillInfo", info.iBattleId, json.encode(info))
end

function GameTable:onServerAddOneRoundDetail()
	if self:isTableStatusBattleStop() or self:isTableStatusBattleDead() or self:isTableStatusRoundStop() then
		return
	end
	local info = {}
	info.iTimeStamp = os.time()
	info.iLookbackId = skynet.call(self.m_pGameServiceMgr, "lua", "onGetANewLookbackId")
	info.iTurnMoneyTable = {}
	for k, v in pairs(self.m_pGameUsers) do
		local pTemp = {}
		pTemp.iUserId = v:onGetUserId()
		pTemp.iTurnMoney = v:onGetTurnMoney()
		table.insert(info.iTurnMoneyTable, pTemp)
	end
	table.insert(self.m_pFriendBattleConfig.iBattleTurnMoneyTable, info)
end

function GameTable:onServerUserSetBillDetail()
	if self:isTableStatusBattleStop() or self:isTableStatusBattleDead() or self:isTableStatusRoundStop() then
		return
	end

	local pBattleId = self.m_pFriendBattleConfig.iBattleId
	local pTurnMoneyTable = self.m_pFriendBattleConfig.iBattleTurnMoneyTable
	local pLookbackId = pTurnMoneyTable[#pTurnMoneyTable].iLookbackId
	local pLookbackTable = self.m_pGameRound.m_pOneRoundLookbackTable or {}
	skynet.send(self.m_pGameServiceMgr, "lua", "onServerUserSetBillLookback", pLookbackId, pLookbackTable)
	
	skynet.send(self.m_pGameServiceMgr, "lua", "onServerUserSetBillDetail", pBattleId, json.encode(pTurnMoneyTable))
end

function GameTable:onCheckGameTableStartGame()
	Log.d(TAG, "onCheckGameTableStartGame")
	if self:isTableStatusPlaying() or self:isTableStatusBattleStop() or self:isTableStatusBattleDead() then
		Log.e(TAG, "当前状态不对,iTableId[%s] iTableStatus[%s]", self.m_pCommonConfig.iTableId, self.m_pTableStatus)
		return 
	end
	Log.d(TAG, "onCheckGameTableStartGame ready[%s] max[%s]", self:onGetReadyUserCount(), self:onGetGameTableMaxUserCount())
	-- 监测人数，是否可以开始游戏
	if self:onGetReadyUserCount() == self:onGetGameTableMaxUserCount() then
		self:setTableStatus(tableStatusMap.TABLE_STATUS_PLAYING)
		
		self.m_pFriendBattleConfig.iBattleCurRound = self.m_pFriendBattleConfig.iBattleCurRound + 1
		-- 清除定时器
		self.m_pScheduleMgr:unregister(self.m_pDisMissBattleTimer)
		self.m_pScheduleMgr:unregister(self.m_pGameRoundDisconnetTimer)
		-- self.m_pScheduleMgr:unregister(self.m_pHalfwayStopTimer)

		self:onServerUpdateOneBattleBillInfo()
		self.m_pGameRound:onGameRoundStart()
		self:onGameTableUpdateData()
		-- 减少一个房间，并开始自动开房
		if 1 == self.m_pFriendBattleConfig.iBattleCurRound then
			local pTableId = self.m_pCommonConfig.iTableId
			local pClubId = self.m_pFriendBattleConfig.iClubId
			local pRet = skynet.call(self.m_pGameServiceMgr, "lua", "onGameTableStartGame", pTableId, pClubId)
			local pRoomUserId = self.m_pFriendBattleConfig.iRoomOwnerId
			Log.d(TAG, "self.m_pIsClubAutoOpenGameTable[%s]", self.m_pIsClubAutoOpenGameTable)
			if self.m_pIsClubAutoOpenGameTable then
				pcall(skynet.call, self.m_pGameServiceMgr, "lua", "onSendPackageToHallServiceMgr", "onClubAutoCreateFriendRoomMore", pRoomUserId, pClubId, self.m_pCommonConfig.iGameCode)
			end
		end
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
	info.iRoomOwnerId = self.m_pFriendBattleConfig.iRoomOwnerId
	info.iBattleTotalRound = self.m_pFriendBattleConfig.iBattleTotalRound
	info.iBattleCurRound = self.m_pFriendBattleConfig.iBattleCurRound
	info.iGameLevel = self.m_pCommonConfig.iGameLevel
	info.iTableName = self.m_pCommonConfig.iTableName
	info.iTableId = self.m_pCommonConfig.iTableId
	info.iBasePoint = self.m_pCommonConfig.iBasePoint
	info.iServerFee = self.m_pCommonConfig.iServerFee
	info.iPlaytype = self.m_pCommonConfig.iPlaytype
	info.iPlaytypeStr = self.m_pFriendBattleConfig.iPlaytypeStr
	info.iMaxCardCount = self:onGetMaxCardCount()
	info.iMaxUserCount = self:onGetMaxUserCount()
	info.iOutCardTime = self.m_pCommonConfig.iOutCardTime - 1
	info.iOperationTime = self.m_pCommonConfig.iOperationTime - 1
	info.iUserTable = {}
	for _, kUser in pairs(self.m_pGameUsers) do
		local pTemp = {}
		pTemp.iUserId = kUser:onGetUserId()
		pTemp.iSeatId = kUser:onGetSeatId()
		-- 这里需要满足一下初始化时需要初始化为特定的值
		if self.m_pGameRound and self.m_pGameRound.onGetUserInitMoney then
			if self.m_pFriendBattleConfig.iBattleCurRound <= 0 then
				local pUserInitMoney = self.m_pGameRound:onGetUserInitMoney()
				kUser:onSetMoney(pUserInitMoney or kUser:onGetMoney())
			end
		end
		pTemp.iMoney = kUser:onGetMoney()
		pTemp.iReady = kUser:onGetReady()
		pTemp.iIsOnline = kUser:onGetIsOnline()
		pTemp.iUserInfoStr = kUser.m_pUserInfoStr
		info.iUserTable[#info.iUserTable + 1] = pTemp
	end
	info.iLocalGameType = self:onGetLocalGameType()
	info.iRoomOwnerName = self.m_pFriendBattleConfig.iRoomUserInfo.name
	info.iGameRoundInfo = json.encode(self.m_pGameRound:onGetGameRoundInfo())
	
	if not pIsLookback then
		self:onSendPackage(pUser:onGetUserId(), name, info)
	else
		return name, info
	end
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
	if not pUser then
		return -1
	end
	-- 广播用户退出房间
	self:onBroadcastUserLogoutTable(pUser)
	-- 处理redis
	self:onDealUserLogoutTableRedis(pUser)
	-- 移除这个玩家
	self:onRemoveUser(pUser)
	-- 上报用户退出
	self:onGameTableUpdateData()
	if not self:isTableStatusBattleStop() then
		self:onServerUpdateOneBattleBillInfo()
	end

	if self:isOneUserStartGame() then
		-- 维护一下桌子上谁是最早进来的
		if pUserId == self.m_pFriendBattleConfig.iStartGameUserId then
			self.m_pFriendBattleConfig.iStartGameUserId = 0
			local tUser = nil
			for _, kUser in pairs(self.m_pGameUsers) do
				if not tUser or tUser:onGetLoginCount() > kUser:onGetLoginCount() then
					tUser = kUser
				end
			end
			-- 需不需要提示该玩家可以准备开始
			if tUser then
				self:onServerUserStartGameUserId(tUser:onGetUserId())
			end
		end
	end

	if self:onGetTableUserCount() <= 0 and self:isTableStatusBattleStop() then
		self:onDismissFriendBattleRoom()
	end
end

-- 更新数据库用户金币
function GameTable:onUpdateDataBaseUserMoney(info)
	local pRet = skynet.call(self.m_pGameServer, "lua", "onUpdateUserMoney", info)
end

-- 是否好友对战场全部结束
function GameTable:isFriendBattleGameOver(result)
	return 2 == result or self.m_pFriendBattleConfig.iBattleTotalRound == self.m_pFriendBattleConfig.iBattleCurRound
end

function GameTable:onDealGameStopWinnerPay()
	if self.m_pFriendBattleConfig.iIsRoomPaid then return end

	if self.m_pFriendBattleConfig.iNeedPayRoomCard then
		if self:isWinnerPay() then
			local pWinnerUsers = {}
			for _, kUser in pairs(self.m_pGameUsers) do
				local pTurnMoney = kUser:onGetMoney()
				if #pWinnerUsers <= 0 or (#pWinnerUsers > 0 and pWinnerUsers[1]:onGetMoney() < pTurnMoney) then
					pWinnerUsers = {}
					pWinnerUsers[#pWinnerUsers + 1] = kUser
				elseif #pWinnerUsers > 0 and (pWinnerUsers[1]:onGetMoney() == pTurnMoney) then
					pWinnerUsers[#pWinnerUsers + 1] = kUser
				end
			end
			-- 如果有赢家，则均摊支付，如有无法均摊的则随机一个赢家支付无法均摊的房卡
			local pNeedRoomCard = self:onGetNeedRoomCardCount()
			if #pWinnerUsers > 0 then
				local pShareRoomCard = math.floor(pNeedRoomCard / #pWinnerUsers)
				for _, kUser in pairs(pWinnerUsers) do
					self:onUserPayRoomCard(kUser:onGetUserId(), pShareRoomCard)
				end
				if pNeedRoomCard - pShareRoomCard * #pWinnerUsers > 0 then
					math.randomseed(tostring(os.time()):reverse():sub(1, 6))
					self:onUserPayRoomCard(pWinnerUsers[math.random(1, #pWinnerUsers)]:onGetUserId(), pNeedRoomCard - pShareRoomCard * #pWinnerUsers)
				end
			end
			-- Log.dump(TAG, pWinnerUsers, "pWinnerUsers")
		end
	end
	self.m_pFriendBattleConfig.iIsRoomPaid = true
end

-- 一局结束
function GameTable:onGameRoundStop(result)
	if self:isTableStatusBattleDead() then return end
	
	for k, v in pairs(self.m_pGameUsers) do
		v:onSetReady(0)
	end
	self:onServerAddOneRoundDetail()
	self:onServerUserSetBillDetail()
	if self:isFriendBattleGameOver(result) then
		-- 如果开了一局以上则要算大赢家
		self:onDealGameStopWinnerPay()
		self:setTableStatus(tableStatusMap.TABLE_STATUS_BATTLE_STOP)
		self:onServerSendBackRoomCard()
		self:onServerUpdateOneBattleBillInfo()
		self:onStartDimissFriendBattleTimer(2 * 60 * 1000)
		-- 上报牌局
		local pReportServer = skynet.call(self.m_pGameServiceMgr, "lua", "onGetReportServer")
		if pReportServer then
			local pGameInfoTable = {}
			pGameInfoTable.iBattleCurRound = self.m_pFriendBattleConfig.iBattleCurRound
			pGameInfoTable.iBattleTotalRound = self.m_pFriendBattleConfig.iBattleTotalRound
			pGameInfoTable.iLocalGameType = self:onGetLocalGameType()
			pGameInfoTable.iUserIdTable = {}
			for _, kUser in pairs(self.m_pGameUsers) do
				table.insert(pGameInfoTable.iUserIdTable, kUser:onGetUserId())
			end
			skynet.send(pReportServer, "lua", "onDealGameRound", pGameInfoTable)
		end
		-- 如果玩家离线则清掉
		for k, v in pairs(self.m_pGameUsers) do
			if 1 ~= v:onGetIsOnline() then
				self:onDealUserLogoutTableSuccess(v:onGetUserId())
			end
		end
	else
		if 1 == self.m_pFriendBattleConfig.iBattleCurRound then
			-- 扣房卡
			local pNeedRoomCard = self:onGetNeedRoomCardCount()
			if self:isOwnerPay() then
				self:onUserPayRoomCard(self.m_pFriendBattleConfig.iRoomOwnerId, pNeedRoomCard)
				self.m_pFriendBattleConfig.iIsRoomPaid = true
			elseif self:isSharePay() then
				for _, kUser in pairs(self.m_pGameUsers) do
					self:onUserPayRoomCard(kUser:onGetUserId(), math.floor(pNeedRoomCard))
				end
				self.m_pFriendBattleConfig.iIsRoomPaid = true
			end
			-- 标记这里必须要交房费
			self.m_pFriendBattleConfig.iNeedPayRoomCard = true
		end
		self:setTableStatus(tableStatusMap.TABLE_STATUS_ROUND_STOP)
		self:onServerUpdateOneBattleBillInfo()
	end
end

--------------------------------------- redis -----------------------------------
function GameTable:onDealUserLoginTableRedis(pUser)
	if not pUser then
		return -1
	end
	local key = string.format("mtKey_%s_%s", self.m_pCommonConfig.iGameCode, pUser:onGetUserId())
	self:onExecuteRedisCmd(DefineType.REDIS_MTKEY, "HMSET", key, "TableId", self.m_pCommonConfig.iTableId)
	-- local key = "mt_"..pUser.m_userId
	-- local pPort = self.m_pCommonConfig.iListenPort
	-- local pMjCode = self.m_pCommonConfig.iMJCode
	-- local pRedisRet = skynet.call(self.m_gameServer, "lua", "onExecuteRedisCmd", "HMSet", "mtkeyRedis", key, "uid", pUser.m_userId, "tid", self.m_tableId, "svid", self.m_serverId, "from", pUser.m_from, "port", pPort, "gamecode", pMjCode)
	-- local pRedisRet = skynet.call(self.m_gameServer, "lua", "onExecuteRedisCmd", "Expire", "mtkeyRedis", key, 3600 * 3)
	-- local key = "svidOnline_"..self.m_serverId
	-- local pRedisRet = skynet.call(self.m_gameServer, "lua", "onExecuteRedisCmd", "SAdd", "mtkeyRedis", key, pUser.m_userId)
	-- local pRedisRet = skynet.call(self.m_gameServer, "lua", "onExecuteRedisCmd", "Expire", "mtkeyRedis", key, 3600 * 3)
end

function GameTable:onDealUserLogoutTableRedis(pUser)
	if not pUser then
		return -1
	end
	local key = string.format("mtKey_%s_%s", self.m_pCommonConfig.iGameCode, pUser:onGetUserId())
	self:onExecuteRedisCmd(DefineType.REDIS_MTKEY, "HMSET", key, "TableId", 0)
	-- local key = "mt_"..pUser.m_userId
	-- local pRedisRet = skynet.call(self.m_gameServer, "lua", "onExecuteRedisCmd", "HMSet", "mtkeyRedis", key, "uid", 0, "tid", 0, "svid", 0, "gamecode", 0)
	-- local pRedisRet = skynet.call(self.m_gameServer, "lua", "onExecuteRedisCmd", "Expire", "mtkeyRedis", key, 3600 * 3)
	-- local key = "svidOnline_"..self.m_serverId
	-- local pRedisRet = skynet.call(self.m_gameServer, "lua", "onExecuteRedisCmd", "SREM", "mtkeyRedis", key, pUser.m_userId)
	-- local pRedisRet = skynet.call(self.m_gameServer, "lua", "onExecuteRedisCmd", "Expire", "mtkeyRedis", key, 3600 * 3)
end

--------------------------------------- 网络包组装函数 -----------------------------
-- 如果userId有值，则不包括该userId
function GameTable:onBroadcastTableUsers(name, info, userId)
	userId = userId or -1
	for _, kUser in pairs(self.m_pGameUsers) do
		if kUser:onGetUserId() ~= userId then
			self:onSendPackage(kUser:onGetUserId(), name, info)
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

function GameTable:onDisConnect(pUserId)
	self.m_pCsQueue(function()
		Log.d(TAG, "onDisConnect pUserId[%s]", pUserId)
		if not pUserId then return end
		local pUser = self:onGetUserByUserId(pUserId)
		if not pUser then return end
		pUser:onSetIsOnline(0)
		-- 如果是对战场，则不清除玩家
		if (self:isTableStatusPlaying() or self:isTableStatusNone() or self:isTableStatusRoundStop()) then
			if self.m_pFriendBattleConfig.iDisConnetTimeTable and 
				not self.m_pFriendBattleConfig.iDisConnetTimeTable.iTotalDisConnetTime then
				local pTime = 15 * 60
				self.m_pFriendBattleConfig.iDisConnetTimeTable.iTotalDisConnetTime = pTime
				self.m_pFriendBattleConfig.iDisConnetTimeTable.iStartDisConnectTime = os.time()
				self:onStartGameRoundDisconnetTimer(pTime * 1000)
			end
		end
		if self:isTableStatusBattleStop() or self:isTableStatusBattleDead() then
			self:onDealUserLogoutTableSuccess(pUserId)
		else
			self:onServerBCUserIsOnline(pUserId)
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
	local pTimeTable = self.m_pFriendBattleConfig.iDisConnetTimeTable
	if pTimeTable.iTotalDisConnetTime then
		local pCostTime = os.time() - pTimeTable.iStartDisConnectTime
		pRemainTime = pTimeTable.iTotalDisConnetTime - pCostTime
	end
	info.iTime = pRemainTime
	Log.dump(TAG, pTimeTable, "pTimeTable")
	self:onBroadcastTableUsers(name, info)
end

function GameTable:onDealOldUserReconnect(pUserId)
	local pUser = self:onGetUserByUserId(pUserId)
	if not pUser then return end 
	-- 设置玩家在线
	pUser:onSetIsOnline(1)

	local name = "ServerUserReconnect"
	local info = {}
	info.iGameCode = self.m_pCommonConfig.iGameCode
	info.iRoomType = self.m_pCommonConfig.iRoomType
	info.iRoomOwnerId = self.m_pFriendBattleConfig.iRoomOwnerId
	info.iBattleTotalRound = self.m_pFriendBattleConfig.iBattleTotalRound
	info.iBattleCurRound = self.m_pFriendBattleConfig.iBattleCurRound
	info.iGameLevel = self.m_pCommonConfig.iGameLevel
	info.iTableId = self.m_pCommonConfig.iTableId
	info.iTableName = self.m_pCommonConfig.iTableName
	info.iBasePoint = self.m_pCommonConfig.iBasePoint
	info.iServerFee = self.m_pCommonConfig.iServerFee
	info.iPlaytype = self.m_pCommonConfig.iPlaytype
	info.iPlaytypeStr = self.m_pFriendBattleConfig.iPlaytypeStr
	info.iMaxCardCount = self:onGetMaxCardCount()
	info.iMaxUserCount = self:onGetMaxUserCount()
	info.iOutCardTime = self.m_pCommonConfig.iOutCardTime - 1
	info.iOperationTime = self.m_pCommonConfig.iOperationTime - 1
	info.iRemainCardCount = self.m_pGameRound.m_pMahjongPool:remainCard()
	info.iIsInGame = self:isTableStatusPlaying() and 1 or 0
	info.iBankerSeatId = self:isTableStatusPlaying() and self.m_pGameRound.m_pBankerSeatId or 0
	info.iIsCanOutCard = self.m_pGameRound:isCanOutCard() and 1 or 0
	info.iDrawCardUserId = self.m_pGameRound:onGetDrawCardUserId()
	info.iOutCardUserId = self.m_pGameRound:onGetOutCardUserId()
	info.iUserTable = {}
	for k, v in pairs(self.m_pGameUsers) do
		local pTemp = {}
		pTemp.iUserId = v:onGetUserId()
		pTemp.iSeatId = v:onGetSeatId()
		pTemp.iMoney = v:onGetMoney()
		pTemp.iReady = v:onGetReady()
		pTemp.iIsOnline = v:onGetIsOnline()
		pTemp.iUserInfoStr = v.m_pUserInfoStr
		pTemp.iHandCards = v:onGetHandCardMap()
		pTemp.iBlockCards = v:onGetBlockCardMap()
		pTemp.iOutCards = v:onGetOutCardMap()
		pTemp.iOpTable = {}
		pTemp.iAllCardTingInfoTable = {}
		pTemp.iExtendInfo = json.encode(self.m_pGameRound:onGetUserExtendInfo(v, pUser))
		if pUserId ~= v:onGetUserId() then
			pTemp.iHandCards = {}
			for _, card in pairs(v:onGetHandCardMap()) do
				pTemp.iHandCards[#pTemp.iHandCards + 1] = 0
			end
		else
			pTemp.iOpTable = self.m_pGameRound:onGetUserOpTable(v:onGetUserId())
			pTemp.iAllCardTingInfoTable = self.m_pGameRound:onGetUserAllCardTingInfoTable(v:onGetUserId())
		end
		info.iUserTable[#info.iUserTable + 1] = pTemp
	end
	info.iLocalGameType = self:onGetLocalGameType()
	info.iRoomOwnerName = self.m_pFriendBattleConfig.iRoomUserInfo.name
	self:onSendPackage(pUser:onGetUserId(), name, info)
	self.m_pGameRound:onUserReconnect(pUser)
	
	self:onServerBCUserDismissBattleRoom()
	local pIsAllOnline = true
	for k, v in pairs(self.m_pGameUsers) do
		if 1 ~= v:onGetIsOnline() then
			pIsAllOnline = false
		end
	end
	if pIsAllOnline then
		self.m_pFriendBattleConfig.iDisConnetTimeTable = {}
		self.m_pScheduleMgr:unregister(self.m_pGameRoundDisconnetTimer)
	end
	self:onServerBCUserIsOnline(pUser:onGetUserId())
end

function GameTable:onDealNewUserReconnect(pUserId)
	local pUser = self:onGetUserByUserId(pUserId)
	if not pUser then return end 
	if self:isTableStatusBattleStop() then 
		self:onDealUserLogoutTableSuccess(pUserId)
		return 
	end
	-- 设置玩家在线
	pUser:onSetIsOnline(1)

	local name = "ServerNewUserReconnect"
	local info = {}
	info.iGameCode = self.m_pCommonConfig.iGameCode
	info.iRoomType = self.m_pCommonConfig.iRoomType
	info.iRoomOwnerId = self.m_pFriendBattleConfig.iRoomOwnerId
	info.iBattleTotalRound = self.m_pFriendBattleConfig.iBattleTotalRound
	info.iBattleCurRound = self.m_pFriendBattleConfig.iBattleCurRound
	info.iGameLevel = self.m_pCommonConfig.iGameLevel
	info.iTableId = self.m_pCommonConfig.iTableId
	info.iTableName = self.m_pCommonConfig.iTableName
	info.iBasePoint = self.m_pCommonConfig.iBasePoint
	info.iServerFee = self.m_pCommonConfig.iServerFee
	info.iPlaytype = self.m_pCommonConfig.iPlaytype
	info.iPlaytypeStr = self.m_pFriendBattleConfig.iPlaytypeStr
	info.iMaxCardCount = self:onGetMaxCardCount()
	info.iMaxUserCount = self:onGetMaxUserCount()
	info.iOutCardTime = self.m_pCommonConfig.iOutCardTime - 1
	info.iOperationTime = self.m_pCommonConfig.iOperationTime - 1
	info.iIsInGame = self:isTableStatusPlaying() and 1 or 0
	info.iLocalGameType = self:onGetLocalGameType()
	info.iRoomOwnerName = self.m_pFriendBattleConfig.iRoomUserInfo.name
	info.iGameRoundInfo = json.encode(self.m_pGameRound:onGetGameRoundInfo())
	info.iUserTable = {}
	for k, v in pairs(self.m_pGameUsers) do
		local pTemp = {}
		pTemp.iUserId = v:onGetUserId()
		pTemp.iSeatId = v:onGetSeatId()
		pTemp.iMoney = v:onGetMoney()
		pTemp.iReady = v:onGetReady()
		pTemp.iIsOnline = v:onGetIsOnline()
		pTemp.iUserInfoStr = v.m_pUserInfoStr
		pTemp.iUserGameInfo = json.encode(self.m_pGameRound:onGetUserGameInfo(v, pUser))
		pTemp.iExtendInfo = json.encode(self.m_pGameRound:onGetUserExtendInfo(v, pUser))
		info.iUserTable[#info.iUserTable + 1] = pTemp
	end
	self:onSendPackage(pUser:onGetUserId(), name, info)
	self.m_pGameRound:onUserReconnect(pUser)

	self:onServerBCUserDismissBattleRoom()
	local pIsAllOnline = true
	for k, v in pairs(self.m_pGameUsers) do
		if 1 ~= v:onGetIsOnline() then
			pIsAllOnline = false
		end
	end
	if pIsAllOnline then
		self.m_pFriendBattleConfig.iDisConnetTimeTable = {}
		self.m_pScheduleMgr:unregister(self.m_pGameRoundDisconnetTimer)
	end
	self:onServerBCUserIsOnline(pUser:onGetUserId())
end

function GameTable:onUserReconnect(pUserId)
	self.m_pCsQueue(function()
		if self.m_pGameRound.isOldUserReconnenct and self.m_pGameRound:isOldUserReconnenct() then
			self:onDealOldUserReconnect(pUserId)
		else
			self:onDealNewUserReconnect(pUserId)
		end
		-- 如果是一个玩家开始的游戏
		if self:isOneUserStartGame() then
			if pUserId == self.m_pFriendBattleConfig.iStartGameUserId then
				self.m_pFriendBattleConfig.iStartGameUserId = 0
				self:onServerUserStartGameUserId(pUserId)
			end
		end
	end)
end

function GameTable:onGetGaoJiXuanXiang()
	return self.m_pFriendBattleConfig.iGaoJiXuanXiang
end

function GameTable:isTableStatusNone()
	return self.m_pTableStatus == tableStatusMap.TABLE_STATUS_NONE
end

function GameTable:isTableStatusPlaying()
	return self.m_pTableStatus == tableStatusMap.TABLE_STATUS_PLAYING
end

function GameTable:isTableStatusBattleStop()
	return self.m_pTableStatus == tableStatusMap.TABLE_STATUS_BATTLE_STOP
end

function GameTable:isTableStatusBattleDead()
	return self.m_pTableStatus == tableStatusMap.TABLE_STATUS_BATTLE_DEAD
end

function GameTable:isTableStatusRoundStop()
	return self.m_pTableStatus == tableStatusMap.TABLE_STATUS_ROUND_STOP
end

-------------------------------------------- socket ------------------------------------------
function GameTable:ClientUserReady(data, pUserId)
	local pUser = self:onGetUserByUserId(pUserId)
	if not pUser then return end
	if self:isTableStatusPlaying() or self:isTableStatusBattleStop() then
		return
	end
	local pIsOneUserStartGame = self:isOneUserStartGame()
	if pIsOneUserStartGame then
		if pUserId ~= self.m_pFriendBattleConfig.iStartGameUserId then
			return
		end
		if self.m_pGameRound.isOneUserCanStartGame and self.m_pGameRound:isOneUserCanStartGame() then
			-- 所有都设置成已准备，然后将最大人数设置成当前人数
			for _, kUser in pairs(self.m_pGameUsers) do
				kUser:onSetReady(1)
			end
			-- 如果是由某个玩家开始的游戏，房间人数必须设置一下
			self.m_pCommonConfig.pSetUpMaxUserCount = self:onGetReadyUserCount()
			
			self:onBroadcastUserReady(pUser)
			self:onCheckGameTableStartGame()
		end
	else
		if 1 == pUser:onGetReady() then return end
		pUser:onSetReady(data.iReady or 0)
		self:onBroadcastUserReady(pUser)
		self:onCheckGameTableStartGame()
	end
end

function GameTable:ClientUserLogoutGame(data, pUserId)
	Log.d(TAG, "ClientUserLogoutGame pUserId[%s] status[%s]", pUserId, self.m_pTableStatus)
	local pUser = self:onGetUserByUserId(pUserId)
	if not pUser then return end
	if self:isTableStatusPlaying() then return end
	if self:isTableStatusBattleDead() then
		return
	end
	if self:isTableStatusRoundStop() then
		return
	end
	Log.d(TAG, "pUserId[%s] self.m_pFriendBattleConfig.iRoomOwnerId[%s]", pUserId, self.m_pFriendBattleConfig.iRoomOwnerId)
	-- 如果是房主离开房间且牌局没结束，直接解散
	if self:isRoomOwner(pUserId) and not self:isTableStatusBattleStop() then
		self:onDismissFriendBattleRoom(1)
	else
		self:onDealUserLogoutTableSuccess(pUserId)
	end
end

function GameTable:ClientUserDismissBattleRoom(data, pUserId)
	local pUser = self:onGetUserByUserId(pUserId)
	if not pUser then return end
	if not self:isTableStatusPlaying() and not self:isTableStatusRoundStop() then return end
	-- 如果是代开房解散
	local pCreateForOther = data.iCreateForOther or 0
	if self:isRoomOwner(pUserId) and (1 == pUser:onGetIsAgent() or 2 == pUser:onGetIsAgent() or 3 == pUser:onGetIsAgent()) and 1 == pCreateForOther then
		-- 如果玩家已经在玩了，则提示
		if self:isTableStatusPlaying() or self:isTableStatusRoundStop() then
			local pMsg = "该房间正在游戏中，无法解散！"
			self:onServerUserShowHints(pUserId, 1, pMsg)
		elseif not self:isTableStatusBattleStop() then
			self:onDismissFriendBattleRoom()
		end
		return
	end
	if self.m_pFriendBattleConfig.iDismissBattleTable then 
		Log.d(TAG, "已经有人请求解散房间了")
		return
	end
	self.m_pFriendBattleConfig.iDismissBattleTable = {}
	local pTime = 2 * 60
	if self.m_pFriendBattleConfig.iDisConnetTimeTable.iTotalDisConnetTime then
		local pCostTime = os.time() - self.m_pFriendBattleConfig.iDisConnetTimeTable.iStartDisConnectTime
		local pRemainTime = self.m_pFriendBattleConfig.iDisConnetTimeTable.iTotalDisConnetTime - pCostTime
		pTime = math.min(pTime, pRemainTime >= 0 and pRemainTime or 0)
	end
	self.m_pFriendBattleConfig.iDismissBattleTable.iStartTime = os.time()
	self.m_pFriendBattleConfig.iDismissBattleTable.iUserId = pUserId
	self.m_pFriendBattleConfig.iDismissBattleTable.iTotolTime = pTime
	self.m_pFriendBattleConfig.iDismissBattleTable.iRemainTime = pTime
	self.m_pFriendBattleConfig.iDismissBattleTable.iDismissBattleUserTable = {}
	for k, v in pairs(self.m_pGameUsers) do
		local pTemp = {}
		pTemp.iUserId = v:onGetUserId()
		pTemp.iIsOnline = v:onGetIsOnline()
		pTemp.iDismissStatus = v:onGetUserId() == pUserId and 1 or 0
		table.insert(self.m_pFriendBattleConfig.iDismissBattleTable.iDismissBattleUserTable, pTemp)
	end
	self:onStartGameRoundHalfwayStop(pTime * 1000)
	self:onServerBCUserDismissBattleRoom()
	-- Log.dump(TAG, self.m_pFriendBattleConfig.iDismissBattleTable, "iDismissBattleTable")
end

function GameTable:ClientUserDismissBattleSelect(data, pUserId)
	if self:isTableStatusBattleStop() or self:isTableStatusBattleDead() then return end
	if not self.m_pFriendBattleConfig.iDismissBattleTable then
		return
	end
	local pUser = self:onGetUserByUserId(pUserId)
	if not pUser then return end
	-- 如果是同意
	if 1 == data.iSelect then
		local pUserAllAgree = true 
		local pDismissBattleTable = self.m_pFriendBattleConfig.iDismissBattleTable
		for k, v in pairs(pDismissBattleTable.iDismissBattleUserTable) do
			if v.iUserId == pUserId then
				v.iDismissStatus = 1
			end
			if 1 ~= v.iDismissStatus then
				pUserAllAgree = false
			end
		end
		-- 是不是所有玩家都同意了
		if pUserAllAgree then
			self.m_pGameRound:onGameRoundStop(2)
		else
			self:onServerBCUserDismissBattleRoom()
		end
	else
		local name = "ServerBCUserRefuseDismissBattle"
		local info = {}
		info.iUserId = pUserId
		info.iRefuseStr = string.format("玩家 %s 拒绝解散房间", pUser:onGetNickName())
		self:onBroadcastTableUsers(name, info)
		self.m_pFriendBattleConfig.iDismissBattleTable = nil
		self.m_pScheduleMgr:unregister(self.m_pHalfwayStopTimer)
	end
end

function GameTable:onStartGameRoundHalfwayStop(time)
	Log.d(TAG, "onStartGameRoundHalfwayStop time[%s]", time)
	self.m_pScheduleMgr:unregister(self.m_pHalfwayStopTimer)
	local pCallback = self.onTimerGameRoundStop
	self.m_pHalfwayStopTimer = self.m_pScheduleMgr:registerOnceNow(pCallback, time, self, 2)
end

function GameTable:onStartGameRoundDisconnetTimer(time)
	Log.d(TAG, "onStartGameRoundDisconnetTimer time[%s]", time)
	self.m_pScheduleMgr:unregister(self.m_pGameRoundDisconnetTimer)
	local pCallback = self.onTimerGameRoundStop
	self.m_pGameRoundDisconnetTimer = self.m_pScheduleMgr:registerOnceNow(pCallback, time, self, 2)
end

function GameTable:onTimerGameRoundStop(result)
	self.m_pCsQueue(function()
		-- 判断如果牌局没开始，则直接解散
		if self.m_pFriendBattleConfig.iBattleCurRound <= 0 then
			self:onDismissFriendBattleRoom()
		elseif not self:isTableStatusBattleStop() and not self:isTableStatusBattleDead() then
			self.m_pGameRound:onGameRoundStop(result)
		end
	end)
end

function GameTable:onServerBCUserDismissBattleRoom()
	if not self.m_pFriendBattleConfig.iDismissBattleTable then
		return
	end
	local pCostTime = os.time() - self.m_pFriendBattleConfig.iDismissBattleTable.iStartTime
	self.m_pFriendBattleConfig.iDismissBattleTable.iRemainTime = self.m_pFriendBattleConfig.iDismissBattleTable.iTotolTime - pCostTime
	-- 更新掉线信息
	for _, kInfo in pairs(self.m_pFriendBattleConfig.iDismissBattleTable.iDismissBattleUserTable) do
		local kUser = self:onGetUserByUserId(kInfo.iUserId)
		if kUser then
			kInfo.iIsOnline = kUser:onGetIsOnline()
		end
	end
	local name = "ServerBCUserDismissBattleRoom"
	local info = self.m_pFriendBattleConfig.iDismissBattleTable
	self:onBroadcastTableUsers(name, info)
end

return GameTable