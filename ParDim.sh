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
# Input:
#      -argsFile       file with all arguments for this shell
#
# Possible arguments are described in a section: ## Default values
#===============================================================================
## Libraries/Input
shopt -s nullglob #allows create an empty array
homePath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" #cur. script locat.
scriptsPath="$homePath/scripts"
source "$scriptsPath"/funcList.sh

curScrName=${0##*/} #delete all before last backSlash
#curScrName=${curScrName%.*}

EchoLineBold
echo "[Start] $curScrName"
argsFile=${1:-"args.listDev"} #file w/ all arguments for this shell

## Detect structure of the pipeline

# Detect all possible labels of integrated tasks based on the patern:
# ##[    scrLab  ]## - Case sensetive. Might be spaces before, after and inside,
# but cannot split scrLab.
awkPattern="\
^([[:space:]]*##)\
\\\[[[:space:]]*[^[:space:]]+[[:space:]]*\\\]\
(##[[:space:]]*)$\
"
  
readarray -t taskPos <<<\
          "$(awk -F "\n"\
                  -v pattern="$awkPattern"\
           '{
             if ($0 ~ pattern){
                gsub (" ", "", $0) #delete spaces
                scrLab = gensub(/##\[(.+)\]##*/,
                                "\\1", "", $0)
                print scrLab
             }
            }' < "$argsFile"
          )" #has to keep order of taskPos!

readarray -t taskPosDupl <<< "$(ArrayGetDupls "${taskPos[@]}")"
taskPosDupl=("$(JoinToStr ", " "${taskPosDupl[@]}")")
if [[ -n "$taskPosDupl" ]]; then
    ErrMsg "Duplicates of tasks are impossible.
            Followings tasks are duplicated:
            $taskPosDupl"
fi

# Assign script, multimap, and files to transfer for a script
nTask=0 #helps to keep the order of integrated tasks
for i in "${taskPos[@]}"; do
  execute=false
  ReadArgs "$argsFile" 1 "$i" 1 "execute" "execute" > /dev/null
  if [[ "$execute" = true ]]; then
      script=""
      transFiles=""
      transFiles=""
      isMultiMap=true #if runs for every directory
      ReadArgs "$argsFile" 1 "$i" 3 "script" "isMultiMap" "transFiles"\
               "isMultiMap" > /dev/null

      # Checking existence of scripts
      script="$(readlink -m "$script")" #whole path
      ChkExist f "$script" "Script for $i: $script\n"
      if [[ "$curScrName" -ef "$script" ]]; then
          ErrMsg "$curScrName cannot be a script for $i,
              since it is the main pipeline script."
      fi

      # Checking files to transfer"
      readarray -t transFiles <<<\
                "$(awk\
                   '{ gsub(/,[[:space:]]*/, "\n"); print }' <<< "$transFiles"
                  )"
      for j in "${!transFiles[@]}"; do
        if [[ -n $(RmSp "${transFiles[$j]}") ]]; then
            transFiles[$j]="$(readlink -m "${transFiles[$j]}")"
            ChkExist f "${transFiles[$j]}" "transFile for $i: ${transFiles[$j]}\n"
            if [[ -z "${taskTransFiles[$nTask]}" ]]; then
                taskTransFiles[$nTask]="${transFiles[$j]}"
            else
              taskTransFiles[$nTask]="${taskTransFiles[$nTask]}, ${transFiles[$j]}"
            fi
        fi
      done
      
      # Assigning values to the corresponding script
      task["$nTask"]="$i"
      taskScript["$nTask"]="$script"
      if [[ "$isMultiMap" != false && "$isMultiMap" != true ]]; then
          ErrMsg "Task $i:
                 The value of isMultiMap = $isMultiMap is not recognised.
                 Please, check the value."
      fi
      taskMultiMap["$nTask"]="$isMultiMap"
      ((nTask ++))
  else
    if [[ "$execute" != false ]]; then
        WarnMsg "Task $i:
                 The value of execute = $execute is not recognised.
                 Task will not be executed."
    fi
  fi
done

