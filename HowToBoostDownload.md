This document describes how to use ParDim to download your files in a relatively
short period, by parralyzing the downloading among a network of computers - 
boostDownload. The minimum set of actions is described in the subsection 
[Minimum requirements](##minimum-requirements)


# 1. Create a main argument file
Create a text file "args.ParDim" or any other preferable name. Insert piece of 
text from [Minimum requirements](##minimum-requirements) to the file,
using text editor of your choice (emacs, vi, gedit, nano and etc):

## Minimum requirements
Use spaces or tabs to split values

--------------------------------------------------------------------------------
##[ ParDim.sh ]##
dataPath &nbsp;&nbsp;&nbsp;&nbsp;&nbsp; path\_where\_to\_save\_data  
jobsDir &nbsp;&nbsp;&nbsp;&nbsp;&nbsp; ./Download.ParDim  

##[ Download ]##
execute &nbsp;&nbsp;&nbsp;&nbsp;&nbsp; true  
transFiles &nbsp;&nbsp;&nbsp;&nbsp;&nbsp; path\_to\_file\_with\_links\_to\_download  
tabPath &nbsp;&nbsp;&nbsp;&nbsp;&nbsp; name\_of\_file\_with\_links\_to\_download  
exePath &nbsp;&nbsp;&nbsp;&nbsp;&nbsp; path\_to\_ParDim/scripts/exeDownload.sh  
-------------------------------------------------------------------------------

## Additional arguments - advanced
You can append additional arguments to a file above for more specification.

### Table specification
-------------------------------------------------------------------------------
1. tabDelim - delimeter used in a table.  
   Default value is ','.		
2. tabDelimJoin - delimeter to use in a table to split files, which has to be
   joined.  
   Default value is ';'.
3. tabDirCol - index of column with directory for files (e.g. experiment name).  
   Default value is 1.
4. tabIsOrigName - true/false, Indicates whether to use original names of files.  
   Default value is true.
5. tabRelNameCol - column to use as a base for names if tabOrigName=false. For example,
   we have 3 columns in a file with header: 1 - experiment, 2 - rep, 3 - ctl. 
   Then files from 3rd column will have names corresponding to names in a column 2 
   and add .ctl. Be careful, that if several files correspond to same base, just
   one will remain and other replaced. If you want to join several files, consider
   tabDelimJoin.  
   Default value is 2.
6. nDotsExt - number of dots before extension of download files starts. Important
   if using not original names. Then the column name will append before extension.  
   Default value is 1.
-------------------------------------------------------------------------------
   
### Technical arguments to save memory or increase speed of downloading
-------------------------------------------------------------------------------
1. tabIsSize - true/false. Indicates if table has size of files or not. This
   column might increase runs a little, if your table contains column with size
   near every ithe column with files. It is not necessary and ParDim detects
   size automatically, but if you have it, you have to provide true, otherwise
   downloading will not work.  
   Default value is false and size detected automatically. 
2. isCreateLinks - true/false. Indicates if create links of same files among
   directories to save space. If you use ParDim just to download files, then
   do not change this option.  
   Default value is false.
3. isZipRes - true/false. Indicates if zip resulting files when transfer
   to the dataPath. It effects time of running the Downloading part,
   but not the final result. If you believe that your files do not 
   decrease size a lot after compression, for example, downloaded 
   file is already compressed, then put false. It will accelerate
   the Download part of a pipeline.  
   Default value is True.
--------------------------------------------------------------------------------

# 2. Create a table with links to download

## Structure of an input table
- First row of a table is considered as a header and defines names of columns.
- One of columns contains basename of directories, where files are supposed to 
  be saved, e.g. name of experiments. The number of this column corresponds to an
  argument tabDirCol. Default value is 1.
- Other columns contain URLs to download files. One column corresponds to a 
  specific type of downloading files. For example, column of control files, with
  name ctl.
- To combine files in one output, links in a column have to be split by a value
  in an argument tabDelimJoin, default is ;.

### Example of a table
experiment,chip,ctl,dnase  
ENCSR473SUA,URL\_Chip,URL\_Ctl1;URL\_Ctl2,URL\_Dnase  
ENCSR473SUB,URL\_Chip,URL\_Ctl1,URL\_Dnase  

where , - delimeter for a table (argument tabDelim)
      ; - delimeter to join files (argument tabDelimJoin)
      
# 3. Start downloading
Finally, to start downloading just type: ParDim.sh args.Pardim

To see a progress, type: MakeReport.sh Download value\_of\_jobsDir reportDownload  
It creates directory reportDownload with all necessary information aobut downloading

Enjoy your fast downloading!
               
