#!/bin/bash
gameCode=$(cat gameCode.txt)

if [ -z "$1" ]; then
   echo "没有第一个参数"
   exit 1
fi
if [[ $1 == *[!0-9]* ]]; then
   echo "$1 not a number"
   exit 1
fi
if [[ $2 == *[!0-9]* ]]; then
   echo "$2 not a number"
   exit 1
fi
pids=$(ps aux | grep "loginServer/config.lua $gameCode" | grep -v grep | awk '{print $2}')
if [ ${#pids} -gt 0 ]; then
   #echo $pids
   #echo ${#pids}
   kill $pids
fi

sleep 2
./skynet loginServer/config.lua $gameCode $1
