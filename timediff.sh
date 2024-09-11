#!/bin/bash
#ARG=${1? Error. Please, provide the input file. Example: timediff.sh  filename}
echo " THIS SCRIPT CAN TAKE SOMETIME This script will process all sessions created on the server and ouput a csv fiel analysis of any delaysin login times etc, session can of course take a long but automated sesison on HANA shpould complete quickly"
inputfile=messages-20240819.txt
session_file=session.txt
outputfile=$inputfile-timedelays.csv
tempfile=temp.txt
function create_input () {
# echo "Processing $inputfile to temp file"
grep '.scope: Deactivated successfully.\|Started Session' $inputfile |sed 's/session-/End session-/g'  | sed 's/Started Session /Start session-/g' | sed -e 's/azlsapd9pdb02 systemd\[1\]://g'| sed 's/.scope:/ scope:/g'  > $tempfile

#echo " Sorting file"
# sort -o -b -k3 $tempfile 
}

function session_file (){
echo " Removing old session file"
rm $session_file
grep session- $tempfile | cut -d " " -f4 | cut -d "-" -f 2| uniq > $session_file
}
function session_array () {
# get all sessions not used 
readarray -t my_array  < <( grep session- $tempfile | cut -d " " -f4 | cut -d "-" -f 2| uniq)
#debug check array values 
#printf '%s\n' "${my_array[@]}"
}

#long no longer needed session=$(grep session-c11416098 filetest.txt | cut -d " " -f4 | cut -d "-" -f 2| uniq)

function csv_header (){
echo " Removing old output files"
rm $outputfile
echo login session,start time, end time , elapsed time in sec >> $outputfile
}

function process_session () {
cat $session_file | while read line   
#for value in "${my_array[@]}"
	do
	echo "Processing session $line"
	#get start end and end time
	start=$(grep $line $tempfile | grep Start  | cut -d " " -f 1 |  sed 's/T/ /g' | cut -d . -f 1)
	start_epoch=$(date -d "${start}" +"%s") 
	end=$(grep $line $tempfile | grep End  | cut -d " " -f 1 | sed 's/T/ /g' |  cut -d . -f 1)
	end_epoch=$(date -d "${end}" +"%s")
	user_name=$(grep $line $tempfile | grep Start  | cut -d " " -f 7  )
	#debug
	#echo $start
	#echo $start_epoch
	#echo $end 
	#echo $end_epoch
	#echo $session
	time_elapsed=$(($end_epoch-$start_epoch)) 
	#f [ $time_elapsed -gt 0 ]; then
	#fi
	echo "$line,$user_name,$start,$end,$time_elapsed" >> $outputfile
	done 
}

#main
csv_header
create_input
session_file
#session_array
process_session
