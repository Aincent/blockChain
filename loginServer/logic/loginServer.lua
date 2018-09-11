local skynet = require("skynet")
local json = require("cjson")
local queue = require("skynet.queue")

local cs = queue()

local TAG = "LoginServer"

local LoginServer = {}

local loginUserTypeMap = {
	GuestLogin = 0,
	WeiXinLogin = 1,
	QQLogin = 2,
	WeiBoLogin = 3,
}

function LoginServer:init(pGameCode)
	self.m_pLoginUserDataMap = {}

	self.m_redisClientsMgr = require("utils/redisClientsMgr")
	self.m_redisClientsMgr:init()

	self.m_pServerConfig = require(onGetServerConfigFile(pGameCode))

	self.m_pLoginServiceMgr = skynet.localname(".LoginServiceMgr")

	-- 初始化userInfoRedis
	self.m_redisClientsMgr:addRedisClient(DefineType.REDIS_USERINFO, self.m_pServerConfig.iGameIpPortConfig.iUserRedisConfig)

	-- 连接DB
	self.m_pDbClient = skynet.newservice("dbClient")
	local pRet = skynet.call(self.m_pDbClient, "lua", "init", self.m_pServerConfig.iGameIpPortConfig.iDatabaseConfig)
end

function LoginServer:onUpdateUserMoney(info)
	-- 直接进行运算更新,少一次请求mysql,而且避免多线程的下并发问题
	local sqlStr = string.format("update UserInfo set Money=Money+%d where UserId=%d", info.iTurnMoney, info.iUserId)
	local pRet = skynet.call(self.m_pDbClient, "lua", "onExecute", sqlStr)

	local sqlStr = string.format("select * from UserInfo where UserId=%d", info.iUserId)
	local pRet = skynet.call(self.m_pDbClient, "lua", "onExecute", sqlStr)
	if isTable(pRet) and #pRet > 0 then
		self:onSaveUserInfoToRedis(pRet[1])
		self:onServerBCUserInfoChange(pRet[1])
		return true
	end
	return false
end

function LoginServer:onServerBCUserInfoChange(pUserInfo)
	if not pUserInfo then return end

	local name = "ServerBCUserInfoChange"
	local info = {}
	info.iUserId = pUserInfo.UserId
	info.iUserInfo = json.encode({
			UserId = pUserInfo.UserId,
			Money = pUserInfo.Money,
		})

	skynet.call(self.m_pLoginServiceMgr, "lua", "onSendPackage", pUserInfo.UserId, name, info)
end

----------------------------- 网络通讯 ---------------------------
function LoginServer:ClientUserLoginHall(request)
	-- Log.dump(TAG, request, "request")
	local pUserLoginInfo = json.decode(request.iUserInfo)
	if not pUserLoginInfo or not pUserLoginInfo.UserType then
		return
	end
	pUserLoginInfo.UserType = tonumber(pUserLoginInfo.UserType)
	local pUserInfo = nil
	-- 不同账号不同处理
	if loginUserTypeMap.GuestLogin == pUserLoginInfo.UserType then
		pUserInfo = self:onDealGuestLogin(pUserLoginInfo)
	elseif loginUserTypeMap.WeiXinLogin == pUserLoginInfo.UserType then
		pUserInfo = self:onDealWeiXinLogin(pUserLoginInfo)
	end
	if pUserInfo then
		-- 要判断是否封号
		if tonumber(pUserInfo.IsForbid) and tonumber(pUserInfo.IsForbid) > 0 then
			local info = {}
			info.iStatus = -1
			info.iLoginMsg = string.format("登陆失败，您的账号(ID：%s)异常！", pUserInfo.UserId)
			info.iUserInfo = json.encode({iServerVersion = GLConfig:onGetServerVersion()})
			return nil, info
		end
		pUserInfo.ClientIp = request.ClientIp
		local info = {}
		info.iStatus = 0
		info.iLoginMsg = "恭喜你，登陆成功，欢迎来到麻将世界！"
		pUserInfo.iServerVersion = GLConfig:onGetServerVersion()
		info.iUserInfo = json.encode(pUserInfo)

		self:onReportUserLogin(pUserInfo.UserId)
		return pUserInfo.UserId, info
	else
		local info = {}
		info.iStatus = -1
		info.iLoginMsg = "登陆失败！"
		info.iUserInfo = json.encode({iServerVersion = GLConfig:onGetServerVersion()})
		return nil, info
	end
