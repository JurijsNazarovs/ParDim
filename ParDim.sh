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
source "$scriptsPath"/funcList.sh
echo "$homePath"
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

EchoLineSh
printf "%-35s %s\n"\
        "The location of $curScrName:"\
        "$homePath"
printf "%-35s %s\n"\
        "The $curScrName is executed from:"\
        "$PWD"
EchoLineSh

argsFile=${1:-"$homePath/args.listDev2"} #file w/ all arguments for this shell
isSubmit=${2:-"true"}
argsFile="$(readlink -m "$argsFile")" #whole path
ChkExist f "$argsFile" "File with arguments for $curScrName: $argsFile\n"
ChkValArg "isSubmit" "" "false" "true"


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
      map=multi #if runs for every directory
      transFiles=""
      args="" #file with arguments (just one)
      ReadArgs "$argsFile" 1 "$i" 4 "script" "map" "transFiles" "args"\
               "map" > /dev/null

      # Checking existence of scripts
      script="$(readlink -m "$script")" #whole path
      ChkExist f "$script" "Script for $i: $script\n"
      if [[ "$curScrName" -ef "$script" ]]; then
          ErrMsg "$curScrName cannot be a script for $i,
              since it is the main pipeline script."
      fi

      # Checking map
      ChkValArg "map" "Task $i:\n" "single" "multi"

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
     
      # Checking args
      if [[ -z $(RmSp "$args") ]]; then
          args="${argsFile}"
      else
        args="$(readlink -m "$args")"
        ChkExist f "$args" "File with arguments for $i: $args\n"
      fi
      
      # Assigning values to the corresponding script
      task["$nTask"]="$i"
      taskScript["$nTask"]="$script"
      taskMap["$nTask"]="$map"
      taskArgsFile["$nTask"]="$args"
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
posArgs=("dataPath" # path for data, which is not neccesary resPath
         "resPath" #resulted path for all tasks
         "jobsDir"  #tmp working directory for all files
         "selectJobsListPath" #path to table with jobs to execute. If empty,
                              #then all from dataPath
        )

jobsDir=$(mktemp -duq dagTestXXXX)
selectJobsListPath=""
ReadArgs "$argsFile" 1 "$curScrName" "${#posArgs[@]}" "${posArgs[@]}"\
         > /dev/null

if [[ "$jobsDir" = "/tmp"* ]]; then
	WarnMsg "jobsDir = $jobsDir 
                Condor might not allowed to use /tmp.
                If pipeline fails, please change jobsDir"
fi
jobsDir="$(readlink -m "$jobsDir")"

echo "Creating the temporary directory:  $jobsDir"
mkdir -p "$jobsDir"
if [[ "$?" -ne 0 ]]; then
    ErrMsg "$jobsDir was not created."
else
  # Directory might exist
  ChkAvailToWrite "jobsDir"
fi


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

        selectJobsListPath="$(mktemp -qu "$homePath/$jobsDir/"selectJobs.XXXX)"
        if [[ "$isDownTask" = false ]]; then
            # No downloading => fill file
            ChkExist d "$dataPath" "dataPath: $dataPath"
            ls -d "$dataPath/"* > "$selectJobsListPath" 
        else
          # Probably have to delete, since I provide path
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
# Thus, if we have just download, then selectJobsListPath is empty

if [[ "$isDownTask" = true ]]; then
    echo "Creating the data directory:  $dataPath"
    mkdir -p "$dataPath"
    if [[ "$?" -ne 0 ]]; then
        ErrMsg "$dataPath was not created."
    else
      # Directory might exist
      ChkAvailToWrite "dataPath"
    fi
fi

if [[ -z $(RmSp "$resPath") ]]; then
    if [[ -z $(RmSp "dataPath") ]]; then
        ErrMsg "Path for results resPath is empty.
               Please provide an available for writing directory."
    else
      resPath="${dataPath%/*}"
      WarnMsg "Path for results resPath is empty.
               The parent directory of $dataPath is set."
    fi
