#!/bin/bash
gameCode=$(cat gameCode.txt)

pids=$(ps aux | grep "allocServer/config.lua $gameCode" | grep -v grep | awk '{print $2}')
if [ ${#pids} -gt 0 ]; then
   kill $pids
fi
pids=$(ps aux | grep "gameServer/config.lua $gameCode" | grep -v grep | awk '{print $2}')
if [ ${#pids} -gt 0 ]; then
   kill $pids
fi
pids=$(ps aux | grep "loginServer/config.lua $gameCode" | grep -v grep | awk '{print $2}')
if [ ${#pids} -gt 0 ]; then
   kill $pids
fi
pids=$(ps aux | grep "hallServer/config.lua $gameCode" | grep -v grep | awk '{print $2}')
if [ ${#pids} -gt 0 ]; then
   kill $pids
fi
pids=$(ps aux | grep "gateServer/config.lua $gameCode" | grep -v grep | awk '{print $2}')
if [ ${#pids} -gt 0 ]; then
   kill $pids
fi
sleep 1
