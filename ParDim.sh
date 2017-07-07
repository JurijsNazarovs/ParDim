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
#      -argsFile     file with all arguments for this shell
#      -isSubmit     false - do not submit, but create everythig to test
# Possible arguments are described in a section: ## Default values
#===============================================================================
## Libraries/Input
shopt -s nullglob #allows create an empty array
homePath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" #cur. script locat.
scriptsPath="$homePath/scripts"
funcListPath="$scriptsPath"/funcListParDim.sh
source "$funcListPath"

curScrName="${0##*/}" #delete all before last backSlash
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

argsFile="${1:-$homePath/args.listDev}" #file w/ all arguments for this shell
isSubmit="${2:-true}"
argsFile="$(readlink -m "$argsFile")" #whole path
ChkExist f "$argsFile" "File with arguments for $curScrName: $argsFile\n"
ChkValArg "isSubmit" "" "false" "true"


## Detect structure of the pipeline

# Detect all possible labels of integrated tasks based on the patern:
# ##[    scrLab]## - Case sensetive. Might be spaces before, after and inside,
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
  if [[ "$i" = "$curScrName" ]]; then
      continue
  fi

  if [[ "$i" =~ ("+"|".") ]]; then
      ErrMsg "Task name $i
             cannot contain + or \".\"."
  fi

  execute=false
  ReadArgs "$argsFile" 1 "$i" 1 "execute" "execute" > /dev/null
  if [[ "$execute" = true ]]; then
      posArgs=(script map transFiles args relResPath)
      if [[ "$i" = "$downloadTaskName" ]]; then
          script="$scriptsPath/boostDownload.sh"
          map=single
      else
        script=""
        map=multi #if runs for every directory
      fi
      transFiles=""
      args="" #file with arguments (just one)
      relResPath="" #path for results relative to the part of pipeline
      ReadArgs "$argsFile" 1 "$i" ${#posArgs[@]} "${posArgs[@]}" "map"\
               > /dev/null

      # Checking existence of scripts
      script="$(readlink -m "$script")" #whole path
      ChkExist f "$script" "Script for $i: $script\n"
      if [[ "$curScrName" -ef "$script" ]]; then
          ErrMsg "$curScrName cannot be a script for $i,
              since it is the main pipeline script."
      fi

      # Checking args
      if [[ -z $(RmSp "$args") ]]; then
          args="${argsFile}"
      else
        args="$(readlink -m "$args")"
        ChkExist f "$args" "File with arguments for $i: $args\n"
      fi

      # Checking map
      ChkValArg "map" "Task $i:\n" "single" "multi"

      # Checking files to transfer"
      readarray -t transFiles <<<\
                "$(awk\
                   '{gsub(/,[[:space:]]*/, "\n"); print }' <<< "$transFiles"
                  )"
      for j in "${!transFiles[@]}"; do
        if [[ -n $(RmSp "${transFiles[$j]}") ]]; then
            #transFiles[$j]="$(readlink -m "${transFiles[$j]}")"
            if [[ "${transFiles[$j]:0:1}" != "/" ]]; then
                transFiles[$j]="$(dirname "$script")/${transFiles[$j]}"
            fi

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
      taskMap["$nTask"]="$map"
      taskArgsFile["$nTask"]="$args"
      taskRelResPath["$nTask"]="$relResPath"
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

# Checking relResPath
isDataPathInRelResPath=false #if relResPath = dataPath; to make a future check
for i in "${taskRelResPath[@]}"; do
  if [[ -n $(RmSp "$i") ]]; then
      if [[ "$i" = dataPath ]]; then
          isDataPathInRelResPath=true
          continue
      fi
      
      if [[ -z "$(ArrayGetInd 1 "$i" "${task[@]}")" ]]; then
          ErrMsg "relResPath: $i
                 is not among queued tasks:
                 $(JoinToStr ', ' "${task[@]}")"
      fi
  fi
done

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
posArgs=("dataPath" # path for data, which is not neccesary resPath
         "resPath" #resulted path for all tasks
         "jobsDir"  #tmp working directory for all files
         "selectJobsListPath" #path to table with jobs to execute. If empty,
                              #then all from dataPath
        )

jobsDir=$(mktemp -duq dagTmpXXXX)
selectJobsListPath=""
ReadArgs "$argsFile" 1 "$curScrName" "${#posArgs[@]}" "${posArgs[@]}"\
         > /dev/null

if [[ "$jobsDir" = "/tmp"* ]]; then
	WarnMsg "jobsDir = $jobsDir 
                Condor might not allowed to use /tmp.
                If pipeline fails, please change jobsDir."
fi
jobsDir="$(readlink -m "$jobsDir")"
dataPath="$(readlink -m "$dataPath")"

