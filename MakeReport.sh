#!/bin/bash
# ==============================================================================
# makeReport.sh creates following files (lists):
# 1. *.queuedJobs.list - queued jobs
# 2. *.compJobs.list - completed jobs
# 3. *.notCompJobs.list - currently not completed jobs
# 4. *.holJobsReason.list - holding lines given reason $holdReason
# 5. *.holdJobs.list - jobs on hold given reason $holdReason
# 
# 6. *.summaryJobs.list - summary info about dirs
# 7. *.notCompDirs.lis - path to not completed dirs, if $inpPath is provided
# 8. *.compDirs.lis - path to completed dirs, if $inpPath is provided
#
# holdReason="" - all hold jobs
# ==============================================================================

## Libraries, input from the line arguments
homePath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" #cur. script locat.
scriptsPath="$homePath/scripts"
source "$scriptsPath"/funcList.sh

curScrName=${0##*/} #delete all before last backSlash

EchoLineBold
echo "[Start]   $curScrName"

## Input
task=${1:-"Download"} #task to get summary of
jobsDir=${2:-"tmp/hui6"} #the working directory for the task
reportDir=${3:-"report"} #directory to create all report files
holdReason=${4:-""} #reason for holding jobs, e.g. "" - all hold jobs, "72 hrs"
delim=${5:-,} #delimeter to use for output files


## Prior parameters
mkdir -p "$reportDir"

mainPipelineFile="$jobsDir/pipelineMain.dag.dagman.out"
queuJobsFile="$reportDir/$task.queuedJobs.list"
compJobsFile="$reportDir/$task.compJobs.list"
notCompJobsFile="$reportDir/$task.notCompJobs.list"
holdJobsFile="$reportDir/$task.holdJobs.list"
holdJobsReasFile="$reportDir/$task.holdJobsReas.list"

sumDirsFile="$reportDir/$task.summaryDirs.list"
notCompDirsFile="$reportDir/$task.notCompDirs.list"
compDirsFile="$reportDir/$task.compDirs.list"

PrintArgs "$curScrName" "task" "jobsDir"  "reportDir" "holdReason"


## Detect the string for submitting node with all argumets
awkPattern="submitting: .* -a dag_node_name' '=' '$task"
submitStr="$(
  awk -v pattern="$awkPattern"\
      '{
        if ($0 ~ pattern){
           print($0)
           exit
           }
       }' "$mainPipelineFile"
         )"


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


## MultiMap
if [[ "$taskMap" = *Multi* ]]; then
    echo "Task $task corresponds to multi map"
    
    tmpFile1="$reportDir/$(mktemp -duq tmp.XXXX)"
    tmpFile2="$reportDir/$(mktemp -duq tmp.XXXX)"
    tmpFile3="$reportDir/$(mktemp -duq tmp.XXXX)"

    logFile="$jobsDir/multiMap/$task/$task.dag.dagman.out"
    ## Queued jobs
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

    # Holding reason line
    less "$logFile" \
        | grep  -A 1 "Event: ULOG_JOB_HELD" \
        | grep -B 1 "$holdReason" \
        | grep -v -- "^--$" \
        | grep "$holdReason" \
               > "$holdJobsReasFile"

    # Condor id of hold given the reason
    less "$holdJobsReasFile" \
        | cut  -d " " -f 10 \
        | sort -u \
               > "$tmpFile1"
    # Take info from list of queued jobs
    grep -f "$tmpFile1" "$queuJobsFile" > "$holdJobsFile"
    printf "done\n"


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

    # Not completed dirs
    # if nCompJobs != nQueJobs => print dir 
    printf "Not completed directories ... "
    awk -v FS="$delim" -v OFS="$delim"\
        '{
        if ($3 != $4){
           print($2)
       }
     }' "$sumDirsFile" \
        > "$tmpFile1"
    grep -f "$tmpFile1" "$selJobsListPath" > "$notCompDirsFile"
    printf "done\n"

    # Completed dirs
    printf "Completed directories ... "
    grep -v -f "$notCompDirsFile" "$selJobsListPath" > "$compDirsFile"
    printf "done\n"

    rm -rf "$tmpFile1" "$tmpFile2" "$tmpFile3"
fi


## Single map
if [[ "$taskMap" = *Single* ]]; then
    echo "Task $task corresponds to single map"

    tmpFile1="$reportDir/$(mktemp -duq tmp.XXXX)"
    
    logFile="$jobsDir/singleMap/$task/$task.dag.dagman.out"
    ## Queued jobs
    printf "Queued jobs ... "
    # File1. 2 columns: Dag#, condorJob, condorId
    less "$logFile" \
        | grep "ULOG_SUBMIT"\
        | cut -d " "  -f 9,10\
        | sort -uk 1,1 \
        | sed "s/[+| ]/$delim/g" \
              > "$queuJobsFile"
    
    printf "done\n"

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

    # Holding reason line
    less "$logFile" \
        | grep  -A 1 "Event: ULOG_JOB_HELD" \
        | grep -B 1 "$holdReason" \
        | grep -v -- "^--$" \
        | grep "$holdReason" \
               > "$holdJobsReasFile"

    # Condor id of hold given the reason
    less "$holdJobsReasFile" \
        | cut  -d " " -f 10 \
        | sort -u \
               > "$tmpFile1"
    # Take info from list of queued jobs
    grep -f "$tmpFile1" "$queuJobsFile" > "$holdJobsFile"
    printf "done\n"

    rm -rf "$tmpFile1"
fi


EchoLineSh
echo "[End]   $curScrName"
EchoLineBold
