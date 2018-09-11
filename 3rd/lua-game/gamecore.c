/**
*  $Id: game.c,v 1.10 2018/01/12 12:51:27 NextChai Exp $
*  Cryptographic and Hash functions for Lua
*  @author  NextChai
*/


#include <stdio.h>
#include <stdlib.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

int mahjongComplete(short pCardCountTwoMap[5][10], int pHasJiang);
int mahjongCompleteLaiZi(short pCardCountTwoMap[5][10], int pHasJiang, int pLaiZiCount);

#define min(a, b) (a <= b ? a : b)

static int lOnComplete(lua_State *L) {
	if (!lua_istable(L, -2)){
		luaL_error(L, lua_typename(L, -2));
		luaL_error(L, "麻将表参数1错误");
		return 0;
	}
	if (!lua_isinteger(L, -1)){
		luaL_error(L, lua_typename(L, -1));
		luaL_error(L, "麻将表参数2错误");
		return 0;
	}

	int pHasJiang = luaL_checknumber(L, -1);
	// luaL_error(L, "pHasJiang = %d", pHasJiang);
	lua_pop(L, 1);
	// 先初始化麻将表
	short pCardCountTwoMap[5][10] = {0};
	// memset(pCardCountTwoMap, sizeof(short), 0);
	for(int i = 0; i <= 4; ++i){
		lua_pushinteger(L, i + 1);
		lua_gettable(L, -2);
		if (!lua_istable(L, -1)){
			luaL_error(L, "麻将数据不是二位表");
			return 0;
		}
		for(int j = 0; j <= 9; ++j){
			lua_pushinteger(L, j + 1);
			lua_gettable(L, -2);
			short pTemp = (short)lua_tointeger(L, -1);
			// printf("%d, top = %d\n", pTemp, lua_gettop(L));
			pCardCountTwoMap[i][j] = pTemp;
			lua_pop(L, 1);
		}
		lua_pop(L, 1);
	}
	

	// 看是能不能听牌
	// if (0 == mahjongComplete(pCardCountTwoMap, pHasJiang)){
		lua_pushinteger(L, mahjongComplete(pCardCountTwoMap, pHasJiang));
	// }else{
	// 	lua_pushinteger(L, 1);
	// }
  	return 1;
}

void printCardCountTwoMap(short pCardCountTwoMap[5][10]){
	printf("-------------------------------\n");
	for (int i = 0; i <= 4; ++i){
		for (int j = 0; j <= 9; ++j){
			printf("%d ", pCardCountTwoMap[i][j]);
		}
		printf("\n");
	}
}

int mahjongComplete(short pCardCountTwoMap[5][10], int pHasJiang){
	// printCardCountTwoMap(pCardCountTwoMap);
	int pCardCount = 0;
	for(int i = 0; i <= 4; ++i){
		pCardCount += pCardCountTwoMap[i][9];
	}
	if (pCardCount <= 0){
		return 0;
	}
	for (int i = 0; i <= 4; ++i){
		if (!pHasJiang){
			if (pCardCountTwoMap[i][9] >= 2){
				for (int j = 0; j <= 8; ++j){
					if (pCardCountTwoMap[i][j] >= 2){
						pCardCountTwoMap[i][j] -= 2;
						pCardCountTwoMap[i][9] -= 2;
						int pIsOk = mahjongComplete(pCardCountTwoMap, 1);
						if (pIsOk == 0) return 0;
						pCardCountTwoMap[i][j] += 2;
						pCardCountTwoMap[i][9] += 2;
					}
				}
			}
		}
		else{
			if (pCardCountTwoMap[i][9] >= 3){
				for (int j = 0; j <= 8; ++j){
					// 先试试3张牌的
					if (pCardCountTwoMap[i][j] >= 3){
						pCardCountTwoMap[i][j] -= 3;
						pCardCountTwoMap[i][9] -= 3;
						int pIsOk = mahjongComplete(pCardCountTwoMap, pHasJiang);
						if (pIsOk == 0) return 0;
						pCardCountTwoMap[i][j] += 3;
						pCardCountTwoMap[i][9] += 3;
					}
					// 如果能凑顺子
					if (i <= 2 && j <= 6 && pCardCountTwoMap[i][j] >= 1 && 
						pCardCountTwoMap[i][j+1] >= 1 && pCardCountTwoMap[i][j+2] >= 1){
						pCardCountTwoMap[i][j] -= 1;
						pCardCountTwoMap[i][j+1] -= 1;
						pCardCountTwoMap[i][j+2] -= 1;
						pCardCountTwoMap[i][9] -= 3;
						int pIsOk = mahjongComplete(pCardCountTwoMap, pHasJiang);
						if (pIsOk == 0) return 0;
						pCardCountTwoMap[i][j] += 1;
						pCardCountTwoMap[i][j+1] += 1;
						pCardCountTwoMap[i][j+2] += 1;
						pCardCountTwoMap[i][9] += 3;
					}
				}
			}
			// 处理完成之后，如果这个门还有牌，则不能胡
			if (pCardCountTwoMap[i][9] >= 1){
				return -1;
			}
		}
	}

	return -1;
}

