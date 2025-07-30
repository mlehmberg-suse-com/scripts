#!/bin/bash
#ARG=${1? Error. Please, provide the input file. Example: timediff.sh  filename}
#This script parses messages files and provides a CSV file output of the login session times present in CSV file format 
#Created by Marc Lehmberg , SUSE.

echo " THIS SCRIPT CAN TAKE SOMETIME This script will process all sessions created on the server and output a csv file for  analysis of any delays in login times etc."
inputfile=$1
session_file=session_id.txt
tmp_sessions_file=tmp_sessions.txt
timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
tempfile=temp.txt
uniq_tmp_session_file=tmp_session_file_uniq.txt


function create_input () {
	echo "================================================================================="
	echo "Processing $inputfile to temp file"
	#touch $tempfile
	#ls -l $tempfile
	grep '.scope: Deactivated successfully.\|Started Session' $inputfile |sed 's/session-/End session-/g'  | sed 's/Started Session /Start session-/g' | sed -e 's/azlsapd8pdb01 systemd\[1\]://g'| sed 's/.scope:/ scope:/g' > $tempfile
	echo "================================================================================="
	echo ""
#echo " Sorting file"
# sort -o -b -k3 $tempfile
}

function get_server_name (){
	echo "================================================================================="
	echo "Processing Server Name from $inputfile "
	servername=$(head -n 1 $inputfile | cut -d " " -f 2) 
	echo "Server Name to be analysed is $servername."
	echo "================================================================================="
	echo ""
}


function get_input_file (){
	echo "================================================================================="
	echo -n "Enter filename for analysis: "
	read inputfile
	echo ""
}

function create_outputfile (){
	#creates an output file with servername, input file and current timedate 
	outputfile=$servername-$inputfile-$timestamp.csv
	nonzero_outputfile=$servername-$inputfile-$timestamp-nonzero.csv
	debug_log=debug-$servername-$inputfile-$timestamp.log
	touch $outputfile
	touch $nonzero_outputfile
	echo "================================================================================="
	echo "Created output files for analysis"
	echo "================================================================================="
	echo ""
	}

function session_file (){
	grep session- $tempfile | cut -d " " -f5 | cut -d "-" -f 2| awk '!seen[$0]++' > $session_file
}

function cleanup_files (){
	echo "================================================================================="
	echo " Removing old session files $tempfile $session_file $uniq_tmp_session_file $tmp_sessions_file "
	rm $tempfile $session_file $uniq_tmp_session_file $tmp_sessions_file 2>/dev/null
	echo "================================================================================="
	echo ""
}

#function session_array () {
	#get all sessions not used
	#readarray -t my_array  < <( grep session- $tempfile | cut -d " " -f1 | cut -d "-" -f 2| uniq)
	#readarray -t my_array  < <( grep session- $tempfile | cut -d " " -f1 |  uniq)
	#debug check array values
	#printf '%s\n' "${my_array[@]}"
	#}

function csv_header (){
	#Add header to CSV file "
	echo login session,start time, end time , elapsed time in sec >> $outputfile
}


function create_sessions_file (){
	echo "Finding all sessions this may take a while  ......."
	cat $session_file | while read line
	do
        	#echo " Processing session $line"
        	grep $line $inputfile  |  grep Start | grep Session >> $tmp_sessions_file
        	grep $line $inputfile | grep session | grep "Deactivated successfully" >> $tmp_sessions_file
		# cut -d " " -f 1 |  sed 's/T/ /g' | cut -d . -f 1
	done
	#cleanup duplicate lines
	sort --stable  --key=1,2 $tmp_sessions_file |  awk '!seen[$0]++' > $uniq_tmp_session_file
}

function process_session () {
	cat $session_file | while read line
        do
        #get start end and end time
	start=$(grep "Started Session $line" $uniq_tmp_session_file  | cut -d " " -f 1 |  sed 's/T/ /g' | cut -d . -f 1)
	#start=$(grep $line $tempfile | grep Started | grep Session |  cut -d " " -f 1 |  sed 's/T/ /g' | cut -d . -f 1)
        start_epoch=$(date -d "${start}" +"%s")
        end=$(grep $line $uniq_tmp_session_file | grep "session-$line.scope: Deactivated successfully"  | cut -d " " -f 1 | sed 's/T/ /g' |  cut -d . -f 1)
        end_epoch=$(date -d "${end}" +"%s")
        user_name=$(grep $line $uniq_tmp_session_file | grep "Started Session $line"  |awk -F " " '{ print $NF}' | awk '{print substr($0, 1, length($0)-1)}')
        #debug
        echo "================================================================================="
	echo "Session ID: $line"
	echo "User Session started at $start"
        echo "Epoch time Start $start_epoch"
        echo "User Session ended at $end"
        echo "Epoch Time end: $end_epoch"
        echo "End Session ID: $line"
	echo "================================================================================="
	echo ""
	#DEBUG LOGS 
	#echo "$line zzzzz" >> $debug_log
	#echo "$line User Session started at $start" >> $debug_log
	#echo "$line Epoch time Start $start_epoch" >> $debug_log
	#echo "$line User Session ended at $end" >> $debug_log
	#echo "$line Epoch Time end: $end_epoch" >> $debug_log
	#echo "" >> $debug_log


	time_elapsed=$(($end_epoch-$start_epoch))
        #remove zero entries WIP 
	#f [ $time_elapsed -gt 0 ]; then
        #fi
        echo "$line,$user_name,$start,$end,$time_elapsed" >> $outputfile
	done
}
function no_zero_second_lines (){
	sed '/0$/d' $outputfile > $nonzero_outputfile

}
function  report_output_file () {
	echo "================================================================================="
	echo " Analysis files created in $(pwd) "
       	echo " All Sessions: $outputfile."
	echo " Non-zero second session: $nonzero_ouputfile."
	echo "================================================================================="

}

#main
clear
get_input_file
get_server_name
create_input
session_file
create_outputfile
csv_header
#session_array
create_sessions_file
process_session
#cleanup_files
no_zero_second_lines
report_output_file
