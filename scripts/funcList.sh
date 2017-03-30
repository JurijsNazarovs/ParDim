#!/bin/bash
#========================================================
# File contains description of functions which are used in
# pipeDAG.sh, pipeDAGMaker.sh, pipeConMaker.sh, exeDAG.sh
#========================================================


## Different printing lines
echoLine(){
  echo "-------------------------------------------------------------------------------------"
}

echoLineSh(){
  echo "----------------------------------------"
}

echoLineBold(){
  echo "====================================================================================="
}

echoLineBoldSh(){
  echo "================================================================"
}

printfLine(){
  #printf "#"
  #printf -- "-%.0s" $(seq 1 85)
  #printf "\n"
  printf "#--------------------------------------------------------------------------------\n"
}

printfLineSh(){
  printf "#----------------------------------------\n"
}

printfLineBold(){
  printf "#================================================================================\n"
}

printfLineBoldSh(){
  printf "#==============================================\n"
}


## Base functions. Functions, which are included in other (void)

rmSp(){
  # Function returns the same line but without any spaces
  # Execution: $(rmSp "hui. t ebe"))
  echo "$1" | tr -d '\040\011\012\015'
}

warnMsg(){
  # Function displays an error message $1 and returns exit code $2
  # Use:  errMsg "Line1!
  #               Line2" 1
  # Function replace \n[\t]+ with \n, so, no tabs.
  # It is done to make code beautiful, so that in code I can put tabs.
  msg=${1:-"Default message about warning"}

  echoLineSh
  printf "Warning!\n"
  # Replace \n[\t]+ with \n
  sed -e ':a;N;$!ba;s/\n[ \t]\+/\n/g' <<<  "$msg"
  echoLineSh
}

errMsg(){
  # Function displays an error message $1 and returns exit code $2
  # Use:  errMsg "Line1!
  #               Line2" 1
  # Function replace \n[\t]+ with \n, so, no tabs.
  # It is done to make code beautiful, so that in code I can put tabs.
  local msg=${1:-"Default message about error"}
  local exFl=${2:-"1"} #default exit code

  echoLineSh >> /dev/stderr
  
  local strTmp="Error!\n$msg\n"
  # Replace \n[\t]+ with \n
  printf "$strTmp" | sed -e ':a;N;$!ba;s/\n[ \t]\+/\n/g' >> /dev/stderr
  
  echoLineSh >> /dev/stderr
  exit $exFl
}



## Status functions. Functions, which check some conditions (boolean)

chkEmptyArgs(){
  ## Function checks if any of arguments is empty.
  local argLab
  local arg
  
  for argLab in "$@"
  do
    eval arg='$'$argLab
    if [[ "$(rmSp $arg)" = "" ]]; then
        errMsg "Imput argument \"$argLab\" is empty"
    fi
  done
}

chkInp(){ #OLD
  # $1 - input type: d,f,etc
  # $2 - path to the folder, file, etc
  # $3 - label to show in case of error

  local inpLbl="$3"
  if [[ $(rmSp "$inpLbl") = "" ]]; then
      inpLbl="$2"
  fi

  if [[ $(rmSp "$2") = "" ]]; then
      errMsg "$3 is empty"
  else
    if [ ! -$1 "$2" ]; then 
        errMsg "$3 does not exist"
    fi
  fi
}

chkExist(){
  # $1 - input type: d,f,etc
  # $2 - path to the folder, file, etc
  # $3 - label to show in case of error
  if [[ $(rmSp "$2") = "" ]]; then
      errMsg "$3 is empty"
  else
    if [ ! -$1 "$2" ]; then 
        errMsg "$3 does not exist"
    fi
  fi
}

checkAvailToWrite(){ #OLD
  ## Function checks if it is possible to write in path $1
  local path=${1:-""}
  if [ "$(rmSp $path)" == "" ]; then
      errMsg "Input argument (path) is empty"
  fi

  local  out=$(mktemp -q "$path"/output.XXXXXXXXXX.) #try to create tmp file inside
  if [ "$(rmSp $out)" == "" ]; then
      errMsg "Impossible to write in $path"
  else
    rm -rf "$out" #delete what we created
  fi
}

