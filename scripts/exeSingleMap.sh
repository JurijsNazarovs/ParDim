#!/bin/bash
#===============================================================================
# This script executes "makeDag.script (for one directory)".
#
# Depending whether option condor is provided, the script have different ways
# to create an output, that is: 
#	- no condor => all files are created in $jobsDir
#	- condor => all files are created on server in $jobsDir,
#		    all files inside $jobsDir are tared together
#		    and move back, including stdOut and stdErr.
#
# Input:
# - taskScript	script to create dag
# - argsFile	file with all arguments for the dagMaker script
# - dagName	name of the output dag, which collects all dags from 
#		every folder using SPLICE
# - resPath     resutls are written here. Should be the full path
# - isCondor    false - no condor, true - condor
# - selectJobsListInfo file with all information about directories
#==============================================================================
## Libraries, input arguments
shopt -s nullglob #allows create an empty array
shopt -s extglob #to use !
homePath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" 
source "$homePath"/funcListParDim.sh #call file with functions

curScrName="${0##*/}"
EchoLine
echo "[Start] $curScrName"

taskScript="$1" #script to create dag (dagMaker)
argsFile="$2"
dagFile="$3:-tmp.dag}" #name of output dag, with independent jobs
resPath="$4" #resutls are written here. Should be the full path
isCondor="${5:-false}"
selectJobsListInfo="$6" #file with all information about directories


## Prepare working directories
jobsDir="${dagFile%.*}Tmp" #content of jobsDir is sent to submit machine
mkdir -p "$jobsDir"


## Execute script to create a dag file
# dagFile and curJobDir are provided since can be in different places 
EchoLineSh
echo "[Start]	$taskScript"
bash "$taskScript"\
     "$argsFile"\
     "$dagFile"\
     "$jobsDir"\
     "$resPath"\
     "$selectJobsListInfo"
exFl=$?

if [[ "$exFl" -ne 0 ]]; then
    dirTmp=$(mktemp -dq tmpXXXX)
    mv !("$dirTmp") "$dirTmp"
    mv "$dirTmp"/_condor_std* ./
    
    ErrMsg "The task $taskScript
           returns the eror: $exFl"
fi


## Collect output together
if [[ "$isCondor" = true ]]; then
    # Create tar.gz file of everything inside $jobsDir folder
    tarName="${dagFile%.*}.tar.gz" #based on ParDim SCRIPT POST
    tar -czf "$tarName" "$jobsDir"
    
    # Has to hide all unnecessary files in tmp directories 
    dirTmp=$(mktemp -dq tmpXXXX)
    mv !("$dirTmp") "$dirTmp"
    mv "$dirTmp"/_condor_std* "$dirTmp/$tarName" "$dirTmp/$dagFile" ./
fi

echo "[End]  $taskScript"
EchoLineSh
exit 0
