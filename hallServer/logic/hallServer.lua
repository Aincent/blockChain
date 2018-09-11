local skynet = require("skynet")
local cluster = require "skynet.cluster"
local queue = require("skynet.queue")
local sprotoloader = require "sprotoloader"
local skynetMgr    = require "skynet.manager"
local json = require("cjson")

local cs = queue()

local TAG = "HallServer"

local HallServer = {}

function HallServer:init(pGameCode)
	self.m_pGameCode = pGameCode
	self.m_pHallServiceMgr = skynet.localname(".HallServiceMgr")
end

function HallServer:onDisConnect(pAgent, pClearRedis)
	Log.d(TAG, "HallServer onDisConnect pAgent[%s]", pAgent)
	
	local pUserId = self:onGetUserIdByAgent(pAgent)
	if not pUserId then return end
	-- 清空该玩家的信息
	local pRet = skynet.call(self.m_pHallServiceMgr, "lua", "onDeleteHallServerByUserId", pUserId, pAgent)
	if not pRet then 
		Log.e(TAG, "onDisConnect 无法清除pAgent[%s] pUserId[%s]", pAgent, pUserId)
		return 
	end

	if pClearRedis then
		local pRet = skynet.call(self.m_pHallServiceMgr, "lua", "onDeleteUserInfoRedis", pUserId)
	end
end

function HallServer:onKickOffUserId(pUserId, pAgent)
	-- 如果有UserId 和 Agent的映射关系
	local tAgent = self:onGetAgentByUserId(pUserId)
	Log.d(TAG, "onKickOffUserId pUserId[%s] tAgent[%s] pAgent[%s]", pUserId, tAgent, pAgent)
	if tAgent and tAgent ~= pAgent then
		Log.d(TAG, "onKickOffUserId tAgent[%s]", tAgent)
		local name = "ServerUserKickOff"
		local info = {}
		info.iKickMsg = "您掉线了，请重新登录！"
		skynet.call(self.m_pHallServiceMgr, "lua", "onSendPackage", tAgent, name, info)
		skynet.call(self.m_pHallServiceMgr, "lua", "onCloseAgent", tAgent)
	end
end

function HallServer:onGetUserIdByAgent(pAgent)
	Log.d(TAG, "onGetUserIdByAgent pAgent[%s]", pAgent)
	return skynet.call(self.m_pHallServiceMgr, "lua", "onGetUserIdByAgent", pAgent)
end

function HallServer:onGetAgentByUserId(pUserId)
	return skynet.call(self.m_pHallServiceMgr, "lua", "onGetAgentByUserId", pUserId)
end

function HallServer:onGetGameServerByUserId(pUserId)
	return skynet.call(self.m_pHallServiceMgr, "lua", "onGetGameServerByUserId", pUserId)
end

function HallServer:onUpdateUserMoney(info)
	return skynet.call(self.m_pHallServiceMgr, "lua", "onUpdateUserMoney", info)
end

----------------------------------------- socket -------------------------------------
function HallServer:onReceivePackage(agent, name, request)
	local pUserId = self:onGetUserIdByAgent(agent)
	Log.d(TAG, "onReceivePackage agent[%s] name[%s] pUserId[%s]", agent, name, pUserId)
	if self[name] then
		self[name](self, agent, name, request)
	else
		Log.e(TAG, "onReceivePackage pUserId[%s] name[%s] error ", pUserId, name)
		--找不到userid就直接关闭这个连接
		skynet.call(self.m_pHallServiceMgr, "lua", "onCloseAgent", agent)
	end
end

--!
--! @brief      玩家登陆大厅
--!
--! @param      agent    The agent
--! @param      name     The name
--! @param      request  The request
--!
--! @return     { description_of_the_return_value }
--!
function HallServer:ClientUserLoginHall(agent, name, request)
	-- 如果当前agent已经绑定了UserId，表示已经登录，则抛弃该登录包
	local aUserId = self:onGetUserIdByAgent(agent)
	if aUserId and aUserId > 0 then return end
	request.ClientIp = skynet.call(self.m_pHallServiceMgr, "lua", "onGetClientIp", agent)
	local pUserId, info = skynet.call(self.m_pHallServiceMgr, "lua", name, request)
	if not info then return end
	local resName = "ServerUserLoginHall"
	local pClusterId = nil
	-- TODO： 如果登陆成功，踢出同一用户，保存当前用户的映射
	if pUserId and pUserId > 0 then
		-- 踢掉异地登陆
		self:onKickOffUserId(pUserId, agent)
		-- 将信息上报给Mgr,由Mgr进行维护
		local pRet = skynet.call(self.m_pHallServiceMgr, "lua", "onUpdateHallServerData", {
				iHallServer = skynet.self(),
				iAgent = agent,
				iUserId = pUserId
			})

		skynet.call(self.m_pHallServiceMgr, "lua", "onSendPackage", agent, resName, info)
	else
		skynet.call(self.m_pHallServiceMgr, "lua", "onSendPackage", agent, resName, info)
		skynet.call(self.m_pHallServiceMgr, "lua", "onCloseAgent", agent)
	end
end

function HallServer:onServerUserShowHints(pAgent, pType, pMsg)
	if not pAgent then return end
	local name = "ServerUserShowHints"
	local info = {}
	info.iShowType = pType
	info.iShowMsg = pMsg
	skynet.call(self.m_pHallServiceMgr, "lua", "onSendPackage", pAgent, name, info)
end

return HallServer