echo "Creating the temporary directory: $jobsDir"
mkdir -p "$jobsDir"
if [[ "$?" -ne 0 ]]; then
    ErrMsg "$jobsDir was not created."
else
  # Directory might exist
  ChkAvailToWrite "jobsDir"
fi


## Initial checking
# Chk/create selectJobsListPath and selectJobsListInfo
if [[ "${taskMap[0]}" != single ]]; then  
    if [[ -z $(RmSp "$selectJobsListPath") ]]; then
        if [[ -z $(RmSp "$dataPath") ]]; then
            ErrMsg "Please provide dataPath in $curScrName
                    to define directories for an analysis or
                    selectJobsListPath - list of analysed directories."
        fi
   
        selectJobsListPath="$(mktemp -qu "$jobsDir/"selectJobsList.XXXX)"
        ChkExist d "$dataPath" "dataPath: $dataPath"
        #ls -d "$dataPath/"*/ > "$selectJobsListPath"
        find "$dataPath/" -mindepth 1 -maxdepth 1 -type d \
             > "$selectJobsListPath"
    else
      ChkExist f "$selectJobsListPath"\
               "List of selected directories: $selectJobsListPath"
      while IFS='' read -r dirPath || [[ -n "$dirPath" ]]; do
        ChkExist d "$dirPath" "selectJobsListPath: directory $dirPath"
        strTmp=("${strTmp[@]}" "$(basename "$dirPath")")
      done < "$selectJobsListPath"
      
      # Chk duplicates of dirNames (basenames) in selectJobsListPath
      # to avoid overwriting on executed server
      readarray -t strTmp <<< "$(ArrayGetDupls "${strTmp[@]}")"
      if [[ -n "${strTmp[@]}" ]]; then
          ErrMsg "In selectJobsListPath: $selectJobsListPath
                  directories cannot have duplicate names.
                  Duplicate directories: $(JoinToStr ", " "${strTmp[@]}")"
      fi
      strTmp=() #delete values for future use
    fi
    selectJobsListInfo="$(mktemp -qu "$jobsDir/"selectJobsInfo.XXXX)"
fi
# Thus, if first task is single-mapping task, then
# selectJobsListPath and selectJobsListInfo are empty on this stage, but
# they are filled later, if there are more tasks.

isDownTask="$(ArrayGetInd 1 "$downloadTaskName" "${task[@]}")"
if [[ -n "$isDownTask" ]]; then
    isDownTask=true
else
  isDownTask=false
fi

if [[ "$isDownTask" = true || "$isDataPathInRelResPath" = true ]]; then
    if [[ -z $(RmSp "$dataPath") ]]; then
        ErrMsg "Please provide dataPath in $curScrName
                to write resutls."
    fi
    echo "Creating the data directory: $dataPath"
    mkdir -p "$dataPath"
    if [[ "$?" -ne 0 ]]; then
        ErrMsg "$dataPath was not created."
    else
      # Directory might exist
      ChkAvailToWrite "dataPath"
    fi
fi

if [[ -z $(RmSp "$resPath") ]]; then
    if [[ -z $(RmSp "$dataPath") ]]; then
        ErrMsg "Path for results resPath is empty.
               Please provide an available for writing directory."
    else
      resPath="$(dirname "$dataPath")"
      WarnMsg "Path for results resPath is empty.
               The parent directory of $dataPath is set."
    fi
fi
resPath="$(readlink -m "$resPath")"

echo "Creating the resulting directory: $resPath"
mkdir -p "$resPath"
if [[ "$?" -ne 0 ]]; then
    ErrMsg "$resPath was not created."
else
  ChkAvailToWrite "resPath"
fi


## Define corresponding DAG files and task path for results
for i in "${!task[@]}"; do
  taskDag[$i]="${task[$i]}.dag" #resulting .dag file. Name NOT path

  if [[ "${task[$i]}" = "$downloadTaskName" ||\
            "${taskRelResPath[$i]}" = dataPath ]]; then
      taskResPath[$i]="$dataPath"
  else
    if [[ -z $(RmSp "${taskRelResPath[$i]}") ]]; then
        taskResPath[$i]="$resPath/${task[i]}"
    else
      taskResPath[$i]="$resPath/${taskRelResPath[$i]}"
    fi
  fi
done


## Print pipeline structure
PrintArgs "$curScrName" "argsFile" "${posArgs[@]}"

