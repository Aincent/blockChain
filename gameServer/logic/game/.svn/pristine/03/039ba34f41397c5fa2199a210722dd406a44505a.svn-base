local OperationType = {}

OperationType.RIGHT_CHI = 0x0001--右吃
OperationType.MID_CHI   = 0x0002--中吃
OperationType.LEFT_CHI  = 0x0004--左吃
OperationType.PENG      = 0x0008--碰
OperationType.GANG      = 0x0010--碰杠
OperationType.AN_GANG   = 0x0020--暗杠
OperationType.BU_GANG   = 0x0040--补杠
OperationType.TING      = 0x0080--听牌
OperationType.HU        = 0x0100--胡
OperationType.ZIMO      = 0x0200--自摸
OperationType.QIANGGANGHU        = 0x0400--抢杠胡
OperationType.GANGSHANGKAIHUA    = 0x0800--杠上开花
OperationType.GANGSHANGPAO       = 0x1000--杠上炮
OperationType.GUO       = 0x8000--过

function OperationType:isRightChi(operateValue)
	return self.RIGHT_CHI == (operateValue & self.RIGHT_CHI)
end

function OperationType:isMidChi(operateValue)
	return self.MID_CHI == (operateValue & self.MID_CHI)
end

function OperationType:isLeftChi(operateValue)
	return self.LEFT_CHI == (operateValue & self.LEFT_CHI)
end

function OperationType:isPeng(operateValue)
	return self.PENG == (operateValue & self.PENG)
end

function OperationType:isGang(operateValue)
	return self.GANG == (operateValue & self.GANG)
end

function OperationType:isZiMo(operateValue)
	return self.ZIMO == (operateValue & self.ZIMO)
end

function OperationType:isHu(operateValue)
	return self.HU == (operateValue & self.HU)
end

function OperationType:isAnGang(operateValue)
	return self.AN_GANG == (operateValue & self.AN_GANG)
end

function OperationType:isBuGang(operateValue)
	return self.BU_GANG == (operateValue & self.BU_GANG)
end

function OperationType:isTing(operateValue)
	return self.TING == (operateValue & self.TING)
end

function OperationType:isGuo(operateValue)
	return self.GUO == (operateValue & self.GUO)
end

function OperationType:isQiangGangHu(operateValue)
	return self.QIANGGANGHU == (operateValue & self.QIANGGANGHU)
end

function OperationType:isGangShangKaiHua(operateValue)
	return self.GANGSHANGKAIHUA == (operateValue & self.GANGSHANGKAIHUA)
end

function OperationType:isGangShangPao(operateValue)
	return self.GANGSHANGPAO == (operateValue & self.GANGSHANGPAO)
end

function OperationType:isHasHu(operateValue)
	if self:isHu(operateValue) or self:isZiMo(operateValue) or self:isQiangGangHu(operateValue) 
		or self:isGangShangKaiHua(operateValue) or self:isGangShangPao(operateValue) then
		return true
	end
end

function OperationType:isHasGang(operateValue)
	if self:isGang(operateValue) or self:isAnGang(operateValue) or self:isBuGang(operateValue) then
		return true
	end
end

function OperationType:isHasChi(operateValue)
	if self:isRightChi(operateValue) or self:isMidChi(operateValue) or self:isLeftChi(operateValue) then
		return true
	end
end

return OperationType