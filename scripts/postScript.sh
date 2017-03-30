#!/bin/bash
#===================================================================================================
# This is a POST SCRIPT for condor job, which "clean" files after job is done
# It is executed in the same directory as condor job.
# Example JOB 1 1.condor DIR dagTmp =>
# => job is executed in dagTmp
#===================================================================================================
file="$1"
task="$2"
inpPath="$3" #to create list of jobs

if [[ "${task,,}" = "jobslist" ]]; then
    ls -d "$inpPath/"* > "$file"
    exit 0
fi


if [ "${task,,}" = "tar" ]; then #${a,,} = lower case
	tar -xzf "$file"
	exFl=$?
	if [ $exFl -ne 0 ]; then
		echo "Cant untar $file"
		exit $exFl
	fi
fi

rm -rf "$file"
