#!/bin/bash
#===============================================================================
# This script creates an argument file for ParDim framework
#
# Input:
#   - argsFile - output file with arguments
#   - isAppend - true => append  to existing argsFile, false => rewrite.
#                Default is false
#   - list all interesting stages using spaces.
#==============================================================================
## Libraries and options
shopt -s nullglob #allows create an empty array
homePath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" 
scriptsPath="$homePath/scripts"
source "$scriptsPath"/funcListParDim.sh

curScrName=${0##*/} #delete last backSlash

EchoLineBold
echo "[Start] $curScrName"
EchoLineSh
lenStr=${#curScrName}
lenStr=$((25 + lenStr))
printf "%-${lenStr}s %s\n"\
        "The location of $curScrName:"\
        "$homePath"
printf "%-${lenStr}s %s\n"\
        "The $curScrName is executed from:"\
        "$PWD"
EchoLineSh

## Input and default values
argsFile=${1:-"$(mktemp -qu args.ParDim.XXXX)"}
argsFile="$(readlink -m "$argsFile")"
shift
isAppend=${1:-"false"}
ChkValArg "isAppend" "" "true" "false"
shift
tasks=("$@")


## Creating the argsFile
if ! [[ -f "$argsFile" && "$isAppend" = true ]]; then
    echo "Creating $argsFile"
    printf "##[ ParDim.sh ]##\n" > "$argsFile"
    printf "dataPath\n" >>  "$argsFile"
    printf "resPath\n" >>  "$argsFile"
    printf "jobsDir\n" >>  "$argsFile"
    printf "selectJobsListPath\n" >>  "$argsFile"
    printf "\n" >> "$argsFile"
else
  echo "Updating $argsFile"
  printf "\n" >> "$argsFile"
fi
EchoLineSh


for task in "${tasks[@]}"; do
  maxLenStr=30
  printf "##[ $task ]##\n" >> "$argsFile"
  printf "%-${maxLenStr}s %s\n" "execute" "true" >> "$argsFile"
  if [[ "$task" != Download ]]; then
    printf "script\n" >> "$argsFile"
    printf "%-${maxLenStr}s %s\n" "map" "multi" >> "$argsFile"
  fi
  
  printf "args\n" >> "$argsFile"
  printf "transFiles\n" >> "$argsFile"
  if [[ "$task" != Download ]]; then
      printf "relResPath\n"  >> "$argsFile"
  fi
  printf "\n" >> "$argsFile"
done

## End
echo "[End]  $curScrName"
EchoLineBold
