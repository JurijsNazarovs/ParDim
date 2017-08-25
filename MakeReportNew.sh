#!/bin/bash
# ==============================================================================
# makeReport.sh creates following files (lists):
#
# Single/Multi task
# 1. *.queuedJobs.list - queued jobs
# 2. *.compJobs.list - completed jobs
# 3. *.notCompJobs.list - currently not completed jobs
# 4. *.holJobsReason.list - holding lines given reason $holdReason
# 5. *.holdJobs.list - jobs on hold given reason $holdReason
#
# Multi task
# 6. *.summaryJobs.list - summary info about dirs
# 7. *.notCompDirs.list - path to not completed dirs
# 8. *.compDirs.list - path to completed dirs
#
# holdReason="" - all hold jobs
#
# Input:
#  - task - task or stageName of which to get summary
#  - jobsDir - the working directory for the task
#  - reportDir - directory to create all report files
#  - holdReason - reason for holding jobs, e.g. "" - all hold jobs, "72 hrs"
#  - delim - delimeter to use for output files
# ==============================================================================

## Libraries, input from the line arguments
homePath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" #cur. script locat.
scriptsPath="$homePath/scripts"
source "$scriptsPath"/funcListParDim.sh

curScrName=${0##*/} #delete all before last backSlash

TimeFromSeconds()
{
  local T=$1
  local D=$((T/60/60/24))
  local H=$((T/60/60%24))
  local M=$((T/60%60))
  local S=$((T%60))
  (( $D > 0 )) && printf '%d days ' $D
  (( $H > 0 )) && printf '%d hours ' $H
  (( $M > 0 )) && printf '%d minutes ' $M
  (( $D > 0 || $H > 0 || $M > 0 )) && printf 'and '
  printf '%d seconds\n' $S
}

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

## Input
task=${1:-Download} #task to get summary of
jobsDir=${2:-tmp/jobsDir} #the working directory for the task
reportDir=${3:-report} #directory to create all report files
holdReason=${4:-""} #reason for holding jobs, e.g. "" - all hold jobs, "72 hrs"
delim=${5:-,} #delimeter to use for output files


## Prior parameters
jobsDir="$(readlink -m "$jobsDir")"
reportDir="$(readlink -m "$reportDir")"

mainPipelineFile="$jobsDir/ParDim.main.dag.dagman.out"
queuJobsFile="$reportDir/$task.queuedJobs.list" #qued but not necessary all
compJobsFile="$reportDir/$task.compJobs.list"
notCompJobsFile="$reportDir/$task.notCompJobs.list"
holdJobsFile="$reportDir/$task.holdJobs.list"
holdJobsReasFile="$reportDir/$task.holdJobsReas.list"

sumDirsFile="$reportDir/$task.summaryDirs.list"
notCompDirsFile="$reportDir/$task.notCompDirs.list"
compDirsFile="$reportDir/$task.compDirs.list"
timeFile="$reportDir/$task.time.list"

PrintArgs "$curScrName" "task" "jobsDir"  "reportDir" "holdReason"

ChkExist "d" "$jobsDir" "Working directory: $jobsDir \n"
ChkExist "f" "$mainPipelineFile" "Main pipeline info file: $mainPipelineFile \n"


## Detect the string for submitting node with all argumets
awkPattern="submitting: .* -a dag_node_name' '=' '$task -a \\\+DAGManJobId"
submitStr="$(
  awk -v pattern="$awkPattern"\
      '{
        if ($0 ~ pattern){
           print($0)
           exit
           }
       }' "$mainPipelineFile"
         )"

if [[ -z $(RmSp "$submitStr") ]]; then
    ErrMsg "Task $task has no story of execution
           in the directory $jobsDir.
           History file: $mainPipelineFile"
fi
mkdir -p "$reportDir"


