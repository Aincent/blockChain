-- 自定义结构Map，所有数据必须唯一
-- 应用场景：大量数据稀疏数组，大量数据的查询
-- 稀疏数组，可以避免table的多次重新hash，  也正常数组的查询效率， 将时间复杂度由O(N)变成O(NlogN)

local LuaMap = class()
local TAG = "LuaMap"

function LuaMap:ctor()
	self.m_pCapacity = 0
	-- 数据类型
	self.m_pValueType = nil

	-- 根节点
	self.m_pRootNode = nil
	self.m_pAllKeyValueMap = {}
end

function LuaMap:dtor()
	self.m_pRootNode = nil
end

function LuaMap:capacity()
	return self.m_pCapacity
end

function LuaMap:insert(key, value)
	if not key or not value then return end
	if type(key) ~= "number" and type(key) ~= "string" then return end
	key = string.format("%s", key)
	if self.m_pValueType and self.m_pValueType ~= type(value) then return end
	self:onInsert(key, value)
end

function LuaMap:delete(key)
	if not key then return end
	if type(key) ~= "number" and type(key) ~= "string" then return end
	key = string.format("%s", key)

end

function LuaMap:getValue(key)
	if not key then return end
	if type(key) ~= "number" and type(key) ~= "string" then return end
	key = string.format("%s", key)

	local pNode = self:onGetNode(key)
	if pNode then
		return pNode.iValue
	end
end

function LuaMap:print()
	local pNode = self.m_pRootNode
	Log.d(TAG, "------------------------- LuaMap start ------------------------")
	self:onPrint(pNode)
	Log.d(TAG, "------------------------- LuaMap end --------------------------")
end

-------------------------------------- 内部函数，禁止修改 -----------------------------------------
function LuaMap:onInsert(key, value)
	-- 首先查找是否存在，如果没有，则新建
	local pNewNode = self:onGetNode(key)
	if pNewNode then
		pNewNode.iValue = value
		return
	end
	pNewNode = self:onNewNode(key, value)
	self.m_pCapacity = self.m_pCapacity + 1
	if not self.m_pRootNode then
		-- self.m_pAllDataMap[#self.m_pAllDataMap + 1] = pNewNode
		self.m_pRootNode = pNewNode
		self.m_pValueType = type(value)
	else
		local pNode = self.m_pRootNode
		while(true)
		do
			local pCompareValue = self:onCompareNode(key, pNode.iKey)
			if 1 == pCompareValue then
				if not pNode.iLeft then
					pNode.iLeft = pNewNode
					break
				else
					pNode = pNode.iLeft
				end
			elseif 2 == pCompareValue then
				if not pNode.iRight then
					pNode.iRight = pNewNode
					break
				else
					pNode = pNode.iRight
				end
			else
				return
			end
		end
	end
end


function LuaMap:onGetNode(key)
	local pNode = self.m_pRootNode
	while(true and pNode)
	do
		local pCompareValue = self:onCompareNode(key, pNode.iKey)
		if 1 == pCompareValue then
			if not pNode.iLeft then
				break
			else
				pNode = pNode.iLeft
			end
		elseif 2 == pCompareValue then
			if not pNode.iRight then
				break
			else
				pNode = pNode.iRight
			end
		else
			return pNode
		end
	end
end

function LuaMap:onNewNode(key, value)
	local pNewNode = {}
	pNewNode.iKey = key
	pNewNode.iValue = value
	pNewNode.iLeft = nil
	pNewNode.iRight = nil
	return pNewNode
end

function LuaMap:onCompareNode(key1, key2)
	if key1 < key2 then
		return 1 
	elseif key1 == key2 then
		return 0
	else
		return 2
	end
end

function LuaMap:onPrint(pNode)
	if not pNode then return end
	if self.m_pValueType == "table" then
		Log.dump(TAG, pNode.iValue, pNode.iKey)
	else
		Log.d(TAG, "[%s] = %s", pNode.iKey, pNode.iValue)
	end
	if pNode.iLeft then
		self:onPrint(pNode.iLeft)
	end
	if pNode.iRight then
		self:onPrint(pNode.iRight)
	end
end

return LuaMap
