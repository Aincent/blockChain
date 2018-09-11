local skynet    = require "skynet.manager"
local TAG = 'main'

local function start_server()

	-- 获取等级和端口
	local pGameCode = tonumber(skynet.getenv("level"))
	local pIdentify = tonumber(skynet.getenv("identify"))
	local pServertype = tonumber(skynet.getenv("servertype"))

	local pLoaderSerice = skynet.uniqueservice("protoLoader")
	local pPbcServer = skynet.uniqueservice("pbc")
	-- skynet.name(".ProtoLoader", pLoaderSerice)

	local pServerConfig = require(onGetServerConfigFile(pGameCode))
	local pDebugPort = pServerConfig.iGameIpPortConfig.iDebugConsolePort
	skynet.newservice("debug_console", pDebugPort + (pServertype - 1)*10 + (pIdentify- 1))

	-- 整个server的控制层
	local pServiceMgr = skynet.uniqueservice("gateServiceMgr")
	skynet.name(".GateServiceMgr", pServiceMgr)
	Log.d(TAG, "pServiceMgr = %s", pServiceMgr)
	
	local pRet = skynet.call(pServiceMgr, "lua", "init", pGameCode, pIdentify)
end

skynet.start(function()
    Log.e(TAG, "GateService Start!")
    start_server()
end)
