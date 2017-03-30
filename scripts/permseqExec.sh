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
chipSAM=$2
dnaseSAM=$3
expName=$4
folderName=$5
curDir=($PWD)
permseqPara=("rLink" "csemLink" "perlLink" "chromRefLink" "outPath" "chipThres")

for i in ${!permseqPara[@]}
do
    eval ${permseqPara[$i]}="$(getValue "$argsFile" "${permseqPara[$i]}")"
done

#Transfer Data and software
scp $outPath/$expName/preAlign/$chipSAM $curDir/$chipSAM
scp $outPath/$expName/preAlign/$dnaseSAM $curDir/$dnaseSAM



chromRef=${chromRefLink##*/}
rTar=${rLink##*/}
csemTar=${csemLink##*/}
perlTar=${perlLink##*/}
rDir=$curDir/${rTar%%.tar.gz}/bin
csemDir=$curDir/${csemTar%%.tar.gz}
perlDir=$curDir/${perlTar%%.tar.gz}

if [ ! -e "$rTar" ]
then
    echo "R is not transferred!"
#    exit 1
fi
if [ ! -e "$csemTar" ]
then
    echo "CSEM is not transferred!"
#    exit 1 
fi
if [ ! -e "$perlTar" ]
then
    echo "Perl is not transferred!"
#    exit 1
fi
if [ ! -e "$chromRef" ]
then
    echo "Chrom.ref is not transferred!"
#    exit 1
fi


tar -xvzf $rTar
tar -xvzf $csemTar
tar -xvzf $perlTar
 
rm -rf $rTar
rm -rf $csemTar
rm -rf $perlTar

if [ ! -d "$outPath/$expName/align/$folderName/" ]
then
     mkdir -p "$outPath/$expName/align/$folderName/"
fi


#Permseq Rscript
$rDir/R CMD BATCH "--args curDir="\'$curDir\'" rDir="\'$rDir\'" csemDir="\'$csemDir\'" perlDir="\'$perlDir\'" argsFile="\'$argsFile\'" chipSAM="\'${curDir}/${chipSAM}\'" dnaseSAM="\'${curDir}/${dnaseSAM}\'" chromRef="\'${curDir}/${chromRef}\'" " ${curDir}/permseqExec.R

scp *Rout $outPath/$expName/preAlign/$folderName.Rout
#scp *badCIGAR $outPath/$expName/preAlign/

chipTagAlign=${chipSAM%%.sam*}_permseq.${chipThres}.tagAlign
#remove duplicate
sort -k1 -k2 -k3  ${chipTagAlign} >${chipTagAlign}.sort
awk '!a[$1$2$3]++' ${chipTagAlign}.sort >${chipSAM%%.sam*}.nodup.tagAlign 

#zip tagAlign file
gzip ${chipSAM%%.sam*}.nodup.tagAlign

#Transfer back the output -- pending
mv $curDir/${chipSAM%%.sam*}.nodup.tagAlign.gz $outPath/$expName/align/$folderName/

rm -rf *tmp*
rm -rf *bad*
rm -rf *$chromRef*
rm -rf *tagAlign*
rm -rf *bam*
rm -rf *sam*
rm -rf *dnase*
rm -rf *Rdata*
rm -rf *BWA*
rm -rf *Permseq*
rm -rf *permseq*
rm -rf *chipmean*
rm -rf *txt
