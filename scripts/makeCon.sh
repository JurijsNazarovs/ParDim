#!/bin/bash

shopt -s nullglob #allows create an empty array
homePath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$homePath"/funcList.sh #call file with functions

### Prior parameters
#homePath="$PWD" #exported from the first shell pipeDAG.dag
#specList #exported from the first shell pipeDAG.dag
#specPath #exported from the first shell pipeDAG.dag
conFile=${1:-"tmp.condor"}
#conFile="${exeFile%.*}.condor"

outPath=${2:-"conOut"}
mkdir -p $outPath
#outPath="/home/nazarovs/pipeTest/out"

exeFile=${3:-"exePipe.sh"} #from the root folder	
args=${4:-""} #array of arguments from condor to executable
transFiles=${5:-""} #files to transfer

coresNum=${6:-"1"}
ram=${7:-"3"}
hd=${8:-"10"}

repFl=${9:-"1"} #repeat? 1-yes, 0 - not

### Main part

printfLine > "$conFile"
printf "# [Start] Description of $conFile\n" >> "$conFile"
printfLine >> "$conFile"
printf "universe = vanilla\n\n" >> "$conFile"

## Options
printf \
    "## Options
should_transfer_files = YES
when_to_transfer_output = ON_EXIT
getenv = true
\n" >> "$conFile"

if [ "$repFl" -ne "0" ]; then
    # Job should only leave the queue if it exited on its own with status 0,
    # to repeat jobs if there is a segmentation fault.
    printf "on_exit_remove = ( (ExitBySignal == False) && (ExitCode == 0) )\n"\
           >> "$conFile"

    # Put job on hold if it was restarted > 5 times
    printf "on_exit_hold = (NumJobStarts > 5)\n" >> "$conFile"

    # Release job from hold because of squid:
    printf "periodic_release =  ((JobStatus == 5) && (HoldReasonCode == 12) && "\
            >> "$conFile"
    printf "(NumJobStarts <= 5) && (CurrentTime - EnteredCurrentStatus) > 300)\n"\
           >> "$conFile"
    # The above will make sure that a job is still never released to run more
    # than 5 times and that HTCondor will wait a little while (300 seconds)
    # before releasing the job to try again.
    
fi


if [ "$(rmSp $transFiles)" != "" ]; then
    printf "transfer_input_files = $transFiles\n" >> "$conFile"
fi


## Output
printf \
    "## Output
output = $outPath/condor\$(Cluster).out
error = $outPath/condor\$(Cluster).err
log = $outPath/condor\$(Cluster).log
\n" >> "$conFile"

## Requirements
#Requirements = (Target.HasGluster == true) && (Arch == "X86_64") && (OpSys =="LINUX")
printf \
    "## Requirements
Requirements = (Target.HasGluster == true)

request_cpus = $coresNum
request_memory = ${ram}GB
request_disk = ${hd}GB
\n" >> "$conFile"

## Execution
printf "## Execution \n" >> "$conFile"

if [ "$(rmSp $args)" != "" ]; then
    printf "arguments = \" \'$args\' \" \n" >> "$conFile"
fi
printf "executable = $exeFile\n" >> "$conFile"

## End
printf "queue\n" >>  "$conFile"

### End
printfLine >> "$conFile"
printf "# [End] Description of $conFile\n" >> "$conFile"
printfLine >> "$conFile"

#less $conFile






