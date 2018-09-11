-- module proto as examples/proto.lua
-- package.path = "./gateServer/protocol/?.lua;" .. package.path

local skynet = require "skynet"
local sprotoparser = require "sprotoparser"
local sprotoloader = require "sprotoloader"
local codecache = require "skynet.codecache"
local proto = require("protocol/proto")

local Protoloader = {}
local TAG = "Protoloader"

function Protoloader:onUpdateProto(pProto)
	if not pProto then return end
	sprotoloader.save(pProto.c2s, 1)
	sprotoloader.save(pProto.s2c, 2)
end

skynet.start(function()
	Protoloader:onUpdateProto(proto)
	skynet.dispatch("lua", function(_, _, command, ...)
		skynet.ret(skynet.pack(Protoloader[command](Protoloader, ...)))
	end)
	-- don't call skynet.exit() , because sproto.core may unload and the global slot become invalid
end)
