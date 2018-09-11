local skynet = require "skynet"
local netpack = require "skynet.netpack"
local socket = require "skynet.socket"

local sproto = require "sproto"
local sprotoloader = require "sprotoloader"
local queue = require "skynet.queue"

local cs = queue()

local TAG = "Agent"

local Agent = {}

local host

function Agent:onRequest(name, request)
	local pRet = skynet.call(self.m_pGateServiceMgr, "lua", "onReceivePackage", skynet.self(), name, request)
end

-- function Agent:onSendPackage(name, info)
-- 	Log.d(TAG, "发送给玩家Agent[%s]", skynet.self())
-- 	Log.dump(TAG, info, name)
-- 	if not self.m_pSocketfd or self.m_pSocketfd <= 0 then
-- 		Log.d(TAG, "socketfd is not exit!")
-- 		return
-- 	end
-- 	local pack    = self.m_pSendPackage(name, info)
-- 	local package = string.pack(">s2", pack)
-- 	-- Log.d(TAG, "pack[%s] package[%s]", pack, package)
-- 	socket.write(self.m_pSocketfd, package)
-- end 

-- function Agent:onReceivePackage(type, ...)
-- 	if self.m_pIsClosing then return end
-- 	if type == "REQUEST" then 
-- 		self.m_pLastSendTime = os.time()
-- 		local ok, result = pcall(self.onRequest, self, ...)
-- 		if not ok then 
-- 			skynet.error(result) 
-- 		end 
-- 	else 
-- 		Log.e(TAG, "doesn't support request client")
-- 	end
-- end 

-- skynet.register_protocol {
-- 	name = "client",
-- 	id = skynet.PTYPE_CLIENT,
-- 	unpack = function(msg, sz)
-- 		return host:dispatch(msg, sz)
-- 	end,
-- 	dispatch = function(session, source, type, name, request, response)
-- 		Log.d(TAG, "recieve session[%s] type[%s] name[%s]", session, type, name)
-- 		if name then
-- 			Log.dump(TAG, request, "request")
-- 			cs(Agent.onReceivePackage, Agent, type, name, request, response)
-- 		end
-- 	end
-- }

function Agent:onSendPackage(name, info)
	Log.d(TAG, "发送给玩家Agent[%s]", skynet.self())
	Log.dump(TAG, info, name)
	if not self.m_pSocketfd or self.m_pSocketfd <= 0 then
		Log.d(TAG, "socketfd is not exit!")
		return
	end

	local package = skynet.call(".pbc", "lua", "pack", "S2C.".. name, info)
	socket.write(self.m_pSocketfd, package)
end

function Agent:onReceivePackage(type, ...)
	if self.m_pIsClosing then return end
	if type == "REQUEST" then 
		self.m_pLastSendTime = os.time()
		local ok, result = pcall(self.onRequest, self, ...)
		if not ok then 
			skynet.error(result) 
		end 
	else 
		Log.e(TAG, "doesn't support request client")
	end
end

skynet.register_protocol {
	name = "client",
	id = skynet.PTYPE_CLIENT,
	unpack = function(msg, sz)
		return skynet.tostring(msg, sz)
	end,
	dispatch = function(session, source, data)
		local type, name, request = skynet.call(".pbc", "lua", "unpack", data)
		Log.d(TAG, "recieve session[%s] type[%s] name[%s]", session, type, name)
		if name then
			Log.dump(TAG, request, "request")
			cs(Agent.onReceivePackage, Agent, type, name, request)
		end
	end
}

function Agent:onGetClientIp()
	return self.m_pClientIp
end

function Agent:start(conf)
	Log.dump(TAG, conf, "conf")
	host         = sprotoloader.load(1):host("package")
	self.m_pSendPackage = host:attach(sprotoloader.load(2))

	self.m_pGateServiceMgr = skynet.localname(".GateServiceMgr")
	local pSplitTable = string.split(conf.iAddr, ":")
	-- Log.dump(TAG, pSplitTable, "pSplitTable")
	self.m_pClientIp = pSplitTable[1] or ""

	self.m_pLastSendTime = os.time()

	self.m_pSocketfd = conf.iSocketfd
	self.m_pWatchdog = conf.iWatchdog
	
	local pRet = skynet.call(self.m_pGateServiceMgr, "lua", "onRegisterAgent", skynet.self())
	local pRet = skynet.call(conf.iGate, "lua", "forward", self.m_pSocketfd)
end

function Agent:disconnect()
	cs(function()
		Log.d(TAG, "disconnect Agent[%s]", skynet.self())
		skynet.call(self.m_pGateServiceMgr, "lua", "onDisConnect", skynet.self(), false)
		skynet.exit()
	end)
end

--!
--! @brief      主动关闭agent，断开链接
--!
--! @return     { description_of_the_return_value }
--!
function Agent:close()
	if not self.m_pIsClosing then
		self.m_pIsClosing = true
		skynet.send(self.m_pWatchdog, "lua", "socket", "close", self.m_pSocketfd)
	end
	return
end

function Agent:onCheckTooTimeNotActive()
	-- 如果1分钟内没有包通信则直接断开
	local pCurTime = os.time()
	if self.m_pLastSendTime > 0 then
		if pCurTime - self.m_pLastSendTime > 60 then
			self:close()
		end
	end
end

skynet.start(function()
	skynet.dispatch("lua", function(_, _, command, ...)
		local f = Agent[command]
		Log.d(TAG, "command[%s]", command)
		if f then
			skynet.ret(skynet.pack(f(Agent, ...)))
		end
	end)
end)
