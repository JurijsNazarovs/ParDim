#!/bin/sh
#========================================================
# This is a general execution file for condor,
# which executes specific part of the AQUAS pipeline
#========================================================
## Prior parameters
argsFile=$1 #file with arguments for the job
specName=$2 #hg19 and etc
specList=$3 #list of all species
specTar=$4  #tar file with all species files

echo "$argsFile"
echo "$specName" #hg19 and etc
echo "$specList" #list of all species
echo "$specTar"  #tar file with all species files

argsFile=${argsFile##*/} #take just the part with the name

## == TESTING PART. NEED TO BE DELETED LATER == ##
#argsFile=xcor1.args 
#specName="hg19"
#specList=species.list
#specTar=species.tar.gz
## == TESTING PART. NEED TO BE DELETED LATER == ##

## Function description
getInd(){ 
# Function return the index of $1, if element of array $2 equals exactly or contain $1
# To search for containing, $1 should be provided with *, for example: peak*
	local sym=$1
	shift
	local array=("$@")
	for i in "${!array[@]}"
	do
		if [[ "${array[$i]}" == $sym ]]; then
		       	printf "$i\n"
	   	fi
	done
}

delInd(){
# Function returns an array $2 without the $1 index (just one, not many)
	local ind=$1 #index to delete
	shift
	local array=("$@")

	for ((i=0; i<${#array[@]}; i++))
	do
		if [ "$i" -ne "$ind" ]; then
			printf -- "${array[$i]}\n"
		fi
	done
}

## Installation
tar -xzf pipeInstallFiles.tar.gz --warning=no-timestamp #untar and turn off the warning about time
rm pipeInstallFiles.tar.gz

echo "BASH: $BASH_VERSION"
echo "ZSH: $ZSH_VERSION"

source ./pipePath.source
bash ./pipeInstall.sh

tar -xzf "$specTar"
rm -rf "$specTar"

## Read parameters from the file
i=0
while read  firstCol restCol #do like that because there might be spaces in names
do
	varsList[$i]="$firstCol" #all variables from the file
	valsList[$i]="$restCol" #all values of variables from the file
	((i++))
done < $argsFile

## Find, save and delete script from the input
readarray -t scrInd <<< "$(getInd "script" "${varsList[@]}")"
scrInd=(${scrInd[0]}) #take just the first value
scr=${valsList[$scrInd]} #get the script value from the file

readarray -t varsList <<< "$(delInd "$scrInd" "${varsList[@]}")"
readarray -t valsList <<< "$(delInd "$scrInd" "${valsList[@]}")"

## Find, save and delete outDir from the input
readarray -t outDirInd <<< "$(getInd "-out_dir" "${varsList[@]}")"
outDirInd=(${outDirInd[0]}) #take just the first value
outDir=${valsList[$outDirInd]} #get the outDir value from the file

readarray -t varsList <<< "$(delInd "$outDirInd" "${varsList[@]}")"
readarray -t valsList <<< "$(delInd "$outDirInd" "${valsList[@]}")"

## Check consistency of # of vars and vals
argsNum=${#varsList[@]}
if [[ "$argsNum" -ne "${#valsList[@]}" ]]; then #fix later to put in the file and break dag
	echo "Wrong input! Number of vars and vals is not consistent."
	exit 1
fi

## Copy all possible inputs from inpPath to a working environment
dataDir="data"
mkdir -p "$dataDir"

posInps=("-bam" "-tag*" "-ctl_tag" "-xcor_qc*" "-peak*") # *means any symbol
for i in ${posInps[@]}
do
	readarray -t ind <<< "$(getInd "$i" "${varsList[@]}")"

	if [ "$ind" ]; then #if index is not empty
		for ((j=0; j<${#ind[@]}; j++)); do #go throw all indecies
			indTmp=(${ind[$j]})
			cp "${valsList[$indTmp]}" $dataDir #copy file
			fileName=${valsList[$indTmp]##*/} #get the name after the last slash
			valsList[$indTmp]="$dataDir/$fileName"			
		done
	fi
done

## Prepare the argument string for bds submission
argsStr=()
for ((i=0; i<$argsNum; i++))
do
	argsStr[$i]="${varsList[$i]} ${valsList[$i]}"
done

## Create tmp folder
# Move everything in one folder to avoid coping stuff back to the machine
# I am afraid to use "rm -rf *" because if I test it on my machine, it can end bad((
mkdir -p tmp
shopt -s extglob

## Execute bds
eval "bds -c .bds/bds.config pipeScripts/$scr ${argsStr[*]} -species $specName -species_file $specList"
exFl=$? #exit value of bds

if [ "$exFl" -ne 0 ]; then
	echo "bds was not successful! Error code: $exFl"
	mv !(tmp) tmp 
	#do not move output and err files back, because they will jsut show a segmentation fault
	mv tmp/_condor_std* ./ #move output and err files back, otherwise condor will not transfer them
	exit $exFl
fi

## Move everything from the out folder to -outDir
echo "Start transfer results"

if [[ ! -d "$outDir" ]]; then
    mkdir -p "$outDir"
    echo "$outDir is created"
fi

cp -r out/* "$outDir"
exFl=$?
if [ "$exFl" -ne 0 ]; then
	echo "Moving results from server to $outDir was not successful! Error code: $exFl"
	exit $exFl
else
	echo "Results transferred!"
fi


## Testing part. Should be deleted later START
echo "File: ${argsFile}"
#echo "${argsStr[@]} -species $specName -species_file $specList"
#ls

## Testing part. Should be deleted later END

## End
# Move everything in one folder to avoid coping stuff back to the machine
mv !(tmp) tmp 
mv tmp/_condor_std* ./ #make condor transfer err, output and log
ls

exit 0
