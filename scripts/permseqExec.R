#Permseq R script
library(permseq)


#Read in csemDir, perlDir, rDir and argsFile
args <- (commandArgs(TRUE))
if(length(args)==0){
    stop("No arguments supplied.")
}else{
    for(i in 1:length(args)){
      eval(parse(text=args[[i]]))
    }
}
setwd(curDir)

#perl Directory and module
Sys.setenv(PERL5LIB=paste(perlDir, "/lib/", sep=""))
system("perldoc -l Statistics::Descriptive")


#read in argsList and identify the parameter by the row name
#Get the outPath to save the bam file and RData
argsMatrix <- data.frame(lapply(read.table(argsFile, head = FALSE), as.character), stringsAsFactors=FALSE)
argsPara <- argsMatrix[, 2]
names(argsPara) <- argsMatrix$V1

dnaseName <- sub("(.*?).sam", "\1", dnaseSAM)
priorProcess_DNase <- priorProcess(dnaseFile = dnaseSAM,
                                   dnaseName = dnaseName,
				   nBWA=as.numeric(argsPara["nBWA"]),
				   oBWA=as.numeric(argsPara["oBWA"]),
                                   tBWA=as.numeric(argsPara["tBWA"]),
				   mBWA=as.numeric(argsPara["mBWA"]),
                                   fragL = as.numeric(argsPara["fragL"]),
                                   AllocThres = as.numeric(argsPara["AllocThres"]),
                                   capping = as.numeric(argsPara["capping"]),
                                   outfileLoc = curDir,
                                   outfile = argsPara["outfile"],
                                   csemDir = csemDir,
		 	           chrom.ref = chromRef,
                                   saveFiles = argsPara["saveFiles"])

save.image(paste(curDir, "/priorProcess_DNaseHistone.Rdata", sep = ""))


priorGenerate_DNase <- priorGenerate(object = priorProcess_DNase,
                                     chipFile = chipSAM,
                                     maxHistone = as.numeric(argsPara["maxHistone"]),
                                     outfileLoc = curDir)

save.image(paste(curDir, "/priorGenerate_DNaseHistone.Rdata", sep=""))

readAllocate_DNase <- readAllocate(object = priorGenerate_DNase,
                                   outfileLoc = curDir,
                                   outputFormat = "tagAlign",
                                   chipThres = as.numeric(argsPara["chipThres"]),
			           chipFile = chipSAM)

save.image(paste(curDir, "/readAllocate_DNaseHistone.Rdata", sep=""))