if [[ ${#task[@]} -eq 0 ]]; then
    ErrMsg "Pipeline is empty, i.e. no tasks are assigned.
            Execution halted."
fi

# Checking duplication of scripts to give a warning
readarray -t taskScriptDupl <<< "$(ArrayGetDupls "${taskScript[@]}")"
if [[ -n "$taskScriptDupl" ]]; then #enough to check just first element
   for i in "${taskScriptDupl[@]}"; do
     readarray -t ind <<<\
               "$(ArrayGetInd "1" "$i" "${taskScript[@]}")"
     if [[ -n "$ind" ]]; then
         taskWithDuplScript=()
         for j in "${ind[@]}"; do
           taskWithDuplScript=("${taskWithDuplScript[@]}" "${task[$j]}")
         done
         taskWithDuplScript=("$(JoinToStr ", " "${taskWithDuplScript[@]}")")

         WarnMsg "The script: $i
                 is duplicated in following tasks:
                 ${taskWithDuplScript[@]}"
     fi
   done
fi


## Input and default values
posArgs=("dataPath"
         "jobsDir"  #tmp working directory for all files
         "selectJobsListPath" #path to table with jobs to execute. If empty,
                              #then all from dataPath
        )

jobsDir=$(mktemp -duq dagTestXXXX)
pipeStructFile="$jobsDir/pipelineMain.dag" #dag description of the whole pipeline
selectJobsListPath=""
ReadArgs "$argsFile" 1 "$curScrName" "${#posArgs[@]}" "${posArgs[@]}" >/dev/null

echo "Creating temporary folder:  $jobsDir ..."
mkdir -p "$jobsDir"


## Initial checking
if [[ -n "$(ArrayGetInd 1 "Download" "${task[@]}")" ]]; then
    isDownTask=true 
else
  isDownTask=false
fi
# Arguments of main (THIS) script (dataPath and selectJobsListPath)
if [[ (${#task[@]} -gt 1) || "$isDownTask" = false ]]; then
    # Case when we have parts except downloading
    
    if [[ -z $(RmSp "$selectJobsListPath") ]]; then
        if [[ -z $(RmSp "$dataPath") ]]; then
            ErrMsg "Please provide dataPath in $curScrName
                    to define directories for an analysis or
                    selectJobsListPath - list of analysed directories."
        fi
        ChkExist d "$dataPath" "dataPath: $dataPath"

        selectJobsListPath="$(mktemp -qu "$homePath/$jobsDir/"selectJobs.XXXX)"
        if [[ "$isDownTask" = false ]]; then
            # No downloading => create file
            ls -d "$dataPath/"* > "$selectJobsListPath" 
        else
          WarnMsg "Since you download data, make sure 
                  it is downloaded in dataPath = $dataPath ."
        fi
    else
      ChkExist f "$selectJobsListPath"\
               "List of selected directories: $selectJobsListPath"
      while IFS='' read -r dirPath || [[ -n "$dirPath" ]]; do
	ChkExist d "$dirPath" "selectJobsListPath: directory $dirPath"
      done < "$selectJobsListPath"
    fi
fi

if [[ "$isDownTask" = true ]]; then
    ChkAvailToWrite "dataPath"
fi


## Print pipeline structure
PrintArgs "$curScrName" "argsFile" "${posArgs[@]}"

maxLenStr=0
nZeros=${#task[@]} #number of zeros to make an order
nZeros=${#nZeros}
for i in "${task[@]}" "Files to Transfer";  do
  #echo "$i"
  maxLenStr=$(Max $maxLenStr ${#i})
done

EchoLineSh
echo "Pipeline structure in order:"
echo ""

for i in "${!task[@]}"
do
  # Script
  printf "%0${nZeros}d. %-$((maxLenStr + nZeros))s %s\n"\
         "$((i + 1))"\
        "${task[$i]}"\
        "${taskScript[$i]}"

  # Files to transfer
  if [[ -n "${taskTransFiles[$i]}" ]]; then
      readarray -t strTmp <<< "$(echo "${taskTransFiles[$i]}" | tr "," "\n")"
      printf "%0${nZeros}s  %-$((maxLenStr + nZeros))s %s\n"\
             ""\
             "Files to transfer"\
             "${strTmp[0]}"
      for j in "${strTmp[@]:1}"; do
        printf "%0${nZeros}s %-$((maxLenStr + nZeros))s %s\n"\
             ""\
             ""\
             "$j"
      done
  fi

  

done
EchoLineSh


for i in "${task[@]}"; do
  taskDag=("${taskDag[@]}" "$i.dag") #resulting .dag file. Name NOT path
done

exit 1

## Condor file
# To execute one of taskScripts (dagMakers) for selected jobs.
# It creates dag file and returns it back to submit server.
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
         "${selectJobsListPath##*/}")
argsCon=$(JoinToStr "\' \'" ${argsCon[@]})
# Variables have to be specified in $pipeStructFile (main dag file) using VARS.
# It is important to pass $scriptsPath, since new condor jobs
# (created on executed machine and returned back) must have executable file
# from $scriptsPath and not from homePath of executable machine.

transFilesCon=("$scriptsPath/funcList.sh"
               "$scriptsPath/makeCon.sh"
               "\$(dagScript)"
               "$homePath/$argsFile"
               "$selectJobsListPath") #transfer files
transFilesCon=("$(JoinToStr ", " ${transFilesCon[@]})")

bash "$scriptsPath"/makeCon.sh "$conDagMaker" "$conOut"\
     "$scriptsPath/exeMultiDag.sh" "$argsCon" "$transFilesCon" "1" "1" "1"


## DAG file, which assign tasks in a right order

# [Start] Print the file description - Head
EchoLineBoldSh
echo "[Start] Creating $pipeStructFile" 

PrintfLine > "$pipeStructFile"
printf "# [Start] Description of $pipeStructFile\n" >> "$pipeStructFile"
PrintfLine >> "$pipeStructFile"

PrintfLine >> "$pipeStructFile"
printf "# Input data path: $dataPath\n" >> "$pipeStructFile"
printf "# Output data path: $outPath\n" >> "$pipeStructFile"
PrintfLine >> "$pipeStructFile"

PrintfLine >> "$pipeStructFile"
printf "# This file manages the order of parts in the pipeline\n" >>\
       "$pipeStructFile"
printf "# \n" >> "$pipeStructFile"
printf "# Possible parts:\n" >> "$pipeStructFile"
for i in ${!taskName[@]}
do
  printf "#\t$((i+1)). ${taskName[$i]}\t\t${taskScript[$i]}\n" >>\
         "$pipeStructFile"
done
PrintfLine >> "$pipeStructFile"

printf "CONFIG $scriptsPath/dag.config\n" >> "$pipeStructFile"
PrintfLine >> "$pipeStructFile"
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
                 "$selectJobsListPath"\
                 "false"\
                 > "$firstStageOut"
          fi

          exFl=$?
          if [[ $exFl -ne 0 ]]; then
              ErrMsg "File \"${taskDag[$i]}\" was not generated by
                      ${taskScript[$i]##*/}"
          else
            isFT="false" #not a first stage anymore
          fi
      else
        jobId="${taskName[$i]}"
        # Parent Child Dependency 
        if [[ -n "$(RmSp $lastTask)" ]]; then
            printf "PARENT $lastTask CHILD $jobId\n" >> "$pipeStructFile"
            PrintfLineSh >> "$pipeStructFile"
        fi
        # Create list of analysed folders after download
        if [[ "$lastTask" = "${taskName[0]}Dag" ]]; then #downloading 
            printf "SCRIPT PRE $jobId $scriptsPath/postScript.sh " >>\
                   "$pipeStructFile" 
            printf "$selectJobsListPath jobsList $dataPath \n" >>\
                   "$pipeStructFile"
        fi

        # Print the condor job
        # [Notice] I do not provide jobsDir to $conDagMaker,
        # because I just return files back in that folder(jobsDir),
        # using postscript. 
        # And i use some tmp folder inside of the exeMultiDag.sh.
        printf "JOB $jobId $conDagMaker DIR $jobsDir\n" >> "$pipeStructFile"
        printf "VARS $jobId dagScript=\"${taskScript[$i]}\"\n" >>\
               "$pipeStructFile" #need to be transfered
        printf "VARS $jobId taskArgsLabs=\"${taskArgsLabs[$i]}\"\n" >>\
               "$pipeStructFile" #string with labels
        printf "VARS $jobId dagName=\"${taskDag[$i]}\"\n" >>\
               "$pipeStructFile" #just a name

        # Post Script to move dag files in right folders
        printf "SCRIPT POST $jobId $scriptsPath/postScript.sh " >>\
               "$pipeStructFile"
        printf "${taskDag[$i]%.*}.tar.gz tar\n" >> "$pipeStructFile"

        lastTask="${taskName[$i]}" #save last executed task
      fi

      # Dag part corresponding to the stage, if it is not empty
      if [[ -n "$(RmSp ${taskDag[$i]})" ]]; then
          jobId="${taskName[$i]}Dag"
          # Parent Child Dependency
          if [[ -n "$(RmSp $lastTask)" ]]; then #i.e. we had a task before
              printf "PARENT $lastTask CHILD $jobId\n\n" >> "$pipeStructFile"
          fi

          printf "SUBDAG EXTERNAL $jobId $jobsDir/${taskDag[$i]}\n" >>\
                 "$pipeStructFile"
          lastTask="$jobId" #save last executed task

      fi
  fi
done

# Delete tmp folder $jobsDir
#printf "#SCRIPT POST $lastTask $scriptsPath/postScript.sh $jobsDir \n" >> "$pipeStructFile"
# [End] Print the jobs section - Stages

# End of file
PrintfLine >> "$pipeStructFile"
printf "# [End]  Description of $pipeStructFile\n" >> "$pipeStructFile"
PrintfLine >> "$pipeStructFile"

echo "[End]  Creating $pipeStructFile"
EchoLineBoldSh

## Submit mainDAG.dag
if [[ "$isFT" = true ]]; then
    ErrMsg "0 jobs are queued by $curScrName"
else
  #condor_submit_dag -f $pipeStructFile
  echo "$pipeStructFile was submitted!"
  echo ""
fi

## End
echo "[End]  $curScrName"
EchoLineBold
exit 0









####### SOme usefull part

exit 1



integrTaskStage=($(MapStage "toTag")    $(MapStage "toTag")
                 $(MapStage "pseudo")   $(MapStage "idroverlap"))

# [Dev] Check that integrTaskStage set ok
if [ -n "$(ArrayGetInd 1 "-1" ${integrTaskStage[@]})" ]; then
    # ErrMsg "[dev] wrong input of taskStage"
    WarnMsg "[dev] wrong input of taskStage"
fi

exit 1
