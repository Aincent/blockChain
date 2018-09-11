local json = require("cjson")
local skynet = require "skynet"
local cluster = require "skynet.cluster"
local connector = require ("utils/connector")

local TAG = 'clusterMgr'

local clusterMgr = {}
local _current_conf = nil
local _connector_map = {}
local _subscribe_cluster_map = {}
local _cluster_nodes = {}

-- 结点连接关系表
local _node_connector_map = {
	[1] = {2},
	[2] = {1,3,4,5},
	[3] = {2,4},
	[4] = {2,3},
	[5] = {2},
}

--主动连接函数
local function _connect_func(conf)
	assert(conf, "conf is nil")
	local current_conf = clusterMgr.onGetCurrentConf()
	return cluster.call(conf.nodename, ".cluster_monitor", "onConnect", current_conf)
end

--主动掉线检测
local function _check_disconnect_func(conf)
	assert(conf, "conf is nil")
	local current_conf = clusterMgr.onGetCurrentConf()
	cluster.call(conf.nodename, ".cluster_monitor", "onCheckAlive", current_conf)
end

--连接成功回调
local function _connect_callback(conf)
	-- Log.d(TAG,"_connect_callback..............%s",conf.nodename)
	local cluster_conf  = _cluster_nodes[conf.nodename]
	if not cluster_conf or cluster_conf.isonline == 1 then
		return
	end

	cluster_conf.isonline = 1

	for addr, _ in pairs(_subscribe_cluster_map) do
		skynet.call(addr, "lua", "onMonitorNodeChange", cluster_conf)
	end
end

--断开连接回调
local function _disconnect_callback(conf)
	-- Log.d(TAG,"_disconnect_callback..............")
	local cluster_conf  = _cluster_nodes[conf.nodename]
	if not cluster_conf or cluster_conf.isonline == 0 then
		return
	end

	cluster_conf.isonline = 0

	for addr, _ in pairs(_subscribe_cluster_map) do
		skynet.call(addr, "lua", "onMonitorNodeChange", conf)
	end
end

--------------------clusterMgr---------------------
function clusterMgr:onSetCurrentConf(conf)
	_current_conf = conf
end

function clusterMgr:onGetCurrentConf()
	return _current_conf
end


function clusterMgr:onSetConnector(name, conn)
	_connector_map[name] = conn
end

function clusterMgr:onGetConnector(name)
	return _connector_map[name]
end

-------------------subscribe------------------------
--nodename is nil so subscribe all nodes
function clusterMgr:onSubscribeMonitor(addr)
	_subscribe_cluster_map[addr] = true
end

function clusterMgr:onUnsubscribeMonitor(addr)
	_subscribe_cluster_map[addr] = nil
end

-----------------------cluster memory----------------------
function clusterMgr:onCacheClusterConf(conf)
	if not _cluster_nodes[conf.nodename] or (_cluster_nodes[conf.nodename] and conf.ver > _cluster_nodes[conf.nodename].ver) then
		_cluster_nodes[conf.nodename] = conf
	end
end

function clusterMgr:onResetConnectors()
	local current_conf = self:onGetCurrentConf()
	for _, v in pairs(_cluster_nodes) do		
		if v.nodename ~= current_conf.nodename then
			local conn = _connector_map[v.nodename]
			if not conn then
				conn = new(connector)
				conn:onSetConnectConf(v)
				conn:onSetConnectFunc(_connect_func)
				conn:onSetCheckDisconnectFun(_check_disconnect_func)
				conn:onSetConnectCallback(_connect_callback)
				conn:onSetDisconnectCallback(_disconnect_callback)
				conn:onStart()
				self:onSetConnector(v.nodename, conn)
			else
				local conf = conn:onGetConnectConf()
				if conf.ver < v.ver then
					conn:onStop()
					conn:onSetConnectConf(v)
					conn:onStart()
				end
			end
		end
	end

	local remove_list = {}
	for name, v in pairs(_connector_map) do
		if not _cluster_nodes[name] then
			v:onStop()
			v:onReset()
			table.insert(remove_list, name)
		end
	end

	for _, name in pairs(remove_list) do
		_connector_map[name] = nil
	end
	
	remove_list = nil	
