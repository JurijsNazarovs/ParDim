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
echoLine
echo "[Start] $curScrName"

dagScript=${1} #[R] script to create dag (dagMaker)
argsFile=${2}  #[R] file w/ all arguments for this shell
argsLabsDelim=${3:-""} #delim to split line with labels for argslist
argsLabs=${4:-""}
readarray -t argsLabs <<< "$(echo "$argsLabs" | tr "$argsLabsDelim" "\n")"
dagName=${5:-"tmp.dag"} #name of the output dag, which collects all dags
                        #from every folder using SPLICE
scriptsPath=${6:-"$homePath"} #path is provided just when we use condor.
                              #Otherwise accept homePath
jobsDir=${7:-"dagTmp"}  #temporary directory for all created files with jobs
selectJobsTabPath=${8:-""} #path to table with dirs to execute
isCondor=${9:-"true"} 	#if not provided then consider as condor.

# The rule is that if this script is used with condor, then jobsDir is not provided,
# but the condor job is executed from the $jobsDir. That is, JOB some.condor DIR $jobsDir
mkdir -p "$jobsDir" #to be safe
dagFile="$jobsDir/$dagName" #path to dagFile: working directory + the name of the dag
errFile="$jobsDir/err.${dagScript##*/}" #file with all NOT proceeded folders
errFile="${errFile%.*}"

# If we run from condor, then we run our script from a home directory, thus,
# we need to change the path to dagScript
if [[ "$isCondor" = true ]]; then
    dagScript="${dagScript##*/}"
fi


## Check if any required arguments are empty
posArgs=("dagScript" "argsFile" "$selectJobsTabPath")
chkEmptyArgs "${posArgs[@]}"


## Create main DAG file, which contains all DAG jobs for every "right" folder & error file
printfLine > "$dagFile"
printf "# [Start] Description of $dagFile\n" >> "$dagFile"
printfLine >> "$dagFile"

printfLine > "$errFile"
printf "# [Start] Description of $errFile\n" >> "$errFile"
printf "# File contains list of unsuccessful folders and error code\n" >> "$errFile"
printfLine >> "$errFile"
printf " Data input path: $inpPath\n\n" >> "$errFile"

jobNum=0 #counter of executable jobs.
# We need variable numZeros to have an estimation about number of folders,
# so that we can print out seq of DAG$i, using necessary amount of zeros infront,
# so that we can sort condor output in a right order: 0001, 0002, 0003, 0004, and etc
numZeros=$(awk 'END{print NR}' "$selectJobsTabPath")
echo "Number of possible folders: $numZeros"

numZeros=${#numZeros} #number of zeros in printf
echo "Number of positions(digits) in DAG name: $numZeros"
while IFS='' read -r dirPath || [[ -n "$dirPath" ]]; do	
  # Get directory name  
  dirName=${dirPath##*/} #delete all before last backSlash
  
  # Create directory for the current dag file corresponding to dirName
  curJobDir="$jobsDir/analysedDirectories/$dirName"
  mkdir -p "$curJobDir"

  # Create name of a dag inside the directory according to dagName
  dagFileInDir="$curJobDir/${dagName%.*}_$dirName.${dagName##*.}" 

  # Execute script to create a dag file
  echoLineSh
  echo "[Start]	$dagScript"
  bash "$dagScript"\
       "$argsFile"\
       "$dirPath"\
       "$dagFileInDir"\
       "$scriptsPath"\
       "${#argsLabs[@]}"\
       "${argsLabs[@]}"
  exFl=$? #exit value of creating dag

  if [ "$exFl" -ne 0 ]; then
      printf " \t $dirName \t\t\t Error code: $exFl\n" >> "$errFile"
      rm -rf "$curJobDir"
  else
    ((jobNum++)) #increase the number of succsessful jobs
    printf "SPLICE DAG%0${numZeros}d $dagFileInDir\n" $jobNum >> "$dagFile"
  fi
  echo "[End]  $dagScript"
  echoLineSh
done < "$selectJobsTabPath"

printfLine >> "$errFile"
printf "# [End]  Description of $errFile\n" >> "$errFile"
printfLine >> "$errFile"

printfLine >> "$dagFile"
printf "# [End]  Description of $dagFile\n" >> "$dagFile"
printfLine >> "$dagFile"

## Collect output together in case of condor
if [[ "$isCondor" = true  ]]; then
    
    # Create tar.gz file of everything inside $jobsDir folder
    tarName="${dagName%.*}.tar.gz" #delete extension
    cd "$jobsDir"
    tar -czf "$tarName" *
    cd -

    mv !($jobsDir) $jobsDir
    mv "$jobsDir"/_condor_std* ./ #move output and err files back,
    #otherwise condor will not transfer them
    mv "$jobsDir/$tarName" ./ #otherwise tar will not be transfered
fi

## End
echo "[End]  $curScrName"
echoLine

if [ $jobNum -eq 0 ]; then
    errMsg "Error! 0 jobs are queued by $dagScript"
fi

exit 0
