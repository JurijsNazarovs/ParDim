#!/bin/bash
#===============================================================================
# This script creates a right version of a dag file of AQUAS pipeline,
# base on files in input directory (inpPath)
#
# The script supports a range of stages (first stage - last stage),
# according to which AQUAS pipeline should be executed and
# corresponding dag file should be constructed.

# This script can stop on any of a supported last stages, but 
# it CANNOT start with some first stage, if the script was not run
# until this first stage before.
# In other words, first stage works like a check point for current pipeline.
#
# Supported stages in an order:
#	- toTag. Not in this script, but in the whole pipeline
#	- pseudo
#	- xcor
#	- pool
#	- stgMacs2
#	- peaks
#	- idroverlap 
# Input:
#	- argsFile	 file with all arguments for this shell
#
# Possible arguments are described in a section: ## Default values		
#==============================================================================

## Libraries and options
shopt -s nullglob #allows create an empty array
homePath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" 
source "$homePath"/funcList.sh

curScrName=${0##*/} #delete last backSlash


### NEW INPUT
## Input and default values
argsFile=${1:-"args.listDev"} 
dagFile=${2:-"download.dag"} #create this
jobsDir=${3:-"downTmp"} #working directory, provided with one of analysed dirs
resPath=${4:-""} #return on submit server. Can be read from file if empty
inpDataInfo=${5} #text file with input data
isCondor=${6:-"true"} #true => script is executed in Condor(executed server)
### END OF NEW INPUT


## Default values, which can be read from the $argsFile
posArgs=("outPath" "firstStage" "lastStage" "trueRep" "coresNum"
	 "specName" "specList" "specTar" "ctlDepthRatio" "isAlligned"
         "exePath")

#rewrite stages!
firstStage="2"		#starting stage of the pipeline 
lastStage="10"		#ending stage of the pipeline
trueRep="false"		#whether to use true replicates or not
coresNum="4"		#number of cores for calculations
specName="hg19"		#names of species: hg38, hg19, mm10, mm9 
specList="spec.list"	#list with all species
specTar="spec.tar.gz"	#tar files w/ all species files
ctlDepthRatio="1.2"	#ratio to compare ctl files to pool
isAlligned="true"	#continue pipeline or run from scratch
exePath="$homePath/exeAquas.sh"

if [[ -z $(RmSp "$resPath") ]]; then
    posArgs=("${posArgs[@]}" "resPath")
fi

ReadArgs "$argsFile" "1" "Aquas" "${#posArgs[@]}" "${posArgs[@]}" > /dev/null
if [[ "${resPath:0:1}" != "/" ]]; then
    ErrMsg "The full path for resPath has to be provided.
           Current value is: $resPath ."
fi

PrintArgs "$curScrName" "${posArgs[@]}" "jobsDir"

firstStage=$(mapStage "$firstStage")
lastStage=$(mapStage "$lastStage")

ChkValArg "isAlligned" "" "true" "false"
ChkValArg "trueRep" "" "true" "false"

if [[ "$trueRep" = "false" ]]; then
    prNum=2 
else
  prNum=0
fi

## Stages
# Define names of stage
tagName="toTag"
pseudoName="pseudo"
xcorName="xcor"
poolName="pool"
stgName="stgMacs2"
peakName="peaks"
idrName="idr"
overlapName="overlap"

# Map stageNames g
#tagStage=$(mapStage "$tagName")
tagStage=$(mapStage "toTagOriginal")
pseudoStage=$(mapStage "$pseudoName")
xcorStage=$(mapStage "$xcorName")
poolStage=$(mapStage "$poolName")
stgStage=$(mapStage "$stgName")
peakStage=$(mapStage "$peakName")
idrOverlapStage=$(mapStage "$idrName$overlapName")


## Detect reps and ctls
requirSize=0
inpPath="$(awk 'NR==1{print $1; exit}' "$inpDataInfo")"
inpPath="${inpPath%:}"
if [[ "$isAlligned" = true ]]; then
    inpExt="tagAlign.gz"
    inpPathTmp="$inpPath"align
    inpType=("rep" "ctl") #names of searched dirs with data

    for i in "${inpType[@]}"; do
      readarray -t inpDir <<<\
                "$(awk -F "\n"\
                       -v pattern="^$inpPathTmp/$i[0-9]*:$"\
                       '{ if ($0 ~ pattern) {print $0} }' "$inpDataInfo"
                 )"
      inpNum=${#inpDir[@]}

      if [[ $inpNum -eq 0 ]]; then 
	  ErrMsg "Number of $i files equals to 0."
      else
        for j in "${!inpDir[@]}"; do
          readarray -t strTmp <<< \
                    "$(awk -F "\t"\
                         -v dir="${inpDir[$j]}"\
                         -v file="$inpExt$"\
                         '{ 
                            if ($0 ~ dir) {f = 1; next}
                            if ($0 ~ "^/.*:$") {f = 0}
                            if (f == 1 && $1 ~ file) {print $0} 
                          }' "$inpDataInfo"
                    )"
	  
	  if [[ ${#strTmp[@]} -ne 1 ]]; then
	      ErrMsg "Cannot detect replicate name from ${inpDir[$j]}"
	  else #just one possible file in directory
            strTmp=(${strTmp[@]})
            requirSize=$((requirSize + strTmp[1]))
	    eval $i"Name[\"$j\"]=${inpDir[$j]%:}/\"${strTmp[0]}\""  #repName
          fi
        done
        eval $i"Num=\${#"$i"Name[@]}" #repNum
      fi
    done
else  #have to allign in this pipeline
  inpExt="bed.gz" #bam
  inpType=("rep" "ctl") #names of searched dirs with data
  posEnd=("ctl" "dnase")

  for i in "${inpType[@]}"; do
    if [[ "$i" != "rep" ]]; then
        inpExtTmp=".$i.$inpExt"
        readarray -t inpName <<<\
                  "$(awk -F "\t"\
                     -v file="$inpExtTmp$"\
                    '{ if ($1 ~ file && NF > 1) {print $0} }' "$inpDataInfo"
                  )"
    else
      posEndTmp=."$(JoinToStr ".|." "${posEnd[@]}")."
      readarray -t inpName <<<\
                "$(awk -F "\t"\
                       -v file="$posEndTmp"\
                       -v ext="$inpExt$"\
                       '{ if ($1 !~ file && $1 ~ ext && NF > 1) {print $0} }'\
                        "$inpDataInfo"
                 )"
    fi

    # Fill variables with full path to files and size
    for j in "${!inpName[@]}"; do
      strTmp=(${inpName[$j]})
      requirSize=$((requirSize + strTmp[1]))
      eval $i"Name[\"$j\"]=$inpPath\"${strTmp[0]}\""
    done
    eval $i"Num=\${#inpName[@]}" #repNum
  done
fi

if [[ "$repNum" -eq 0 ]]; then
    ErrMsg "Number of replicates has to be more than 0"
fi

if !([[ "$ctlNum" -eq 0 || "$ctlNum" -eq 1 || "$ctlNum" -eq "$repNum" ]]); then
    ErrMsg "Confusing number of ctl files.
            Number of ctl: $ctlNum
            Number of rep: $repNum"
fi


## Condor
# Calculate required memory, based on input files
hd=$requirSize #size in kilobytes
hd=$((hd*1)) #increase size in 1 times
hd=$(echo $hd/1024^2 + 1 | bc) #in GB rounded to a bigger integer
ram=$((1*hd)) #just in case.
ram=$(max $ram 13) #get at least 10GB
ram=$(min $ram 32) #get the most 32GB 

hd=$((hd+3+2)) #+3gb for installation files +2gb for safety

# Arguments for condor job
jobArgsFile #file filled with argumetns for every condor job, e.g. xcor1.args
jobArgsFileVar="argsFile" #variable
#E.g. DAG: argsFile="tag.args"; Condor: arguments = '$(argsFile)'
argsCon=("\$($jobArgsFileVar)" "$specName" "${specList##*/}" "${specTar##*/}")
argsCon=$(joinToStr "\' \'" "${argsCon[@]}")

# Output directory for condor log files
conOut="$jobsDir/conOut"
mkdir -p "$conOut"

# Transfered files
transFiles=("$jobsDir/\$($jobArgsFileVar)"
            "$specTar"
            "$specList"
	    "http://proxy.chtc.wisc.edu/SQUID/nazarovs/pipeInstallFiles.tar.gz")
transFiles=$(joinToStr ", " "${transFiles[@]}")

# Main condor file
conFile="$jobsDir/${curScrName%.*}.condor"
bash "$homePath"/makeCon.sh "$conFile" "$conOut" "$exePath"\
     "$argsCon" "$transFiles"\
     "\$(nCores)" "$ram" "$hd" "\$(transOut)" "\$(transMap)"

## STOP HERE
## Decision of using pool ctl or not
if [[ "$lastStage" -gt "$tagStage" ]]; then
    # Variables for future refences in pool and peaks, namely tags.
    useCtlPool=() #whether ctl[i]=pool or not
    for ((i=0; i<$ctlNum; i++))
    do
      useCtlPool[$i]="false"
    done

    inpExt="tagAlign.gz"
    ctlTag=() #array

    # Ctl
    for ((i=0; i<$ctlNum; i++))
    do
      ctlTag[$i]="$outPath/align/ctl$((i+1))/${ctlName[$i]}.nodup.$inpExt"
      
      # Check that ctl is not empty
      if [ "$(getNumLines "${ctlTag[$i]}")" -eq "0" ]; then
          ErrMsg "Wrong input! CTL: ${ctlTag[$i]} has 0 lines"
      fi
    done

    # Create copy of ctl1 for easy further calculations if we have just one ctl and several reps
    if [[ "$ctlNum" -eq "1" && "$repNum" -ge "2" ]]; then
        for ((i=1; i<$repNum; i++)) #yes, exactly from i=1
        do
          ctlTag[$i]="${ctlTag[0]}"
        done
    fi

    # Pooled ctl
    if [ "$ctlNum" -eq "1" ]; then
        ctlTagPool="${ctlTag[0]}"
    else
      ctlTagPool="$outPath/align/pooled_ctl/${ctlName[0]}.nodup_pooled.$inpExt"
    fi

    # Rep_j, rep_jPr1, rep_jPr2
    declare -A repTag #matrix, rows: rep, pr1, pr2, ...; cols: 1,..,repNum
    rowNum="$((1+prNum))" #real + number of pseudo
    colNum="$repNum"

    for ((i=0; i<$rowNum; i++))
    do
      for ((j=1; j<=$colNum; j++))
      do
        if [ "$i" -eq "0" ]; then #should exist
	    inpTmp="$outPath/align/rep$j/${repName[$((j-1))]}.nodup.$inpExt"

	    # Check that chip is not empty
	    if [ "$(getNumLines "$inpTmp")" -eq "0" ]; then
	        ErrMsg "Wrong input! CHIP: $inpTmp has 0 lines"
	    fi	
        else	 #just make a reference for future
          inpTmp="$outPath/align/pseudo_reps/rep$j/pr$i/${repName[$((j-1))]}.nodup.pr$i.$inpExt"
        fi
        #inpTmp=$(rmSp "$inpTmp") #not the best idea, since name can have spaces
        repTag[$i,$((j-1))]="$inpTmp"
      done
    done

    # Just if we have more than 1 ctl
    if [ "$ctlNum" -ge "2" ]; then	
        nLinesRep=() # of lines in tagaligns, key: 0,rep for replicate, 1,rep for control
        nLinesCtl=() # of lines in control tagaligns

        for ((i=0; i<$repNum; i++))
        do
          for tmp in ${repTag[0,$i]} ${ctlTag[$i]} #two different tmp
          do
	    chkInp "f" $tmp "${tmp##*/}"
          done

          nLinesRep[i]="$(getNumLines "${repTag[0,$i]}")"
          nLinesCtl[i]="$(getNumLines "${ctlTag[$i]}")"
        done

        nLinesCtlMax=$(max ${nLinesCtl[@]})
        nLinesCtlMin=$(min ${nLinesCtl[@]})
        tmp="$(echo ${nLinesCtlMax}/${nLinesCtlMin} |bc -l)"
        tmp="$(echo "$tmp > $ctlDepthRatio" |bc -l)"

        if [ $tmp -eq 1 ]; then
	    for ((i=0; i<$ctlNum; i++))
	    do				
	      useCtlPool[$i]=true
	      #ctlTag[$i]="$ctlTagPool"
	    done
        else	
          for ((i=0; i<$ctlNum; i++))
          do
	    if [ "${nLinesCtl[i]}" -lt "${nLinesRep[i]}" ]; then
	        useCtlPool[$i]=true
	        #ctlTag[$i]="$ctlTagPool"
	    fi
          done
        fi
    fi

fi


## Start the "$dagFile"
printfLine > "$dagFile" 
printf "# [Start] Description of $dagFile\n" >> "$dagFile"
printfLine >> "$dagFile"


## toTag
#if [[ "$firstStage" -le "$tagStage" && "$lastStage" -ge "$tagStage" && 1 -eq 0 ]]; then
if [[ "$firstStage" -le "$tagStage" && "$lastStage" -ge "$tagStage" ]]; then	
    jobName=$tagName

    printfLine >> "$dagFile"
    printf "# $jobName\n" >> "$dagFile" 
    printfLine >> "$dagFile"
    
    # Create the dag file
    for ((i=0; i<=1; i++)) #0 - rep, 1 - ctl 
    do
      if [ "$i" -eq "0" ]; then
	  labelTmp="Rep"
	  numTmp=$repNum
	  nameTmp=("${repName[@]}")
      else
	labelTmp="Ctl"
	numTmp=$ctlNum
	nameTmp=("${ctlName[@]}")
      fi
      
      for ((j=1; j<=$numTmp; j++))
      do
	jobId="$jobName$labelTmp$j"
	jobArgsFile=("$jobsDir/$jobId.args")

	printfLineSh >> "$dagFile"
	printf "# $jobId\n" >> "$dagFile"
	printfLineSh >> "$dagFile"

	printf "JOB $jobId $conNCore\n" >> "$dagFile"
	printf "VARS $jobId $jobArgsFileVar=\"$jobId.args\"\n" >> "$dagFile"
	# args file
	printf -- "script\t\t$jobName.bds\n" > $jobArgsFile
	printf -- "-out_dir\t\t$outPath\n" >> $jobArgsFile
	printf -- "-nth\t\t$coresNum\n" >> $jobArgsFile
	printf -- "-$inpExt\t\t$inpPath/${nameTmp[$((j-1))]}.$inpExt\n"\
	       >> $jobArgsFile
	printf -- "-rep\t\t$j\n" >> $jobArgsFile
	printf -- "-ctl\t\t$i\n" >> $jobArgsFile
	printf -- "-true_rep\t\t$trueRep\n" >> $jobArgsFile

	# Parent & Child dependency
	# xcor
	if [[ "$i" -eq "0" && "$lastStage" -ge "$xcorStage" ]]; then #i.e. rep
	    printf "PARENT $jobId CHILD xcor$j\n" >> "$dagFile"
	fi
	
	# pool
	if [[ "$lastStage" -ge "$poolStage" && "$repNum" -ge "2" && \
		  !("$i" = "1" && "$ctlNum" -le "1") ]]; then
	    if [ "$i" -eq "0" ]; then
		printf "PARENT $jobId CHILD ${poolName}Pr0 " >> "$dagFile"
		for ((k=1; k<=$prNum; k++))
		do
		  printf "${poolName}Pr$k " >> "$dagFile"
		done
		printf "\n" >> "$dagFile"
	    else
	      printf "PARENT $jobId CHILD ${poolName}Ctl\n" >> "$dagFile"
	    fi
	fi

	# peak
	if [ "$lastStage" -ge "$peakStage" ]; then
	    if [[ "$i" = "1" && "$ctlNum" -eq "1" && "$repNum" -ge "2" ]]; then
		printf "PARENT $jobId CHILD " >> "$dagFile"
		#i.e. we have 1 ctl and several replicates
		for ((s=0; s<=$repNum; s++)) #write all replicate peaks, including pooled as child
		do
		  for ((k=0; k<=$prNum; k++)) #go throw pseudo
		  do				
		    printf "${peakName}Rep${s}Pr$k " >> "$dagFile"
		  done
		done
		printf "\n" >> "$dagFile"
	    else #means that number of ctl = number or reps and > 1
	      if [[ !("$i" = 1 && "${useCtlPool[$((j-1))]}" = "true") ]]; then
		  printf "PARENT $jobId CHILD " >> "$dagFile"
		  for ((k=0; k<=$prNum; k++)) #go throw pseudo
		  do				
		    printf "${peakName}Rep${j}Pr$k " >> "$dagFile"
		  done
	      fi
	    fi
	    printf "\n" >> "$dagFile"
	fi

	# stgMacs
	if [ "$lastStage" -ge "$stgStage" ]; then
	    if [[ "$i" = "1" && "$ctlNum" -eq "1" && "$repNum" -ge "2" ]]; then
		printf "PARENT $jobId CHILD " >> "$dagFile"
		#i.e. we have 1 ctl and several replicates
		for ((s=0; s<=$repNum; s++)) #write all replicate peaks, including pooled as child
		do
		  printf "${stgName}Rep${s} " >> "$dagFile"
		done
		printf "\n" >> "$dagFile"
	    else #means that number of ctl = number or reps and > 1
	      if [[ !("$i" = 1 && "${useCtlPool[$((j-1))]}" = "true") ]]; then
		  printf "PARENT $jobId CHILD ${stgName}Rep${j}" >> "$dagFile"
	      fi
	    fi
	    printf "\n" >> "$dagFile"
	fi
      done
    done
fi


## pseudo
if [[ $firstStage -le $pseudoStage && $lastStage -ge $pseudoStage && "$trueRep" == "false" ]]; then
    jobName="$pseudoName" 

    printfLine >> "$dagFile"
    printf "# $jobName\n" >> "$dagFile" 
    printfLine >> "$dagFile"
    
    # Create the dag file	
    for ((j=1; j<=$repNum; j++))
    do
      jobId="${jobName}Rep$j"
      jobArgsFile=("$jobsDir/$jobId.args")

      printfLineSh >> "$dagFile"
      printf "# $jobId\n" >> "$dagFile"
      printfLineSh >> "$dagFile"

      printf "JOB $jobId $conFile\n" >> "$dagFile"
      printf "VARS $jobId $jobArgsFileVar=\"$jobId.args\"\n" >> "$dagFile"
      printf "VARS $jobId nCores=1\n" >> "$dagFile"
      # args file
      printf -- "script\t\t$jobName.bds\n" > $jobArgsFile
      printf -- "-out_dir\t\t$outPath\n" >> $jobArgsFile
      printf -- "-nth\t\t1\n" >> $jobArgsFile
      printf -- "-tag\t\t${repTag[0,$((j-1))]}\n" >> $jobArgsFile
      printf -- "-rep\t\t$j\n" >> $jobArgsFile

      # Parent & Child dependency
      
      # pool
      if [[ $lastStage -ge $poolStage && "$repNum" -ge "2" ]]; then
	  printf "PARENT $jobId CHILD " >> "$dagFile"
	  for ((k=1; k<=$prNum; k++))
	  do
	    printf "${poolName}Pr$k " >> "$dagFile"
	  done
	  printf "\n" >> "$dagFile"
      fi

      # peak
      if [[ $lastStage -ge $peakStage && $ctlNum -ge 1 ]]; then
	  printf "PARENT $jobId CHILD " >> "$dagFile"
	  for ((k=1; k<=$prNum; k++)) #go throw pseudo
	  do				
	    printf "${peakName}Rep${j}Pr$k " >> "$dagFile"
	  done

	  printf "\n" >> "$dagFile"
      fi
    done
fi


## xcor
if [[ "$firstStage" -le "$xcorStage" && "$lastStage" -ge "$xcorStage" ]]; then
    jobName=$xcorName
    inpExt="tagAlign.gz"

    printfLine >> "$dagFile"
    printf "# $jobName\n" >> "$dagFile" 
    printfLine >> "$dagFile"
    
    # Create the dag file
    for ((i=1; i<=$repNum; i++))
    do				
      jobId="$jobName$i"
      jobArgsFile=("$jobsDir/$jobId.args")

      printfLineSh >> "$dagFile"
      printf "# $jobId\n" >> "$dagFile"
      printfLineSh >> "$dagFile"

      #printf "JOB $jobId $conNCore\n" >> "$dagFile"
      printf "JOB $jobId $conFile\n" >> "$dagFile"
      printf "VARS $jobId $jobArgsFileVar=\"$jobId.args\"\n" >> "$dagFile"
      printf "VARS $jobId nCores=1\n" >> "$dagFile"
      
      # args file
      printf -- "script\t\t$jobName.bds\n" > $jobArgsFile
      printf -- "-out_dir\t\t$outPath\n" >> $jobArgsFile
      #printf -- "-nth\t\t$coresNum\n" >> $jobArgsFile
      printf -- "-nth\t\t1\n" >> $jobArgsFile
      printf -- "-tag\t\t${repTag[0,$((i-1))]}\n" >> $jobArgsFile
      printf -- "-rep\t\t$i\n" >> $jobArgsFile

      # Parent & Child dependency
      # peak
      if [[ "$lastStage" -ge "$peakStage" && $ctlNum -ge 1 ]]; then
	  printf "PARENT $jobId CHILD " >> "$dagFile"

	  if [ "$repNum" -gt "1" ]; then #pooled peak
	      for ((j=0; j<=$prNum; j++)) #go throw pseudo
	      do				
		printf "${peakName}Rep0Pr$j " >> "$dagFile"
	      done
	  fi

	  for ((j=0; j<=$prNum; j++)) #go throw pseudo #replicate peak
	  do				
	    printf "${peakName}Rep${i}Pr$j " >> "$dagFile"
	  done
	  printf "\n" >> "$dagFile"
      fi

      # stgMacs
      if [[ "$lastStage" -ge "$stgStage" && $ctlNum -ge 1 ]]; then
	  printf "PARENT $jobId CHILD " >> "$dagFile"

	  if [ "$repNum" -gt "1" ]; then #pooled peak				
	      printf "${stgName}Rep0 " >> "$dagFile"
	  fi
	  
	  printf "${stgName}Rep${i}" >> "$dagFile"
	  printf "\n" >> "$dagFile"
      fi
    done
fi


## pool
if [[ "$firstStage" -le "$poolStage" && "$lastStage" -ge "$poolStage" && "$repNum" -ge "2" ]]; then
    jobName=$poolName
    inpExt="tagAlign.gz"
    jobArgsFile=() #here we have several arguments files

    printfLine >> "$dagFile"
    printf "# $jobName\n" >> "$dagFile" 
    printfLine >> "$dagFile"

    # Reps and PR

    # Create args files for pr0-2
    for ((i=0; i<$rowNum; i++))
    do
      jobArgsFile[$i]="$jobsDir/${jobName}Pr$i.args"
      printf -- "script\t\t$jobName.bds\n" > ${jobArgsFile[$i]}
      printf -- "-out_dir\t\t$outPath\n" >> ${jobArgsFile[$i]} 
      printf -- "-nth\t\t1\n" >> ${jobArgsFile[$i]}

      for ((j=1; j<=$colNum; j++)) #number of reps
      do
	printf -- "-tag$j\t\t${repTag[$i,$((j-1))]}\n">> ${jobArgsFile[$i]}
      done

      printf -- "-ctl\t\t0\n">> ${jobArgsFile[$i]}
      printf -- "-pr\t\t$i\n">> ${jobArgsFile[$i]}
    done

    # ctls	
    if [ "$ctlNum" -gt "1" ]; then
	# Create args file for ctl
	jobArgsFileTmp="$jobsDir/${jobName}Ctl.args"
	jobArgsFile[${#jobArgsFile[@]}]=$jobArgsFileTmp
	printf -- "script\t\t$jobName.bds\n" > $jobArgsFileTmp
	printf -- "-out_dir\t\t$outPath\n" >> $jobArgsFileTmp
	printf -- "-nth\t\t1\n" >> $jobArgsFileTmp

	# Fill these files
	for ((i=1; i<=$ctlNum; i++))
	do
	  printf -- "-tag$i\t\t${ctlTag[$((i-1))]}\n">> $jobArgsFileTmp
	done
	printf -- "-ctl\t\t1\n">> $jobArgsFileTmp
    fi

    # Fill job file
    for ((i=0; i<${#jobArgsFile[@]}; i++)) #pr0, pr1, pr2, ..., ctl
    do
      jobId="${jobArgsFile[i]##*/}" #take the name from the argFile with format
      jobId="${jobId%.*}" #delete format

      printfLineSh >> "$dagFile"
      printf "# $jobId\n" >> "$dagFile"
      printfLineSh >> "$dagFile"

      printf "JOB $jobId $conFile\n" >> "$dagFile"
      printf "VARS $jobId $jobArgsFileVar=\"$jobId.args\"\n" >> "$dagFile"
      printf "VARS $jobId nCores=1\n" >> "$dagFile"
      
      # Parent & Child dependency
      # peak
      if [[ "$lastStage" -ge "$peakStage" && $ctlNum -ge 1 ]]; then
	  printf "PARENT $jobId CHILD " >> "$dagFile"

	  if [ "$i" -lt "$((${#jobArgsFile[@]} - 1))" ]; then #pr part
	      printf "${peakName}Rep0Pr$i " >> "$dagFile"
	  else 
	    if [ "$ctlNum" -ge "2" ]; then #ctl part
		for ((j=0; j<=$prNum; j++)) #go throw pooled pseudo peaks
		do
		  printf "${peakName}Rep0Pr$j " >> "$dagFile"
		done
		
		# Peaks of reps, where ctl = pool
		for ((j=0; j<$ctlNum; j++))
		do
		  if [ "${useCtlPool[$j]}" = "true" ]; then
		      for ((k=0; k<=$prNum; k++)) #go throw pooled pseudo peaks
		      do
			printf "${peakName}Rep$((j+1))Pr$k "\
			       >> "$dagFile"
		      done
		  fi
		done
	    else #last pr part
	      printf "${peakName}Rep0Pr$i " >> "$dagFile" 
	    fi
	  fi
	  printf "\n" >> "$dagFile"
      fi

      # stgMacs2
      if [[ "$lastStage" -ge "$stgStage" && $ctlNum -ge 1 ]]; then
	  if [ "$i" -eq "0" ]; then
	      printf "PARENT $jobId CHILD ${stgName}Rep0" >> "$dagFile"
	  fi

	  if [[ "$i" = "$((${#jobArgsFile[@]} - 1))" && "$ctlNum" -ge "2" ]]; then #ctl part
	      printf "PARENT $jobId CHILD " >> "$dagFile"
	      printf "${stgName}Rep0 " >> "$dagFile"

	      # Peaks of reps, where ctl = pool
	      for ((j=0; j<$ctlNum; j++))
	      do
		if [ "${useCtlPool[$j]}" = "true" ]; then	
		    printf "${stgName}Rep$((j+1)) " >> "$dagFile"
		fi
	      done
	  fi
	  printf "\n" >> "$dagFile"
      fi
    done
fi

## Add path of ctlPool in ctlTag
for ((i=0; i<$ctlNum; i++))
do
  if [ "${useCtlPool[$i]}" = "true" ]; then
      ctlTag[$i]="$ctlTagPool"
  fi
done

## peak and stgMacs2. Code is almost the same for two parts. That is why we use loop
stIterTmp=("$stgName" "$peakName")
for stIter in "${stIterTmp[@]}"
do
  stTmp=$(mapStage "$stIter")
  if [[ $firstStage -le $stTmp && $lastStage -ge $stTmp && $ctlNum -ge 1 ]]; then
      jobName=$stIter
      inpExt="tagAlign.gz"

      if [ "$stIter" = "$stgName" ]; then
	  prNumTmp=0
      else
	prNumTmp=$prNum
      fi

      printfLine >> "$dagFile"
      printf "# $jobName\n" >> "$dagFile" 
      printfLine >> "$dagFile"

      # For reps
      for ((i=0; i<=$repNum; i++)) #0-pooled
      do	
	inpXcorTmp=() 
	jobId=()
	inpTmp=()
	
	# Create right records for job file
	if [ "$i" -eq "0" ]; then #i.e. pooled peak
	    if [ "$repNum" -ge "2" ]; then

		# ctl settings
		inpCtlTmp="$ctlTagPool" #includes 1 or many ctl

		# xcor settings
		for ((j=1; j<=repNum; j++))
		do
		  inpXcorTmp[$((j-1))]="$outPath/qc/rep$j/\
						${repName[$((j-1))]}.nodup.15M.cc.qc"
		done

		# rep and pr settings
		for ((j=0; j<=$prNumTmp; j++)) #go throw type of rep: rep, repPr1, repPr2, ...
		do				
		  if [ "$j" -eq "0" ]; then
		      inpTmp[$j]="$outPath/align/pooled_rep/\
							${repName[0]}.nodup_pooled.$inpExt"
		  else	
		    inpTmp[$j]="$outPath/align/pooled_pseudo_reps/ppr$j/\
							${repName[0]}.nodup.pr${j}_pooled.$inpExt"
		  fi
		  
		  jobId[$j]="${jobName}Rep${i}"
		  if [ "$stIter" != "$stgName" ]; then
		      jobId[$j]="${jobId[$j]}Pr$j"
		  fi
		done
	    else
	      continue
	    fi
	else #separately for replicates

	  # ctl settings
	  inpCtlTmp="${ctlTag[$((i-1))]}" #considering if ctlNum>1 or not

	  # xcor settings
	  inpXcorTmp="$outPath/qc/rep$i/${repName[$((i-1))]}.nodup.15M.cc.qc"

	  # rep and pr settings
	  for ((j=0; j<=$prNumTmp; j++)) #go throw type of rep: rep, repPr1, repPr2, ...
	  do
	    inpTmp[$j]=${repTag[$j,$((i-1))]}
	    jobId[$j]="${jobName}Rep${i}"
	    if [ "$stIter" != "$stgName" ]; then
		jobId[$j]="${jobId[$j]}Pr$j"
	    fi
	  done
	fi

	# Print jobs in the file		
	printfLineSh >> "$dagFile"
	printf "# Rep$i\n" >> "$dagFile" 
	printfLineSh >> "$dagFile"

	for ((j=0; j<=$prNumTmp; j++)) #go throw type of rep: rep, repPr1, repPr2, ...
	do
	  jobIdTmp="${jobId[$j]}"
	  jobArgsFile=("$jobsDir/$jobIdTmp.args")
	  inpTmp[$j]=$(rmSp "${inpTmp[$j]}")
	  

	  printf "JOB $jobIdTmp $conNCore\n" >> "$dagFile" #original like this
	  printf "VARS $jobIdTmp $jobArgsFileVar=\"$jobIdTmp.args\"\n" >> "$dagFile"
          if [[ "$stIter" = "$stgName" ]]; then #string comparison
	      printf "VARS $jobId nCores=1\n" >> "$dagFile"
	  else
	    printf "VARS $jobId nCores=$coresNum\n" >> "$dagFile"
	  fi

	  # args file
	  printf -- "script\t\t$jobName.bds\n" > $jobArgsFile
	  printf -- "-out_dir\t\t$outPath\n" >> $jobArgsFile
	  #printf -- "-nth\t\t$coresNum\n" >> $jobArgsFile

	  if [ "$stIter" = "$stgName" ]; then #string comparison
	      printf -- "-nth\t\t1\n" >> $jobArgsFile
	  else
	    printf -- "-nth\t\t$coresNum\n" >> $jobArgsFile
	  fi

	  printf -- "-tag\t\t${inpTmp[$j]}\n" >> $jobArgsFile
	  printf -- "-ctl_tag\t\t$inpCtlTmp\n" >> $jobArgsFile

	  if [ "$stIter" != "$stgName" ]; then
	      printf -- "-pr\t\t$j\n" >> $jobArgsFile
	  fi

	  if [ "$i" -eq "0" ]; then
	      for ((k=1; k<=$repNum; k++))
	      do
		inpXcorTmp[$((k-1))]=$(rmSp "${inpXcorTmp[$((k-1))]}")			
		printf -- "-xcor_qc$k\t\t${inpXcorTmp[$((k-1))]}\n"\
		       >> $jobArgsFile
	      done
	  else
	    printf -- "-rep\t\t$i\n" >> $jobArgsFile
	    printf -- "-xcor_qc\t\t$inpXcorTmp\n" >> $jobArgsFile
	  fi

	  # Parent & Child dependency
	  if [[ "$lastStage" -ge "$idrOverlapStage" && "$stIter" != "$stgName" ]]; then
	      printf "PARENT $jobIdTmp CHILD $idrName $overlapName\n\n"\
		     >> "$dagFile"
	  fi
	done
      done
  fi
done


## idr and overlap
if [[ $firstStage -le $idrOverlapStage && $lastStage -ge $idrOverlapStage && $ctlNum -ge 1 ]]; then
    inpExt="regionPeak.gz"
    jobArgsFileTmp=("$jobsDir/tmp.args")

    for ((i=0; i<$ctlNum; i++))
    do
      if [ "${useCtlPool[$i]}" = "true" ]; then
	  ctlNameTmp[$i]="${ctlTagPool##*/}" #take the name of the file, deleting path
      else 
	ctlNameTmp[$i]="${ctlTag[$i]##*/}" #take the name of the file, deleting path
      fi
      ctlNameTmp[$i]="${ctlNameTmp[$i]%.*}" #delete .gz
    done

    # Create copy of ctl1 names for easy further calculations if we have just one ctl and several reps
    if [[ "$ctlNum" -eq "1" && "$repNum" -ge "2" ]]; then
	for ((i=1; i<$repNum; i++)) #yes, exactly from i=1
	do
	  ctlNameTmp[$i]="${ctlNameTmp[0]}"
	done
    fi
    
    # Create input for args files for both idr and overlap
    for ((i=0; i<=$repNum; i++)) #0-pooled
    do
      inpTmp=()
      if [ "$i" -eq "0" ]; then #i.e. pooled version
	  if [ "$repNum" -ge "2" ]; then
	      # rep and pr settings
	      for ((j=0; j<=$prNum; j++)) #go throw type of rep: rep, repPr1, repPr2, ...
	      do				
		# below repName[0] is used, because AQUAS takes it as a name for pooled replicates
		if [ "$j" -eq "0" ]; then
		    inpTmp[$j]="$outPath/peak/spp/pooled_rep/\
						${repName[0]}.nodup_pooled.tagAlign_x_"
		else	
		  inpTmp[$j]="$outPath/peak/spp/pooled_pseudo_reps/ppr$j/\
						${repName[0]}.nodup.pr${j}_pooled.tagAlign_x_"
		fi
		# It should be ctlTagPool anyway (which can be just ctlName[0] if ctlNum=1)
		strTmp="${ctlTagPool##*/}"
		strTmp="${strTmp%.*}" #delete .gz
		inpTmp[$j]="${inpTmp[$j]}$strTmp.$inpExt" #because for both cases we use same ending.
	      done
	  else
	    continue
	  fi
      else #separately for replicates
	for ((j=0; j<=$prNum; j++)) #go throw type of rep: rep, repPr1, repPr2, ...
	do
	  if [ "$j" -eq "0" ]; then
	      inpTmp[$j]="$outPath/peak/spp/rep$i/\
					${repName[$((i-1))]}.nodup.tagAlign_x_"
	  else	
	    inpTmp[$j]="$outPath/peak/spp/pseudo_reps/rep$i/pr$j/\
					${repName[$((i-1))]}.nodup.pr$j.tagAlign_x_"
	  fi
	  inpTmp[$j]="${inpTmp[$j]}${ctlNameTmp[$((i-1))]}.$inpExt" #because for both cases we use same ending
	done
      fi

      # args file
      for ((j=0; j<=$prNum; j++)) #go throw type of rep: rep, repPr1, repPr2, ...
      do
	inpTmp[$j]=$(rmSp "${inpTmp[$j]}")
	if [ "$i" -eq "0" ]; then
	    if [ "$j" -eq "0" ]; then
		printf -- "-peak_pooled" >> $jobArgsFileTmp
	    else
	      printf -- "-peak_ppr$j" >> $jobArgsFileTmp
	    fi
	else
	  if [ "$repNum" = "1" ]; then
	      printf -- "-peak" >> $jobArgsFileTmp
	  else
	    printf -- "-peak$i" >> $jobArgsFileTmp
	  fi
	  if [ "$j" -ne "0" ]; then
	      printf -- "_pr$j" >> $jobArgsFileTmp
	  fi
	fi
	printf -- "\t\t${inpTmp[$j]}\n" >> $jobArgsFileTmp
      done
    done

    printf -- "-out_dir\t\t$outPath\n" >> $jobArgsFileTmp
    printf -- "-true_rep\t\t$trueRep\n" >> $jobArgsFileTmp
    printf -- "-nth\t\t1\n" >> $jobArgsFileTmp

    # Fill job files
    jobId=($idrName $overlapName)
    for jobName in "${jobId[@]}"
    do
      printfLine >> "$dagFile"
      printf "# $jobName\n" >> "$dagFile" 
      printfLine >> "$dagFile"

      jobArgsFile=("$jobsDir/$jobName.args")
      printf "JOB $jobName $conFile\n" >> "$dagFile"
      printf "VARS $jobName $jobArgsFileVar=\"$jobName.args\"\n\n" >> "$dagFile"
      printf "VARS $jobId nCores=1\n" >> "$dagFile"
      
      cp "$jobArgsFileTmp" "$jobArgsFile"
      printf -- "script\t\t$jobName.bds\n" >> $jobArgsFile
    done

    rm -rf $jobArgsFileTmp
fi

## stg
#if [[ "$firstStage" -le "$stgStage" && "$lastStage" -ge "$stgStage" ]]; then
#	jobName="stg"
#	inpExt="bam"
#
#	printfLine >> "$dagFile"
#	printf "# $jobName\n" >> "$dagFile" 
#	printfLine >> "$dagFile"
#			
#	# Create the dag file
#	inpExt="bam"
#		
#	for ((i=1; i<=$repNum; i++))
#	do
#		jobId="$jobName$i"
#		jobArgsFile=("$jobsDir/$jobId.args")
#
#		printfLineSh >> "$dagFile"
#		printf "# $jobId\n" >> "$dagFile"
#		printfLineSh >> "$dagFile"
#
#		printf "JOB $jobId $conNCore\n" >> "$dagFile"
#		printf "VARS $jobId $jobArgsFileVar=\"$jobId.args\"\n" >> "$dagFile"
#		
#		# args file
#		printf -- "script\t\t$jobName.bds\n" > $jobArgsFile
#		printf -- "-out_dir\t\t$outPath\n" >> $jobArgsFile
#		printf -- "-nth\t\t$coresNum\n" >> $jobArgsFile
#		printf -- "-$inpExt\t\t$inpPath/${repName[$((i-1))]}.$inpExt\n"\
    #										>> $jobArgsFile
#		printf -- "-rep\t\t$i\n" >> $jobArgsFile
#	done
#fi

## End
printfLine >> "$dagFile"
printf "# [End] Description of $dagFile\n" >> "$dagFile"
printfLine >> "$dagFile"

exit 0 #everything is ok
