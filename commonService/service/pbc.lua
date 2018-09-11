local skynet = require "skynet"
local protobuf = require "protobuf"
local crc32 = require "utils/crc32"
local TAG = "pbc"

local pbc = {}

local files = {
	"./commonService/protobuf/S2CProto",
	"./commonService/protobuf/C2SProto",
}

--协议号映射表
local name2code = {}
local code2name = {}

--打印二进制string，用于调试
local function bin2hex(s)
    s=string.gsub(s, "(.)", function (x) return string.format("%02X ", string.byte(x)) end)
    return s
end

--分析proto文件，计算映射表
local function analysis_file(path)
	local file = io.open(path, "r") 
	local package = ""
	for line in file:lines() do
		local s, c = string.gsub(line, "^%s*package%s*([%w%.]+).*$", "%1")
		if c > 0 then
			package = s
		end
		local s, c = string.gsub(line, "^%s*message%s*([%w%.]+).*$", "%1")
		if c > 0 then
			local name = package.."."..s
			local code = crc32.hash(name)
			--print(string.format("analysis proto file:%s->%d(%x)", name, code, code))
			name2code[name] = code
			code2name[code] = name
		end
	end
	Log.dump(TAG, name2code, "name2code")
	Log.dump(TAG, code2name, "code2name")
	file:close()  
end

for k, v in pairs(files) do
	analysis_file(v..".proto")
	protobuf.register_file(v..".pb")
end

--cmd:login.Login
--msg:{account="1",password="1234"}
function pbc:pack(cmd, msg)
	--格式说明
	--> >:big endian
	-->i2:前面两位为长度
    -->I4:uint cmd_code 
	--code
	local code = name2code[cmd]
	if not code then
		Log.e(TAG, "pbc fail, cmd:%s", cmd or "nil")
		return
	end

	Log.d(TAG, "protobuf.encode cmd = %s", cmd)
	local pbstr = protobuf.encode(cmd, msg)
	local pblen = string.len(pbstr)
	--len
	local len = 4 + pblen
	--组成发送字符串
	local f = string.format("> i2 I4 c%d", pblen)
	local str = string.pack(f, len, code, pbstr)
	Log.d(TAG, "send pbstr: %s", bin2hex(pbstr))
	Log.d(TAG, "send: %s ", bin2hex(str))
	local pblen = string.len(str)
	Log.d(TAG, "send pblen: %s ", pblen)
    return str
end

function pbc:unpack(str)
	Log.d(TAG,"recv: %s ", bin2hex(str))
	local pblen = string.len(str) - 4
	Log.d(TAG, "recv pblen: %s ", pblen)
	local f = string.format("> I4 c%d", pblen)
	local code, pbstr = string.unpack(f, str)
	Log.d(TAG, "recv pblen: %s ", pblen)
	Log.d(TAG, "recv pbstr: %s", bin2hex(pbstr))
	local cmd = code2name[code]
	if not cmd then
		Log.d(TAG, "recv:code(%d) but not regiest", code)
		return "ERROR"
	end
	local msg = protobuf.decode(cmd, pbstr)
    local cmdlist = string.split(cmd, ".") 
    return "REQUEST", cmdlist[2], msg
end

skynet.start(function()
	skynet.dispatch("lua", function(_, _, command, ...)
		local f = pbc[command]
		Log.d(TAG, "command[%s]", command)
		if f then
			skynet.ret(skynet.pack(f(pbc, ...)))
		end
	end)

	skynet.register(".pbc")
end)