-- 江苏南京棋牌的配置
local PortRule = require("config/portRule")
local ServerConfig = {}

ServerConfig.iGameRoomConfig = {
    {
        iBasePoint = 1,
        iServerFee = 0,
        iOutCardTime = 10,
        iOperationTime = 10,
        
        iPlaytype = 0x0,

        iTableName = "好友对战",
        iGameLevel = 1,
        iRoomType = DefineType.RoomType_Friend,
    },
    {
        iTableName = "金币场",
        iAllGoldFieldTable = {},
        iGameLevel = 2,
        iRoomType = DefineType.RoomType_GlodField,
    },
}

local gateIp = "127.0.0.1"
local redisIp = "127.0.0.1"
local dbIp = "127.0.0.1"
local webIp = "127.0.0.1"

if GLConfig:isFormalMode() then
    gateIp = "172.18.242.191"
    redisIp = "172.18.242.191"
    webIp = "172.18.242.169"
    dbIp = "172.18.242.171"
end

ServerConfig.iGameIpPortConfig = {
    iDatabaseConfig = {
        SOCKET = "",
        PORT = GLConfig:isFormalMode() and 3307 or 3306,
        PASSWORD = GLConfig:isFormalMode() and "a3u2Du4uEpiIUxAr" or "123456",
        HOST = dbIp,
        DB = "blockchain",
        USER = GLConfig:isFormalMode() and "wzlDevUser" or "root",
    },
    iUserRedisConfig = {
        host = redisIp,
        port = PortRule:onGetGameRedisPort(0),
        db   = 0,
    },
    iTableRedisConfig = {
        host = redisIp,
        port = PortRule:onGetGameRedisPort(1),
        db   = 0,
    },
    iActivityRedisConfig = {
        host = redisIp,
        port = PortRule:onGetGameRedisPort(3),
        db   = 0,
    },
    -- 存放牌局日志的端口
    iBillListRedisConfig = {
        host = webIp,
        port = PortRule:onGetWebRedisPort(0),
        db   = 0,
    },
    -- 这个端口是所有项目都公用的
    iClubRedisConfig = {
        host = webIp,
        port = 9000,
        db   = 0,
    },
    iHallServerConfig = 1,
    iLoginServerConfig = 1,
    iDebugConsolePort = PortRule:onGetDebugPort(),
}

ServerConfig.iGateServerConfig  = {
    {
        host = gateIp,
        port = PortRule:onGetGateConfigPort(0),
    },
    {
        host = gateIp,
        port = PortRule:onGetGateConfigPort(1),
    },
    {
        host = gateIp,
        port = PortRule:onGetGateConfigPort(2),
    },
    {
        host = gateIp,
        port = PortRule:onGetGateConfigPort(3),
    },
    {
        host = gateIp,
        port = PortRule:onGetGateConfigPort(4),
    },
    {
        host = gateIp,
        port = PortRule:onGetGateConfigPort(5),
    },
    {
        host = gateIp,
        port = PortRule:onGetGateConfigPort(6),
    },
    {
        host = gateIp,
        port = PortRule:onGetGateConfigPort(7),
    },
    {
        host = gateIp,
        port = PortRule:onGetGateConfigPort(8),
    },
    {
        host = gateIp,
        port = PortRule:onGetGateConfigPort(9),
    },
}

--[[
    节点名         节点服务        内网地址    服务器类型       服务器版本号      是否在线
    nodename    clustername     intranet    servertype      ver         isonline

    服务器类型对照表
    servertype = {
        gateserver  =  1,
        hallserver  =  2,
        gameserver  =  3,
        allocserver =  4,
        loginserver =  5,
    }
]]
ServerConfig.iClusterConfig = {
    [1] = {
        nodename = "iGateServer1",
        clustername = ".GateServiceMgr",
        servertype = 1,
        serverNumber = 1, -- 序号
        intranet = GLConfig:isFormalMode() and "172.18.242.195" or "127.0.0.1",
        ver = 1,
        isonline = 0,
    },
    [2] = {
        nodename = "iHallServer1",
        clustername = ".HallServiceMgr",
        intranet = GLConfig:isFormalMode() and "172.18.242.168" or "127.0.0.1",
        servertype = 2,
        serverNumber = 1, -- 序号
        ver = 1,
        isonline = 0,
    },
    -- [3] = {
    --     nodename = "iGameServer1",
    --     clustername = ".GameServiceMgr",
    --     intranet = GLConfig:isFormalMode() and "172.18.242.168" or "127.0.0.1",
    --     servertype = 3,
    --     serverNumber = 1, -- 序号
    --     ver = 1,
    --     isonline = 0,
    -- },
    -- [4] = {
    --     nodename = "iAllocServer1",
    --     clustername = ".AllocServiceMgr",
    --     intranet = GLConfig:isFormalMode() and "172.18.242.168" or "127.0.0.1",
    --     servertype = 4,
    --     serverNumber = 1, -- 序号
    --     ver = 1,
    --     isonline = 0,
    -- },
    [3] = {
        nodename = "iLoginServer1",
        clustername = ".LoginServiceMgr",
        intranet = GLConfig:isFormalMode() and "172.18.242.168" or "127.0.0.1",
        servertype = 5,
        serverNumber = 1, -- 序号
        ver = 1,
        isonline = 0,
    },
}

-- 重新设置intranet
for _, kCluster in pairs(ServerConfig.iClusterConfig) do
    local pPort = PortRule:onGetClusterConfigPort(kCluster.servertype, kCluster.serverNumber)
    kCluster.intranet = string.format("%s:%s", kCluster.intranet, pPort)
end

ServerConfig.iPlaytypeConfigPath    = "config/401/playtypeConfig"
ServerConfig.iOtherConfigPath       = "config/401/otherConfig"

return ServerConfig