chkAvailToWrite(){
  ## Function checks if it is possible to write in path $1
  chkEmptyArgs "$@"

  local pathLab
  local path
  local outFile
  for pathLab in "$@"; do
    eval path='$'$pathLab
    outFile=$(mktemp -q "$path"/outFile.XXXXXXXXXX.) #try to create file inside
    if [[ $(rmSp "$outFile") = "" ]]; then
        errMsg "Impossible to write in $path"
    else
      rm -rf "$outFile" #delete what we created
    fi
  done
}

checkUrl(){
  local string=$1
  local regex='^(https?|ftp|file)://'
  regex+='[-A-Za-z0-9\+&@#/%?=~_|!:,.;]*[-‌​A-Za-z0-9\+&@#/%=~_|‌​]$'
  if [[ $string =~ $regex ]]
  then 
      echo "true"
  else
    echo "false"
  fi
}

chkStages(){
  local fStage=$1
  local lStage=$2
  if [[ "$fStage" -eq -1 ]]; then
      errMsg "First stage is not supported." 
  fi

  if [[ "$lStage" -eq -1 ]]; then
      errMsg "Last stage is not supported."
  fi

  if [[ "$ftStage" -gt "$lStage" ]]; then 
      errMsg "First stage cannot be after the last stage."
  fi
}


## Mapping functions

mapStage(){
  # Function maps input to numbers for comparison purpose
  # Input is the stage
  case "$1" in
    "")             echo 0;;
    "download")     echo 1;;
    "toTagOriginal")        echo 2;;
    "pseudo")       echo 3;;
    "xcor")         echo 4;;
    "pool")         echo 5;;
    "stgMacs2")     echo 6;;
    "peaks")        echo 7;;
    "idroverlap")   echo 8;; #becasue search for a computer is about 3-5mins,
    #which is the time of idr
    *)              echo -1
  esac
}

joinToStr(){
  # Join all element of an array in one string
  # $1 is the splitting character
  # >$1 everything to combine
  # Using: joinToStr "\' \'" "$a" "$b" ... ("$a[@]")
  spC=$1
  shift

  args="$1"
  shift

  for i in "$@"
  do
    args="$args$spC$i"
  done

  echo "$args"    
}

getNumLines(){
  # Function returns number of lines in the file
  fileName=$1

  if [ "${fileName##*.}" = "gz" ]; then
      echo "$(zcat $fileName | wc -l)"
  else
    echo "$(cat $fileName | wc -l)"
  fi
}

max(){
  # Function returns the maximum element among the input
  # Input: max 1 2 3 4 5 Or max ${arr[@]}
  local res=$1
  shift 
  local i

  for i in $@
  do
    ((i > res)) && res="$i"
  done

  echo "$res"
}

min(){
  # Function returns the minimum element among the input
  # Input: min 1 2 3 4 5 Or min ${arr[@]}
  local res=$1
  shift
  local i

  for i in $@
  do
    ((i < res)) && res="$i"
  done

  echo "$res"
}

