#!/bin/bash

gameCode=$(cat gameCode.txt)

svn up
svn up commonService/config/$gameCode
svn up gameServer/logic/game

chmod -R 775 .