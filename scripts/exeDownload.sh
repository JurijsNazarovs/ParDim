#!/bin/bash
#========================================================
# This is an execution file to download data and
# move it in a right folder
#========================================================
## Libraries, input arguments
shopt -s nullglob #allows create an empty array
shopt -s extglob #to use !
DOWNL_ERR_FL=0 # Global variable for downloading error
CreateErrFile() {
  local curDir="$1"
  mkdir -p "$curDir"
  touch "$curDir/RemoveDirFromList"
  #DOWNL_ERR_FL=1 #not successful downloading
}


## Input and default values
link=${1}
path=${2:-./}
delim=${3:-,} #use to split path
delimJoin=${4:-;} #use to split link
outTar=${5} #tarFile to return back on submit machine
isCreateLinks=${6:-true} #create links or not
isZipRes=${7:-true} #zip results
isDry=${8:-true}


## Initial preparation
readarray -t path <<< "$(echo "$path" | tr "$delim" "\n")"
readarray -t link <<< "$(echo "$link" | tr "$delimJoin" "\n")"

dirTmp=$(mktemp -dq tmpXXXX) #create tmp folder to tar everything inside later


## Downloading file
downlCounter=1
# Repeat Downloading at most 5 times in case of network issues
while [[ $downlCounter -le 5 ]]; do
  wget "${link[@]}"
  DOWNL_ERR_FL=$?
  if [[ "$DOWNL_ERR_FL" -eq 8 ]]; then
      echo "Downloading was not successful! Error code: $DOWNL_ERR_FL"
      echo "Attempt: $downlCounter/5"
      ((downlCounter++))
      sleep 10
  else
    downlCounter=100
  fi
done


if [[ "$DOWNL_ERR_FL" -ne 0 ]]; then
    echo "Downloading was not successful! Error code: $DOWNL_ERR_FL"
    for i in "${!path[@]}"; do
      filePath="$dirTmp/${path[$i]}"
      curDir="${filePath%/*}"
      CreateErrFile "$curDir"
    done
else
  ## Create single or joined temporary file
  fileTmp=$(mktemp -uq downloadedFileTmpXXXX) #create tmp file to join other files
  if [[ ${#link[@]} -eq 1 ]]; then
      mv ${link##*/} "$fileTmp"
  else
    cat "${link[@]##*/}" > "$fileTmp" #join several files in one
    exFl=$? #exit value of joining
    if [[ "$exFl" -ne 0 ]]; then
        echo "Joining files was not successful! Error code: $exFl"
        for i in "${!path[@]}"; do
          filePath="$dirTmp/${path[$i]}"
          curDir="${filePath%/*}"
          CreateErrFile "$curDir"
        done
    fi
    rm -rf "${link[@]##*/}"
  fi
  

  ## Copy file in a right directory
  for i in "${!path[@]}"; do
    filePath="$dirTmp/${path[$i]}"
    curDir="${filePath%/*}"
    mkdir -p "$curDir" #directory for downloaded file
    if [[ $i -eq 0 ]]; then
        mv "$fileTmp" "$filePath"
        exFl=$? #exit value of coping
        origFile="$filePath"
    else
      if [[ "$isCreateLinks" = true ]]; then
          numDots=$(($(grep -o "/" <<< "$curDir" | wc -l)))
          ln -s `printf "%0.s../" $(seq 1 $numDots)`"${origFile#*/}" "$filePath"
          #without dirTmp, since I tar inside of dirTmp
      else
        cp "$origFile" "$filePath"
      fi
      exFl=$? #exit value of coping
    fi

    if [[ "$exFl" -ne 0 ]]; then
        echo "Coping was not successful! Error code: $exFl"
        CreateErrFile "$curDir"
    else
      echo "Success! Check file: $filePath"
    fi
  done
fi


## Prepare tar to move results back
if [[ "$isZipRes" = true ]]; then
    env GZIP=-9 tar -czf "$outTar" -C "$dirTmp" . #to compress with max level
else
  tar -cf "$outTar" -C "$dirTmp" .
fi

exFl=$?
if [[ "$exFl" -ne 0 ]]; then
    echo "Creating tar was not successful! Error code: $exFl"
fi

if [[ "$isDry" = false ]]; then
    echo "Final step: moving files in $outTar"
    mv !("$dirTmp") "$dirTmp"
    mv "$dirTmp"/_condor_std* ./
    if [[ "$exFl" -eq 0 ]]; then
        mv "$dirTmp/$outTar" ./
    fi
fi

if [[ "$DOWNL_ERR_FL" -ne 0 ]]; then
    exit "$DOWNL_ERR_FL"
fi

exit "$exFl"

