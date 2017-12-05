# Introduction
ParDim - software, which provides the framework (front end) for a simple
procedure of creating pipeline by integrating different stages and paralleling
the execution for a number of analysed directories, based on HTCondor
environment.

In other words, if user has a script to run on condor for one directory,
which corresponds to a specific data set or experiment, ParDim implements runs
for multiple directories.  
*Note:* more about script is in the section
[Script designing for the ParDim](#script-designing-for-the-pardim)

ParDim provides tools to manage a workflow of scripts, download and prepare data
for runs (section [Built-in Download stage](#built-in-download-stage)), and a
great reporting function to get a status of running jobs
(section [ParDim installation and execution](#pardim-installation-and-execution)).

Construction of a pipeline is completed in an intuitive description of
stages in a text file, with ability to include/exclude a specific stage by
changing a value of just one argument - execute. Such structure allows to
keep all information in one text file and control the workflow without
deleting chunks of parameters. As an example, pipeline with stage1 -> stage3,
looks like:

--------------------------------------------------------------------------------

\#\#[ stage1 ]\#\#  
execute &nbsp;&nbsp;&nbsp;&nbsp; true  
...

\#\#[ stage2 ]\#\#  
execute &nbsp;&nbsp;&nbsp;&nbsp; false  
...

\#\#[ stage3 ]\#\#  
execute &nbsp;&nbsp;&nbsp;&nbsp; true  
...

--------------------------------------------------------------------------------

ParDim provides all necessary information about a previous stage of a pipeline
to a next stage using text files. It controls that results of a stage are
transferred in a right directory in an organised way (according to a stage name).

An important feature is that ParDim sends result of successfully analysed directories
to a next stage for an analysis and keep records of unsuccessful directories for
every stage of a pipeline.


# ParDim installation and execution

## Installation
1. To install the ParDim framework go in a directory where you would like to
   install software:
   ``` bash
   cd "/path/to/softwareDirectory"
   ```
   2. Download the current version of the ParDim from the GitHub repository:
   ``` bash
   git clone git@github.com:JurijsNazarovs/ParDim.git
   ```
3. Add following lines in your .bash_profile file (should be in your $HOME path):
   ``` bash
   export PATH="/path/to/softwareDirectory/ParDim/:$PATH"
   ```

Now you have an access to three functions from any directory:
1. ParDim.sh - ParDim framework
2. MakeArgsFile.sh - creates a template for an argument file
3. MakeReport.sh - provides an information about pipeline running status

## Execution
In this subsection we assume that the Pardim framework is installed.

### ParDim.sh
ParDim.sh is ParDim framework, which constructs a pipeline based on argsFile,
checks that all relative input provided in argsFile is valid, and prepare
resulting directories.

ParDim.sh is executed as:  
ParDim.sh "argsFile" "isSubmit", where:

1. argsFile - path to a text file with constructed pipeline and relative
   arguments.

   *Note:* default value is args.ParDim in a root directory of ParDim.sh
2. isSubmit  - a variable with values true/false.
   If value is false, then everything is prepared to run the pipeline, but
   does not run, to test the structure to make sure everything is OK.

   *Note:* default value is true, which means run the whole pipeline.

### MakeArgsFile.sh
MakeArgsFile.sh creates a template for an argument file for ParDim.sh, based
on a list of stages of a pipeline. Since it is a template, user still has to
fill necessary gaps.

MakeArgsFile.sh is executed as:  
MakeArgsFile.sh "argsFile" "isAppend" "stage1" ... "stageN", where:

1. argsFile - path to a text file with constructed pipeline and relative
   arguments.

   *Note:* default value is args.list in a root directory of ParDim.sh
2. isAppend - a variable with values true/false.
   true  - append to existing argsFile without creating a head for ParDim.sh
   false - rewrite the whole file
3-. different names of stages in order of required execution

   *Note:* default value is just ParDim stage, to create necessary arguments
   to run the ParDim. More details in the section [ParDim Stage](#pardim-stage).

*Note:* for the stage with the name Download, ParDim creates different set of
arguments, since it is a built-in function.

### MakeReport.sh
MakeReport.sh provides an information about the specific stage of a pipeline,
like completed jobs, completed directories and etc. The full output is described
below.

MakeReport.sh is executed as:  
MakeReport.sh "stageName" "jobsDir" "reportDir" "holdReason" "delim", where:

1. stageName - name of a stage of which to get summary. If it is empty, then
               report for all stages is created automatically.  
               Default is empty.
2. jobsDir - the working directory for the task, specified in ParDim.
3. reportDir - directory to create all report files.  
               Default is report.
4. holdReason - reason for holding jobs, e.g. "" - all hold jobs, "72 hrs".  
                Default is "".
5. delim - delimiter to use for output files.  
           Default is , .

Output of MakeReport.sh is 9 files for multi-mapping scripts (1-9) and
6 files for single-mapping scripts (1-6):
1. *.time.list - timing relative to a specific stage
2. *.queuedJobs.list - queued jobs
3. *.compJobs.list - completed jobs
4. *.notCompJobs.list - currently not completed jobs
5. *.holJobsReason.list - holding lines given reason $holdReason
6. *.holdJobs.list - jobs on hold given reason $holdReason
7. *.summaryJobs.list - summary info about directories
8. *.notCompDirs.list - path to not completed directories
9. *.compDirs.list - path to completed directories

*Note:* one of the output files of MakeReport.sh is a list of not completed
directories. If you want to rerun an analysis of these directories after some
possible changes, you can submit the path to this list as a selectJobsListPath
argument in ParDim. More details are in the section [ParDim stage](#pardim-stage).


# Pipeline construction
To construct a pipeline - combination of stages, the argument file (text file)
is filled with specific syntax for a stage description.

## Required input
There are 3 required arguments to describe a pipeline stage
  1. stageName - provided in a pattern (*S* - any number of spaces):
     *S*##[*S*stageName*S*]##*S*
     
     *Note:* stageName contains no spaces!
  2. execute - a variable with values true/false. Indicates, if a stage
     should be executed or not. If the stage is not executed, it is just skipped.
     So, there is no need to delete it from the argument file.

     *Note:* if value is not true, task is not executed and warning appears.
  3. script - path to the script, which is executed to construct a DAG.
  
     *Note:* if not full path is provided, then path is assumed to be relative
     to a directory, where the ParDim is executed.
     
## Additional input
  1. map - argument with 2 values: multi/single. Type of a stage (more examples 
     later).
  2. args - path to an argument file, which is used for a script.
     If the argument is empty, then the current file with a description of a
     pipeline is used for a script.  
     That means, that in the description of a stage you can provide
     all other necessary information for a script, or create another file
     and provide path to that file here.
     
     *Note:* if not full path is provided, then path is assumed to be relative 
     to a directory, where the ParDim is executed.
  3. transFiles - path to all files, split by comma (and spaces), which are used
     by a script. For example, if you have some libraries to send, you can
     add them here.
     
     *Note:* if not full path is provided, then the dirname of a script is
     considered as a root path of transFiles.
  4. relResPath - path for results relative to a part of the pipeline or dataPath.
     Possible values are: previous/next stageName and dataPath.
     
     That is, results for current stage are saved in results directory of a
     stage specified in relResPath.
     
     **Example**: there is data in dataPath, and we need to create new additional
     data in same directory. So, that next stage can read original + new data
     from dataPath (or any stages). Then relResPath is dataPath.

     *Note:* if nothing is provided, then relResPath is resPath/stageName.

*Note:* ParDim.sh provides an error if something is wrong with values in argumetns:
script, args, transFiles, and relResPath.

*Note:* files corresponding to arguments "args" and "script" are transferred
automatically.

## Example with all possible arguments
\#\#[ stageName ]\#\#  
execute &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; true/false  
map &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; single/multi  
script &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; /path/to/script  
args &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; /path/to/argument/file/for/script  
transFiles &nbsp;&nbsp;&nbsp; /path/to/different/files/to/transfer/using/,  
relResPath


# ParDim Stage
In argsFile, there are 4 available arguments for the ParDim to initialise
the pipeline. Variables have to be specified after the label: \#\#[ ParDim.sh ]\#\#
   
1. dataPath - path to analysed data or resulting path for download stage
   (later about that). The path is used to construct a list of analysed
   directories.
2. resPath - path to results of the whole pipeline.
   By default every stage creates its own directory corresponding
   to a stage name. But no default value for resPath.
3. jobsDir - temporary directory for all files generated by ParDim.
   Default is to create a temporary unique directory dagTestXXXX .
4. selectJobsListPath - initial list of directories for the analysis.
   Can be empty.

*Note:* in a majority of cases by providing 2 arguments: resPath and
either dataPath or selectJobsListPath, ParDim works fine and ready to construct
a pipeline. However, there are different possible combinations of arguments,
which are described below.

## Possible combinations of arguments
1. Default values - these rules are applied first, so, the values assigned
   here are used in steps 2-4
   - if [jobsDir] is empty, then a directory with unique name dagTmpXXXX
     is created
   - if [resPath] is empty, but [dataPath] is not, then resPath = dirname(dataPath)
   
2. If there is the Download task or [dataPath] is used as [relResPath] for any
   stage, then
   - [dataPath] has to be provided with ability to write
   
3. If first stage is single-mapping, then following arguments have to be provided:
   - [resPath]
   - [jobsDir]

4. If first stage is multi-mapping, then following arguments have to be provided:
   - [resPath]
   - [jobsDir]
   - [dataPath] or [selectJobsListPath]


# Script designing for the ParDim
The flow of ParDim is dedicated to 2 steps:
    - construct a DAG file (let call a script to construct a DAG file as DagMaker)
    - execute a constructed DAG file
Thus, to design a stage for the ParDim, user has to provide a script - DagMaker,
which creates a DAG condor file, and ParDim handles its execution. 

Depending on a mapping value of a stage different arguments are passed to a
DagMaker (but almost the same). Thus, while designing a script (DagMaker for stages),
user has to write it in a way to accept these arguments in the same order.
In following subsections details for specific stages are provided.

*Note:* DagMaker has to be able to read all necessary arguments to construct a
DAG from a text file (value in an argument args). It can be done by using a ParDim
function ReadArgs. More details in the subsection
[Useful functions](##useful-functions).

## Difference in arguments between single-mapping and multi-mapping scripts
In a multi-mapping script there are two more arguments compare to a
single-mapping script: *resDir* and *transOut*. 

The difference is because the ParDim expects that results of a DAG are returned
in a tar file in a specific directory, where later ParDim untar it.

ParDim expects that in single-mapping scripts, a DagMaker developer provides
unique names to tar files and directories with results to avoid an overlap of
tared and untared files and directories.

However, since multi-mapping scripts are executed for several directories, to
avoid an overlap the ParDim takes care of a directory with results - argument
resDir, and a unique name of a tar file - argument transOut.

## Single-mapping scripts
Single-mapping scripts are designed to construct a DAG file based on the
specific argument (file), which is most likely has to be pass using args in a
description of a stage or with transFiles argument.  Usually, it is some sort of
prescripts before a multi-mapping script.

### Examples
  1. Download files according to a list of links. In this case a text file -
     list of links, can be transfered using an argument transFiles. The DAG file
     consists of independent jobs, where every job downloads a file according to
     a specific link.

     *Note:* this is a short description of the built-in Download stage of ParDim.
     More details are in the section 
     [Built-in Download stage](#built-in-download-stage).
  2. Assume we have a text file with N rows, where N rows contain information
     about M IDs. We would like to analyse every ID separately. In this case the
     argument transFiles is a path to a text file. The DAG file consists of M
     independent jobs, where every job creates a directory and saves the part of
     a file corresponding to one of M IDs. Thus, creating an input for a
     multi-mapping stage.

### DagMaker arguments
Following arguments are provided for a single-mapping DagMaker script by ParDim:

  1. argsFile - a text file with arguments necessary for a DagMaker.
     This is a file, which you specify as a value in args in a stage description.

     *Note:* if nothing is specified, the main file with arguments, where the
     structure of a pipeline is described, is used.
  2. dagFile - a name of a DAG file which is submit in a second step. DagMaker
     has to use a value of this variable exactly, without any manipulations.
     For example, to create a file just use: printf "" > "$dagFile".

     *Note:* ParDim returns the dagFile to a submit server.
  3. jobsDir - a working directory, where DagMaker saves all necessary files
     for DAG submission. DagMaker has to use a value of this variable exactly,
     without taking the full path or any other manipulations.

     *Note:* ParDim returns the directory to a submit server.
  4. resPath - path where results are saved. Below is a suggested chunk of code
     for a DagMaker to save results in the "$resPath":
     
     ---------------------------------------------------------------------------
     
     conFile="$jobsDir/Name.condor"  
     jobId="$uniqJobId" #can be an iterator to count jobs  
     
     printf "JOB  $jobId $conFile\n" >> "$dagFile"  
     printf "VARS $jobId transOut=\"$jobId.tar.gz\"\n" >> "$dagFile"  
     printf "VARS $jobId transMap=\"\$(transOut)=$resPath/\$(transOut)\"\n"\  
     \>\> "$dagFile"
     
     ---------------------------------------------------------------------------
     
     *Note:* structure of a condor file "$conFile" and an executed file is
     provided in the subsection
     [Structure of a condor file](##structure-of-a-condor-file) and
     [Structure of an execution file](##structure-of-an-execution-file)
     respectively.

     *Note:* value of transOut has to be passed to an execution file and directory
     with results has to be tared with a name corresponding to a value of
     transOut.
     
  5. selectJobsListInfo - file with all information about results of a previous
     stage, if a previous stage exists.

     *Note:* Structure of file is provided in the subsection
     [Structure of selectJobsListInfo and inpDataInfo](##structure-of-selectjobslistinfo-and-inpdatainfo)
     
### Deactivate directory for future analysis
ParDim is designed to proceed analysis of future stage just with successfully
completed directories on current stage. In case of Multi-mapping script ParDim
can trace automatically which directories are successful in an analysis. However,
with Single-mapping scripts to avoid the specific directory from an analysis,
the developer of a stage should create a file "RemoveDirFromList" 
(ex. in bash: touch RemoveDirFromList).

As an example, the Download stage creates a file RemoveDirFromList in case
if any of files for a directory is not downloaded. Then the whole directory
is skipped for further analysis.
     
## Multi-mapping scripts
Multi-mapping scripts are designed to construct a DAG file based on information
about a specific directory, so that script is executed for every of analysed
directories independently.

### Examples
  1. alignment of fastq files for an experiment
  2. peak calling for an experiment
  3. trimming for an experiment

### DagMaker arguments
Following arguments are provided for a multi-mapping DagMaker script by ParDim:

  1. argsFile - a text file with arguments necessary for a DagMaker.
     This is a file, which you specify as a value in args in a stage description.

     *Note:* if nothing is specified, the main file with arguments, where the
     structure of a pipeline is described, is used.
  2. dagFile - a name of a DAG file which is submit in a second step. DagMaker
     has to use a value of this variable exactly, without any manipulations.
     For example, to create a file just use: printf "" > "$dagFile".

     *Note:* ParDim returns the dagFile to a submit server.
  3. jobsDir - a working directory, where DagMaker saves all necessary files
     for DAG submission. DagMaker has to use a value of this variable exactly,
     without taking the full path or any other manipulations.

     *Note:* ParDim returns the directory to a submit server.
  4. resPath - path where results are saved. Below is a suggested chunk of code
     for a DagMaker to save results in the "$resPath":
     
     ---------------------------------------------------------------------------
     
     conFile="$jobsDir/Name.condor"  
     jobId="$uniqJobId" #can be an iterator to count jobs  
     
     printf "JOB  $jobId $conFile\n" >> "$dagFile"  
     printf "VARS $jobId transOut=\"$transOut.jobId.tar.gz\"\n" >> "$dagFile"  
     printf "VARS $jobId transMap=\"\$(transOut)=$resPath/\$(transOut)\"\n"\  
     \>\> "$dagFile"
     
     ---------------------------------------------------------------------------
     
     *Note:* structure of a condor file "$conFile" and an executed file is
     provided in the subsection
     [Structure of a condor file](##structure-of-a-condor-file) and
     [Structure of an execution file](##structure-of-an-execution-file)
     respectively.

     *Note:* value of transOut has to be passed to an execution file and directory
     with results has to be tared with a name corresponding to a value of
     transOut.
     
     *Note:* in contrast to a single-mapping script the transOut variable depends on
     a $transOut variable, which is described under number 7 in the current list.
     
  5. inpDataInfo - file with all information about results of a previous
     stage for the same directory (specific analysed directory and not for
     all of them as in single script).

      *Note:* Structure of file is provided in the subsection
     [Structure of selectJobsListInfo and inpDataInfo](##structure-of-selectjobslistinfo-and-inpdatainfo)

  Following arguments are provided to a DagMaker just to pass them further in an
  execution file.  
  
  6. resDir - directory to save results, equals to a name of analysed directory.
  DagMaker has to pass a value of this variable exactly, without taking the full
  path or any other manipulations and should be used same way in an execution
  file.  
  
  7. transOut - an unique name of a tar file to tar $resDir in an execution file.

## Structure of a condor file
In both cases of mapping scripts we specify transOut and transMap as variables
for a specific job. So, "$conFile" description is:

--------------------------------------------------------------------------------

...  
transfer_output = $(transOut)  
transfer_output_remaps = "$(transMap)"  
arguments = "'arg1', 'arg2', '\$(transOut)', ...,
             'resDir - in case of multi-mapping script'"  
...

--------------------------------------------------------------------------------

## Structure of an execution file
In an execution file results have to be tared with a name corresponding
to a value of transOut variable. That is, in an execution file you have to have
a variable like outTar=$3, where 3 - corresponds to a position of transOut in 
arguments in condor file (see above). Then do:

``` bash
tar -czf "$outTar" "$dirWithAllresults ($resDir in case of multi-mapping script)"
```

## Structure of a selectJobsListInfo and an inpDataInfo

The difference between a selectJobsListInfo and an InpDataInfo is that first file
is a combination of a second file, but for all directories in a resulting
directory of a previous stage. While the InpDataInfo contains information from a
previous stage just about single analysed directory. The InpDataInfo structure is:

--------------------------------------------------------------------------------

/path/to/directory/or/subdirectory:  
fileName1  &nbsp;&nbsp;&nbsp;&nbsp; size in bytes &nbsp;&nbsp;&nbsp;&nbsp;
s &nbsp;&nbsp;&nbsp;&nbsp; linkName1  
....  
fileNameN  &nbsp;&nbsp;&nbsp;&nbsp; size in bytes &nbsp;&nbsp;&nbsp;&nbsp;
s &nbsp;&nbsp;&nbsp;&nbsp; linkName1  

--------------------------------------------------------------------------------

*Note:* the space above is '\t' - tabular.
*Note:* Since it is possible that data might be a soft link, fileName - name of
a real file where the link point to (target file). Size is size of the real file.
s - symbol which means if current file is a link or not. linkName - name of a
soft link, that is, a real file in sub-directory. If file is link, then fileName
is relative path, which looks like ../anotherSubDir/anotherFileName. While, a
linkName is just a name without relative path.
*Note* If file is not a link, then you will see just 2 columns instead of 4.

## Useful functions

### ReadArgs
Location: ParDim/scripts/funcListParDim.sh
ReadArgs - reads arguments from a file in a section according to a label
\#\#[ scrLab ]\#\# and substitutes values in a code.

For example, in an argument file we have a line:
foo &nbsp;&nbsp;&nbsp;&nbsp; 23  
Then in a code after function ReadArgs is called, "echo $foo" returns 23.

Input:
 1. argsFile - file with arguments
 2. scrLabNum - number of script labels
 3. scrLabList - vector of names of labels (scrLab) to search for arguments
    according to the pattern: \#\#[    scrLab  ]\#\# - Case sensitive. Might be
    spaces before, after and inside, but cannot split scrLab, \#\#[, and ]\#\#.
    If scrLab = "", the whole file is searched for arguments, and the last
    entry is selected.
 4. posArgNum - number of arguments to read
 5. posArgList - possible arguments to search for
 6. reservArg  - reserved argument which can't be duplicated
 7. isSkipLabErr - binary variable true/false. If true, then no error appeared
    for missed labels, if other labels exist. No arguments are read.

Possible behaviour:
- If a variable is defined before reading file, and in a file it is empty,
  then original value remains.
- If an argument repeats several times, then warning appears and last value is
  assigned.
- If an argument is empty after reading a file, a warning appears.
- If no labels are provided, the whole file is read.
- If label appears several times, then error.
- If label cannot be found while other labels exist, then error (or not if
  isSkipLabErr = true)
- If a file has no sections (scrLab), then the whole file is read
    
How to write an argsFile:  
argumentName(no spaces) argumentValue(spaces, tabs, any symbols)  
That is, after first column space has to be provided!

### PrintArgs
Location: ParDim/scripts/funcListParDim.sh  
PrintArgs - prints arguments for a specific script in a beautiful way.

Input:
 1. scrName - name of a script to print arguments for. Can be an empty. It just
    influences a header message.  
 2-. posArgs - vector of arguments to print values of.

Usage: PrintArgs "$scriptName" "${posArgs[@]}"

### makeCon.sh
Location: ParDim/scripts/makeCon.sh  
makeCon.sh - creates a condor submit file, depending on parameters.

Description of input arguments is provided in makeCon.sh in the section "Input".


# Built-in Download stage
To download files (to fill a dataPath) ParDim provides a stage Download.

The Download stage of the ParDim downloads unique files from a table and
distribute them in right directories. The Download stage is written for HTCondor
environment, it downloads every file on separate machine simultaneously, which
boosts downloading process. The further analysis is executed just for directories
where all files were downloaded successfully.

The Download stage provides several useful options:  
 1. Save files with original names or based on relative name according to the
    pattern: "relativeName.columnName.extensionOfRelativeName"
    e.g.: relativeName = enc.gz, columnName = ctl => output = enc.ctl.gz  
    *Note:* names for relativeName column is not changed
 2. Combine several files in one output
 3. Create links for same files in different directories to save space.

*Note:* the name of the stage is reserved for a built-in ParDim script
boostDownload.sh. If you would like to use your own downloading script, you
have to use another name of the stage, except ##[ Download ]##.

## Start downloading
To execute the Download stage, there should be 3 arguments in a ParDim argsFile.

--------------------------------------------------------------------------------

\#\#[ Download ]\#\#  
execute &nbsp;&nbsp;&nbsp;&nbsp;&nbsp; true  
transFiles &nbsp;&nbsp; /path/to/table/with/urls  
args &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; /path/to/argsFile/for/Download/stage  

--------------------------------------------------------------------------------

The description of a table in "transFiles" is provided in the subsection
[Structure of an input table](##structure-of-an-input-table) below.
The description of a file in "args" is provided in the subsection
[Argument file](##argument-file) below.

*Note:* for the Download stage arguments: script, map, and relResPath are ignored.
*Note:* the Download stage saves data in dataPath.


## Structure of an input table
- First row of a table is considered as a header and defines names of columns.
- One of columns contains basename of directories, where files are supposed to 
  be saved. The number of column is set in an argument tabDirCol.
- Other columns contain URLs to download files. One column corresponds to a 
  specific type of downloading files. For example, column of control files.
- To combine files in one output, links in a column have to be split by a value
  in an argument tabDelimJoin.

*Note:* since Download stage is developed for HTCondor environment, it is necessary
to detect size for downloading files. The Download stage does it automatically,
but if this information is provided in a table, then argument tabIsSize should
be set as true.

### Example of a table
experiment,chip,ctl,dnase  
ENCSR473SUA,URL\_Chip,URL\_Ctl1;URL\_Ctl2,URL\_Dnase  
ENCSR473SUB,URL\_Chip,URL\_Ctl1,URL\_Dnase  

where , - delimeter for a table (argument tabDelim)
      ; - delimeter to join files (argument tabDelimJoin)

## Argument file
 1. tabPath - path to an input table with links to files.
 2. tabDelim - delimeter used in a table.  
               Default value is ','.		
 3. tabDelimJoin - delimeter to use in a table to join files.  
                   Default value is ';'.
 4. tabDirCol - index of column with directory.  
                Default value is 1.
 5. tabIsOrigName - true/false, Indicates if use original names or not.  
                    Default value is false.
 6. tabRelNameCol - column to use as a base for names if tabOrigName=false.  
                    Default value is 2.
 7. tabIsSize - true/false. Indicates if table has size of files or not.  
                Default value is false and size detected automatically. 
 8. nDotsExt - number of dots before extension of download files starts.  
               Default value is 1.
 9. isCreateLinks - true/false. Indicates if create links of same files among
                    experiments to save space.
                    Default value is false.
 10. isZipRes - true/false. Indicates if zip resulting files when transfer
                to the dataPath. It effects time of running the Downloading part,
                but not the final result. If you believe that your files do not 
                decrease size a lot after compression, for example, downloaded 
                file is already compressed, then put false. It will accelerate
                the Download part of a pipeline.
               
