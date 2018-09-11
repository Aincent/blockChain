local OperationType       = require("logic/game/mahjong/operationType") 
local json = require("cjson")
local skynet = require "skynet"
local GameRound = {}

-- 先这样写，下次找个好的方案修改
local pGameCode = tonumber(skynet.getenv("level"))
local pHasTimeDelay = (pGameCode == 200)

local TAG = "GameRound"

local roundStatusMap = {
	ROUND_STATUS_NONE = 0,
	ROUND_STATUS_DRAW_CARD = 1,
	ROUND_STATUS_OUT_CARD = 2,
	ROUND_STATUS_OP_OUT_CARD = 3,
	ROUND_STATUS_OP_DRAW_CARD = 4,
	ROUND_STATUS_OP_BUGANG_CARD = 5,
	ROUND_STATUS_OP_PENG_CARD = 6,
	ROUND_STATUS_OP_CHI_CARD = 7,
	ROUND_STATUS_OP_SELECT_GANG_CARD = 8, -- 特殊给扳倒胡
	ROUND_STATUS_OP_LAST_CARD = 9, -- 特殊给饶平
	ROUND_STATUS_OP_SELECT_DINGQUE = 10,
	ROUND_STATUS_OP_HUAN_SAN_ZHANG = 11,
	ROUND_STATUS_OP_BAO_TING = 12,  -- 选择报听状态
	ROUND_STATUS_OP_AUTO_OUT_CARD = 13,  -- 自动出牌状态
	ROUND_STATUS_OP_LANG_QI = 14,  -- 选择廊起状态
	ROUND_STATUS_OP_OUT_CARD_MYSELF = 15,  -- 自己胡自己打出去的牌的状态
	ROUND_STATUS_OP_SELECT_MAIDIAN = 16,  -- 选择买点的状态
	ROUND_STATUS_OP_LAO_LAST_CARD = 17, -- 特殊给闲时卡二条，最后海底捞的操作
	ROUND_STATUS_OP_BU_HUA = 18, --南京麻将补花
}

function GameRound:init(pGameTable, pScheduleMgr)
	Log.d(TAG, "[init]")
	self.m_pGameTable = pGameTable
	self.m_pGameUsers = self.m_pGameTable.m_pGameUsers
	self.m_pScheduleMgr = pScheduleMgr
	
	self.m_pGameRule = self:onGetGameRuleByGameCode(self.m_pGameTable.m_pCommonConfig.iGameCode)
	if self.m_pGameRule.init then
		self.m_pGameRule:init(self)
	end
	assert(self.m_pGameRule)

	self.m_pMahjongPool = require("logic/game/mahjong/mahjongPool")
	self.m_pRoundStatus = roundStatusMap.ROUND_STATUS_NONE

	self.m_pUserCurOpTable = {}
	self.m_pIsCanOutCard = false

	self.m_pPreRoundInfo = {}
	self.m_pOneRoundLookbackTable = {}

	self.m_pRoundIsHu = false
	self.m_pTotalHuCount = 0

	self:clear()
	self:onClearGameRoundBankerInfo()
end 

function GameRound:onGetGameTable()
	return self.m_pGameTable
end

function GameRound:onGetGameRule()
	return self.m_pGameRule
end

function GameRound:clear()
	self.m_pAllTurnMoneyTable = {
		iHuTurnMoneyTable = {},
		iGangTurnMoneyTable = {},
	}

	self:onClearUserCurOpTable()
	self.m_pIsCanOutCard = false
	self.m_pRoundIsHu = false
	self.m_pTotalHuCount = 0

	self.m_pPengHouBuKeGangTable = {}

	self.m_pUserMaiDianTable = {}

	self.m_pUserBuHuaTable = {}

	self.m_pOneRoundLookbackTable = {}
	for k, v in pairs(self.m_pGameUsers) do
		v:onClearOneRound()
		self.m_pUserMaiDianTable[v:onGetUserId()] = -1
		self.m_pUserBuHuaTable[v:onGetUserId()] = {}
	end
end 

function GameRound:onGameRoundStart()
	Log.d(TAG, "onGameRoundStart")
	self.m_pGameUsers = self.m_pGameTable.m_pGameUsers
	self:clear()
	self:onGetGameRule():onGameRoundStart(self)
	local pUserCount = self:onGetGameTable():onGetGameTableMaxUserCount()
	self.m_pMahjongPool:initMahjongPool(self.m_pGameRule:onGetMahjongPool(pUserCount), pUserCount, self)
	-- 设置流程的状态
	self.m_pBankerSeatId = 0
	self.m_pCurOutCardSeatId = 0
	self.m_pTotalOutCard = 0
	self.m_pUserCurOpTable = {}
	self:setRoundStatus(roundStatusMap.ROUND_STATUS_NONE)
	-- 设置游戏中的信息
	if self.m_pGameTable:isFirendBattleRoom() then
		if 1 == self.m_pGameTable.m_pFriendBattleConfig.iBattleCurRound then
			self.m_pGameRule:onGameFristRoundStart(self.m_pGameUsers)
		end
	end
	-- 写入回看数据
	local name, info = self.m_pGameTable:onSendUserLoginSuccess(self.m_pGameUsers[1], true)
	table.insert(self.m_pOneRoundLookbackTable, {
		iName = name,
		iInfo = info,
	})
	-- 首先广播游戏开始
	self:onBroadcastGameStart()
	self.m_pProcessTable = self.m_pGameRule:onGetProcessTable()
	-- 处理流水线
	self:onDealProcessWork()
end

function GameRound:onGetMaxCardCount()
	return #self.m_pGameRule:onGetMahjongPool(self.m_pGameTable:onGetGameTableMaxUserCount())
end