end

------------------- 内部函数 -------------------
--[[
	游客登陆
]]
function LoginServer:onDealGuestLogin(pUserLoginInfo)
	if not pUserLoginInfo.MachineId then return end
	local PlatformId = string.format("%d_%s", pUserLoginInfo.UserType, pUserLoginInfo.MachineId)
	Log.d(TAG, "PlatformId[%s]", PlatformId)
	local sqlStr = string.format("select * from UserInfo where PlatformId='%s'", PlatformId)
	local pRet = skynet.call(self.m_pDbClient, "lua", "onExecute", sqlStr)
	if isTable(pRet) and #pRet <= 0 then
		-- 用户注册
		pUserLoginInfo.PlatformId = PlatformId
		return self:onUserRegister(pUserLoginInfo)
	elseif isTable(pRet) and #pRet > 0 then
		return self:onUserLogin(pUserLoginInfo, pRet[1])
	end
end

--!
--! @brief      微信登陆
--!
--! @param      pUserLoginInfo  The user login information
--!
--! @return     用户信息
--!
function LoginServer:onDealWeiXinLogin(pUserLoginInfo)
	if not pUserLoginInfo.unionid then return end
	local PlatformId = string.format("%d_%s", pUserLoginInfo.UserType, pUserLoginInfo.unionid)
	Log.d(TAG, "PlatformId[%s]", PlatformId)
	local sqlStr = string.format("select * from UserInfo where PlatformId=\"%s\"", PlatformId)
	local pRet = skynet.call(self.m_pDbClient, "lua", "onExecute", sqlStr)

	pUserLoginInfo.Sex = pUserLoginInfo.sex or 0
	pUserLoginInfo.NickName = pUserLoginInfo.nickname or ""
	pUserLoginInfo.NickName = string.gsub(pUserLoginInfo.NickName, "\"", "")
	pUserLoginInfo.NickName = string.gsub(pUserLoginInfo.NickName, "\\", "")
	pUserLoginInfo.NickName = string.gsub(pUserLoginInfo.NickName, "\'", "")
	pUserLoginInfo.NickName = onGetNotEmojiName(pUserLoginInfo.NickName)
	if isTable(pRet) and #pRet <= 0 then
		-- 用户注册
		pUserLoginInfo.PlatformId = PlatformId
		return self:onUserRegister(pUserLoginInfo)
	elseif isTable(pRet) and #pRet > 0 then
		return self:onUserLogin(pUserLoginInfo, pRet[1])
	end
end

local UserName = {
	"李", "黄", "陈", "花", "易", "居", "池", "王", "谢", "游", "真", "善", "美",
}

local UserMing = {
	
}

