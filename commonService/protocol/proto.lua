local sprotoparser = require "sprotoparser"

local proto = {}

proto.c2s = sprotoparser.parse [[
.package { # . means a user defined type
    type 0 : integer
    session 1 : integer

}

ClientUserLoginHall 1 { #客户端请求登陆大厅
    request {
        iUserInfo 0 : string #json用户信息
    }
}

ClientUserLoginGame 2 { #客户端请求登录房间
    request {
        iUserId 0 : integer #玩家Id
        iUserInfoStr 1 : string #玩家信息
        iClientVersion 2 : string #客户端版本
        iGameLevel 3 : integer #场次等级,由配置文件给
        iReady 4 : integer #1准备，0未准备
        iTableId 5 : integer #指定进好友某一个房间
        iGoldFieldId 6 : integer #金币场特定场次
    }
}

ClientUserReady 3 {
    request {
        iUserId 0 : integer
        iReady 1 : integer #1准备，0未准备
    }
}

ClientUserOutCard 4 {
    request {
        iUserId 0 : integer
        iCardValue 1 : integer
    }
}

ClientUserTakeOp 5 {
    request {
        iOpValue 0 : integer
        iCardValue 1 : integer
    }
}

ClientUserLogoutGame 6 {
    request {
        iLeave 0 : integer  #为1则是房主解散房间
    }
}

ClientUserCreateFriendRoom 7 {
    request {
        iUserId 0 : integer #玩家Id
        iUserInfoStr 1 : string #玩家信息
        iClientVersion 2 : string #客户端版本
        iGameLevel 3 : integer #场次等级,由配置文件给
        iPlaytype 4 : integer
        iPayType 5 : integer  #支付方式 0房主出 1赢家出 3代理出
        iBattleTotalRound 6 : integer
        iExtendInfo 7 : string #其他信息
        iCreateForOther 8 : integer #0不是代开，1是代开
        iClubId 9 : integer #俱乐部ID
    }
}

ClientUserGetConfig 8 {
    request {
        #GetFriendRoomConfig获取好友对战场的配置(iGameCode是必须的)
        #GetGoldRoomConfig获取金币场配置(iGameCode是必须的)
        #GetAnnouncementConfig 获取公告(iGameCode是必须的)
        #GetAuditConfig 获取审核开关(iGameCode和iVersion是必须的)
        #GetShareActivityConfig 获取分享活动(iGameCode和iUserId是必须的)
        #SetShareActivityData 设置分享成功的数据(iGameCode和iUserId是必须的)
        iConfigName 0 : string
        iParamData 1 : string
    }
}

ClientUserGetBillList 9 {
    request {
        iUserId 0 : integer
    }
}

ClientUserGetBillDetail 10 {
    request {
        iUserId 0 : integer
        iBattleId 1 : string
    }
}

ClientUserDismissBattleRoom 11 {
    request {
    }
}

ClientUserDismissBattleSelect 12 {
    request {
        iSelect 0 : integer #1同意，2拒绝
    }
}

ClientUserSendChatFace 13 {
    request {
        iMsgType 0 : integer
        iChatMsg 1 : string
        iChatFace 2 : integer
    }
}

ClientUserSendVoiceSlice 14 {
    request {
        iTableId 0 : integer   #房间号
        iUserId 1 : integer    #用户id
        iSendUid 2 : integer   #接收id
        iVoiceId 3 : string   #语音id
        iSum 4 : integer       #总大小
        iIndex 5 : integer     #下标
        iLen 6 : integer       #当个长度
        iData 7 : string       #数据
        iPlayTime 8 : integer  #播放时间
    }
}

ClientUserRequestDelivery 15 {
    request {
        iUserId 0 : integer
        iParamData 1 : string
    }
}

ClientUserHeartbeat 16 {
    request {
    }
}

ClientUserReusetData 17 {
    request {
        iReusetName 0 : string #请求数据类型
        iUserId 1 : integer
        iParamData 2 : string #json 请求参数
    }
}

ClientUserGetBillLookback 18 {
    request {
        iUserId 0 : integer
        iLookbackId 1 : string
    }
}

ClientUserDismissOtherBattleRoom 19 {
    request {
        iTableId 0 : integer
    }
}

ClientUserAgentOpreation 20 {
    request {
        #AgentOpOtherRoomCard代理赠钻(iTUserId被赠送ID, iPassword密码, iRoomCardNum:钻石数)
        #AgentOpQueryUserInfo代理查询用户信息(iTUserId被查询ID)
        iOpName 0 : string
        iUserId 1 : integer
        iOpInfo 2 : string
    }
}

ClientUserSelectGangCard 21 {
    request {
        iCardValue 0 : integer
        iChaoDi 1 : integer #1抄底 0不抄
    }
}

ClientUserSelectDingQue 22 {
    request {
        iDingQue 0 : integer
    }
}

ClientUserHuanSanZhang 23 {
    request {
        iHuanCardTable 0 : *integer
    }
}

ClientUserBaoTing 24 {
    request {
        iBaoTing 0 : integer  #1是报听，-1是过
    }
}

ClientUserLangQi 25 {
    request {
        iLangQi 0 : integer  #1是廊起，0是过
    }
}

ClientPuKeUserOutCard 26 {
    request {
        iOpValue 0 : integer #操作值
        iOutCardValues 1 : *integer  #打出去的牌
        iDaiCardValues 2 : *integer  #带的牌
        iShowOutCardValues 3 : *iPokerInfo
        iShowDaiCardValues 4 : *iPokerInfo
    }
}

ClientZJHUserOpHandCard 27 {
    request {
        iOpValue 0 : integer #操作值
        iBeiShu 1 : integer #加倍数
        iUserIdTable 2 : *integer #被比牌Id列表，不包括自己
    }
}

ClientUserChangeUserInfo 28 {
    request {
        iUserInfo 0 : string
    }
}

ClientUserQiangZhuang 29 {
    request {
        iQiangZhuang 0 : integer #0不抢  1抢
    }
}

ClientUserRefreshUserData 30 {
    request {
        iUserIdTable 0 : *integer #需要刷新的用户表，注意是推送给UserId对应的玩家
        #iRoomCardNum
        iRefreshInfo 1 : string #json数据
    }
}

ClientDNUserXiaZhu 31 {
    request {
        iXiaZhu 0 : integer
    }
}

ClientDNUserXuanPai 32 {
    request {
        iHasNiu 0 : integer  #0无牛 1有牛
    }
}

ClientUserSelectMaiDian 33 {
    request {
        iMaiDian 0 : integer
    }
}

ClientLYCUserTakeOp 34 {
    request {
        iOpValue 0 : integer #操作值
        iXiaZhu 1 : LYCXiaZhuInfo
        iUserIdTable 2 : *integer #被比牌Id列表，不包括自己
    }
}

ClientUseriClubAutoCreateRoom 35 {
    request {
        iClubId 0 : integer
    }
}

ClientUserHaiDiLaoCard 36 {
    request {
        iLaoType 0 : integer #0不捞  1海底捞牌
    }
}

# 玩家认输
ClientUserRenShu 37 {
    request {
        iRenShu 0: integer #
    }
}

ClientUserTiYiJiao 38 {
    request {
        iTiType 0: integer # 1 踢  2 回
        iTiYiJiao 1 : integer #0不踢/不回   1踢一脚/回一脚
    }
}

ClientUserForcedDismissClubBattleRoom 39 {
    request {
        iTableId 0 : integer
    }
}

#象棋行棋
ClientXiangQiUserPlay 40 {
    request {
        iFromX 0 : integer # 
        iFromY 1 : integer #
        iToX 2 : integer  #
        iToY 3 : integer  #
    }
}

#悔棋
ClientXiangQiUserTakeOp 41 {
    request {
        iOpValue 0 : integer 
    }
}

#五子棋行棋
ClientWuZiQiUserPlayChess 42 {
    request {
        iPoint 0 : *integer #落子位置 talbe { x, y }
    }
}

#五子棋操作
ClientWuZiQiUserTakeOp 43 {
    request {
        iOpValue 0 : integer # 拒绝 悔棋 和棋 认输
    }
}

ClientUserAiStatus 44 {
    request {
        iAi 0 : integer #0是正常 1是托管
    }
}

.LYCXiaZhuInfo {
    iXiaZhu 0 : integer
    iStatus 1 : integer #0是正常下注码  1是码宝  2是走水
}

.iPokerInfo {
    iCardValue 1 : integer  #本来的值
    iShowValue 2 : integer  #展示出来的值
    iCardType 3 : integer
}

]]