--[[
	流水线工作
]]
function GameRound:onDealProcessWork()
	Log.d(TAG, "onDealProcessWork, [%s]", #self.m_pProcessTable)
	if #self.m_pProcessTable > 0 then
		local pProcess = table.remove(self.m_pProcessTable, 1)
		-- Log.dump(TAG, self.RoundProcessMap[pProcess])
		local pIsOk, pErr = pcall(self.RoundProcessMap[pProcess].iFunc, self)
		if not pIsOk then
			Log.d(TAG, pErr)
		end
		-- 启动定时器
		if not self.RoundProcessMap[pProcess].iNeedConfrim then
			local time = self.RoundProcessMap[pProcess].iTime
			local callback = self.onDealProcessWork
			self:startTimer("timerProcess", time, callback)
		end
	else
		-- 这个要加入到时序中
		self:onGetGameTable():onDealCsFunc(self.onDealProcessWorkDone, self)
		-- self:onDealProcessWorkDone()
	end
end

function GameRound:onDealProcessWorkDone()
	-- 给庄家发是否能操作的包
	local pUser = self.m_pGameUsers[self.m_pBankerSeatId]
	if not pUser then return end
	local pHandCardMap = pUser:onGetHandCardMap()
	local opTable = self:onGetGameRule():onGetOpTableWhenDrawCard(pUser, pHandCardMap[#pHandCardMap], self.m_pGameUsers)
	local pAllCardTingInfoTable = self:onGetGameRule():onGetTingCardTable(pUser)
	local name = "ServerBCUserBankerCanOp"
	local info = {}
	info.iUserId = pUser:onGetUserId()
	info.iRemainCardCount = self.m_pMahjongPool:remainCard()
	for k, v in pairs(self.m_pGameUsers) do
		if v:onGetUserId() == info.iUserId then
			info.iOpTable = opTable
			for _, p in pairs(info.iOpTable) do
				local op = {
					iOpValue = p.iOpValue,
					iCardValue = p.iCardValue,
					iSeatId = v:onGetSeatId(),
					iTSeatId = pUser:onGetSeatId(),
					iStatus = 0
				}
				table.insert(self.m_pUserCurOpTable, op)
			end
			info.iAllCardTingInfoTable = pAllCardTingInfoTable
		else
			info.iOpTable = {}
			info.iAllCardTingInfoTable = {}
		end
		self.m_pGameTable:onSendPackage(v:onGetUserId(), name, info)
	end
	-- 把所有的操作写入回放
	self:onWriteLookbackAllUserOpTable()
	-- 如果没有操作，启动定时器，开始打牌
	self.m_pCurOutCardSeatId = self.m_pBankerSeatId
	if #opTable <= 0 then
		self:setRoundStatus(roundStatusMap.ROUND_STATUS_OUT_CARD)
	else
		self:onSortUserCurOpTable()
		self:setRoundStatus(roundStatusMap.ROUND_STATUS_OP_DRAW_CARD)
	end

	self.m_pIsCanOutCard = true
end

function GameRound:isCanOutCard()
	return self.m_pIsCanOutCard and not self:isRoundStatusOpLastCard() and not self:isRoundStatusOpLaoLastCard()
end

--[[
	打牌超时,随便打一张
]]
function GameRound:onTimerOutCardCallbak()
	Log.d(TAG, "onTimerOutCardCallbak")
	local pUser = self.m_pGameUsers[self.m_pCurOutCardSeatId]
	if not pUser then return end
	local pHandCardMap = pUser:onGetHandCardMap()
	self:ClientUserOutCard({iCardValue = pHandCardMap[#pHandCardMap]}, pUser:onGetUserId())
end

--[[
	操作抓牌超时
]]
function GameRound:onTimerOpDrawCardCallbak()
	local name = "timerOutCard"
	local time = 2000
	local callback = self.onTimerOutCardCallbak
	-- self:startTimer(name, time, callback)
end

function GameRound:onWriteLookbackAllUserOpTable()
	local name = "ServerBCLookbackAllUserOpTable"
	local info = {}
	info.iLokkbackOpTable = {}
	for _, kUser in pairs(self.m_pGameUsers) do
		local kUserOpTable = {}
		kUserOpTable.iUserId = kUser:onGetUserId()
		kUserOpTable.iOpTable = {}
		table.insert(info.iLokkbackOpTable, kUserOpTable)
	end
	if #self.m_pUserCurOpTable > 0 then
		for _, kOp in pairs(self.m_pUserCurOpTable) do
			for _, kUserOpTable in pairs(info.iLokkbackOpTable) do
				local kUser = self:onGetUserByUserId(kUserOpTable.iUserId)
				if kOp.iSeatId == kUser:onGetSeatId() then
					local kOpInfo = {}
					kOpInfo.iOpValue = kOp.iOpValue
					kOpInfo.iCardValue = kOp.iCardValue
					table.insert(kUserOpTable.iOpTable, kOpInfo)
				end
			end
		end
		-- 写入回看数据
		table.insert(self.m_pOneRoundLookbackTable, {
			iName = name,
			iInfo = info,
		})
	end
end

function GameRound:onWriteLookbackUserTakeOp(pOp)
	local name = "ServerBCLookbackUserTakeOp"
	local info = {}
	local pUser = self.m_pGameUsers[pOp.iSeatId]
	local tUser = self.m_pGameUsers[pOp.iTSeatId]
	local pTakeOpInfo = {
		iUserId = pUser:onGetUserId(),
		iOpValue = pOp.iOpValue,
		iTUserId = tUser:onGetUserId(),
		iCardValue = pOp.iCardValue
	}
	info.iTakeOpInfo = pTakeOpInfo
	-- 写入回看数据
	table.insert(self.m_pOneRoundLookbackTable, {
		iName = name,
		iInfo = info,
	})
end


function GameRound:onGetUserInitMoney()
	local pInitMoney = 0
	if self:onGetGameRule().onGetUserInitMoney then
		pInitMoney = self:onGetGameRule():onGetUserInitMoney()
	end

	return pInitMoney
end

function GameRound:onGetGameRoundInfo()
	local pGameRoundInfoTable = {}
	if self:onGetGameRule().onGetGameRoundInfo then
		pGameRoundInfoTable = self:onGetGameRule():onGetGameRoundInfo()
	end
	pGameRoundInfoTable.iRemainCardCount = self.m_pMahjongPool:remainCard() or 0
	pGameRoundInfoTable.iBankerSeatId = self.m_pBankerSeatId or 0
	pGameRoundInfoTable.iIsCanOutCard = self:isCanOutCard() and 1 or 0
	pGameRoundInfoTable.iDrawCardUserId = self:onGetDrawCardUserId()
	pGameRoundInfoTable.iOutCardUserId = self:onGetOutCardUserId()
	pGameRoundInfoTable.iClubId = self:onGetGameTable().m_pFriendBattleConfig.iClubId
	if self:onGetGameRule().isGameSettingEmoji and not self.m_pGameTable:isGoldFieldRoom() then
		pGameRoundInfoTable.iEmoji = self:onGetGameRule():isGameSettingEmoji() and 1 or 0
	end
	return pGameRoundInfoTable
end

--[[
	这个包只是为了告诉客户端游戏开始，现在不能退出房间
]]
function GameRound:onBroadcastGameStart()
	Log.d(TAG, "onBroadcastGameStart")
	local name = "ServerBCGameStart"
	local info = {}
	info.iBattleCurRound = 0
	if self.m_pGameTable:isFirendBattleRoom() then
		info.iBattleCurRound = self.m_pGameTable.m_pFriendBattleConfig.iBattleCurRound
	end
	info.iGameRoundInfo = json.encode(self:onGetGameRoundInfo())
	self.m_pGameTable:onBroadcastTableUsers(name, info)
	-- 写入回看数据
	table.insert(self.m_pOneRoundLookbackTable, {
		iName = name,
		iInfo = info,
	})
end

--[[
	发牌,给所有玩家都发牌，庄家隔2秒多发一张
]]
function GameRound:onProcessDealCards()
	local userCount = self.m_pGameTable:onGetGameTableMaxUserCount()
	local cardCount = self.m_pGameTable:onGetDealCardCount()

	local pDealCardMap = self.m_pMahjongPool:dealCards(userCount, cardCount)
	local name = "ServerBCUserDealCards"
	local info = {}
	info.iBankerSeatId   = self.m_pBankerSeatId 
	info.iDiceTable = {}
	math.randomseed(tostring(os.time()):reverse():sub(1, 6))
	if pHasTimeDelay then
		for i = 1, 2 do
			info.iDiceTable[i] = math.random(6)
		end
	end
	info.iHandCardMap = {}
	for i = 1, userCount do
		local pUser = self.m_pGameUsers[i]
		local pHandCardMap = pUser:onGetHandCardMap()
		for j = 1, userCount do
			info.iHandCardMap[j] = {}
			info.iHandCardMap[j].iSeatId = j
			info.iHandCardMap[j].iHandCards = {}
			for k = 1, cardCount do
				if i == j then
					info.iHandCardMap[j].iHandCards[k] = pDealCardMap[i][k]
					pHandCardMap[k] = pDealCardMap[i][k]
				else
					info.iHandCardMap[j].iHandCards[k] = 0
				end
			end
		end
		self.m_pGameTable:onSendPackage(pUser:onGetUserId(), name, info)
	end
	-- 写入回看数据
	-- 将牌设置成全部都有的
	info.iHandCardMap = {}
	for i = 1, userCount do
		local pUser = self.m_pGameUsers[i]
		info.iHandCardMap[i] = {}
		info.iHandCardMap[i].iSeatId = i
		info.iHandCardMap[i].iHandCards = {}
		for j = 1, cardCount do
			info.iHandCardMap[i].iHandCards[j] = pDealCardMap[i][j]
		end
	end
	table.insert(self.m_pOneRoundLookbackTable, {
		iName = name,
		iInfo = info,
	})

	-- 启动定时器，隔3秒给庄家多发一张牌
	local timerName = "timerBankerCard"
	local time = pHasTimeDelay and 3000 or 0
	local callback = self.onUserDrawCard
	local userId = self.m_pGameUsers[self.m_pBankerSeatId]:onGetUserId()
	self:startTimer(timerName, time, callback, userId, true)
end

function GameRound:onClearGameRoundBankerInfo()
	self.m_pPreRoundBankerInfo = {
		iBankerSeatId = 0,
		iLianZhuangCount = 0,
	}
end

--[[
	定庄，庄家是有GameRule确定的
]]
function GameRound:onProcessMakeBanker()
	local name = "ServerBCMahjongMakeBanker"
	local info = {}
	info.iBankerSeatId, info.iDiceTable = self.m_pGameRule:onGetBankerSeatId(self.m_pGameTable:onGetGameTableMaxUserCount())
	self.m_pBankerSeatId = info.iBankerSeatId
	self.m_pGameTable:onBroadcastTableUsers(name, info)
	-- 处理连庄
	if self.m_pPreRoundBankerInfo.iBankerSeatId == info.iBankerSeatId then
		self.m_pPreRoundBankerInfo.iLianZhuangCount = self.m_pPreRoundBankerInfo.iLianZhuangCount + 1
	else
		self:onClearGameRoundBankerInfo()
		if self:onGetGameTable().m_pFriendBattleConfig.iBattleCurRound > 1 then
			self.m_pPreRoundBankerInfo.iBankerSeatId = info.iBankerSeatId
		end
	end
	-- 写入回看数据
	table.insert(self.m_pOneRoundLookbackTable, {
		iName = name,
		iInfo = info,
	})
end

function GameRound:onProcessMakeGangCard(pIsUpdate)
	local name = "ServerBCMahjongMakeGangCard"
	local info = {}
	info.iGangCardTable = {}
	if self.m_pGameRule.onGetMakeGangCardTable then 
		if pIsUpdate then
			info.iGangCardTable = self.m_pGameRule:onGetMakeGangCardTable()
		else
			info.iGangCardTable = self.m_pGameRule:onGetMakeGangCardTable(self.m_pMahjongPool)
		end
	end
	info.iRemainCardCount = self.m_pMahjongPool:remainCard()
	self.m_pGameTable:onBroadcastTableUsers(name, info)
	-- 写入回看数据
	table.insert(self.m_pOneRoundLookbackTable, {
		iName = name,
		iInfo = info,
	})
end

function GameRound:onProcessMakeGuiCard(pIsUpdate)
	local name = "ServerBCMahjongMakeGuiCard"
	local info = {}
	info.iShowCardTable = {}
	info.iGuiCardTable = {}
	if self.m_pGameRule.onGetMakeGuiCardTable then 
		if pIsUpdate then
			info.iShowCardTable, info.iGuiCardTable = self.m_pGameRule:onGetMakeGuiCardTable()
		else
			info.iShowCardTable, info.iGuiCardTable = self.m_pGameRule:onGetMakeGuiCardTable(self.m_pMahjongPool)
		end
	end
	self.m_pGameTable:onBroadcastTableUsers(name, info)
	
	-- 写入回看数据
	table.insert(self.m_pOneRoundLookbackTable, {
		iName = name,
		iInfo = info,
	})
end

function GameRound:onProcessHuanSanZhang(pUserId)
	local name = "ServerBCMahjongStartHuanSanZhang"
	local info = {}
	if self:onGetGameRule().onGetIsCanRenYiHuan then
		info.iIsCanRenYiHuan = self:onGetGameRule():onGetIsCanRenYiHuan()
	end
	if pUserId and pUserId > 0 then
		self:onGetGameTable():onSendPackage(pUserId, name, info)
	else
		self.m_pGameTable:onBroadcastTableUsers(name, info)
	end
	self:setRoundStatus(roundStatusMap.ROUND_STATUS_OP_HUAN_SAN_ZHANG)
end

function GameRound:onProcessDingQue(pUserId)
	local name = "ServerBCMahjongStartDingQue"
	local info = {}
	if pUserId and pUserId > 0 then
		local pUser = self:onGetUserByUserId(pUserId)
		if not pUser then return end
		if pUser:onGetDingQue() <= 0 then
			info.iDingQueTable = self:onGetGameRule():onGetDingQueTable(pUser)
		else
			-- 如果已经本人已经定缺了，则发空包，提示现在还在定缺阶段
			info.iDingQueTable = {}
		end
		self:onGetGameTable():onSendPackage(pUser:onGetUserId(), name, info)
	else
		for k, v in pairs(self.m_pGameUsers) do
			info.iDingQueTable = self:onGetGameRule():onGetDingQueTable(v)
			self:onGetGameTable():onSendPackage(v:onGetUserId(), name, info)
		end
	end
	self:setRoundStatus(roundStatusMap.ROUND_STATUS_OP_SELECT_DINGQUE)
end

function GameRound:onProcessBaoTing(pUserId)
	local name = "ServerBCUserCanBaoTing"
	local info = {}
	info.iBaoTingTable = {}
	if pUserId and pUserId > 0 then
		local pUser = self:onGetUserByUserId(pUserId)
		if not pUser then return end
		for _, kUser in pairs(self.m_pGameUsers) do
			-- 如果还是可报还没有报听的状态
			if 0 == kUser:onGetIsBaoTing() then
				table.insert(info.iBaoTingTable, kUser:onGetUserId())
			end
		end
		if #info.iBaoTingTable > 0 then
			self:onGetGameTable():onSendPackage(pUserId, name, info)
			self:setRoundStatus(roundStatusMap.ROUND_STATUS_OP_BAO_TING)
		end
	else
		for _, kUser in pairs(self.m_pGameUsers) do
			kUser:onSetIsBaoTing(-1)
			-- 判断是否能听牌
			if self:onGetGameRule():isCanBaoTing(kUser) then
				kUser:onSetIsBaoTing(0)
				table.insert(info.iBaoTingTable, kUser:onGetUserId())
			end
		end
		if #info.iBaoTingTable > 0 then
			self:onGetGameTable():onBroadcastTableUsers(name, info)
			self:setRoundStatus(roundStatusMap.ROUND_STATUS_OP_BAO_TING)
		else
			self:onDealProcessWork()
		end
	end
end

function GameRound:onProcessMaiDian(pUserId)
	local name = "ServerBCMahjongStartMaiDian"
	local info = {}
	if pUserId and pUserId > 0 then
		if self.m_pUserMaiDianTable[pUserId] < 0 then
			info.iUserId = pUserId
	        info.iMaiDianTable = self.m_pCanMaiDianTable
	        self:onGetGameTable():onSendPackage(pUserId, name, info)
		end
	else
		self.m_pCanMaiDianTable = {0 , 1, 2}
		for _, kUser in pairs(self.m_pGameUsers) do
			info.iUserId = kUser:onGetUserId()
	        info.iMaiDianTable = self.m_pCanMaiDianTable
	        self:onGetGameTable():onSendPackage(info.iUserId, name, info)
	    end
	    self:setRoundStatus(roundStatusMap.ROUND_STATUS_OP_SELECT_MAIDIAN)
	end
end

function GameRound:onProcessBuHua()
	for _, kUser in pairs(self.m_pGameUsers) do
		local pUserId = kUser:onGetUserId()
		local pHandCardMap = kUser:onGetHandCardMap()
		local pHuaPei = {}
		for k,v in pairs(pHandCardMap) do 
			if math.floor(v / 10) > 4 then
				table.insert(pHuaPei, v) -- 先到所有花牌
			end
		end

		for k,v in pairs(pHuaPei) do
			table.insert(self.m_pUserBuHuaTable[pUserId], v)
			self:onMoveOneHandCard(pUserId, v)
			self:onGetGameRule():isCanHuaGang(kUser)

			local cardValue = self.m_pMahjongPool:drawCard(kUser:onGetSeatId())
			while (math.floor(cardValue / 10) > 4) do
				table.insert(self.m_pUserBuHuaTable[pUserId], cardValue)
				self:onAddOneDrawCard(pUserId, cardValue)
				self:onGetGameRule():isCanHuaGang(kUser)
				cardValue = self.m_pMahjongPool:drawCard(kUser:onGetSeatId())
			end

			self:onAddOneHandCard(pUserId, cardValue)
			self:onAddOneDrawCard(pUserId, cardValue)	
		end
	end

	self:setRoundStatus(roundStatusMap.ROUND_STATUS_OP_BU_HUA)

	-- 启动定时器，隔1秒推送一次补花信息
	local timerName = "timerBuHua"
	local time = 100 --第一个补花的不用隔1秒
	local callback = self.onTimeOutBuHua
	self:startTimer(timerName, time, callback, self.m_pBankerSeatId, true)
end

function GameRound:onTimeOutBuHua(pSeatId, pFlag)
	local name = "ServerBCMahjongBuHua"
	local time = 1000
	local userCount = self.m_pGameTable:onGetGameTableMaxUserCount()
	local nextSeatId = pSeatId % userCount + 1
	if pFlag or pSeatId ~= self.m_pBankerSeatId then
		local userId = self.m_pGameUsers[pSeatId]:onGetUserId() 
		if #self.m_pUserBuHuaTable[userId] > 0 then
			for _, kUser in pairs(self.m_pGameUsers) do
				local info = {}
				info.iUserId  = userId
				if kUser:onGetSeatId() == pSeatId then
					info.iHandCards = {}
					for k,v in pairs(kUser:onGetHandCardMap()) do
						table.insert(info.iHandCards, v)
					end
				else
					info.iHandCards = {}
					for k,v in pairs(self.m_pGameUsers[pSeatId]:onGetHandCardMap()) do
						table.insert(info.iHandCards, 0)
					end
				end

				info.iHuaPai = {}
				for kHua, vHua in pairs(self.m_pUserBuHuaTable[userId]) do
					table.insert(info.iHuaPai, vHua)
				end
				
				if kUser:onGetSeatId() == pSeatId then
					-- 写入回看
					table.insert(self.m_pOneRoundLookbackTable, {
						iName = name,
						iInfo = info,
					})
				end

				self:onGetGameTable():onSendPackage(kUser:onGetUserId(), name, info)
			end
		else
			time = 100 -- 如果没有花可补直接跳到下一个
		end

		local timerName = "timerBuHua"
		local callback = self.onTimeOutBuHua
		self:startTimer(timerName, time, callback, nextSeatId)
	else
		local callback = self.onDealProcessWork
		time = 1000
		self:startTimer("timerProcess", time, callback)
	end
end

function GameRound:onUserBuHua(pUserId, pCardValue)
	Log.d(TAG, "onUserBuHua pUserId[%s], pCardValue[%s] roundStatus[%s]", pUserId, pCardValue, self.m_pRoundStatus)
	local name = "ServerBCMahjongBuHua"
	local info = {}
	if not self:isRoundStatusOpBuHua() then return end
	local pUser = self:onGetUserByUserId(pUserId)
	if not pUser then return end
	if math.floor(pCardValue / 10) > 4 then
		table.insert(self.m_pUserBuHuaTable[pUserId], pCardValue)
		self:onMoveOneHandCard(pUserId, pCardValue)
		self:onGetGameRule():isCanHuaGang(pUser)
		
		info.iUserId = pUserId
		info.iHuaPai = {}
		for kHua, vHua in pairs(self.m_pUserBuHuaTable[pUserId]) do
			table.insert(info.iHuaPai, vHua)
		end

		info.iBuPai = pCardValue
		-- 写入回看
		table.insert(self.m_pOneRoundLookbackTable, {
			iName = name,
			iInfo = info,
		})	
		self:onGetGameTable():onBroadcastTableUsers(name, info)

		self:setRoundStatus(roundStatusMap.ROUND_STATUS_DRAW_CARD)

		--补花后延迟0.7s抓牌
		local pCallBack = self.onUserDrawCard
		self:startTimer("timerBuHua", 700, pCallBack, pUserId)
	end
end

function GameRound:ClientUserSelectMaiDian(pData, pUserId)
	if not self:isRoundStatusOpSelectMaiDian() then return end
	local pUser = self:onGetUserByUserId(pUserId)
	if not pUser then return end
	-- 如果已经买过了
	if self.m_pUserMaiDianTable[pUserId] >= 0 then return end
	local pIsHasIn = false
	pData.iMaiDian = pData.iMaiDian or 0
	for _, kMaiDian in pairs(self.m_pCanMaiDianTable) do
		if kMaiDian == pData.iMaiDian then
			pIsHasIn = true
			break
		end
	end
	self.m_pUserMaiDianTable[pUserId] = pData.iMaiDian or 0
	local name = "ServerBCMahjongUserMaiDianDone"
	local info = {}
	info.iUserId = pUserId
	info.iMaiDian = self.m_pUserMaiDianTable[pUserId]
	self:onGetGameTable():onBroadcastTableUsers(name, info)

	-- 写入回看数据
	table.insert(self.m_pOneRoundLookbackTable, {
		iName = name,
		iInfo = info,
	})

	-- 是不是已经都已经选了
	local pIsAllSelect = true
	for kUserId, kMaiDian in pairs(self.m_pUserMaiDianTable) do
		if kMaiDian < 0 then
			pIsAllSelect = false
			break
		end
	end
	if pIsAllSelect then
		self:onDealProcessWork()
	end
end

--[[
	最后海底捞操作
]]
function GameRound:onGameLaoLastCard(pUserId, iIsReConnect)
	iIsReConnect = iIsReConnect or false
	local name = "ServerBCMahjongStartLaoCard"
	local info = {}
	if iIsReConnect then
		info.iUserId = self.m_pGameUsers[self.m_pCurOutCardSeatId]:onGetUserId()
		self:onGetGameTable():onSendPackage(pUserId, name, info)
	else
		self:setRoundStatus(roundStatusMap.ROUND_STATUS_OP_LAO_LAST_CARD)
		local pUser = self:onGetUserByUserId(pUserId)
		self.m_pCurOutCardSeatId = pUser:onGetSeatId()
		info.iUserId = pUserId
		self:onGetGameTable():onBroadcastTableUsers(name, info)
	end
end

--[[
	玩家抓牌, isBankerOne表示是否为庄家多发牌
]]
function GameRound:onUserDrawCard(pUserId, isBankerOne, pIsGang)
	Log.d(TAG, "onUserDrawCard pUserId[%s] isBankerOne[%s]", pUserId, isBankerOne)
	local pUser = self:onGetUserByUserId(pUserId)
	if not pUser then return end 
	local pRemainCard = self.m_pMahjongPool:remainCard()
	local pUserCount = self.m_pGameTable:onGetGameTableMaxUserCount()
	-- 最后几张牌需不需要提示
	if self.m_pGameRule.isLastCardNeedTips then
		local pIsOk, pMsg = self.m_pGameRule:isLastCardNeedTips(pRemainCard, pUserCount)
		if pIsOk then 
			pMsg = pMsg or "最后一圈"
			for _, kUser in pairs(self.m_pGameUsers) do
				self.m_pGameTable:onServerUserShowHints(kUser:onGetUserId(), 0, pMsg)
			end
		end
	end
	if self.m_pGameRule.isLastCardCanLao then --最后一张牌是不是有手动捞的操作
		local pIsOk = self.m_pGameRule:isLastCardCanLao(pRemainCard, pUserId)
		if pIsOk then
			self:onGameLaoLastCard(pUserId)
			return
		end
	end
	-- 首先判断是不是流局了
	if self.m_pGameRule:isGameStopLiuJu(self.m_pCurOutCardSeatId, pRemainCard) then
		self:onGameRoundStop(1)
		return
	end
	local cardValue = self.m_pMahjongPool:drawCard(pUser:onGetSeatId())
	self:onAddOneHandCard(pUserId, cardValue)
	self:onAddOneDrawCard(pUserId, cardValue)
	-- 如果是杠牌，写进杠牌的信息里面
	if pIsGang then
		self:onSetBlockMakeGangCard(pUserId, cardValue)
	end
	-- 当前出牌玩家设置
	self.m_pCurOutCardSeatId = pUser:onGetSeatId()
	self:onBroadcastUserDrawCard(pUserId, cardValue, isBankerOne)
end

function GameRound:onGetCurDrawCardUser()
	local userCount = self.m_pGameTable:onGetGameTableMaxUserCount()
	if self:onGetGameRule():isCanXueZhanDaoDi() then
		local nextSeatId = self.m_pCurOutCardSeatId % userCount + 1
		if self.m_pGameUsers[nextSeatId]:onGetIsHu() >= 1 then
			self.m_pCurOutCardSeatId = nextSeatId
			return self:onGetCurDrawCardUser()
		else
			return self.m_pGameUsers[nextSeatId]
		end
	else
		local nextSeatId = self.m_pCurOutCardSeatId % userCount + 1
		return self.m_pGameUsers[nextSeatId]
	end
end

function GameRound:onGetUserOpTable(pUserId)
	local pOpTable = {}
	for k, v in pairs(self.m_pUserCurOpTable) do
		local pUser = self.m_pGameUsers[v.iSeatId]
		if pUser and pUser:onGetUserId() == pUserId and v.iStatus <= 0 then
			local op = {}
			op.iOpValue = v.iOpValue
			op.iCardValue = v.iCardValue
			pOpTable[#pOpTable + 1] = op
		end
	end
	return pOpTable
end

function GameRound:onGetUserAllCardTingInfoTable(pUserId)
	-- 如果是该自己打牌
	local tUserId = self:onGetDrawCardUserId()
	Log.d(TAG, "pUserId[%s] tUserId[%s]", pUserId, tUserId)
	if pUserId == tUserId and pUserId > 0 then
		local pUser = self:onGetUserByUserId(pUserId)
		if pUser and pUser:onGetIsHu() <= 0 then
			local pAllCardTingInfoTable = self.m_pGameRule:onGetTingCardTable(pUser)
			for _, kCardTingInfo in pairs(pAllCardTingInfoTable) do
				for _, kTingInfo in pairs(kCardTingInfo.iTingCardInfoTable) do
					kTingInfo.iHandCardCountMap = nil
					kTingInfo.iBlockCardMap = nil
				end
			end
			return pAllCardTingInfoTable
		end
	end
	return {}
end

function GameRound:onCheckOutCardIsVaild(pUser, cardValue)
	local pHandCardMap = pUser:onGetHandCardMap()
	if self.m_pCurOutCardSeatId ~= pUser:onGetSeatId() then
		return false
	end
	if self:onGetGameRule().onCheckOutCardIsVaild then
		if not self:onGetGameRule():onCheckOutCardIsVaild(pUser, cardValue) then
			return false
		end
	end 
	for k, v in pairs(pHandCardMap) do
		if v == cardValue then
			return true
		end
	end
	-- Log.dump(TAG, pHandCardMap, "pHandCardMap")
	return false
end

function GameRound:onDealExtendTurnMoney(result)
	if 2 == result then
		return 
	end
	if 0 == result and self.m_pGameRule.isCanMaiMa and self.m_pGameRule:isCanMaiMa() then
		self.m_pAllTurnMoneyTable.iMaiMaInfoTable = self.m_pGameRule:onDealMaiMaInfo(self.m_pGameUsers)
		-- Log.dump(TAG, self.m_pAllTurnMoneyTable, "self.m_pAllTurnMoneyTable")
	end
	-- 查叫
	if self.m_pGameRule.isCanChaJiao and self.m_pGameRule:isCanChaJiao(self.m_pGameUsers) then
		local pBasePoint = self.m_pGameTable.m_pCommonConfig.iBasePoint
		self.m_pGameRule:onDealChaJiaoTurnMoney(self.m_pAllTurnMoneyTable, self.m_pGameUsers, pBasePoint)
	end
end

--[[
	result : 0 有人胡牌 1流局 2中途退出
]]
function GameRound:onGameRoundStop(result)
	-- 停止计时器
	self:stopTimer("timerProcess")
	self:stopTimer("timerBankerCard")
	self:stopTimer("timerLastCard")
	self:stopTimer("timerAutoOutCard")
	self:stopTimer("timerHaiDiLaoDelay")
	self:stopTimer("timerBuHua")
	self:setRoundStatus(roundStatusMap.ROUND_STATUS_NONE)
	Log.d(TAG, "onGameRoundStop result[%s] iTableId[%s]", result, self.m_pGameTable.m_pCommonConfig.iTableId)
	self:onDealExtendTurnMoney(result)
	-- 如果是中途退出，该局流水还算不算, 如果现在是等待下一次牌局
	if 2 == result then
		if self:onGetGameTable():isTableStatusRoundStop() then
			self:clear()
			for k, v in pairs(self.m_pGameUsers) do
				v:onClearOneRound()
			end
		end
		if self.m_pGameRule.isCanMoneyByForceStop and self.m_pGameRule:isCanMoneyByForceStop() then

		else
			self.m_pAllTurnMoneyTable.iGangTurnMoneyTable = {}
			self.m_pAllTurnMoneyTable.iHuTurnMoneyTable = {}
		end
	end
	if 1 == result then
		self:onClearGameRoundBankerInfo()
	end
	-- 计算所有的金钱流
	local pExtendInfoTable, pTurnMoneyTable = self.m_pGameRule:onGameRoundStop(result, self.m_pAllTurnMoneyTable, self.m_pGameUsers, self.m_pGameTable:isFirendBattleRoom())
	for k, v in pairs(pTurnMoneyTable) do
		local pUser = self:onGetUserByUserId(k)
		if pUser then
			pUser:onSetTurnMoney(v)
			pUser:onSetMoney(pUser:onGetMoney() + v)
		end
	end

	if self.m_pGameRule.isFriendBattleGameOver and self.m_pGameRule:isFriendBattleGameOver(result) then
		result = 2 
	end
	-- Log.dump(TAG, pExtendInfoTable, "pExtendInfoTable")
	-- Log.dump(TAG, pTurnMoneyTable, "pTurnMoneyTable")
	local name = "ServerBCGameStopOneRound"
	local info = {}
	info.iRoomType = self.m_pGameTable.m_pCommonConfig.iRoomType
	info.iResultType = result
	info.iTimeStamp = os.time()
	info.iUserTable = {}
	for k, v in pairs(self.m_pGameUsers) do
		local temp = {}
		temp.iUserId = v:onGetUserId()
		temp.iHandCards = v:onGetHandCardMap()
		temp.iBlockCards = v:onGetBlockCardMap()
		temp.iMoney = v:onGetMoney()
		temp.iTurnMoney = v:onGetTurnMoney()
		temp.iExtendInfo = json.encode(pExtendInfoTable[temp.iUserId])
		info.iUserTable[#info.iUserTable + 1] = temp
	end
	info.iIsBattleStop = 0
	info.iBattleStopUserTable = {}
	if self.m_pGameTable:isFriendBattleGameOver(result) then
		info.iIsBattleStop = 1
		info.iBattleStopUserTable = self:onGetFriendBattleGameOverUserTable()
	end
	info.iMaiMaCardInfoTable = {}
	if self.m_pAllTurnMoneyTable.iMaiMaInfoTable and self.m_pAllTurnMoneyTable.iMaiMaInfoTable.iMaiMaCardTable then
		info.iMaiMaCardInfoTable = self.m_pAllTurnMoneyTable.iMaiMaInfoTable.iMaiMaCardTable
	end

	for k, v in pairs(self.m_pGameUsers) do
		self.m_pGameTable:onSendPackage(v:onGetUserId(), name, info)
	end

	self.m_pGameTable.m_pFriendBattleConfig.iPreRoundGameStopTable = clone(info)

	-- 写入回看数据
	table.insert(self.m_pOneRoundLookbackTable, {
		iName = name,
		iInfo = info,
	})

	self.m_pGameTable:onGameRoundStop(result)

	-- Log.dump(TAG, self.m_pOneRoundLookbackTable, "self.m_pOneRoundLookbackTable")

	self.m_pOneRoundLookbackTable = {}
end

function GameRound:onGetFriendBattleGameOverUserTable()
	if not self.m_pGameTable:isFirendBattleRoom() then
		return
	end
	local pBattleStopUserTable = {} 
	for k, v in pairs(self.m_pGameTable.m_pGameUsers) do
		local temp = {}
		temp.iUserId = v:onGetUserId()
		temp.iTurnMoney = v:onGetMoney()
		temp.iNickName = v:onGetNickName()
		temp.iHeadUrl = v:onGetHeadUrl()
		temp.iSex = v:onGetSex()
		local iExtendTable = self.m_pGameRule:onGetUserExtendTable(v) or {}
		temp.iExtendInfo = json.encode(iExtendTable)
		pBattleStopUserTable[#pBattleStopUserTable + 1] = temp
	end
	return pBattleStopUserTable
end

function GameRound:onGetUserGameInfo(pUser, pReUser)
	local pUserGameInfoTable = {}
	pUserGameInfoTable.iHandCards = {}
	local pHandCardMap = pUser:onGetHandCardMap()
	-- 手牌
	if #pHandCardMap > 0 then
		for _, kCardValue in pairs(pHandCardMap) do
			table.insert(pUserGameInfoTable.iHandCards, pUser == pReUser and kCardValue or 0)
		end
	end
	-- 操作牌
	local pBlockCardMap = pUser:onGetBlockCardMap()
	pUserGameInfoTable.iBlockCards = pBlockCardMap
	if self.m_pGameRule.onBlockCardMapFilter then
		pUserGameInfoTable.iBlockCards = self.m_pGameRule:onBlockCardMapFilter(pUser, pReUser, pBlockCardMap)
	end

	local pOutCardMap = pUser:onGetOutCardMap()
	pUserGameInfoTable.iOutCards = pOutCardMap

	if pUser == pReUser then
		pUserGameInfoTable.iOpTable = self:onGetUserOpTable(pUser:onGetUserId())
		pUserGameInfoTable.iAllCardTingInfoTable = self:onGetUserAllCardTingInfoTable(pUser:onGetUserId())
	else
		pUserGameInfoTable.iOpTable = {}
		pUserGameInfoTable.iAllCardTingInfoTable = {}
	end
	
	return pUserGameInfoTable
end

--定时器 框架部分
local function getFullNameByKey(key)
	return 'm_'..key..'Handle'
end 

function GameRound:getTimerHandlerByKey(key)
	return self[getFullNameByKey(key)]
end 

function GameRound:setTimerHandler(key , value)
	self[getFullNameByKey(key)] = value
end 

function GameRound:startTimer(key, time, callback, ...)
	self:stopTimer(key)
	if not self:getTimerHandlerByKey(key) then 
		self:setTimerHandler(key, self.m_pScheduleMgr:registerOnceNow(callback, time, self, ...) )
	end 
end 

function GameRound:stopTimer(key)
	local h = self:getTimerHandlerByKey(key)
	if h then 
		self.m_pScheduleMgr:unregister(h)
		self:setTimerHandler(key, nil)
	end 
end 

function GameRound:resetTimer(key)
	local h = self:getTimerHandlerByKey(key)
	if h then 
		local s = self.m_pScheduleMgr:getSchedulerByHandler(h)
		if s then 
			local time = s.intaval
			self:stopTimer(key)
			self:startTimer(key, time)
		end 
	end
end 

function GameRound:onGetUserByUserId(pUserId)
	if not pUserId then return end
	for k, v in pairs(self.m_pGameUsers) do
		if v:onGetUserId() == pUserId then
			return v
		end
	end
end

function GameRound:isOldUserReconnenct()
	return false
end

function GameRound:onGetTotalOutCard()
	return self.m_pTotalOutCard
end

function GameRound:setRoundStatus(status)
	self.m_pRoundStatus = status
end

function GameRound:isRoundStatusNone()
	return self.m_pRoundStatus == roundStatusMap.ROUND_STATUS_NONE
end

function GameRound:isRoundStatusDrawCard()
	return self.m_pRoundStatus == roundStatusMap.ROUND_STATUS_DRAW_CARD
end

function GameRound:isRoundStatusOutCard()
	return self.m_pRoundStatus == roundStatusMap.ROUND_STATUS_OUT_CARD
end

function GameRound:isRoundStatusOpDrawCard()
	return self.m_pRoundStatus == roundStatusMap.ROUND_STATUS_OP_DRAW_CARD
end

function GameRound:isRoundStatusOpOutCard()
	return self.m_pRoundStatus == roundStatusMap.ROUND_STATUS_OP_OUT_CARD
end

function GameRound:isRoundStatusOpBuGangCard()
	return self.m_pRoundStatus == roundStatusMap.ROUND_STATUS_OP_BUGANG_CARD
end

function GameRound:isRoundStatusOpPengCard()
	return self.m_pRoundStatus == roundStatusMap.ROUND_STATUS_OP_PENG_CARD
end

function GameRound:isRoundStatusOpChiCard()
	return self.m_pRoundStatus == roundStatusMap.ROUND_STATUS_OP_CHI_CARD
end

function GameRound:isRoundStatusOpSelectGangCard()
	return self.m_pRoundStatus == roundStatusMap.ROUND_STATUS_OP_SELECT_GANG_CARD
end

function GameRound:isRoundStatusOpLastCard()
	return self.m_pRoundStatus == roundStatusMap.ROUND_STATUS_OP_LAST_CARD
end

function GameRound:isRoundStatusOpSelectDingQue()
	return self.m_pRoundStatus == roundStatusMap.ROUND_STATUS_OP_SELECT_DINGQUE
end

function GameRound:isRoundStatusOpHuanSanZhang()
	return self.m_pRoundStatus == roundStatusMap.ROUND_STATUS_OP_HUAN_SAN_ZHANG
end

function GameRound:isRoundStatusOpBaoTing()
	return self.m_pRoundStatus == roundStatusMap.ROUND_STATUS_OP_BAO_TING
end

function GameRound:isRoundStatusOpAutoOutCard()
	return self.m_pRoundStatus == roundStatusMap.ROUND_STATUS_OP_AUTO_OUT_CARD
end

function GameRound:isRoundStatusOpLangQi()
	return self.m_pRoundStatus == roundStatusMap.ROUND_STATUS_OP_LANG_QI
end

function GameRound:isRoundStatusOpOutCardMyself()
	return self.m_pRoundStatus == roundStatusMap.ROUND_STATUS_OP_OUT_CARD_MYSELF
end

function GameRound:isRoundStatusOpSelectMaiDian()
	return self.m_pRoundStatus == roundStatusMap.ROUND_STATUS_OP_SELECT_MAIDIAN
end

function GameRound:isRoundStatusOpLaoLastCard()
	return self.m_pRoundStatus == roundStatusMap.ROUND_STATUS_OP_LAO_LAST_CARD
end

function GameRound:isRoundStatusOpBuHua()
	return self.m_pRoundStatus == roundStatusMap.ROUND_STATUS_OP_BU_HUA
end

function GameRound:onMoveOneHandCard(userId, cardValue)
	local pUser = self:onGetUserByUserId(userId)
	local pHandCardMap = pUser:onGetHandCardMap()
	for k, v in pairs(pHandCardMap) do
		if v == cardValue then
			table.remove(pHandCardMap, k)
			return true
		end
	end
	return false
end

function GameRound:onAddOneHandCard(userId, cardValue)
	local pUser = self:onGetUserByUserId(userId)
	local pHandCardMap = pUser:onGetHandCardMap()
	if cardValue and cardValue > 0 then
		pHandCardMap[#pHandCardMap + 1] = cardValue
	end
end

function GameRound:onMoveOneBlockCard(userId, cardValue, opValue)
	local pUser = self:onGetUserByUserId(userId)
	local pBlockCardMap = pUser:onGetBlockCardMap()
	for k, v in pairs(pBlockCardMap) do
		if v.iOpValue == opValue and v.iCardValue == cardValue then
			if OperationType:isBuGang(opValue) then
				v.iOpValue = OperationType.PENG
			else
				table.remove(pHandCardMap, k)
			end
			return true
		end
	end
	return false
end

function GameRound:onAddOneBlockCard(userId, cardValue, opValue, pTuserId)
	local pUser = self:onGetUserByUserId(userId)
	local pBlockCardMap = pUser:onGetBlockCardMap()
	self.m_pTotalOutCard = self.m_pTotalOutCard + 1
	if OperationType:isBuGang(opValue) then
		for k, v in pairs(pBlockCardMap) do
			if OperationType:isPeng(v.iOpValue) and v.iCardValue == cardValue then
				v.iOpValue = opValue
				v.iRank = self.m_pTotalOutCard 
				return
			end
		end
	end
	pBlockCardMap[#pBlockCardMap + 1] = {
		iCardValue = cardValue,
		iOpValue = opValue,
		iRank = self.m_pTotalOutCard,
		iTUserId = pTuserId or 0,
		-- iCardTable = mCardTable or 0，
		iGangCardValue = 0,
	}
end

function GameRound:onSetBlockMakeGangCard(pUserId, pCardValue)
	local pUser = self:onGetUserByUserId(pUserId)
	local pBlockCardMap = pUser:onGetBlockCardMap()
	-- 找到最后的一次操作，将杠到的牌设置进去
	for k, v in pairs(pBlockCardMap) do
		if OperationType:isHasGang(v.iOpValue) and self.m_pTotalOutCard == v.iRank then
			v.iGangCardValue = pCardValue
		end
	end
end

function GameRound:onAddOneOutCard(userId, cardValue)
	local pUser = self:onGetUserByUserId(userId)
	local pOutCardMap = pUser:onGetOutCardMap()
	self.m_pTotalOutCard = self.m_pTotalOutCard + 1
	pOutCardMap[#pOutCardMap + 1] = {
		iCardValue = cardValue,
		iStatus = 0,
		iRank = self.m_pTotalOutCard
	}
end

function GameRound:onAddOneDrawCard(userId, cardValue)
	local pUser = self:onGetUserByUserId(userId)
	local pDrawCardMap = pUser:onGetDrawCardMap()
	table.insert(pDrawCardMap, cardValue)
end

function GameRound:onBroadcastUserDrawCard(userId, cardValue, isBankerOne)
	local pUser = self:onGetUserByUserId(userId)
	if not pUser then return end
	-- 是否能去掉过胡的状态
	if self:onGetGameRule().onUserClearGuoHu then
		self:onGetGameRule():onUserClearGuoHu(pUser, DefineType.CLEAR_WHEN_DRAWCARD)
	end
	local pRemainCard = self.m_pMahjongPool:remainCard()
	local pUserCount = self:onGetGameTable():onGetGameTableMaxUserCount()
	local pIsLastCard = false
	if self.m_pGameRule.isRaoPingLastCardNotOut and self.m_pGameRule:isRaoPingLastCardNotOut(pRemainCard, pUserCount) then
		pIsLastCard = true
	end

	-- 这是给南京麻将补花的
	local pIsNeedBuHua = false
	if self.m_pGameRule.onGetNeedBuHua and self.m_pGameRule:onGetNeedBuHua(pUser, cardValue) then
		pIsNeedBuHua = true
	end

	local name = "ServerBCUserDrawCard"
	local info = {}
	info.iUserId = userId
	info.iCardValue = 0
	info.iOpTable = {}
	info.iRemainCardCount = self.m_pMahjongPool:remainCard()
	info.iCanNotOutCard = 1
	self:onClearUserCurOpTable()
	for k, v in pairs(self.m_pGameUsers) do
		Log.d(TAG, "v:onGetUserId()[%s] info.iUserId[%s]", v:onGetUserId(), info.iUserId)
		if v:onGetUserId() == info.iUserId then
			info.iCardValue = cardValue
			if not isBankerOne and not pIsNeedBuHua then
				local opTable = self.m_pGameRule:onGetOpTableWhenDrawCard(pUser, cardValue, self.m_pGameUsers)
				local pAllCardTingInfoTable = {}
				if not pIsLastCard then
					pAllCardTingInfoTable = self.m_pGameRule:onGetTingCardTable(pUser)
					info.iCanNotOutCard = 0
				end
				info.iOpTable = opTable
				for _, p in pairs(info.iOpTable) do
					local op = {
						iOpValue = p.iOpValue,
						iCardValue = p.iCardValue,
						iSeatId = v:onGetSeatId(),
						iTSeatId = pUser:onGetSeatId(),
						iStatus = 0
					}
					table.insert(self.m_pUserCurOpTable, op)
				end
				info.iAllCardTingInfoTable = pAllCardTingInfoTable
			else
				info.iOpTable = {}
				info.iAllCardTingInfoTable = {}
				info.iCanNotOutCard = 1
			end
		else
			info.iCardValue = 0
			info.iOpTable = {}
			info.iAllCardTingInfoTable = {}
			info.iCanNotOutCard = 1
		end
		self.m_pGameTable:onSendPackage(v:onGetUserId(), name, info)
	end
	-- 写入回看数据
	info.iCardValue = cardValue
	info.iOpTable = {}
	info.iAllCardTingInfoTable = {}
	table.insert(self.m_pOneRoundLookbackTable, {
		iName = name,
		iInfo = info,
	})

	if isBankerOne then
		self:setRoundStatus(roundStatusMap.ROUND_STATUS_DRAW_CARD)
	elseif #self.m_pUserCurOpTable <= 0 then
		self:setRoundStatus(roundStatusMap.ROUND_STATUS_OUT_CARD)
		
		-- 这个是特殊给饶平人民的
		if pIsLastCard then
			self:setRoundStatus(roundStatusMap.ROUND_STATUS_OP_LAST_CARD)
			local pCallBack = self.onUserDrawCard
			self:startTimer("timerLastCard", 1200, pCallBack, self:onGetCurDrawCardUser():onGetUserId())
		end 
		-- 这个是给卡二条报听的
		if pUser:onGetIsBaoTing() > 0 then
			self:setRoundStatus(roundStatusMap.ROUND_STATUS_OP_AUTO_OUT_CARD)
			local pCallBack = self.onServerUserAutoOutCard
			self:startTimer("timerAutoOutCard", 1200, pCallBack, pUser:onGetUserId(), cardValue)
		end
		-- 这个是给卡心五廊起的

		if pIsNeedBuHua then
			self:setRoundStatus(roundStatusMap.ROUND_STATUS_OP_BU_HUA)
			local pCallBack = self.onUserBuHua
			self:startTimer("timerBuHua", 100, pCallBack, pUser:onGetUserId(), cardValue)
		end

	else
		self:onSortUserCurOpTable()
		self:setRoundStatus(roundStatusMap.ROUND_STATUS_OP_DRAW_CARD)
		if pIsLastCard then
			self:setRoundStatus(roundStatusMap.ROUND_STATUS_OP_LAST_CARD)
		end 
		-- 把所有的操作写入回放
		self:onWriteLookbackAllUserOpTable()
	end
end

function GameRound:onReconnetSelectGangCardTable(pUser)
	local pUserId = pUser:onGetUserId()
	if self:isRoundStatusOpSelectGangCard() then
		local name = "ServerUserSelectGangCard"
		local info = {}
		info.iUserId = pUserId
		local pGangCardTable, pIsCanChaoDi = self:onGetGameRule():onGetUserReconnectSelectGangCardInfo(pUser)
		info.iGangCardTable = pGangCardTable
		info.iIsCanChaoDi = pIsCanChaoDi and 1 or 0
		if #info.iGangCardTable > 0 then
			self:onGetGameTable():onSendPackage(pUserId, name, info)
		end
	end
end

function GameRound:onReconnetMakeGangCardTable(pUser)
	local name = "ServerBCMahjongMakeGangCard"
	local info = {}
	info.iGangCardTable = {}
	if self.m_pGameRule.onGetMakeGangCardTable then 
		info.iGangCardTable = self.m_pGameRule:onGetMakeGangCardTable()
		if #info.iGangCardTable <= 0 then
			return
		end
		info.iRemainCardCount = self.m_pMahjongPool:remainCard()
		self:onGetGameTable():onSendPackage(pUser:onGetUserId(), name, info)
	end
end

function GameRound:onClearUserCurOpTable()
	self.m_pUserCurOpTable = {}
end

function GameRound:onBroadcastUserOutCard(userId, cardValue)
	local pUser = self:onGetUserByUserId(userId)
	if self:onGetGameRule().onUserClearGuoHu then
		self:onGetGameRule():onUserClearGuoHu(pUser, DefineType.CLEAR_WHEN_OUTCARD)
	end
	local name = "ServerBCUserOutCard"
	local info = {}
	info.iUserId = pUser:onGetUserId()
	info.iCardValue = cardValue
	info.iOpTable = {}
	self:onClearUserCurOpTable()
	local pIsMyselfCanOp = false
	-- 首先判断自己能不能胡
	local opTable = self.m_pGameRule:onGetOpTableWhenOutCard(pUser, pUser, cardValue, self.m_pGameUsers)
	if #opTable > 0 then
		for _, p in pairs(opTable) do
			local op = {
				iOpValue = p.iOpValue,
				iCardValue = p.iCardValue,
				iSeatId = pUser:onGetSeatId(),
				iTSeatId = pUser:onGetSeatId(),
				iStatus = 0
			}
			table.insert(self.m_pUserCurOpTable, op)
		end
		pIsMyselfCanOp = true
	else
		for k, v in pairs(self.m_pGameUsers) do
			if pUser ~= v then
				local opTable = self.m_pGameRule:onGetOpTableWhenOutCard(pUser, v, cardValue, self.m_pGameUsers)
				if #opTable > 0 then
					for _, p in pairs(opTable) do
						local op = {
							iOpValue = p.iOpValue,
							iCardValue = p.iCardValue,
							iSeatId = v:onGetSeatId(),
							iTSeatId = pUser:onGetSeatId(),
							iStatus = 0
						}
						table.insert(self.m_pUserCurOpTable, op)
					end
				end
			end
		end
	end
	for k, v in pairs(self.m_pGameUsers) do
		info.iOpTable = {}
		-- 找到自己当前操作
		for _, op in pairs(self.m_pUserCurOpTable) do
			if op.iSeatId == v:onGetSeatId() and op.iStatus <= 0 then
				table.insert(info.iOpTable, op)
			end
		end
		self.m_pGameTable:onSendPackage(v:onGetUserId(), name, info)
	end
	-- 写入回看数据
	info.iOpTable = {}
	table.insert(self.m_pOneRoundLookbackTable, {
		iName = name,
		iInfo = info,
	})

	--处理玩家广播出牌后的逻辑
	if self:onGetGameRule().onGetDealTableWhenUserOutCard then
		self:onGetGameRule():onGetDealTableWhenUserOutCard(pUser, cardValue)
	end

	-- 如果有操作
	if #self.m_pUserCurOpTable > 0 then
		self:onSortUserCurOpTable()
		self:setRoundStatus(pIsMyselfCanOp and roundStatusMap.ROUND_STATUS_OP_OUT_CARD_MYSELF or roundStatusMap.ROUND_STATUS_OP_OUT_CARD)
		-- 把所有的操作写入回放
		self:onWriteLookbackAllUserOpTable()
	else
		self:onSortUserCurOpTable()
		self:setRoundStatus(roundStatusMap.ROUND_STATUS_DRAW_CARD)
		self:onUserDrawCard(self:onGetCurDrawCardUser():onGetUserId())
	end
end

function GameRound:onSortUserCurOpTable()
	if #self.m_pUserCurOpTable <= 0 then return end
	for i = 1, #self.m_pUserCurOpTable - 1 do
		for j = i + 1, #self.m_pUserCurOpTable do
			local opI = self.m_pUserCurOpTable[i]
			local opJ = self.m_pUserCurOpTable[j]
			local pUserCount = self.m_pGameTable:onGetGameTableMaxUserCount()
			local pIsSwap = false
			if OperationType:isHasChi(opI.iOpValue) and OperationType:isPeng(opJ.iOpValue) then
				pIsSwap = true
			end
			if OperationType:isHasChi(opI.iOpValue) and OperationType:isHasGang(opJ.iOpValue) then
				pIsSwap = true
			end
			if OperationType:isHasChi(opI.iOpValue) and OperationType:isHasHu(opJ.iOpValue) then
				pIsSwap = true
			end
			if OperationType:isPeng(opI.iOpValue) and OperationType:isHasHu(opJ.iOpValue) then
				pIsSwap = true
			end
			if OperationType:isPeng(opI.iOpValue) and OperationType:isHasGang(opJ.iOpValue) then
				pIsSwap = true
			end
			if OperationType:isHasGang(opI.iOpValue) and OperationType:isHasHu(opJ.iOpValue) then
				pIsSwap = true
			end
			if OperationType:isHasHu(opI.iOpValue) and OperationType:isHasHu(opJ.iOpValue) then
				-- 如果有特殊情况
				if self:onGetGameRule().isNeedSwap then
					local iUser = self.m_pGameUsers[opI.iSeatId]
					local jUser = self.m_pGameUsers[opJ.iSeatId]
					local tUser = self.m_pGameUsers[opI.iTSeatId]
					if iUser and jUser and tUser then
						pIsSwap = self:onGetGameRule():isNeedSwap(iUser, jUser, tUser, opI.iCardValue)
					end
				else
					local pCurx = (opI.iSeatId - opI.iTSeatId + pUserCount) % pUserCount
					local pCury = (opJ.iSeatId - opJ.iTSeatId + pUserCount) % pUserCount
					if pCurx > pCury then
						pIsSwap = true
					end
				end
			end
			if OperationType:isGuo(opI.iOpValue) and not OperationType:isGuo(opJ.iOpValue) then
				pIsSwap = true
			end
			if pIsSwap then
				local t = self.m_pUserCurOpTable[i]
				self.m_pUserCurOpTable[i] = self.m_pUserCurOpTable[j]
				self.m_pUserCurOpTable[j] = t
			end
		end
	end
	Log.dump(TAG, self.m_pUserCurOpTable, "self.m_pUserCurOpTable")
end

---------------------------------------- socket --------------------------------------
--[[
	玩家选择捞或不捞牌
]]
function GameRound:ClientUserHaiDiLaoCard(data, userId)
	if not self:isRoundStatusOpLaoLastCard() then return end
	local pUser = self:onGetUserByUserId(userId)
	if not pUser then return end
	if self.m_pCurOutCardSeatId ~= pUser:onGetSeatId() then return end
	local iLaoType = data.iLaoType or 0
	local name = "ServerBCMahjongDoneLaoCard"
	local info = {}
	info.iUserId = userId
	info.iLaoType = iLaoType
	info.iCardValue = 0
	info.iOpTable = {}
	if iLaoType == 1 then --玩家选择捞牌
		info.iCardValue = self.m_pMahjongPool:drawCard()
		self.m_pGameRule.m_pLastLaoCard = info.iCardValue
	end

	if iLaoType == 0 then --玩家选择不捞
		self:onGetGameTable():onBroadcastTableUsers(name, info)
		-- 写入回看数据
		table.insert(self.m_pOneRoundLookbackTable, {
			iName = name,
			iInfo = info,
		})
		self:onUserDrawCard(self:onGetCurDrawCardUser():onGetUserId())
	elseif iLaoType == 1 then --玩家选择捞牌
		self:onClearUserCurOpTable()
		local pIsMyselfCanOp = false

		-- 首先判断自己能不能胡
		local opTable = self.m_pGameRule:onGetOpWhenLaoLastCard(pUser, info.iCardValue, self.m_pGameUsers)
		if #opTable > 0 then
			for _, p in pairs(opTable) do
				local op = {
					iOpValue = p.iOpValue,
					iCardValue = p.iCardValue,
					iSeatId = pUser:onGetSeatId(),
					iTSeatId = pUser:onGetSeatId(),
					iStatus = 0
				}
				table.insert(self.m_pUserCurOpTable, op)
			end
			pIsMyselfCanOp = true
		else
			for k, v in pairs(self.m_pGameUsers) do
				if pUser ~= v then
					local opTable = self.m_pGameRule:onGetOpWhenLaoLastCard(v, info.iCardValue, self.m_pGameUsers)
					if #opTable > 0 then
						for _, p in pairs(opTable) do
							local op = {
								iOpValue = p.iOpValue,
								iCardValue = p.iCardValue,
								iSeatId = v:onGetSeatId(),
								iTSeatId = pUser:onGetSeatId(),
								iStatus = 0
							}
							table.insert(self.m_pUserCurOpTable, op)
						end
					end
				end
			end
			
		end
		for k, v in pairs(self.m_pGameUsers) do
			info.iOpTable = {}
			-- 找到自己当前操作
			for _, op in pairs(self.m_pUserCurOpTable) do
				if op.iSeatId == v:onGetSeatId() and op.iStatus <= 0 then
					table.insert(info.iOpTable, op)
				end
			end
			-- info.iOpHints = #self.m_pUserCurOpTable > 0 and 1 or 0
			self.m_pGameTable:onSendPackage(v:onGetUserId(), name, info)
		end
		-- 写入回看数据
		info.iOpTable = {}
		table.insert(self.m_pOneRoundLookbackTable, {
			iName = name,
			iInfo = info,
		})
		-- 如果有操作
		if #self.m_pUserCurOpTable > 0 then
			self:onSortUserCurOpTable()
			self:setRoundStatus(pIsMyselfCanOp and roundStatusMap.ROUND_STATUS_OP_OUT_CARD_MYSELF or roundStatusMap.ROUND_STATUS_OP_OUT_CARD)
		else --没有人能胡牌直接流局 
			local function callback()
				self:onGameRoundStop(1)
			end
			self:startTimer("timerHaiDiLaoDelay", 1000, callback)
		end
	end
end

--[[
	玩家打出一张牌
]]
function GameRound:ClientUserOutCard(data, userId)
	Log.d(TAG, "ClientUserOutCard userId[%s] cardValue[%s] RoundStatus[%s]", userId, data.iCardValue, self.m_pRoundStatus)
	if not self:isRoundStatusOutCard() then return end
	local pUser = self:onGetUserByUserId(userId)
	if not pUser then return end
	-- 校验是不是当前玩家打牌，打的牌是不是手牌里的
	if not self:onCheckOutCardIsVaild(pUser, data.iCardValue) then
		Log.e(TAG, "ClientUserOutCard E1 userId[%s]", userId, data.iCardValue)
		self:onGetGameTable():onActiveCloseConnect(userId)
		return 
	end
	-- 从手牌中拿出，放入出牌中
	if not self:onMoveOneHandCard(userId, data.iCardValue) then
		Log.e(TAG, "ClientUserOutCard E2 userId[%s]", userId, data.iCardValue)
		self:onGetGameTable():onActiveCloseConnect(pUserId)
		return 
	end
	self:onAddOneOutCard(userId, data.iCardValue)
	self:onBroadcastUserOutCard(userId, data.iCardValue)
end

function GameRound:ClientUserSelectDingQue(data, userId)
	Log.d(TAG, "ClientUserSelectDingQue roundStatus[%s]", self.m_pRoundStatus)
	if not self:isRoundStatusOpSelectDingQue() then
		return
	end
	local pUser = self:onGetUserByUserId(userId)
	if not pUser then return end
	if self:onGetGameRule().onCheckSelectDingQueIsVaild and self:onGetGameRule():onCheckSelectDingQueIsVaild(pUser, data) then
		pUser:onSetDingQue(data.iDingQue)
	end
	-- 是否所有玩家都已经选择完成
	for k, v in pairs(self.m_pGameUsers) do
		if v:onGetDingQue() <= 0 then
			Log.d(TAG, "还有玩家[%s]未选择定缺", v:onGetUserId())
			return
		end
	end
	local name = "ServerBCMahjongDoneDingQue"
	local info = {}
	info.iDingQueDoneTable = {}
	for k, v in pairs(self.m_pGameUsers) do
		local pTemp = {}
		pTemp.iUserId = v:onGetUserId()
		pTemp.iDingQue = v:onGetDingQue()
		table.insert(info.iDingQueDoneTable, pTemp)
	end
	self:onGetGameTable():onBroadcastTableUsers(name, info)
	-- 写入回看数据
	table.insert(self.m_pOneRoundLookbackTable, {
		iName = name,
		iInfo = info,
	})

	self:onDealProcessWork()
end

function GameRound:ClientUserHuanSanZhang(data, userId)
	if not self:isRoundStatusOpHuanSanZhang() then
		return
	end
	local pUser = self:onGetUserByUserId(userId)
	if not pUser then return end
	if self:onGetGameRule().onCheckHuanSanZhangIsVaild and self:onGetGameRule():onCheckHuanSanZhangIsVaild(pUser, data) then
		pUser:onSetHuanCardTable(data.iHuanCardTable)
		-- 先将自己的手牌减少
		for _, kCardValue in pairs(pUser:onGetHuanCardTable()) do
			self:onMoveOneHandCard(pUser:onGetUserId(), kCardValue)
		end
		local name = "ServerUserDoneHuanSanZhang"
		local info = {}
		info.iUserId = pUser:onGetUserId()
		info.iHuanCardTable = {}
		for k, v in pairs(data.iHuanCardTable) do
			table.insert(info.iHuanCardTable, 0)
		end
		self:onGetGameTable():onBroadcastTableUsers(name, info)

		-- 写入回看数据
		info.iHuanCardTable = data.iHuanCardTable
		table.insert(self.m_pOneRoundLookbackTable, {
			iName = name,
			iInfo = info,
		})
	end
	-- 是否所有玩家都已经选择完成
	for _, kUser in pairs(self.m_pGameUsers) do
		if #kUser:onGetHuanCardTable() <= 0 then
			Log.d(TAG, "还有玩家[%s]未选择定缺", kUser:onGetUserId())
			return
		end
	end
	self:onGetGameRule():onDealAllUserHuanSanZhang(self.m_pGameUsers)
	
	self:onDealProcessWork()
end

function GameRound:onDealUserHuanSanZhang(pUser, tUser)
	local name = "ServerBCMahjongDoneHuanSanZhang"
	
	for _, kCardValue in pairs(tUser:onGetHuanCardTable()) do
		self:onAddOneHandCard(pUser:onGetUserId(), kCardValue)
	end

	for _, aUser in pairs(self.m_pGameUsers) do
		local info = {}
		info.iUserId = pUser:onGetUserId()
		info.iHuanCardTable = {}
		info.iHandCards = {}
		for _, kCardValue in pairs(tUser:onGetHuanCardTable()) do
			table.insert(info.iHuanCardTable, pUser == aUser and kCardValue or 0)
		end
		for _, kCardValue in pairs(pUser:onGetHandCardMap()) do
			table.insert(info.iHandCards, pUser == aUser and kCardValue or 0)
		end
		if pUser == aUser then
			-- 写入回看数据
			table.insert(self.m_pOneRoundLookbackTable, {
				iName = name,
				iInfo = info,
			})
		end
		self:onGetGameTable():onSendPackage(aUser:onGetUserId(), name, info)
	end
end

function GameRound:ClientUserBaoTing(pData, pUserId)
	if not self:isRoundStatusOpBaoTing() then return end
	local pUser = self:onGetUserByUserId(pUserId)
	if not pUser then return end
	-- 如果已经报听或者不选择报听
	if pUser:onGetIsBaoTing() ~= 0 then
		return
	end
	pData.iBaoTing = 1 == pData.iBaoTing and 1 or -1
	pUser:onSetIsBaoTing(pData.iBaoTing)
	-- 判断是不是所有人都报听完了
	local name = "ServerBCUserBaoTing"
	local info = {}
	info.iBaoTingTable = {}
	for _, kUser in pairs(self.m_pGameUsers) do
		if kUser:onGetIsBaoTing() == 0 then
			return
		end
		if kUser:onGetIsBaoTing() == 1 then
			table.insert(info.iBaoTingTable, kUser:onGetUserId())
		end
	end
	self:onGetGameTable():onBroadcastTableUsers(name, info)
	-- 写入回看数据
	table.insert(self.m_pOneRoundLookbackTable, {
		iName = name,
		iInfo = info,
	})

	self:onDealProcessWork()
end

function GameRound:ClientUserLangQi(pData, pUserId)
	if not self:isRoundStatusOpLangQi() then return end
	local pUser = self:onGetUserByUserId(pUserId)
	if not pUser then return end
	local name = "ServerBCUserLangQi"
	info.iAllLangQiInfoTable = self.m_pGameRule:onGetLangQiTable(v)
	self.m_pGameTable:onSendPackage(v:onGetUserId(), name, info)
end

function GameRound:onServerUserAutoOutCard(pUserId, pCardValue)
	Log.d(TAG, "onServerUserAutoOutCard pUserId[%s], pCardValue[%s] roundStatus[%s]", pUserId, pCardValue, self.m_pRoundStatus)
	self:stopTimer("timerAutoOutCard")
	if not self:isRoundStatusOpAutoOutCard() then return end
	self:setRoundStatus(roundStatusMap.ROUND_STATUS_OUT_CARD)
	self:ClientUserOutCard({iCardValue = pCardValue}, pUserId)
end

function GameRound:onGetSelectOpInfoTable()
	local pOpInfoTable = {}
	for _, op in pairs(self.m_pUserCurOpTable) do
		if not OperationType:isGuo(op.iOpValue) and op.iStatus == 1 then
			local pUser = self.m_pGameUsers[op.iSeatId]
			local tUser = self.m_pGameUsers[op.iTSeatId]
			local t = {
				iUserId = pUser:onGetUserId(),
				iOpValue = op.iOpValue,
				iTUserId = tUser:onGetUserId(),
				iCardValue = op.iCardValue
			}
			pOpInfoTable[#pOpInfoTable + 1] = t
		end
	end
	self:onClearUserCurOpTable()
	return pOpInfoTable
end

function GameRound:onDealAllUserTakeOp()
	Log.d(TAG, "onDealAllUserTakeOp")
	-- Log.dump(TAG, self.m_pUserCurOpTable, "self.m_pUserCurOpTable")
	-- 判断所有的玩家是不是全部已经操作完成
	for k, v in pairs(self.m_pUserCurOpTable) do
		if v.iStatus <= 0 then 
			return 
		end
	end
	Log.d(TAG, "onDealAllUserTakeOp done")
	-- 找到所有的操作
	local pOpInfoTable = self:onGetSelectOpInfoTable()
	Log.dump(TAG, pOpInfoTable, "pOpInfoTable")
	-- 分不同的情况处理
	-- 如果只有一个玩家操作
	if #pOpInfoTable == 1 then
		for _, op in pairs(pOpInfoTable) do
			-- 设置出牌
			if op.iTUserId and op.iUserId ~= op.iTUserId then
				local tUser = self:onGetUserByUserId(op.iTUserId)
				local pOutCardMap = tUser:onGetOutCardMap()
				if #pOutCardMap > 0 and pOutCardMap[#pOutCardMap].iCardValue == op.iCardValue then
					pOutCardMap[#pOutCardMap].iStatus = 1
				end
			end
			if OperationType:isPeng(op.iOpValue) then
				self:onDealTakeOpPeng(op)
				self:onBroadcastUserTakeOp(pOpInfoTable, true)
				if #self.m_pUserCurOpTable > 0 then
					self:onSortUserCurOpTable()
					self:setRoundStatus(roundStatusMap.ROUND_STATUS_OP_PENG_CARD)
				end
			elseif OperationType:isHasGang(op.iOpValue) then
				self:onDealTakeOpGang(op)
				self:onBroadcastUserTakeOp(pOpInfoTable, false)
				if self.m_pGameRule.onGetDealTableWhenUserGang then
					self.m_pGameRule:onGetDealTableWhenUserGang(self.m_pGameUsers, op, self.m_pUserCurOpTable)
				end

				Log.dump(TAG, self.m_pUserCurOpTable, "self.m_pUserCurOpTable")
				if #self.m_pUserCurOpTable <= 0 then
					self:setRoundStatus(roundStatusMap.ROUND_STATUS_DRAW_CARD)
					local pUser = self:onGetUserByUserId(op.iUserId)
					self:onDealUserMakeGangCard(pUser:onGetUserId())
					-- self:onUserDrawCard(pUser:onGetUserId())
				else
					self:onSortUserCurOpTable()
					self:setRoundStatus(roundStatusMap.ROUND_STATUS_OP_BUGANG_CARD)
				end
			elseif OperationType:isHasHu(op.iOpValue) then
				self.m_pTotalHuCount = self.m_pTotalHuCount + 1
				self:onBroadcastUserTakeOp(pOpInfoTable, false)
				self:onDealTakeOpHu(op)
				if not self.m_pGameRule:isCanXueZhanDaoDi() then
					self:onGameRoundStop(0)
				else
					local pNotHuCount = 0
					-- 判断是不是都已经胡了
					for k, v in pairs(self.m_pGameUsers) do
						if v:onGetIsHu() <= 0 then
							pNotHuCount = pNotHuCount + 1
						end
					end
					if pNotHuCount <= 1 then
						self:onGameRoundStop(0)
						return
					end
					local pUser = self:onGetUserByUserId(op.iUserId)
					self.m_pCurOutCardSeatId = pUser:onGetSeatId()
					self:onUserDrawCard(self:onGetCurDrawCardUser():onGetUserId())
				end
			elseif OperationType:isHasChi(op.iOpValue) then
				self:onDealTakeOpChi(op)
				self:onBroadcastUserTakeOp(pOpInfoTable, true)
				if #self.m_pUserCurOpTable > 0 then
					self:onSortUserCurOpTable()
					self:setRoundStatus(roundStatusMap.ROUND_STATUS_OP_CHI_CARD)
				end
			end
		end
	elseif #pOpInfoTable > 1 then
		local tUser = nil
		local pLastHuId = nil
		-- 处理一炮多响的情况
		for _, op in pairs(pOpInfoTable) do
			if OperationType:isHasHu(op.iOpValue) then
				self.m_pTotalHuCount = self.m_pTotalHuCount + 1
			end
			-- 设置出牌
			if op.iTUserId and op.iUserId ~= op.iTUserId then
				tUser = self:onGetUserByUserId(op.iTUserId)
				local pOutCardMap = tUser:onGetOutCardMap()
				if pOutCardMap[#pOutCardMap].iCardValue == op.iCardValue then
					pOutCardMap[#pOutCardMap].iStatus = 1
				end
			end
			self:onBroadcastUserTakeOp({op}, false)
			if OperationType:isHasHu(op.iOpValue) then
				self:onDealTakeOpHu(op, true)
			end
			local pUser = self:onGetUserByUserId(op.iUserId)
			pLastHuId = op.iUserId
		end
		if not self.m_pGameRule:isCanXueZhanDaoDi() then
			self:onGameRoundStop(0)
		else
			local pNotHuCount = 0
			-- 判断是不是都已经胡了
			for k, v in pairs(self.m_pGameUsers) do
				if v:onGetIsHu() <= 0 then
					pNotHuCount = pNotHuCount + 1
				end
			end
			if pNotHuCount <= 1 then
				self:onGameRoundStop(0)
				return
			end
			-- 设置打牌座位号
			self.m_pCurOutCardSeatId = self:onGetUserByUserId(pLastHuId):onGetSeatId()
			self:onUserDrawCard(self:onGetCurDrawCardUser():onGetUserId())
		end
	else
		-- 如果是自己胡自己，然后选了过，需要判断其他人能不能胡
		if self:isRoundStatusOpOutCardMyself() then
			local tUser = self.m_pGameUsers[self.m_pCurOutCardSeatId]
			local tOutCardMap = tUser:onGetOutCardMap()
			local tCardValue = tOutCardMap[#tOutCardMap] and tOutCardMap[#tOutCardMap].iCardValue or 0
			for k, v in pairs(self.m_pGameUsers) do
				if tUser ~= v and tCardValue > 0 then
					local opTable = self.m_pGameRule:onGetOpTableWhenOutCard(tUser, v, tCardValue, self.m_pGameUsers)
					if #opTable > 0 then
						for _, p in pairs(opTable) do
							local op = {
								iOpValue = p.iOpValue,
								iCardValue = p.iCardValue,
								iSeatId = v:onGetSeatId(),
								iTSeatId = tUser:onGetSeatId(),
								iStatus = 0
							}
							table.insert(self.m_pUserCurOpTable, op)
						end
					end
				end
			end
		end
		self:onBroadcastUserTakeOp(pOpInfoTable, true)
		if self:isRoundStatusOpOutCard() then
			self:setRoundStatus(roundStatusMap.ROUND_STATUS_DRAW_CARD)
			self:onUserDrawCard(self:onGetCurDrawCardUser():onGetUserId())
		elseif self:isRoundStatusOpDrawCard() then
			self:setRoundStatus(roundStatusMap.ROUND_STATUS_OUT_CARD)
			local tUser = self.m_pGameUsers[self.m_pCurOutCardSeatId]
			if tUser and tUser:onGetIsBaoTing() > 0 then
				if self:onGetGameRule().isCanAutoOutCard and self:onGetGameRule():isCanAutoOutCard(tUser) then
					self:setRoundStatus(roundStatusMap.ROUND_STATUS_OP_AUTO_OUT_CARD)
					local pCallBack = self.onServerUserAutoOutCard
					local pHandCardMap = tUser:onGetHandCardMap()
					self:startTimer("timerAutoOutCard", 1200, pCallBack, tUser:onGetUserId(), pHandCardMap[#pHandCardMap])
				end
			end
		elseif self:isRoundStatusOpBuGangCard() then
			self:setRoundStatus(roundStatusMap.ROUND_STATUS_DRAW_CARD)
			local pUserId = self.m_pGameUsers[self.m_pCurOutCardSeatId]:onGetUserId() 
			self:onDealUserMakeGangCard(pUserId)
			if self.m_pGameRule.onGetDealTableWhenUserGang then
				self.m_pGameRule:onGetDealTableWhenUserGang(self.m_pGameUsers, {iUserId = pUserId, iOpValue = OperationType.BU_GANG})
			end
		elseif self:isRoundStatusOpPengCard() or self:isRoundStatusOpChiCard() then
			self:setRoundStatus(roundStatusMap.ROUND_STATUS_OUT_CARD)
		elseif self:isRoundStatusOpLastCard() then
			self:onUserDrawCard(self:onGetCurDrawCardUser():onGetUserId())
		elseif self:isRoundStatusOpOutCardMyself() then
			if #self.m_pUserCurOpTable > 0 then
				self:setRoundStatus(roundStatusMap.ROUND_STATUS_OP_OUT_CARD)
			else
				self:setRoundStatus(roundStatusMap.ROUND_STATUS_DRAW_CARD)
				self:onUserDrawCard(self:onGetCurDrawCardUser():onGetUserId())
			end
		end
	end
	-- 把所有的操作写入回放
	if not self:isRoundStatusOpDrawCard() then
		self:onWriteLookbackAllUserOpTable()
	end
end

function GameRound:onBroadcastUserTakeOp(pOpInfoTable, pTing)
	-- 广播玩家操作
	local name = "ServerBCUserTakeOp"
	local info = {}
	info.iTakeOpInfo = pOpInfoTable
	info.iTotalHuCount = 0
	local pUser = nil
	if #pOpInfoTable > 0 then
		pUser = self:onGetUserByUserId(pOpInfoTable[1].iUserId)
		info.iTotalHuCount = OperationType:isHasHu(pOpInfoTable[1].iOpValue) and self.m_pTotalHuCount or 0
	else
		pUser = self.m_pGameUsers[self.m_pCurOutCardSeatId]
	end
	for k, v in pairs(self.m_pGameUsers) do
		info.iOpTable = {}
		info.iAllCardTingInfoTable = {}
		-- 找到自己当前操作
		for _, op in pairs(self.m_pUserCurOpTable) do
			if op.iSeatId == v:onGetSeatId() and op.iStatus <= 0 then
				table.insert(info.iOpTable, op)
			end
		end
		-- info.iOpHints = #self.m_pUserCurOpTable > 0 and 1 or 0
		-- 计算听牌信息
		if pTing and #info.iOpTable <= 0 and v == pUser then
			info.iAllCardTingInfoTable = self.m_pGameRule:onGetTingCardTable(v)
		end
		info.iTakeOpInfo = pOpInfoTable
		if self.m_pGameRule.onBlockCardMapFilter then
			info.iTakeOpInfo = self.m_pGameRule:onBlockCardMapFilter(pUser, v, pOpInfoTable)
		end
		self.m_pGameTable:onSendPackage(v:onGetUserId(), name, info)
	end
	-- 写入回看数据
	info.iTakeOpInfo = pOpInfoTable
	info.iOpTable = {}
	info.iAllCardTingInfoTable = {}
	table.insert(self.m_pOneRoundLookbackTable, {
		iName = name,
		iInfo = info,
	})
end

function GameRound:onDealTakeOpChi(op)
	local pUser = self:onGetUserByUserId(op.iUserId)
	local tUser = self:onGetUserByUserId(op.iTUserId)
	self.m_pCurOutCardSeatId = pUser:onGetSeatId()
	if OperationType:isRightChi(op.iOpValue) then
		self:onMoveOneHandCard(pUser:onGetUserId(), op.iCardValue - 2)
		self:onMoveOneHandCard(pUser:onGetUserId(), op.iCardValue - 1)
	elseif OperationType:isMidChi(op.iOpValue) then
		self:onMoveOneHandCard(pUser:onGetUserId(), op.iCardValue - 1)
		self:onMoveOneHandCard(pUser:onGetUserId(), op.iCardValue + 1)
	elseif OperationType:isLeftChi(op.iOpValue) then
		self:onMoveOneHandCard(pUser:onGetUserId(), op.iCardValue + 1)
		self:onMoveOneHandCard(pUser:onGetUserId(), op.iCardValue + 2)
	end
	self:onAddOneBlockCard(pUser:onGetUserId(), op.iCardValue, op.iOpValue, op.iTUserId)
	self:setRoundStatus(roundStatusMap.ROUND_STATUS_OUT_CARD)
	local opTable = self.m_pGameRule:onGetOpTableWhenOpCard(pUser, pUser, op, self.m_pGameUsers)
	if #opTable > 0 then
		for _, kOp in pairs(opTable) do
			local op = {
				iOpValue = kOp.iOpValue,
				iCardValue = kOp.iCardValue,
				iSeatId = pUser:onGetSeatId(),
				iTSeatId = tUser:onGetSeatId(),
				iStatus = 0
			}
			table.insert(self.m_pUserCurOpTable, op)
		end
	end
end

function GameRound:onDealTakeOpPeng(op)
	local pUser = self:onGetUserByUserId(op.iUserId)
	local tUser = self:onGetUserByUserId(op.iTUserId)
	self.m_pCurOutCardSeatId = pUser:onGetSeatId()
	self:onMoveOneHandCard(pUser:onGetUserId(), op.iCardValue)
	self:onMoveOneHandCard(pUser:onGetUserId(), op.iCardValue)
	self:onAddOneBlockCard(pUser:onGetUserId(), op.iCardValue, op.iOpValue, op.iTUserId)
	self:setRoundStatus(roundStatusMap.ROUND_STATUS_OUT_CARD)
	local opTable = self.m_pGameRule:onGetOpTableWhenOpCard(pUser, pUser, op, self.m_pGameUsers)	
	if #opTable > 0 then
		for _, kOp in pairs(opTable) do
			local op = {
				iOpValue = kOp.iOpValue,
				iCardValue = kOp.iCardValue,
				iSeatId = pUser:onGetSeatId(),
				iTSeatId = tUser:onGetSeatId(),
				iStatus = 0
			}
			table.insert(self.m_pUserCurOpTable, op)
		end
	end
	-- 如果有能碰能杠，碰后不可杠，则要记录下来
	if self:onGetGameRule().isPengHouBuKeGang and self:onGetGameRule():isPengHouBuKeGang() then
		-- 如果手上还有则以后不可以再杠
		local pIsHasSameCardValue = false
		local pHandCardMap = pUser:onGetHandCardMap()
		for _, kCardValue in pairs(pHandCardMap) do
			if kCardValue == op.iCardValue then
				pIsHasSameCardValue = true
				break
			end
		end
		if pIsHasSameCardValue then
			local pPengCard = {
				iCardValue = op.iCardValue,
				iOpValue = op.iOpValue,
				iUserId = op.iUserId,
			}
			table.insert(self.m_pPengHouBuKeGangTable, pPengCard)
		end
	end
end

function GameRound:onDealTakeOpGang(op)
	local pUser = self:onGetUserByUserId(op.iUserId)
	local tUser = self:onGetUserByUserId(op.iTUserId)
	local pBasePoint = self.m_pGameTable.m_pCommonConfig.iBasePoint

	if self:onGetGameRule().onGetGangTableWhenUserGang then
		local pRet = self:onGetGameRule():onGetGangTableWhenUserGang(pUser, tUser, self.m_pGameUsers, op, pBasePoint)
		if pRet then
			table.insert(self.m_pAllTurnMoneyTable.iGangTurnMoneyTable, pRet)
		end
	end

	local pHandCardMap = pUser:onGetHandCardMap()
	self:setRoundStatus(roundStatusMap.ROUND_STATUS_OUT_CARD)
	if OperationType:isAnGang(op.iOpValue) then
		self:onMoveOneHandCard(pUser:onGetUserId(), op.iCardValue)
		self:onMoveOneHandCard(pUser:onGetUserId(), op.iCardValue)
		self:onMoveOneHandCard(pUser:onGetUserId(), op.iCardValue)
		self:onMoveOneHandCard(pUser:onGetUserId(), op.iCardValue)
		self:onAddOneBlockCard(pUser:onGetUserId(), op.iCardValue, op.iOpValue, op.iTUserId)
		-- self:onUserDrawCard(pUser:onGetUserId())
	elseif OperationType:isBuGang(op.iOpValue) then
		self:onMoveOneHandCard(pUser:onGetUserId(), op.iCardValue)
		self:onAddOneBlockCard(pUser:onGetUserId(), op.iCardValue, op.iOpValue, op.iTUserId)
		-- 判断是否能抢杠胡
		for _, kUser in pairs(self.m_pGameUsers) do
			if kUser ~= pUser then
				local opTable = self.m_pGameRule:onGetOpTableWhenOpCard(pUser, kUser, op, self.m_pGameUsers)	
				if #opTable > 0 then
					for _, kOp in pairs(opTable) do
						local op = {
							iOpValue = kOp.iOpValue,
							iCardValue = kOp.iCardValue,
							iSeatId = kUser:onGetSeatId(),
							iTSeatId = pUser:onGetSeatId(),
							iStatus = 0
						}
						table.insert(self.m_pUserCurOpTable, op)
					end
				end
			end
		end
	elseif OperationType:isGang(op.iOpValue) then
		self:onMoveOneHandCard(pUser:onGetUserId(), op.iCardValue)
		self:onMoveOneHandCard(pUser:onGetUserId(), op.iCardValue)
		self:onMoveOneHandCard(pUser:onGetUserId(), op.iCardValue)
		self:onAddOneBlockCard(pUser:onGetUserId(), op.iCardValue, op.iOpValue, op.iTUserId)
		self.m_pCurOutCardSeatId = pUser:onGetSeatId()
		-- 判断是否能抢杠胡
		for _, kUser in pairs(self.m_pGameUsers) do
			if kUser ~= pUser then
				local opTable = self.m_pGameRule:onGetOpTableWhenOpCard(pUser, kUser, op, self.m_pGameUsers)	
				if #opTable > 0 then
					for _, kOp in pairs(opTable) do
						local op = {
							iOpValue = kOp.iOpValue,
							iCardValue = kOp.iCardValue,
							iSeatId = kUser:onGetSeatId(),
							iTSeatId = pUser:onGetSeatId(),
							iStatus = 0
						}
						table.insert(self.m_pUserCurOpTable, op)
					end
				end
			end
		end
	end
end

function GameRound:onDealUserMakeGangCard(pUserId)
	local pUser = self:onGetUserByUserId(pUserId)
	if not pUser then return end
	-- 这里是如果杠牌只能自己定
	if self:onGetGameRule().onGetMakeGangCard then
		local pIsShuangGangHua, pCardTable, pIsCanChaoDi = self:onGetGameRule():onGetMakeGangCard(pUser)
		if pIsShuangGangHua then
			local name = "ServerUserSelectGangCard"
			local info = {}
			info.iUserId = pUserId
			info.iGangCardTable = pCardTable
			info.iIsCanChaoDi = pIsCanChaoDi and 1 or 0
			self:onGetGameTable():onSendPackage(pUserId, name, info)
			self:setRoundStatus(roundStatusMap.ROUND_STATUS_OP_SELECT_GANG_CARD)
		elseif #pCardTable > 0 then
			local pCardValue = pCardTable[1].iCardValue
			self:onAddOneHandCard(pUserId, pCardValue)
			-- 当前出牌玩家设置
			self.m_pCurOutCardSeatId = pUser:onGetSeatId()
			self:onBroadcastUserDrawCard(pUserId, pCardValue, false)
		else
			self:onUserDrawCard(pUserId, false, true)
		end
	else
		self:onUserDrawCard(pUserId, false, true)
	end
end

function GameRound:isNeedAddOneHandCard(pUser)
	local pHandCardMap = pUser:onGetHandCardMap()
	if #pHandCardMap % 3 ~= 2 then
		return true
	end
	return false
end

function GameRound:onDealTakeOpHu(op, pIsYiPaoDuoXiang)
	Log.dump(TAG, op, "op")
	local pUser = self:onGetUserByUserId(op.iUserId)
	local tUser = self:onGetUserByUserId(op.iTUserId)
	-- 如果是抢杠胡则还要去掉直接补杠的金币流水
	if OperationType:isQiangGangHu(op.iOpValue) then
		for k, kGangTurnMony in pairs(self.m_pAllTurnMoneyTable.iGangTurnMoneyTable) do
			if op.iTUserId == kGangTurnMony.iUserId and OperationType:isBuGang(kGangTurnMony.iOpValue) and op.iCardValue == kGangTurnMony.iCardValue then
				table.remove(self.m_pAllTurnMoneyTable.iGangTurnMoneyTable, k)
				break
			end
		end
		self:onMoveOneBlockCard(op.iTUserId, op.iCardValue, OperationType.BU_GANG)
	end
	local isZiMo = (pUser == tUser)
	if self:isNeedAddOneHandCard(pUser) then
		self:onAddOneHandCard(pUser:onGetUserId(), op.iCardValue)
	end
	pUser:onSetIsHu(self.m_pTotalHuCount)
	local pBasePoint = self.m_pGameTable.m_pCommonConfig.iBasePoint
	local pRet = self.m_pGameRule:onGetHuTableWhenUserHu(pUser, tUser, self.m_pGameUsers, op, pBasePoint, self.m_pGameTable:isFirendBattleRoom(), pIsYiPaoDuoXiang)
	-- 去掉胡牌
	if pRet and pRet.iHuCard and pRet.iHuCard > 0 then
		self:onMoveOneHandCard(pUser:onGetUserId(), pRet.iHuCard)
	end
	table.insert(self.m_pAllTurnMoneyTable.iHuTurnMoneyTable, pRet)
	self.m_pRoundIsHu = true
	-- 如果是杠上炮，则添加到表里
	if pRet.iIsGangShangPao then
		local pLastGangTurnMony = self.m_pAllTurnMoneyTable.iGangTurnMoneyTable[#self.m_pAllTurnMoneyTable.iGangTurnMoneyTable]
		if pLastGangTurnMony and pLastGangTurnMony.iUserId == pRet.iTUserId and pLastGangTurnMony.iGangShangPaoIds then
			table.insert(pLastGangTurnMony.iGangShangPaoIds, pRet.iUserId)
		end
	end
	if pRet.iIsGangShangPao and pRet.iLianGangLianShao then
		-- 先找到自己所有的杠牌，如果是最后的杠牌，则要取消掉
		local tBlockCardMap = tUser:onGetBlockCardMap()
		for i = #tBlockCardMap, 1, -1 do
			local pIndex = #tBlockCardMap - i + 1
			if OperationType:isHasGang(tBlockCardMap[i].iOpValue) and self:onGetTotalOutCard() - tBlockCardMap[i].iRank == pIndex then
				-- 从杠牌流水中删除
				local pLastGangTurnMony = self.m_pAllTurnMoneyTable.iGangTurnMoneyTable[#self.m_pAllTurnMoneyTable.iGangTurnMoneyTable]
				if pLastGangTurnMony and pLastGangTurnMony.iUserId == pRet.iTUserId then 
					table.remove(self.m_pAllTurnMoneyTable.iGangTurnMoneyTable, #self.m_pAllTurnMoneyTable.iGangTurnMoneyTable)
				else
					break
				end
			else
				break
			end
		end
	end
	if pRet.iIsQiangGangHu and pRet.iLianGangLianShao then
		-- 先找到自己所有的杠牌，如果是最后的杠牌，则要取消掉
		local tBlockCardMap = tUser:onGetBlockCardMap()
		for i = #tBlockCardMap - 1, 1, -1 do
			local pIndex = #tBlockCardMap - i
			if OperationType:isHasGang(tBlockCardMap[i].iOpValue) and self:onGetTotalOutCard() - tBlockCardMap[i].iRank == pIndex then
				-- 从杠牌流水中删除
				local pLastGangTurnMony = self.m_pAllTurnMoneyTable.iGangTurnMoneyTable[#self.m_pAllTurnMoneyTable.iGangTurnMoneyTable]
				if pLastGangTurnMony and pLastGangTurnMony.iUserId == pRet.iTUserId then 
					table.remove(self.m_pAllTurnMoneyTable.iGangTurnMoneyTable, #self.m_pAllTurnMoneyTable.iGangTurnMoneyTable)
				else
					break
				end
			else
				break
			end
		end
	end
end

--!
--! @brief      用户进行操作
--!
--! @param      data    The data
--! @param      userId  The user identifier
--!
--! @return     { description_of_the_return_value }
--!
function GameRound:ClientUserTakeOp(data, userId)
	Log.d(TAG, "ClientUserTakeOp userId[%s] roundStatus[%s]", userId, self.m_pRoundStatus)
	if not self:isRoundStatusOpOutCard() and not self:isRoundStatusOpDrawCard() 
		and not self:isRoundStatusOpBuGangCard() and not self:isRoundStatusOpPengCard()
		and not self:isRoundStatusOpChiCard() and not self:isRoundStatusOpLastCard()
		and not self:isRoundStatusOpOutCardMyself() and not self:isRoundStatusOpLaoLastCard() then
		return
	end
	-- Log.dump(TAG, self.m_pUserCurOpTable, "self.m_pUserCurOpTable")
	-- 判断该玩家有没有操作
	local pUser = self:onGetUserByUserId(userId)
	if not pUser then return end
	-- iStatus 状态的意义
	-- nil 为没有状态，还可以进行选择
	-- 1 为我的选择是有效的
	-- 2 为我没选择，被别人或者自己淘汰
	-- 3 为我选择了，但是被别人淘汰
	-- 检测是否有该玩家的操作
	local pHasOpValue, pCurOp = false, nil
	-- 首先查找如果自己已经选择过，则是非法操作
	for i = 1, #self.m_pUserCurOpTable do
		local op = self.m_pUserCurOpTable[i]
		if pUser:onGetSeatId() == op.iSeatId and (op.iStatus == 1 or op.iStatus == 3) then
			return
		end
	end
	-- 查找匹配的操作
	for i = 1, #self.m_pUserCurOpTable do
		local op = self.m_pUserCurOpTable[i]
		if op.iOpValue == data.iOpValue and op.iCardValue == data.iCardValue and pUser:onGetSeatId() == op.iSeatId then
			op.iStatus = op.iStatus == 2 and 3 or 1
			pHasOpValue = true
			pCurOp = op
			break
		end
	end
	if not pHasOpValue then
		return
	end

	for i = #self.m_pUserCurOpTable, 1, -1 do
		local op = self.m_pUserCurOpTable[i]
		if pUser:onGetSeatId() == op.iSeatId and op.iStatus <= 0 then
			op.iStatus = 2
			-- 如果自己可以胡，却选择不胡，则要问rule是不是要设置过胡状态
			if OperationType:isHasHu(op.iOpValue) then
				local pGuoHuInfo = {}
				pGuoHuInfo.iStatus = true
				pGuoHuInfo.iHuInfo = pUser:onGetHuInfo()
				onPerformSelector(self:onGetGameRule(), self:onGetGameRule().onUserHasGuoHu, pUser, pGuoHuInfo)
				-- self:onGetGameRule():onUserHasGuoHu(pUser)
			end
		end
	end
	
	if not OperationType:isGuo(data.iOpValue) then
		for i = #self.m_pUserCurOpTable, 1, -1 do
			local op = self.m_pUserCurOpTable[i]
			-- 前面的优先级都比它大
			if op.iOpValue == data.iOpValue and op.iCardValue == data.iCardValue and pUser:onGetSeatId() == op.iSeatId then
				break
			end
			if OperationType:isHasHu(data.iOpValue) then
				if not OperationType:isHasHu(op.iOpValue) then
					op.iStatus = op.iStatus == 1 and 3 or 2
				else
					if not self.m_pGameRule:isCanYiPaoDuoXiang() then
						op.iStatus = op.iStatus == 1 and 3 or 2
					end
				end
			else
				op.iStatus = op.iStatus == 1 and 3 or 2
			end
		end
	end

	-- if OperationType:isGuo(data.iOpValue) then
	-- 	-- 将过的操作写入回看
	-- 	self:onDealUserTakeGuoOp(pCurOp)
	-- end
	-- 把玩家的操作写入回放
	self:onWriteLookbackUserTakeOp(pCurOp)
	-- 检测是否所有人都操作完成
	self:onDealAllUserTakeOp()
	Log.dump(TAG, self.m_pUserCurOpTable, "self.m_pUserCurOpTable")
end

function GameRound:onDealUserTakeGuoOp(pOp)
	local pOpInfoTable = {}
	local pUser = self.m_pGameUsers[pOp.iSeatId]
	local tUser = self.m_pGameUsers[pOp.iTSeatId]
	local t = {
		iUserId = pUser:onGetUserId(),
		iOpValue = pOp.iOpValue,
		iTUserId = tUser:onGetUserId(),
		iCardValue = pOp.iCardValue
	}
	pOpInfoTable[#pOpInfoTable + 1] = t

	local name = "ServerBCUserTakeOp"
	local info = {}
	info.iTakeOpInfo = pOpInfoTable
	info.iTotalHuCount = 0
	info.iCanLangQi = 0
	info.iOpTable = {}
	info.iAllCardTingInfoTable = {}
	-- 写入回看数据
	table.insert(self.m_pOneRoundLookbackTable, {
		iName = name,
		iInfo = info,
	})
end

function GameRound:ClientUserSelectGangCard(data, userId)
	local pUser = self:onGetUserByUserId(userId)
	if not pUser then return end
	local pCardValue = data.iCardValue
	if not self:isRoundStatusOpSelectGangCard() then
		return
	end
	-- 判断是不是该玩家操作选杠牌，选牌是否有效
	if not self:onGetGameRule().onCheckSelectGangCardIsVaild then
		return
	end
	if not self:onGetGameRule():onCheckSelectGangCardIsVaild(pUser, data) then
		return
	end
	if data.iChaoDi and data.iChaoDi > 0 then
		self:onUserDrawCard(userId, false, true)
	else
		if self:onGetGameRule().onDelAndAddOneGangCard then
			self:onGetGameRule():onDelAndAddOneGangCard(pCardValue)
			self:onProcessMakeGangCard(true)
		end
		-- 选牌成功则发牌
		self:onAddOneHandCard(userId, pCardValue)
		self:onSetBlockMakeGangCard(userId, pCardValue)
		-- 当前出牌玩家设置
		self.m_pCurOutCardSeatId = pUser:onGetSeatId()
		self:onBroadcastUserDrawCard(userId, pCardValue, false)
	end
end

function GameRound:onGetRemainCardNum(pUserId, pCardValue)
	local pRemain = 4
	for k, v in pairs(self.m_pGameUsers) do
		-- 先减掉出牌
		local pOutCardMap = v:onGetOutCardMap()
		for _, card in pairs(pOutCardMap) do
			if card.iCardValue == pCardValue and card.iStatus == 0 then
				pRemain = pRemain - 1
			end
		end
		-- Log.d(TAG, "pUserId[%s] pRemain[%s]", v:onGetUserId(), pRemain)
		-- 操作牌
		local pBlockCardMap = v:onGetBlockCardMap()
		for _, card in pairs(pBlockCardMap) do
			if card.iCardValue == pCardValue then
				if OperationType:isPeng(card.iOpValue) then
					pRemain = pRemain - 3
				end
				if OperationType:isHasGang(card.iOpValue) then
					pRemain = pRemain - 4
				end
			end
		end
		-- Log.d(TAG, "pUserId[%s] pRemain[%s]", v:onGetUserId(), pRemain)
		-- 去掉自己的手牌
		if v:onGetUserId() == pUserId then
			local pHandCardMap = v:onGetHandCardMap()
			for _, card in pairs(pHandCardMap) do
				if card == pCardValue then
					pRemain = pRemain - 1
				end
			end
		end
		-- Log.d(TAG, "pUserId[%s] pRemain[%s]", v:onGetUserId(), pRemain)
	end
	return pRemain
end

-- 获取需要打牌的玩家
function GameRound:onGetDrawCardUserId()
	if self:isRoundStatusNone() then
		return 0
	end
	if self:isRoundStatusOpLastCard() then
		if #self.m_pUserCurOpTable > 0 and self.m_pGameUsers[self.m_pUserCurOpTable[1].iSeatId] then
			return self.m_pGameUsers[self.m_pUserCurOpTable[1].iSeatId]:onGetUserId()
		end
	end
	for k, v in pairs(self.m_pGameUsers) do
		local pHandCardMap = v:onGetHandCardMap()
		if #pHandCardMap % 3 == 2 then
			return v:onGetUserId()
		end
	end
	return 0 
end

function GameRound:onGetOutCardUserId()
	if self:onGetDrawCardUserId() > 0 then
		return 0
	end
	if #self.m_pUserCurOpTable > 0 and self:isRoundStatusOpOutCard() then
		if self.m_pUserCurOpTable[1].iSeatId ~= self.m_pUserCurOpTable[1].iTSeatId then
			if self.m_pGameUsers[self.m_pUserCurOpTable[1].iTSeatId] then
				return self.m_pGameUsers[self.m_pUserCurOpTable[1].iTSeatId]:onGetUserId()
			end
		end
	end
	return 0
end

function GameRound:onUserReconnect(pUser)
	self:onReconnetMakeGangCardTable(pUser)
	self:onReconnetSelectGangCardTable(pUser)
	-- 如果在定缺阶段
	if self:isRoundStatusOpSelectDingQue() then
		self:onProcessDingQue(pUser:onGetUserId())
	end
	-- 如果是在换三张阶段
	if self:isRoundStatusOpHuanSanZhang() then
		-- 如果自己没有还没有选择，广播一次开始选择
		if #pUser:onGetHuanCardTable() <= 0 then
			self:onProcessHuanSanZhang(pUser:onGetUserId())
		end
	end
	-- 如果是选择报听阶段
	if self:isRoundStatusOpBaoTing() then
		self:onProcessBaoTing(pUser:onGetUserId())
	end
	-- 如果是在选择买点阶段
	if self:isRoundStatusOpSelectMaiDian() then
		self:onProcessMaiDian(pUser:onGetUserId())
	end
	if self:isRoundStatusOpLaoLastCard() then
		self:onGameLaoLastCard(pUser:onGetUserId(), true)
	end
end

function GameRound:onGetUserExtendInfo(pUser, pReUser)
	if self:onGetGameRule().onGetUserExtendInfo then
		return self:onGetGameRule():onGetUserExtendInfo(pUser, pReUser)
	else
		return {}
	end
end

function GameRound:onGetGameRuleByGameCode()
	local pLocalGameType = self:onGetGameTable():onGetLocalGameType()
	local pRulePath = self:onGetGameTable().m_pPlaytypeConfig.iGameRulePath[pLocalGameType]
	return require(pRulePath)
end

function GameRound:onGetTableId()
	return self:onGetGameTable():onGetCommonConfig().iTableId
end

function GameRound:onGetGameCode()
	return self:onGetGameTable():onGetCommonConfig().iGameCode
end

function GameRound:onGetCommonConfig()
	return self:onGetGameTable():onGetCommonConfig()
end

GameRound.RoundProcessMap = {
	-- 定庄
	[1] = {
		iName = "makeBanker",
		iFunc = GameRound.onProcessMakeBanker,
		iTime = pHasTimeDelay and 2000 or 500,
	},
	-- 发牌
	[2] = {
		iName = "dealCards",
		iFunc = GameRound.onProcessDealCards,
		iTime = pHasTimeDelay and 4000 or 1000,
	},
	-- 扳倒胡选择屁股的杠牌
	[3] = {
		iName = "makeGangCard",
		iFunc = GameRound.onProcessMakeGangCard,
		iTime = 0,
	},
	-- 换3张
	[4] = {
		iName = "huanSanZhang",
		iFunc = GameRound.onProcessHuanSanZhang,
		iTime = 0,
		iNeedConfrim = true,
	},
	-- 定缺
	[5] = {
		iName = "dingQue",
		iFunc = GameRound.onProcessDingQue,
		iTime = 0,
		iNeedConfrim = true,
	},
	-- 报听
	[6] = {
		iName = "baoTing",
		iFunc = GameRound.onProcessBaoTing,
		iTime = 0,
		iNeedConfrim = true,
	},
	-- 买点
	[7] = {
		iName = "maiDian",
		iFunc = GameRound.onProcessMaiDian,
		iTime = 0,
		iNeedConfrim = true,
	},
	--鬼牌
	[8] = {
		iName = "makeGuiCard",
		iFunc = GameRound.onProcessMakeGuiCard,
		iTime = 0,
	},
	--花牌
	[9] = {
		iName = "buHua",
		iFunc = GameRound.onProcessBuHua,
		iTime = 0,
		iNeedConfrim = true,
	},
}

return GameRound
