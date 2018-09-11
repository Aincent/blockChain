
local skynet = require "skynet"
local coroutine = require "skynet.coroutine"

local connector = class()

local TAG = "connector"

CONNECT_NONE = 0 --未连接状态
CONNECT_OK   = 2 --连接成功

function connector:ctor()
	self.m_pConnectStatus = CONNECT_NONE
	self.m_pUseable = true
	self.m_pReconnectWait = 3
	self.m_pConnectConf = nil
	self.m_pConnectFunc = nil
	self.m_pCheckDisconnectFunc = nil
	self.m_pConnectCb = nil
	self.m_pDisConnectCb = nil
	self.m_pCo = nil
end

function connector:onSetConnectConf(conf)
	self.m_pConnectConf = conf
end

function connector:onSetConnectFunc(func)
	self.m_pConnectFunc = func
end

function connector:onSetCheckDisconnectFun(func)
	self.m_pCheckDisconnectFunc = func
end

function connector:onSetConnectCallback(func)
	self.m_pConnectCb = func
end

function connector:onSetDisconnectCallback(func)
	self.m_pDisConnectCb = func
end

function connector:onSetStatusConnected()
	self.m_pConnectStatus = CONNECT_OK
end

function connector:onSetStatusDisconnect()
	self.m_pConnectStatus = CONNECT_NONE
end

function connector:IsUseable()
	return self.m_pUseable == true
end

function connector:IsConnected()
	return self.m_pConnectStatus == CONNECT_OK
end

function connector:onGetConnectConf()
	return self.m_pConnectConf
end

function connector:onStop()
	self.m_pUseable = false
	if self.m_pThread then
		self.m_pThread = nil
	end
end

function connector:onConnect()
	local ret
	local ok, msg = xpcall(function()
		ret = self.m_pConnectFunc(self.m_pConnectConf)
	end, debug.traceback)
	if not ok or not ret then
		pcall(self.m_pDisConnectCb, self.m_pConnectConf)
		return false
	end

	self:onSetStatusConnected()
	if self.m_pConnectCb then
		pcall(self.m_pConnectCb, self.m_pConnectConf)
	end

	return true
end

function connector:onCheckDisconnect()
	local ok, msg = xpcall(function()
		self.m_pCheckDisconnectFunc(self.m_pConnectConf)
	end, debug.traceback)
	if not ok then
		if self:IsConnected() and self.m_pDisConnectCb then
			pcall(self.m_pDisConnectCb, self.m_pConnectConf)
		end

		self:onSetStatusDisconnect()
		return false
	end

	return true
end

function connector:onStart()
	self.m_pUseable = true
	skynet.fork(function()
		self.m_pThread = coroutine.running()
		while self:IsUseable() and self.m_pThread == coroutine.running() do
			if not self:onConnect() then
				skynet.sleep(self.m_pReconnectWait * 100)
			else
				self:onCheckDisconnect()
			end
		end
	end)
end

function connector:onReset()
	self.m_pConnectStatus = CONNECT_NONE
	self.m_pUseable = true
	self.m_pReconnectWait = 3
	self.m_pConnectConf = nil
	self.m_pConnectFunc = nil
	self.m_pCheckDisconnectFunc = nil
	self.m_pConnectCb = nil
	self.m_pDisConnectCb = nil
	self.m_pCo = nil
end

return connector