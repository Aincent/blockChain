local TAG = "gameRuleJSNJJYZ"
local OperationType = require("logic/game/mahjong/operationType")
local GameCore = require("gamecore")

local gameRuleJSNJJYZ = {}

function gameRuleJSNJJYZ:init(pGameRound)
	self.m_pGameRound = pGameRound
	self.m_pLocalGameType = self.m_pGameRound:onGetGameTable():onGetLocalGameType()
	self.m_pPlaytype = self.m_pGameRound:onGetGameTable():onGetPlayType()
	self.m_pPlaytypeConfig = self.m_pGameRound:onGetGameTable().m_pPlaytypeConfig
	-- Log.d(TAG, "self.m_pLocalGameType[%s]", self.m_pLocalGameType)
	self.m_pBaoTingUserIdTable = {}
	self.m_pJiaPaiTable = {}
	-- 封顶番数，默认为2番
	self.m_pFengDing = self.m_pGameRound:onGetGameTable().m_pFriendBattleConfig.iExtendTable.iFengDing or 3
end

function gameRuleJSNJJYZ:onGetGameName()
	local pBigType = string.format("0x%04x", self.m_pLocalGameType & 0xFF00)
	local pSmallType = string.format("0x%02x", self.m_pLocalGameType & 0x00FF)
	if self.m_pPlaytypeConfig.iLocalGameTypeMap then
		return self.m_pPlaytypeConfig.iLocalGameTypeMap[pBigType][pSmallType].iName
	end
	return ""
end

function gameRuleJSNJJYZ:onGetPaytypeStr(pConfTale)
	if pConfTale.iPayType == DefineType.ROOMCARD_PAYTYPE_OWNER then
		return "房主支付"
	elseif pConfTale.iPayType == DefineType.ROOMCARD_PAYTYPE_WINNER then
		return "大赢家支付"
	elseif pConfTale.iPayType == DefineType.ROOMCARD_PAYTYPE_SHARE then
		return "AA支付"
	end
	return "房主支付"
end

function gameRuleJSNJJYZ:onGetGameRoundInfo()
	local pGameRoundInfoTable = {}
	if self.m_pGameRound.m_pPreRoundInfo.iBiXiaHu then
		pGameRoundInfoTable.iBiXiaHu = 1
	end
	return pGameRoundInfoTable
end

function gameRuleJSNJJYZ:onGameFristRoundStart(pGameUsers)
	self.m_pUserExtendTable = {}
	for k, v in pairs(pGameUsers) do
		self.m_pUserExtendTable[v:onGetUserId()] = {
			iZiMoCount = 0,
			iJiePaoCount = 0,
			iFangPaoCount = 0,
			iGangCount = 0,
			iWaiBao = 0,
			iMaxFan = 0,
		}
		-- v:onSetMoney(self:onGetGameUpperLimit())
	end
end

function gameRuleJSNJJYZ:onGetPlaytypeStr(pConfTale, pUserCount)
	self.m_pExtendTable = pConfTale.iExtendTable
	-- 添加局数，封顶
	if self:isPlaytypeQuanShu(self.m_pPlaytype) then
		pConfTale.iBattleTotalRound = pConfTale.iBattleTotalRound * 4  --一圈4把
	end

	local pPlaytypeStr = string.format("%s，%s局", self:onGetGameName(), pConfTale.iBattleTotalRound)
	pPlaytypeStr = string.format("%s，%d人", pPlaytypeStr, pUserCount)
	for k, v in pairs(self:onGetLocalGamePlaytypeTable()) do
		if v.iValue == (self.m_pPlaytype & v.iValue) then
			pPlaytypeStr = string.format("%s，%s", pPlaytypeStr, v.iName)
		end
	end
	-- 显示封顶番数
	local pFengDingStr = ""
	if self.m_pFengDing > 0 then
		pFengDingStr = string.format("%d番封顶", self.m_pFengDing)
	else
		pFengDingStr = "不封顶"
	end
	pPlaytypeStr = string.format("%s，%s", pPlaytypeStr, pFengDingStr)
	if self:isGameSettingEmoji() then
		pPlaytypeStr = string.format("%s，屏蔽互动表情", pPlaytypeStr)
	end
	return pPlaytypeStr
end

function gameRuleJSNJJYZ:onGetUserExtendTable(pUser)
	if self.m_pUserExtendTable and self.m_pUserExtendTable[pUser:onGetUserId()] then
		return self.m_pUserExtendTable[pUser:onGetUserId()]
	end
end

function gameRuleJSNJJYZ:onGetUserExtendInfo(pUser, pReUser)
	local pGameUserInfo = {}
	pGameUserInfo.iHuaPai = {}
	for k,v in pairs(self.m_pGameRound.m_pUserBuHuaTable[pUser:onGetUserId()] or {}) do
		table.insert(pGameUserInfo.iHuaPai, v)
	end
	
	if pUser:onGetIsBaoTing() > 0 then
		pGameUserInfo.iBaoTing = 1
	end
	if self.m_pJiaPaiTable[pUser:onGetUserId()] and self.m_pJiaPaiTable[pUser:onGetUserId()].iJiaPai then
		pGameUserInfo.iJiaPai = self.m_pJiaPaiTable[pUser:onGetUserId()].iJiaPai
	end
	
	return pGameUserInfo
end

--!
--! @brief      当一局游戏开始前调用
--!
--! @param      pGameRound  The game round
--!
--! @return     { description_of_the_return_value }
--!
function gameRuleJSNJJYZ:onGameRoundStart(pGameRound)
	self.m_pGameRound = pGameRound
	self.m_pIsCanZhengChan = false
	self.m_pIsBiXiaHu = false
	self.m_pBaoTingUserIdTable = {}
	self.m_pJiaPaiTable = {}
end