static int lOnCompleteLaiZi(lua_State *L) {
	if (!lua_istable(L, -3)){
		luaL_error(L, lua_typename(L, -3));
		luaL_error(L, "麻将表参数1错误");
		lua_pushinteger(L, -1);
		return 0;
	}
	if (!lua_isinteger(L, -2)){
		luaL_error(L, lua_typename(L, -2));
		luaL_error(L, "麻将表参数2错误");
		lua_pushinteger(L, -1);
		return 0;
	}
	if (!lua_isinteger(L, -1)){
		luaL_error(L, lua_typename(L, -1));
		luaL_error(L, "麻将表参数3错误");
		lua_pushinteger(L, -1);
		return 0;
	}

	int pHasJiang = luaL_checknumber(L, -2);
	int pLaiZiCount = luaL_checknumber(L, -1);
	lua_pop(L, 2);
	// 先初始化麻将表
	short pCardCountTwoMap[5][10] = {0};
	// memset(pCardCountTwoMap, sizeof(short), 0);
	for(int i = 0; i <= 4; ++i){
		lua_pushinteger(L, i + 1);
		lua_gettable(L, -2);
		if (!lua_istable(L, -1)){
			luaL_error(L, "麻将数据不是二位表");
			return 0;
		}
		for(int j = 0; j <= 9; ++j){
			lua_pushinteger(L, j + 1);
			lua_gettable(L, -2);
			short pTemp = (short)lua_tointeger(L, -1);
			// printf("%d, top = %d\n", pTemp, lua_gettop(L));
			pCardCountTwoMap[i][j] = pTemp;
			lua_pop(L, 1);
		}
		lua_pop(L, 1);
	}
	lua_pushinteger(L, mahjongCompleteLaiZi(pCardCountTwoMap, pHasJiang, pLaiZiCount));
  	return 1;
}

