
local skynet = require "skynet.manager"
local codecache = require "skynet.codecache"
local cluster = require "skynet.cluster"
local clusterMonitor = require "utils/clusterMonitor"
local TAG = "LoginServiceMgr"

local LoginServiceMgr = {}

function LoginServiceMgr:init(pGameCode, pIdentify)
	local pServerConfig = require(onGetServerConfigFile(pGameCode))
	self.m_pGameCode = pGameCode

	self.m_pHallServiceMgr = nil
	self.m_pLoginServerTable = {}

	-- 启动LoginServer
	for i = 1, pServerConfig.iGameIpPortConfig.iLoginServerConfig do
		local pLoginServer = skynet.newservice("loginServerService")
		skynet.name(string.format(".LoginServer_[%s]", i), pLoginServer)
		table.insert(self.m_pLoginServerTable, pLoginServer)
		Log.d(TAG, "pLoginServer = %s", pLoginServer)
		local pRet = skynet.call(pLoginServer, "lua", "init", pGameCode)
	end

	-- 启动reportServer
	self.m_pReportServerTable = {}
	local pReportServer = skynet.newservice("reportServer")
	table.insert(self.m_pReportServerTable, pReportServer)
	skynet.send(pReportServer, "lua", "init", pGameCode)

	-- 确保自身数据初始化完毕再开启结点间链接
	clusterMonitor:onSubscribeNode(self.onConnectChange)
	clusterMonitor:onStart(pServerConfig.iClusterConfig)
	clusterMonitor:onOpen()
end

function LoginServiceMgr:onSendPackage(pUserId, name, info)
	if self.m_pHallServiceMgr then
		pcall(skynet.call, self.m_pHallServiceMgr, "lua", "onSendPackage", pUserId, name, info)
	else
		Log.e(TAG, "hallservice disconnect error ")
	end
end

function LoginServiceMgr:onGetLoginServer()
	math.randomseed(tostring(os.time()):reverse():sub(1, 6))
	return self.m_pLoginServerTable[math.random(1, #self.m_pLoginServerTable)]
end

function LoginServiceMgr:onReceivePackage(name, ...)
	local pLoginServer = self:onGetLoginServer()
	if pLoginServer then
		return skynet.call(pLoginServer, "lua", name, ...)
	else
		Log.d(TAG, "onReceivePackage [%s]  error", name)
	end
end

function LoginServiceMgr:onGetReportServer()
	return self.m_pReportServerTable[#self.m_pReportServerTable]
end

function LoginServiceMgr:onConnectChange( conf )
	Log.dump(TAG,conf,"onConnectChange")
	if conf.isonline == 1 then
		self.m_pHallServiceMgr = cluster.proxy(conf.nodename, conf.clustername)
	else
		self.m_pHallServiceMgr = nil
	end
end

function LoginServiceMgr:onMonitorNodeChange(conf)
	Log.dump(TAG,conf,"onMonitorNodeChange")
	if not conf then return end
	if not conf.nodename then return end
	local callback = clusterMonitor:onGetSubcribeCallback()
	if not callback then
		return
	end
	return callback(LoginServiceMgr, conf)
end

function LoginServiceMgr:onReLoad()
	local modulename = onGetServerConfigFile(self.m_pGameCode)
	package.loaded[modulename] = nil  
	codecache.clear()

	local pServerConfig = require(modulename)
	clusterMonitor:onReLoad(pServerConfig.iClusterConfig)
end

function LoginServiceMgr:onUpdatePlaytypeConfig(pPlaytypeConfig)
	self.m_pPlaytypeConfig = pPlaytypeConfig
end

function LoginServiceMgr:onGetPlaytypeConfig()
	return self.m_pPlaytypeConfig
end

skynet.start(function()
	skynet.dispatch("lua", function(_, _, command, ...)
		Log.d(TAG, "dispatch command[%s]", command )
		skynet.ret(skynet.pack(LoginServiceMgr[command](LoginServiceMgr, ...)))
	end)
end)