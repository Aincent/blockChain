local defineType = {
	-- 进入房间的定义
	ERROR_LOGIN_TABLE_FULL = {
		iErrorType = 1,
		iErrorMsg = "进入房间失败，房间已满！",
	},
	ERROR_LOGIN_WRONG_DATA = {
		iErrorType = 2,
		iErrorMsg = "进入房间失败，获取玩家数据错误！",
	},
	ERROR_LOGIN_NOT_ENOUGH_MONEY = {
		iErrorType = 3,
		iErrorMsg = "进入房间失败，您身上的金币不够进入该场次！",
	},
	ERROR_LOGIN_TOO_MUCH_MONEY = {
		iErrorType = 4,
		iErrorMsg = "进入房间失败，您身上的金币超过该场次的上限！",
	},
	ERROR_LOGIN_TABLE_STATUS_ERROR = {
		iErrorType = 5,
		iErrorMsg = "进入房间失败，您进入的房间已经解散！",
	},
	ERROR_LOGIN_PAY_ROOMCARD_FAIL = {
		iErrorType = 6,
		iErrorMsg = "进入房间失败，扣取钻石失败！",
	},
	ERROR_LOGIN_NOT_ENOUGH_ROOMCARD = {
		iErrorType = 7,
		iErrorMsg = "进入房间失败，您的钻石不够进入该房间！",
	},
	ERROR_LOGIN_CREATE_FOR_OTHER = {
		iErrorType = 8,
		iErrorMsg = "创建房间失败，您的钻石不够代开此房间！",
	},
	ERROR_LOGIN_CREATE_NOT_IN_CLUB = {
		iErrorType = 9,
		iErrorMsg = "创建房间失败，您无法创建该茶馆的房间！",
	},
	ERROR_LOGIN_USER_NOT_IN_CLUB = {
		iErrorType = 10,
		iErrorMsg = "进入房间失败，您无法进入该茶馆的房间！",
	},

	-- redis名字
	REDIS_USERINFO = "userInfoRedis",
	REDIS_MTKEY = "mtkeyRedis",
	REDIS_BILLLIST = "billListRedis",
	REDIS_ACTIVITY = "activityRedis",
	REDIS_CLUB	= "clubRedis",

	-- 胡牌定义
	MAHJONG_HUTYPE_NONE = 0,
	MAHJONG_HUTYPE_PAOHU = 1,
	MAHJONG_HUTYPE_ZIMO = 2,

	-- 房卡支付方式
	ROOMCARD_PAYTYPE_OWNER = 0, 	-- 房主支付
	ROOMCARD_PAYTYPE_WINNER = 1,	-- 赢家支付
	ROOMCARD_PAYTYPE_SHARE = 2,		-- 均摊支付

	-- 设备定义
	PLATFORM_NONE = 0,
	PLATFORM_IOS = 1,
	PLATFORM_ANDROID = 2,
	PLATFORM_WINDOWS = 3,
	PLATFORM_MAC = 4,

	-- 清除过胡不胡的时机状态(后续补充)
	CLEAR_WHEN_DRAWCARD = 1,	-- 抓牌
	CLEAR_WHEN_OUTCARD = 2,		-- 打牌

	-- 房间类型
	RoomType_Friend = 1,		-- 好友场
	RoomType_GlodField = 2,		-- 金币场

	-- 配置标志
	Config_GoldField = 1,

	-- 算番类型
	HuType_ZiMo = 0,
	HuType_FangPao = 1,
	HuType_ChiPeng = 2,
	HuType_TingPai = 3, -- 其实确切说应该是查叫
}

return defineType