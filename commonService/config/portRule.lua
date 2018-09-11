
local PortRule = {}

function PortRule:onGetGateConfigPort(pNumber)
    local pGameCode = GLConfig:onGetGameCode()
    local pSmallGameCode = pGameCode % 100
    return 4000 + pSmallGameCode * 10 + pNumber
end

function PortRule:onGetGameRedisPort(pNumber)
    local pGameCode = GLConfig:onGetGameCode()
    local pSmallGameCode = pGameCode % 100
    return 4500 + pSmallGameCode * 10 + pNumber
end

function PortRule:onGetWebRedisPort(pNumber)
	local pGameCode = GLConfig:onGetGameCode()
    return 10000 + pGameCode * 10 + pNumber
end

function PortRule:onGetClusterConfigPort(pServerType, pNumber)
    local pGameCode = GLConfig:onGetGameCode()
    local pSmallGameCode = pGameCode % 100
    return 10000 + pSmallGameCode * 100 + (pServerType - 1) * 10 + (pNumber - 1)
end

function PortRule:onGetDebugPort()
    local pGameCode = GLConfig:onGetGameCode()
    local pSmallGameCode = pGameCode % 100
    return 15000 + pSmallGameCode * 100
end

return PortRule