#!/bin/bash
#===============================================================================
# This is a POST SCRIPT for condor job, which "clean" files after job is done.
# It is executed in the same directory as condor job.
# Example JOB1 1.condor DIR dagTmp =>
# => post script job is executed in dagTmp
#===============================================================================
## Libraries/Input
shopt -s nullglob #allows create an empty array
homePath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" #cur. script locat.
source "$homePath"/funcList.sh
curScrName=${0##*/}

task="${1,,}" #${a,,} = lower case
shift

UntarFiles(){
  # Usage: UntarFile "${files[@]}"
  local files=("$@")
  local file exFl
  
  for file in "${files[@]}"; do
    ChkExist f "$file" "File to untar: $file"
    tar -xzf "$file"
    exFl=$?
    if [[ "$exFl" -ne 0 ]]; then
        ErrMsg "$file cannot be unzip" "$exFl"
    else
      rm -rf "$file"
    fi
  done
}

## Main part - selection based on task
EchoLineBold
echo "[Start] $curScrName"
EchoLineSh
echo "Task is $task"
EchoLineSh

# Fill list with directories from inpPath
if [[ "$task" = filllistofdirs ]]; then
    file="${1}"
    inpPath="$2"
    ChkEmptyArgs "file" "inpPath"
    ls -d "$inpPath/"*/ > "$file"
    if [[ "$?" -ne 0 ]]; then
        ErrMsg "Something went wrong with filling the list $file.
               Error: $?" "$?"
    else
      exit 0
    fi
fi

# Untar files by providing files
if [[ "$task" = untarfiles ]]; then
    UntarFiles "$@"
    exit 0
fi

# Untar files from directory
if [[ "$task" = untarfilesfromdir ]]; then
    dirPath=$1
    ChkAvailToWrite "dirPath"
    files=("$dirPath"/*.tar.gz)
    UntarFiles "${files[@]}"
    exit 0
fi

ErrMsg "Unfamiliar task. Possible tasks are:
       FillListOfDirs - fill a list with all directories of inpPath
       UntarFiles - untar all files
       UNtarFilesFromDir - untar files in a specific directory"

echo "[End] $curScrName"
EchoLineBold
