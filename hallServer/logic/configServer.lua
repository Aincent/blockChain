
local skynet = require("skynet")
local sharedata = require "skynet.sharedata"
local json = require("cjson")
local codecache = require "skynet.codecache"

local TAG = "ConfigServer"

local ConfigServer = {}

function ConfigServer:init(pGameCode)
	-- Log.d(TAG, "11111111111111121212121")
	self.m_pGoldRoomConfigTable = {}

	-- 配置
	self.m_pAnnouncementConfig = nil
	self.m_pShareActivityConfig = nil
	self.m_pAuditConfig = nil

	self.m_redisClientsMgr = require("utils/redisClientsMgr")
	self.m_redisClientsMgr:init()

	self.m_pServerConfig = require(onGetServerConfigFile(pGameCode))

	self.m_pHallServiceMgr = skynet.localname(".HallServiceMgr")

	-- self.m_pGameConfigFilePath = self.m_pServerConfig.iOtherConfigPath

	-- 初始化userInfoRedis
	self.m_redisClientsMgr:addRedisClient(DefineType.REDIS_ACTIVITY, self.m_pServerConfig.iGameIpPortConfig.iActivityRedisConfig)

	-- 启动定时器查看配置
	self.m_pScheduleMgr = require("utils/schedulerMgr")
	self.m_pScheduleMgr:init()

	local pCallback = self.onRefreshConfig
	self.m_pGetAnnouncementTimer = self.m_pScheduleMgr:register(pCallback, 30 * 60 * 1000, -1, 10 * 1000, self)
	self:onRefreshConfig()
end

function ConfigServer:onUpdatePlaytypeConfig(pPlaytypeConfig)
	-- 去掉一部分的数据
	pPlaytypeConfig.iGameRoundPath = nil
	pPlaytypeConfig.iGameRulePath = nil
	pPlaytypeConfig.iGameUserCardMap = nil
	self.m_pPlaytypeConfig = pPlaytypeConfig
end

function ConfigServer:onRefreshConfig()
	local pOtherConfigFile = self.m_pServerConfig.iOtherConfigPath
	-- Log.dump(TAG, self.m_pServerConfig, "self.m_pServerConfig")
	Log.d(TAG, "pOtherConfigFile = [%s]", pOtherConfigFile)
	package.loaded[pOtherConfigFile] = nil
	codecache.clear()

	self.m_pOtherConfig = require(pOtherConfigFile)
	Log.dump(TAG, self.m_pOtherConfig, "self.m_pOtherConfig")
end

------------------- socket --------------------
function ConfigServer:ClientUserGetConfig(pAgent, reqest)
	-- Log.dump(TAG, reqest, "reqest")
	if reqest.iConfigName and reqest.iParamData and self[reqest.iConfigName] then
		return self[reqest.iConfigName](self, reqest.iConfigName, pAgent, reqest.iParamData)
	end
end

function ConfigServer:GetFriendRoomConfig(pConfigname, pAgent, data)
	data = data and json.decode(data) or {}
	if not data or not data.iGameCode then
		return 
	end

	if self.m_pPlaytypeConfig then
		local name = "ServerUserGetConfig"
		local info = {}
		info.iConfigName = pConfigname
		info.iConfigData = json.encode(self.m_pPlaytypeConfig)
		skynet.call(self.m_pHallServiceMgr, "lua", "onSendPackage", pAgent, name, info)
	end
end

