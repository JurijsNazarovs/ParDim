#!/bin/bash
#========================================================
# This is a general execution file for condor,
# which executes specific part of the AQUAS pipeline
#========================================================
## Libraries and options
shopt -s extglob #to use !
source "funcList.sh" #need to transfer

curScrName=${0##*/} #delete last backSlash
EchoLineBold
echo "[Start] $curScrName"

## Input and default values
script=$1
argsFile=$2 #file w/ arguments for the bds
resDir=${3:-"resDir"}
outTar=${4:-"aquas.tar.gz"} #tarFile to return back to submit machine
softTar=${5:-"pipeInstallFiles.new.tar.gz"}
isDry=${6:-true}


## Installation
#untar and turn off the warning about time
tar -xzf "$softTar" --warning=no-timestamp 
rm "$softTar"

echo "BASH: $BASH_VERSION"
echo "ZSH: $ZSH_VERSION"
ls

source ./pipePath.source
bash ./pipeInstall.sh
if [[ $? -ne 0  ]]; then
    ErrMsg "Software was not installed successfully"
fi



## Read parameters from the file
i=0
while read  firstCol restCol #do like that because there might be spaces in names
do
	varsList[$i]="$firstCol" #all variables from the file
	valsList[$i]="$restCol" #all values of variables from the file
	((i++))
done < "$argsFile"

# Check consistency of # of vars and vals
argsNum=${#varsList[@]}
if [[ "$argsNum" -ne "${#valsList[@]}" ]]; then #fix later to put in the file and break dag
	ErrMsg "Wrong input! Number of vars and vals is not consistent."
fi


## Prepare the argument string for bds submission
argsStr=()
for ((i=0; i<$argsNum; i++)); do
	argsStr[$i]="${varsList[$i]} ${valsList[$i]}"
done


## Task(script) execution
mkdir -p "$resDir"
if [[ $? -ne 0 ]]; then
    ErrMsg "Cannot create a $resDir"
fi

# Necessary to do eval, since argsStr contains -OPTION as options
eval "bds -c .bds/bds.config pipeScripts/\"$script\" ${argsStr[*]}"
bdsFl=$?

if [[ $bdsFl -ne 0 ]]; then
    echo "bds was not successful! Error code: $bdsFl"
else
  cd out
  mv !(report) ../"$resDir"
  cd ../
  tar -czf "$outTar" "$resDir"
  if [[ $? -ne 0 ]]; then
      ErrMsg "Cannot create a $outTar"
  fi
fi

# Has to hide all unnecessary files in tmp directories
if [[ "$isDry" = false ]]; then
    mv !("$resDir") "$resDir"
    mv "$resDir"/_condor_std* ./
    if [[ $bdsFl -eq 0 ]]; then
        mv "$resDir/$outTar" ./
    fi
fi

echo "[End]  $curScrName"
EchoLineBold
exit $bdsFl
