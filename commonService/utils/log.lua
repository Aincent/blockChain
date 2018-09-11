local skynet = require("skynet")
local Log = {}

Log.LV_ERROR = 1
Log.LV_WARN = 2
Log.LV_INFO = 3
Log.LV_DEBUG = 4

local function format_msg(level, tag, fmt, ...)
    local time_info = os.date("%c", os.time())
    local debug_info = debug.getinfo(3)
    local msg = string.format(tostring(fmt), ...)
    return string.format("%s:%s[%d] lv%d %s [%s] --> %s",debug_info.source, (debug_info.name or "NotFound"), (debug_info.currentline or 0), level, tag, time_info, msg)
end

local function format_dump(level, tag, msg)
    local time_info = os.date("%X",os.time())
    local debug_info = debug.getinfo(3)
    return string.format("%s:%s[%d] lv%d %s [%s] --> %s",debug_info.source, (debug_info.name or "NotFound"), (debug_info.currentline or 0), level, tag, time_info, msg)
end

local function log_printfmsg(msg)
    skynet.error(msg)
end

local log_level = GLConfig:isFormalMode() and Log.LV_ERROR or Log.LV_DEBUG

local function log_error(tag, fmt, ...)
    if log_level >= Log.LV_ERROR then
        local info = format_msg(Log.LV_ERROR, tag, fmt, ...)
        log_printfmsg(info)
    end
end

local function log_warn(tag, fmt, ...)
    if log_level >= Log.LV_WARN then
        local info = format_msg(Log.LV_WARN, tag, fmt, ...)
        log_printfmsg(info)
    end
end

local function log_info(tag, fmt, ...)
    if log_level >= Log.LV_INFO then
        local info = format_msg(Log.LV_INFO, tag, fmt, ...)
        log_printfmsg(info)
    end
end

local function log_debug(tag, fmt, ...)
    if log_level >= Log.LV_DEBUG then
        local info = format_msg(Log.LV_DEBUG, tag, fmt, ...)
        log_printfmsg(info)
    end
end

local function log_dump(tag, root, name)
    if not root then return end
    if log_level < Log.LV_DEBUG then return end
    local function _dump(t, space, name)
        local temp = {}
        table.insert(temp, string.format("%s = {", name and name or "table"))
        for k, v in pairs(t) do
            local key = tostring(k)
            if type(v) == "table" then
                table.insert(temp, string.format("%s%s%s", space, string.rep(" ", 4), _dump(v, space..string.rep(" ", 4), key)))
            else
                if type(v) == "number" or type(v) == "boolean" then
                    table.insert(temp, string.format("%s%s%s = %s,", space, string.rep(" ", 4), key, tostring(v)))
                else
                    table.insert(temp, string.format("%s%s%s = \"%s\",", space, string.rep(" ", 4), key, tostring(v)))
                end
            end
        end
        table.insert(temp, string.format("%s}", space))
        return table.concat(temp, "\n")
    end
    local fmt = string.format("\n%s", _dump(root, "", name and name or "table"))
    local info = format_dump(Log.LV_DEBUG, tag, fmt)
    log_printfmsg(info)
end

local function log_errordump(tag, root, name)
    if not root then return end
    if log_level < Log.LV_ERROR then return end
    local function _dump(t, space, name)
        local temp = {}
        table.insert(temp, string.format("%s = {", name and name or "table"))
        for k, v in pairs(t) do
            local key = tostring(k)
            if type(v) == "table" then
                table.insert(temp, string.format("%s%s%s", space, string.rep(" ", 4), _dump(v, space..string.rep(" ", 4), key)))
            else
                if type(v) == "number" or type(v) == "boolean" then
                    table.insert(temp, string.format("%s%s%s = %s,", space, string.rep(" ", 4), key, tostring(v)))
                else
                    table.insert(temp, string.format("%s%s%s = \"%s\",", space, string.rep(" ", 4), key, tostring(v)))
                end
            end
        end
        table.insert(temp, string.format("%s}", space))
        return table.concat(temp, "\n")
    end
    local fmt = string.format("\n%s", _dump(root, "", name and name or "table"))
    local info = format_dump(Log.LV_DEBUG, tag, fmt)
    log_printfmsg(info)
end

local function _tostring(t)
    local cache = {  [t] = "." }
    local function _dump(t,name)
        local temp = {}
        for k,v in pairs(t) do
            local key = tostring(k)
            if cache[v] then
                table.insert(temp,key .. " {" .. cache[v].."}")
            elseif type(v) == "table" then
                local new_key = name .. "." .. key
                cache[v] = new_key
                table.insert(temp,key .."= {" .. _dump(v,new_key) .."}")
            else
                table.insert(temp,key .. " = " .. tostring(v).."")
            end
        end
        return table.concat(temp," , ")
    end
    return "{" .. _dump(t,"").. "}"
end

local function log_string(tag, fmt,...)
    local strList = {};
    local arg = {...}
    for i,v in ipairs(arg) do
        if type(v) == "table" then
            strList[#strList+1] = _tostring(v)
        elseif type(v) == "UserData" then
            strList[#strList+1] = "UserData";
        else
            strList[#strList+1] = tostring(v);
        end
    end

    local info = format_msg(Log.LV_ERROR, tag, fmt, table.unpack(strList))
    log_printfmsg(info)
end

Log.e = log_error
Log.w = log_warn
Log.i = log_info
Log.d = log_debug
Log.dump = log_dump
Log.edump = log_errordump
Log.string = log_string

return Log