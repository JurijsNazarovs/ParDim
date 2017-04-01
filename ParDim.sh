#!/bin/bash
#===============================================================================
# parDim.sh creates the pipeline (the dag file)
# with an ordered tasks from the pull of possible tasks,
# based on the stage of pipeline, specified by user. 
# Some of possible tasks can produce their own dag jobs, and not just jobs.
#
# The first task is executed on a submit machine,
# while other in a sequence are writen as JOB in the main dag file.
#
#                             Pipeline description
#-------------------------------------------------------------------------------
#   Task        Script                Output dag files      Description: 
#-------------------------------------------------------------------------------
# - download    boostDownload.sh      downloadFiles.dag     download data based on table
# - alignment   makeAlignmentDag.sh   alignment.dag         implements some allignment
# - aquas       makeAquasDag.sh       aquas.dag             implement aquas pipeline
#-------------------------------------------------------------------------------
#
# Input:
#      -argsFile       file with all arguments for this shell
#
# Possible arguments are described in a section: ## Default values
#===============================================================================
## Libraries, input from the line arguments
shopt -s nullglob #allows create an empty array
homePath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" #cur. script locat.
scriptsPath="$homePath/scripts"
source "$scriptsPath"/funcList.sh

curScrName=${0##*/} #delete all before last backSlash
#curScrName=${curScrName%.*}

echoLineBold
echo "[Start] $curScrName"


## Prior parameters
argsFile=${1:-"args.listDev"} #file w/ all arguments for this shell

coreTask=("download" "preprocess")
coreTaskScript=("$scriptsPath/boostDownload.sh"
                "$scriptsPath/makePreprocessDag.sh")
coreTaskStage=("false" "false") #implement or not

integrTask=("allignment" "aquas")
integrTaskScript=("$scriptsPath/makeAlignmentDag.sh"
                  "$scriptsPath/makeAquasDag.sh")
# Stages of tasks have to be presented as intervals with 2 bounds
integrTaskStage=($(mapStage "toTag")    $(mapStage "toTag")
                 $(mapStage "pseudo")   $(mapStage "idroverlap"))

# [Dev] Check that integrTaskStage set ok
if [ -n "$(getInd "-1" ${integrTaskStage[@]})" ]; then
    # errMsg "[dev] wrong input of taskStage"
    echo "[dev] wrong input of taskStage"
fi


######## This part is important, need to move later.
######## Need to define core and integrated tasks first
task=("${coreTask[@]}" "${integrTask[@]}")
taskScript=("${coreTaskScript[@]}" "${integrTaskScript[@]}")

taskArgsLabsDelim="#" #used in exeMultidag.sh to split taskArgsLabs
for i in "${task[@]}"; do
  taskDag=("${taskDag[@]}" "$i.dag") #resulting .dag file. Name NOT path
  taskArgsLabs=("${taskArgsLabs[@]}"
               "$(joinToStr "$taskArgsLabsDelim" "$curScrName" "${task[$i]}")")
done

## Detect executable tasks from the file: core and integrated
# Detect all possible labels of scritps based on pattern:
# ##[scrLab]## - Case sensetive. Spaces are not important at all.
readarray -t taskPos <<<\
          "$(awk -v pattern="^(##)\\\[.*\\\](##)$"\
           '{
             gsub (" ", "", $0) #delete spaces
             if ($0 ~ pattern){
                scrLab = gensub(/##\[(.*)\]##/, "\\1", "", $0)
                print scrLab
             }
            }' < "$argsFile"
          )" #has to keep order of taskPos!

taskPosNoDupl=($(echo "${taskPos[@]}" | tr " " "\n" | sort | uniq))
if [[ ${#taskPosNoDupl[@]} -ne ${#taskPos[@]} ]]; then
    # Just values which are repeated once
    taskPosUniq=($(echo "${taskPos[@]}" | tr " " "\n" | uniq -u))
    taskPosDupl=($(echo "${taskPosNoDupl[@]}" "${taskPosUniq[@]}" |
                       tr " " "\n" |
                       sort |
                       uniq -u))
    taskPosDupl=("$(joinToStr ", " "${taskPosDupl[@]}")")
    errMsg "Duplicates of tasks are impossible.
            Followings tasks are duplicated:
            ${taskPosDupl[@]}"
fi

echo "Possible tasks in order: ${taskPos[@]}"
exit 1
## Decision to use coreTask
for i in ${!coreTask[@]}; do
  execute=false
  readArgs "$argsFile" 1 "${coreTask[$i]}" execute  > /dev/null
  
  if [[ "$execute" != true && "$execute" != false ]]; then
      warnMsg "The value of execute = $execute is not recognised.
              Core task \"${coreTask[$i]}\" will not be executed"
  else
    coreTaskStage[$i]="$execute"
  fi
done


## Input and default values
posArgs=("inpPath"  #[R] path for: input data; output of download task
         "outPath"  #[R] path for  output
         "firstStage"
         "lastStage"
         "jobsDir"  #tmp working directory for all files
         "selectJobsTabPath" #path to table with jobs to execute. If empty,
                             #then all from inpPath
        )

jobsDir=$(mktemp -duq dagTestXXXX)
mainJobsFile="$jobsDir/pipelineMain.dag" #dag description of the whole pipeline

readArgs "$argsFile" 1 "$curScrName" "${posArgs[@]}"
printArgs "$curScrName" "argsFile" "${posArgs[@]}"

firstStage=$(mapStage "$firstStage")
lastStage=$(mapStage "$lastStage")


## Initial checking
# Stages
chkStages "$firstStage" "$lastStage"

if [[ "$firstStage" -eq 0 &&  "$lastStage" -eq 0 &&
    "${coreTaskStage[0]}" = false && "${coreTaskStage[1]}" = false ]]; then
    errMsg "No stages or core tasks are selected for the pipeline."
fi

# Arguments of main (THIS) script
if [[ !("$firstStage" -eq 0 &&
            "$lastStage" -eq 0 &&
            "${coreTaskStage[1]}" = false) ]]; then
    # Case when we have some other parts except downloading
    chkAvailToWrite "outPath"

    if [[ -z "$selectJobsTabPath" ]]; then
        chkExist d "$inpPath" "inpPath: $inpPath"

        selectJobsTabPath="$(mktemp -qu "$homePath/$jobsDir/"selectJobs.XXXX)"
        echo "[dev] less $selectJobsTabPath"
        if [[ "${coreTaskStage[0]}" = false ]]; then
            # No downloading => create file
            ls -d "$inpPath/"* > "$selectJobsTabPath" 
        fi
    else
      chkExist f "$selectJobsTabPath"\
               "List of selected directories: $selectJobsTabPath"
      while IFS='' read -r dirPath || [[ -n "$dirPath" ]]; do
	chkExist d "$dirPath" "selectJobsTabPath: $dirPath"
      done < "$selectJobsTabPath"
    fi
fi

if [[ "${coreTaskStage[0]}" = true ]]; then
    # Downloading
    chkAvailToWrite "inpPath"
fi

echo "Creating temporary folder:  $jobsDir ..."
mkdir -p "$jobsDir"

exit 1

## Condor file
# To execute one of taskScripts (dagMakers) for selected or all jobs in inpPath.
# It creates dag file and returns it back
conDagMaker="$homePath/$jobsDir/makeDag.condor" 
conOut="$homePath/$jobsDir/conOut"  #output folder for condor
mkdir -p "$conOut"

# Args for condor job, corresponding to order of args in exeMultiDag.sh
argsCon=("\$(dagScript)"  #variable -script name
         "${argsFile##*/}"
         "$taskArgsLabsDelim"
         "\$(taskArgsLabs)" #variable - string with argument labels
         "\$(dagName)" #variable - output dag file name
         "$scriptsPath"
         "$jobsDir"
         "${selectJobsTabPath##*/}")
argsCon=$(joinToStr "\' \'" ${argsCon[@]})
# Variables have to be specified in $mainJobsFile (main dag file) using VARS.
# It is important to pass $scriptsPath, since new condor jobs
# (created on executed machine and returned back) must have executable file
# from $scriptsPath and not from homePath of executable machine.

transFilesCon=("$scriptsPath/funcList.sh"
               "$scriptsPath/makeCon.sh"
               "\$(dagScript)"
               "$homePath/$argsFile"
               "$selectJobsTabPath") #transfer files
transFilesCon=("$(joinToStr ", " ${transFilesCon[@]})")

bash "$scriptsPath"/makeCon.sh "$conDagMaker" "$conOut"\
     "$scriptsPath/exeMultiDag.sh" "$argsCon" "$transFilesCon" "1" "1" "1"


## DAG file, which assign tasks in a right order

# [Start] Print the file description - Head
echoLineBoldSh
echo "[Start] Creating $mainJobsFile" 

printfLine > "$mainJobsFile"
printf "# [Start] Description of $mainJobsFile\n" >> "$mainJobsFile"
printfLine >> "$mainJobsFile"

printfLine >> "$mainJobsFile"
printf "# Input data path: $inpPath\n" >> "$mainJobsFile"
printf "# Output data path: $outPath\n" >> "$mainJobsFile"
printfLine >> "$mainJobsFile"

printfLine >> "$mainJobsFile"
printf "# This file manages the order of parts in the pipeline\n" >>\
       "$mainJobsFile"
printf "# \n" >> "$mainJobsFile"
printf "# Possible parts:\n" >> "$mainJobsFile"
for i in ${!taskName[@]}
do
  printf "#\t$((i+1)). ${taskName[$i]}\t\t${taskScript[$i]}\n" >>\
         "$mainJobsFile"
done
printfLine >> "$mainJobsFile"

printf "CONFIG $scriptsPath/dag.config\n" >> "$mainJobsFile"
printfLine >> "$mainJobsFile"
# [End] Print the file description - Head

# [Start] Print the jobs section - Stages
isFT="true" #is the First Task
lastTask="" #last executed task for PARENT CHILD dependency
firstStageOut="$jobsDir/firstStage.out" #echo first output stage here
for i in ${!taskName[@]} #change for taskIter
do

  if [[ $(interInt "$(echo ${taskStage[@]:(( i*2 )):2 } )"\
                    "$firstStage $lastStage") -eq 1 ||\
            ($i -eq 0 && "$isDownload" = true) ]]; then
  
      # If our task is the first one, then we execute it
      # otherwise, we write it as a job in condor and create this condor

      # Condor/local part, not Dag
      if [[ "$isFT" = true ]]; then
          
          if [[ $i -eq 0 ]]; then #downloading
              bash "${taskScript[$i]}"\
                   "$argsFile"\
                   "${taskDag[$i]}"\
                   "false"\
                   "$taskArgsLabsDelim"\
                   "${taskArgsLabs[$i]}"\
                   "false"\
                   > "$firstStageOut" 
          else
            # [Notice] I do provide jobsDir to exeMultiDag.sh,
            # since new files should be written in that folder.
            bash "$scriptsPath"/exeMultiDag.sh\
                 "${taskScript[$i]}"\
                 "$argsFile"\
                 "$taskArgsLabsDelim"\
                 "${taskArgsLabs[$i]}"\
                 "${taskDag[$i]}"\
                 "$scriptsPath"\
                 "$jobsDir"\
                 "$selectJobsTabPath"\
                 "false"\
                 > "$firstStageOut"
          fi

          exFl=$?
          if [[ $exFl -ne 0 ]]; then
              errMsg "File \"${taskDag[$i]}\" was not generated by
                      ${taskScript[$i]##*/}"
          else
            isFT="false" #not a first stage anymore
          fi
      else
        jobId="${taskName[$i]}"
        # Parent Child Dependency 
        if [[ -n "$(rmSp $lastTask)" ]]; then
            printf "PARENT $lastTask CHILD $jobId\n" >> "$mainJobsFile"
            printfLineSh >> "$mainJobsFile"
        fi
        # Create list of analysed folders after download
        if [[ "$lastTask" = "${taskName[0]}Dag" ]]; then #downloading 
            printf "SCRIPT PRE $jobId $scriptsPath/postScript.sh " >>\
                   "$mainJobsFile" 
            printf "$selectJobsTabPath jobsList $inpPath \n" >>\
                   "$mainJobsFile"
        fi

        # Print the condor job
        # [Notice] I do not provide jobsDir to $conDagMaker,
        # because I just return files back in that folder(jobsDir),
        # using postscript. 
        # And i use some tmp folder inside of the exeMultiDag.sh.
        printf "JOB $jobId $conDagMaker DIR $jobsDir\n" >> "$mainJobsFile"
        printf "VARS $jobId dagScript=\"${taskScript[$i]}\"\n" >>\
               "$mainJobsFile" #need to be transfered
        printf "VARS $jobId taskArgsLabs=\"${taskArgsLabs[$i]}\"\n" >>\
               "$mainJobsFile" #string with labels
        printf "VARS $jobId dagName=\"${taskDag[$i]}\"\n" >>\
               "$mainJobsFile" #just a name

        # Post Script to move dag files in right folders
        printf "SCRIPT POST $jobId $scriptsPath/postScript.sh " >>\
               "$mainJobsFile"
        printf "${taskDag[$i]%.*}.tar.gz tar\n" >> "$mainJobsFile"

        lastTask="${taskName[$i]}" #save last executed task
      fi

      # Dag part corresponding to the stage, if it is not empty
      if [[ -n "$(rmSp ${taskDag[$i]})" ]]; then
          jobId="${taskName[$i]}Dag"
          # Parent Child Dependency
          if [[ -n "$(rmSp $lastTask)" ]]; then #i.e. we had a task before
              printf "PARENT $lastTask CHILD $jobId\n\n" >> "$mainJobsFile"
          fi

          printf "SUBDAG EXTERNAL $jobId $jobsDir/${taskDag[$i]}\n" >>\
                 "$mainJobsFile"
          lastTask="$jobId" #save last executed task

      fi
  fi
done

# Delete tmp folder $jobsDir
#printf "#SCRIPT POST $lastTask $scriptsPath/postScript.sh $jobsDir \n" >> "$mainJobsFile"
# [End] Print the jobs section - Stages

# End of file
printfLine >> "$mainJobsFile"
printf "# [End]  Description of $mainJobsFile\n" >> "$mainJobsFile"
printfLine >> "$mainJobsFile"

echo "[End]  Creating $mainJobsFile"
echoLineBoldSh

## Submit mainDAG.dag
if [[ "$isFT" = true ]]; then
    errMsg "0 jobs are queued by $curScrName"
else
  #condor_submit_dag -f $mainJobsFile
  echo "$mainJobsFile was submitted!"
  echo ""
fi

## End
echo "[End]  $curScrName"
echoLineBold
exit 0
