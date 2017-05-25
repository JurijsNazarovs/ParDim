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
homePath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" 
source "$homePath"/funcList.sh #call file with functions

curScrName=${0##*/}
echoLine
echo "[Start] $curScrName"

taskScript=${1} #script to create dag (dagMaker)
argsFile=${2}
dagName=${3:-"tmp.dag"} #name of the output dag, which collects all dags
jobsDir=${4:-"dagTmp"}  #temporary directory for all created files with jobs


## Prepare dagFile and a directorie for the $taskScript
jobsDir="$jobsDir/singleMap/${dagName%.*}"
mkdir -p "$jobDir"
dagFileInDir="$jobsDir/$dagName" 


## Execute script to create a dag file
EchoLineSh
echo "[Start]	$taskScript"
bash "$taskScript"\
     "$argsFile"\
     "$dagFileInDir"
exFl=$? #exit value of creating dag

if [ "$exFl" -ne 0 ]; then
    ErrMsg "The task $taskScript
           returns the eror: $exFl"
    rm -rf "$curJobDir"
fi
echo "[End]  $taskScript"
EchoLineSh
