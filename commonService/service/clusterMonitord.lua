local skynet = require "skynet"
local cluster = require "skynet.cluster"
local clusterMgr = require  "utils/clusterMgr"

local TAG = 'clusterMonitord'

local clusterMonitord = {}

function clusterMonitord:onConnect(session, conf)
	if session > 0 then
		skynet.retpack(true)
	end
end

function clusterMonitord:onCheckAlive(session, conf)
	
end

function clusterMonitord:onSubscribeMonitor(session, addr)
	local ret1, ret2 = clusterMgr:onSubscribeMonitor(addr)
	if session > 0 then
		skynet.retpack(ret1, ret2)
	end
end

function clusterMonitord:onUnSubscribeMonitor(session, addr)
	local ret1, ret2 = clusterMgr:onUnsubscribeMonitor(addr)
	if session > 0 then
		skynet.retpack(ret1, ret2)
	end
end

function clusterMonitord:onStart(session, current_conf)
	local ret1, ret2 = clusterMgr:onStart(current_conf)
	if session > 0 then
		skynet.retpack(ret1, ret2)
	end
end

function clusterMonitord:onOpen(session)
	local ret1, ret2 = clusterMgr:onOpen()
	if session > 0 then
		skynet.retpack(ret1, ret2)
	end
end

function clusterMonitord:onReLoad(session, current_conf)
	local ret1, ret2 = clusterMgr:onReLoad(current_conf)
	if session > 0 then
		skynet.retpack(ret1, ret2)
	end
end

function clusterMonitord:onGetCurrentNodename(session)
	if session > 0 then
		local current_conf = clusterMgr:onGetCurrentConf()
		skynet.retpack(current_conf.nodename)
	end
end

skynet.start(function()
	skynet.dispatch("lua", function(session, address, cmd, ...)
		local f = clusterMonitord[cmd]
		assert(f, "function["..cmd.."] is nil")
		f(clusterMonitord,session, ...)
	end)
	skynet.register(".cluster_monitor")
end)
