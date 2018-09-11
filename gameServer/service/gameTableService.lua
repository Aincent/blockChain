local skynet = require "skynet"

local GameTableFileMap = {
	[DefineType.RoomType_Friend] = "logic/gameTable_Friend",
	[DefineType.RoomType_GlodField] = "logic/gameTable_GoldField",
}

local pRoomType = tonumber(...)

if not pRoomType or not GameTableFileMap[pRoomType] then
	pRoomType = DefineType.RoomType_Friend
end
local GameTable = require(GameTableFileMap[pRoomType])

skynet.start(function()
	--注册消息处理函数
	skynet.dispatch("lua", function(session, source, cmd, subcmd, ...)
		if GameTable[cmd] then
			skynet.ret(skynet.pack(GameTable[cmd](GameTable, subcmd, ...)))
		else
			Log.e(TAG, "unknown cmd = %s", cmd)
		end
	end)
end)