interInt(){
  # Function intersect 2 intervals
  # Is used to find inclussion of stages
  # output: 1-intersect, 0 -no
  
  if [ "$#" -ne 2 ]; then
      errMsg "Wrong input! Two intervals has to be provided and not $# value(s)"
  fi

  local a=($1) 
  local b=($2)
  
  if [[ ${#a[@]} -ne 2 || ${#b[@]} -ne 2 ]]; then
      errMsg "Wrong input! Intervals shoud have 2 finite boundaries"
  fi

  local aMinVal=$(min ${a[@]})
  local aMaxVal=$(max ${a[@]})
  local bMinVal=$(min ${b[@]})
  local bMaxVal=$(max ${b[@]})

  local maxMinVal=$(max $aMinVal $bMinVal)
  local minMaxVal=$(min $aMaxVal $bMaxVal)
  
  if [ $maxMinVal -le $minMaxVal ]; then
      echo 1
  else
    echo 0
  fi
  
}

getInd(){ 
  # Function return the index of $1, if element of array $2 equals exactly or contain $1
  # To search for containing, $1 should be provided with *, for example: peak*
  local sym=$1
  shift 
  local array=("$@")
  for i in "${!array[@]}"
  do
    if [[ "${array[$i]}" == $sym ]]; then
        printf "$i\n"
    fi
  done
}

delInd(){
  # Function returns an array $2 without the $1 index (just one, not many)
  local ind=$1 #index to delete
  shift
  local array=("$@")

  for ((i=0; i<${#array[@]}; i++))
  do
    if [ "$i" -ne "$ind" ]; then
        printf -- "${array[$i]}\n"
    fi
  done
}

readArgsOld(){
  # Function readArgs() read arguments from the file $1 and substitute values in the code
  # Example, in the file we have: foo     23
  # then in the code, where this file sourced and function readArgs is called
  # "echo $foo" returns 23.
  #
  # If the variable is defined before reading file, and in file it is empty,
  # then default value remains
  #
  # Input:
  #       -argsFile       file with arguments
  #       -posArgs        possible arguments to search for
  #
  # args.list has to be written in a way, that:
  #       first column = argumentName             second column = argumentValue
  #
  # Use: readArgs "$argsFile" "${posArgs[@]}"

  ## Prior parameters
  local argsFile="$1"
  chkInp "f" "$argsFile" "List of arguments"
  shift

  local posArgs=("$@")
  ## Read arguments and corresponding values
  i=0
  while read  firstCol restCol #do like that because there might be spaces in names
  do
    varsList[$i]="$firstCol" #all variables from the file
    valsList[$i]="$restCol" #all values of variables from the file
    ((i++))
  done < "$argsFile"

  for i in ${posArgs[@]}; do
    readarray -t ind <<< "$(getInd "$i" "${varsList[@]}")"
    ind=(${ind[0]}) #take just the first value
    if [ "$ind" ]; then #if index is not empty              
        eval "$i=${valsList[$ind]}" #use eval to define: parameter=value
        exFl=$?
        if [ $exFl -ne 0 ]; then
            errMsg "Cant read the parameter: $i=${valsList[$ind]}"
        fi
    fi
    # If index is empty, then no need to do anything, because
    # bash defines non-existing variable as empty.
    # Example: if [ $hui11221993 = "" ]; then echo "hui11221993 is empty"; fi
  done
}

readArgs(){
  # Function readArgs() read arguments from the file $1 according to
  # label ##[ scrLab ]## and substitute values in the code.
  # Example, in the file we have: foo     23
  # then in the code, where this file sourced and function readArgs is called
  # "echo $foo" returns 23.
  #
  # If the variable is defined before reading file, and in file it is empty,
  # then default value remains
  #
  # Input:
  #       -argsFile   file with arguments
  #       -scrLabNum  number of script labels
  #       -scrLabList vector of names of  script to search for arguments after
  #                   ##[ scrLab ]##. tolowerCase + no spaces are applied.
  #                   If scrLab = "", the whole file is searched for arguments,
  #                   and the last entry is selected.
  #       -posArgs    possible arguments to search for
  #
  # args.list has to be written in a way:
  #      argumentName(no spaces) argumentValue(spaces, tabs, any sumbols)
  # That is after first column space has to be provided
  #
  # Use: readArgs "$argsFile" "$scrLabNum" "${scrLabList[@]}" "${posArgs[@]}"

  ## Input
  local argsFile="$1"
  chkInp "f" "$argsFile" "List of arguments"
  shift

  local scrLabNum=${1:-"0"} #0-read whole file
  shift

  local scrLabList
  if [[ $scrLabNum -eq 0 ]]; then
      scrLabList=""
  else
    while (( scrLabNum -- > 0 )) ; do
      scrLab=$(echo "$1" | tr '[:upper:]' '[:lower:]')
      scrLabNoSp=$(rmSp "$scrLab")
      if [[ ${#scrLab} -ne ${#scrLabNoSp} ]]; then
          errMsg "Impossible to read arguments for \"$scrLab\".
               Remove spaces: \"$scrLab\" ----> \"$scrLabNoSp\""
      fi

      scrLabList+=( "$scrLab" )
      shift
    done
  fi

  local posArgs=("$@")
  for scrLab in "${scrLabList[@]}"; do
    
    ## Read arguments and corresponding values
    local rawStart="" #will read argFile from here
    local rawEnd="" #until here

    if [[ -n "$scrLab" ]]; then
        readarray -t rawStart <<<\
                  "$(awk -v pattern="^(##)\\\[$scrLab\\\](##)$"\
                   '{
                     gsub (" ", "", $0); #delete spaces
                     if (tolower($0) ~ pattern){
                        print (NR + 1)
                     }
                    }' < "$argsFile"
                 )"
        
        if [[ ${#rawStart[@]} -gt 1 ]]; then
            rawStart=("$(joinToStr ", " "${rawStart[@]}")")
            errMsg "Impossible to detect arguments for $scrLab in $argsFile.
                  Label: ##[ $scrLab ]## appears several times.
                  Lines: $rawStart"
        fi

        if [[ -n "$rawStart" ]]; then
            readarray -t rawEnd <<<\
                      "$(awk -v rawStart="$rawStart"\
                       '{ 
                         if (NR < rawStart) {next}
 
                         gsub (" ", "", $0);
                         if (tolower($0) ~ /^(##)\[.*\](##)$/){
                          print (NR - 1)
                         }
                        }' < "$argsFile"
                     )"
            rawEnd="${rawEnd[0]}"
        else
          readarray -t rawEnd <<<\
                    "$(awk\
                      '{
                        origLine = $0
                        gsub (" ", "", $0);
                        if (tolower($0) ~ /^(##)\[.*\](##)$/){
                           print origLine
                        }
                       }' < "$argsFile"
                     )"
          
          if [[ -n "$rawEnd" ]]; then
              errMsg "Can't find label: ##[ $scrLab ]## in $argsFile, while
                    other labels exist, line: $rawEnd"
          fi
        fi
        
    fi

    if [[ -z "$rawStart" ]]; then
        rawStart=1
    fi

    if [[ -z "$rawEnd" ]]; then
        rawEnd=$(awk 'END{print NR}' < "$argsFile")
    fi

    if [[ "$rawStart" -gt "$rawEnd" ]]; then
        errMsg "No arguments after ##[ $scrLab ]## in $argsFile!"
    fi

    echoLineSh
    if [[ -n "$scrLab" ]]; then
        echo "Reading arguments in \"$scrLab\" section from \"$argsFile\""
    else
      echo "Reading arguments from \"$argsFile\""
    fi
    echo "Starting line: $rawStart"
    echo "Ending line: $rawEnd"
    echoLineSh
    
    declare -A varsList #map - array, local by default
    
    # Read files between rawStart and rawEnd lines, skipping empty raws
    declare -A nRepVars #number of repetiotions of argument
    while read -r firstCol restCol #because there might be spaces in names
    do
      ((nRepVars[$firstCol]++))
      varsList["$firstCol"]="$(sed -e "s#[\"$]#\\\&#g" <<< "$restCol")"
    done <<< "$(awk -v rawStart=$rawStart -v rawEnd=$rawEnd\
              'NF > 0 && NR >= rawStart; NR == rawEnd {exit}'\
              "$argsFile")" 
    local i
    
    for i in ${!nRepVars[@]}; do
     if [[ ${nRepVars[$i]} -gt 1 ]]; then
         warnMsg "Argument $i is repeated ${nRepVars[$i]} times.
                  Last value $i = ${varsList[$i]} is recorded."
     fi
    done

    # Assign variables
    for i in ${posArgs[@]}; do
      if [[ -n $(rmSp "${varsList[$i]}") ]]; then
          eval $i='${varsList[$i]}' #define: parameter=value
          exFl=$?
          if [ $exFl -ne 0 ]; then
              errMsg "Cannot read the parameter: $i=${valsList[$ind]}"
          fi
      fi
    done
  done
}

printArgs(){
  ## Print arguments for the "current" script
  ## Use: printArgs "$scriptName" "${posArgs[@]}"
  local curScrName=$1
  shift 

  local posArgs=("$@")
  local maxLenArg=() #detect maximum argument length

  for i in ${!posArgs[@]};  do
    maxLenArg=(${maxLenArg[@]} ${#posArgs[$i]})
  done
  maxLenArg=$(max ${maxLenArg[@]})

  ## Print
  echoLineSh
  if [[ -n "$(rmSp $curScrName)" ]]; then
      echo "Arguments for $curScrName:"
  else
    echo "Arguments"
  fi
  echoLineSh
  
  local i
  for i in ${posArgs[@]}
  do
    eval "printf \"%-$((maxLenArg + 10))s %s \n\"\
                 \"- $i\" \"$"$i"\" "
  done
  echoLineSh
}

mk_dir(){ #Delete. 
  # Function is alias to real mkdir -p, but which proceeds an exit flag in a
  # right way.

  local dirName=$1
  if [[ -z "$(rmSp $dirName)" ]]; then
      errMsg "Input is empty"
  fi

  mkdir -p "$dirName"
  exFl=$?
  if [ $exFl = 0 ]; then
      echo "$dirName is created"
  else
    errMsg "Error: $dirName not created"
  fi
}
