#!/bin/bash
#========================================================
# File contains description of functions which are used in
# pipeDAG.sh, pipeDAGMaker.sh, pipeConMaker.sh, exeDAG.sh
#========================================================


## Different printing lines
EchoLine(){
  echo "-------------------------------------------------------------------------------------"
}

EchoLineSh(){
  echo "----------------------------------------"
}

EchoLineBold(){
  echo "====================================================================================="
}

EchoLineBoldSh(){
  echo "========================================"
}

PrintfLine(){
  #printf "#"
  #printf -- "-%.0s" $(seq 1 85)
  #printf "\n"
  printf "#--------------------------------------------------------------------------------\n"
}

PrintfLineSh(){
  printf "#----------------------------------------\n"
}

PrintfLineBold(){
  printf "#================================================================================\n"
}

PrintfLineBoldSh(){
  printf "#========================================\n"
}


## Base functions. Functions, which are included in other (void)

RmSp(){
  # Function returns the same line but without any spaces
  # Execution: $(RmSp "hui. t ebe"))
  echo "$1" | tr -d '\040\011\012\015'
}

WarnMsg(){
  # Function displays an error message $1 and returns exit code $2
  # Use:  errMsg "Line1!
  #               Line2" 1
  # Function replace \n[\t]+ with \n, so, no tabs.
  # It is done to make code beautiful, so that in code I can put tabs.
  msg=${1:-"Default message about warning"}

  echo "*******************************************"
  #EchoLineSh
  printf "WARNING!\n"
  # Replace \n[\t]+ with \n
  sed -e ':a;N;$!ba;s/\n[ \t]\+/\n/g' <<<  "$msg"
  echo "*******************************************"
  #EchoLineSh
  #echo "-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-"
}

ErrMsg(){
  # Function displays an error message $1 and returns exit code $2
  # Use:  ErrMsg "Line1!
  #               Line2" 1
  # Function replace \n[\t]+ with \n, so, no tabs.
  # It is done to make code beautiful, so that in code I can put tabs.
  local msg=${1:-"Default message about error"}
  local exFl=${2:-"1"} #default exit code

  EchoLineBoldSh >> /dev/stderr
  
  local strTmp="ERROR!\n$msg\n"
  # Replace \n[\t]+ with \n
  printf "$strTmp" | sed -e ':a;N;$!ba;s/\n[ \t]\+/\n/g' >> /dev/stderr
  
  EchoLineBoldSh >> /dev/stderr
  exit $exFl
}


## Status functions. Functions, which check some conditions (boolean)

ChkEmptyArgs(){
  ## Function checks if any of arguments is empty.
  local argLab
  local arg
  
  for argLab in "$@"
  do
    eval arg='$'$argLab
    if [[ -z $(RmSp "$arg") ]]; then
        ErrMsg "Input argument \"$argLab\" is empty"
    fi
  done
}

ChkExist(){
  # $1 - input type: d,f,etc
  # $2 - path to the folder, file, etc
  # $3 - label to show in case of error

  local inpLbl="$3"
  if [[ -z $(RmSp "$inpLbl") ]]; then
      inpLbl="$2"
  fi

  if [[ -z $(RmSp "$2") ]]; then
      ErrMsg "$3 is empty"
  else
    if [ ! -$1 "$2" ]; then 
        ErrMsg "$3 does not exist"
    fi
  fi
}

ChkAvailToWrite(){
  ## Function checks if it is possible to write in path $1
  ChkEmptyArgs "$@"

  local pathLab
  local path
  local outFile
  for pathLab in "$@"; do
    eval path='$'$pathLab
    outFile=$(mktemp -q "$path"/outFile.XXXXXXXXXX.) #try to create file inside
    if [[ -z $(RmSp "$outFile") ]]; then
        ErrMsg "Impossible to write in $path"
    else
      rm -rf "$outFile" #delete what we created
    fi
  done
}

