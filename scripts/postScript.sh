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
curScrName=${0##*/}

logFile=${1:-outAndErr.postScript}.err
exec > "$logFile" 2>&1 #redirect both stdOut and stdErr to a file Globally
#exec 2> "$logFile" #redirect stdErr to a file Globally

shift

task=${1,,} #${a,,} = lower case
shift

UntarFiles(){
  # Usage: UntarFile "${files[@]}"
  local files=("$@")
  local file exFl
  local outPath
  
  for file in "${files[@]}"; do
    ChkExist f "$file" "File to untar: $file"
    outPath="$(dirname "$file")"
    tar --no-overwrite-dir -xzf "$file" -C "$outPath" #try unzip first
    if [[ $? -ne 0 ]]; then
        echo "Cannot unzip $file. Trying to untar"
        tar --no-overwrite-dir -xf "$file" -C "$outPath" #try just untar
        if [[ "$exFl" -ne 0 ]]; then
            ErrMsg "$file cannot be untar with zip and not zip options" "$exFl"
        fi
    fi
    rm -rf "$file"
  done
}

UntarFilesFromDir(){
  # Usage: UntarFilesFromDir "$dirPath"
  local dirPath=$1
  ChkAvailToWrite "dirPath"
  local files=("$dirPath"/*{.tar.gz,.tar})
  if [[ "${#files[@]}" -eq 0 ]]; then
      ErrMsg "No .tar or .tar.gz files in $dirPath"
  fi
  UntarFiles "${files[@]}"
}

FillListOfDirs(){
  local inpPath=$1
  local outfile=$2
  ChkEmptyArgs "outfile" "inpPath"
  #ls -d "$inpPath/"*/ > "$outfile"
  find "$inpPath/" -mindepth 1 -maxdepth 1 -type d\
       '!' -exec test -e "{}/RemoveDirFromList" ';' -print\
       > "$outfile" #do not consider dirs with RemoveDirFromList file
  if [[ "$?" -ne 0 ]]; then
      ErrMsg "Something went wrong with filling the list $outfile.
               Error: $?" "$?"
  fi
}

FillListOfContent(){
  local inpFile=$1
  local outFile=$2
  ChkEmptyArgs "inpFile" "outFile"
  
  if [[ ! -s "$inpFile" ]] ; then
      ErrMsg "The file with list of directories is empty"
  fi

  printf ""  > "$outFile"
  
  while IFS='' read -r dirPath || [[ -n "$dirPath" ]]; do
    if [[ "$dirPath" = "." ]]; then
        continue
    fi

    ChkExist d "$dirPath" "Directory"
    ls -lR "$dirPath" |
        awk\
            -v dirPath="$dirPath/"\
            '{
        if ($0 ~ "total.*") {next}
        # In case of soft link
        if (NF == 11) {"ls -l " dirPath$11 " | cut -d \" \" -f 5"| getline size;
                       print($11 "\t" size "\t" "s" "\t" $9); next}
        if (NF == 9) {print $9 "\t" $5; next}
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

  # Fill list of dirs and create file with content
  filllistofdirsandcontentwithreport)
    # $1 - task for report
    # $2 - working directory with log file
    # $3 - root dir where results saved. Used to cat with dirnames of comp. dirs
    # $4 - output file with directories
    # $5 - output file with info about directories
    dirTmp="$(mktemp -qud "ReportDirTmp.XXX")"
    bash "$homePath/../MakeReport.sh"  "$1" "$2" "$dirTmp"
    if [[ $? -ne 0 ]]; then
        ErrMsg "MakeReport function failed. No output is produced."
    fi

    ChkExist "f" "$dirTmp/$1.compDirs.list" "List of completed directories"
    # Change dirname of completed directories to temporary result directory
    awk -v dirPath="$3" '{
        n = split($0, splStr, "/")
        print (dirPath "/" splStr[n])
    }' "$dirTmp/$1.compDirs.list" > "$4"
    
    rm -rf "$dirTmp"
    
    FillListOfContent "$4" "$5" #1: inpFile, #2: outFile
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