function gameRuleJSNJJYZ:onGetMahjongPool(pUserCount)
	-- 将所有的牌都放一张存起来，用来计算听牌
	self.m_pMahjongOneCardTable = {}

	local poolTable = {}
	for i = 1, 3 do
		for j = 1, 9 do
			local pCardValue = i * 10 + j
			poolTable[#poolTable + 1] = pCardValue
			poolTable[#poolTable + 1] = pCardValue
			poolTable[#poolTable + 1] = pCardValue
			poolTable[#poolTable + 1] = pCardValue

			self.m_pMahjongOneCardTable[#self.m_pMahjongOneCardTable + 1] = pCardValue
		end
	end

	for i = 4, 5 do
		local len = (i == 4) and 4 or 3
		for j = 1, len do
			local pCardValue = i * 10 + j
			poolTable[#poolTable + 1] = pCardValue
			poolTable[#poolTable + 1] = pCardValue
			poolTable[#poolTable + 1] = pCardValue
			poolTable[#poolTable + 1] = pCardValue

			self.m_pMahjongOneCardTable[#self.m_pMahjongOneCardTable + 1] = pCardValue
		end
	end

	local i = 6
	for j=1, 8 do
		local pCardValue = i * 10 + j
		poolTable[#poolTable + 1] = pCardValue
		self.m_pMahjongOneCardTable[#self.m_pMahjongOneCardTable + 1] = pCardValue	
	end
	
	return poolTable
end

function gameRuleJSNJJYZ:onGetBankerSeatId(pUserCount)
	-- Log.dump(TAG, self.m_pGameRound.m_pPreRoundInfo, "self.m_pGameRound.m_pPreRoundInfo")
	local pIsBiXiaHu = self.m_pGameRound.m_pPreRoundInfo.iBiXiaHu 
	if self.m_pGameRound.m_pPreRoundInfo.iBankerSeatId and self.m_pGameRound.m_pPreRoundInfo.iBankerSeatId > 0 then
		local pBankerSeatId = self.m_pGameRound.m_pPreRoundInfo.iBankerSeatId
		self.m_pGameRound.m_pPreRoundInfo = {}
		self.m_pGameRound.m_pPreRoundInfo.iBiXiaHu = pIsBiXiaHu
		
		return pBankerSeatId, {}
	end
	
	self.m_pGameRound.m_pPreRoundInfo = {}
	self.m_pGameRound.m_pPreRoundInfo.iBiXiaHu = pIsBiXiaHu

	return 1, {} -- 坐在东的位置开始坐庄
end

function gameRuleJSNJJYZ:onGetProcessTable()
	return {1, 2, 6, 9}
end

function gameRuleJSNJJYZ:isCanXueZhanDaoDi() 
	return false
end

function gameRuleJSNJJYZ:isCanYiPaoDuoXiang()
	return true
end

function gameRuleJSNJJYZ:isAutoReady()
	return true
end

function gameRuleJSNJJYZ:isOldUserReconnenct()
	return false
end

function gameRuleJSNJJYZ:onCheckOutCardIsVaild(pUser, cardValue)
	local pCardType, _ = self:onGetCardTypeAndValue(cardValue)
	if pCardType > 4 then
		return false
	end

	return true
end

function gameRuleJSNJJYZ:isCanAutoOutCard(pUser)
	return true
end

function gameRuleJSNJJYZ:onBlockCardMapFilter(pUser, tUser, pBlockCardMap)
	for k, v in pairs(pBlockCardMap) do
		if OperationType:isBuGang(v.iOpValue) and v.iUserId == v.iTUserId then
			local pTempBlockCardMap = pUser:onGetBlockCardMap()
			for kTemp, vTemp in pairs(pTempBlockCardMap) do
				if OperationType:isBuGang(vTemp.iOpValue) and vTemp.iCardValue == v.iCardValue then
					v.iTUserId = vTemp.iTUserId
					break
				end
			end
		end
	end

	return pBlockCardMap	
end

function gameRuleJSNJJYZ:onGetNeedRoomCardCount(pPlaytypeConfig, pTotolRound, pMaxUserCount, pPayType)
	if not self.m_pPlaytypeConfig or not pTotolRound then
		return 0 
	end
	local pBigType = string.format("0x%04x", self.m_pLocalGameType & 0xFF00)
	local pSmallType = string.format("0x%02x", self.m_pLocalGameType & 0x00FF)
	local pPlayType = "0x01"
	if self:isPlaytypeQuanShu(self.m_pPlaytype) then
		pPlayType = "0x02"
	end

	if self.m_pPlaytypeConfig.iGameCircleRoomCardTable then
		for k, v in pairs(self.m_pPlaytypeConfig.iGameCircleRoomCardTable[pBigType][pSmallType][pPlayType] or {}) do
			if tonumber(k) == pTotolRound then
				return v.iValue
			end
		end
	end
	return 0
end

function gameRuleJSNJJYZ:onGetUserInitMoney()
	self.m_pLimitMoney = self.m_pExtendTable.iLimit
	local pBigType = string.format("0x%04x", self.m_pLocalGameType & 0xFF00)
	local pSmallType = string.format("0x%02x", self.m_pLocalGameType & 0x00FF)
	local pLimitTable = self.m_pPlaytypeConfig.iGameUpperLimitTable[pBigType][pSmallType] or {}	
	assert(pLimitTable)

	if self.m_pLimitMoney > pLimitTable.iMaxValue then
		self.m_pLimitMoney =  pLimitTable.iMaxValue
	end

	if self.m_pLimitMoney < pLimitTable.iMinValue then
		self.m_pLimitMoney =  pLimitTable.iMinValue
	end

	return self.m_pLimitMoney
end


function gameRuleJSNJJYZ:isRealCanPeng(pUser, pGameUsers, pCardValue)
	if pUser:onGetIsBaoTing() > 0 then return end

	local pOutCardMap = pUser:onGetOutCardMap()
	local pOutCard = pOutCardMap[#pOutCardMap]

	local pRank = pOutCard and pOutCard.iRank or 0

	local pCardCount = 0
	-- 找到所有需要判断的牌
	for _, kUser in pairs(pGameUsers) do
		local pOutCardMap = kUser:onGetOutCardMap()
		for _, kCard in pairs(pOutCardMap) do
			if kCard.iRank > pRank then
				if kCard.iCardValue == pCardValue then
					pCardCount = pCardCount + 1
				end
			end
		end
	end
	
	if pCardCount >= 2 then return false end       --碰牌不碰在轮到自己前不能再碰
	return true
end

function gameRuleJSNJJYZ:isCanBaoTing(pUser)
	--如果是庄家则没有听牌
	if pUser:onGetSeatId() == self.m_pGameRound.m_pBankerSeatId then
		return false
	end
	-- 如果是14张牌，则直接找听牌
	local pHandCardMap = pUser:onGetHandCardMap()
	local pBlockCardMap = pUser:onGetBlockCardMap()
	if #pHandCardMap == 14 then
		local pAllCardTingInfoTable = self:onGetTingCardTable(pUser)
		if #pAllCardTingInfoTable > 0 then
			table.insert(self.m_pBaoTingUserIdTable, pUser:onGetUserId())
			return true
		end
	else
		local pOneCardTingInfoTable = self:onGetOneTingCardTable(pUser, pHandCardMap, pBlockCardMap)
		if #pOneCardTingInfoTable > 0 then
			table.insert(self.m_pBaoTingUserIdTable, pUser:onGetUserId())
			return true
		end
	end
	return false
end

function gameRuleJSNJJYZ:onUserHasGuoHu(pUser, pGuoHuInfo)
	Log.d(TAG, "设置成过胡不胡UserId为【%s】", pUser:onGetUserId())
	pUser:onSetIsGuoHuInfo(pGuoHuInfo)
end

function gameRuleJSNJJYZ:onUserClearGuoHu(pUser, pStatus)
	if DefineType.CLEAR_WHEN_DRAWCARD == pStatus then
		Log.d(TAG, "清理成过胡不胡UserId为【%s】", pUser:onGetUserId())
		pUser:onSetIsGuoHuInfo()
	end
end

function gameRuleJSNJJYZ:isRealCanHu(pUser, pHandCardCountTwoMap)
	local pGuoHuInfo = pUser:onGetIsGuoHuInfo()
	if pGuoHuInfo.iStatus then return false end
	if pUser:onGetMoney() <= 0 then return false end

	local pBlockCardMap = pUser:onGetBlockCardMap()
	local pUserId = pUser:onGetUserId()

	Log.d(TAG, "onGetHuTypeInfo...................pUserId = %s isMenQing = %s,  isFourHardHua = %s ", pUserId, self:isMenQing(pHandCardCountTwoMap, pBlockCardMap) , self:isFourHardHua(pUserId))
	if self:isMenQing(pHandCardCountTwoMap, pBlockCardMap) or self:isFourHardHua(pUserId) then
		return true
	end

	local pAddToFanTable = self:onDealAddToFanWhenPingHu(pHandCardCountTwoMap, pBlockCardMap) -- 必须要有4个硬花以上 胡对对胡，全球，混一色，清一色 除外
	
	Log.dump(TAG, pAddToFanTable, "isRealCanHu ...... pAddToFanTable")
	if pAddToFanTable.iFan > 0 then
		return true
	end

	return false
end

function gameRuleJSNJJYZ:onPrintHandCardCountTwoMap(pHandCardCountTwoMap)
	local pHandCardMap = {}
	for i = 1, 5 do
		for j = 1, 9 do
			for k = 1, pHandCardCountTwoMap[i][j] do
				pHandCardMap[#pHandCardMap + 1] = i * 10 + j
			end
		end
	end
	table.sort(pHandCardMap)
	Log.dump(TAG, pHandCardMap, "pHandCardMap")
end

function gameRuleJSNJJYZ:onGetHuTypeInfo(pGetType, pUser, pHandCardCountTwoMap, pCardValue)
	local pBlockCardMap = pUser:onGetBlockCardMap()
	local pUserId = pUser:onGetUserId()

	local pHuInfo = nil
	local pIsDraw = (0 == pGetType) or (2 == pGetType)
	if self:isXiaoQiDui(pHandCardCountTwoMap, pBlockCardMap) then
		local pQiDuiHuInfo = {}
		pQiDuiHuInfo.iFan = 0
		pQiDuiHuInfo.iName = ""
		local pAddToFanTable = self:onDealAddToFanWhenQiXiaoDui(pHandCardCountTwoMap, pBlockCardMap, pIsDraw)
		pQiDuiHuInfo.iFan = pQiDuiHuInfo.iFan + pAddToFanTable.iFan
		pQiDuiHuInfo.iName = string.format("%s %s", pQiDuiHuInfo.iName, pAddToFanTable.iName)
		pQiDuiHuInfo.iBiXiaHu = true

		pHuInfo = pQiDuiHuInfo
	end
	if self:isNormalHu(pHandCardCountTwoMap, false) then 
		local pPingHuInfo = {} 
		pPingHuInfo.iFan = 0
		pPingHuInfo.iName = ""
		local pAddToFanTable = self:onDealAddToFanWhenPingHu(pHandCardCountTwoMap, pBlockCardMap, pIsDraw)
		pPingHuInfo.iFan = pPingHuInfo.iFan + pAddToFanTable.iFan
		
		if #pAddToFanTable.iName > 0 then 
			pPingHuInfo.iName = string.format("%s %s", pPingHuInfo.iName, pAddToFanTable.iName)
		end

		if pAddToFanTable.iFan > 0 then
			pPingHuInfo.iBiXiaHu = true
		end
 
		Log.dump(TAG, pAddToFanTable, "pAddToFanTable")
		Log.dump(TAG, pPingHuInfo, "pPingHuInfo")
	
		
		Log.d(TAG, "onGetHuTypeInfo............... pHuInfo = %s , #pPingHuInfo.iName = %s ", not pHuInfo, #pPingHuInfo.iName)
		if not pHuInfo then
			pHuInfo = pPingHuInfo
		end
	end

	if pHuInfo then
		if self:isWuHuaGuo(pUserId) then
			pHuInfo.iFan =  pHuInfo.iFan + 30
			pHuInfo.iName = string.format("%s %s", pHuInfo.iName, "无花果")
			pHuInfo.iBiXiaHu = true
		end

		if self:isMenQing(pHandCardCountTwoMap, pBlockCardMap) then
			pHuInfo.iFan =  pHuInfo.iFan + 10
			pHuInfo.iName = string.format("%s %s", pHuInfo.iName, "门清")
		end

		if #pHuInfo.iName <= 0 then 
			pHuInfo.iName = string.format("%s %s", pHuInfo.iName, "小胡")
		end
	end
	
	return pHuInfo
end

--[[
首张按顺序出东南西北或北西南东，每家付5花
]]
function gameRuleJSNJJYZ:isDongNanXiBeiFaKuan(pBlockCardMap, pOutCardMap)
	if #pOutCardMap ~= 4 then return false end
	local pIsFaKuan = true
	for i=1, 4 do -- 东南西北
		if pOutCardMap[i].iCardValue ~= 4*10 + i then
			pIsFaKuan = false
			break
		end
	end

	if not pIsFaKuan then
		pIsFaKuan = true
		local iIndex = 1
		for i=4, 1, -1 do -- 北西南东
			if pOutCardMap[i].iCardValue ~= 4*10 + iIndex then
				pIsFaKuan = false
				break
			end

			iIndex = iIndex + 1 
		end
	end

	return pIsFaKuan
end

function gameRuleJSNJJYZ:isDoubleDongNanXiBei(pBlockCardMap, pOutCardMap)
	if #pOutCardMap ~= 8 then return false end
	local pIsZhengChan = true
	for i=1, 8 do -- 东南西北 东南西北
		local j = i < 5 and i or (i - 4)
		if pOutCardMap[i].iCardValue ~= 4*10 + j then
			pIsZhengChan = false
			break
		end
	end

	if not pIsZhengChan then
		pIsZhengChan = true
		 local j = 1
		for i=8, 1, -1 do -- 北西南东 北西南东
			if pOutCardMap[i].iCardValue ~= 4*10 + j then
				pIsZhengChan = false
				break
			end
			j = j + 1
			if j > 4 then j = 1 end
		end
	end

	return pIsZhengChan
end

--[[
	四人连续出同样的牌，第一个出牌的付每人5花
]]
function gameRuleJSNJJYZ:isFourOutSameCard(pBlockCardMap, pUser)
	local pOutCardMap =  pUser:onGetOutCardMap()
 	local pCardValue = pOutCardMap[#pOutCardMap].iCardValue
 	local pTotalOutCard = pOutCardMap[#pOutCardMap].iRank
 	local pPerSeatId =  (pUser:onGetSeatId() - 1 ) > 0 and (pUser:onGetSeatId() - 1 ) or self.m_pGameRound:onGetGameTable():onGetGameTableMaxUserCount()
 	while (pPerSeatId ~= pUser:onGetSeatId()) do
 		local pTempUser = self.m_pGameRound.m_pGameUsers[pPerSeatId]
 		local pTempOutCardMap = pTempUser:onGetOutCardMap()
 		if #pTempOutCardMap == 0 then return false end

 		local pTempCardValue = pTempOutCardMap[#pTempOutCardMap].iCardValue
 		local pTempTotalOutCard = pTempOutCardMap[#pTempOutCardMap].iRank
 		if pCardValue ~= pTempCardValue or pTotalOutCard ~= (pTempTotalOutCard + 1) then
 			return false
 		end

 		pTotalOutCard = pTempTotalOutCard
		pPerSeatId =  (pPerSeatId - 1 ) > 0 and (pPerSeatId - 1 ) or self.m_pGameRound:onGetGameTable():onGetGameTableMaxUserCount()
 	end
 	return true
end


function gameRuleJSNJJYZ:isCanHuaGang(pUser)
	local pBuHuaTable = self.m_pGameRound.m_pUserBuHuaTable[pUser:onGetUserId()]
	if #pBuHuaTable < 4 then return false end
	local pCardValue = pBuHuaTable[#pBuHuaTable]
	local pType, pValue = self:onGetCardTypeAndValue(pCardValue)
	if pType > 4 then -- 如果抓到花牌必须补牌
		local pCardCount = 0
		if pType == 5 then
			for k, v in ipairs(pBuHuaTable) do
				if v == pCardValue then
					pCardCount = pCardCount + 1
				end
			end
		else
			local pBeginValue = pValue < 5 and 1 or 5 -- 春夏秋冬 梅兰竹菊
			local pEndValue = pBeginValue + 3
			for i = pBeginValue, pEndValue do
				for k, v in ipairs(pBuHuaTable) do
					if v == (pType * 10 + i) then
						pCardCount = pCardCount + 1
					end
				end
			end
		end

		if pCardCount == 4 then
			--TODO: 罚款 花杠：另外三家每家付10花
			Log.d(TAG, "onGameCurrentSettlement 罚款 花杠 春夏秋冬 梅兰竹菊 10 ")
			self:onGameCurrentSettlement(pUser, nil, self.m_pGameRound.m_pGameUsers, 10)
		end
	end
end

--[[
	一个人出四张同样的牌（不需要连续）付每人5花
]]
function gameRuleJSNJJYZ:isOutFourSameCard(pBlockCardMap, pOutCardMap)
	if #pOutCardMap == 0 then return false end
 
 	local pCardValue = pOutCardMap[#pOutCardMap].iCardValue
 	local pOutSameCardCount = 0

 	for k, v in pairs(pOutCardMap) do
 		if v.iCardValue == pCardValue then
 			pOutSameCardCount = pOutSameCardCount + 1
 		end
 	end

 	return pOutSameCardCount == 4
end
 
--[[
	十六幺:连续打出19和风牌是十六张就行
]]
function gameRuleJSNJJYZ:isShiLiuYao(pBlockCardMap, pOutCardMap)
	local pOutCount = 0
	for k, v in pairs(pOutCardMap) do
		local kType, kValue = self:onGetCardTypeAndValue(v.iCardValue)
		if kValue == 1 or kValue == 9 or kType  == 4 then
			pOutCount = pOutCount + 1
		else
			pOutCount = 0
		end

		if pOutCount > 15 then return true end
	end

	return false
end

function gameRuleJSNJJYZ:isShiXiZhang(pUserId)
 	return #self.m_pGameRound.m_pUserBuHuaTable[pUserId] >= 14
end 

--[[
	返回值为table{
		{iOpValue = 1, iCardValue = 1,}，
		...
	}
]]
function gameRuleJSNJJYZ:onGetOpTableWhenDrawCard(pUser, pCardValue)
	local pHandCardMap = pUser:onGetHandCardMap()
	local pBlockCardMap = pUser:onGetBlockCardMap()
	local pHandCardCountTwoMap = self:onGetHandCardCountTwoMap(pHandCardMap)
	local pAllGangCardTable = self:onGetAllGangTable(pHandCardCountTwoMap, pBlockCardMap)
	
	local opTable = {}
	if pUser:onGetIsBaoTing() <= 0 then
		for _, kGangCard in pairs(pAllGangCardTable) do
			local op = {
				iOpValue = kGangCard.iOpValue,
				iCardValue = kGangCard.iCardValue,
			}

			opTable[#opTable + 1] = op
		end
	end

	-- 胡牌
	local pHuInfo = self:onGetHuTypeInfo(0, pUser, pHandCardCountTwoMap, pCardValue)
	if pHuInfo and self:isRealCanHu(pUser, pHandCardCountTwoMap) then
		local pIsGangShangKaiHua = false
		local pTotalOutCard = self.m_pGameRound:onGetTotalOutCard()
		for k, v in pairs(pBlockCardMap) do
			if OperationType:isHasGang(v.iOpValue) and pTotalOutCard == v.iRank then
				pIsGangShangKaiHua = true
				break
			end
		end
		pUser:onSetHuInfo(pHuInfo)
		local op = {
			iOpValue = pIsGangShangKaiHua and OperationType.GANGSHANGKAIHUA or OperationType.ZIMO,
			iCardValue = pCardValue,
		}
		opTable[#opTable + 1] = op
	end

	for k, v in pairs(opTable) do
		if OperationType:isAnGang(v.iOpValue) then
			if self:isSanDaSiBao(pUser, pHandCardCountTwoMap, pCardValue) then
				local pHuInfo = {}
				pHuInfo.iFan = -1
				pHuInfo.iName = "三打四包"

				opTable = {} -- 触发外包直接胡
				local op = {
					iOpValue = OperationType.HU,
					iCardValue = pCardValue,
				}
				opTable[#opTable + 1] = op
			end

			break
		end
	end

	if self:isPlaytypeShiXiHua(self.m_pPlaytype) and self:isShiXiZhang(pUser:onGetUserId()) then
		opTable = {}

		local pHuInfo = {}
		pHuInfo.iFan = -1
		pHuInfo.iName = "十四张"

		pUser:onSetHuInfo(pHuInfo)

		local op = {
			iOpValue = OperationType.ZIMO,
			iCardValue = pCardValue,
		}
		opTable[#opTable + 1] = op	

		self.m_pIsCanZhengChan = true

	elseif #opTable > 0 then
		local op = {
			iOpValue = OperationType.GUO,
			iCardValue = pCardValue,
		}
		opTable[#opTable + 1] = op
	end


	-- Log.dump(TAG, opTable, "opTable")
	return opTable
end

--[[
	返回值为table{
		{iOpValue = 1, iCardValue = 1,}，
		...
	}
]]
function gameRuleJSNJJYZ:onGetOpTableWhenOutCard(pOutUser, pUser, pCardValue, pGameUsers)
	local pHandCardMap = pUser:onGetHandCardMap()
	local pBlockCardMap = pUser:onGetBlockCardMap()
	local pHandCardCountTwoMap = self:onGetHandCardCountTwoMap(pHandCardMap, pCardValue)
	local pAllGangCardTable = self:onGetAllGangTable(pHandCardCountTwoMap, pBlockCardMap, pCardValue)

	local opTable = {}
	-- 如果不是自己
	if pOutUser ~= pUser then
		-- 碰牌
		if self:isCanPeng(pHandCardCountTwoMap, pCardValue) and self:isRealCanPeng(pUser, pGameUsers, pCardValue) then
			local op = {
				iOpValue = OperationType.PENG,
				iCardValue = pCardValue,
			}
			opTable[#opTable + 1] = op
		end

		-- 杠牌
		if pUser:onGetIsBaoTing() <= 0 then
			for _, kGangCard in pairs(pAllGangCardTable) do
				local op = {
					iOpValue = kGangCard.iOpValue,
					iCardValue = kGangCard.iCardValue,
				}
				opTable[#opTable + 1] = op
			end
		end
		-- 胡牌
		local pHuInfo = self:onGetHuTypeInfo(1, pUser, pHandCardCountTwoMap, pCardValue)
		-- 是不是杠上炮
		local pIsGangShangPao = false
		-- local pOutUserBlockCardMap = pOutUser:onGetBlockCardMap()
		-- local pTotalOutCard = self.m_pGameRound:onGetTotalOutCard()
		-- for k, v in pairs(pOutUserBlockCardMap) do
		-- 	if OperationType:isHasGang(v.iOpValue) and v.iRank == pTotalOutCard - 1 then
		-- 		pIsGangShangPao = true
		-- 		break
		-- 	end
		-- end
		if pHuInfo and self:isRealCanHu(pUser, pHandCardCountTwoMap) then 
			pUser:onSetHuInfo(pHuInfo)
			local op = {
				iOpValue = pIsGangShangPao and OperationType.GANGSHANGPAO or OperationType.HU,
				iCardValue = pCardValue,
			}
			opTable[#opTable + 1] = op
		elseif self:isQingYiSe(pHandCardCountTwoMap, pBlockCardMap) and self:isQingYiSePengSanDu(pUser, pHandCardCountTwoMap, pCardValue) then
			local pHuInfo = {}
			pHuInfo.iFan = -1
			pHuInfo.iName = "清一色碰三对"

			pUser:onSetHuInfo(pHuInfo)

			opTable = {} -- 触发外包直接胡
			local op = {
				iOpValue = OperationType.HU,
				iCardValue = pCardValue,
			}
			opTable[#opTable + 1] = op
		elseif self:isSanDaSiBao(pUser, pHandCardCountTwoMap, pCardValue) then
			local pHuInfo = {}
			pHuInfo.iFan = -1
			pHuInfo.iName = "三打四包"

			pUser:onSetHuInfo(pHuInfo)

			opTable = {} -- 触发外包直接胡
			local op = {
				iOpValue = OperationType.HU,
				iCardValue = pCardValue,
			}
			opTable[#opTable + 1] = op
		end

		if #opTable > 0 then
			local op = {
				iOpValue = OperationType.GUO,
				iCardValue = pCardValue,
			}
			opTable[#opTable + 1] = op
		end		
	else
		local pOutCardMap = pUser:onGetOutCardMap()
		if self:isPlaytypeShiLiuYao(self.m_pPlaytype) and self:isShiLiuYao(pBlockCardMap, pOutCardMap) then
			local pHuInfo = {}
			pHuInfo.iFan = -1
			pHuInfo.iName = "十六幺"

			pUser:onSetHuInfo(pHuInfo)

			local op = {
				iOpValue = OperationType.ZIMO,
				iCardValue = pCardValue,
			}
			opTable[#opTable + 1] = op
			self.m_pIsCanZhengChan = true		
				
		elseif self:isPlaytypeDoubleDongNanXiBei(self.m_pPlaytype) and self:isDoubleDongNanXiBei(pBlockCardMap, pOutCardMap) then
			local pHuInfo = {}
			pHuInfo.iFan = -1
			pHuInfo.iName = "两轮东南西北或两轮北西南东"

			pUser:onSetHuInfo(pHuInfo)

			local op = {
				iOpValue = OperationType.ZIMO,
				iCardValue = pCardValue,
			}
			opTable[#opTable + 1] = op		
			self.m_pIsCanZhengChan = true

		elseif #opTable > 0 then
			local op = {
				iOpValue = OperationType.GUO,
				iCardValue = pCardValue,
			}
			opTable[#opTable + 1] = op	
		end
	end

	return opTable
end

function gameRuleJSNJJYZ:onGetOpTableWhenOpCard(pOpUser, pUser, pOp)
	local opTable = {}
	-- 碰牌之后是否能杠
	if OperationType:isPeng(pOp.iOpValue) and pOpUser == pUser then
		local pHandCardMap = pUser:onGetHandCardMap()
		local pBlockCardMap = pUser:onGetBlockCardMap()
		local pHandCardCountTwoMap = self:onGetHandCardCountTwoMap(pHandCardMap)
		local pAllGangCardTable = self:onGetAllGangTable(pHandCardCountTwoMap, pBlockCardMap)
		for _, kGangCard in pairs(pAllGangCardTable) do
			local op = {
				iOpValue = kGangCard.iOpValue,
				iCardValue = kGangCard.iCardValue,
			}
			opTable[#opTable + 1] = op
		end
	elseif OperationType:isBuGang(pOp.iOpValue) and pOpUser ~= pUser then
		local pHandCardMap = pUser:onGetHandCardMap()
		local pBlockCardMap = pUser:onGetBlockCardMap()
		local pHandCardCountTwoMap = self:onGetHandCardCountTwoMap(pHandCardMap, pOp.iCardValue)
		local pHuInfo = self:onGetHuTypeInfo(1, pUser, pHandCardCountTwoMap, pOp.iCardValue)
		if pHuInfo and self:isRealCanHu(pUser, pHandCardCountTwoMap) then
			pUser:onSetHuInfo(pHuInfo)
			local op = {
				iOpValue = OperationType.QIANGGANGHU,
				iCardValue = pOp.iCardValue,
			}
			opTable[#opTable + 1] = op
		end
	elseif OperationType:isGang(pOp.iOpValue) and pOpUser ~= pUser then
		local pHandCardMap = pUser:onGetHandCardMap()
		local pBlockCardMap = pUser:onGetBlockCardMap()
		local pHandCardCountTwoMap = self:onGetHandCardCountTwoMap(pHandCardMap, pOp.iCardValue)
		local pHuInfo = self:onGetHuTypeInfo(1, pUser, pHandCardCountTwoMap, pOp.iCardValue)
		if pHuInfo and self:isRealCanHu(pUser, pHandCardCountTwoMap) then
			pUser:onSetHuInfo(pHuInfo)
			local op = {
				iOpValue = OperationType.QIANGGANGHU,
				iCardValue = pOp.iCardValue,
			}

			Log.d(TAG, op, "onGetOpTableWhenOpCard op")
			opTable[#opTable + 1] = op
		end


	end
	if #opTable > 0 then
		local op = {
			iOpValue = OperationType.GUO,
			iCardValue = pOp.iCardValue,
		}
		opTable[#opTable + 1] = op
	end
	return opTable
end

function gameRuleJSNJJYZ:onGetDealTableWhenUserGang(pGameUsers, pOp, pUserCurOpTable)
	local pUser = nil
	local tUser = nil
	for k, v in pairs(pGameUsers) do
		if v:onGetUserId() == pOp.iUserId then
			pUser = v
		end

		if v:onGetUserId() == pOp.iTUserId then
			tUser = v
		end
	end

	-- 如果是直杠
	if OperationType:isGang(pOp.iOpValue) then -- 明杠：出杠者付10花
		Log.d(TAG, "onGetDealWhenUserGang isGang 10 ")
		self:onGameCurrentSettlement(pUser, tUser, pGameUsers, 10)
	elseif OperationType:isAnGang(pOp.iOpValue) then
		Log.d(TAG, "onGetDealWhenUserGang isAnGang 5 ")
		self:onGameCurrentSettlement(pUser, nil, pGameUsers, 5)
	else
		Log.d(TAG, "onGetDealWhenUserGang isBuGang 10 ")
		local pBlockCardMap = pUser:onGetBlockCardMap()
		local pOpTable = pBlockCardMap[#pBlockCardMap]
		if (pUserCurOpTable and #pUserCurOpTable > 0) or not OperationType:isBuGang(pOpTable.iOpValue) then return end -- 暗杠 如果有玩家先择胡，抢杠胡不算钱
		for k, v in pairs(pGameUsers) do
			if v:onGetUserId() == pOpTable.iTUserId then
				tUser = v
				break
			end
		end

		self:onGameCurrentSettlement(pUser, tUser, pGameUsers, 10)
	end
end

--!
--! @brief      Determines if game stop liu ju.
--!
--! @param      cardCount  The card count
--!
--! @return     True if game stop liu ju, False otherwise.
--!
function gameRuleJSNJJYZ:isGameStopLiuJu(pSeatId , pCardCount)
	if pCardCount <= 0 then
		self.m_pGameRound.m_pPreRoundInfo.iBankerSeatId = self.m_pGameRound.m_pBankerSeatId --荒庄 坐庄的人继续坐庄
		self.m_pIsBiXiaHu = true
		return true
	end
	return false
end

--!
--! @brief      将手牌转化成2维计数数组
--!
--! @param      pHandCardMap  The hand card map
--!
--! @return     pHandCardCountTwoMap  
--!
function gameRuleJSNJJYZ:onGetHandCardCountTwoMap(pHandCardMap, pCardValue)
	local pHandCardCountTwoMap = {}
	for i = 1, 6 do -- 需要加上花牌
		pHandCardCountTwoMap[i] = {}
		for j = 1, 10 do
			pHandCardCountTwoMap[i][j] = 0
		end
	end
	for _, kCardValue in pairs(pHandCardMap) do
		local kType, kValue = self:onGetCardTypeAndValue(kCardValue)
		pHandCardCountTwoMap[kType][10] = pHandCardCountTwoMap[kType][10] + 1
		pHandCardCountTwoMap[kType][kValue] = pHandCardCountTwoMap[kType][kValue] + 1
	end
	if pCardValue and pCardValue > 0 then
		local pType, pValue = self:onGetCardTypeAndValue(pCardValue)
		pHandCardCountTwoMap[pType][10] = pHandCardCountTwoMap[pType][10] + 1
		pHandCardCountTwoMap[pType][pValue] = pHandCardCountTwoMap[pType][pValue] + 1
	end
	return pHandCardCountTwoMap
end

--!
--! @brief      Determines if can peng.
--!
--! @param      pHandCardMap  The hand card map
--! @param      pCardValue    The card value
--!
--! @return     True if can peng, False otherwise.
--!
function gameRuleJSNJJYZ:isCanPeng(pHandCardCountTwoMap, pCardValue)
	local pType, pValue = self:onGetCardTypeAndValue(pCardValue)
	return pHandCardCountTwoMap[pType][pValue] >= 3 
end

function gameRuleJSNJJYZ:onGetCanTingCardTable(pHandCardCountTwoMap, pBlockCardMap)
	local pMahjongOneCardTable = {}
	local onAddOneCard = function(pMahjongOneCardTable, pValue)
		for _, kCardValue in pairs(pMahjongOneCardTable) do
			if kCardValue == pValue then
				return
			end
		end
		table.insert(pMahjongOneCardTable, pValue)
	end

	-- 加上和手牌有关的牌
	for i = 1, 5 do
		for j = 1, 9 do
			if pHandCardCountTwoMap[i][j] > 0 then
				onAddOneCard(pMahjongOneCardTable, i * 10 + j)
				if i <= 3 and j - 1 >= 1 then
					onAddOneCard(pMahjongOneCardTable, i * 10 + j - 1)
				end
				if i <= 3 and j + 1 <= 9 then
					onAddOneCard(pMahjongOneCardTable, i * 10 + j + 1)
				end
			end
		end
	end
	return pMahjongOneCardTable
end

function gameRuleJSNJJYZ:onGetHandOneCardMap(pHandCardMap)
	local pHandOneCardMap = {}
	for i = 1, #pHandCardMap do
		local pIsHas = false
		for j = 1, #pHandOneCardMap do
			if pHandCardMap[i] == pHandOneCardMap[j] then
				pIsHas = true
				break
			end
		end
		if not pIsHas then
			pHandOneCardMap[#pHandOneCardMap + 1] = pHandCardMap[i]
		end
	end
	return pHandOneCardMap
end

function gameRuleJSNJJYZ:onGetTingCardTable(pUser)
	local pStartTime = os.clock()
	local pAllCardTingInfoTable = {}
	local pHandCardMap = pUser:onGetHandCardMap()
	local pBlockCardMap = pUser:onGetBlockCardMap()
	-- 有多少张手牌
	local pHandOneCardMap = self:onGetHandOneCardMap(pHandCardMap)
	-- Log.dump(TAG, pBlockCardMap, "pBlockCardMap")
	for index, _ in pairs(pHandOneCardMap) do
		local pCardValue = pHandOneCardMap[index]
		local pOneCardTingInfoTable = self:onGetOneTingCardTable(pUser, pHandCardMap, pBlockCardMap, pCardValue)
		
		if #pOneCardTingInfoTable > 0 then
			pAllCardTingInfoTable[#pAllCardTingInfoTable + 1] = {
				iTingCardValue = pCardValue,
				iTingCardInfoTable = pOneCardTingInfoTable
			}
		end
	end
	-- Log.dump(TAG, pAllCardTingInfoTable, "pAllCardTingInfoTable")
	local pCostTime = (os.clock() - pStartTime) * 1000
	-- Log.e(TAG, "gameRuleJSNJJYZ after4 onGetTingCardTable1111111111 time[%s]", pCostTime)
	return pAllCardTingInfoTable
end

function gameRuleJSNJJYZ:onGetOneTingCardTable(pUser, pHandCardMap, pBlockCardMap, pCardValue)
	local pOneCardTingInfoTable = {}
	local pMahjongOneCardTable = self:onGetCanTingCardTable(self:onGetHandCardCountTwoMap(pHandCardMap), pBlockCardMap)
	for i = 1, #pMahjongOneCardTable do
		local tCardValue = pMahjongOneCardTable[i]
		local pHandCardCountTwoMap = self:onGetHandCardCountTwoMap(pHandCardMap)
		local tType, tValue = self:onGetCardTypeAndValue(tCardValue)
		pHandCardCountTwoMap[tType][tValue] = pHandCardCountTwoMap[tType][tValue] + 1
		pHandCardCountTwoMap[tType][10] = pHandCardCountTwoMap[tType][10] + 1
		if pCardValue and pCardValue > 0 then
			local pType, pValue = self:onGetCardTypeAndValue(pCardValue)
			pHandCardCountTwoMap[pType][pValue] = pHandCardCountTwoMap[pType][pValue] - 1
			pHandCardCountTwoMap[pType][10] = pHandCardCountTwoMap[pType][10] - 1
		end
		-- 如果能听牌，则开始计算最大番型
		local pHuInfo = self:onGetHuTypeInfo(2, pUser, pHandCardCountTwoMap, pCardValue)
		if pHuInfo and self:isRealCanHu(pUser, pHandCardCountTwoMap) then
			pHuInfo.iCardValue = tCardValue
			pHuInfo.iCardCount = self.m_pGameRound:onGetRemainCardNum(pUser:onGetUserId(), tCardValue)
			pHuInfo.iNeed = ""  -- 是否需要自摸
			pOneCardTingInfoTable[#pOneCardTingInfoTable + 1] = pHuInfo
		end
	end
	return pOneCardTingInfoTable
end

function gameRuleJSNJJYZ:isNormalHu(pHandCardCountTwoMap, pHasJiang)
	local pCloneHandCardCountTwoMap = clone(pHandCardCountTwoMap)
	return self:onComplet(pCloneHandCardCountTwoMap, pHasJiang)
end

--!
--! @brief      获得当某一个玩家胡牌的信息
--!
--! @param      pUser        胡牌玩家
--! @param      tUser        放炮玩家
--! @param      pGameUsers   所有玩家
--! @param      op           The operation
--!
--! @return     返回胡牌信息
--!
function gameRuleJSNJJYZ:onGetHuTableWhenUserHu(pUser, tUser, pGameUsers, op, pBasePoint, pIsBattle, pIsYiPaoDuoXiang)
	local pRet = {}
	local pHuCard = op.iCardValue
	local pHandCardMap = pUser:onGetHandCardMap()
	local pBlockCardMap = pUser:onGetBlockCardMap()
	local pOutCardMap = pUser:onGetOutCardMap()
	local pHandCardCountTwoMap = self:onGetHandCardCountTwoMap(pHandCardMap) 
	local pGangCardTable = self:onGetAllGangTable(pHandCardCountTwoMap, pBlockCardMap)
	
	local pHuInfo = pUser:onGetHuInfo()
	if pHuInfo then
		-- 处理其他的番型
		if not self.m_pIsCanZhengChan then --如果不是整铲除
			local pAddToFanTable = self:onDealAddToFanWhenHasHu(pUser, pGameUsers, op, pUser == tUser, pHuCard)
			pHuInfo.iFan = pHuInfo.iFan + pAddToFanTable.iFan
			pHuInfo.iName = string.format("%s %s", pHuInfo.iName, pAddToFanTable.iName)
			if self.m_pGameRound.m_pPreRoundInfo.iBiXiaHu then -- 比下胡结算是胡牌总花数×2
				pHuInfo.iFan = pHuInfo.iFan * 2
			end
			if pHuInfo.iBiXiaHu or pAddToFanTable.iFan > 0 then
				self.m_pIsBiXiaHu = true
			end

			local pAddToHuaTable = self:onDealAddToHuaWhenHasHu(pUser, pHuCard)
			pHuInfo.iFan = pHuInfo.iFan + pAddToHuaTable.iFan
			pHuInfo.iName = string.format("%s %s", pHuInfo.iName, pAddToHuaTable.iName)
		else
			if pHuInfo.iBiXiaHu then
				self.m_pIsBiXiaHu = true
			end			

			if self.m_pGameRound.m_pPreRoundInfo.iBiXiaHu then -- 比下胡结算是胡牌总花数×2
				pHuInfo.iFan = pHuInfo.iFan * 2
			end			
		end
		
		-- 设置手牌和操作牌
		if not pHuInfo.iHuCard then
			pHuInfo.iHuCard = pHuCard
		end

		local pHuType = pUser == tUser and DefineType.MAHJONG_HUTYPE_ZIMO or DefineType.MAHJONG_HUTYPE_PAOHU
		pRet = {
			iUserId = pUser:onGetUserId(),
			iTUserId = tUser:onGetUserId(),
			iFan = pHuInfo.iFan,
			iName = pHuInfo.iName,
			iHuType = pHuType,
			iHuCard = pHuInfo.iHuCard,
			iTurnMoneyTable = {},
			iIsWaiBao = false,
		}
	end

	local pBei = pRet.iFan and  pRet.iFan or 0

	if pUser:onGetSeatId() == self.m_pGameRound.m_pBankerSeatId or pIsYiPaoDuoXiang then -- 比下胡 庄家胡牌 一炮多响
		self.m_pIsBiXiaHu = true
	end
	
	if self:isPlaytypeBaShu(self.m_pPlaytype) and not self.m_pIsBiXiaHu then -- 接庄比：庄的下家胡牌，下局也比下胡
		local userCount =  self.m_pGameRound:onGetGameTable():onGetGameTableMaxUserCount()
		local nextSeatId = self.m_pGameRound.m_pBankerSeatId % userCount + 1
		if nextSeatId == pUser:onGetSeatId() then
			self.m_pIsBiXiaHu = true
		end
	end

	self:onGetHuSettlement(pRet, pUser, tUser, pGameUsers, op, pBei)
	-- 统计玩家的数据
	if pIsBattle then
		local pUserExtend = self.m_pUserExtendTable[pUser:onGetUserId()]
		-- Log.dump(TAG, pUserExtend, "pUserExtend")
		for k, v in pairs(pBlockCardMap) do
			if OperationType:isHasGang(v.iOpValue) then
				pUserExtend.iGangCount = pUserExtend.iGangCount + 1
			end
		end
		if pUserExtend.iMaxFan < pRet.iFan then
			pUserExtend.iMaxFan = pRet.iFan
		end
		if pUser == tUser then
			pUserExtend.iZiMoCount = pUserExtend.iZiMoCount + 1
		else
			local tUserExtend = self.m_pUserExtendTable[tUser:onGetUserId()]
			tUserExtend.iFangPaoCount = tUserExtend.iFangPaoCount + 1
			pUserExtend.iJiePaoCount = pUserExtend.iJiePaoCount + 1
		end
	end
	-- 设置上局的信息,用来定庄
	--庄胡连庄，闲胡下庄
	if pUser:onGetSeatId() == self.m_pGameRound.m_pBankerSeatId then
		self.m_pGameRound.m_pPreRoundInfo.iBankerSeatId = pUser:onGetSeatId()
	elseif pIsYiPaoDuoXiang and pGameUsers[self.m_pGameRound.m_pBankerSeatId]:onGetIsHu() > 0 then
		self.m_pGameRound.m_pPreRoundInfo.iBankerSeatId = self.m_pGameRound.m_pBankerSeatId
	else
		local userCount =  self.m_pGameRound:onGetGameTable():onGetGameTableMaxUserCount()
		self.m_pGameRound.m_pPreRoundInfo.iBankerSeatId = pUser:onGetSeatId() % userCount + 1		
	end
	-- Log.dump(TAG, pRet ,"pRet")
	return pRet
end

function gameRuleJSNJJYZ:onGetHuSettlement(pRet, pUser, tUser, pGameUsers, pOp, pBei)
	--是否内包
	--内包在桌面设置的100分内结算
	local pSongGangZheUserId = self:onGetSongGangZheUserId(pUser, tUser, pGameUsers, pOp)
	local pQingYiSeWaiBao, pQingYiSeWaiBaoUserId = self:isQingYiSeWaiBao(pUser, tUser, pOp, pRet.iHuCard)

	if pOp and OperationType:isQiangGangHu(pOp.iOpValue) then -- 抢杠胡算自摸，由杠牌人付三倍，并且杠牌人不能收杠钱
		local pValue = pBei * 3
		pValue = tUser:onGetMoney() < pValue and tUser:onGetMoney() or pValue
		pRet.iTurnMoneyTable[tUser:onGetUserId()] = -pValue
		pRet.iTurnMoneyTable[pUser:onGetUserId()] = pRet.iTurnMoneyTable[pUser:onGetUserId()] or 0
		pRet.iTurnMoneyTable[pUser:onGetUserId()] = pRet.iTurnMoneyTable[pUser:onGetUserId()] + pValue		

	elseif pSongGangZheUserId > 0 then -- 大杠开花：杠开者算自摸，全部由送杠者一家付三倍
		local pValue = pBei * 3
		local pTempMoney = self:onGetUserMoneyByUserId(pSongGangZheUserId, pGameUsers)
		pValue = pTempMoney < pValue and pTempMoney or pValue
		pRet.iTurnMoneyTable[pSongGangZheUserId] = -pValue
		pRet.iTurnMoneyTable[pUser:onGetUserId()] = pRet.iTurnMoneyTable[pUser:onGetUserId()] or 0
		pRet.iTurnMoneyTable[pUser:onGetUserId()] = pRet.iTurnMoneyTable[pUser:onGetUserId()] + pValue	

	elseif self:isQuanQiuDuDiaoJiaPai(pUser, tUser) then --全球独钓架牌
			local pValue = 50 
			if self.m_pGameRound.m_pPreRoundInfo.iBiXiaHu then
				pValue = pValue * 2
			end

			self.m_pUserExtendTable[tUser:onGetUserId()].iWaiBao = self.m_pUserExtendTable[tUser:onGetUserId()].iWaiBao + (-pValue)
			self.m_pUserExtendTable[pUser:onGetUserId()].iWaiBao = self.m_pUserExtendTable[pUser:onGetUserId()].iWaiBao + pValue

			pRet.iName = "外包"
			pRet.iIsWaiBao = true

			pRet.iTurnMoneyTable[tUser:onGetUserId()] = -pValue
			pRet.iTurnMoneyTable[pUser:onGetUserId()] = pRet.iTurnMoneyTable[pUser:onGetUserId()] or 0
			pRet.iTurnMoneyTable[pUser:onGetUserId()] = pRet.iTurnMoneyTable[pUser:onGetUserId()] + pValue	

			self.m_pIsBiXiaHu = true
	elseif pQingYiSeWaiBao then --清一色外包
			local pValue = 50 
			if self.m_pGameRound.m_pPreRoundInfo.iBiXiaHu then
				pValue = pValue * 2
			end

			self.m_pUserExtendTable[pQingYiSeWaiBaoUserId].iWaiBao = self.m_pUserExtendTable[pQingYiSeWaiBaoUserId].iWaiBao + (-pValue)
			self.m_pUserExtendTable[pUser:onGetUserId()].iWaiBao = self.m_pUserExtendTable[pUser:onGetUserId()].iWaiBao + pValue

			pRet.iName = "外包"
			pRet.iIsWaiBao = true

			pRet.iTurnMoneyTable[pQingYiSeWaiBaoUserId] = -pValue
			pRet.iTurnMoneyTable[pUser:onGetUserId()] = pRet.iTurnMoneyTable[pUser:onGetUserId()] or 0
			pRet.iTurnMoneyTable[pUser:onGetUserId()] = pRet.iTurnMoneyTable[pUser:onGetUserId()] + pValue	

			self.m_pIsBiXiaHu = true
	else
		if pUser == tUser then 
			for p, q in pairs(pGameUsers) do
				if pUser ~= q and q:onGetIsHu() <= 0 then
					local pValue = pBei
					pValue = q:onGetMoney() < pValue and q:onGetMoney() or pValue
					pRet.iTurnMoneyTable[q:onGetUserId()] = -pValue
					pRet.iTurnMoneyTable[pUser:onGetUserId()] = pRet.iTurnMoneyTable[pUser:onGetUserId()] or 0
					pRet.iTurnMoneyTable[pUser:onGetUserId()] = pRet.iTurnMoneyTable[pUser:onGetUserId()] + pValue
				end
			end
		else
			local pValue = pBei
			pValue = tUser:onGetMoney() < pValue and tUser:onGetMoney() or pValue
			pRet.iTurnMoneyTable[tUser:onGetUserId()] = -pValue
			pRet.iTurnMoneyTable[pUser:onGetUserId()] = pRet.iTurnMoneyTable[pUser:onGetUserId()] or 0
			pRet.iTurnMoneyTable[pUser:onGetUserId()] = pRet.iTurnMoneyTable[pUser:onGetUserId()] + pValue
		end
	end
end

function gameRuleJSNJJYZ:onGetSongGangZheUserId(pUser, tUser, pGameUsers, pOp)
	if not pOp or not OperationType:isGangShangKaiHua(pOp.iOpValue) then return 0 end
	local pBlockCardMap = pUser:onGetBlockCardMap()
	local pOpTable = pBlockCardMap[#pBlockCardMap]
	if OperationType:isGang(pOpTable.iOpValue) then
		for k, v in pairs(pGameUsers) do
			if v:onGetUserId() ~= pUser:onGetUserId() then
				local pOutCardMap = v:onGetOutCardMap()
				for kOut, vOut in pairs(pOutCardMap) do
					if vOut.iRank + 1 == pOpTable.iRank then
						return v:onGetUserId()
					end
				end
			end
		end
	end

	if OperationType:isBuGang(pOpTable.iOpValue) then -- 补杠 前面出牌让我碰的为送杠者
		for k, v in pairs(pGameUsers) do
			if v:onGetUserId() ~= pUser:onGetUserId() then
				local pOutCardMap = v:onGetOutCardMap()
				for kOut, vOut in pairs(pOutCardMap) do
					if vOut.iCardValue == pOpTable.iCardValue then
						return v:onGetUserId()
					end
				end
			end
		end
	end

	return 0
end

function gameRuleJSNJJYZ:isQuanQiuDuDiaoJiaPai(pUser, tUser)
	if pUser == tUser then return false end

	local pHandCardMap = pUser:onGetHandCardMap()
	local pBlockCardMap = pUser:onGetBlockCardMap()
	local pHandCardCountTwoMap = self:onGetHandCardCountTwoMap(pHandCardMap)
	if self:isQuanQiuDuDiao(pHandCardCountTwoMap, pBlockCardMap) then 
		local pCardValue = pHandCardMap[#pHandCardMap]
		local pOpTable = pBlockCardMap[#pBlockCardMap]
		local pOutCardMap = pUser:onGetOutCardMap()

		local pOutCardValue = 0
		for k, v in pairs(pOutCardMap) do
			if v.iRank == pOpTable.iRank + 1 then
				pOutCardValue = v.iCardValue
				break
			end
		end

		if pOutCardValue <= 0 then return false end
		local pType, pValue = self:onGetCardTypeAndValue(pCardValue)
		local pOutType, pOutValue = self:onGetCardTypeAndValue(pOutCardValue)
		if pType ~= pOutType then
			return false
		end

		if not self.m_pJiaPaiTable[pUser:onGetUserId()] or not self.m_pJiaPaiTable[pUser:onGetUserId()].iCardValue then
			return false
		end

		if pValue  <= pOutValue + 2 or pValue >= pOutValue - 2 then
			return true
		end
	end

	return false
end

function gameRuleJSNJJYZ:isSanDaSiBao(pUser, pHandCardCountTwoMap, pCardValue) -- 三打四包
	local pBlockCardMap = pUser:onGetBlockCardMap()
	local pTustUserId = 0
	local pSameUserPengCount = 0 
	local pCardCount = 0 
	for k, v in pairs(pBlockCardMap) do
		if OperationType:isPeng(v.iOpValue) or OperationType:isBuGang(v.iOpValue) or OperationType:isGang(v.iOpValue) then
			if pTustUserId == 0 or pTustUserId == v.iTUserId then
				pSameUserPengCount = pSameUserPengCount + 1
				pTustUserId = v.iTUserId
			else
				break
			end
		end

		if OperationType:isAnGang(v.iOpValue) then
			pSameUserPengCount = pSameUserPengCount + 1
		end
	end

	local pType, pValue = self:onGetCardTypeAndValue(pCardValue)
	pCardCount = pHandCardCountTwoMap[pType][pValue]
	
	Log.d(TAG, "isSanDaSiBao.............. pSameUserPengCount = %s pCardCount = %s ", pSameUserPengCount, pCardCount)
	if pSameUserPengCount >= 3 then 
		if pCardCount >= 3 or self:isDuiDuiHu(pHandCardCountTwoMap, pBlockCardMap) then
			return true, pTustUserId
		end
	end

	Log.d(TAG, "isQingYiSeWaiBao  isSanDaSiBao.....................................in")
	return false
end

function gameRuleJSNJJYZ:isQingYiSePengSanDu(pUser, pHandCardCountTwoMap, pCardValue)
	local pPengCount = 0
	local pBlockCardMap = pUser:onGetBlockCardMap()
	if #pBlockCardMap < 3 then return false end

	local pUserId = 0 
	for i=1, #pBlockCardMap do
		if OperationType:isPeng(pBlockCardMap[i].iOpValue) or OperationType:isHasGang(pBlockCardMap[i].iOpValue) then
			if pUserId ~= pBlockCardMap[i].iTUserId then
				pPengCount = pPengCount + 1
				pUserId = pBlockCardMap[i].iTUserId
			else
				break
			end
		end
	end

	local pType, pValue = self:onGetCardTypeAndValue(pCardValue)
	if pPengCount ~= 3 or pHandCardCountTwoMap[pType][pValue] < 3 then
		return false
	end

	return true
end

function gameRuleJSNJJYZ:isQingYiSePengSanDuFangPao(pUser, tUser, pBlockCardMap, pOp)
	local pPengCount = 0
	local pSameUserPengCount = {}
	if pUser == tUser then return false end
	if #pBlockCardMap < 3 then return false end

	local pUserId = 0 
	for i=1, #pBlockCardMap do
		if OperationType:isPeng(pBlockCardMap[i].iOpValue) or OperationType:isHasGang(pBlockCardMap[i].iOpValue) then
			if pUserId ~= pBlockCardMap[i].iTUserId then
				pPengCount = pPengCount + 1
				pUserId = pBlockCardMap[i].iTUserId
			else
				break
			end
		end
	end

	if pPengCount ~= 3 then
		return false
	end

	return true, tUser:onGetUserId()
end

function gameRuleJSNJJYZ:isQingYiSePengSameSanDuFangPao(pUser, tUser, pBlockCardMap)
	if pUser == tUser then return false end
	if #pBlockCardMap < 3 then return false end
	local pTustUserId = 0
	local pSameUserPengCount = 0 
	for k, v in pairs(pBlockCardMap) do
		if OperationType:isPeng(v.iOpValue) or OperationType:isGang(v.iOpValue) or OperationType:isBuGang(v.iOpValue) then
			if pTustUserId == 0 or pTustUserId == v.iTUserId then
				pSameUserPengCount = pSameUserPengCount + 1
				pTustUserId = v.iTUserId
			else
				pSameUserPengCount = 1
				pTustUserId = v.iTUserId
			end	
		end

		if OperationType:isAnGang(v.iOpValue) then
			pSameUserPengCount = pSameUserPengCount + 1
		end
	end

	if pSameUserPengCount < 3 or pTustUserId == 0 then
		return false
	end

	return true, pTustUserId
end

function gameRuleJSNJJYZ:isQingYiSeWaiBao(pUser, tUser, pOp, pCardValue) --清一色外包
	local pHandCardMap = pUser:onGetHandCardMap()
	local pBlockCardMap = pUser:onGetBlockCardMap()
	local pHandCardCountTwoMap = self:onGetHandCardCountTwoMap(pHandCardMap)
	if self:isQingYiSe(pHandCardCountTwoMap, pBlockCardMap) then
		local pFlag, pUserId = self:isQingYiSePengSanDu(pUser, pHandCardCountTwoMap, pCardValue), tUser:onGetUserId()
		if pFlag then
			Log.d(TAG, "isQingYiSeWaiBao  isQingYiSePengSanDu.....................................in")
			return pFlag, pUserId
		end

		pFlag, pUserId = self:isQingYiSePengSanDuFangPao(pUser, tUser, pBlockCardMap, pOp)
		if pFlag then
			Log.d(TAG, "isQingYiSeWaiBao  isQingYiSePengSanDuFangPao.....................................in")
			return pFlag, pUserId
		end

		pFlag, pUserId = self:isQingYiSePengSameSanDuFangPao(pUser, tUser, pBlockCardMap)
		if pFlag then
			Log.d(TAG, "isQingYiSeWaiBao  isQingYiSePengSameSanDuFangPao.....................................in")
			return pFlag, pUserId
		end	
	end

	return self:isSanDaSiBao(pUser, pHandCardCountTwoMap, pCardValue)
end


function gameRuleJSNJJYZ:onGetNeedBuHua(pUser, pCardValue)
	local tType, tValue = self:onGetCardTypeAndValue(pCardValue)
	return tType > 4 
end

--------------------------- 内部函数 ---------------------
function gameRuleJSNJJYZ:onGetGameSettingConfig()
	if not self.m_pPlaytypeConfig or not self.m_pPlaytypeConfig.iGameSettingTable then return {} end
	local iGameSettingTable = self.m_pPlaytypeConfig.iGameSettingTable
	local pBigType = string.format("0x%04x", self.m_pLocalGameType & 0xFF00)
	local pSmallType = string.format("0x%02x", self.m_pLocalGameType & 0x00FF)
	if iGameSettingTable[pBigType] == nil then return {} end
	return iGameSettingTable[pBigType][pSmallType] or {}
end

--是否屏蔽表情
function gameRuleJSNJJYZ:isGameSettingEmoji()
	local iGameSettingConfig = self:onGetGameSettingConfig()
	if iGameSettingConfig.GAME_SETTING_EMOJI == nil then return end
	local iValue = iGameSettingConfig.GAME_SETTING_EMOJI.iValue
	local iGameSetting = self.m_pExtendTable.iGameSetting or 0
	return (iGameSetting & iValue) == iValue
end

--[[
	获取当前地区玩法下的玩法配置表
]]
function gameRuleJSNJJYZ:onGetLocalGamePlaytypeTable()
	local pBigType = string.format("0x%04x", self.m_pLocalGameType & 0xFF00)
	local pSmallType = string.format("0x%02x", self.m_pLocalGameType & 0x00FF)
	return self.m_pPlaytypeConfig.iGamePlaytypeTable[pBigType][pSmallType] or {}
end

--[[
	把数(接庄比)
]]
function gameRuleJSNJJYZ:isPlaytypeBaShu(playtype)
	local playtypeTable = self:onGetLocalGamePlaytypeTable()
	local value = playtypeTable.MAHJONG_PLAYTYPE_BASHU.iValue
	return value == (playtype & value)
end

--[[
	圈数(占庄比)
]]
function gameRuleJSNJJYZ:isPlaytypeQuanShu(playtype)
	local playtypeTable = self:onGetLocalGamePlaytypeTable()
	local value = playtypeTable.MAHJONG_PLAYTYPE_QUANSHU.iValue
	return value == (playtype & value)
end

--[[
	花砸2
]]
function gameRuleJSNJJYZ:isPlaytypeHuaZaer(playtype)
	local playtypeTable = self:onGetLocalGamePlaytypeTable()
	local value = playtypeTable.MAHJONG_PLAYTYPE_HUAZAER.iValue
	return value == (playtype & value)
end

--[[
	东南西北罚款
]]
function gameRuleJSNJJYZ:isPlaytypeDongNanXiBeiFaKuan(playtype)
	local playtypeTable = self:onGetLocalGamePlaytypeTable()
	local value = playtypeTable.MAHJONG_PLAYTYPE_DONGNANXIBEIFAKUAN.iValue
	return value == (playtype & value)
end

--[[
	14花(整铲)
]]
function gameRuleJSNJJYZ:isPlaytypeShiXiHua(playtype)
	local playtypeTable = self:onGetLocalGamePlaytypeTable()
	local value = playtypeTable.MAHJONG_PLAYTYPE_SHIXIHUA.iValue
	return value == (playtype & value)
end

--[[
	16幺(整铲)
]]
function gameRuleJSNJJYZ:isPlaytypeShiLiuYao(playtype)
	local playtypeTable = self:onGetLocalGamePlaytypeTable()
	local value = playtypeTable.MAHJONG_PLAYTYPE_SHILIUYAO.iValue
	return value == (playtype & value)
end

--[[
	一炮三响(整铲)
]]
function gameRuleJSNJJYZ:isPlaytypeYiPaoSanXiang(playtype)
	local playtypeTable = self:onGetLocalGamePlaytypeTable()
	local value = playtypeTable.MAHJONG_PLAYTYPE_YIPAOSANXIANG.iValue
	return value == (playtype & value)
end

--[[
	东南西北、东南西北(整铲)
]]
function gameRuleJSNJJYZ:isPlaytypeDoubleDongNanXiBei(playtype)
	local playtypeTable = self:onGetLocalGamePlaytypeTable()
	local value = playtypeTable.MAHJONG_PLAYTYPE_DOUBLEDONGNANXIBEI.iValue
	return value == (playtype & value)
end


--!
--! @brief      Determines if ping hu.
--!
--! @param      pHandCardCountTwoMap  The hand card count map
--! @param      pBlockCardMap      The block card map
--!
--! @return     True if ping hu, False otherwise.
--!
function gameRuleJSNJJYZ:isPingHu(pHandCardCountTwoMap, pBlockCardMap)
	local pCloneHandCardCountMap = clone(pHandCardCountTwoMap)
	if self:isNormalHu(pCloneHandCardCountMap) then
		local pRet = {
			iHandCardCountMap = pHandCardCountTwoMap,
			iBlockCardMap = pBlockCardMap,
		}
		return pRet
	end
end

function gameRuleJSNJJYZ:onDealAddToFanWhenQiXiaoDui(pHandCardCountTwoMap, pBlockCardMap)
	local pAddToFanTable = {
		iName = "",
		iFan = 0,
	}
	-- 判断是不是三龙七对
	if self:isSanLongQiDui(pHandCardCountTwoMap, pBlockCardMap) then
		pAddToFanTable.iName = string.format("%s%s ", pAddToFanTable.iName, "超超豪华七对")
		pAddToFanTable.iFan = pAddToFanTable.iFan + 160
	elseif self:isShuangLongQiDui(pHandCardCountTwoMap, pBlockCardMap) then
		pAddToFanTable.iName = string.format("%s%s ", pAddToFanTable.iName, "超豪华七对")
		pAddToFanTable.iFan = pAddToFanTable.iFan + 120
	elseif self:isLongQiDui(pHandCardCountTwoMap, pBlockCardMap) then
		pAddToFanTable.iName = string.format("%s%s ", pAddToFanTable.iName, "豪华七对")
		pAddToFanTable.iFan = pAddToFanTable.iFan + 80
	else
		pAddToFanTable.iName = string.format("%s%s ", pAddToFanTable.iName, "七对")
		pAddToFanTable.iFan = pAddToFanTable.iFan + 30
	end
	-- 判断是不是清一色
	if self:isQingYiSe(pHandCardCountTwoMap, pBlockCardMap) then
		pAddToFanTable.iName = string.format("%s%s ", pAddToFanTable.iName, "清一色")
		pAddToFanTable.iFan = pAddToFanTable.iFan + 30
	end

	return pAddToFanTable
end

function gameRuleJSNJJYZ:onDealAddToFanWhenPingHu(pHandCardCountTwoMap, pBlockCardMap)
	local pAddToFanTable = {
		iName = "",
		iFan = 0,
	}
	-- 判断是不是对对胡
	if self:isDuiDuiHu(pHandCardCountTwoMap, pBlockCardMap) then
		pAddToFanTable.iName = string.format("%s%s ", pAddToFanTable.iName, "对对胡")
		pAddToFanTable.iFan = pAddToFanTable.iFan + 20
	end
	-- 判断是不是清一色
	if self:isQingYiSe(pHandCardCountTwoMap, pBlockCardMap) then
		pAddToFanTable.iName = string.format("%s%s ", pAddToFanTable.iName, "清一色")
		pAddToFanTable.iFan = pAddToFanTable.iFan + 30
	end

	if self:isHunYiSe(pHandCardCountTwoMap, pBlockCardMap) then
		pAddToFanTable.iName = string.format("%s%s ", pAddToFanTable.iName, "混一色")
		pAddToFanTable.iFan = pAddToFanTable.iFan + 20
	end

	if self:isQuanQiuDuDiao(pHandCardCountTwoMap, pBlockCardMap) then
		pAddToFanTable.iName = string.format("%s%s ", pAddToFanTable.iName, "全球独钓")
		pAddToFanTable.iFan = pAddToFanTable.iFan + 30
	end

	return pAddToFanTable
end


function gameRuleJSNJJYZ:onDealAddToFanWhenHasHu(pUser, pGameUsers, pOp, pIsDraw, pCardValue)
	local pAddToFanTable = {
		iName = "",
		iFan = 0,

	}

	if pIsDraw then
		if not pOp or not OperationType:isGangShangKaiHua(pOp.iOpValue) then
			if self:isDaGangKaiHua(pUser) then
				pAddToFanTable.iName = string.format("%s %s", pAddToFanTable.iName, "大杠开花")
				pAddToFanTable.iFan = pAddToFanTable.iFan + 20
			elseif self:isXiaoGangKaiHua(pUser) then
				pAddToFanTable.iName = string.format("%s %s", pAddToFanTable.iName, "小杠开花")
				pAddToFanTable.iFan = pAddToFanTable.iFan + 10
			-- else
			-- 	pAddToFanTable.iName = string.format("%s %s", pAddToFanTable.iName, "自摸")
			-- 	pAddToFanTable.iFan = pAddToFanTable.iFan + 0
			end
		end
	end

	-- if pOp and OperationType:isQiangGangHu(pOp.iOpValue) then
	-- 	pAddToFanTable.iName = string.format("%s %s", pAddToFanTable.iName, "抢杠胡")
	-- 	pAddToFanTable.iFan = pAddToFanTable.iFan + 0
	-- end

	if pOp and OperationType:isGangShangKaiHua(pOp.iOpValue) then
		pAddToFanTable.iName = string.format("%s %s", pAddToFanTable.iName, "大杠开花")
		pAddToFanTable.iFan = pAddToFanTable.iFan + 20
	end

	local pHandCardMap = pUser:onGetHandCardMap()
	local pHandCardCountTwoMap = self:onGetHandCardCountTwoMap(pHandCardMap)
	if self:isYaJue(pUser, pHandCardCountTwoMap, pCardValue) then
		pAddToFanTable.iFan =  pAddToFanTable.iFan + 20
		pAddToFanTable.iName = string.format("%s %s", pAddToFanTable.iName, "压绝")
	end

	-- if pOp and OperationType:isGangShangPao(pOp.iOpValue) then
	-- 	pAddToFanTable.iName = string.format("%s %s", pAddToFanTable.iName, "杠上炮")
	-- 	pAddToFanTable.iFan = pAddToFanTable.iFan + 0
	-- 	pAddToFanTable.iIsGangShangPao = true
	-- end
	-- 判断是不是天胡，地胡
	if self:isTianHu(pUser, pGameUsers) then
		pAddToFanTable.iName = string.format("%s %s", pAddToFanTable.iName, "天胡")
		pAddToFanTable.iFan = pAddToFanTable.iFan + 0 -- 三家干、
		self.m_pIsCanZhengChan = true
	elseif self:isDiHu(pUser, pGameUsers) then
		pAddToFanTable.iName = string.format("%s %s", pAddToFanTable.iName, "地胡")
		pAddToFanTable.iFan = pAddToFanTable.iFan + 30
	end

	return pAddToFanTable
end

--!
--! @brief      Determines if Xiao Gang Kai Hua.
--!
--! @param      pHandCardCountTwoMap  The hand card count map
--! @param      pBlockCardMap      The block card map
--!
--! @return     True if Xiao Gang Kai Hua, False otherwise.
--!
function gameRuleJSNJJYZ:isXiaoGangKaiHua(pUser)
	local pDrawCardMap = pUser:onGetDrawCardMap()
	if #pDrawCardMap < 2 then return false end 
	local pPerCardValue = pDrawCardMap[#pDrawCardMap - 1]
	local pCardType, _ = self:onGetCardTypeAndValue(pPerCardValue)
	if pCardType < 5 then 
		return false
	else
		local pCardCount = 0
		for i,v in ipairs(pDrawCardMap) do
			if v == pPerCardValue then
				pCardCount = pCardCount + 1
			end
		end
		
		return pCardCount  < 4
	end
end

--!
--! @brief      Determines if Da Gang Kai Hua.
--!
--! @param      pHandCardCountTwoMap  The hand card count map
--! @param      pBlockCardMap      The block card map
--!
--! @return     True if Da Gang Kai Hua, False otherwise.
--!
function gameRuleJSNJJYZ:isDaGangKaiHua(pUser)
	local pDrawCardMap = pUser:onGetDrawCardMap()
	if #pDrawCardMap < 2 then return false end

	local pPerCardValue = pDrawCardMap[#pDrawCardMap - 1]
	local pType, pValue = self:onGetCardTypeAndValue(pPerCardValue)

	local pCardCount = 0
	if pType == 5 then
		for i,v in ipairs(pDrawCardMap) do
			if v == pPerCardValue then
				pCardCount = pCardCount + 1
			end
		end
	elseif pType == 6 then
		local pBeginValue = pValue < 5 and 1 or 5 -- 春夏秋冬 梅兰竹菊
		local pEndValue = pBeginValue + 3
		for i = pBeginValue, pEndValue do
			for k, v in ipairs(pDrawCardMap) do
				if v == (pType * 10 + i) then
					pCardCount = pCardCount + 1
				end
			end
		end
	end

	return pCardCount == 4
end	

--!
--! @brief      Determines if qing yi se.
--!
--! @param      pHandCardCountTwoMap  The hand card count map
--! @param      pBlockCardMap      The block card map
--!
--! @return     True if qing yi se, False otherwise.
--!
function gameRuleJSNJJYZ:isQingYiSe(pHandCardCountTwoMap, pBlockCardMap)
	local pHuaSeTable = {}
	for k, v in pairs(pBlockCardMap) do
		local kType, kValue = self:onGetCardTypeAndValue(v.iCardValue)
		pHuaSeTable[kType] = true
	end
	for i = 1, 5 do
		pHuaSeTable[i] = pHuaSeTable[i] or pHandCardCountTwoMap[i][10] > 0 
	end
	local pHuaSeCount = 0
	for i = 1, 3 do
		pHuaSeCount = pHuaSeCount + (pHuaSeTable[i] and 1 or 0)
	end
	if pHuaSeTable[4] or pHuaSeTable[5] then
		pHuaSeCount = pHuaSeCount + 1
	end
	return pHuaSeCount <= 1
end


--!
--! @brief      Determines if dui dui hu.
--!
--! @param      pHandCardCountTwoMap  The hand card count map
--! @param      pBlockCardMap      The block card map
--!
--! @return     True if dui dui hu, False otherwise.
--!
function gameRuleJSNJJYZ:isDuiDuiHu(pHandCardCountTwoMap, pBlockCardMap)
	for k, v in pairs(pBlockCardMap) do
		if not OperationType:isPeng(v.iOpValue) and not OperationType:isHasGang(v.iOpValue) then
			return
		end
	end
	local pJiangCount = 0
	for i = 1, 4 do -- 中发白是花牌
		for j = 1, 9 do
			if 2 == pHandCardCountTwoMap[i][j] or pHandCardCountTwoMap[i][j] == 5 then
				pJiangCount = pJiangCount + 1
			elseif pHandCardCountTwoMap[i][j] > 0 and pHandCardCountTwoMap[i][j] ~= 3 then
				return
			end
		end
	end
	return 1 == pJiangCount
end

--!
--! @brief      Determines if xiao qi dui.
--!
--! @param      pHandCardCountTwoMap  The hand card count map
--! @param      pBlockCardMap      The block card map
--!
--! @return     True if xiao qi dui, False otherwise.
--!
function gameRuleJSNJJYZ:isXiaoQiDui(pHandCardCountTwoMap, pBlockCardMap)
	if #pBlockCardMap > 0 then return end
	for i = 1, 5 do
		if 0 ~= pHandCardCountTwoMap[i][10] % 2 then return end
		for j = 1, 9 do
			if 0 ~= pHandCardCountTwoMap[i][j] % 2 then return end
		end
	end
	return true
end


--!
--! @brief      Determines if long qi dui.
--!
--! @param      pHandCardCountTwoMap  The hand card count map
--! @param      pBlockCardMap      The block card map
--!
--! @return     True if long qi dui, False otherwise.
--!
function gameRuleJSNJJYZ:isLongQiDui(pHandCardCountTwoMap, pBlockCardMap)
	if not self:isXiaoQiDui(pHandCardCountTwoMap, pBlockCardMap) then 
		return
	end
	local pGangCount = 0
	for i = 1, 5 do
		for j = 1, 9 do
			if pHandCardCountTwoMap[i][j] >= 4 then
				pGangCount = pGangCount + 1
			end
		end
	end
	return pGangCount >= 1
end

--!
--! @brief      Determines if men qing.
--!
--! @param      pHandCardCountTwoMap  The hand card count map
--! @param      pBlockCardMap      The block card map
--!
--! @return     True if men qing, False otherwise.
--!
function gameRuleJSNJJYZ:isMenQing(pHandCardCountTwoMap, pBlockCardMap)
	-- 门清就是没碰，但明杠和暗杠也算门清
	for k, v in pairs(pBlockCardMap) do
		if OperationType:isPeng(v.iOpValue) then
			return false
		end
	end
	return true
end

--!
--! @brief      Determines if Four Hard Hua.
--!
--! @param      pHandCardCountTwoMap  The hand card count map
--! @param      pBlockCardMap      The block card map

--!
--! @return     True if Four Hard Hua, False otherwise.
--!
function gameRuleJSNJJYZ:isFourHardHua(pUserId)
	return #self.m_pGameRound.m_pUserBuHuaTable[pUserId] > 3
end


--!
--! @brief      Determines if Hun Yi Se.
--!
--! @param      pHandCardCountTwoMap  The hand card count map
--! @param      pBlockCardMap      The block card map
--!
--! @return     True if Hun Yi Se, False otherwise.
--!
function gameRuleJSNJJYZ:isHunYiSe(pHandCardCountTwoMap, pBlockCardMap)
	local pZiCount = 0
	for i=4,5 do
		pZiCount = pZiCount + pHandCardCountTwoMap[i][10]
	end
	local pWan, pTong, pTiao = 0, 0, 0
	if pHandCardCountTwoMap[1][10] >0 then
		pWan = 1
	end
	if pHandCardCountTwoMap[2][10] >0 then
		pTong = 1
	end
	if pHandCardCountTwoMap[3][10] >0 then
		pTiao = 1
	end

	if (pWan + pTong + pTiao) > 1 or (pWan + pTong + pTiao) == 0 then
		return false
	end

	for k, v in pairs(pBlockCardMap) do
		local pType, pValue = self:onGetCardTypeAndValue(v.iCardValue)
		if pType >= 4 and pType <= 5 then
			pZiCount = pZiCount + 1
		elseif 3 == pType then
			pTiao = 1
		elseif 2 == pType  then
			pTong = 1
		elseif 1 == pType  then
			pWan = 1
        end
        if (pWan + pTong + pTiao) > 1 or (pWan + pTong + pTiao) == 0 then
	    	return false
	    end
	end
	if pZiCount <=0 then
		return false
	end
	return true
end

--!
--! @brief      Determines if Wu Hua Guo.
--!
--! @param      pHandCardCountTwoMap  The hand card count map
--! @param      pBlockCardMap      The block card map
--!
--! @return     True if Wu Hua Guo, False otherwise.
--!
function gameRuleJSNJJYZ:isWuHuaGuo(pUserId)
	return #self.m_pGameRound.m_pUserBuHuaTable[pUserId] == 0
end

--!
--! @brief      Determines if Ya Jue.
--!
--! @param      pHandCardCountTwoMap  The hand card count map
--! @param      pBlockCardMap      The block card map
--!
--! @return     True if Ya Jue, False otherwise.
--!
function gameRuleJSNJJYZ:isYaJue(pUser, pHandCardCountTwoMap, pCardValue)
	local pGameUsers = self.m_pGameRound.m_pGameUsers
	local pIsPeng = false
	if self:onGetYaDang(pUser, pHandCardCountTwoMap, pCardValue) or self:onGetBianZhi(pUser, pHandCardCountTwoMap, pCardValue) then
		for _, kUser in pairs(pGameUsers) do
			local pBlockCardMap = kUser:onGetBlockCardMap()
			for k, v in pairs(pBlockCardMap) do
				if (OperationType:isPeng(v.iOpValue) or OperationType:isBuGang(v.iOpValue)) and v.iCardValue == pCardValue then
					pIsPeng = true
					break
				end
			end

			if pIsPeng then break end
		end
	end

	return pIsPeng
end

--!
--! @brief      Determines if Tian Hu.
--!
--! @param      pHandCardCountTwoMap  The hand card count map
--! @param      pBlockCardMap      The block card map
--!
--! @return     True if Tian Hu, False otherwise.
--!
function gameRuleJSNJJYZ:isTianHu(pUser, pGameUsers)
	for _, kUser in pairs(pGameUsers) do
		local pOutCardMap = kUser:onGetOutCardMap()
		local pBlockCardMap = kUser:onGetBlockCardMap()
		if #pOutCardMap > 0 or #pBlockCardMap > 0 then
			return false
		end
		if kUser:onGetIsHu() > 0 and kUser ~= pUser then
			return false
		end
	end
	return true
end

--!
--! @brief      Determines if Di Hu.
--!
--! @param      pHandCardCountTwoMap  The hand card count map
--! @param      pBlockCardMap      The block card map
--!
--! @return     True if Di Hu, False otherwise.
--!
function gameRuleJSNJJYZ:isDiHu(pUser, pGameUsers)
	if pUser:onGetIsBaoTing() <= 0 then return false end
	return true
end
	
--!
--! @brief      Determines if Quan Qiu Du Diao.
--!
--! @param      pHandCardCountTwoMap  The hand card count map
--! @param      pBlockCardMap      The block card map
--!
--! @return     True if Quan Qiu Du Diao, False otherwise.
--!
function gameRuleJSNJJYZ:isQuanQiuDuDiao(pHandCardCountTwoMap, pBlockCardMap)
	local pCardCount = 0
	for i=1, 4 do
		pCardCount = pCardCount + pHandCardCountTwoMap[i][10]
	end
	return pCardCount == 2
end

--!
--! @brief      Determines if shuang long qi dui.
--!
--! @param      pHandCardCountTwoMap  The hand card count map
--! @param      pBlockCardMap      The block card map
--!
--! @return     True if shuang long qi dui, False otherwise.
--!
function gameRuleJSNJJYZ:isShuangLongQiDui(pHandCardCountTwoMap, pBlockCardMap)
	if not self:isXiaoQiDui(pHandCardCountTwoMap, pBlockCardMap) then 
		return
	end
	local pGangCount = 0
	for i = 1, 5 do
		for j = 1, 9 do
			if pHandCardCountTwoMap[i][j] >= 4 then
				pGangCount = pGangCount + 1
			end
		end
	end
	return pGangCount >= 2
end

function gameRuleJSNJJYZ:isSanLongQiDui(pHandCardCountTwoMap, pBlockCardMap)
	if not self:isXiaoQiDui(pHandCardCountTwoMap, pBlockCardMap) then 
		return
	end
	local pGangCount = 0
	for i = 1, 5 do
		for j = 1, 9 do
			if pHandCardCountTwoMap[i][j] >= 4 then
				pGangCount = pGangCount + 1
			end
		end
	end
	return pGangCount >= 3
end

function gameRuleJSNJJYZ:onComplet(pHandCardCountTwoMap, pHasJiang)
	local pRet = GameCore.onComplete(pHandCardCountTwoMap, pHasJiang and 1 or 0)
	Log.d(TAG, "onComplete pRet[%s]", pRet)
	return 0 == pRet
end

function gameRuleJSNJJYZ:onGetAllGangTable(pHandCardCountTwoMap, pBlockCardMap, pCardValue)
	local pGangCardTable = {}
	if pCardValue and pCardValue > 0 then
		local pType, pValue = self:onGetCardTypeAndValue(pCardValue)
		if pHandCardCountTwoMap[pType][pValue] >= 4 then
			pGangCardTable[#pGangCardTable + 1] = {
				iCardValue = pCardValue,
				iCardNum = 4,
				iOpValue = OperationType.GANG,
			}
		end
	else
		for i = 1, 5 do
			if pHandCardCountTwoMap[i][10] >= 4 then
				for j = 1, 9 do
					if pHandCardCountTwoMap[i][j] >= 4 then
						local kCardValue = i * 10 + j
						pGangCardTable[#pGangCardTable + 1] = {
							iCardValue = kCardValue,
							iCardNum = 4,
							iOpValue = OperationType.AN_GANG,
						}
					end
				end
			end
		end
		for k, v in pairs(pBlockCardMap) do
			local pType, pValue = self:onGetCardTypeAndValue(v.iCardValue)
			if OperationType:isPeng(v.iOpValue) and pHandCardCountTwoMap[pType][pValue] > 0 then
				pGangCardTable[#pGangCardTable + 1] = {
					iCardValue = v.iCardValue,
					iCardNum = 1,
					iOpValue = OperationType.BU_GANG,
				}
			end
		end
	end
	return pGangCardTable
end

function gameRuleJSNJJYZ:isCanYiPaoSanXiang(pGameUsers)
	local pHuCount = 0
	local pFangPaoUserId = 0
	if self:isPlaytypeYiPaoSanXiang(self.m_pPlaytype) then
		for k, v in pairs(pGameUsers) do
			if v:onGetIsHu() > 0 then
				pHuCount = pHuCount + 1
			else
				pFangPaoUserId = v:onGetUserId()
			end
		end
	end

	return pHuCount == 3, pFangPaoUserId
end

function gameRuleJSNJJYZ:onGetUserMoneyByUserId(pUserId, pGameUsers)
	for k, v in pairs(pGameUsers) do
		if v:onGetUserId() == pUserId then
			return v:onGetMoney()
		end
	end

	return 0
end

function gameRuleJSNJJYZ:onGameRoundStop(result, pAllTurnMoneyTable, pGameUsers)
	local pExtendInfoTable = {}
	local pTurnMoneyTable = {}
	local pHuUserId = 0
	for k, v in pairs(pGameUsers) do
		pExtendInfoTable[v:onGetUserId()] = {
			iUserId = v:onGetUserId(),
			iFan = 0,
			iName = "",
			iHuType = DefineType.MAHJONG_HUTYPE_NONE,
			iHuCard = 0,
		}
		pTurnMoneyTable[v:onGetUserId()] = 0

		if v:onGetIsHu() > 0 then
			pHuUserId = v:onGetUserId()
		end
	end

	self.m_pGameRound.m_pPreRoundInfo.iBiXiaHu = self.m_pIsBiXiaHu

	local pIsYiPaoSanXiang, pFangPaoUserId = self:isCanYiPaoSanXiang(pGameUsers) -- 一炮三响：三家胡的人直接干，放炮的人赢
	if pIsYiPaoSanXiang or self.m_pIsCanZhengChan then
		pHuUserId = pIsYiPaoSanXiang and pFangPaoUserId or pHuUserId
		for k, v in pairs(pAllTurnMoneyTable.iHuTurnMoneyTable) do
			local pTotalMoney = 0
			-- 计算所有人的分数
			pExtendInfoTable[v.iUserId].iFan = v.iFan
			pExtendInfoTable[v.iUserId].iName = v.iName
			pExtendInfoTable[v.iUserId].iHuType = v.iHuType
			pExtendInfoTable[v.iUserId].iHuCard = v.iHuCard
			for tKey, tUser in pairs(pGameUsers) do
				if pHuUserId ~= tUser:onGetUserId() then
					pTurnMoneyTable[tUser:onGetUserId()] = 0 - tUser:onGetMoney()
					pTotalMoney = pTotalMoney + tUser:onGetMoney()
				end
			end

			pTurnMoneyTable[pHuUserId] = pTotalMoney
		end
	else
		for k, v in pairs(pAllTurnMoneyTable.iHuTurnMoneyTable) do
			-- 计算所有人的分数
			pExtendInfoTable[v.iUserId].iFan = v.iFan
			pExtendInfoTable[v.iUserId].iName = v.iName
			pExtendInfoTable[v.iUserId].iHuType = v.iHuType
			pExtendInfoTable[v.iUserId].iHuCard = v.iHuCard
			if v.iIsWaiBao then
				for p, q in pairs(v.iTurnMoneyTable) do
					pExtendInfoTable[p].iWaiBao = q
				end	
			else
				for p, q in pairs(v.iTurnMoneyTable) do
					local pTempMoney = self:onGetUserMoneyByUserId(p, pGameUsers)
					if (pTempMoney + q ) < 0 then
						q = - pTempMoney
					end

					pTurnMoneyTable[p] = pTurnMoneyTable[p] + q 
				end				
			end

		end
	end

	return pExtendInfoTable, pTurnMoneyTable
end

function gameRuleJSNJJYZ:isFriendBattleGameOver(result)
	local pGameUsers = self.m_pGameRound.m_pGameUsers
	local pZeroMoney = 0
	local pUserCount = 0
	for k, v in pairs(pGameUsers) do
		if v:onGetMoney() <= 0 then
			pZeroMoney = pZeroMoney + 1
		end

		pUserCount = pUserCount + 1
	end

	local function onClearUserMoney()
		for k, v in pairs(pGameUsers) do
			local pTempMoney = v:onGetMoney() - self.m_pLimitMoney
			v:onSetMoney(pTempMoney)
		end		
	end

	if result == 0 and self.m_pGameRound:onGetGameTable():isFriendBattleGameOver(result) then
		onClearUserMoney()
	elseif result == 2 or (pUserCount > 3 and pZeroMoney > 1) or (pUserCount < 4 and pZeroMoney > 0) then
		onClearUserMoney()
		return true
	end

	return false
end

function gameRuleJSNJJYZ:onGameCurrentSettlement(pUser, tUser, pGameUsers, pValue)
	local name = "ServerBCMahjongMoneyUpdate"
	local info = {}
	info.iMoneyTable = {}
	if not pUser then return end
	if tUser and tUser == pUser then return end

	if self.m_pGameRound.m_pPreRoundInfo.iBiXiaHu then
		pValue = pValue * 2 -- 比下胡结算是现场汇也相对应×2
	end

	if tUser then
		pValue = tUser:onGetMoney() > pValue and pValue or tUser:onGetMoney()
		pUser:onSetMoney(pUser:onGetMoney() + pValue)
		tUser:onSetMoney(tUser:onGetMoney() - pValue)
	else
		if pValue > 0 then
			for k, v in pairs(pGameUsers) do
				if pUser:onGetUserId() ~= v:onGetUserId() then
					local pTempMoney = v:onGetMoney() > pValue and pValue or v:onGetMoney()
					v:onSetMoney(v:onGetMoney() - pTempMoney)
					pUser:onSetMoney(pUser:onGetMoney() + pTempMoney)
				end
			end
		else
			local userCount =  self.m_pGameRound:onGetGameTable():onGetGameTableMaxUserCount()
			local nextSeatId = pUser:onGetSeatId() % userCount + 1
			while (nextSeatId ~= pUser:onGetSeatId()) do
				local pTempUser = pGameUsers[nextSeatId]
				local pTempMoney = pUser:onGetMoney() + pValue > 0 and pValue or (0 - pUser:onGetMoney())
				pTempUser:onSetMoney(pTempUser:onGetMoney() - pTempMoney)
				pUser:onSetMoney(pUser:onGetMoney() + pTempMoney)
				nextSeatId = pTempUser:onGetSeatId() % userCount + 1

				if pUser:onGetMoney() <= 0 then
					break
				end
			end
		end
	end

	local pZeroMoney = 0
	local pUserCount = 0
	for k, v in pairs(pGameUsers) do
		if tUser then
			if tUser:onGetUserId() == v:onGetUserId() or pUser:onGetUserId() == v:onGetUserId() then
				local iMoneyInfo = {}
				iMoneyInfo.iUserId = v:onGetUserId()
				iMoneyInfo.iMoney = v:onGetMoney()
				table.insert(info.iMoneyTable, iMoneyInfo)
			end
		else
			local iMoneyInfo = {}
			iMoneyInfo.iUserId = v:onGetUserId()
			iMoneyInfo.iMoney = v:onGetMoney()
			table.insert(info.iMoneyTable, iMoneyInfo)
		end

		if v:onGetMoney() <= 0 then
			pZeroMoney = pZeroMoney + 1
		end

		pUserCount = pUserCount + 1
	end

	self.m_pGameRound:onGetGameTable():onBroadcastTableUsers(name, info)
	table.insert(self.m_pGameRound.m_pOneRoundLookbackTable, {
		iName = name,
		iInfo = info,
	})

	if (pUserCount > 3 and pZeroMoney > 1) or (pUserCount < 4 and pZeroMoney > 0) then
		self.m_pGameRound:onGameRoundStop(2) -- 当有两家携带游戏币为0时，游戏立刻结束 按流局处理
	end

	self.m_pIsBiXiaHu = true
end

function gameRuleJSNJJYZ:onGetUserJiaPai(pUser, pCardValue)
	local pHandCardMap = pUser:onGetHandCardMap()
	if #pHandCardMap > 1 then return end
	local pUserId = pUser:onGetUserId()
	if self.m_pJiaPaiTable[pUserId] then
		if pCardValue == self.m_pJiaPaiTable[pUserId].iCardValue then
			local pTempCardValue = pHandCardMap[#pHandCardMap]
			if pTempCardValue == pCardValue then
				return
			end

			self.m_pJiaPaiTable[pUserId] = {}
		else
			return
		end
	else
		self.m_pJiaPaiTable[pUserId] = {}
		self.m_pJiaPaiTable[pUserId].iCardValue = pHandCardMap[#pHandCardMap]
		self.m_pJiaPaiTable[pUserId].iJiaPai = pCardValue
	end

	local name = "ServerBCMahjongJiaPai"
	local info = {}
	info.iJiaPaiInfo = {}
	for k,v in pairs(self.m_pJiaPaiTable) do
		if v.iJiaPai then
			local pJiaPaiInfo  = {}
			pJiaPaiInfo.iUserId = k
			pJiaPaiInfo.iCardValue = v.iJiaPai
			table.insert(info.iJiaPaiInfo, pJiaPaiInfo)
		end
	end

	self.m_pGameRound:onGetGameTable():onBroadcastTableUsers(name, info)
	table.insert(self.m_pGameRound.m_pOneRoundLookbackTable, {
		iName = name,
		iInfo = info,
	})
end

function gameRuleJSNJJYZ:onGetDealTableWhenUserOutCard(pUser, pCardValue)
	local pBlockCardMap = pUser:onGetBlockCardMap()
	local pOutCardMap = pUser:onGetOutCardMap()

	self:onGetUserJiaPai(pUser, pCardValue)

	if self:isPlaytypeDongNanXiBeiFaKuan(self.m_pPlaytype) then			
		if #pOutCardMap == 4 and self:isDongNanXiBeiFaKuan(pBlockCardMap, pOutCardMap) then
			--TODO: 罚款
			Log.d(TAG, "onGameCurrentSettlement isPlaytypeDongNanXiBeiFaKuan 5 ")
			self:onGameCurrentSettlement(pUser, nil, self.m_pGameRound.m_pGameUsers, 5)
		end
	end

	if self:isFourOutSameCard(pBlockCardMap, pUser) then
		--TODO: 罚款
		local pPerSeatId =  (pUser:onGetSeatId() - 1 ) > 0 and (pUser:onGetSeatId() - 1 ) or self.m_pGameRound:onGetGameTable():onGetGameTableMaxUserCount()
		for i=1, 2 do
			pPerSeatId =  (pPerSeatId - 1 ) > 0 and (pPerSeatId - 1 ) or self.m_pGameRound:onGetGameTable():onGetGameTableMaxUserCount()
		end

		Log.d(TAG, "onGameCurrentSettlement isFourOutSameCard -5 ")
		self:onGameCurrentSettlement(self.m_pGameRound.m_pGameUsers[pPerSeatId], nil, self.m_pGameRound.m_pGameUsers, -5)
	end

	if self:isOutFourSameCard(pBlockCardMap, pOutCardMap) then
		Log.d(TAG, "onGameCurrentSettlement isOutFourSameCard -5 ")
		self:onGameCurrentSettlement(pUser, nil, self.m_pGameRound.m_pGameUsers, -5)
	end
end

function gameRuleJSNJJYZ:onGetFengPengCount(pUser)
	local pHandCardMap = pUser:onGetHandCardMap()
	local pHandCardCountTwoMap = self:onGetHandCardCountTwoMap(pHandCardMap)
	local pFengKeCount = 0
	for i = 1, 4 do
		if pHandCardCountTwoMap[4][i] > 2 then
			pFengKeCount = pFengKeCount + 1
		end
	end

	return pFengKeCount
end

function gameRuleJSNJJYZ:onGetYaDang(pUser, pHandCardCountTwoMap, pCardValue)
	local pType, pValue = self:onGetCardTypeAndValue(pCardValue)
	if pType < 4 and pValue - 1 > 0 and pValue + 1 < 10 then
		if pHandCardCountTwoMap[pType][pValue - 1] > 0 and pHandCardCountTwoMap[pType][pValue + 1] > 0 then
			local pHandCardMap = pUser:onGetHandCardMap()
			local pBlockCardMap = pUser:onGetBlockCardMap()
			local pOneCardTingInfoTable = self:onGetOneTingCardTable(pUser, pHandCardMap, pBlockCardMap, pCardValue)
			if #pOneCardTingInfoTable == 1 and pOneCardTingInfoTable[1].iCardValue == pCardValue then
				local pCloneHandCardCountTwoMap = clone(pHandCardCountTwoMap)
				pCloneHandCardCountTwoMap[pType][pValue] = pCloneHandCardCountTwoMap[pType][pValue] - 1
				pCloneHandCardCountTwoMap[pType][pValue - 1] = pCloneHandCardCountTwoMap[pType][pValue - 1] - 1
				pCloneHandCardCountTwoMap[pType][pValue + 1] = pCloneHandCardCountTwoMap[pType][pValue + 1] - 1
				pCloneHandCardCountTwoMap[pType][10] = pCloneHandCardCountTwoMap[pType][10] - 3
				if self:onComplet(pCloneHandCardCountTwoMap) then
					return true
				end
			end
		end
	end

	return false
end

function gameRuleJSNJJYZ:onGetDuZhan(pUser, pCardValue)
	local pHandCardMap = pUser:onGetHandCardMap()
	local pHandCardCountTwoMap = self:onGetHandCardCountTwoMap(pHandCardMap)
	local pBlockCardMap = pUser:onGetBlockCardMap()
	if self:isXiaoQiDui(pHandCardCountTwoMap, pBlockCardMap) or self:isQuanQiuDuDiao(pHandCardCountTwoMap, pBlockCardMap) then -- 七对子不算独占
		return false
	end

	local pType, pValue = self:onGetCardTypeAndValue(pCardValue)
	-- 看看能不能单吊
	if self:isDuiDuiHu(pHandCardCountTwoMap, pBlockCardMap) then
		if pHandCardCountTwoMap[pType][pValue] >= 2 then
			local pCloneHandCardCountTwoMap = clone(pHandCardCountTwoMap)
			pCloneHandCardCountTwoMap[pType][pValue] = pCloneHandCardCountTwoMap[pType][pValue] - 2
			pCloneHandCardCountTwoMap[pType][10] = pCloneHandCardCountTwoMap[pType][10] - 2
			if self:onComplet(pCloneHandCardCountTwoMap, true) then
				return true
			end
		end
	else
		local pOneCardTingInfoTable = self:onGetOneTingCardTable(pUser, pHandCardMap, pBlockCardMap, pCardValue)
		if #pOneCardTingInfoTable == 1 and pOneCardTingInfoTable[1].iCardValue == pCardValue then
			if pHandCardCountTwoMap[pType][pValue] >= 2 then
				local pCloneHandCardCountTwoMap = clone(pHandCardCountTwoMap)
				pCloneHandCardCountTwoMap[pType][pValue] = pCloneHandCardCountTwoMap[pType][pValue] - 2
				pCloneHandCardCountTwoMap[pType][10] = pCloneHandCardCountTwoMap[pType][10] - 2
				if self:onComplet(pCloneHandCardCountTwoMap, true) then
					return true
				end
			end
		end
	end

	return false
end

function gameRuleJSNJJYZ:onGetBianZhi(pUser, pHandCardCountTwoMap, pCardValue)
	local pHandCardMap = pUser:onGetHandCardMap()
	local pBlockCardMap = pUser:onGetBlockCardMap()
	local pType, pValue = self:onGetCardTypeAndValue(pCardValue)
	if pType < 4 and ((pValue + 2) == 9 or (pValue - 2) == 1) then
		if (pValue + 2) == 9 and pHandCardCountTwoMap[pType][pValue + 1] > 0 and pHandCardCountTwoMap[pType][pValue + 2] > 0 then
			local pOneCardTingInfoTable = self:onGetOneTingCardTable(pUser, pHandCardMap, pBlockCardMap, pCardValue)
			if #pOneCardTingInfoTable == 1 and pOneCardTingInfoTable[1].iCardValue == pCardValue then					
				local pCloneHandCardCountTwoMap = clone(pHandCardCountTwoMap)
				pCloneHandCardCountTwoMap[pType][pValue] = pCloneHandCardCountTwoMap[pType][pValue] - 1
				pCloneHandCardCountTwoMap[pType][pValue + 1] = pCloneHandCardCountTwoMap[pType][pValue + 1] - 1
				pCloneHandCardCountTwoMap[pType][pValue + 2] = pCloneHandCardCountTwoMap[pType][pValue + 2] - 1
				pCloneHandCardCountTwoMap[pType][10] = pCloneHandCardCountTwoMap[pType][10] - 3
				if self:onComplet(pCloneHandCardCountTwoMap) then
					return true
				end
			end
		end

		if (pValue - 2) == 1 and pHandCardCountTwoMap[pType][pValue - 1] > 0 and pHandCardCountTwoMap[pType][pValue - 2] > 0 then
			local pOneCardTingInfoTable = self:onGetOneTingCardTable(pUser, pHandCardMap, pBlockCardMap, pCardValue)
			if #pOneCardTingInfoTable == 1 and pOneCardTingInfoTable[1].iCardValue == pCardValue then
				local pCloneHandCardCountTwoMap = clone(pHandCardCountTwoMap)
				pCloneHandCardCountTwoMap[pType][pValue] = pCloneHandCardCountTwoMap[pType][pValue] - 1
				pCloneHandCardCountTwoMap[pType][pValue - 1] = pCloneHandCardCountTwoMap[pType][pValue - 1] - 1
				pCloneHandCardCountTwoMap[pType][pValue - 2] = pCloneHandCardCountTwoMap[pType][pValue - 2] - 1
				pCloneHandCardCountTwoMap[pType][10] = pCloneHandCardCountTwoMap[pType][10] - 3
				if self:onComplet(pCloneHandCardCountTwoMap) then
					return true
				end
			end
		end
	end

	return false
end

function gameRuleJSNJJYZ:onGetQueYiMen(pUser)
	local pHuaSeTable = {}
	local pHandCardMap = pUser:onGetHandCardMap()
	local pHandCardCountTwoMap = self:onGetHandCardCountTwoMap(pHandCardMap)
	local pBlockCardMap = pUser:onGetBlockCardMap()

	if self:isHunYiSe(pHandCardCountTwoMap, pBlockCardMap) or self:isQingYiSe(pHandCardCountTwoMap, pBlockCardMap) then --混一色清一色不算缺一
		return false
	end

	for k, v in pairs(pBlockCardMap) do
		local kType, kValue = self:onGetCardTypeAndValue(v.iCardValue)
		pHuaSeTable[kType] = true
	end
	for i = 1, 3 do
		pHuaSeTable[i] = pHuaSeTable[i] or pHandCardCountTwoMap[i][10] > 0 
	end
	local pHuaSeCount = 0
	for i = 1, 3 do
		pHuaSeCount = pHuaSeCount + (pHuaSeTable[i] and 1 or 0)
	end

	return pHuaSeCount == 2
end

function gameRuleJSNJJYZ:onGetBlockHua(pUser)
	local pHuaCount = 0
	local pBlockCardMap = pUser:onGetBlockCardMap()
	for k, v in pairs(pBlockCardMap) do
		local tType, _ = self:onGetCardTypeAndValue(v.iCardValue)
		if OperationType:isGang(v.iOpValue) then
			if tType < 4 then
				pHuaCount = pHuaCount + 1
			else
				pHuaCount = pHuaCount + 2
			end
		end

		if OperationType:isAnGang(v.iOpValue) then
			if tType < 4 then
				pHuaCount = pHuaCount + 2
			else
				pHuaCount = pHuaCount + 3
			end
		end

		if OperationType:isPeng(v.iOpValue) then
			if tType > 3 then
				pHuaCount = pHuaCount + 1
			end
		end
	end	

	return pHuaCount
end


function gameRuleJSNJJYZ:onDealAddToHuaWhenHasHu(pUser, pCardValue)
	local pAddToFanTable = {
		iName = "",
		iFan = 0,
	}

	local pOutCardMap = pUser:onGetOutCardMap()
	local pHandCardMap = pUser:onGetHandCardMap()
	local pHandCardCountTwoMap = self:onGetHandCardCountTwoMap(pHandCardMap) 

	local pHardHuaCount = #self.m_pGameRound.m_pUserBuHuaTable[pUser:onGetUserId()]
	local pSoftHuaCount = 0
	local pDiZi = 10 -- 底子为10 

	pSoftHuaCount = pSoftHuaCount + self:onGetFengPengCount(pUser)

	if self:onGetDuZhan(pUser, pCardValue) then
		pSoftHuaCount = pSoftHuaCount + 1
	end

	if not self:isYaJue(pUser, pHandCardCountTwoMap, pCardValue) then --压绝成牌后压档和边枝软花不算
		if self:onGetYaDang(pUser, pHandCardCountTwoMap, pCardValue) then --边枝和压档统称丫子，只算一个
			pSoftHuaCount = pSoftHuaCount + 1
		elseif self:onGetBianZhi(pUser, pHandCardCountTwoMap, pCardValue) then
			pSoftHuaCount = pSoftHuaCount + 1
		end
	end

	if self:onGetQueYiMen(pUser) then
		pSoftHuaCount = pSoftHuaCount + 1
	end

	pSoftHuaCount = pSoftHuaCount + self:onGetBlockHua(pUser)

	if self:isPlaytypeHuaZaer(self.m_pPlaytype) then
		pHardHuaCount = pHardHuaCount * 2
		pSoftHuaCount = pSoftHuaCount * 2
	end

	if pHardHuaCount > 0 then
		pAddToFanTable.iName = string.format("%s %s", pAddToFanTable.iName, "硬花*")
		pAddToFanTable.iName = string.format("%s%d", pAddToFanTable.iName, pHardHuaCount)
	end

	if pSoftHuaCount > 0 then
		pAddToFanTable.iName = string.format("%s %s", pAddToFanTable.iName, "软花*")
		pAddToFanTable.iName = string.format("%s%d", pAddToFanTable.iName, pSoftHuaCount)
	end

	pAddToFanTable.iName = string.format("%s %s", pAddToFanTable.iName, "底子*")
	pAddToFanTable.iName = string.format("%s%d", pAddToFanTable.iName, pDiZi)
	
	if self.m_pGameRound.m_pPreRoundInfo.iBiXiaHu then
		-- 比下胡结算是胡牌总花数×2
		pHardHuaCount = pHardHuaCount * 2
		pSoftHuaCount = pSoftHuaCount * 2
		pDiZi = pDiZi * 2
	end

	pAddToFanTable.iFan = pAddToFanTable.iFan + pHardHuaCount
	pAddToFanTable.iFan = pAddToFanTable.iFan + pSoftHuaCount
	pAddToFanTable.iFan = pAddToFanTable.iFan + pDiZi

	return pAddToFanTable
end

function gameRuleJSNJJYZ:onGetCardTypeAndValue(pCardValue)
	pCardValue = pCardValue or 10
	return math.floor(pCardValue / 10), pCardValue % 10
end

return gameRuleJSNJJYZ