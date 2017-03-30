#!/bin/bash
# ==============================================================================
# makeReport.sh creates following files (lists):
# 1. *.queuedJobs.list - queued jobs
# 2. *.compJobs.list - completed jobs
# 3. *.notCompJobs.list - currently not completed jobs
# 4. *.holJobsReason.list - holding lines given reason $holdReason
# 5. *.holdJobs.list - jobs on hold given reason $holdReason
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

echoLineBold
echo "[Start]   $curScrName"

## Input
logFile=${1:-"tmp/aquas.dag.dagman.out"}
repDir=${2:-"report"}
delim=${3:-,}
holdReason=${4:-""} #reason for holding jobs. "" - all hold jobs. "72 hrs"

#inpPath for data to create list of not finished folders
inpPath=${5:-"/mnt/gluster/nazarovs/knzRuns/tmp/awkRuns2Bam"} 

## Prior parameters
mkdir -p "$repDir"
mainNameFile="${logFile##*/}" #part of name used in all saved files
mainNameFile="${mainNameFile%%.*}"

queuJobsFile="$repDir/${mainNameFile}.queuedJobs.list"
compJobsFile="$repDir/${mainNameFile}.compJobs.list"
notCompJobsFile="$repDir/${mainNameFile}.notCompJobs.list"
holdJobsFile="$repDir/${mainNameFile}.holdJobs.list"
holdJobsReasFile="$repDir/${mainNameFile}.holdJobsReas.list"

sumDirsFile="$repDir/${mainNameFile}.summaryDirs.list"
notCompDirsFile="$repDir/${mainNameFile}.notCompDirs.list"
compDirsFile="$repDir/${mainNameFile}.compDirs.list"

tmpFile1="$repDir/$(mktemp -duq tmp.XXXX)"
tmpFile2="$repDir/$(mktemp -duq tmp.XXXX)"
tmpFile3="$repDir/$(mktemp -duq tmp.XXXX)"

printArgs "$curScrName" "logFile" "repDir" "holdReason"


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
if [[ -n $(rmSp "$holdReason") ]]; then
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

## List of pathes not completed/completed  dirs
if [[ -n "$(rmSp "$inpPath")" ]]; then
    # Not completed dirs
    # nCompJobs != nQueJobs => print inpPath/dir
    printf "Not completed directories ... "
    awk -v FS="$delim" -v OFS="$delim"\
        -v inpPath="$inpPath"\
        '{
          if ($3 != $4){
             print inpPath "/" $2
          }
         } 
        ' "$sumDirsFile" \
            > "$notCompDirsFile"
    printf "done\n"
    
    # Completed dirs
    # nCompJobs == nQueJobs => print inpPath/dir
    printf "Completed directories ... "
    awk -v FS="$delim" -v OFS="$delim"\
        -v inpPath="$inpPath"\
        '{
          if ($3 == $4){
             print inpPath "/" $2
          }
         } 
        ' "$sumDirsFile" \
            > "$compDirsFile"
    printf "done\n"
fi

rm -rf "$tmpFile1" "$tmpFile2" "$tmpFile3"

echoLineSh
echo "[End]   $curScrName"
echoLineBold
