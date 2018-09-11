local skynet = require "skynet"
local mysql = require "skynet.db.mysql"
local json = require "cjson"

local TAG = "DBClient"

local MAX_SQL_BUF_LEN = 2048

local DBClient = {}

local function dump(obj)
    local getIndent, quoteStr, wrapKey, wrapVal, dumpObj
    getIndent = function(level)
        return string.rep("\t", level)
    end
    quoteStr = function(str)
        return '"' .. string.gsub(str, '"', '\\"') .. '"'
    end
    wrapKey = function(val)
        if type(val) == "number" then
            return "[" .. val .. "]"
        elseif type(val) == "string" then
            return "[" .. quoteStr(val) .. "]"
        else
            return "[" .. tostring(val) .. "]"
        end
    end
    wrapVal = function(val, level)
        if type(val) == "table" then
            return dumpObj(val, level)
        elseif type(val) == "number" then
            return val
        elseif type(val) == "string" then
            return quoteStr(val)
        else
            return tostring(val)
        end
    end
    dumpObj = function(obj, level)
        if type(obj) ~= "table" then
            return wrapVal(obj)
        end
        level = level + 1
        local tokens = {}
        tokens[#tokens + 1] = "{"
        for k, v in pairs(obj) do
            tokens[#tokens + 1] = getIndent(level) .. wrapKey(k) .. " = " .. wrapVal(v, level) .. ","
        end
        tokens[#tokens + 1] = getIndent(level - 1) .. "}"
        return table.concat(tokens, "\n")
    end
    return dumpObj(obj, 0)
end

function DBClient:isConnected()
	if self.m_pSocketfd then
        return true
    else
        self:connectToClient()
        return false
    end
end

function DBClient:connectToClient()
    local function on_connect(db)
        -- if db then
        --     Log.d(TAG, "on_connect set charset utf8")
        -- end
        db:query("set charset utf8")
    end
    self.m_pSocketfd = mysql.connect({
        host = self.m_dbConfig.HOST,
        user = self.m_dbConfig.USER,
        password = self.m_dbConfig.PASSWORD,
        database = self.m_dbConfig.DB,
        port = self.m_dbConfig.PORT,
        max_packet_size = 1024 * 1024,
        on_connect = on_connect,
    })
    if not self.m_pSocketfd then 
        Log.d(TAG, "DBClient.client_fd is nil, db failed!")
        return -1
    end
    Log.d(TAG, "DBClient success to connect to mysql server")
    return 0
end

function DBClient:init(pConf)
	self.m_dbConfig = pConf
	assert(self.m_dbConfig)
	-- Log.dump(TAG, self.m_dbConfig, "m_dbConfig")
	return self:connectToClient()
end

function DBClient:disconnect()
    Log.e(TAG, "DBClient disconnect")
	self.m_pSocketfd = nil
end

function DBClient:onExecute(sqlStr)
    if not self:isConnected() then
        return
    end
    Log.d(TAG, "onExecute %s", sqlStr)
    local suc, res = pcall(self.m_pSocketfd.query, self.m_pSocketfd, sqlStr)
    if suc and res and type(res) == "table" then
        Log.dump(TAG, res, "res")
        if res.badresult then
            Log.e(TAG, "onExecute failed %s", res.err)
            Log.e(TAG, "onExecute failed %s", sqlStr)
        end
    else
        res = nil
    end
    return res
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, subcmd, ...)
        -- Log.i(TAG, "cmd : %s subcmd : %s", cmd, subcmd)
        local f = assert(DBClient[cmd])
        skynet.ret(skynet.pack(f(DBClient, subcmd, ...)))
    end)
end)