## Detect running time
printf "" > "$timeFile"
for i in "" "Dag"; do  #endings for pattern: 1-construct dag, 2-execute dag
  taskName="$task$i"
  
  taskFirstStr="$(
    awk -v pattern="$Submitting HTCondor Node $taskName"\
        '{
        if ($0 ~ pattern){
           print($0)
           exit
           }
       }' "$mainPipelineFile"
              )"
  timeStart="$(cut -d " " -f 1,2 <<< "$taskFirstStr")" #date and time

  taskLastStr="$(
    awk -v pattern="Node $taskName job completed"\
        '{
        if ($0 ~ pattern){
           print($0)
           isJobCompleted=1
           exit
           }
       } 
       
       END {
        if (!isJobCompleted){
           print($0)
        }
       }' "$mainPipelineFile"
            )"
  timeEnd="$(cut -d " " -f 1,2 <<< "$taskLastStr")" #date and time

  timeDif="$(( $(date -ud "$timeEnd" +'%s') - $(date -ud "$timeStart" +'%s') ))"

  # Print resutls
  PrintfLine >> "$timeFile"
  if [[ "$i" == "" ]]; then
      printf "# Construct dag for the task: $task\n" >> "$timeFile"
  else
    printf "# Execute dag constructed by the task: $task\n" >> "$timeFile"
  fi
  PrintfLine >> "$timeFile"
  printf "Start: $timeStart\n" >> "$timeFile"
  printf "End:   $timeEnd\n" >> "$timeFile"
  printf "Run:   $(TimeFromSeconds "$timeDif")\n" >> "$timeFile"
done
exit 1
## Detect the map used for the task
taskMap="$(
  awk -F "\047"\
      '{
        for (i = 1; i <= NF; i++){
            if ($i ~ "-a exeMap"){
               fileName = gensub(/.*\/(.+) -a .*/, "\\1", "", $(i+4))
               print(fileName)
               exit
           }
        }
     }' <<< "$submitStr"
              )"


## Create temporarty files and detect log file
tmpFile1="$reportDir/$(mktemp -uq tmp.XXXX)"
tmpFile2="$reportDir/$(mktemp -uq tmp.XXXX)"

if [[ "$taskMap" = *Multi* ]]; then
    echo "Task $task corresponds to a multi map"
   
    tmpFile3="$reportDir/$(mktemp -uq tmp.XXXX)"
    logFile="$jobsDir/multiMap/$task/$task.dag.dagman.out"
fi

if [[ "$taskMap" = *Single* ]]; then
    echo "Task $task corresponds to a single map"

    logFile="$jobsDir/singleMap/$task/$task.dag.dagman.out"
fi


## Queued jobs
if [[ "$taskMap" = *Multi* ]]; then
    printf "Queued jobs ... "
    # File1. 2 columns: Dag#, condorJob, condorId
    less "$logFile" \
        | grep "ULOG_SUBMIT"\
        | cut -d " "  -f 9,10\
        | sort -uk 1,1 \
        | sed "s/[+| ]/$delim/g" \
              > "$tmpFile1"

    # File2. 2 columns: Dag#, experiment dir (from path to file.dag)
    less "$logFile" \
        | grep "Parsing Splice" \
        | cut -f 6,12 -d " " \
        | sort -u \
        | sed "s/ /$delim/g" \
              > "$tmpFile2"

    printf "" > "$tmpFile3"
    while IFS="$delim" read -r dagCol pathCol; do
      pathCol="${pathCol%/*}"
      pathCol="${pathCol##*/}"
      printf "%s$delim%s\n" "$dagCol" "$pathCol" >> "$tmpFile3"
    done < "$tmpFile2"

    # Queud jobs file. 3 columns: Dag#, experiment dir, condor job.
    join -t "$delim" "$tmpFile3" "$tmpFile1" > "$tmpFile2"
    mv "$tmpFile2" "$queuJobsFile"
    printf "done\n"
fi

if [[ "$taskMap" = *Single* ]]; then
    printf "Queued jobs ... "
    # File1. 2 columns: Dag#, condorJob, condorId
    less "$logFile" \
        | grep "ULOG_SUBMIT"\
        | cut -d " "  -f 9,10\
        | sort -uk 1,1 \
        | sed "s/[+| ]/$delim/g" \
              > "$queuJobsFile"
    
    printf "done\n"
fi


## Completed Jobs
printf "Completed jobs ... "
# Condor id of completed
less "$logFile" \
    | grep "completed successfully" \
    | cut  -d " " -f 8\
    | sort -u \
           > "$tmpFile1"
# Take info from list of queued jobs
grep -f "$tmpFile1" "$queuJobsFile" > "$compJobsFile"
printf "done\n"


