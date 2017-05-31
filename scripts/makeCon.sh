#!/bin/bash
#===============================================================================
# makeCon.sh creates the description of a condor submit file,
# depending on parameters.
#===============================================================================

## Libraries
shopt -s nullglob #allows create an empty array
homePath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$homePath"/funcList.sh #call file with functions

## Input
conFile=${1:-"condor.tmp"}
outPath=${2:-"conOut"}
exeFile=${3:-""}	
args=${4:-""} #string of arguments from condor to executable" (1\ \2\ \3)
transFiles=${5:-""} #files to transfer

nCpus=${6:-"1"}
memSize=${7:-"3"}
diskSize=${8:-"10"}

transOut=${9:-""}
transMap=${10:-""}

isRepeat=${11:-"true"} #1 - repeat in case of failure
#isHold
isGluster=${12:-"false"}


## Initial checking
ChkValArg "isRepeat" "" "false" "true"
ChkValArg "isGluster" "" "false" "true" 
#ChkExist f "$exeFile" "Executed file for condor: $exeFile\n"
if [[ -z $(RmSp "$conFile") ]]; then
    conFile="$(mktemp -qu conFile.XXXX)"
fi

## Main part
mkdir -p "$outPath"

PrintfLine > "$conFile"
printf "# [Start] Description of $conFile\n" >> "$conFile"
PrintfLine >> "$conFile"
printf "universe = vanilla\n\n" >> "$conFile"

## Options
printf \
    "## Options
should_transfer_files = YES
when_to_transfer_output = ON_EXIT
getenv = true
\n" >> "$conFile"

if [[ "$isRepeat" = true ]]; then
    # Job should only leave the queue if it exited on its own with status 0,
    # to repeat jobs if there is a segmentation fault.
   # printf "on_exit_remove = ( (ExitBySignal == False) && (ExitCode == 0) )\n"\
    #       >> "$conFile"

    # Put job on hold if it was restarted > 5 times
    printf "on_exit_hold = (NumJobStarts > 5)\n" >> "$conFile"

    # Release job from hold because of squid:
    printf "periodic_release =  ((JobStatus == 5) && (HoldReasonCode == 12) && "\
            >> "$conFile"
    printf "(NumJobStarts <= 5) && (CurrentTime - EnteredCurrentStatus) > 300)
           \n" >> "$conFile"
    # The above will make sure that a job is still never released to run more
    # than 5 times and that HTCondor will wait a little while (300 seconds)
    # before releasing the job to try again.
    
fi


if [[ -n $(RmSp "$transFiles") ]]; then
    printf "transfer_input_files = $transFiles\n" >> "$conFile"
fi

if [[ -n $(RmSp "$transOut") && -n $(RmSp "$transMap") ]]; then
    printf "transfer_output = $transOut\n" >> "$conFile"
    printf "transfer_output_remaps = \"$transMap\" \n" >> "$conFile"
fi

 
## Output
printf \
    "## Output
output = $outPath/condor\$(Cluster).out
error = $outPath/condor\$(Cluster).err
log = $outPath/condor\$(Cluster).log
\n" >> "$conFile"


## Requirements
if [[ "$isGluster" = true ]]; then
    printf \
        "## Requirements
Requirements = (Target.HasGluster == true)
\n" >> "$conFile"
fi


## Request
printf \
    "## Request
request_cpus = $nCpus
request_memory = ${memSize}GB
request_disk = ${diskSize}GB
\n" >> "$conFile"


## Execution
printf "## Execution \n" >> "$conFile"

if [[ -n $(RmSp "$args") ]]; then
    printf "arguments = \" \'$args\' \" \n" >> "$conFile"
fi
printf "executable = $exeFile\n" >> "$conFile"

## End
printf "queue\n" >>  "$conFile"
PrintfLine >> "$conFile"
printf "# [End] Description of $conFile\n" >> "$conFile"
PrintfLine >> "$conFile"