maxLenStr=0
nZeros=${#task[@]} #number of zeros to make an order
nZeros=${#nZeros}
for i in "${task[@]}" "Files to Transfer" "Results";  do
  maxLenStr=$(Max $maxLenStr ${#i})
done

EchoLineBoldSh
echo "Pipeline structure in order:"
echo ""

for i in "${!task[@]}"; do
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

  # Results
  printf "%0${nZeros}s  %-$((maxLenStr + nZeros))s %s\n"\
         ""\
        "Results"\
        "${taskResPath[$i]}"
done
EchoLineBoldSh


## Condor map file - is used to execute one of mapping scripts to create
#  dag/splice/usual condor file.
#  Two mapping scripts:
#  -exeSingleMap - creates dag file based on some input
#  -exeMultiMap  - creares splice for every analysed directory
conMap="$jobsDir/makeDag.condor" 
conMapOutDir="$jobsDir/conOut"  #.err, .out, and .log
mkdir -p "$conMapOutDir"

# Args for condor job, corresponding to order of args in Map scripts
conMapArgs=("\$(taskScript)" #variable - script name executed by map.script
            "\$(argsFile)" #variable
            "\$(dagFile)" #variable - output dag file name: jobsDir/map/dagName
            "\$(resPath)" #variable - partially path for results for task[i]
            "true" #is script submit from executed machine
            "\$(selectJobsListInfo)" #single and multi map
            "\$(selectJobsListPath)" #multi map
           )
conMapArgs=$(JoinToStr "\' \'" "${conMapArgs[@]}")

# Transfer files
for i in "${!task[@]}"; do
  strTmp="$funcListPath, ${taskScript[i]}"  #scripts used in mapping scripts
  if [[ "${task[$i]}" = "$downloadTaskName" ]]; then
     strTmp="$strTmp, $scriptsPath/makeCon.sh"
  fi

  conMapTransFiles["$i"]="$strTmp, ${taskArgsFile[i]}"

  if [[ -n "${taskTransFiles[$i]}" ]]; then
      conMapTransFiles["$i"]="${conMapTransFiles[$i]}, ${taskTransFiles[$i]}"
  fi

  # Check transfer files have no duplicates in basenames,
  # to avoid overlapping on executed server
  readarray -t strTmp <<< "$(echo ${conMapTransFiles[$i]} | tr "," "\n")"
  for j in "${!strTmp[@]}"; do
    strTmp[$j]="$(basename "${strTmp[$j]}")"
  done

  readarray -t strTmp <<< "$(ArrayGetDupls "${strTmp[@]}")"
  if [[ -n "${strTmp[@]}" ]]; then
      ErrMsg "There are duplicates in basenames among transfering files.
             Possible overlapping with system files.
             Duplicates: $(JoinToStr ", " "${strTmp[@]}")"
  fi
  strTmp=() #delete values for future use
done

bash "$scriptsPath"/makeCon.sh "$conMap" "$conMapOutDir"\
     "\$(exeMap)" "$conMapArgs" "\$(conMapTransFiles)"\
     "1" "1" "1" "" "" "\$(conName)"
if [[ "$?" -ne 0 ]]; then
    ErrMsg "Cannot create a condor file: $conFile" "$?"
fi


## DAG description of a pipeline
pipeStructFile="$jobsDir/ParDim.main.dag"

# Print the head
PrintfLine > "$pipeStructFile"
printf "CONFIG $scriptsPath/dag.config\n" >> "$pipeStructFile"
PrintfLine >> "$pipeStructFile"

# Print the jobs section
isFT="true" #is the First Task
lastTask="" #last executed task for PARENT CHILD dependency
for i in "${!task[@]}"; do
  jobId="${task[$i]}"
  
  # Prescripts
  if [[ "${taskMap[$i]}" != single && -z $(RmSp "$lastTask") ]]; then
      # Create selectJobsListInfo
      printf "SCRIPT PRE $jobId \"$scriptsPath/postScript.sh\" "\
             >> "$pipeStructFile" 
      printf "pre.$jobId FillListOfContent "  >> "$pipeStructFile"
      printf "\"$selectJobsListPath\" \"$selectJobsListInfo\" \n\n"\
             >> "$pipeStructFile"
  fi

  # Parent-child dependency 
  if [[ -n $(RmSp "$lastTask") ]]; then
      printf "PARENT $lastTask CHILD $jobId\n" >> "$pipeStructFile"
      PrintfLineSh >> "$pipeStructFile"

      if [[ "$jobId" != "$downloadTaskName" ]]; then
          # Need to create 2 files: file with dirs and file with content of dirs
          selectJobsListPath="$(mktemp -qu "$jobsDir/"selectJobsList.$jobId.XXXX)"
          selectJobsListInfo="$(mktemp -qu "$jobsDir/"selectJobsInfo.$jobId.XXXX)"
          
          printf "SCRIPT PRE $jobId \"$scriptsPath/postScript.sh\" " \
                 >> "$pipeStructFile" 
          printf "pre.$jobId FillListOfDirsAndContent \"$resPathTmp\" " \
                 >> "$pipeStructFile"
          printf "\"$selectJobsListPath\"  \"$selectJobsListInfo\" \n\n" \
                 >> "$pipeStructFile"
          # resPathTmp is defined after task is executed. So, we have path for
          # results of a previous running job.
      fi
  fi

  # Transfered files
  if [[ "$jobId" != "$downloadTaskName" ]]; then
      conMapTransFiles["$i"]="${conMapTransFiles[$i]}, $selectJobsListInfo"
  fi
  if [[ "${taskMap[$i]}" != single ]]; then
      conMapTransFiles["$i"]="${conMapTransFiles[$i]}, $selectJobsListPath"
  fi

  # Print the condor job
  # conMap returns files back in jobsDir, using postscript. 
  # Meanwile I use some tmp directory inside of the exeMap.
  jobsDirTmp="$jobsDir/${taskMap[$i]}Map/${taskDag[$i]%.*}"
  mkdir -p "$jobsDirTmp"
  printf "JOB $jobId $conMap DIR $jobsDirTmp\n\n" >> "$pipeStructFile"
  
  # Variables for conMap
  printf "VARS $jobId exeMap=\"${taskMapScripts[${taskMap[$i]}]}\"\n"\
         >> "$pipeStructFile" #transfered automatically since it is an executable
  strTmp="${taskScript[$i]}"; strTmp="${strTmp##*/}" #from homepath in condor 
  printf "VARS $jobId taskScript=\"$strTmp\"\n"\
         >> "$pipeStructFile" #need to be transfered
  strTmp="${taskArgsFile[$i]}"; strTmp="${strTmp##*/}" #from homepath in condor 
  printf "VARS $jobId argsFile=\"$strTmp\"\n"\
         >> "$pipeStructFile" #need to be transfered
  
  printf "VARS $jobId dagFile=\"${taskDag[$i]}\"\n"\
         >> "$pipeStructFile" #just a name
  printf "VARS $jobId conMapTransFiles=\"${conMapTransFiles[$i]}\"\n"\
         >> "$pipeStructFile"
  printf "VARS $jobId conName=\"${taskMap[$i]}.$jobId.\"\n"\
         >> "$pipeStructFile"
  
  if [[ "$jobId" != "$downloadTaskName" ]]; then
      printf "VARS $jobId selectJobsListInfo=\"${selectJobsListInfo##*/}\"\n"\
             >> "$pipeStructFile"
  fi
  if [[ "${taskMap[$i]}" != single ]]; then
      printf "VARS $jobId selectJobsListPath=\"${selectJobsListPath##*/}\"\n"\
             >> "$pipeStructFile"
  fi

  # Path to return all results from jobs
  resPathTmp="${taskResPath[$i]}" #need to save, used in a next stage as input
  mkdir -p "$resPathTmp"
  if [[ $? -ne 0 ]]; then
      ErrMsg "Impossible to create $resPathTmp"
  fi

  printf "VARS $jobId resPath=\"$resPathTmp\"\n"\
         >> "$pipeStructFile" #just a name
  
  # Post Script to move dag files in right directories
  printf "\nSCRIPT POST $jobId \"$scriptsPath/postScript.sh\" "\
         >> "$pipeStructFile"
  printf "post.$jobId untarfiles \"${taskDag[$i]%.*}.tar.gz\"\n\n"\
         >> "$pipeStructFile"

  lastTask="${task[$i]}" #save last executed task
  
  # DAG part
  jobId="${task[$i]}Dag"
  printf "PARENT $lastTask CHILD $jobId\n" >> "$pipeStructFile"
  PrintfLineSh >> "$pipeStructFile"
  printf "SUBDAG EXTERNAL $jobId ${taskDag[$i]} DIR $jobsDirTmp\n" >>\
         "$pipeStructFile"
  printf "SCRIPT POST $jobId \"$scriptsPath/postScript.sh\" "\
         >> "$pipeStructFile"
  printf "post.$jobId untarfilesfromdir \"$resPathTmp\"\n\n"\
         >> "$pipeStructFile"
  lastTask="$jobId"
done

## Delete tmp folder $jobsDir
    #printf "#SCRIPT POST $lastTask $scriptsPath/postScript.sh $jobsDir \n"\
        #    >> "$pipeStructFile"
# [End] Print the jobs section - Stages

## Submit mainDAG.dag
if [[ "$isSubmit" = true ]]; then
    condor_submit_dag -f "$pipeStructFile" > /dev/null 2>&1
    EchoLineSh
    if [[ "$?" -eq 0 ]]; then
        echo "$pipeStructFile was submitted!"
    else
      ErrMsg "$pipeStructFile was not submitted!"
    fi
    EchoLineSh
else
  EchoLineSh
  echo "$pipeStructFile is ready for a test"
  EchoLineSh
fi

## End
echo "[End]  $curScrName"
EchoLineBold
exit 0
