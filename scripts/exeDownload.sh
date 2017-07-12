#!/bin/bash
#========================================================
# This is an execution file to download data and
# move it in a right folder
#========================================================
## Libraries, input arguments
shopt -s nullglob #allows create an empty array
shopt -s extglob #to use !

## Input and default values
link=${1}
path=${2:-./}
delim=${3:-,} #use to split path
delimJoin=${4:-;} #use to split link
outTar=${5} #tarFile to return back on submit machine
isDry=${6:-true}


## Initial preparation
readarray -t path <<< "$(echo "$path" | tr "$delim" "\n")"
readarray -t link <<< "$(echo "$link" | tr "$delimJoin" "\n")"

dirTmp=$(mktemp -dq tmpXXXX) #create tmp folder to tar everything inside later


## Dowloading file
wget "${link[@]}"
exFl=$?
if [ "$exFl" -ne 0 ]; then
    echo "Downloading was not successful! Error code: $exFl"
    exit $exFl
fi


## Copy file in a right directory
for filePath in "${path[@]}"; do
  curDir="${filePath%/*}"
  mkdir -p "$curDir" #directory for downlaoded file
  
  if [[ ${#link[@]} -eq 1 ]]; then
      cp ${link##*/} "$filePath"
  else
    cat "${link[@]##*/}" > "${filePath##*/}" #join several files in one
    exFl=$? #exit value of coping
    if [[ "$exFl" -ne 0 ]]; then
        echo "Joining files was not successful! Error code: $exFl"
        exit $exFl
    fi
    cp "${filePath##*/}" "$filePath"
  fi
  
  exFl=$? #exit value of coping
  if [[ "$exFl" -ne 0 ]]; then
      echo "Coping was not successful! Error code: $exFl"
      exit $exFl
  else
    echo "Success! Check file: $filePath"
    rm -rf "${link[@]}"
    mv "$curDir" "$dirTmp"
  fi
done

## Prepare tar to move results back
tar -czf "$outTar" -C "$dirTmp" .

# Has to hide all unnecessary files in tmp directories 
if [[ "$isDry" = false ]]; then
    mv !("$dirTmp") "$dirTmp"
    mv "$dirTmp"/_condor_std* ./
    mv "$dirTmp/$outTar" ./
fi

exit 0

