--[[
麻将编码如下:
11 ~ 19   [1~9]万
21 ~ 29   [1~9]筒
31 ~ 39   [1~9]条
41 ~ 44   [东,南,西,北]风
51 ~ 53   [红中,发财,白板]
61 ~ 68   [春,夏,秋,冬,梅,兰,菊,竹]
]]
local skynet = require "skynet"
local TAG = "mahjongPool"

local mahjongPool = {}

function mahjongPool:initMahjongPool(pCardTable, pUserCount, pGameRound)
	self.m_pMahjongPool = pCardTable
	self.m_pMaxCardCount = #self.m_pMahjongPool
	self.m_pGameRound = pGameRound
	self.m_pCurCount = 0

	self.m_pGameServiceMgr = skynet.localname(".GameServiceMgr")
	
	local pTableId = self.m_pGameRound:onGetTableId()
	self:onShuffleMahjongPool(pUserCount, pTableId)
	if not GLConfig:isFormalMode() then
		self:onStackCard(pUserCount)
	end
	return self
end

-- 测试服配牌测试
function mahjongPool:onStackCard(pUserCount)
	-- 读取Redis中的配置
	local pGameCode = self.m_pGameRound:onGetGameCode()
	local pLocalGameType = self.m_pGameRound:onGetGameTable():onGetLocalGameType()
	local pDealCardCount = self.m_pGameRound:onGetGameTable():onGetDealCardCount()
	local pkey = string.format("HandCardTable_%d_%d", pGameCode, pLocalGameType)
	local pRet = skynet.call(self.m_pGameServiceMgr, "lua", "onExecuteRedisCmd", DefineType.REDIS_CLUB, "Get", pkey)
	local pStackCardTable = onGetTableByJson(pRet)
	if not pStackCardTable or not pStackCardTable.iHandCardTable or not pStackCardTable.iDrawCardTable then return end
	Log.dump(TAG, pStackCardTable, "pStackCardTable")
	self.m_pStackCardTable = pStackCardTable
	for i = 1, math.min(#pStackCardTable.iHandCardTable, pUserCount) do
		for j = 1, pDealCardCount do
			local pCardValue = pStackCardTable.iHandCardTable[i][j]
			if pCardValue then
				local pIndex = (i - 1) * pDealCardCount + j
				for k = pIndex, #self.m_pMahjongPool do
					if self.m_pMahjongPool[k] == pCardValue then
						self.m_pMahjongPool[k] = self.m_pMahjongPool[pIndex]
						self.m_pMahjongPool[pIndex] = pCardValue
					end
				end
			end
		end
	end
	-- 还要把抓牌都放到最后，防止被用掉
	local pCardCount = 0
	for i = 1, math.min(#pStackCardTable.iDrawCardTable, pUserCount) do
		for _, kCardValue in pairs(pStackCardTable.iDrawCardTable[i]) do
			pCardCount = pCardCount + 1
			for j = #self.m_pMahjongPool, 1, -1 do
				if self.m_pMahjongPool[j] == kCardValue then
					self.m_pMahjongPool[j] = self.m_pMahjongPool[#self.m_pMahjongPool - pCardCount]
					self.m_pMahjongPool[#self.m_pMahjongPool - pCardCount] = kCardValue
				end
			end
		end
	end
end	

--洗牌
function mahjongPool:onShuffleMahjongPool(pUserCount, pTableId)
	local pSeed = pTableId * 1000000 + tonumber(tostring(os.time()):reverse():sub(1, 6))
	math.randomseed(pSeed)
	local swapIndex1, swapIndex2 = 1, 1
	for i = 1, 1000 do
		swapIndex1 = math.random(self.m_pMaxCardCount)
		swapIndex2 = math.random(self.m_pMaxCardCount)
		local pValue = self.m_pMahjongPool[swapIndex1]
		self.m_pMahjongPool[swapIndex1] = self.m_pMahjongPool[swapIndex2]
		self.m_pMahjongPool[swapIndex2] = pValue
	end
	-- 然后将牌一张一张的调整分开
	for i = 1, pUserCount do
		for j = 1, 13 do
			local pValue = self.m_pMahjongPool[(i - 1) * 13 + j]
			self.m_pMahjongPool[(i - 1) * 13 + j] = self.m_pMahjongPool[(j - 1) * pUserCount + 1]
			self.m_pMahjongPool[(j - 1) * pUserCount + 1] = pValue
		end
	end
end 

--发牌
function mahjongPool:dealCards(playerNum, mahjongNum)
	local dealCardMap = {}
	for i = 1, playerNum do
		local handCards = {}
		for j = 1, mahjongNum or 1 do
			handCards[#handCards + 1] = self:pop()
		end
		dealCardMap[#dealCardMap + 1] = handCards
	end

	return dealCardMap
end 

-- 抓牌
function mahjongPool:drawCard(pSeatId)
	-- 如果是抓牌，则要判断是否有测试服的配牌
	if pSeatId and self.m_pStackCardTable and self.m_pStackCardTable.iDrawCardTable then
		local pDrawCards = self.m_pStackCardTable.iDrawCardTable[pSeatId]
		if pDrawCards and #pDrawCards > 0 then
			local pCardValue = table.remove(pDrawCards, 1)
			for i = self.m_pCurCount + 1, #self.m_pMahjongPool do
				if self.m_pMahjongPool[i] == pCardValue then
					self.m_pMahjongPool[i] = self.m_pMahjongPool[self.m_pCurCount + 1]
					self.m_pMahjongPool[self.m_pCurCount + 1] = pCardValue
				end
			end
		end
	end
	return self:pop()
end

function mahjongPool:pop()
	self.m_pCurCount = self.m_pCurCount + 1
	if self.m_pCurCount > self.m_pMaxCardCount then return 0 end
	return self.m_pMahjongPool[self.m_pCurCount]
end 

function mahjongPool:onGetTop(pNum)
	local pIndex = #self.m_pMahjongPool - pNum + 1
	return self.m_pMahjongPool[pIndex] or 0
end 

--剩余张数
function mahjongPool:remainCard()
	if self.m_pMaxCardCount and self.m_pCurCount then
		return self.m_pMaxCardCount - self.m_pCurCount
	end
	return 0
end 

return mahjongPool