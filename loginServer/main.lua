local skynet    = require "skynet.manager"
local TAG = 'main'

local function start_server()

	-- 获取等级和端口
	local pGameCode = tonumber(skynet.getenv("level"))
	local pIdentify = tonumber(skynet.getenv("identify"))
	local pServertype = tonumber(skynet.getenv("servertype"))
	
	local pServerConfig = require(onGetServerConfigFile(pGameCode))
	skynet.newservice("debug_console", pServerConfig.iGameIpPortConfig.iDebugConsolePort + (pServertype - 1)*10 + (pIdentify- 1))

	-- 整个server的控制层
	local pServiceMgr = skynet.uniqueservice("loginServiceMgr")
	skynet.name(".LoginServiceMgr", pServiceMgr)
	Log.d(TAG, "pServiceMgr = %s", pServiceMgr)
	
	local pRet = skynet.call(pServiceMgr, "lua", "init", pGameCode, pIdentify)
end

skynet.start(function()
    Log.e(TAG, "LoginServiceMgr Start!")
    start_server()
end)