-- 用户注册
function LoginServer:onUserRegister(pUserLoginInfo)
	-- 获取配置
	local pPlaytypeConfig = skynet.call(self.m_pLoginServiceMgr, "lua", "onGetPlaytypeConfig")
	if not pPlaytypeConfig or not pPlaytypeConfig.iGameRegisterTable then
		Log.e(TAG, "onUserRegister, pPlaytypeConfig is not valid!")
		Log.edump(TAG, pPlaytypeConfig, "pPlaytypeConfig")
		return 
	end
	local pUserInfo = {}
	-- 生成默认的信息
	pUserInfo.UserType = pUserLoginInfo.UserType
	pUserInfo.Sex = pUserLoginInfo.Sex or 0
	pUserInfo.MachineId = pUserLoginInfo.MachineId
	pUserInfo.PlatformId = pUserLoginInfo.PlatformId
	pUserInfo.Level = 0
	pUserInfo.Money = pPlaytypeConfig.iGameRegisterTable.Money or 3000
	math.randomseed(tostring(os.time()):reverse():sub(1, 6))
	pUserInfo.NickName = pUserLoginInfo.NickName or UserName[math.random(#UserName)]
	pUserInfo.RegisterTime = os.time()
	pUserInfo.LastLoginTime = os.time()
	pUserInfo.HeadUrl = pUserLoginInfo.HeadUrl or ""

	local sqlStr = string.format("insert into UserInfo(NickName,UserType,MachineId,PlatformId,Sex,Level,Money,RegisterTime,LastLoginTime,HeadUrl) values(\"%s\",'%s','%s','%s','%s','%s','%s','%s','%s','%s');", 
			pUserInfo.NickName, pUserInfo.UserType, pUserInfo.MachineId, pUserInfo.PlatformId, pUserInfo.Sex, pUserInfo.Level, pUserInfo.Money, pUserInfo.RegisterTime, pUserInfo.LastLoginTime, pUserInfo.HeadUrl)

	local pRet = skynet.call(self.m_pDbClient, "lua", "onExecute", sqlStr)
	if not pRet then
		return nil
	end
	local sqlStr = string.format("select UserId from UserInfo where PlatformId='%s'", pUserInfo.PlatformId)
	local pRet = skynet.call(self.m_pDbClient, "lua", "onExecute", sqlStr)
	if isTable(pRet) and #pRet > 0 then
		pUserInfo.UserId = tonumber(pRet[1].UserId)
		if not pUserInfo.UserId or pUserInfo.UserId <= 0 then 
			return nil
		end
	else
		return nil
	end

	self:onReportUserRegister(pUserInfo.UserId)
	-- 信息保存到redis中
	self:onSaveUserInfoToRedis(pUserInfo)
	return pUserInfo
end

-- 用户登录
function LoginServer:onUserLogin(pUserLoginInfo, pUserInfo)
	-- 如果这里有该玩家的信息,则直接在这里更新
	pUserInfo.NickName = pUserLoginInfo.NickName or pUserInfo.NickName
	Log.d(TAG, "pUserInfo.NickName[%s]", pUserInfo.NickName)
	pUserInfo.Sex = pUserLoginInfo.Sex or pUserInfo.Sex
	pUserInfo.LastLoginTime = os.time()
	pUserInfo.HeadUrl = pUserLoginInfo.HeadUrl or ""
	local sqlStr = string.format("update UserInfo set MachineId='%s',NickName=\"%s\",Sex=%s,LastLoginTime='%s',HeadUrl='%s'  where UserId=%d", pUserLoginInfo.MachineId, pUserInfo.NickName, pUserInfo.Sex, pUserInfo.LastLoginTime, pUserInfo.HeadUrl, pUserInfo.UserId)
	local pRet = skynet.call(self.m_pDbClient, "lua", "onExecute", sqlStr)
	self:onSaveUserInfoToRedis(pUserInfo)
	return pUserInfo
end

----------------------------------- redis ---------------------------------
function LoginServer:onExecuteRedisCmd(redis, cmd, ...)
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

-- 将用户信息保存到redis
function LoginServer:onSaveUserInfoToRedis(pUserInfo)
	local pKey = string.format("UserInfo_UserId_%s", pUserInfo.UserId)
	pUserInfo = json.encode(pUserInfo)
	self:onExecuteRedisCmd(DefineType.REDIS_USERINFO, "SET", pKey, pUserInfo)
end

function LoginServer:onDeleteUserInfoRedis(pUserId)
	local pKey = string.format("UserInfo_UserId_%s", pUserId)
	self:onExecuteRedisCmd(DefineType.REDIS_USERINFO, "DEL", pKey)
end

------------------------------------- reportServer ------------------------------------------
function LoginServer:onReportUserLogin(pUserId)
	local pReportServer = skynet.call(self.m_pLoginServiceMgr, "lua", "onGetReportServer")
	if pReportServer then
		skynet.send(pReportServer, "lua", "onDealDAU", pUserId)
	end
end

function LoginServer:onReportUserRegister(pUserId)
	local pReportServer = skynet.call(self.m_pLoginServiceMgr, "lua", "onGetReportServer")
	if pReportServer then
		skynet.send(pReportServer, "lua", "onDealNewAddUser", pUserId)
	end
end

return LoginServer