#!/bin/bash

#Do NOT Terminate terminate with a "/"
current_dir=$(pwd)
INPUT="$current_dir/Evaluation/Testcases/Input"
OUTPUT="$current_dir/Evaluation/Testcases/Output"

rm "A4-Marks.txt"
touch "A4-Marks.txt"
MARKSFILE="$current_dir/A4-Marks.txt"

echo "====================START==========================" >> $MARKSFILE
date >> $MARKSFILE

for filename in SUBMIT/*.cu;
do
	echo $filename
	# cd "${FOLDER}"
	
	ROLLNO=$(echo $filename | tail -1 | cut -d'.' -f1)
	ROLLNO=${ROLLNO#"SUBMIT/"}
	echo $ROLLNO
	LOGFILE=${ROLLNO}.log
		
	cd SUBMIT

	rm ${ROLLNO}.log
	# # cp require/our input files to stud's folder and build
	# cp ${ROLLNO}.cu main.cu
	# cp -r $INPUT .
	# cp -r $OUTPUT .
	
	nvcc "$ROLLNO.cu" -o main
	
	# If build fails? then skip to next stud
	if [ $? -ne 0 ] 
	then
		echo $ROLLNO,BUILD FAILED!
    	echo $ROLLNO,BUILD FAILED! >> $MARKSFILE # write to file     
		cd ../ # MUST
		continue
	fi

	for testcase in $INPUT/*; do 
		
		file_name=${testcase##*/}
		echo "$file_name"
		
		./main  $testcase  output.txt
		diff -w "$OUTPUT/$file_name" output.txt > /dev/null 2>&1
		exit_code=$?
		if (($exit_code == 0)); then
		  	echo "success" >> $LOGFILE
		else 
			echo "failure" >> $LOGFILE
		fi

		rm output.txt

	done
	
	SCORE=$(grep -ic success $LOGFILE) #Counts the success in log
	#! TOTAL=$(ls $INPUT/*.txt | wc -l)
	echo $ROLLNO,$SCORE "testcases passed"
	echo $ROLLNO,$SCORE "testcases passed" >> $MARKSFILE  # write to file 
	
	# IMPORTANT
	cd ../
done

date >> $MARKSFILE
echo "====================DONE!==========================" >> $MARKSFILE

