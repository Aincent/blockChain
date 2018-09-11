
local skynet = require "skynet.manager"
local codecache = require "skynet.codecache"
local cluster = require "skynet.cluster"
local json = require("cjson")

local sprotoloader = require "sprotoloader"
local queue = require "skynet.queue"
local clusterMonitor = require "utils/clusterMonitor"


local TAG = "GateServiceMgr"

local GateServiceMgr = {}

function GateServiceMgr:init(pGameCode, pIdentify)
	local pServerConfig = require(onGetServerConfigFile(pGameCode))
	self.m_pGameCode = pGameCode

	self.m_pHallServiceMgr = nil

	self.m_pWatchDogs = {}
	self.m_pAgentMap = {}

	for k, v in pairs(pServerConfig.iGateServerConfig or {}) do
		-- 监听玩家的登陆
		local watchdog = skynet.newservice("watchdog")
		local pRet = skynet.call(watchdog, "lua", "init",{
			port      = v.port,
			maxclient = 1024,
			nodelay   = true,
		})

		table.insert(self.m_pWatchDogs, watchdog)
	end

	local host          = sprotoloader.load(1):host("package")
	self.m_pSendPackage = host:attach(sprotoloader.load(2))

	-- 启动计时器
	self.m_pScheduleMgr = require('utils/schedulerMgr')
	self.m_pScheduleMgr:init()

	local pCallback = self.onCheckTooTimeNotActive
	self.m_pCheckActiveTimer = self.m_pScheduleMgr:register(pCallback, 5 * 60 * 1000, -1, 10 * 1000, self)

	-- 确保自身数据初始化完毕再开启结点间链接
	clusterMonitor:onSubscribeNode(self.onConnectChange)
	clusterMonitor:onStart(pServerConfig.iClusterConfig)

	self.m_pClusterId =  clusterMonitor:onGetCurrentNodename()
	clusterMonitor:onOpen()
end


function GateServiceMgr:onPrint()
	Log.dump(TAG, self.m_pAgentMap, "self.m_pAgentMap")
end

function GateServiceMgr:onRegisterAgent(pAgent)
	table.insert(self.m_pAgentMap, pAgent)
	-- self:onPrint()
	if not self.m_pHallServiceMgr then
		Log.e(TAG, "hallservice disconnect error ")
		return
	end

	local data = {}
	data.iAgent = pAgent
	data.iClusterId = self.m_pClusterId
	pcall(skynet.call, self.m_pHallServiceMgr, "lua", "onUpdateGateServerData", string.format("%s_%s", self.m_pClusterId, pAgent), data)
end

function GateServiceMgr:ClientUserHeartbeat(pAgent, name, request)
	local resName = "ServerUserHeartbeat"
	local info = {}

	local pRet = skynet.call(pAgent, "lua", "onSendPackage", resName, info)
end

function GateServiceMgr:onReceivePackage(pAgent, name, request )
	if self[name] then
		self[name](self, pAgent, name, request)
	else
		if self.m_pHallServiceMgr then
			Log.d(TAG, "onReceivePackage[%s] self.m_pHallServiceMgr[%s]", name, self.m_pHallServiceMgr)
			pcall(skynet.call, self.m_pHallServiceMgr, "lua", "onReceivePackage", string.format("%s_%s", self.m_pClusterId, pAgent), name, request)
		else
			Log.e(TAG, "hallservice disconnect error ")
		end
	end
end

function GateServiceMgr:onDisConnect(pAgent, pClearRedis)
	for k, v in ipairs(self.m_pAgentMap) do
		if v == pAgent then
			table.remove(self.m_pAgentMap, k)
			break
		end
	end
	self:onPrint()
	if self.m_pHallServiceMgr then
		pcall(skynet.call, self.m_pHallServiceMgr, "lua", "onDisConnect", string.format("%s_%s", self.m_pClusterId, pAgent), pClearRedis)
	else
		Log.e(TAG, "hallservice disconnect error ")
	end
end

function GateServiceMgr:onCheckTooTimeNotActive()
	Log.d(TAG, "onCheckTooTimeNotActive")
	for k, v in pairs(self.m_pAgentMap) do
		local pRet = skynet.call(v, "lua", "onCheckTooTimeNotActive")
	end
end

function GateServiceMgr:onPackLookbackTable(pLookbackTable)
	--写入回看数据
	local pIsAllOk = true
	local pLookbackDataTable = {}
	for _, kLookback in pairs(pLookbackTable) do
		local pIsOk, pack = pcall(self.m_pSendPackage, kLookback.iName, kLookback.iInfo)
		if not pIsOk then
			Log.e(TAG, "kLookback.iName[%s]", kLookback.iName)
			pIsAllOk = false
			break
		else
			local package = string.pack(">s2", pack)
			table.insert(pLookbackDataTable, package)
		end
	end
	
	return pIsAllOk, json.encode(pLookbackDataTable)
end


function GateServiceMgr:onConnectChange( conf )
	Log.dump(TAG,conf,"onConnectChange")
	if conf.isonline == 1 then
		self.m_pHallServiceMgr = cluster.proxy(conf.nodename, conf.clustername)
		for k,v in pairs(self.m_pWatchDogs) do
			local pRet = skynet.call(v, "lua", "start") -- 开启监听
		end
	else
		for k,v in pairs(self.m_pWatchDogs) do
			local pRet = skynet.call(v, "lua", "stop") -- 关闭监听
		end

		for k,v in ipairs(self.m_pAgentMap) do
			local pRet = skynet.call(v, "lua", "close") -- 关闭所有agent
		end

		self.m_pHallServiceMgr = nil
	end
end

function GateServiceMgr:onMonitorNodeChange(conf)
	if not conf then return end
	if not conf.nodename then return end
	local callback = clusterMonitor:onGetSubcribeCallback()
	if not callback then
		return
	end
	return callback(GateServiceMgr,conf)	
end

function GateServiceMgr:onReLoad()
	local modulename = onGetServerConfigFile(self.m_pGameCode)
	package.loaded[modulename] = nil  
	codecache.clear()

	local pServerConfig = require(modulename)
	clusterMonitor:onReLoad(pServerConfig.iClusterConfig)
end

-- 热更新协议
function GateServiceMgr:onUpdateProto(pProto)
	-- local pProtoService = skynet.localname(".ProtoLoader")
	local pProtoService = skynet.queryservice("protoLoader")
	Log.e(TAG, "更新pProto，pProtoService[%s]", pProtoService)
	pcall(skynet.call, pProtoService, "lua", "onUpdateProto", pProto)
end

skynet.start(function()
	skynet.dispatch("lua", function(_, _, command, ...)
		skynet.ret(skynet.pack(GateServiceMgr[command](GateServiceMgr, ...)))
	end)
end)