function ConfigServer:SetShareActivityData(pConfigname, pAgent, data)
	data = data and json.decode(data) or {}
	if not data or not data.iGameCode or not data.iUserId then
		return 
	end
	if not self.m_pOtherConfig or not self.m_pOtherConfig.iShareConfig then
		return
	end
	Log.dump(TAG, self.m_pOtherConfig.iShareConfig, "self.m_pOtherConfig.iShareConfig")
	local pOneDayReward = self.m_pOtherConfig.iShareConfig.iOneDayReward or 1
	local pUserId = data.iUserId
	local pKey = string.format("Share_Count_UserId_%d", pUserId)
	local pRet = self:onExecuteRedisCmd(DefineType.REDIS_ACTIVITY, "HMGET", pKey, "continue", "getCount", "isFirst", "lastTime")
	local pDataTime = onGetNowDataLastTime(os.date("*t", os.time()))
	if isTable(pRet) then
		-- 如果不是连续的
		pRet[1] = tonumber(pRet[1]) and tonumber(pRet[1]) + 1 or 1
		pRet[2] = tonumber(pRet[2]) and tonumber(pRet[2]) + pOneDayReward or pOneDayReward
		if pRet[4] then 
			local pOldDate = os.date("%x", tonumber(pRet[4]))
			local pNewDate = os.date("%x", os.time())
			-- 计算上次签到的最后时间
			if pOldDate == pNewDate then
				local pMsg = "您今天已经分享领过奖励了，本次分享没有钻石奖励。"
				self:onServerUserShowHints(pUserId, 0 , pMsg)
				return
			else
				-- 如果不是连续天
				if os.time() - tonumber(pRet[4]) > 24 * 60 * 60 then
					pRet[1] = 1
					pRet[2] = pOneDayReward
				end
			end
		end

		local pData = {}
		pData.iUserId = pUserId
		pData.RoomCardNum = pOneDayReward
		local pTable = not pRet[3] and self.m_pOtherConfig.iShareConfig.iFirstConfig or self.m_pOtherConfig.iShareConfig.iNormalConfig
		if pRet[1] >= 5 then
			pRet[1] = 0
			pRet[3] = 1
			pRet[2] = 0
			pData.RoomCardNum = pData.RoomCardNum + pTable.iRewardTable.RoomCardNum
			local pRet = self:onExecuteRedisCmd(DefineType.REDIS_ACTIVITY, "HMSET", pKey, "isFirst", pRet[3])
		end
		local pRet = self:onExecuteRedisCmd(DefineType.REDIS_ACTIVITY, "HMSET", pKey, "continue", pRet[1], "getCount", pRet[2], "lastTime", pDataTime)
		self:onDealShareRewardTable(pAgent, pConfigname, pData)
	end 
end

function ConfigServer:onServerUserShowHints(pUserId, pType, pMsg)
	local pAgent = skynet.call(self.m_pHallServiceMgr, "lua", "onGetAgentByUserId", pUserId)
	if not pAgent then return end
	local name = "ServerUserShowHints"
	local info = {}
	info.iShowType = pType
	info.iShowMsg = pMsg
	skynet.call(self.m_pHallServiceMgr, "lua", "onSendPackage", pAgent, name, info)
end

function ConfigServer:onDealShareRewardTable(pAgent, pConfigname, data)
	if not data or not data.iUserId then return end

	if data.RoomCardNum then
		local info = {
			iUserId = data.iUserId,
			iRoomCardNum = data.RoomCardNum,
		}
		local pHallServer = skynet.call(self.m_pHallServiceMgr, "lua", "onGetHallServerByUserId", info.iUserId)
		if pHallServer then
			local pRet = skynet.call(pHallServer, "lua", "onUpdateUserRoomCard", info)
		end
		self:onSendConfigData(pAgent, pConfigname, data)
	end
end

