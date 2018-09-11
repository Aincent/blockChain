local skynet = require "skynet"

local TAG = 'clusterMonitor'

local addr 
local clusterMonitor = {}
local subscribe_nodes = {}
local all_subscribe = false
local all_subscribe_cb = nil

local function table_len(t) 
	local count = 0
	for k, v in pairs(t) do
		count = count + 1
	end
	return count
end 

local function init()
	addr = skynet.uniqueservice("clusterMonitord")
end

function clusterMonitor:onGetCurrentNodename()
	local curr_nodename = skynet.call(addr, "lua", "onGetCurrentNodename")
	return curr_nodename
end


function clusterMonitor:onSubscribeNode(callback, nodename)
	if all_subscribe == false and table_len(subscribe_nodes) == 0 then
		skynet.call(addr, "lua", "onSubscribeMonitor", skynet.self())
	end

	if nodename == nil then
		all_subscribe = true
		all_subscribe_cb = callback
	else
		subscribe_nodes[nodename] = callback
	end
end

function clusterMonitor:onUnsubscribeNode(nodename)
	if nodename == nil then
		all_subscribe = false
		all_subscribe_cb = nil
		return
	end

	if subscribe_nodes[nodename] then
		subscribe_nodes[nodename] = nil
	end

	if not all_subscribe and table_len(subscribe_nodes) == 0 then
		skynet.call(addr, "lua", "onUnSubscribeMonitor", skynet.self())
	end
end

function clusterMonitor:onGetSubcribeCallback(nodename)
	if nodename == nil and all_subscribe == true then
		return all_subscribe_cb
	elseif nodename and subscribe_nodes[nodename] then
		return subscribe_nodes[nodename]
	end
	return nil
end


function clusterMonitor:onStart(current_conf)
	assert(current_conf, "current_conf is nil")
	skynet.call(addr, "lua", "onStart", current_conf)
end

function clusterMonitor:onOpen()
	skynet.call(addr, "lua", "onOpen")
end

function clusterMonitor:onReLoad(current_conf)
	assert(current_conf, "current_conf is nil")
	skynet.call(addr, "lua", "onReLoad", current_conf)
end

skynet.init(init)

return clusterMonitor
