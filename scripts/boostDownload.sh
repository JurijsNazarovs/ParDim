#!/bin/bash
# ==============================================================================
# boostDownload.sh transforms table in a way to submit to condor job            
# to reduce the number of downloading files.                                   
# The result of the function is a file(table), which
# has same name and extension  as an input table,
# but the name will end with Tmp. Also, the path equals to the path of tmp fold
# er.
#
# The output file looks like that: link, link for corresponding chip,
# type (ctl, and etc), name of all experiments where this file is participating.
#
# The condor jobs download all files based on links, and distribute
# in right folders based on names of experiments, changing names based on types.
#
# Input:
#	-argsFile	file with all arguments for this shell
#
# Possible arguments are described in a section: ## Default values
#
# If join several files, then final name based on the name of 1st file
# if it is relative name, then based on 1st name of relative names
# if there are several to join.
# ==============================================================================

## Libraries and options
shopt -s nullglob #allows create an empty array

homePath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$homePath"/funcList.sh

curScrName=${0##*/}


## Input and default values
argsFile=${1:-"args.listDev"} 
dagFile=${2:-"downloadFiles.dag"}
isSubmit=${3:-"false"} #submit condor or not (independence use of pipeline)
argsLabsDelim=${4:-""} #delim to split line with labels for argslist
if [[ -n $(rmSp "$argsLabsDelim") ]]; then
    argsLabs=${5:-""}
    readarray -t argsLabs <<< "$(echo "$argsLabs" | tr "$argsLabsDelim" "\n")"
fi
isDispProgBar=${6:-"false"} #use if results are not printed in file

# Default values: can be read from the $argsFile
posArgs=("tabPath" "tabDelim" "tabDelimJoin" "tabDirCol" "tabRelNameCol"\
         "tabIsSize" "nDotsExt" "inpPath" "jobsDir")

tabPath=""		#[R] path for  table
tabDelim=','		#delimeter to use in table
tabDelimJoin=';'        #delimeter to use in table to join files
tabDirCol=1             #index of column with directory
tabIsOrigName="false"   #use original names or not
tabRelNameCol=2         #column to use as a base for names if tabOrigName=false
tabIsSize="true"        #if table has size of files
nDotsExt=1              # # of dots before  extension of download files starts
inpPath=""		#[R] path for input data
jobsDir="downTmp"	#directory where to save tmp files

echoLine
echo "[Start] $curScrName"
# Read arguments and corresponding values
readArgs "$argsFile" "${#argsLabs[@]}" "${argsLabs[@]}" "${posArgs[@]}"
printArgs "$curScrName" "${posArgs[@]}"

# Check if any required arguments are empty
chkEmptyArgs "${posArgs[@]}" #check if any required arguments are empty

echo "Create temporary folder:  $jobsDir"
mkdir -p "$jobsDir"
dagFile="$jobsDir/$dagFile" #dag file, which contains jobs to download files


## Initial checking of the table
if [[ "$tabDelimJoin" = "$tabDelim" ]]; then
    errMsg "tabDelim and tabDelimJoin cannot be the same "
fi

# Read names of columns
readarray -t colName <<< "$(head -1 $tabPath | tr $tabDelim '\n')"

# Define number of columns and rows
nCol=${#colName[@]}
nRow=$(awk 'END{print NR}' "$tabPath")

# Check that in every line same number of columns
exFl="$(awk -F $tabDelim -v nCol=$nCol  'NF != nCol {print NR}' $tabPath)"

if [ -n "$exFl" ]; then
    errMsg "Rows:
            $exFl
            have inconsistent number of columns with header"
fi

## Prepare the output table, which is used to submit to condor

# Get iterators depending on whether we have size or not
if [[ "$tabIsSize" = true ]]; then
    if [[ $((tabDirCol%2)) -eq 0 ]]; then
        errMsg "Parameter \"tabDirCol\" can't be an even number, since
                size column follows link column"
    fi

    if [[ $((nCol%2)) -eq 0 ]]; then
        errMsg "Number of columns should be odd, since
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
for i in ${colIter[@]}; do
  #for ((i=2; i<=2; i++)); do
  printf "" > "$tabTmp1"
  printf "" > "$tabTmp2"
  printf "" > "$tabTmp3"
  # tabDirCol is skipped 
  if [[ $i = $tabDirCol ]]; then
      continue
  fi

  ## Create table with records (tabTmp1): link, right path including right name
  awk -v FS="$tabDelim" -v OFS="$tabDelim"\
      -v delimJoin=$tabDelimJoin\
      -v linkCol=$i -v dirCol=$tabDirCol\
      -v isOrigName=$tabIsOrigName -v relNameCol=$tabRelNameCol\
      -v nDotsExt=$nDotsExt\
      -v colName="${colName[$((i-1))]}"\
      -v inpPath="$inpPath"\
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
       {print $linkCol, inpPath "/" $dirCol "/" fileName}
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
        
        if [[ $(chkUrl "${linkCol[j]}") = false ]]; then
            errMsg "Url is not valid: ${linkCol[j]}
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


## Create condor to download files
conOut="$jobsDir/conOut"
mkdir -p "$conOut"

conFile="$jobsDir/downloadFiles.condor"
bash "$homePath"/makeCon.sh "$conFile" "$conOut" "$homePath/exeDownload.sh"\
     "\$(args)" "" "1" "1" "\$(downSize)" "0"
iter=1 #number of downloading files				
printf "" > "$dagFile"
while IFS='' read -r line || [[ -n "$line" ]]; do
  readarray -t line <<< "$(echo "$line" | tr "$tabDelim" "\n")"
  downSize=$((line[0]/1024/1024/1024 + 1)) #in Gb and rounded
  link="${line[1]}"
  path="$(joinToStr "$tabDelim" "${line[@]:2}")"
  # Create arguments string
  args="$(joinToStr "\' \'" "$link" "$path" "$tabDelim" "$tabDelimJoin")"
  printf "JOB download$iter $conFile\n" >> "$dagFile"
  printf "VARS download$iter downSize=\"$downSize\"\n" >> "$dagFile"
  printf "VARS download$iter args=\"$args\"\n" >> "$dagFile"
  printf "\n" >> "$dagFile"

  ((iter++))
done < "$tabOut"

## Check if we have several equal final pathes
awk -v FS="$tabDelim"\
    '{for(i = 3; i <= NF; i++) {print $i}}'\
    "$tabOut" > "$tabTmp1"
sort "$tabTmp1" | uniq -d  > "$tabTmp2"

errFl=0
while IFS='' read -r line || [[ -n "$line" ]]; do
  readarray -t line <<< "$(echo "$line" | tr "/" "\n")"
  lineLen=${#line[@]}
  if [[ $errFl -eq 0 ]]; then
      echoLineSh
      printf "Warning!\n\n"
  fi

  printf "File \"${line[$((lineLen-1))]}\" "
  printf "is scheduled to download in\n"
  printf "directory \"${line[$((lineLen-2))]}\" "
  printf "more than once.\n\n"

  ((errFl++))
done < "$tabTmp2"
if [[ $errFl -ne 0 ]]; then
    echo "Total warnings: $errFl"
    echo "Possible reason: for sevaral equal folders same relative name"
    echo "is provided, and parameter \"tabIsOrigName\" is false."
    echoLineSh
fi


## Submit mainDAG.dag
if [[ "$isSubmit" = true ]]; then
    condor_submit_dag -f "$dagFile"
fi

## End
rm -rf "$tabTmp1" "$tabTmp2" "$tabTmp3"

echo "[End]  $curScrName"
echoLine

exit 0
