#!/bin/bash
#
# 		ACCREDITATION
#
# 	All code, including frontend, backend, and handler (this script) was written by Aidan McPeake unless otherwise specified
#
#
#		ARGUMENTS
#
# 	One single argument is passed from the backend in the following JSON format: (Where "" denotes a string, and [] denotes a list)
# 		{"language": "", "code": "", "input": [ [] ]}
#
# 	Language refers to the programming language, i.e. python. It is used to determine which commands to execute to compile the user-provided code
#
# 	Code is the aforementioned user-provided code. Is is sent as an escaped string
#
# 	Input refers simply to sets of input which are to be piped into the given code via stdin redirection (See checkComp() function)
#
# 	This program returns JSON in the form:
#		{"status": "pass|fail", "stderr":[ "" ], "output": [ [] ]}
#
#
#		PROCESS
#
#	1. Backend passes input as JSON to this script
#	2. Input is parsed into required fields (language, code, input)
#	3. Code is compiled according to which language it is written in
#	4. If input is present, pipe test input and parse result into sets of output
#	5. Errors, output, etc. is parsed into a JSON string and returned to backend
#
#
# 		GLOBAL DECLARATIONS

STATUS="pass"	# Flag to determine the success of the program compilation
rm stderr &> /dev/null

#		FUNCTIONS

buildJSON() { # buildJSON(status = "$STATUS", output = "$OUTPUT") | Takes gathered variables and builds them into a json string which is returned to the backend
	local status="${1:-}"
	local output="${2:-}"
	local stderr="$(cat stderr 2> /dev/null | tr -d '\n' | tr -s '⠀' ',')" # Get the errors stored in stderr file and replace the newlines with commas

	local json="{"
	json+="\"status\":\"$status\""

	if [ ! -z "$output" ] # If the variable "output" is set...
	then
		json+=", \"output\":[ $output ]" # Add it to our json string
	fi

	if [ ! -z "$stderr" ]
	then
		json+=", \"stderr\":[ ${stderr%?} ]" # %? removes the last character from the string (which is an invalid ',')
	fi
	
	json+="}"
	
	if [ "$(parseJSON "$json" '.')" ] # Validate JSON before returning
        then
		echo -e "$json"
	else
		echo false
	fi
}

parseJSON() { # parseJSON(json, filter = '.') | Parse JSON using jq and return the values found by the given filter or false if filter fails
	local json="${1:-$json}"
	local filter="${2:-.}"
	filter+=" // empty"
	local result="$(echo "$json" | jq -r "$filter" 2> /dev/null || echo false)"
	echo -e "$result"	
}

checkComp() { # checkComp(command, time = 30, input = '')  | Pass a series of inputs, run the code on a timer to catch hanging and return the outputs in form ["x1", "y1", "z1"], ["x2", "y2", "z2"]...
	local command="$1"
	local time=${2:-30} # Evaluates to $1 if $1 is set and not null and defaults to 30 otherwise
	local input="${3:-}"
	local results # Must be declared separately to avoid sweeping of exit codes
	if [ -z "$input" ]
	then
		results="$(timeout $time $command 2>&1)"
	else
		results="$(timeout $time $command <<< "$(echo -e "$input")" 2>&1)"
	fi
	local status=$?
	if [ "$status" = 124 ]
	then 
		sendErr "Program hangs. Incorrectly waiting for input?"
		echo false
	
	elif [ "$status" != 0 ]
	then
		sendErr "Program failed to compile"
		sendErr "$results"
		echo false
	
	elif [ ! -z "$results" ]
	then
		local numLines="$(echo -e "$results" | wc -l)"
		for (( i = 1; i <= numLines; i++ ))
		do
			local result="$(echo -e "$results" | awk -v i="$i" 'BEGIN{ RS = "" ; FS = "\n" }{print $i}')"
			if [ ! -z "$result" ]
			then
				case+="$(jq -aR . <<< $result)"

				if [ $i -ne $numLines ]
				then
					case+=", "
				fi
			fi
		done
		if [ ! -z "$case" ]
		then
			echo "[$case]"
		fi
	fi
}

sendErr() { # sendErr(*strings) | Pipe given strings to stderr
	if [ -z "$1" ]
	then
		read str
	else
		str="$@"
	fi
	echo "$(jq -aR . <<< "$(echo "$str" | awk '{printf "%s\\n", $0}')")⠀" >> stderr # Append at the end of the message to distinguish newlines from the intended end of a message
}

