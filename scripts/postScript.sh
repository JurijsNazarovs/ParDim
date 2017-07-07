#!/bin/bash
#===============================================================================
# This is a POST SCRIPT for condor job, which "prepare" files after job is done.
# It is executed in the same directory as condor job.
# Example JOB1 1.condor DIR dagTmp =>
# => post script job is executed in dagTmp
#===============================================================================
## Libraries/Input
shopt -s nullglob #allows create an empty array
homePath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" #cur. script locat.
source "$homePath"/funcListParDim.sh
curScrName="${0##*/}"

logFile="${1:-outAndErr.postScript}.err"
exec > "$logFile" 2>&1 #redirect both stdOut and stdErr to a file Globally
#exec 2> "$logFile" #redirect stdErr to a file Globally

shift

task="${1,,}" #${a,,} = lower case
shift

UntarFiles(){
  # Usage: UntarFile "${files[@]}"
  local files=("$@")
  local file exFl
  local outPath
  
  for file in "${files[@]}"; do
    ChkExist f "$file" "File to untar: $file"
    outPath="$(dirname "$file")"
    
    tar -xzf "$file" -C "$outPath"
    exFl=$?
    if [[ "$exFl" -ne 0 ]]; then
        ErrMsg "$file cannot be unzip" "$exFl"
    else
      rm -rf "$file"
    fi
  done
}

UntarFilesFromDir(){
  # Usage: UntarFilesFromDir "$dirPath"
  local dirPath=$1
  ChkAvailToWrite "dirPath"
  local files=("$dirPath"/*.tar.gz)
  if [[ "${#files[@]}" -eq 0 ]]; then
      ErrMsg "No .tar.gz files in $dirPath"
  fi
  UntarFiles "${files[@]}"
}

FillListOfDirs(){
  local inpPath="$1"
  local outfile="$2"
  ChkEmptyArgs "outfile" "inpPath"
  #ls -d "$inpPath/"*/ > "$outfile"
  find "$inpPath/" -mindepth 1 -maxdepth 1 -type d > "$outfile"
  if [[ "$?" -ne 0 ]]; then
      ErrMsg "Something went wrong with filling the list $outfile.
               Error: $?" "$?"
  fi
}

FillListOfContent(){
  local inpFile="$1"
  local outFile="$2"
  ChkEmptyArgs "inpFile" "outFile"
  
  if [[ ! -s "$inpFile" ]] ; then
      ErrMsg "The file with directories is empty"
  fi

  printf ""  > "$outFile"
  
  while IFS='' read -r dirPath || [[ -n "$dirPath" ]]; do
    if [[ "$dirPath" = "." ]]; then
        continue
    fi

    ChkExist d "$dirPath" "Directory"
    ls -lR "$dirPath" |
        awk\
    '{
        if ($0 ~ "total.*") {next}
        if (NF > 2) {print $9 "\t" $5}
        if (NF == 1) {print}
     }' >> "$outFile"
  done < "$inpFile"

  if [[ ! -s "$outFile" ]] ; then
      ErrMsg "The file with content is empty"
  fi
}

## Main part - selection based on task
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
echo "Task is $task"
EchoLineSh


case "$task" in
  # Fill list with directories from inpPath
  filllistofdirs)
    FillListOfDirs "$1" "$2" #1: inpDir, #2: outFile
    ;;
  
  # Fill list with all content of directories from file
  filllistofcontent)
    FillListOfContent "$1" "$2" #1: inpFile, #2: outFile
    ;;
  
  # Fill list of dirs and create file with content
  filllistofdirsandcontent)
    FillListOfDirs "$1" "$2" #1: inpDir, #2: outFile
    FillListOfContent "$2" "$3" #1: inpFile, #2: outFile
    ;;
  
  # Untar files by providing files
  untarfiles)
    UntarFiles "$@" #all files to untar
    ;;

  # Untar files from a directory
  untarfilesfromdir)
    UntarFilesFromDir "$1" #directory
    ;;

  # No options
  *)
    ErrMsg "Unfamiliar task. Possible tasks are:
           FillListOfDirs - fill a list with all directories of inpPath
           FillListOfContent - fill a list with all content based on dirs
           FillListOfDirsAndContent - 1) fill list 2) fill content
           UntarFiles - untar all files
           UntarFilesFromDir - untar files in a specific directory"
esac

rm -rf "$logFile" #if we are here, then no errors happen
echo "[End] $curScrName"
EchoLineBold
