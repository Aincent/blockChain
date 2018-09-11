
local PlaytypeConfigJSNJ = {}

PlaytypeConfigJSNJ.iName = "南京麻将"
PlaytypeConfigJSNJ.iGameLevel = 1
PlaytypeConfigJSNJ.iGameCode = 100

PlaytypeConfigJSNJ.iVersion = 1

PlaytypeConfigJSNJ.iGameRoundPath = {
    [0x0101] = "logic/game/mahjong/gameRound",
    [0x0102] = "logic/game/mahjong/gameRound",
}

PlaytypeConfigJSNJ.iGameRulePath = {
    [0x0101] = "logic/game/mahjong/gameRuleJSNJJYZ",
    [0x0102] = "logic/game/mahjong/gameRuleJSNJCKT",
}

PlaytypeConfigJSNJ.iLocalGameTypeMap = {
	["0x0100"] = {
		["0x01"] = {
			iName = "进园子",
			iType = 0x01,
		},
		["0x02"] = {
			iName = "敞开头",
			iType = 0x02,
		},
	},
}

PlaytypeConfigJSNJ.iGameUserCardMap = {
	iGameMaxUserCount = 4,
	iGameMaxCardCount = 144,
	iGameDealCardCount = 13,
}

PlaytypeConfigJSNJ.iGameUpperLimitTable = {
	["0x0100"] = {
		["0x01"] = {
			iMinValue = 95,
			iMaxValue  = 100, 
		},
	}	
}

PlaytypeConfigJSNJ.iSingleUpperLimitTable = {
	["0x0100"] = {
		["0x02"] = {
			iMinValue = 1,
			iMaxValue  = 300, 
		},
	}	
}

-- 某个游戏下的特定玩法
PlaytypeConfigJSNJ.iGamePlaytypeTable = {
	["0x0100"] = {
		["0x01"] = {
			MAHJONG_PLAYTYPE_BASHU = {
				iValue = 0x01,
				iName = "把数(接庄比)",
			},
			MAHJONG_PLAYTYPE_QUANSHU = {
				iValue = 0x02,
				iName = "圈数(占庄比)",
			},
			MAHJONG_PLAYTYPE_HUAZAER = {
				iValue = 0x04,
				iName = "花砸2",
			},
			MAHJONG_PLAYTYPE_DONGNANXIBEIFAKUAN = {
				iValue = 0x08,
				iName = "东南西北罚款",
			},
			MAHJONG_PLAYTYPE_SHIXIHUA = {
				iValue = 0x010,
				iName = "14花(整铲)",
			},
			MAHJONG_PLAYTYPE_SHILIUYAO = {
				iValue = 0x020,
				iName = "16幺(整铲)",
			},
			MAHJONG_PLAYTYPE_YIPAOSANXIANG = {
				iValue = 0x040,
				iName = "一炮三响(整铲)",
			},
			MAHJONG_PLAYTYPE_DOUBLEDONGNANXIBEI = {
				iValue = 0x080,
				iName = "东南西北、东南西北(整铲)",
			},
		},
		["0x02"] = {		
		}
	},
}

-- 好友对战场的配置
PlaytypeConfigJSNJ.iGamePlaytypeRuleTable = {
	["0x0100"] = {
		["0x01"] = {
			iMutexTable = {
			},
			iTogetherTable = {
			},
			iOneOfTwoTable = {
				{0x01, 0x02},
			},
			iSelectNotShowTable = {
			},
		},
		["0x02"] = {
			iMutexTable = {
			},
			iTogetherTable = {
			},
			iOneOfTwoTable = {
			},
			iSelectNotShowTable = {
			},
		},
	},
}

PlaytypeConfigJSNJ.iGameUserCountTable = {
	["0x0100"] = {
		["0x01"] = {
			["4人"] = 4,
			["3人"] = 3,
			["2人"] = 2,
		},
		["0x02"] = {
			["4人"] = 4,
			["3人"] = 3,
			["2人"] = 2,
		},
	}
}

PlaytypeConfigJSNJ.iGameCircleRoomCardTable = {
	["0x0100"] = {
		["0x01"] = {
			["0x01"] = {
				["4"] = {
					iValue = 0,
					iName = "把",
				},
				["8"] = {
					iValue = 0,
      				iName = "把",
				},
				["12"] = {
					iValue = 0,
      				iName = "把"
				},
				["16"] = {
					iValue = 0,
      				iName = "把"
				},
			},
			["0x02"] = {
				["1"] = {
					iValue = 0,
					iName = "圈",
				},
				["2"] = {
					iValue = 0,
      				iName = "圈",
				},
				["3"] = {
					iValue = 0,
      				iName = "圈"
				},
				["4"] = {
					iValue = 0,
      				iName = "圈"
				},
			}
		},
		["0x02"] = {
			["0x01"] = {
				["4"] = {
					iValue = 2,
					iName = "把",
				},
				["8"] = {
					iValue = 3,
      				iName = "把",
				},
				["12"] = {
					iValue = 5,
      				iName = "把"
				},
				["16"] = {
					iValue = 8,
      				iName = "把"
				},
			},
		},
	},
}


PlaytypeConfigJSNJ.iGameRegisterTable = {
	Money = 3000,
	RoomCardNum = 10,
}

return PlaytypeConfigJSNJ