fi
resPath="$(readlink -m "$resPath")"
ChkAvailToWrite "resPath"


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
conMap="$jobsDir/makeDag.condor" 
conMapOutDir="$jobsDir/conOut"  #.err, .out, and .log
mkdir -p "$conMapOutDir"

# Args for condor job, corresponding to order of args in Map scripts
conMapArgs=("\$(taskScript)" #variable - script name executed by map.script
            "\$(argsFile)" #variable
            "\$(dagFile)" #variable - output dag file name: jobsDir/map/dagName
            "\$(resPath)" #variable - partially path for results for task[i]
            "${selectJobsListPath##*/}" #send file name anyway regardless
            #a mapping script, and just do not execute in exeSingleMap
           )

conMapArgs=$(JoinToStr "\' \'" "${conMapArgs[@]}")

# Transfer files
for i in "${!task[@]}"; do
  # Scripts used in mapping scripts
  strTmp="$scriptsPath/funcList.sh, $scriptsPath/makeCon.sh, \
         ${taskScript[i]}"
  conMapTransFiles["$i"]="$strTmp, ${taskArgsFile[i]}"
  
  if [[ "${taskMap[$i]}" = multi ]]; then
      conMapTransFiles["$i"]="${conMapTransFiles[$i]}, $selectJobsListPath"
  fi

  if [[ -n "${taskTransFiles[$i]}" ]]; then
      conMapTransFiles["$i"]="${conMapTransFiles[$i]}, ${taskTransFiles[$i]}"
  fi
done

bash "$scriptsPath"/makeCon.sh "$conMap" "$conMapOutDir"\
     "\$(exeMap)" "$conMapArgs" "\$(conMapTransFiles)"\
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
      printf "FillListOfDirs $selectJobsListPath $dataPath \n\n" >>\
             "$pipeStructFile"
  fi

  # Print the condor job
  # conMap returns files back in jobsDir, using postscript. 
  # Meanwile i use some tmp directory inside of the exeMap.
  jobsDirTmp="$jobsDir/${taskMap[$i]}Map"
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
  printf "VARS $jobId dagFile=\"$jobsDirTmp/${taskDag[$i]}\"\n"\
         >> "$pipeStructFile" #just a name
  printf "VARS $jobId conMapTransFiles=\"${conMapTransFiles[$i]}\"\n"\
         >> "$pipeStructFile"
  printf "\n" >> "$pipeStructFile"

  # Path to return all results from jobs
  if [[ "$jobId" = "$downloadTaskName" ]]; then
      resPathTmp="$dataPath"
  else
    resPathTmp="$resPath/$jobId"
  fi
  printf "VARS $jobId resPath=\"$resPathTmp\"\n"\
         >> "$pipeStructFile" #just a name
  
  # Post Script to move dag files in right directories
  printf "SCRIPT POST $jobId $scriptsPath/postScript.sh "\
         >> "$pipeStructFile"
  printf "untarfiles ${taskDag[$i]%.*}.tar.gz\n\n" >> "$pipeStructFile"

  lastTask="${task[$i]}" #save last executed task
  
  # DAG part
  jobId="${task[$i]}Dag"
  printf "PARENT $lastTask CHILD $jobId\n" >> "$pipeStructFile"
  PrintfLineSh >> "$pipeStructFile"
  printf "SUBDAG EXTERNAL $jobId $jobsDirTmp/${taskDag[$i]}\n" >>\
         "$pipeStructFile"
   printf "SCRIPT POST $jobId $scriptsPath/postScript.sh "\
         >> "$pipeStructFile"
  printf "untarfilesfromdir $resPathTmp\n\n" >> "$pipeStructFile"
  lastTask="$jobId"
done

## Delete tmp folder $jobsDir
#printf "#SCRIPT POST $lastTask $scriptsPath/postScript.sh $jobsDir \n" >> "$pipeStructFile"
# [End] Print the jobs section - Stages

## Submit mainDAG.dag
if [[ "$isSubmit" = true ]]; then
    condor_submit_dag -f "$pipeStructFile"
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

echo "[End] Creating $pipeStructFile"
EchoLineBoldSh

## End
echo "[End]  $curScrName"
EchoLineBold
exit 0