testInput() { # testInput(json, command) | Take input, run through program and determine status, returns false if code hangs or fails to compile
	local json="$1"
	local command="$2"
	local numCases=$(parseJSON "$json" ".|length")
	local msg=""
	local status="pass"
	for (( iCase = 0; iCase < numCases; iCase++ )); # Iterate through cases, i.e. [3, 2] 
	do
			local numInputs=$(parseJSON "$json" ".[$iCase]|length")
			local iString=""
	
			for (( iInput = 0; iInput < numInputs; iInput++ ));
			do
				iString+="$(parseJSON "$json" ".[$iCase][$iInput]")\n"
			done

			local results="$(checkComp "$command" 5 "$iString")"
			if [ "$results" = false ]
			then
				status="fail"

			elif [ ! -z "$results" ]
			then
				msg+="$results"
			
				if [ $iCase -ne $((numCases - 1)) ]
				then
					msg+=", "
				fi
			fi
	done
	if [ "$status" = "fail" ]
	then
		echo false
	elif [ "$status" = "pass" ]
	then
		echo "$msg"
	fi
}



#	INPUT PARSING
# Since this input is coming from the backend we can assume correct formatting, however error checking will still be performed


if [ -z "$1" ] # Check if we have a first argument
then
	sendErr "No argument provided"
	STATUS="fail" 	# FAIL STATE: No input means we cannot compile
else
	json=$1
	if [ ! "$(parseJSON "$json" '.')" ]
	then
		sendErr "Malformed JSON received"
		STATUS="fail"
	
	elif [ "$STATUS" != "fail" ]
	then
		# 	JSON PARSING
		# Getting our arguments from the provided JSON 

		# code; User-provided code:

        	code="$(parseJSON "$json" ".code")"
        	if [ -z "$code" ]
        	then
	                sendErr "No code provided"
	                STATUS="fail"   # FAIL STATE: No code means we have nothing to compile
		elif [ "$STATUS" != "fail" ]
		then
			# language; Programming language provided code is written in:
	
			language="$(parseJSON "$json" ".language")"
	
			if [ -z "$language" ] # If the function call returned false (i.e. field not found)
			then
				sendErr "No language provided"
				STATUS="fail"	# FAIL STATE: No language means we cannot compile
			elif [ "$STATUS" != "fail" ]
			then
	
				#	LANGUAGE PARSING
				# Given the selected language, prepare the necessary executables and remember the command needed to run our code
	
				if [ "$language" = "python" ]
				then
	        			echo -e "$code" > code.py # Outputs code to the required file
	        			cmd="python3.6 code.py" # Executable to run
	
				elif [ "$language" = "cpp" ]
				then
		        		echo "$code" > code.cpp
					error="$(g++ code.cpp 2>&1)"
					status=$?

					if [ $status != 0 ]
					then
						STATUS="fail"
						sendErr "Code failed to compile"
						sendErr "$error"
					else
						cmd="./a.out" # Executable to run
					fi
		
				elif [ "$language" = "bash" ]
				then
					echo -e "$code" > code.sh
					cmd="bash code.sh"

				elif [ "$language" = "java" ]
				then
					echo "$code" > code.java
					error="$(javac code.java 2>&1)"
					if [ $? != 0 ]
					then
						STATUS="fail"
						sendErr "Code failed to compile"
						sendErr "$error"
					else
						cmd="java "$(ls | grep '.class' | sed 's/.class//g')""

					fi
				else
		        		sendErr "Invalid language provided: $language"
					STATUS="fail"	# FAIL STATE: Invalid language means we cannot compile the code
				fi

				# input; Test inputs (Not necessary):

				input="$(parseJSON "$json" ".input")"

				if [ -z "$input" ]
				then # Simply compile and return output
					results="$(checkComp "$cmd" 5)"
				
				elif [ "$STATUS" != "fail" ]
				then	# Compile, run test inputs through program, compare to test outputs and return output
					results="$(testInput "$input" "$cmd")"	
						
				fi
				
				if [ "$results" = false ]
				then
					STATUS="fail"

				elif [ ! -z "$results" ]
				then
					OUTPUT+="$results"
				fi
			fi
		fi
	fi
fi
echo -E "$(buildJSON "$STATUS" "$OUTPUT")"