end
-------------------------------init---------------------------
local function unique(t, bArray)  
    local check = {}  
    local n = {}  
    local idx = 1  
    for k, v in pairs(t) do  
        if not check[v] then  
            if bArray then  
                n[idx] = v  
                idx = idx + 1  
            else  
                n[k] = v  
            end  
            check[v] = true  
        end  
    end 

    return n  
end  

function clusterMgr:onCheckClusterConf(pClusterConfig)
	local pIdentify = tonumber(skynet.getenv("identify"))
	local pServertype = tonumber(skynet.getenv("servertype"))
	local pCurNode = true
	local nodenames = {}
	local intranets = {}
	local retires = {}

	for k,v in pairs(pClusterConfig) do
		if v.servertype == pServertype and tonumber(string.sub(v.nodename,-1)) == pIdentify then
			pCurNode = false
		end

		if v.servertype == 3 and v.retire and v.retire == 1 then
			table.insert(retires, v.nodename)
		end

		table.insert(nodenames, v.nodename)
		table.insert(intranets, v.intranet)
	end

	if pCurNode then
		Log.e(TAG, "ClusterConfig servertype[%s] nodename not Found !", pServertype)
		return false
	end

	if #(unique(nodenames,true)) ~= #nodenames then
		Log.e(TAG, "ClusterConfig nodename repeated !")
		return false
	end

	if #(unique(intranets, true)) ~= #intranets then
		Log.e(TAG, "ClusterConfig intranet repeated !")
		return false
	end

	if pServertype == 2 or pServertype == 4 then
		for k,v in pairs(retires) do
			if not _cluster_nodes[v] then
				Log.e(TAG, "ClusterConfig retire nodename[%s] in Systems not Found !", v)
				return false
			end
		end
	end

	return true
end

function clusterMgr:onReloadClusterConf(pClusterConfig)
	local pIdentify = tonumber(skynet.getenv("identify"))
	local pServertype = tonumber(skynet.getenv("servertype"))

	local function IsInTable(value, tbl) 
		for k,v in ipairs(tbl) do 
			if v == value then 
				return true; 
			end 
		end 
		return false; 
	end

	local config = {}
	local nodenames = {}
	for k,v in pairs(pClusterConfig) do
		if v.servertype == pServertype and tonumber(string.sub(v.nodename,-1)) == pIdentify then
			self:onSetCurrentConf(v)
			config[v.nodename] = v.intranet
		end

		if IsInTable(v.servertype, _node_connector_map[pServertype]) then
			self:onCacheClusterConf(v)
			nodenames[v.nodename] = true
		end
	end
	
	for k,v in pairs(_cluster_nodes) do
		if not nodenames[v.nodename] then
			_cluster_nodes[v.nodename] = nil
		else
			config[v.nodename] = v.intranet
		end
	end

	cluster.reload(config)
end

function clusterMgr:onStart(pClusterConfig)
	if not self:onCheckClusterConf(pClusterConfig) then
		return false
	end

	self:onReloadClusterConf(pClusterConfig)
	self:onResetConnectors()
	return true
end

--开放本节点
function clusterMgr:onOpen()
	local current_conf = self:onGetCurrentConf()
	if current_conf then
		-- Log.dump(TAG, current_conf, "current_conf")
		cluster.open(current_conf.nodename)
	end

	return true
end

function clusterMgr:onReLoad(pClusterConfig)
	if not self:onCheckClusterConf(pClusterConfig) then
		return false
	end

	self:onReloadClusterConf(pClusterConfig)
	self:onResetConnectors()
	return true	
end

--关闭本节点
function clusterMgr:close()

end

return clusterMgr