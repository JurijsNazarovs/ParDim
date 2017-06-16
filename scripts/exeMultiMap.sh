#!/bin/bash
#===============================================================================
# This script executes "makeDag.script (for one folder)" for selected or all
# jobs in inpPath and collect names of all constructed dags in one file
# (using SPLICE).
#
# Depending whether option condor is provided, the script have different ways
# to create an output, that is: 
#	- no condor => all files are created in $jobsDir
#	- condor => all files are created on server in $jobsDir,
#		    all files inside $jobsDir are tared together
#		    and move back, including stdOut and stdErr.
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
## Libraries, input arguments
shopt -s nullglob #allows create an empty array
shopt -s extglob #to use !
homePath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" 
source "$homePath"/funcList.sh #call file with functions

curScrName=${0##*/}
EchoLine
echo "[Start] $curScrName"

taskScript=${1} #[R] script to create dag (dagMaker)
argsFile=${2}  #[R] file w/ all arguments for this shell
dagFile=${3:-"tmp.dag"} #path to output splice, with dags for every directory
resPath=${4:-""} #resutls are written here. Should be the full path
isCondor=${5:-false}
selectJobsListInfo=${6-""} #file with all information about directories
selectJobsListPath=${7:-""} #path to list of dirs to execute


## Create main DAG file, which contains all DAG jobs for every "right" folder & error file
PrintfLine > "$dagFile"
printf "# [Start] Description of $dagFile\n" >> "$dagFile"
PrintfLine >> "$dagFile"

errFile="err.${dagFile%.*}" #file with all NOT proceeded folders
PrintfLine > "$errFile"
printf "# [Start] Description of $errFile\n" >> "$errFile"
printf "# File contains list of unsuccessful directories and error code\n"\
       >> "$errFile"
PrintfLine >> "$errFile"

numZeros=$(awk 'END{print NR}' "$selectJobsListPath")
numZeros=${#numZeros} #number of zeros in printf to have DAG0001,..., DAG0003

jobNum=0 #counter of executable jobs.
jobsDir="analysedDirectories"

while IFS='' read -r dirPath || [[ -n "$dirPath" ]]; do
  dirName="$(basename $dirPath)"
  curJobDir="$jobsDir/$dirName"
  mkdir -p "$curJobDir"
  dagFileInDir="$curJobDir/${dagFile%.*}_$dirName.${dagFile##*.}"
  fileWithContent="$curJobDir/fileWithContent_$dirName"

  # Define file with content of dirPath
  awk -F "\n"\
      -v curLine="^$dirPath.*:$"\
      -v nextLine="^/.*:$"\
      '{
        if ($0 ~ curLine) {f = 1}
        if ($0 ~ nextLine && $0 !~ curLine) {f = 0}
        if (f == 1 && NF) {print}
       }' "$selectJobsListInfo" > "$fileWithContent"

  # Execute script to create a dag file
  EchoLineSh
  echo "[Start]	$taskScript for $dirName"
  bash "$taskScript"\
       "$argsFile"\
       "$dagFileInDir"\
       "$curJobDir"\
       "$fileWithContent"\
       "$resPath"\
       "$dirName"\
       "${taskScript%.*}_$dirName"
  # "$dirName" - directory to save results and has to be tared with following:
  # "${taskScript%.*}_$dirName" - unique name for transfer output +.tar.gz
  exFl=$? #exit value of creating dag

  if [[ "$exFl" -ne 0 ]]; then
      printf " \t $dirName \t\t\t Error code: $exFl\n" >> "$errFile"
      rm -rf "$curJobDir"
  else
    ((jobNum++))
    printf "SPLICE DAG%0${numZeros}d $dagFileInDir\n" $jobNum >> "$dagFile"
  fi
  echo "[End]  $taskScript for $dirName"
  EchoLineSh
done < "$selectJobsListPath"

PrintfLine >> "$errFile"
printf "# [End]  Description of $errFile\n" >> "$errFile"
PrintfLine >> "$errFile"

PrintfLine >> "$dagFile"
printf "# [End]  Description of $dagFile\n" >> "$dagFile"
PrintfLine >> "$dagFile"


## End
if [[ $jobNum -eq 0 ]]; then
    dirTmp=$(mktemp -dq tmpXXXX)
    mv !("$dirTmp") "$dirTmp"
    mv "$dirTmp"/_condor_std* "$dirTmp/$errFile" ./
    ErrMsg "0 jobs are queued by $taskScript"
else
  ## Collect output together in case of condor
  if [[ "$isCondor" = true ]]; then
      # Create tar.gz file of everything inside $jobsDir folder
      tarName="${dagFile%.*}.tar.gz" #based on ParDim SCRIPT POST
      tar -czf "$tarName" "$jobsDir"

      # Has to hide all unnecessary files in tmp directories 
      dirTmp=$(mktemp -dq tmpXXXX)
      mv !("$dirTmp") "$dirTmp"
      mv "$dirTmp"/_condor_std* "$dirTmp/$tarName" "$dirTmp/$dagFile"\
         "$dirTmp/$errFile" ./
  fi

  echo "[End]  $curScrName"
  EchoLine

  exit 0
fi
