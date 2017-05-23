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
#curScrName=${curScrName%.*} #delete extension
downloadTaskName="Download" #several parts of the code depend on the name of
#a task with downloading script
declare -A taskMapScripts
taskMapScripts["single"]="$scriptsPath/exeSingleMap.sh"
taskMapScripts["multi"]="$scriptsPath/exeMultiMap.sh"

for i in "${taskMapScripts[@]}"; do
  ChkExist f "$i" "Mapping script $i\n"
done

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
      map=multi #if runs for every directory
      ReadArgs "$argsFile" 1 "$i" 3 "script" "map" "transFiles"\
               "map" > /dev/null

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
      if [[ "$map" != single && "$map" != multi ]]; then
          ErrMsg "Task $i:
                 The value of map = $map is not recognised.
                 Please, check the value."
      fi
      taskMap["$nTask"]="$map"
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
selectJobsListPath=""
ReadArgs "$argsFile" 1 "$curScrName" "${#posArgs[@]}" "${posArgs[@]}" >/dev/null

echo "Creating temporary folder:  $jobsDir ..."
mkdir -p "$jobsDir"


## Initial checking
if [[ -n "$(ArrayGetInd 1 "$downloadTaskName" "${task[@]}")" ]]; then
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

## Define corresponding DAG files
for i in "${task[@]}"; do
  taskDag=("${taskDag[@]}" "$i.dag") #resulting .dag file. Name NOT path
done


## Print pipeline structure
PrintArgs "$curScrName" "argsFile" "${posArgs[@]}"

maxLenStr=0
nZeros=${#task[@]} #number of zeros to make an order
nZeros=${#nZeros}
for i in "${task[@]}" "Files to Transfer";  do
  maxLenStr=$(Max $maxLenStr ${#i})
done

EchoLineBoldSh
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
      strTmp=() #delete values for future use
  fi

done
EchoLineSh

## Condor map file - is used to execute one of mapping scripts to create
#  dag/splice/usual condor file.
#  Two mapping scripts:
#  -exeSingleMap - creates dag file based on some input
#  -exeMultiMap  - creares splice for every analysed directory
conMap="$homePath/$jobsDir/makeDag.condor" 
conMapOutDir="$homePath/$jobsDir/conOut"  #.err, .out, and .log
mkdir -p "$conMapOutDir"

# Args for condor job, corresponding to order of args in exeMultiDag.sh
conMapArgs=("\$(taskScript)"  #variable - script name executed by map.script
            "${argsFile##*/}"
            "\$(dagName)" #variable - output dag file name
            "$jobsDir"
            "${selectJobsListPath##*/}" #send file name anyway regardless
            #a mapping script, and just do not execute in exeSingleMap
           )
conMapArgs=$(JoinToStr "\' \'" "${argsCon[@]}")

for i in "${!task[@]}"; do
  strTmp="$scriptsPath/funcList.sh, \$(taskScript)" #scripts used in
  #mapping scripts
  conMapTransFiles["$i"]="$strTmp, $homePath/$argsFile"
  
  if [[ "${taskMap[$i]}" = multi ]]; then
      conMapTransFiles["$i"]="${conMapTransFiles[$i]}, $selectJobsListPath"
  fi

  if [[ -n "${taskTransFiles[$i]}" ]]; then
      conMapTransFiles["$i"]="${conMapTransFiles[$i]}, ${taskTransFiles[$i]}"
  fi
done

bash "$scriptsPath"/makeCon.sh "$conMap" "$conMapOutDir"\
     "\$(exeMap)" "$conMapArgs" "$conMapTransFiles"\
     "1" "1" "1"
if [[ "$?" -ne 0 ]]; then
    exit "$?"
fi


## DAG description of a pipeline
pipeStructFile="$jobsDir/pipelineMain.dag"

EchoLineBoldSh
echo "[Start] Creating $pipeStructFile"

# Print the head
PrintfLine > "$pipeStructFile"
printf "CONFIG $scriptsPath/dag.config\n" >> "$pipeStructFile"
PrintfLine >> "$pipeStructFile"

# Print the jobs section
isFT="true" #is the First Task
lastTask="" #last executed task for PARENT CHILD dependency
for i in "${!task[@]}"
do
  jobId="${task[$i]}"
  
  # Parent Child Dependency 
  if [[ -n $(RmSp "$lastTask") ]]; then
      printf "PARENT $lastTask CHILD $jobId\n" >> "$pipeStructFile"
      PrintfLineSh >> "$pipeStructFile"
  fi
  
  # Create list of analysed directories after download
  if [[ "$lastTask" = "${downloadTaskName}Dag" ]]; then
      printf "SCRIPT PRE $jobId $scriptsPath/postScript.sh " >>\
             "$pipeStructFile" 
      printf "$selectJobsListPath jobsList $dataPath \n\n" >>\
             "$pipeStructFile"
  fi

  # Print the condor job
  # conMap returns files back in jobsDir, using postscript. 
  # Meanwile i use some tmp directory inside of the exeMap.
  printf "JOB $jobId $conMap DIR $jobsDir\n" >> "$pipeStructFile"
  
  # Variables for conMap
  printf "VARS $jobId dagScript=\"${taskScript[$i]}\"\n" >>\
         "$pipeStructFile" #need to be transfered
  printf "VARS $jobId dagName=\"${taskDag[$i]}\"\n" >>\
         "$pipeStructFile" #just a name
  printf "VARS $jobId exeMap=\"${taskMapScripts[${taskMap[$i]}]}\"\n" >>\
           "$pipeStructFile"

  # Post Script to move dag files in right directories
  printf "SCRIPT POST $jobId $scriptsPath/postScript.sh " >>\
         "$pipeStructFile"
  printf "${taskDag[$i]%.*}.tar.gz tar\n" >> "$pipeStructFile"

  lastTask="${task[$i]}" #save last executed task

  # DAG part
  jobId="${task[$i]}Dag"
  printf "PARENT $lastTask CHILD $jobId\n\n" >> "$pipeStructFile"
  printf "SUBDAG EXTERNAL $jobId $jobsDir/${taskDag[$i]}\n" >>\
         "$pipeStructFile"
  lastTask="$jobId"
done

# Delete tmp folder $jobsDir
#printf "#SCRIPT POST $lastTask $scriptsPath/postScript.sh $jobsDir \n" >> "$pipeStructFile"
# [End] Print the jobs section - Stages

## Submit mainDAG.dag

#condor_submit_dag -f $pipeStructFile
EchoLineSh
if [[ "$?" -eq 0 ]]; then
    echo "$pipeStructFile was submitted!"
else
  ErrMsg "$pipeStructFile was not submitted!"
fi
EchoLineSh

echo "[End] Creating $pipeStructFile"
EchoLineBoldSh

## End
echo "[End]  $curScrName"
EchoLineBold
exit 0
