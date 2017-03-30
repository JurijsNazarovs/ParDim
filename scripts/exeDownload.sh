#!/bin/sh
#========================================================
# This is an execution file to download data and
# move it in a right folder
#========================================================

## Input and default values
link=$1
path=${2:-"./"}
delim=${3:-","} #use to split path
delimJoin=${4:-";"} #use to split link


## Initial preparation
readarray -t path <<< "$(echo "$path" | tr "$delim" "\n")"
readarray -t link <<< "$(echo "$link" | tr "$delimJoin" "\n")"

dirTmp=$(mktemp -dq condorTmpXXXX) #create tmp folder
cd "$dirTmp"


## Dowloading file
wget ${link[@]}
exFl=$?
if [ "$exFl" -ne 0 ]; then
    echo "Downloading was not successful! Error code: $exFl"
    exit $exFl
fi


## Copy file in right folders
for filePath in "${path[@]}"; do
  mkdir -p "${filePath%/*}"
  
  if [[ ${#link[@]} -eq 1 ]]; then
      cp ${link##*/} "$filePath"
  else
    cat ${link[@]##*/} > "${filePath##*/}"
    exFl=$? #exit value of coping
    if [ "$exFl" -ne 0 ]; then
        echo "Joining files was not successful! Error code: $exFl"
        exit $exFl
    fi
    cp "${filePath##*/}" "$filePath"
  fi
  
  exFl=$? #exit value of coping
  if [ "$exFl" -ne 0 ]; then
      echo "Coping was not successful! Error code: $exFl"
      exit $exFl
  fi

  echo "Success! Check file: $filePath"
done

exit 0

