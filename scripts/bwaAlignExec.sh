#!/bin/bash

#Function
getValue(){

    local argsFile=$1
    local selectName=$2
    local i=0
    local selectVal=""
    while read firstCol restCol
    do 
	varName[$i]="$firstCol"
	varValue[$i]="$restCol"
	((i++))
    done < $argsFile

    for i in ${!varName[@]}
    do
	if [ "${varName[$i]}" == $selectName ]
	then
	    selectVal=${varValue[$i]}
	    printf "$selectVal"
	    return 0
	fi
    done
}

#Parameters
argsFile=$1
dataDir=$2
expName=$3
dataName=$4

#obtain the parameter values from argsFile
bwaPara=("bwaIndexLink" "bwaIndexName" "bwaSoftwareLink" "nBWA" "oBWA" "tBWA" "mBWA" "qBWA" "lBWA" "kBWA" "outPath")
for i in ${!bwaPara[@]}
do
    eval ${bwaPara[$i]}="$(getValue "$argsFile" "${bwaPara[$i]}")"
done


#Transfer data and unzip softwares BWA BWA.tar
curDir=($PWD)
bwaSoftwareTar=${bwaSoftwareLink##*/}
bwaIndexTar=${bwaIndexLink##*/}
bwaDir=$curDir/${bwaSoftwareTar%%.*}/
bwaIndex=$curDir/${bwaIndexTar%%.*}/$bwaIndexName

if [ ! -e "$bwaSoftwareTar" ]
then 
    echo "BWA tar file is not transferred!"
#    exit 1
fi

if [ ! -e "$bwaIndexTar" ]
then 
    echo "BWA Index file is not transferred!"
#    exit 1
fi


tar -xvzf $bwaSoftwareTar
rm -rf $bwaSoftwareTar
tar -xvzf $bwaIndexTar
rm -rf $bwaIndexTar



#BWA alignment
if [ -e "${dataDir}/${dataName}.fastq" ]
then
    scp ${dataDir}/${dataName}.fastq ${curDir}/${dataName}.fastq
    $bwaDir/bwa aln -n $nBWA -o $oBWA -t $tBWA -q $qBWA -l $lBWA -k $kBWA $bwaIndex $curDir/${dataName}.fastq >$curDir/$dataName.sai
    $bwaDir/bwa samse -n $mBWA $bwaIndex $curDir/$dataName.sai $curDir/${dataName}.fastq | $bwaDir/xa2multi.pl >$curDir/$dataName.tmp.sam

elif [ -e "${dataDir}/${dataName}.fastq.gz" ]
then
    scp ${dataDir}/${dataName}.fastq.gz $curDir/${dataName}.fastq.gz
    $bwaDir/bwa aln -n $nBWA -o $oBWA -t $tBWA -q $qBWA -l $lBWA -k $kBWA $bwaIndex <(zcat $curDir/${dataName}.fastq.gz) >$curDir/$dataName.sai
    $bwaDir/bwa samse -n $mBWA $bwaIndex $curDir/$dataName.sai <(zcat $curDir/${dataName}.fastq.gz) | $bwaDir/xa2multi.pl >$curDir/$dataName.tmp.sam
else
    echo "No ${dataName}.fastq or ${dataName}.fastq.gz exists!"
#   	exit 1
	
fi


##########################################################
# Find bad CIGAR read names      for DNase                                                                                                                                                                                                                                        
cat $curDir/$dataName.tmp.sam | awk 'BEGIN {FS="\t" ; OFS="\t"} ! /^@/ && $6!="*" { cigar=$6; gsub("[0-9]+D","",cigar); n = split(cigar,vals,"[A-Z]"); s = 0; for (i=1;i<=n;i++) s=s+vals[i]; seqlen=length($10) ; if (s!=seqlen) {print $0} }' > $curDir/$dataName.tmp.sam.badCIGAR
#| sort | uniq 

# Remove bad CIGAR read pairs                                                                                                 

if [[ $(cat $curDir/$dataName.tmp.sam.badCIGAR | wc -l) -gt 0 ]]
then
    cat $curDir/$dataName.tmp.sam  | grep -v -F -f $curDir/$dataName.tmp.sam.badCIGAR >$curDir/$dataName.sam
    wc -l $curDir/$dataName.tmp.sam
    #wc -l $curDir/$dataName.sam
    rm -rf $curDir/$dataName.tmp.sam
    rm -rf $curDir/$dataName.tmp.sam.badCIGAR
#| samtools view -Su - | samtools sort - ${RAW_BAM_PREFIX}
else
    mv $curDir/$dataName.tmp.sam $curDir/$dataName.sam
#    samtools view -Su ${RAW_SAM_FILE} | samtools sort - ${RAW_BAM_PREFIX}
fi
###########################################################



if [ ! -d $outPath/$expName/preAlign ]
then
   mkdir -p $outPath/$expName/preAlign
fi
scp $curDir/${dataName}.sam $outPath/$expName/preAlign/${dataName}.sam
#scp $curDir/$dataName.badCIGAR $outPath/$expName/preAlign/${dataName}.badCIGAR
#rm -rf *${dataName}*

rm -rf BWA*
rm -rf bwa*
rm -rf *sai
rm -rf *sam
rm -rf *fastq*
rm -rf *tmp*
