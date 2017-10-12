#!/bin/bash
#========================================================
# This is an execution file to download data and
# move it in a right folder
#========================================================
## Libraries, input arguments
shopt -s nullglob #allows create an empty array
shopt -s extglob #to use !

CleanOutput() {
  local dirTmp="$1"
  local outTar="$2"
  
  mv !("$dirTmp") "$dirTmp"
  mv "$dirTmp"/_condor_std* ./
  mv "$dirTmp/$outTar" ./
}


## Input and default values
link=${1}
path=${2:-./}
delim=${3:-,} #use to split path
delimJoin=${4:-;} #use to split link
outTar=${5} #tarFile to return back on submit machine
isDry=${6:-false}


## Initial preparation
readarray -t path <<< "$(echo "$path" | tr "$delim" "\n")"
readarray -t link <<< "$(echo "$link" | tr "$delimJoin" "\n")"

dirTmp=$(mktemp -dq tmpXXXX) #create tmp folder to tar everything inside later


## Downloading file
wget "${link[@]}"
exFl=$?
if [ "$exFl" -ne 0 ]; then
    echo "Downloading was not successful! Error code: $exFl"
    exit $exFl
fi


## Create single or joined temporary file
fileTmp=$(mktemp -uq downloadedFileTmpXXXX) #create tmp file to join other files
if [[ ${#link[@]} -eq 1 ]]; then
    mv ${link##*/} "$fileTmp"
else
  cat "${link[@]##*/}" > "$fileTmp" #join several files in one
  exFl=$? #exit value of coping
  if [[ "$exFl" -ne 0 ]]; then
      echo "Joining files was not successful! Error code: $exFl"
      CleanOutput "$dirTmp" "$outTar"
      exit $exFl
  fi
  rm -rf "${link[@]##*/}"
fi
 

## Copy file in a right directory
for filePath in "${path[@]}"; do
  curDir="${filePath%/*}"
  mkdir -p "$curDir" #directory for downloaded file
  cp "$fileTmp" "$filePath"
  
  exFl=$? #exit value of coping
  if [[ "$exFl" -ne 0 ]]; then
      echo "Coping was not successful! Error code: $exFl"
      CleanOutput "$dirTmp" "$outTar"
      exit $exFl
  else
    echo "Success! Check file: $filePath"
    mv "$curDir" "$dirTmp"
  fi
done


## Prepare tar to move results back
env GZIP=-9 tar -czf "$outTar" -C "$dirTmp" . #to compress with max level
exFl=$?
if [[ "$exFl" -ne 0 ]]; then
    echo "Creating tar was not successful! Error code: $exFl"
    CleanOutput "$dirTmp" "$outTar"
    exit $exFl
fi

if [[ "$isDry" = false ]]; then
    echo "Final step: moving files in $outTar"
    CleanOutput "$dirTmp" "$outTar"
fi

exit 0