ChkUrl(){
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

ChkStages(){
  local fStage=$1
  local lStage=$2
  if [[ "$fStage" -eq -1 ]]; then
      ErrMsg "First stage is not supported." 
  fi

  if [[ "$lStage" -eq -1 ]]; then
      ErrMsg "Last stage is not supported."
  fi

  if [[ "$ftStage" -gt "$lStage" ]]; then 
      ErrMsg "First stage cannot be after the last stage."
  fi
}


## Mapping functions

MapStage(){
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

JoinToStr(){
  # Join all element of an array in one string
  # $1 is the splitting character
  # >$1 everything to combine
  # Using: JoinToStr "\' \'" "$a" "$b" ... ("$a[@]")
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

GetNumLines(){
  # Function returns number of lines in the file
  fileName=$1

  if [ "${fileName##*.}" = "gz" ]; then
      echo "$(zcat $fileName | wc -l)"
  else
    echo "$(cat $fileName | wc -l)"
  fi
}

Max(){
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

Min(){
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

InterInt(){
  # Function intersect 2 intervals
  # Is used to find inclussion of stages
  # output: 1-intersect, 0 -no
  
  if [ "$#" -ne 2 ]; then
      ErrMsg "Wrong input! Two intervals has to be provided and not $# value(s)"
  fi

  local a=($1) 
  local b=($2)
  
  if [[ ${#a[@]} -ne 2 || ${#b[@]} -ne 2 ]]; then
      ErrMsg "Wrong input! Intervals shoud have 2 finite boundaries"
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

GetIndArray(){ 
  # Function return the index of $2, if element of array $3-... equals exactly
  # or contain $1. To search for containing, $1 should be provided with *.
  # For example: peak*
  # Input: size of "elements to find", elements, array
  # Output: array of indecies 
  # Use: readarray -t ind <<<\
  #               "$(GetIndArray "{#elem[@]}" "${elem[@]}" "${varsList[@]}")"

  local nElem=${1:-""}
  shift
  local elem
  local tmp
  while (( nElem -- > 0 )) ; do
    tmp="$1"
    elem+=( "$tmp" )
    shift
  done
  local array=("$@")

  local i
  local j
  for i in "${elem[@]}"; do
    for j in "${!array[@]}";  do
      if [[ "${array[$j]}" == $i ]]; then
          printf "$j\n"
      fi
    done
  done
}

DelIndArray(){
  # Function returns an array $3-... without the indecies $2 - array
  # Output: array without indecies
  # Use: readarray -t varsList <<<\
  #       "$(DelIndArray "${#scrInd[@]}" "${scrInd[@]}" "${varsList[@]}")"

  local nIndDel=${1:-""}
  shift
  local indDel
  local tmp
  while (( nIndDel -- > 0 )) ; do
    tmp="$1"
    indDel+=( "$tmp" )
    shift
  done
  local array=("$@")

  local ind=($(echo "${indDel[@]}" "${!array[@]}" |
                   tr " " "\n" |
                   sort |
                   uniq -u))
  local i
  for i in "${ind[@]}"; do
    printf -- "${array[$i]}\n"
  done
}

DelElemArray(){
  # Function returns an array $3,... without the elements $2 - array
  # Output: array without deleted elements
  # Use:readarray -t arrayNoElem <<<\
  #              "$(DelElemArray "{#elem[@]}" "${elem[@]}" "${varsList[@]}")
  local nElem=${1:-""}
  shift
  local elem
  local tmp
  while (( nElem -- > 0 )) ; do
    tmp="$1"
    elem+=( "$tmp" )
    shift
  done
  local array=("$@")

  readarray -t indToDel <<<\
            "$(GetIndArray "${#elem[@]}" "${elem[@]}" "${array[@]}")"
  readarray -t arrayNoElem <<<\
            "$(DelIndArray "${#indToDel[@]}" "${indToDel[@]}" "${array[@]}")"
  for i in ${arrayNoElem[@]}; do
    printf -- "$i\n"
  done
}

ReadArgs(){
  # Function ReadArgs() read arguments from the file $1 according to
  # label ##[ scrLab ]## and substitute values in the code.
  # Example, in the file we have: foo     23
  # then in the code, where this file sourced and function ReadArgs is called
  # "echo $foo" returns 23.
  #
  # If the variable is defined before reading file, and in file it is empty,
  # then default value remains
  #
  # Input:
  #       -argsFile   file with arguments
  #       -scrLabNum  number of script labels
  #       -scrLabList vector of name of scripts to search for arguments after
  #                   ##[ scrLab ]##. Case sensetive. Spaces are not important.
  #                   If scrLab = "", the whole file is searched for arguments,
  #                   and the last entry is selected.
  #       -posArgNum  number of arguments to read
  #       -posArgList possible arguments to search for
  #       -reservArg  reserved argument which can't be duplicated
  #       -isSkipLab  true = no error for missed labels
  #
  # args.list has to be written in a way:
  #      argumentName(no spaces) argumentValue(spaces, tabs, any sumbols)
  # That is after first column space has to be provided
  #
  # Use: ReadArgs "$argsFile" "$scrLabNum" "${scrLabList[@]}" "${posArgs[@]}"

  ## Input
  local argsFile="$1"
  ChkExist "f" "$argsFile" "File with arguments"
  shift

  # Get list of labels to read
  local scrLabNum=${1:-"0"} #0-read whole file
  shift

  local scrLabList
  local scrLab
  if [[ $scrLabNum -eq 0 ]]; then
      scrLabList=""
  else
    while (( scrLabNum -- > 0 )) ; do
      #scrLab=$(echo "$1" | tr '[:upper:]' '[:lower:]')
      scrLab="$1"
      if [[ $(RmSp "$scrLab") != "$scrLab" ]]; then
          ErrMsg "Impossible to read arguments for \"$scrLab\".
                  Remove spaces: $scrLab"
      fi

      scrLabList+=( "$scrLab" )
      shift
    done
  fi

  # Get list of arguments to read
  local posArgNum=${1:-"0"} 
  shift
  if [[ $posArgNum -eq 0 ]]; then
      ErrMsg "No arguments to read from $argsFile"
  fi

  local posArgList
  local posArg
  if [[ $posArgNum -eq 0 ]]; then
      posArgList=""
  else
    while (( posArgNum -- > 0 )) ; do
      posArg="$1"
      if [[ $(RmSp "$posArg") != "$posArg" ]]; then
          ErrMsg "Possible argument cannot have spaces: $posArg"
      fi

      posArgList+=( "$posArg" )
      shift
    done
  fi

  # Other inputs
  local reservArg=${1:-""}
  shift

  local isSkipLab=${1:-"false"}
  shift

  if [[ "$isSkipLab" != true && "$isSkipLab" != false ]]; then
      WarnMsg "The value of isSkipLab = $isSkipLab is not recognised.
               Value false is assigned"
  fi


  # Detect start and end positions to read between and read arguments
  for scrLab in "${scrLabList[@]}"; do
    local rawStart="" #will read argFile from here
    local rawEnd="" #until here

    if [[ -n "$scrLab" ]]; then
        readarray -t rawStart <<<\
                  "$(awk -v pattern="^##\\\[$scrLab\\\]##$"\
                   '{
                     gsub (" ", "", $0) #delete spaces
                     if ($0 ~ pattern){
                        print (NR + 1)
                     }
                    }' < "$argsFile"
                 )"
        
        if [[ ${#rawStart[@]} -gt 1 ]]; then
            rawStart=("$(JoinToStr ", " "${rawStart[@]}")")
            ErrMsg "Impossible to detect arguments for $scrLab in $argsFile.
                   Label: ##[ $scrLab ]## appears several times.
                   Lines: $rawStart"
        fi

        if [[ -n "$rawStart" ]]; then
            readarray -t rawEnd <<<\
                      "$(awk -v rawStart="$rawStart"\
                       '{ 
                         if (NR < rawStart) {next}
 
                         gsub (" ", "", $0)
                         if ($0 ~ /^##\[.*\]##$/){
                          print (NR - 1)
                          exit
                         }
                        }' < "$argsFile"
                     )"
        else
          # Check if any other labels appear. rawEnd here is label, not number
          readarray -t rawEnd <<<\
                    "$(awk\
                      '{
                        origLine = $0
                        gsub (" ", "", $0)
                        if ($0 ~ /^##\[.*\]##$/){
                           print origLine
                        }
                       }' < "$argsFile"
                     )"
          
          if [[ -n "$rawEnd" ]]; then
              if [[ "$isSkipLab" = true ]]; then
                  return "2"
              else
                rawEnd=("$(JoinToStr ", " "${rawEnd[@]}")")
                ErrMsg "Can't find label: ##[ $scrLab ]## in $argsFile, while
                        other labels exist:
                        $rawEnd"    
              fi
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
        ErrMsg "No arguments after ##[ $scrLab ]## in $argsFile!"
    fi
    
    EchoLineSh
    if [[ -n "$scrLab" ]]; then
        echo "Reading arguments in \"$scrLab\" section from \"$argsFile\""
    else
      echo "Reading arguments from \"$argsFile\""
    fi
    echo "Starting line: $rawStart"
    echo "Ending line: $rawEnd"
    EchoLineSh
    
    declare -A varsList #map - array, local by default
    
    # Read files between rawStart and rawEnd lines, skipping empty raws
    declare -A nRepVars #number of repetiotions of argument
    while read -r firstCol restCol #because there might be spaces in names
    do
      nRepVars["$firstCol"]=$((nRepVars["$firstCol"] + 1))
      #((nRepVars["$firstCol"]++)) #- doesnot work
      varsList["$firstCol"]="$(sed -e "s#[\"$]#\\\&#g" <<< "$restCol")"
    done <<< "$(awk -v rawStart=$rawStart -v rawEnd=$rawEnd\
              'NF > 0 && NR >= rawStart; NR == rawEnd {exit}'\
              "$argsFile")"
    
    local i
    for i in ${!nRepVars[@]}; do
      if [[ ${nRepVars[$i]} -gt 1 ]]; then
          if [[ "$i" = "$reservArg" ]]; then
              ErrMsg "$i - reserved argument and cannot be duplicated"
          fi

          WarnMsg "Argument $i is repeated ${nRepVars[$i]} times.
                   Last value $i = ${varsList[$i]} is recorded."
      fi
    done

    # Assign variables
    for i in ${posArgList[@]}; do
      if [[ -n $(RmSp "${varsList[$i]}") ]]; then
          eval $i='${varsList[$i]}' #define: parameter=value
          exFl=$?
          if [ $exFl -ne 0 ]; then
              ErrMsg "Cannot read the parameter: $i=${valsList[$ind]}"
          fi
      fi
    done
  done
}

PrintArgs(){
  ## Print arguments for the "current" script
  ## Use: PrintArgs "$scriptName" "${posArgs[@]}"
  local curScrName=$1
  shift 

  local posArgs=("$@")
  local maxLenArg=() #detect maximum argument length

  for i in ${!posArgs[@]};  do
    maxLenArg=(${maxLenArg[@]} ${#posArgs[$i]})
  done
  maxLenArg=$(max ${maxLenArg[@]})

  ## Print
  EchoLineSh
  if [[ -n $(RmSp "$curScrName") ]]; then
      echo "Arguments for $curScrName:"
  else
    echo "Arguments"
  fi
  EchoLineSh
  
  local i
  for i in ${posArgs[@]}
  do
    eval "printf \"%-$((maxLenArg + 10))s %s \n\"\
                 \"- $i\" \"$"$i"\" "
  done
  EchoLineSh
}

mk_dir(){ #Delete. 
  # Function is alias to real mkdir -p, but which proceeds an exit flag in a
  # right way.

  local dirName=$1
  if [[ -z $(RmSp "$dirName") ]]; then
      ErrMsg "Input is empty"
  fi

  mkdir -p "$dirName"
  exFl=$?
  if [ $exFl = 0 ]; then
      echo "$dirName is created"
  else
    ErrMsg "Error: $dirName not created"
  fi
}
