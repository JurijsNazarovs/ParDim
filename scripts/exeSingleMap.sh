#!/bin/bash
#===============================================================================
# This script executes "makeDag.script" to create dag based on some input,
# without running that for every directory as in exeMultiMap.shXS
#
# Input:
#	- dagScript	script to create dag
#	- argsFile	file with all arguments for the dagMaker script
#	- argsLabsDelim delim to split line with labels for argsFile
#	- argsLab       labels to read arguments in argsFile
#	- dagName	name of the output dag, which collects all dags from 
#			every folder using SPLICE. No path, just a name	
#	- scriptsPath	path with all scripts for pipeline, in case of Condor
#	- jobsDir	temporary directory for all created files with jobs
#	- selectJobsTabPath path to table with dirs to execute
#	- isCondor	false - no condor, true - condor. Default is true
#==============================================================================
ls
pwd
## Libraries, input arguments
shopt -s nullglob #allows create an empty array
shopt -s extglob #to use !
homePath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" 
source "$homePath"/funcList.sh #call file with functions

curScrName=${0##*/}
EchoLine
echo "[Start] $curScrName"

taskScript=${1} #script to create dag (dagMaker)
argsFile=${2}
dagFile=${3:-"tmp.dag"} #path to output dag, with independent jobs
resPath=${4:-""} #resutls are written here. Should be the full path
isCondor=${5:-false}

## Prepare working directories
jobsDir="${dagFile%.*}Tmp"
mkdir -p "$jobsDir"

## Execute script to create a dag file
# dagFile and curJobDir are provided since can be in different places 
EchoLineSh
echo "[Start]	$taskScript"
bash "$taskScript"\
     "$argsFile"\
     "$dagFile"\
     "$jobsDir"\
     "$resPath"
exFl=$?

if [[ "$exFl" -ne 0 ]]; then
    rm -rf "$curJobDir"
    ErrMsg "The task $taskScript
           returns the eror: $exFl"
fi


## Collect output together
if [[ "$isCondor" = true ]]; then
    # Create tar.gz file of everything inside $jobsDir folder
    tarName="${dagFile%.*}.tar.gz" #based on ParDim SCRIPT POST
    tar -czf "$tarName" "$jobsDir"
    ls
    # Has to hide all unnecessary files in tmp directories 
    dirTmp=$(mktemp -dq tmpXXXX)
    mv !("$dirTmp") "$dirTmp"
    mv "$dirTmp"/_condor_std* "$dirTmp/$tarName" "$dirTmp/$dagFile" ./
fi

## End
echo "[End]  $taskScript"
EchoLineSh
exit 0