## Not completed jobs
printf "Not completed jobs ... "
# Substraction of compJobsFile from queuJobsFile
comm -13 "$compJobsFile" "$queuJobsFile" > "$notCompJobsFile"
printf "done\n"


## Hold Jobs
printf "Hold jobs "
if [[ -n $(RmSp "$holdReason") ]]; then
    printf "for reason \"$holdReason\" "
fi
printf "... "

# File with holding reason lines
PrintfLine > "$holdJobsReasFile"
printf "# This is a history file of all hold reasons, since\n"\
       >> "$holdJobsReasFile"
printf "# some jobs might be released and finished successfully\n"\
       >> "$holdJobsReasFile"
PrintfLine >> "$holdJobsReasFile"
less "$logFile" \
    | grep  -A 1 "Event: ULOG_JOB_HELD" \
    | grep -B 1 "$holdReason" \
    | grep -v -- "^--$" \
    | grep "$holdReason" \
           >> "$holdJobsReasFile"

# Condor id of holding jobs given the reason
tail -n +5 "$holdJobsReasFile" \
    | cut  -d " " -f 10 \
    | sort -u \
           > "$tmpFile1"
# Take info from list of queued jobs
grep -f "$tmpFile1" "$queuJobsFile" > "$tmpFile2"
# Select jobs which are not among complete jobs, since a hold job might
# be released if issue is fixed
comm -23 "$tmpFile2" "$compJobsFile" > "$holdJobsFile"
printf "done\n"

## Summary, completed dirs, not completed dirs
if [[ "$taskMap" = *Multi* ]]; then
    ## Summary of jobs
    printf "Summary of jobs ... "
    # File1. 2 columns: Dag#,  experiment dir
    less "$queuJobsFile" \
        | cut -d "$delim"  -f 1,2 \
        | sort -u \
               > "$tmpFile1"

    # File2. 2 columns: #completedJobs, #queuedJobs
    printf "" > "$tmpFile2"
    while IFS="$delim" read -r dagCol restCol; do
      nComJobs=$(less "$compJobsFile" | grep -P "$dagCol$delim" | wc -l) 
      nQueJobs=$(less "$queuJobsFile" | grep -P "$dagCol$delim" | wc -l)
      printf "%s$delim%s\n" "$nComJobs" "$nQueJobs" >> "$tmpFile2"
    done < "$tmpFile1"  

    # Summary of jobs file. 4 columns:
    # Dag#,  experiment dir, #completedJobs, #queuedJobs
    paste -d "$delim" "$tmpFile1" "$tmpFile2" > "$sumDirsFile"
    printf "done\n"


    ## List of pathes not completed/completed dirs
    # Detect list with selected dirs for specific task
    selJobsListName="$(
    awk -F "\047"\
      '{
        for (i = 1; i <= NF; i++){
            if ($i ~ "-a selectJobsListPath"){
               fileName = gensub(/(.+) -a .*/, "\\1", "", $(i+4))
               print(fileName)
               exit
           }
        }
     }' <<< "$submitStr"
              )"

    selJobsListPath="$(
    awk -v RS="\047"\
      -v fileName="$selJobsListName"\
      '{
        if ($0 ~ "-a conMapTransFiles") {f = 1; next}
        if (f == 1 && $0 ~ fileName) {
           filePath = gensub(/(.+) -a .*/, "\\1", "", $0)
           print(filePath)
           exit
        } 
     }' <<< "$submitStr"
              )"

    # Completed dirs
    # if nCompJobs == nQueJobs => print dir 
    printf "Completed directories ... "
    awk -v FS="$delim" -v OFS="$delim"\
        '{
        if ($3 == $4){
           print($2)
       }
     }' "$sumDirsFile" \
        > "$tmpFile1"
    grep -f "$tmpFile1" "$selJobsListPath" > "$compDirsFile"
    printf "done\n"

    # Not completed dirs
    printf "Not completed directories ... "
    grep -v -f "$compDirsFile" "$selJobsListPath" > "$notCompDirsFile"
    printf "done\n"
fi


rm -rf "$tmpFile1" "$tmpFile2"

if [[ "$taskMap" = *Multi* ]]; then
    rm -rf "$tmpFile3"
fi

EchoLineSh
echo "[End]   $curScrName"
EchoLineBold
