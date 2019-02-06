#!/bin/bash
#
# 		ACCREDITATION
#
# All code, including frontend, backend, and handler (this script) was written by Aidan McPeake unless otherwise specified
#
#
#		ARGUMENTS
#
# One single argument is passed from the backend in the following JSON format:
# 	{"language": "", "code": "", "io" {}}
#
# Language refers to the programming language, i.e. python. It is used to determine which commands to execute to compile the user-provided code
#
# Code is the aforementioned user-provided code. Is is sent as an escaped string
#
# io refers to the test inputs/outputs. This value is technically optional but almost always used to some degree. It is in the form:: 
# 	{"given": [[]], "hidden": [[]]}
#
#
#		INFO
#
# Some challenges will have test inputs and expected outputs. For these challenges, sets of I/O will be provided to the user as examples, and some will be hidden from the user to prevent hard-coding. These sets of I/O are run through the program and used to determine the success of the challenge. Anything sent to STDOUT will be regarded as a success and anything sent to STDERR will be regarded as a failure.
#
# The backend determines the final result of the tests based on whether output is sent to stderr or stdout, as such we need to catch all output from execute commands and parse it ourselves before finally determining the status
#
# ${VAR1:-VAR2} -- evaluates to VAR1 if VAR1 has a value or VAR2 if not. This is used to set default values if none are given. The remainder of the code should be self explanatory for those familiar with bash
#
#
#		PROCESS
#1. Backend passes input as JSON to this script
#2. Input is parsed into required fields (language, code, io)
#3. Code is compiled according to which language it is written in
#4. If io is present, run test cases; Pipe test input and compare the actual output to the expected output.
#5. Output of compilation/test cases are parsed into JSON and returned to backend upon completion of the program
# 		GLOBAL DECLARATIONS

STATUS="pass" 	# Flag to determine the success of the program compilation
OUTPUT=""	# Output from corresponding 
rm stdout &> /dev/null
rm stderr &> /dev/null
#		FUNCTIONS
getJSON() { # getJSON(status = "fail", output = "", errors = "", tests = "")
	local status="${1:-fail}"
	local output="${2:-}"
	local stdout=$(cat stdout 2> /dev/null)
	local stderr=$(cat stderr 2> /dev/null)
	local json="{\"status\":\"$status\""
	if [ ! -z "$output" ]
	then
		json+=", \"output\":{ $output }"
	fi
	if [ ! -z "$stdout" ]
	then
		json+=", \"stdout\":\"$stdout\""
	fi
	if [ ! -z "$stderr" ]
	then
		json+=", \"stderr\":\"$stderr\""
	fi
	json+="}"
	echo -E "$json"
}

parseJSON() { # parseJSON(json, filter = '.')	| parse JSON using jq and return the given values
	local json="${1:-json}"
	local filter="${2:-.}"
	filter+=" // empty"
	local result="$(echo $json | jq -r "$filter")"
	echo -e "$result"	
}

checkHang() { # checkHang(command, time = 30, input = '')  | Run a command on a timer, return the STDOUT or False if it hangs longer than alloted
	local command="$1"
	local time=${2:-30} # Evaluates to $1 if $1 is set and not null and defaults to 30 otherwise
	local input="${3:-}"
	if [ -z "$input" ]
	then
		local result="$(timeout $time $command 2>> stderr || echo false)"
	else
		local result="$(timeout $time $command <<< "$(echo -e "$input")" 2>> stderr || echo false)"
	fi
	echo "$result"
}

sendErr() { # errcho(*strings) | Pipe given strings to stderr
	echo -e "$@" >> stderr 
}

sendOut() { # sendOut(*strings) | Pipe given strings to stdout
	echo -e "$@" >> stdout
}

testVals () { # testVals(json, command) | Take I/O, run through program and determine status
#	LOCAL DECLARATIONS
local json="$1"
local command="$2"
local numScopes=$(parseJSON "$json" ".|length")
local msg=""
for (( iScope = 0; iScope < numScopes; iScope++ )); # Iterate through scopes (i.e. "given"/"hidden") 
do
	local scope="$(parseJSON "$json" ".|keys[$iScope]")"
	msg+="\"$scope\": [ "
	local numCases=$(parseJSON "$json" ".[\"$scope\"]|length")
        for (( iCase = 0; iCase < numCases; iCase++ ));
        do
		local numInputs=$(parseJSON "$json" ".[\"$scope\"][$iCase]|length")
		local iString=""

                for (( iInput = 0; iInput < numInputs; iInput++ ));
                do
			iString+="$(parseJSON "$json" ".[\"$scope\"][$iCase][$iInput]")\n"
                done

		local results="$(checkHang "$command" 5 "$iString")"

	       	if [ "$results" = false ]
		then
			STATUS="fail"
			sendErr "Error: Code hangs when compiled"	
		else
			local numOutputs=$(echo -e "$results" | wc -l)	
			msg+="["
			for (( iOutput = 0; iOutput < numOutputs; iOutput++ ));
                	do
				local result="$(echo $results | awk -v i=$(( iOutput + 1)) '{print $i}')"
				msg+="$result"
				if [ $iOutput -ne $((numOutputs - 1)) ]
                        	then
                                	msg+=", "
                        	fi
                	done
			msg+="]"
			if [ $iCase -ne $((numCases - 1)) ]
			then
				msg+=", "
			fi
		fi
        done
	msg+=" ]"
	if [ $iScope -ne $((numScopes - 1)) ]
	then
		msg+=", "
	fi
done
echo "$msg"
}



#	INPUT PARSING
# Since this input is coming from the backend we can assume correct formatting, however error checking will still be performed


if [ -z "$1" ] # Check if we have a first argument
then
	sendErr "No argument provided"
	STATUS="fail" 	# FAIL STATE: No input means we cannot compile
else
	json=$1

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
	        		echo -e "$code" > code.cpp && g++ code.cpp # Outputs code to required file then compiles it
	        		cmd="./a.out" # Executable to run
	
			else
	        		sendErr "Invalid language provided: $language"
				STATUS="fail"	# FAIL STATE: Invalid language means we cannot compile the code
			fi


			# input; Test inputs (Not necessary):

			input="$(parseJSON "$json" ".input")"

			if [ -z "$input" ]
			then # Simply compile and return output
				results="$(checkHang "$cmd" 30)"
				if [ "$results" = false ]
				then
					sendErr "Error: Program hangs"
					STATUS="fail"
				else
				OUTPUT+="\"given\":[ "
				numOutputs=$(echo -e "$results" | wc -l)
                        	OUTPUT+="["
                        	for (( iOutput = 0; iOutput < numOutputs; iOutput++ ));
                        	do
                                	result="$(echo $results | awk -v i=$(( iOutput + 1)) '{print $i}')"
                                	OUTPUT+="$result"
                                	if [ $iOutput -ne $((numOutputs - 1)) ]
                                	then
                                        	OUTPUT+=", "
                                	fi
                        	done
				fi
                        	OUTPUT+="] ]"

			elif [ "$STATUS" != "fail" ]
			then	# Compile, run test inputs through program, compare to test outputs and return output
				OUTPUT="$(testVals "$input" "$cmd")"	

			fi
		fi
	fi
fi

echo -E $(getJSON "$STATUS" "$OUTPUT")
