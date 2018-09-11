local json = require("cjson")
local TAG = "GameUser"
local GameUser = class()

function GameUser:ctor(data, userId, seatId)
	self.m_pUserId = userId
	self.m_pSeatId = seatId
	-- self.m_pSocketfd = socketfd

	self.m_pIsRobot = 0

	self.m_pReady = 0
	self.m_pNickName = ""
	self.m_pMoney = 0
	self.m_pWinTimes = 0
	self.m_pLoseTimes = 0
	self.m_pDrawTimes = 0
	self.m_pClientIp = ""
	self.m_pClientVersion = 0
	self.m_pRoomCardCount = 0
	self.m_pUserInfo = {}
	self.m_pUserInfoStr = ""
	self.m_pHeadUrl = ""
	self.m_pIsAgent = 0
	self.m_pLoginCount = 0
	self.m_pSex = 0
	self.m_pIsAi = 0
	self.m_pLoginTimeStamp = os.time()

	self:onSetUserInfo(data)

	-- 玩牌信息
	self.m_pHandCardMap = {}
	self.m_pBlockCardMap = {}
	self.m_pOutCardMap = {}
	self.m_pDrawCardMap = {}

	self.m_pTurnMoney = 0
	self.m_pIsOnline = 0

	self.m_pHuInfo = nil

	self.m_pIsGuoHuInfo = {}

	self.m_pIsHu = 0
	self.m_pDingQue = 0
	-- 卡二条(报听)
	self.m_pIsBaoTing = 0
	-- 卡心五(廊起)
	self.m_pLangQiCardTable = {}
	-- 血战
	self.m_pHuanCardTable = {}
	-- 扎金花 0x0表示正常 0x1表示看了牌 0x2表示弃牌 0x4表示比牌赢 0x8表示比牌输
	self.m_pLookOrQiCard = 0
	-- 听牌信息
	self.m_pTingCardTable = {}
	-- 给中山，胡牌的时候有没有鬼牌
	self.m_pIsHasGuiCard = false
end

function GameUser:dtor()
	-- delete(self.m_ppGameRoundUserInfo)
	-- self.m_ppGameRoundUserInfo = nil
end

function GameUser:onSetUserInfo(data)
	Log.dump(TAG, data, "GameUserData")
	self.m_pMoney = data.iMoney or 0
	self.m_pIsAgent = data.iIsAgent or 0
	local pIsOk, pUserInfo = pcall(json.decode, data.iUserInfoStr or "{}")
	self.m_pUserInfo = pIsOk and pUserInfo or {}
	self.m_pUserInfoStr = data.iUserInfoStr or ""
	self.m_pClientIp = data.iClientIp or ""
	self.m_pIsRobot = data.iIsRobot or 0
	self.m_pReady = data.iReady or 0
	self.m_pNickName = data.iNickName or ""
	self.m_pWinTimes = data.iWinTimes or 0
	self.m_pLoseTimes = data.iLoseTimes or 0
	self.m_pDrawTimes = data.iDrawTimes or 0
	-- 设置用户名，版本号, 胜负平值
	self.m_pClientVersion = self.m_pUserInfo.iClientVersion or ""
	self.m_pHeadUrl = self.m_pUserInfo.headUrl or ""
	self.m_pSex = self.m_pUserInfo.sex or ""
end

function GameUser:onGetNickName()
	return self.m_pNickName
end

function GameUser:onGetHeadUrl()
	return self.m_pHeadUrl
end

function GameUser:onGetSex()
	return self.m_pSex
end

function GameUser:onGetClientIp()
	return self.m_pClientIp
end

function GameUser:onGetUserId()
	return self.m_pUserId
end

function GameUser:onGetSeatId()
	return self.m_pSeatId
end

function GameUser:onSetReady(value)
	self.m_pReady = value and value or self.m_pReady
end

function GameUser:onGetReady()
	return self.m_pReady
end

function GameUser:onSetMoney(value)
	self.m_pMoney = value and value or self.m_pMoney
end

function GameUser:onGetMoney()
	return self.m_pMoney
end

function GameUser:onSetIsOnline(value)
	self.m_pIsOnline = value and value or self.m_pIsOnline
