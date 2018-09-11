#!/bin/bash
gameCode=$(cat gameCode.txt)

gameServerPort=$((15020 + $(($(($gameCode % 100)) * 100))))
hallServerPort=$((15010 + $(($(($gameCode % 100)) * 100))))
echo "clearcache" | nc 127.0.0.1 $gameServerPort
echo "call 0000000a 'onServerHotUpdate'" | nc 127.0.0.1 $hallServerPort