int mahjongCompleteLaiZi(short pCardCountTwoMap[5][10], int pHasJiang, int pLaiZiCount){
	// printCardCountTwoMap(pCardCountTwoMap);
	int pCardCount = 0;
	for(int i = 0; i <= 4; ++i){
		pCardCount += pCardCountTwoMap[i][9];
	}
	if (pCardCount <= 0){
		return 0;
	}
	for (int i = 0; i <= 4; ++i){
		if (!pHasJiang){
			if (pCardCountTwoMap[i][9] >= 1 && pCardCountTwoMap[i][9] + pLaiZiCount >= 2){
				for (int j = 0; j <= 8; ++j){
					if (pCardCountTwoMap[i][j] >= 1 && pCardCountTwoMap[i][j] + pLaiZiCount >= 2){
						int pNeedLaiZi = 2 - min(pCardCountTwoMap[i][j], 2);
						pCardCountTwoMap[i][j] -= (2 - pNeedLaiZi);
						pCardCountTwoMap[i][9] -= (2 - pNeedLaiZi);
						int pIsOk = mahjongCompleteLaiZi(pCardCountTwoMap, 1, pLaiZiCount - pNeedLaiZi);
						if (pIsOk == 0) return 0;
						pCardCountTwoMap[i][j] += (2 - pNeedLaiZi);
						pCardCountTwoMap[i][9] += (2 - pNeedLaiZi);
					}
				}
			}
		}
		else{
			if (pCardCountTwoMap[i][9] >= 1 && pCardCountTwoMap[i][9] + pLaiZiCount >= 3){
				for (int j = 0; j <= 8; ++j){
					// 先试试3张牌的
					if (pCardCountTwoMap[i][j] >= 1 && pCardCountTwoMap[i][j] + pLaiZiCount >= 3){
						int pNeedLaiZi = 3 - min(pCardCountTwoMap[i][j], 3);
						pCardCountTwoMap[i][j] -= (3 - pNeedLaiZi);
						pCardCountTwoMap[i][9] -= (3 - pNeedLaiZi);
						int pIsOk = mahjongCompleteLaiZi(pCardCountTwoMap, pHasJiang, pLaiZiCount - pNeedLaiZi);
						if (pIsOk == 0) return 0;
						pCardCountTwoMap[i][j] += (3 - pNeedLaiZi);
						pCardCountTwoMap[i][9] += (3 - pNeedLaiZi);
					}
					// 如果能凑顺子
					if (i <= 2 && j <= 6 && pCardCountTwoMap[i][j] >= 1){
						int pNeedLaiZi = 0, pNeedLaiZi1 = 0, pNeedLaiZi2 = 0;
						if (pCardCountTwoMap[i][j+1] <= 0){
							pNeedLaiZi += 1;
							pNeedLaiZi1 = 1;
						}
						if (pCardCountTwoMap[i][j+2] <= 0){
							pNeedLaiZi += 1;
							pNeedLaiZi2 = 1;
						}
						if (pLaiZiCount >= pNeedLaiZi && pNeedLaiZi <= 1){
							pCardCountTwoMap[i][j] -= 1;
							pCardCountTwoMap[i][9] -= 1;
							if (!pNeedLaiZi1){
								pCardCountTwoMap[i][j+1] -= 1;
								pCardCountTwoMap[i][9] -= 1;
							}
							if (!pNeedLaiZi2){
								pCardCountTwoMap[i][j+2] -= 1;
								pCardCountTwoMap[i][9] -= 1;
							}
							int pIsOk = mahjongCompleteLaiZi(pCardCountTwoMap, pHasJiang, pLaiZiCount - pNeedLaiZi);
							if (pIsOk == 0) return 0;
							pCardCountTwoMap[i][j] += 1;
							pCardCountTwoMap[i][9] += 1;
							if (!pNeedLaiZi1){
								pCardCountTwoMap[i][j+1] += 1;
								pCardCountTwoMap[i][9] += 1;
							}
							if (!pNeedLaiZi2){
								pCardCountTwoMap[i][j+2] += 1;
								pCardCountTwoMap[i][9] += 1;
							}
						}
					}
					// 如果能凑顺子，当且仅当没有7的牌有8,9的牌的时候
					if (i <= 2 && j == 7 && pCardCountTwoMap[i][j-1] <= 0 && 
						pCardCountTwoMap[i][j] >= 1 && pCardCountTwoMap[i][j+1] >= 1  && pLaiZiCount >= 1){

						pCardCountTwoMap[i][j] -= 1;
						pCardCountTwoMap[i][j+1] -= 1;
						pCardCountTwoMap[i][9] -= 2;
						int pIsOk = mahjongCompleteLaiZi(pCardCountTwoMap, pHasJiang, pLaiZiCount - 1);
						if (pIsOk == 0) return 0;
						pCardCountTwoMap[i][j] += 1;
						pCardCountTwoMap[i][j+1] += 1;
						pCardCountTwoMap[i][9] += 2;
					}
				}
			}
			// 处理完成之后，如果这个门还有牌，则不能胡
			if (pCardCountTwoMap[i][9] >= 1){
				return -1;
			}
		}
	}

	return -1;
}

static struct luaL_Reg gamelib[] = {
	{"onComplete", lOnComplete},
	{"onCompleteLaiZi", lOnCompleteLaiZi},
	{NULL, NULL}
};

int luaopen_gamecore(lua_State *L) {
	// lua_newtable(L);
  	// luaL_setfuncs(L, gamelib, 0);
  	luaL_newlib(L, gamelib);
  	return 1;
}