function ConfigServer:GetShareActivityConfig(pConfigname, pAgent, data)
	data = data and json.decode(data) or {}
	if not data or not data.iGameCode or not data.iUserId then
		return 
	end
	if not self.m_pOtherConfig or not self.m_pOtherConfig.iShareConfig then
		return
	end
	local pUserId = data.iUserId
	-- 加上自己的信息
	local pKey = string.format("Share_Count_UserId_%d", pUserId)
	local pRet = self:onExecuteRedisCmd(DefineType.REDIS_ACTIVITY, "HMGET", pKey, "continue", "getCount", "isFirst", "lastTime")
	if isTable(pRet) and pRet[3] then
		self.m_pOtherConfig.iShareConfig.iNormalConfig.iContinueNum = tonumber(pRet[1]) or 0
		self.m_pOtherConfig.iShareConfig.iNormalConfig.iGetCount = tonumber(pRet[2]) or 0
		self.m_pOtherConfig.iShareConfig.iNormalConfig.iIsFirst = 0
		self.m_pOtherConfig.iShareConfig.iNormalConfig.iTodayReward = 0
		if pRet[4] then 
			local pOldDate = os.date("%x", tonumber(pRet[4]))
			local pNewDate = os.date("%x", os.time())
			-- 计算上次签到的最后时间
			if pOldDate == pNewDate then
				self.m_pOtherConfig.iShareConfig.iNormalConfig.iTodayReward = 1
			else
				-- 如果不是连续天
				if os.time() - tonumber(pRet[4]) > 24 * 60 * 60 then
					self.m_pOtherConfig.iShareConfig.iNormalConfig.iContinueNum = 0
					self.m_pOtherConfig.iShareConfig.iNormalConfig.iGetCount = 0
					local pRet = self:onExecuteRedisCmd(DefineType.REDIS_ACTIVITY, "HMSET", pKey, "continue", 0, "getCount", 0)
				end
			end
		end
		self:onSendConfigData(pAgent, pConfigname, self.m_pOtherConfig.iShareConfig.iNormalConfig)
	elseif isTable(pRet) then
		self.m_pOtherConfig.iShareConfig.iFirstConfig.iContinueNum = pRet[1] or 0
		self.m_pOtherConfig.iShareConfig.iFirstConfig.iGetCount = pRet[2] or 0
		self.m_pOtherConfig.iShareConfig.iFirstConfig.iIsFirst = 1
		self.m_pOtherConfig.iShareConfig.iFirstConfig.iTodayReward = 0
		if pRet[4] then 
			local pOldDate = os.date("%x", tonumber(pRet[4]))
			local pNewDate = os.date("%x", os.time())
			-- 计算上次签到的最后时间
			if pOldDate == pNewDate then
				self.m_pOtherConfig.iShareConfig.iFirstConfig.iTodayReward = 1
			else
				-- 如果不是连续天
				if os.time() - tonumber(pRet[4]) > 24 * 60 * 60 then
					self.m_pOtherConfig.iShareConfig.iFirstConfig.iContinueNum = 0
					self.m_pOtherConfig.iShareConfig.iFirstConfig.iGetCount = 0
					local pRet = self:onExecuteRedisCmd(DefineType.REDIS_ACTIVITY, "HMSET", pKey, "continue", 0, "getCount", 0)
				end
			end
		end
		self:onSendConfigData(pAgent, pConfigname, self.m_pOtherConfig.iShareConfig.iFirstConfig)
	end
end

function ConfigServer:GetAuditConfig(pConfigname, pAgent, data)
	data = data and json.decode(data) or {}
	if not data or not data.iVersion then
		return 
	end
	local pVersion = nil
	local pOpen = 0
	data.iPlatform = tonumber(data.iPlatform) or DefineType.PLATFORM_IOS
	if self.m_pOtherConfig and self.m_pOtherConfig.iAuditConfig then
		if DefineType.PLATFORM_IOS == tonumber(data.iPlatform) then
			pVersion = self.m_pOtherConfig.iAuditConfig.iIosVersion
		elseif DefineType.PLATFORM_ANDROID == tonumber(data.iPlatform) then
			pVersion = self.m_pOtherConfig.iAuditConfig.iAndroidVersion
		elseif DefineType.PLATFORM_WINDOWS == tonumber(data.iPlatform) then
			pVersion = self.m_pOtherConfig.iAuditConfig.iWindowsVersion
		elseif DefineType.PLATFORM_MAC == tonumber(data.iPlatform) then
			pVersion = self.m_pOtherConfig.iAuditConfig.iMacVersion
		end
		if pVersion and pVersion <= data.iVersion then
			pOpen = 1
		end
	end
	local pConfigData = {}
	pConfigData.iOpen = pOpen
	self:onSendConfigData(pAgent, pConfigname, pConfigData)
end

function ConfigServer:onSendConfigData(pAgent, pConfigname, pConfigData)
	local name = "ServerUserGetConfig"
	local info = {}
	info.iConfigName = pConfigname
	info.iConfigData = json.encode(pConfigData)
	skynet.call(self.m_pHallServiceMgr, "lua", "onSendPackage", pAgent, name, info)
end

----------------------------------- redis ---------------------------------
function ConfigServer:onExecuteRedisCmd(redis, cmd, ...)
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

return ConfigServer