end

function GameUser:onGetIsOnline()
	return self.m_pIsOnline
end

function GameUser:onSetTurnMoney(value)
	self.m_pTurnMoney = value and value or self.m_pTurnMoney
end

function GameUser:onGetTurnMoney()
	return self.m_pTurnMoney
end

function GameUser:onSetLoginCount(value)
	self.m_pLoginCount = value or 0
end

function GameUser:onGetLoginCount()
	return self.m_pLoginCount
end

function GameUser:onGetIsAi()
	return self.m_pIsAi
end

function GameUser:onSetIsAi(value)
	self.m_pIsAi = value
end

function GameUser:onGetLoginTimeStamp()
	return self.m_pLoginTimeStamp
end

function GameUser:onSetLoginTimeStamp(value)
	self.m_pLoginTimeStamp = value
end

function GameUser:onGetHandCardMap()
	return self.m_pHandCardMap
end

function GameUser:onSetHandCardMap(pHandCardMap)
	self.m_pHandCardMap = pHandCardMap
end

function GameUser:onGetBlockCardMap()
	return self.m_pBlockCardMap
end

function GameUser:onSetBlockCardMap(pBlockCardMap)
	self.m_pBlockCardMap = pBlockCardMap
end

function GameUser:onGetOutCardMap()
	return self.m_pOutCardMap
end

function GameUser:onGetDrawCardMap()
	return self.m_pDrawCardMap
end

function GameUser:onGetIsAgent()
	return self.m_pIsAgent or 0
end

function GameUser:onSetIsHu(value)
	self.m_pIsHu = value
end

function GameUser:onGetIsHu()
	return self.m_pIsHu
end

function GameUser:onSetDingQue(value)
	self.m_pDingQue = value
end

function GameUser:onGetDingQue()
	return self.m_pDingQue or 0
end

function GameUser:onSetIsBaoTing(value)
	self.m_pIsBaoTing = value
end

function GameUser:onGetIsBaoTing()
	return self.m_pIsBaoTing
end

function GameUser:onSetLangQiCardTable(value)
	self.m_pLangQiCardTable = value
end

function GameUser:onGetLangQiCardTable()
	return self.m_pLangQiCardTable
end

function GameUser:onSetHuanCardTable(value)
	self.m_pHuanCardTable = value
end

function GameUser:onGetHuanCardTable()
	return self.m_pHuanCardTable or {}
end

function GameUser:onSetHuInfo(value)
	self.m_pHuInfo = value
end

function GameUser:onGetHuInfo()
	return self.m_pHuInfo
end

function GameUser:onSetLookOrQiCard(value)
	self.m_pIsLookCard = value or 0
end

function GameUser:onGetLookOrQiCard()
	return self.m_pIsLookCard
end

function GameUser:onSetTingCardTable(value)
	self.m_pTingCardTable = value or {}
end

function GameUser:onGetTingCardTable()
	return self.m_pTingCardTable
end

function GameUser:onSetIsHasGuiCard(value)
	self.m_pIsHasGuiCard = value or false
end

function GameUser:onGetIsHasGuiCard()
	return self.m_pIsHasGuiCard
end

function GameUser:onSetIsGuoHuInfo(value)
	self.m_pIsGuoHuInfo = value or {}
end

function GameUser:onGetIsGuoHuInfo()
	return self.m_pIsGuoHuInfo
end

function GameUser:onClearOneRound()
	self:onSetReady(0)
	self:onSetTurnMoney(0)
	self:onSetIsHu(0)
	self:onSetDingQue(0)
	self:onSetIsBaoTing(0)
	self:onSetHuInfo(nil)
	self:onSetLookOrQiCard(0)
	self:onSetIsHasGuiCard(false)
	self:onSetIsGuoHuInfo({})
	self:onSetIsAi(0)
	
	self.m_pHandCardMap = {}
	self.m_pBlockCardMap = {}
	self.m_pOutCardMap = {}
	self.m_pDrawCardMap = {}

	self.m_pHuanCardTable = {}
	self.m_pLangQiCardTable = {}
	self.m_pTingCardTable = {}
end

return GameUser