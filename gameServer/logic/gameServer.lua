
local skynet = require("skynet")
local sharedata = require "skynet.sharedata"
local json = require("cjson")

local TAG = "GameServer"

local GameServer = {}

function GameServer:init(pGameCode, pLevel)
	Log.d(TAG, "pGameCode[%s] pLevel[%s]", pGameCode, pLevel)
	self.m_pServerConfig = require(onGetServerConfigFile(pGameCode))
	self:initShareData(pGameCode, pLevel)

	-- 连接DB
	self.m_pDbClient = skynet.newservice("dbClient")
	local pRet = skynet.call(self.m_pDbClient, "lua", "init", self.m_pServerConfig.iGameIpPortConfig.iDatabaseConfig)

	self.m_pGameTableMap = {}

	self.m_pUserIdToGameTableMap = {}

	self.m_pGameServiceMgr = skynet.localname(".GameServiceMgr")
	self.m_pGoldFieldTableIdMap = {}
end

function GameServer:initShareData(pGameCode, pLevel)
	self.m_pGameRoomConfig = self.m_pServerConfig.iGameRoomConfig[pLevel]
	self.m_pGameRoomConfig.iGameCode = pGameCode
	self.m_pGameRoomConfig.iGameLevel = pLevel
	local pName = string.format("GameRoomConfig_Code[%s]_Level[%s]", pGameCode, pLevel)
	sharedata.new(pName, self.m_pGameRoomConfig)
	self.m_pGameRoomConfig = sharedata.query(pName)
end

function GameServer:onGameTableUpdateData(data)
	self.m_pGameTableMap[data.iTableId] = data
	for k, v in pairs(data.iUserTable) do
		self.m_pUserIdToGameTableMap[v] = data.iGameTable
	end
end

function GameServer:onGameTableDeleteData(data)
	self.m_pGameTableMap[data.iTableId] = nil
end

function GameServer:onGameTableDeleteGoldField(pGoldFieldId, pTableId)
	if not self.m_pGoldFieldTableIdMap[pGoldFieldId] then return end
	for kIndex, kTableId in pairs(self.m_pGoldFieldTableIdMap[pGoldFieldId]) do
		if kTableId == pTableId then
			table.remove(self.m_pGoldFieldTableIdMap[pGoldFieldId], kIndex)
			break
		end
	end
end

--清除没有开始牌局的房间
function GameServer:onGameTableClear()
	local pGameTableMap = clone(self.m_pGameTableMap)
	for k, v in pairs(pGameTableMap) do
		-- TODO:删除房间的时候如果已经有人在房间内
		if v.iTableStatus == 0 then
			pcall(skynet.call, v.iGameTable, "lua", "onDismissFriendBattleRoom")
		end
	end
end

--获取房间数量
function GameServer:onGateGameTableCount()
	local pGameTableCount = 0
	for k, v in pairs(self.m_pGameTableMap) do
		pGameTableCount = pGameTableCount + 1
	end

	return pGameTableCount
end

