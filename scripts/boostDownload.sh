#!/bin/bash
# ==============================================================================
# boostDownload.sh - download uniques files and distribute them in right
# directories, with several options:
#     - save files with original names or based on relative name according to
#       pattern: relativeName.columnName.extensionOfRelName
#       e.g.: relativeName = enc.gz, columnName = ctl => output = enc.ctl.gz
#       Note: names for relativeName column is not changed
#     - combine several files, splitted by tabDelimJoin, then
#       final name is based on the name of 1st file. If it is relative name,
#       then based on 1st name of relative names, if there are several to join.
#
# The result of the function is:
#     - dagFile - description of jobs to download unique file
#
# The final output file (removed) to generate dagFile looks like following:
# size(for condor), link, all directories to copy.
#
# Possible arguments are described in a section: ## Input and default values 
# ==============================================================================

## Libraries and options
shopt -s nullglob #allows create an empty array
homePath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$homePath"/funcListParDim.sh

curScrName=${0##*/}


## Input and default values
argsFile=${1:-args.listDev} 
dagFile=${2:-download.dag} #create this
jobsDir=${3:-downTmp} #working directory
resPath=${4} #return here on submit server. Can be read from file if empty
isCondor=${6:-true} #true => script is executed in Condor(executed server)
isSubmit=${7:-true} #false => dry run

ChkValArg "isCondor" "" "true" "false"
argsFile="$(readlink -m "$argsFile")" #whole path
ChkExist f "$argsFile" "File with arguments for $curScrName: $argsFile\n"

# Read arguments from the $argsFile, given default values
posArgs=("tabPath" "exePath"
         "tabDelim" "tabDelimJoin" "tabDirCol"
         "tabIsOrigName" "tabRelNameCol" "tabIsSize" "nDotsExt"
         "isCreateLinks" "isZipRes")

tabPath=""		#[R] path for table or name in case of ParDim
exePath="$homePath/exeDownload.sh"
isDispProgBar="true"    #use if results are not printed in file
tabDelim=','		#delimeter to use in table
tabDelimJoin=';'        #delimeter to use in table to join files
tabDirCol=1             #index of column with directory
tabIsOrigName="true"   #use original names or not (see tabRelNameCol)
tabRelNameCol=2         #column to use as a base for names if tabOrigName=false
tabIsSize="false"       #if table has size of files
nDotsExt=1              # # of dots before  extension of download files starts
isCreateLinks="true"    #create links instead of real files
isZipRes="true"         #zip results for transfering

if [[ -z $(RmSp "$resPath") ]]; then
    posArgs=("${posArgs[@]}" "resPath")
fi

ReadArgs "$argsFile" 1 "Download"  "${#posArgs[@]}" "${posArgs[@]}" > /dev/null
if [[ "$isCondor" = true ]]; then 
    isSubmit="false" #because submit is the next step of ParDim
    isDispProgBar="false"
    tabPath="${tabPath##*/}"
fi
if [[ "${resPath:0:1}" != "/" ]]; then
    ErrMsg "The full path for resPath has to be provided.
           Current value is: $resPath ."
fi

if [[ "$isCondor" = false ]]; then
    mkdir -p "$resPath"
    if [[ "$?" -ne 0 ]]; then
        ErrMsg "$resPath was not created."
    else
      # Directory might exist
      ChkAvailToWrite "resPath"
    fi
fi

ChkExist f "$tabPath" "Input file for $curScrName: $tabPath"
PrintArgs "$curScrName" "${posArgs[@]}"
WarnMsg "Make sure that resPath: $resPath
        is available from a submit machine."

echo "Creating the temporary folder: $jobsDir"
mkdir -p "$jobsDir"


## Initial checking of the table
if [[ "$tabDelimJoin" = "$tabDelim" ]]; then
    ErrMsg "tabDelim and tabDelimJoin cannot be the same"
fi

# Read names of columns
readarray -t colName <<< "$(head -1 $tabPath | tr $tabDelim '\n')"

# Define number of columns and rows
nCol=${#colName[@]}
nRow=$(awk 'END{print NR}' "$tabPath")

# Check that in every line same number of columns
exFl="$(awk -F $tabDelim -v nCol=$nCol  'NF != nCol {print NR}' $tabPath)"

if [ -n "$exFl" ]; then
    ErrMsg "Rows:
            $exFl
            have inconsistent number of columns with header"
fi


## Prepare the output table, which is used to submit to condor

# Get iterators depending on whether we have size or not
if [[ "$tabIsSize" = true ]]; then
    if [[ $((tabDirCol%2)) -eq 0 ]]; then
        ErrMsg "Parameter \"tabDirCol\" can't be an even number, since
                size column follows link column"
    fi

    if [[ $((nCol%2)) -eq 0 ]]; then
        ErrMsg "Number of columns should be odd, since
                size column follows link column and
                we have dir column"
    fi

    colIterStep=2 #read every second column
else
  colIterStep=1 #read every column
fi
readarray -t colIter <<< "$(seq 1 $colIterStep $(($tabDirCol - 1));\
                            seq $(($tabDirCol + 1)) $colIterStep $nCol)"

# Copy $tabPath file to $out without the header
tabOut=$(mktemp -q "$jobsDir/${tabPath##*/}"Out.XXXX) #create tmp file
tabTmp1=$(mktemp -q "$jobsDir/${tabPath##*/}"Tmp1.XXXX) #create tmp file
tabTmp2=$(mktemp -q "$jobsDir/${tabPath##*/}"Tmp2.XXXX) #create tmp file
tabTmp3=$(mktemp -q "$jobsDir/${tabPath##*/}"Tmp3.XXXX) #create tmp file

printf "" > "$tabOut"
for i in "${colIter[@]}"; do
  printf "" > "$tabTmp1"
  printf "" > "$tabTmp2"
  printf "" > "$tabTmp3"
 
  if [[ "$i" = "$tabDirCol" ]]; then
      continue
  fi

  ## Create table with records (tabTmp1): link, right path including right name
  awk -v FS="$tabDelim" -v OFS="$tabDelim"\
      -v delimJoin=$tabDelimJoin\
      -v linkCol=$i -v dirCol=$tabDirCol\
      -v isOrigName=$tabIsOrigName -v relNameCol=$tabRelNameCol\
      -v nDotsExt=$nDotsExt\
      -v colName="${colName[$((i-1))]}"\
      '{
        if (NR <= 1) {next} #skip header

        ## Chose a right name for the file
        if (isOrigName == "false" && linkCol != relNameCol){
          fileName=$relNameCol
        } else {
          fileName=$linkCol
        }
        
        # Chose part before "delimeter to join". 
        len = split(fileName, a, delimJoin)
        fileName=a[1]

        # Get name part (last part)
        len = split(fileName, a, "/")
        fileName = a[len]

        # Change name based on relative name
        if (isOrigName == "false" && linkCol != relNameCol){
          len = split(fileName, a, ".")

          if (nDotsExt < len){
            # Add part before extenstion starts
            fileName = a[1]
            for(j = 2; j <= nDotsExt; j++){
              fileName = fileName "." a[j]
            }
            # Add name of the column
            fileName = fileName "." colName
            # Add extension
            for(j = nDotsExt + 1; j <= len; j++){
              fileName = fileName "." a[j]
            }
          }

        }

       }
       {print $linkCol, $dirCol "/" fileName}
      ' "$tabPath" > "$tabTmp1"
  

  ## Create table with records (tabTmp2): size
  if [[ "$tabIsSize" = true ]]; then
      awk -v FS="$tabDelim" -v OFS="$tabDelim" -v sizeCol=$((i+1))\
          'NR <=1 {next} {print $sizeCol}' "$tabPath" > "$tabTmp2"
  else
    lineCount=0
    printf "File size detection (column $i): "
    if [[ "$isDispProgBar" = true ]]; then
        printf "\n"
    fi

    rowErrInd=2 #1-st is header
    while IFS="$tabDelim" read -r linkCol pathCol; do
      
      # Consider link=combination of several links with
      # sep = $tabDelimJoin. So, that size can be summed
      readarray -t linkCol <<< "$(echo $linkCol | tr "$tabDelimJoin" '\n')"

      sizeCol=0
      for ((j = 0; j < ${#linkCol[@]}; j++)); do
        
        if [[ $(ChkUrl "${linkCol[j]}") = false ]]; then
            ErrMsg "Url is not valid: ${linkCol[j]}
                    Column: $i -  ${colName[$((i-1))]}
                    Row: $rowErrInd"
        fi

        sizeColTmp="$(wget ${linkCol[j]} --spider --server-response -O - 2>&1 |\
                         sed -ne '/^Length/{s/.*: \([0-9]*\).*/\1/;p}')"
        sizeCol=$((sizeCol + sizeColTmp))
        exFl=$?
        if [[ $exFl -ne 0 ]]; then
            sizeCol="NA"
            continue
        fi

        ((rowErrInd++))
      done
      
      printf "$sizeCol\n" >> "$tabTmp2"

      # Progress bar, because it may take too long
      if [[ "$isDispProgBar" = true ]]; then
          lineCount=$((lineCount + 1))
          progBar=$((lineCount*100/(nRow-1))) #-1 because no header
          printf "#%.0s" $(seq 0 $((progBar/1)))
          printf " %.0s" $(seq 0 $(((100 - progBar)/1)))
          printf "| $progBar%%"
          
          if [[ $lineCount -ne $((nRow-1)) ]]; then
              printf "\r"
          else
            printf "\n"
          fi
      fi
    done < "$tabTmp1"

    if [[ "$isDispProgBar" != true ]]; then
        printf " Done!\n"
    fi
  fi

  
  ## Combination of tmp files
  # Create size, link, path
  paste -d "$tabDelim" "$tabTmp2" "$tabTmp1" > "$tabTmp3"

  # Take unique records, because files migt be accidentaly repeated
  # E.g.: 2 rows have same 2 columns, but 3rd is different, then
  # for link in 2nd column will be 2 same pathes.
  sort "$tabTmp3" | uniq > "$tabTmp1"
  cat "$tabTmp1" > "$tabTmp3"
  
  # Join path of downloading file according to size, link
  awk -v FS="$tabDelim" -v OFS="$tabDelim"\
      'NF >= 3 {a[$1 FS $2] = a[$1 FS $2] FS $3} END{for(i in a){print i a[i]}}'\
      "$tabTmp3" > "$tabTmp1"
  # Concatenate to final file
  cat "$tabTmp1" >> "$tabOut"
done


## Check if we have several equal final pathes
awk -v FS="$tabDelim"\
    '{for(i = 3; i <= NF; i++) {print $i}}'\
    "$tabOut" > "$tabTmp1"
sort "$tabTmp1" | uniq -d  > "$tabTmp2" #print duplicated directories

errFl=0
while IFS='' read -r line || [[ -n "$line" ]]; do
  readarray -t line <<< "$(echo "$line" | tr "/" "\n")"
  lineLen=${#line[@]}

  WarnMsg "File ${line[$((lineLen-1))]}
          is scheduled to download in 
          directory ${line[$((lineLen-2))]}
          more than once."

  ((errFl++))
done < "$tabTmp2"

if [[ $errFl -ne 0 ]]; then
    WarnMsg "Total warnings: $errFl
             Possible reason: for sevaral equal directories same relative name
             is provided, and parameter \"tabIsOrigName\" is false."
fi


## Create condor to download files
conOut="$jobsDir/conOut"
mkdir -p "$conOut"

conFile="$jobsDir/${curScrName%.*}.condor"
bash "$homePath"/makeCon.sh "$conFile" "$conOut" "$exePath"\
     "\$(args)" "" "1" "1" "\$(downSize)" "\$(transOut)" "\$(transMap)"
if [[ "$?" -ne 0 ]]; then
    ErrMsg "Cannot create a condor file: $conFile" "$?"
fi

nZeros=$(awk 'END{print(NR)}' < "$tabOut") #to create jobId with leading zeros
nZeros=${#nZeros}
iter=1 #number of downloading files
printf "" > "$dagFile"
while IFS='' read -r line || [[ -n "$line" ]]; do
  readarray -t line <<< "$(echo "$line" | tr "$tabDelim" "\n")"
  if [[ "$isCreateLinks" = true ]]; then
      downSize=$((2*(line[0]/1024/1024/1024 + 1))) #in Gb, rounded + tarSize
  else
    numCopies=$((${#line[@]} - 2))
    downSize=$((2*numCopies*(line[0]/1024/1024/1024 + 1))) #in GB
  fi
  
  link="${line[1]}"
  path="$(JoinToStr "$tabDelim" "${line[@]:2}")"
  # Create arguments string
  args="$(JoinToStr "\' \'" "$link" "$path" "$tabDelim" "$tabDelimJoin"\
                    "\$(transOut)" "$isCreateLinks" "$isZipRes" "false")"
  #jobId="download$iter"
  jobId="$(printf "download%0${nZeros}d" "$((iter))")" 
  printf "JOB  $jobId $conFile\n" >> "$dagFile"
  
  printf "VARS $jobId args=\"$args\"\n" >> "$dagFile"
  printf "VARS $jobId downSize=\"$downSize\"\n" >> "$dagFile"
  if [[ "$isZipRes" = true ]]; then
      printf "VARS $jobId transOut=\"$jobId.tar.gz\"\n" >> "$dagFile"
  else
    printf "VARS $jobId transOut=\"$jobId.tar\"\n" >> "$dagFile"
  fi
  printf "VARS $jobId transMap=\"\$(transOut)=$resPath/\$(transOut)\"\n"\
         >> "$dagFile"
  printf "\n" >> "$dagFile"

  ((iter++))
done < "$tabOut"


## Submit mainDAG.dag
if [[ "$isSubmit" = true ]]; then
    condor_submit_dag -f "$dagFile"
    EchoLineSh
    if [[ "$?" -eq 0 ]]; then
        echo "$dagFile was submitted!"
    else
      ErrMsg "$dagFile was not submitted!"
    fi
    EchoLineSh
else
  EchoLineSh
  echo "$dagFile is created but not submitted"
  EchoLineSh
fi
  

## End
rm -rf "$tabTmp1" "$tabTmp2" "$tabTmp3" #"$tabOut"

exit 0