proto.s2c = sprotoparser.parse [[
.package { # . means a user defined type
    type 0 : integer
    session 1 : integer
}

ServerUserLoginGameSuccess 1 {
    request {
        iGameCode 0 : integer #游戏类型
        iRoomType 1 : integer #房间类型
        iRoomOwnerId 2 : integer
        iBattleTotalRound 3 : integer
        iBattleCurRound 4 : integer
        iGameLevel 5 : integer #场次等级
        iTableId 6 : integer #桌子Id,对战场公用
        iTableName 7 : string #桌子名字
        iBasePoint 8 : integer #房间底注
        iServerFee 9 : integer #房间台费
        iPlaytype 10 : integer #房间玩法
        iPlaytypeStr 11 : string #房间玩法描述
        iMaxCardCount 12 : integer #房间牌数目
        iMaxUserCount 13 : integer #房间人数
        iOutCardTime 14 : integer #打牌时间
        iOperationTime 15 : integer #操作时间
        iUserTable 16 : *UserInfo #玩家信息
        iLocalGameType 17 : integer #游戏的本地分类
        iRoomOwnerName 18 : string #房主姓名
        iGameRoundInfo 19 : string #牌局中的信息
    }
}

ServerBCUserEnterTable 2 {
    request {
        iUserId 0 : integer
        iSeatId 1 : integer #座位号 1,2,3,4
        iMoney 2 : integer #钱
        iReady 3 : integer #是否已经准备
        iUserInfoStr 4 : string #玩家信息
    }
}

ServerBCUserReady 3 {
    request {
        iUserId 0 : integer
        iReady 1 : integer
    }
}

ServerBCUserLogoutTable 4 {
    request {
        iUserId 0 : integer
    }
}

ServerBCGameStart 5 {
    request {
        iBattleCurRound 0 : integer
        iGameRoundInfo 1 : string
    }
}

ServerBCMahjongMakeBanker 6 {
    request {
        iBankerSeatId 0 : integer
        iDiceTable 1 : *integer
        #-1第一局之类的不用显示, 0没有改变 1改变了
        iIsChange 2 : integer
    }
}

ServerBCUserDealCards 7 {
    request {
        iBankerSeatId 0 : integer
        iDiceTable 1 : *integer
        iHandCardMap 2 : *HandCardTable
        iRemainCardCount 3 : integer #剩余牌
    }
}

ServerBCUserDrawCard 8 {
    request {
        iUserId 0 : integer
        iCardValue 1 : integer #大于0是正常的
        iOpTable 2 : *OpInfo
        iAllCardTingInfoTable 3 : *TingCardInfoTable
        iRemainCardCount 4 : integer
        iCanNotOutCard 5 : integer #1不可打 0可打
    }
}

ServerBCUserOutCard 9 {
    request {
        iUserId 0 : integer
        iCardValue 1 : integer #大于0是正常的
        iOpTable 2 : *OpInfo
    }
}

ServerBCUserBankerCanOp 10 {
    request {
        iUserId 0 : integer
        iOpTable 1 : *OpInfo
        iAllCardTingInfoTable 2 : *TingCardInfoTable
        iRemainCardCount 3 : integer
    }
}

ServerUserLoginHall 11 {
    request {
        iStatus 0 : integer #状态, 1登陆成功
        iLoginMsg 1 : string #登陆的消息
        iUserInfo 2 : string #用户信息
        iIsInGame 3 : integer #1是在游戏中
    }
}

ServerBCUserTakeOp 12 {
    request {
        iTakeOpInfo 0 : *TakeOpInfo
        iOpTable 1 : *OpInfo
        iAllCardTingInfoTable 2 : *TingCardInfoTable
        iTotalHuCount 3 : integer
    }
}

ServerBCGameStopOneRound 13 {
    request {
        iRoomType 0 : integer  #0 金币场 1 好友对战
        iResultType 1 : integer   #0 玩家有人胡牌  1 流局 2中途退出
        iTimeStamp 2 : integer
        iUserTable 3 : *GameStopUserInfo
        iIsBattleStop 4 : integer #0未结束 1结束
        iBattleStopUserTable 5 : *GameOverUserInfo
        iMaiMaCardInfoTable 6 : *integer
    }
}

ServerUserKickOff 14 {
    request {
        iKickMsg 0 : string
    }
}

ServerUserReconnect 15 {
    request {
        iGameCode 0 : integer #游戏类型
        iRoomType 1 : integer #房间类型
        iRoomOwnerId 2 : integer
        iBattleTotalRound 3 : integer
        iBattleCurRound 4 : integer
        iGameLevel 5 : integer #场次等级
        iTableId 6 : integer #桌子Id
        iTableName 7 : string #桌子名字
        iBasePoint 8 : integer #房间底注
        iServerFee 9 : integer #房间台费
        iPlaytype 10 : integer #房间玩法
        iPlaytypeStr 11 : string #房间玩法描述
        iMaxCardCount 12 : integer #房间牌数目
        iMaxUserCount 13 : integer #房间人数
        iOutCardTime 14 : integer #打牌时间
        iOperationTime 15 : integer #操作时间
        iRemainCardCount 16 : integer #剩余牌
        iIsInGame 17 : integer #是否在游戏中
        iBankerSeatId 18 : integer
        iIsCanOutCard 19 : integer #0不可以，1可以
        iDrawCardUserId 20 : integer #抓牌玩家的Id,该玩家需打牌或者操作
        iOutCardUserId 21 : integer #打牌玩家的Id,等待别人操作中
        iUserTable 22 : *GameReconnetUserInfo #玩家信息
        iLocalGameType 23 : integer
        iRoomOwnerName 24 : string #房主姓名
    }
}

ServerUserLoginGameFail 17 {
    request {
        iErrorType 0 : integer
        iErrorMsg 1 : string
    }
}

ServerUserGetBillList 18 {
    request {
        iUserBillList 0 : *string
    }
}

ServerUserGetBillDeatail 19 {
    request {
        iBattleId 0 : string
        iBattleAllRoundInfo 1 : string
    }
}

ServerBCUserDismissBattleRoom 20 {
    request {
        iUserId 0 : integer #发起玩家
        iRemainTime 1 : integer #剩余倒计时
        iDismissBattleUserTable 2 : *DismissBattleUserInfo
    }
}

ServerBCUserRefuseDismissBattle 21 {
    request {
        iUserId 0 : integer #拒绝玩家
        iRefuseStr 1 : string #显示语句
    }
}

ServerBCUserSendChatFace 22 {
    request {
        iUserId 0 : integer
        iMsgType 1 : integer
        iChatMsg 2 : string
        iChatFace 3 : integer
    }
}

ServerUserGetConfig 23 {
    request {
        iConfigName 0 : string
        iConfigData 1 : string
    }
}

ServerBCUserIsOnline 24 { #广播用户断线
    request {
        iUserId 0 : integer #玩家Id
        iIsOnline 1 : integer #1在线，0离线
        iTime 2 : integer #倒计时
    }
}

ServerUserSendVoiceSlice 25 { #用户发送语音片返回
    request {
        iUserId 0 : integer   #用户uid
        iStatus 1 : integer   #0表示失败，1表示成功
        iIndex 2 : integer    #下标
        iTableId 3 : integer      #房间id
        iVoiceId 4 : string   #语音id
    }
}

ServerBCUserSendVoiceSlice 26 { #广播玩家语音发送
    request {
        iUserId 0 : integer     #用户uid
        iTableId 1 : integer    #桌子id
        iSendUid 2 : integer    #接收id
        iVoiceId 3 : string    #语音id
        iSum 4 : integer        #总大小
        iIndex 5 : integer      #下标
        iLen 6 : integer        #长度
        iData 7 : string        #数据
        iPlayTime 8 : integer   #播放时间
    }
}

ServerUserShowHints 27 { #用户显示提示
    request {
        iShowType 0 : integer #0显示Banner 1显示弹框
        iShowMsg 1 : string #显示内容
    }
}

ServerUserRequestDelivery 28 { #给玩家发货
    request {
        iStatus 0 : integer #0是正常
        iData 1 : string
    }
}

ServerUserHeartbeat 29 {
    request {
    }
}

ServerBCUserInfoChange 30 {
    request {
        iUserId 0 : integer
        iUserInfo 1 : string #json用户信息
    }
}

ServerUserGetBillLookback 31 {
    request {
        iLookbackId 0 : string
        iBattleLookbackData 1 : string
    }
}

ServerUserCreateForOther 32 {
    request {
        iUserId 0 : integer
        iTableId 1 : integer
        iRoomCardNum 2 : integer
        iPlaytypeStr 3 : string
        iGameInfo 4 : string
    }
}

ServerUserAgentOpreation 33 {
    request {
        iOpName 0 : string
        iUserId 1 : integer
        iOpInfo 2 : string
    }
}

ServerBCGameLastCardNotOut 34 {
    request {
        iLastCardInfoTable 0 : *LastCardInfo
    }
}

ServerBCMahjongMakeGangCard 35 {
    request {
        iGangCardTable 0 : *integer
        iRemainCardCount 1 : integer
    }
}

ServerUserSelectGangCard 36 {
    request {
        iGangCardTable 0 : *GangCardInfo
        iIsCanChaoDi 1 : integer #1可以抄底
    }
}

ServerBCMahjongStartHuanSanZhang 37 {
    request {
        iIsCanRenYiHuan 0 : integer
    }
}

ServerUserDoneHuanSanZhang 38 {
    request {
        iUserId 0 : integer
        iHuanCardTable 1 : *integer
    }
}

ServerBCMahjongDoneHuanSanZhang 39 {
    request {
        iUserId 0 : integer
        iHuanCardTable 1 : *integer
        iHandCards 2 : *integer
    }
}

ServerBCMahjongStartDingQue 40 {
    request {
        iDingQueTable 0 : *iDingQueInfo
    }
}

ServerBCMahjongDoneDingQue 41 {
    request {
        iDingQueDoneTable 0 : *iDingQueDoneInfo
    }
}

ServerBCUserCanBaoTing 42 {
    request {
        iBaoTingTable 0 : *integer
    }
}

ServerBCUserBaoTing 43 {
    request {
        iBaoTingTable 0 : *integer
    }
}

ServerBCUserLangQi 44 {
    request {
        iAllLangQiInfoTable 0 : *LangQiInfoTable
    }
}

ServerBCPuKeOutCard 45 {
    request {
        iUserId 0 : integer #打牌玩家的Id
        iPuKeOutCardInfo 1 : PuKeOutCardInfo #打出去的牌
        iIsFirstOutCard 2 : integer #1第一次打牌 0不是
        iNeedOutCards 3 : *integer #必须要出的牌
        iCurOutUserId 4 : integer #当前出牌玩家
        iOpCanOpValue 5 : integer #可以出牌的操作
        iBaoDanOrShuang 6 : integer #0不报 1报单 2报双
        iNeedOutMaxCard 7 : integer #0不需要 1需要
        iIsReConnect 8 : integer #0不是重连 1重连
        iBeiShu 9 : integer #当前的加倍数,炸弹什么的要加倍的
        iRemainCardCount 10 : integer #剩余牌
        iCanNotOutCards 11 : *integer #不能出的牌
    }
}

ServerNewUserReconnect 46 {
    request {
        iGameCode 0 : integer #游戏类型
        iRoomType 1 : integer #房间类型
        iRoomOwnerId 2 : integer
        iBattleTotalRound 3 : integer
        iBattleCurRound 4 : integer
        iGameLevel 5 : integer #场次等级
        iTableId 6 : integer #桌子Id
        iTableName 7 : string #桌子名字
        iBasePoint 8 : integer #房间底注
        iServerFee 9 : integer #房间台费
        iPlaytype 10 : integer #房间玩法
        iPlaytypeStr 11 : string #房间玩法描述
        iMaxCardCount 12 : integer #房间牌数目
        iMaxUserCount 13 : integer #房间人数
        iOutCardTime 14 : integer #打牌时间
        iOperationTime 15 : integer #操作时间
        iIsInGame 16 : integer #是否在游戏中
        iLocalGameType 17 : integer
        iRoomOwnerName 18 : string #房主姓名
        iGameRoundInfo 19 : string #牌局中的信息
        iUserTable 20 : *GameNewReconnetUserInfo #玩家信息
    }
}

ServerBCZJHUserCanOp 47 {
    request {
        iUserId 0 : integer
        iCanOpValue 1 : integer
        iCurXiaZhu 2 : integer
        iBeiShu 3: integer
        iLunCi 4 : integer
    }
}

ServerBCZJHUserTakeOp 48 {
    request {
        iUserId 0 : integer
        iOpValue 1 : integer
        iXiaZhu 2 : integer
        iHandCards 3 : *integer
        iCurXiaZhu 4 : integer
        iCardType 5 : integer
    }
}

ServerBCZJHUserCompareCard 49 {
    request {
        iUserIdTable 0 : *integer
        iWinUserId 1 : integer
    }
}

ServerBCZJHQianZhu 50 {
    request {
        iQianZhuTable 0 : *ZJHQianZhuInfo
    }
}

ServerUserStartGameUserId 51 {
    request {
        iUserId 0 : integer
        iNeedCount 1 : integer #满多少人才显示
    }
}

ServerBCUserChangeUserInfo 52 {
    request {
        iUserId 0 : integer
        iUserInfo 1 : string
    }
}

ServerBCLYCUserCanOp 53 {
    request {
        iUserId 0 : integer
        iOpCanOpValue 1 : integer
        iXiaZhuTable 2 : *LYCXiaZhuInfo
        iHandCards 3 : *integer
    }
}

ServerBCLYCProcessValue 54 {
    request {
        #1是下注阶段 2是庄家炸开 3是闲家操作 4是补牌 5是庄家比牌 6是庄家操作 7是系统比牌
        iProcessValue 0 : integer
    }
}

ServerBCLYCUserCompareCard 55 {
    request {
        iUserId 0 : integer #这个是当前玩家的，即非庄家
        iHandCards 1 : *integer
        iDianShu 2 : integer
        iCardType 3 : integer
        iCompareType 4 : integer #1胜 2平 3负
    }
}

ServerBCLYCUserTakeOp 56 {
    request {
        iUserId 0 : integer
        iOpValue 1 : integer
        iXiaZhu 2 : LYCXiaZhuInfo
        iHandCards 3 : *integer
        iDianShu 4 : integer
        iCardType 5 : integer
    }
}

ServerBCStartQiangZhuang 57 {
    request {
        #1是固定庄 2是抢庄
        iQiangType 0 : integer
    }
}

ServerBCDNStartXiaZhu 58 {
    request {
        iUserId 0 : integer
        iXiaZhuTable 1 : *integer
    }
}

ServerBCDNUserXiaZhu 59 {
    request {
        iUserId 0 : integer
        iXiaZhu 1 : integer
    }
}

ServerBCDNUserStartXuanPai 60 {
    request {
        iUserId 0 : integer
        iHandCards 1 : *integer
        iNiuTips 2 : *integer
        iDianShu 3 : integer
        iCardType 4 : integer
    }
}

ServerBCMahjongStartMaiDian 61 {
    request {
        iUserId 0 : integer
        iMaiDianTable 1 : *integer
    }
}

ServerBCMahjongUserMaiDianDone 62 {
    request {
        iUserId 0 : integer
        iMaiDian 1 : integer
    }
}

ServerBCDNUserXuanPaiDone 63 {
    request {
        iUserId 0 : integer
    }
}

ServerBCDNUserOtherHandCards 64 {
    request {
        iUserId 0 : integer
        iHandCards 1 : *integer
        iOtherCards 2 : *integer
    }
}

ServerBCDDZUserStartQiangDiZhu 65 {
    request {
        iUserId 0 : integer
        iQiangDiZhuInfo 1 : *DDZQiangDiZhuInfo
    }
}

ServerBCDDZUserDoneQiangDiZhu 66 {
    request {
        iUserId 0 : integer
        iFen 1 : integer # 0是不抢  其它的是抢多少分
        iDiZhuPoint 2 : integer # 抢了的地主分
        iBeiShu 3 : integer #加倍数
        iQiangStatus 4 : integer #抢地主的状态，可用来扩展
    }
}

ServerBCDDZMakeBanker 67 {
    request {
        iBankerSeatId 0 : integer
        iDiZhuPoint 1 : integer
        iDiZhuCards 2 : *integer #地主牌
        iBeiShu 3 : integer #加倍数
        iDoNotShow 4 : integer #不展示地主牌
        iQiangStatus 5 : integer #抢地主的状态，可用来扩展
    }
}

ServerBCMahjongStartLaoCard 68 {
    request {
        iUserId 0 : integer
    }
}

ServerBCMahjongDoneLaoCard 69 {  #玩家选择了捞牌
    request {
        iUserId 0 : integer
        iCardValue 1 : integer #大于0说明玩家选择了捞牌
        iOpTable 2 : *OpInfo
    }
}

ServerBCPuKeOpCard 70 {
    request {
        iUserId 0 : integer
        iOpValue 1 : integer
        iRemainCardCount 2 : integer #剩余牌
        iHandCardMap 3 : *HandCardTable
    }
}

ServerBCPuKeIntegralCards 71 {
    request {
        iWSKIntegralCardsInfo 0 : *WSKIntegralCardsInfo
    }
}

ServerBCBankerSeatIds 72 {
    request {
        iBankerSeatIds 0 : *integer
    }
}

ServerBCPuKeLaiZiCards 73 {
    request {
        iLaiZiCards 0 : *iPokerInfo #广播扑克的癞子是哪几张
    }
}

# 告诉玩家能不能认输
ServerBCPuKeUserCanRenShu 74 {
    request {
        iCanRenShu 0: integer # 0：玩家不可以认输  1：玩家可以认输了
    }
}

#普洱斗地主，开局先翻一张牌，谁摸到这张牌，谁开始叫地主
ServerBCPuKeUserFanPai 75 {
    request {
        iFanPai 0: *integer #牌值，牌的序号
        iUserId 1: integer #取到地主的ID
    }
}

# 跑得快算炸弹分
ServerBCUserOutBomb 76 {
    request {
        iZhaDanFenTable 0 : *PDKZhaDanFen
    }
}

# 只针对麻将回放：用来告诉当前所有人的全部操作
ServerBCLookbackAllUserOpTable 77 {
    request {
        iLokkbackOpTable 0 : *LookbackOpTable
    }
}

# 只针对麻将回放：用来告诉当前有人进行了操作
ServerBCLookbackUserTakeOp 78 {
    request {
        iTakeOpInfo 0 : TakeOpInfo
    }
}

# 广播开始踢一脚或回一脚操作
ServerBCUserTiYiJiaoStart 79 {
    request {
        iUserId 0: integer   # 踢一脚的玩家
        iTiType 1: integer   # 1踢   2 回
        iTiInfo 2: *integer  # 0不踢/不回  1 踢一脚/回一脚
    }
}

# 广播玩家操作的踢一脚或回一脚
ServerBCUserTiYiJiaoDone 80 {
    request {
        iUserId 0: integer   # 踢一脚的玩家
        iTiType 1: integer   # 1踢   2 回
        iTiYiJiao 2: integer  # 0不踢/不回  1 踢一脚/回一脚
    }
}

#象棋行棋
ServerBCUserXiangQiUserMove 81 {
    request {
        iUserId 0: integer #下棋的玩家
        iXiangQiMoveInfo 1: XiangQiMoveInfo #象棋移动的信息
        iCurPlayUserId 2: integer #当前行棋玩家
        iIsReConnect 3 : integer #0不是重连 1重连(或不需要改变客户端棋子的情况)
        iOpTable 4 : *XiangQiOpInfo #当前用户能进行的操作（悔棋，和棋，头像等操作）
    }
}

#象棋的操作
ServerBCXiangQiOpChess 82 {
    request {
        iUserId 0: integer #操作玩家
        iOpValue 1: integer # 
        iXiangQiMoveRecords 2: *XiangQiMoveInfo #象棋移动的记录,给悔棋用
        iOpTable 3 : *XiangQiOpInfo #当前用户能进行的操作（悔棋，和棋，头像等操作）
        iExtendInfo 4: string #额外信息
    }
}

#五子棋行棋
ServerBCWuZiQiPlayChess 83 {
    request {
        iUserId 0 : integer #下棋玩家的id
        iCurOutUserId 1 : integer #当前下棋玩家
        iWuZiQiInfo 2 : WuZiQiInfo #五子棋状态
        iIsReConnect 3 : integer #0不是重连 1重连
    }
}

#五子棋操作
ServerBCWuZiQiOpChess 84 {
    request {
        iUserId 0 : integer #操作玩家
        iOpValue 1 : integer #操作内容 拒绝 悔棋 和棋
    }
}

ServerBCUserAiStatus 85 {
    request {
        iUserId 0 : integer
        iAi 1 : integer
    }
}

ServerBCUserNeedUpdate 86 {
    request {
        iConfigValue 0 : integer
    }
}

ServerBCMahjongBuHua 87 {
    request {
        iUserId 0 : integer
        iBuPai 1 : integer
        iHuaPai 2 : *integer
        iHandCards 3 : *integer
    }
}

ServerBCMahjongMoneyUpdate 88 {
    request {
        iMoneyTable 0 : *MoneyInfo
    }
}

ServerBCMahjongJiaPai 89 {
    request {
        iJiaPaiInfo 0 : *JiaPaiInfo
    }
}


.MoneyInfo {
    iUserId 0 : integer
    iMoney 1 : integer
}

.JiaPaiInfo {
    iUserId 0 : integer
    iCardValue 1 : integer
}

.WuZiQiInfo {
    iPoint 0 : *integer #落子位置 table { x, y }
    iChessboard 1 : *integer #棋盘状态 table
    iType 2 : integer #连棋类型 无 五连 长连禁手 四四禁手 三三禁手 和棋
}

.XiangQiOpInfo {
    iUserId 0 : integer
    iOpValue 1 : integer
    iExtend 2 : integer
}

.XiangQiMoveInfo{
    iFromValue 0 : integer # 
    iToValue 1 : integer #
    iCurValue 2 : integer  #
    iMoveType 3: integer # 0 行棋  1 吃子  2 悔棋  3 将军   4 将死 游戏结束   5 和棋
    iStepNumber 4 : integer #当前下棋玩家行棋步数
}

.LookbackOpTable {
    iUserId 0 : integer
    iOpTable 1 : *OpInfo
}

.PDKZhaDanFen{
    iUserId 0 : integer
    iFen 1 : integer
}

.WSKIntegralCardsInfo{
    iUserId 0 : integer
    iCards 2 : *integer
}

.DDZQiangDiZhuInfo {
    iFen 0: integer # 0是不抢  其它的是抢多少分
    iStatus 1: integer #0不能操作  1能操作
}

.LYCXiaZhuInfo {
    iXiaZhu 0 : integer
    iStatus 1 : integer #0是正常下注码  1是码宝  2是走水
}

.ZJHQianZhuInfo {
    iUserId 0 : integer
    iXiaZhu 1 : integer
}

.PuKeOutCardInfo {
    iOpValue 0 : integer #操作值
    iOutCardValues 1 : *integer  #打出去的牌
    iDaiCardValues 2 : *integer  #带的牌
    iShowOutCardValues 3 : *iPokerInfo
    iShowDaiCardValues 4 : *iPokerInfo
}

.iPokerInfo {
    iCardValue 1 : integer  #本来的值
    iShowValue 2 : integer  #变化后的值
    iCardType 3 : integer
}

.DismissBattleUserInfo {
    iUserId 0 : integer
    iIsOnline 1 : integer #0不在线， 1在线
    iDismissStatus 2 : integer #0未操作 1同意 2不同意
}

.BattleOneRoundBill {
    iTimeStamp 0 : integer
    iTurnMoneyTable 1 : *BattleOneRoundTurnMoney
}

.BattleOneRoundTurnMoney {
    iUserId 0 : integer
    iTurnMoney 1 : integer
}

.GameReconnetUserInfo {
    iUserId 0 : integer
    iSeatId 1 : integer #座位号 1,2,3,4
    iMoney 2 : integer #钱
    iReady 3 : integer #是否已经准备
    iIsOnline 4 : integer #1在线，0离线
    iUserInfoStr 5 : string #玩家信息
    iHandCards 6 : *integer
    iBlockCards 7 : *OpInfo
    iOutCards 8 : *OutCard
    iOpTable 9 : *OpInfo
    iAllCardTingInfoTable 10 : *TingCardInfoTable
    iExtendInfo 11 : string #其他信息
}

.GameNewReconnetUserInfo {
    iUserId 0 : integer
    iSeatId 1 : integer #座位号 1,2,3,4
    iMoney 2 : integer #钱
    iReady 3 : integer #是否已经准备
    iIsOnline 4 : integer #1在线，0离线
    iUserInfoStr 5 : string #玩家信息
    iUserGameInfo 6 : string #牌信息
    iExtendInfo 7 : string #其他信息
}

.GameOverUserInfo {
    iUserId 0 : integer
    iNickName 1 : string
    iHeadUrl 2 : string
    iTurnMoney 3 : integer
    iExtendInfo 4 : string
}

.GameStopUserInfo {
    iUserId 0 : integer
    iHandCards 1 : *integer
    iBlockCards 2 : *OpInfo
    iMoney 3 : integer   #玩家手上的分数
    iTurnMoney 4 : integer     #这局变化的分数
    iExtendInfo 5 : string     #特定麻将的番型
}

.TakeOpInfo {
    iUserId 0 : integer
    iOpValue 1 : integer
    iTUserId 2 : integer
    iCardValue 3 : integer
}

.OutCard {
    iCardValue 0 : integer
    iStatus 1 : integer  #0是正常，1被吃碰杠胡
}

.OpInfo {
    iOpValue 0 : integer
    iCardValue 1 : integer
}

.TingCardInfoTable {
    iTingCardValue 0 : integer
    iTingCardInfoTable 1 : *OneCardTingInfo
}

.OneCardTingInfo {
    iCardValue 0 : integer
    iFan 1 : integer
    iCardCount 2 : integer
    iName 3 : string
    iNeed 4 : string
}

.LangQiInfoTable {
    iLangQiOutCardValue 0 : integer
    iLangQiInfoTable 1 : *OneCardLangQiInfo
}

.OneCardLangQiInfo {
    iTingCardInfoTable 0 : *OneCardTingInfo
    iLangQiCardTable 5 : *LangQiCardTable
}

.LangQiCardTable {
    iCardTable 0 : *integer
}

.HandCardTable {
    iSeatId 0 : integer
    iHandCards 2 : *integer
}

.UserInfo {
    iUserId 0 : integer
    iSeatId 1 : integer #座位号 1,2,3,4
    iMoney 2 : integer #钱
    iReady 3 : integer #是否已经准备
    iIsOnline 4 : integer #1在线，0离线
    iUserInfoStr 5 : string #玩家信息
}

.LastCardInfo {
    iUserId 0 : integer
    iCardValue 1 : integer
    iOpTable 2 : *OpInfo
}

.GangCardInfo {
    iCardValue 0 : integer
    iCanSelect 1 : integer  #0不可选 1可选
    iName 2 : string #提示番数等信息，可以先不用
}

.iDingQueInfo {
    iDingQue 0 : integer #1万2筒3条
    iRecommend 1 : integer #0不推荐1推荐
}

.iDingQueDoneInfo {
    iUserId 0 : integer
    iDingQue 1 : integer #1万2筒3条
}

]]

return proto