function GameServer:onGetGoldFieldTableId(pData)
	local pGoldFieldId = pData.iGoldFieldId
	Log.dump(TAG, self.m_pGoldFieldTableIdMap, "self.m_pGoldFieldTableIdMap")
	if not pGoldFieldId or not self.m_pGoldFieldTableIdMap[pGoldFieldId] then
		return
	end
	-- 找到该场次的房间
	for _, kTableId in pairs(self.m_pGoldFieldTableIdMap[pGoldFieldId]) do
		local kTableInfo = self.m_pGameTableMap[kTableId]
		if kTableInfo and kTableInfo.iUserCount < kTableInfo.iMaxUserCount and kTableInfo.iTableStatus == 0 then
			return kTableInfo.iGameTable
		end
	end
	local pStatus, pTableId = skynet.call(self.m_pGameServiceMgr, "lua", "onCreateOneTableId")
	if pStatus and pTableId and not self.m_pGameTableMap[pTableId] then
		local pGameTable = skynet.newservice("gameTableService", DefineType.RoomType_GlodField)
		local pRet = skynet.call(pGameTable, "lua", "init", skynet.self(), pTableId)
		local pRet = skynet.call(pGameTable, "lua", "onInitGlodFieldConfig", pData)
		self.m_pGoldFieldTableIdMap[pGoldFieldId][#self.m_pGoldFieldTableIdMap[pGoldFieldId] + 1] = pTableId
		return pGameTable
	end
end

function GameServer:onUpdateGoldFieldConfig(pGoldFieldConfig)
	Log.d(TAG, "onUpdateGoldFieldConfig")
	Log.dump(TAG, pGoldFieldConfig, "pGoldFieldConfig")
	if not self:isGoldFieldServer() then return end
	-- 和当前的进行对比
	-- for kGoldFieldId, _ in pairs(self.m_pGoldFieldTableIdMap) do
	-- 	local pIsExist = false
	-- 	for _, tConfig in pairs(pGoldFieldConfig.iGoldFieldTable) do
	-- 		if kGoldFieldId == tConfig.iGoldFieldId then 
	-- 			pIsExist = true
	-- 			break
	-- 		end
	-- 	end
	-- 	if not pIsExist then
	-- 		self.m_pGoldFieldTableIdMap[kGoldFieldId] = nil
	-- 	end
	-- end
	-- for _, tConfig in pairs(pGoldFieldConfig.iGoldFieldTable) do
	-- 	local pIsExist = false
	-- 	for kGoldFieldId, _ in pairs(self.m_pGoldFieldTableIdMap) do
	-- 		if kGoldFieldId == tConfig.iGoldFieldId then
	-- 			pIsExist = true
	-- 			break
	-- 		end
	-- 	end
	-- 	if not pIsExist then
	-- 		self.m_pGoldFieldTableIdMap[tConfig.iGoldFieldId] = {}
	-- 	end
	-- end
	-- 如果配置更新，则之前的旧房间无法匹配，一段时间后，房间没有人之后就会销毁
	self.m_pGoldFieldTableIdMap = {}
	for _, tConfig in pairs(pGoldFieldConfig.iGoldFieldTable) do
		self.m_pGoldFieldTableIdMap[tConfig.iGoldFieldId] = {}
	end
	for kGoldFieldId, _ in pairs(self.m_pGoldFieldTableIdMap) do
		Log.d(TAG, "kGoldFieldId[%s]", kGoldFieldId)
	end
end

function GameServer:onReceivePackage(userId, name, data)
	Log.d(TAG, "onReceivePackage userId[%s] name[%s] gameTable[%s]", userId, name, self.m_pUserIdToGameTableMap[userId])
	if self[name] then
		return self[name](self, userId, data)
	else
		if self.m_pUserIdToGameTableMap[userId] then
			return skynet.call(self.m_pUserIdToGameTableMap[userId], "lua", "onReceivePackage", userId, name, data)
		end
	end
end

function GameServer:ClientUserCreateFriendRoom(userId, data)
	if not self:isFriendBattleServer() then return end
	local pStatus, pTableId = skynet.call(self.m_pGameServiceMgr, "lua", "onCreateOneRoomId", skynet.self(), data.iClubId, data.iPlayId)
	Log.d(TAG, "pTableId[%s]", pTableId)
	-- 开房成功，直接进房间
	if pStatus and pTableId then
		data.iUserId = userId
		data.iReady = 0
		local pGameTable
		if self.m_pGameTableMap[pTableId] then
			pGameTable = self.m_pGameTableMap[pTableId].iGameTable
		else
			pGameTable = skynet.newservice("gameTableService", DefineType.RoomType_Friend)
		end

		if pcall(skynet.call, pGameTable, "lua", "init", skynet.self(), pTableId) and 
			pcall(skynet.call, pGameTable, "lua", "onInitFriendBattleConfig", data) then
			local pIsOk, pStatus = pcall(skynet.call, pGameTable, "lua", "onClientCmdLoginGame", data, userId)
			Log.d(TAG, "pIsOk[%s], pStatus[%s]", pIsOk, pStatus)
			if not pIsOk then
				if not data.iServerAuto then
					local pMsg = "创建房间失败！"
					self:onServerUserShowHints(userId, 0, pMsg)
				end
				local pRet = skynet.call(pGameTable, "lua", "onDismissFriendBattleRoom")
			else
				return pStatus
			end
		else
			if not data.iServerAuto then
				local pMsg = "创建房间失败！"
				self:onServerUserShowHints(userId, 0, pMsg)
			end
			local pRet = skynet.call(pGameTable, "lua", "onDismissFriendBattleRoom")
		end
	end
end

function GameServer:ClientUserLoginGame(pUserId, pData)
	-- 如果是金币场
	if self:isGoldFieldServer() then
		local pGameTable = self:onGetGoldFieldTableId(pData)
		if not pGameTable then return end
		return skynet.call(pGameTable, "lua", "onClientCmdLoginGame", pData, pUserId)
	elseif self:isFriendBattleServer() then
		-- Log.dump(TAG, self.m_pGameTableMap, "self.m_pGameTableMap")
		if pData.iTableId and pData.iTableId > 0 then
			local pInfo = self.m_pGameTableMap[pData.iTableId]
			if not pInfo then
				local pMsg = "您要进入的房间已经解散！"
				self:onServerUserShowHints(pUserId, 0, pMsg)
				return
			end
			if pInfo.iUserCount < pInfo.iMaxUserCount then
				return skynet.call(pInfo.iGameTable, "lua", "onClientCmdLoginGame", pData, pUserId)
			else
				local pMsg = "您要进入的房间人数已满！"
				self:onServerUserShowHints(pUserId, 0, pMsg)
			end
		end 
	end
end

function GameServer:onServerUserShowHints(pUserId, pType, pMsg)
	local name = "ServerUserShowHints"
	local info = {}
	info.iShowType = pType
	info.iShowMsg = pMsg

	pcall(skynet.call, self.m_pGameServiceMgr, "lua", "onSendPackageToHallServiceMgr", "onSendPackage",pUserId, name, info)
end

function GameServer:onDisConnect(pUserId)
	Log.d(TAG, "onDisConnect self.m_pUserIdToGameTableMap[%s] = [%s]", pUserId, self.m_pUserIdToGameTableMap[pUserId])
	if not pUserId then return end
	if self.m_pUserIdToGameTableMap[pUserId] then
		return skynet.call(self.m_pUserIdToGameTableMap[pUserId], "lua", "onDisConnect", pUserId)
	end
end

function GameServer:onUserReconnect(pUserId)
	-- 查找该server上有没有该玩家
	Log.d(TAG, "onUserReconnect pUserId[%s]", pUserId)
	if self.m_pUserIdToGameTableMap[pUserId] then
		local pRet = skynet.call(self.m_pUserIdToGameTableMap[pUserId], "lua", "onUserReconnect", pUserId)
		return true
	end
end

function GameServer:ClientUserDismissOtherBattleRoom(pUserId, data)
	local pGameTable = self:onGetGameTableByTableId(data.iTableId)
	if pGameTable and pGameTable > 0 then
		-- 代开房间解散
		local pRet = skynet.call(pGameTable, "lua", "onDismissFriendBattleRoom", 1)
	end
end

function GameServer:ClientUserForcedDismissClubBattleRoom(pUserId, data)
	local pGameTable = self:onGetGameTableByTableId(data.iTableId)
	if pGameTable and pGameTable > 0 then
		-- 代开房间解散
		local pRet = skynet.call(pGameTable, "lua", "onForcedDismissFriendBattleRoom", pUserId)
	end
end

function GameServer:onGetGameTableByTableId(tableId)
	local data = self.m_pGameTableMap[tableId]
	if data then
		return data.iGameTable
	end
end

function GameServer:isFriendBattleServer()
	return self.m_pGameRoomConfig.iRoomType == DefineType.RoomType_Friend
end

function GameServer:isGoldFieldServer()
	return self.m_pGameRoomConfig.iRoomType == DefineType.RoomType_GlodField
end

function GameServer:onGetGameCodeAndLevel()
	return self.m_pGameRoomConfig.iGameCode, self.m_pGameRoomConfig.iGameLevel
end

function GameServer:onGetGameServerOnlineAndPlay()
	local pOnlineAndPlay = {
		iOnlineCount = 0,
		iPlayCount = 0,		
	}
	Log.dump(TAG, self.m_pGameTableMap, "self.m_pGameTableMap")
	for _, kGameTableData in pairs(self.m_pGameTableMap) do
		if kGameTableData.iTableStatus and 1 == kGameTableData.iTableStatus then
			pOnlineAndPlay.iPlayCount = pOnlineAndPlay.iPlayCount + kGameTableData.iUserCount
			pOnlineAndPlay.iOnlineCount = pOnlineAndPlay.iOnlineCount + kGameTableData.iUserCount
		else
			pOnlineAndPlay.iOnlineCount = pOnlineAndPlay.iOnlineCount + kGameTableData.iUserCount
		end
	end
	return pOnlineAndPlay
end

function GameServer:onUpdateUserRoomCard(info)
	-- 直接进行运算更新,少一次请求mysql，而且避免多线程的下并发问题
	local sqlStr = string.format("update Mahjong_UserInfo set RoomCardNum=RoomCardNum+%d where UserId=%d", info.iRoomCardNum, info.iUserId)
	local pRet = skynet.call(self.m_pDbClient, "lua", "onExecute", sqlStr)

	local sqlStr = string.format("select * from Mahjong_UserInfo where UserId=%d", info.iUserId)
	local pRet = skynet.call(self.m_pDbClient, "lua", "onExecute", sqlStr)
	if isTable(pRet) and #pRet > 0 then
		self:onSaveUserInfoToRedis(pRet[1])
		self:onServerBCUserInfoChange(pRet[1])
		return true
	end
	return false
end

function GameServer:onUpdateUserMoney(info)
	-- 直接进行运算更新,少一次请求mysql,而且避免多线程的下并发问题
	local sqlStr = string.format("update Mahjong_UserInfo set Money=Money+%d where UserId=%d", info.iTurnMoney, info.iUserId)
	local pRet = skynet.call(self.m_pDbClient, "lua", "onExecute", sqlStr)

	local sqlStr = string.format("select * from Mahjong_UserInfo where UserId=%d", info.iUserId)
	local pRet = skynet.call(self.m_pDbClient, "lua", "onExecute", sqlStr)
	if isTable(pRet) and #pRet > 0 then
		self:onSaveUserInfoToRedis(pRet[1])
		self:onServerBCUserInfoChange(pRet[1])
		return true
	end
	return false
end

function GameServer:onServerBCUserInfoChange(pUserInfo)
	if not pUserInfo then return end
	local name = "ServerBCUserInfoChange"
	local info = {}
	info.iUserId = pUserInfo.UserId
	info.iUserInfo = json.encode({
			UserId = pUserInfo.UserId,
			RoomCardNum = pUserInfo.RoomCardNum,
			Money = pUserInfo.Money,
		})

	pcall(skynet.call, self.m_pGameServiceMgr, "lua", "onSendPackageToHallServiceMgr", "onSendPackage",pUserInfo.UserId, name, info)
end

-- 将用户信息保存到redis
function GameServer:onSaveUserInfoToRedis(pUserInfo)
	local pKey = string.format("UserInfo_UserId_%s", pUserInfo.UserId)
	pUserInfo = json.encode(pUserInfo)
	self:onExecuteRedisCmd(DefineType.REDIS_USERINFO, "SET", pKey, pUserInfo)
end

-- 获取用户是否在当前俱乐部
function GameServer:onCheckUserIdInClub(pUserId, pClubId)
	local sqlStr = string.format("select count(*) from club_mapping where user_id=%d and club_id=%d", pUserId, pClubId)
	local pRet = skynet.call(self.m_pDbClient, "lua", "onExecute", sqlStr)
	if isTable(pRet) and #pRet >= 1 then
		if pRet[1]["count(*)"] and pRet[1]["count(*)"] >= 1 then
			return true
		end
	end 
	return false
end

function GameServer:onExecuteRedisCmd(redis, ...)
	return skynet.call(self.m_pGameServiceMgr, "lua", "onExecuteRedisCmd", redis, ...)
end

return GameServer