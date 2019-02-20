#!/bin/bash
#
# 		ACCREDITATION
#
# 	All code, including frontend, backend, and handler (this script) was written by Aidan McPeake unless otherwise specified
#
#
#		ARGUMENTS
#
# 	One single argument is passed from the backend in the following JSON format: (Where " " denotes a string, X denotes an integer, and [ ] denotes a list)
# 		{"language": " ", "code": " ", "timeout": X, "input": [ [ ] ]}
#
# 	Language refers to the programming language, i.e. python3. It is used to determine which commands to execute to compile the user-provided code
#
# 	Code is the aforementioned user-provided code. Is is sent as an escaped string
#
#	Timeout refers to the amount of time the code is allowed to run before it is considered hung, and killed accordingly
#
# 	Input refers simply to sets of input which are to be piped into the given code via STDIN redirection (See checkComp function)
#
# 	This program returns JSON in the form:
#		{"status": "pass|fail", "error": [ " " ], "output": [ [ ] ]}
#
#
#		PROCESS
#
#	1. JSON is passed to this script as an argument
#	2. JSON is parsed into required fields (language and code)
#	3. Code is compiled according to which language it is written in
#	4. If input is present, pipe test input and parse result into sets of output
#	5. Errors, output, etc. is parsed into a JSON string and output
#
#
# 		GLOBAL DECLARATIONS

STATUS="pass"	# Flag to determine the success of the program compilation/execution
MAX_TIME=30	# Maximum time any program is allowed to run
ERROR=()	# Errors are stored in an array
OUTPUT=()	# Output is stored in an arrary

#		EXIT CODES
#100 - 104: JSON Error Codes
#	101: JSON Key Error (JSONKE)		| Given filter returned null
#	102: JSON Parsing Error (JSONPE)	| Malformed JSON received
#	103: 
#	104: JSON General Failure (JSONGF)
#	
#105-109: Handler Error Codes
#	105: Handler Input Error (HANDIE)	| Required field not provided
#	106:
#	107:
#	108:
#	109: Handler General Failure (HGF)
#
#110+: Code Compilation/Execute Errors:
#	110: Code Compilation Failure (CODECF)	| Given code failed to compile
#	111: Code Execution Error (CODEEE)	| Given code failed to execute
#	124: Code Time Out (CODETO)		| Given code timed out

E_JSONKE=101
E_JSONPE=102


E_HANDIE=105


E_CODECF=110
E_CODEEE=111
E_CODETO=124

#		FUNCTIONS

outputJSON() { # buildJSON(status = $STATUS, output = $OUTPUT, ERROR = $ERROR) | Compilation/Execution status, errors, and output are gathered, parsed into JSON, and output. Program then exits
	
	local status="${1:-$STATUS}"
	local error="$(IFS=","; echo -n "${ERROR[*]}"; IFS=" \t\n")"
	local output="$(IFS=","; echo -n "${OUTPUT[*]}"; IFS=" \t\n")"
	local json

	json+="\"status\":\"$status\""

	if [ ! -z "$output" ] # If the variable "output" is set and not empty...
	then
		json+=", \"output\":[ $output ]" # Add it to our json string
	fi

	if [ ! -z "$error" ]
	then
		json+=", \"error\":[ $error ]"
	fi

	parseJSON "{$json}" '.' &> /dev/null && echo -En "{$json}" || echo -En '{"status": "fail", "error": [ "Failed to build JSON" ] }' # Check if the JSON is valid before outputting it
	exit
}

parseJSON() { # parseJSON(json, filter = '.') | Parse JSON using jq and return the values found by the given filter
	
	local json="${1:-$json}"
	local filter="${2:-.}"
	local value
	
	value="$(jq -r "$filter // empty" 2>/dev/null <<< "$(echo -E "$json")")" # Get the value at the given key
	local status=$?
	
	if [ $status != 0 ] # If JQ threw an error, return JSON Parsing Error
	then
		return $E_JSONPE
	
	elif [ -z "$value" ] # If no value was returned, return JSON Key Error
	then
		return $E_JSONKE
	
	else # If a value was returned, and JQ threw no errors, return the value
		echo -E "$value"
	fi
}


parseErr() { # parseErr(e, msg = "", fstate = "false") | Take an exit code, parses it into a string and passes it to the sendErr() function; If fstate is true, the error is fatal
	
	local errCode=$1
	local msg="${2:-}"
	local fstate="${3:-false}"
	
	case $errCode in
		0)
			;;

		$E_JSONPE)	# 101
			sendErr "JSON Parsing Error: Malformed JSON received"
			;;

		$E_JSONKE)	# 102
			sendErr "JSON Key Error: Filter \"$msg\" returned no value"
			;;

		$E_HANDIE)      # 105
                        sendErr "Handler Input Error:" "$msg"
                        ;;

		$E_CODECF)	# 110
			sendErr "Code Compilation Failure: Program failed to compile" "$msg"
			;;

		$E_CODEEE)	# 111
			sendErr "Code Execution Error: Program failed to run" "$msg"
			;;

		$E_CODETO)      # 124
                        sendErr "Code Execution Error: Program hangs"
                        ;;

		*)
			sendErr "Code Execution Error: Program failed to run" "$msg"
			;;
	esac

	if [ "$fstate" == "true" ] # Denotes a fatal error, set STATUS to "fail"
	then
		STATUS="fail"
	fi
}

sendErr() { # sendErr(*strings) | Add given strings to ERROR array
	
	local str
	
	if [ -z "$1" ] # If no argument is given, try to read from STDIN
        then
		read str
		ERROR[${#ERROR[@]}]="$(jq -saR . <<< "$(echo "$str")")"

	else
                for str in "$@"
		do
			#	Converts to escaped JSON	Removes duplicate lines	Converts newlines to \n		Converts tabs to \t
			ERROR[${#ERROR[@]}]="$(jq -saR . <<< "$(echo "$str")")"
		done
        fi
}

sendOut() { # sendOut(*strings) | Add given strings to OUTPUT array
	
	local str

	if [ -z "$1" ]
        then
                read str
                OUTPUT[${#OUTPUT[@]}]="$str"
        
	else

                for str in "$@"
                do
			OUTPUT[${#OUTPUT[@]}]="$(jq -sraR . <<< "$(echo "$str")")"
                done
        fi
}

runCase() { # runCase(command, case = '', time = 30) | Pass a series of inputs (aka a case), run the code on a timer to catch hanging and return the outputs in form ["x1", "y1", "z1"], ["x2", "y2", "z2"]...
	
	local command="$1"
	local case="${2:-}"
	local time=${3:-30}
	local results # Must be declared separately to avoid sweeping of exit codes
	local status
	local output

	results="$(timeout $time $command 2>&1 <<< "$(echo -e "$case")")" # Pipe it into the program and gather any output
	status=$?

	if [ $status == 124 ] # If code timed out, return 124
	then
		return $E_CODETO
	
	elif [ $status != 0 ] # If the command threw an error, return the error and the output message
	then
		echo -En "$results"
		return $E_CODEEE 
	
	elif [ $status == 0 ] && [ ! -z "$results" ] # If no error was thrown and results were returned, parse them into a JSON array, and return them
	then
		local numLines="$(echo -e "$results" | wc -l)" # Get number of output values
		
		for (( i = 1; i <= numLines; i++ )) # Iterate through output values
		do
			local result="$(echo -e "$results" | awk -v i="$i" 'BEGIN{ RS = "" ; FS = "\n" }{print $i}')"
			
			if [ ! -z "$result" ]
			then
				output+="$(jq -aR . <<< "$(echo -En "$result")")" # Parse the result into an escaped string
				
				if [ $i -lt $numLines ]
				then
					output+=", "
				fi
	 		fi
		done
		
		echo -En "[$output]"
		return 0
	fi
}

testCode() { # testCode(command, input = '') | Run program and gather status
	
	local command="$1"
	local input="${2:-}"
	local msg
	local results
	local status
	
	if [ -z "$input" ] # If there is no input, run program once
	then
		msg="$(runCase "$command" "" $timeout)"
		status=$?

		if [ $status != 0 ]
		then
			parseErr $status "$msg" "true"
		fi
	
	else # If there is input, run program once per input case
		local numCases=$(parseJSON "$input" ".|length") # Get total number of cases
		
		for (( iCase = 0; iCase < numCases; iCase++ )); # Iterate through cases
		do
			
			if [ "$STATUS" != "fail" ]
			then
				local iString="$(parseJSON "$input" ".[$iCase][]|tostring")" # Get input value(s) as a single string
				
				results="$(runCase "$command" "$iString" $timeout)"
				status=$?
				
				if [ $status == 0 ] && [ ! -z "$results" ]
				then
					msg+="$results"
			
					if [ $iCase -ne $((numCases - 1)) ]
					then
						msg+=", "
					fi
				
				else
					parseErr $status "$results"
				fi

			fi
		done
	fi

	if [ $status == 0 ]
	then
		sendOut "$msg"
	fi
}


#	ENTRYPOINT

#	INPUT PARSING

if [ -z "$1" ] # If no argument is provided
then
	parseErr $E_HANDIE "No arguments provided" "true" # FAIL STATE: Script needs argument to function

else
	json="$1" 
	parseJSON "$json" '.' &> /dev/null || parseErr $E_JSONPE "" "true" # FAIL STATE: JSON must be valid
fi
	
# 	JSON PARSING
# Gather required arguments from the provided JSON 
# code; User-provided code:

code="$(parseJSON "$json" ".code")" || parseErr $E_HANDIE "No code proivded" "true"

# timeout; Time the program is allowed to run for

timeout=$(parseJSON "$json" ".timeout")
if [ -z "$timeout" ] || ! [[ $timeout =~ ^[0-9]+$ ]] || [ $timeout -ge $MAX_TIME ]
then
	timeout=30
fi

# language; Programming language provided code is written in:

language="$(parseJSON "$json" ".language")" || parseErr $E_HANDIE "No language provided" "true" # FAIL STATE: No language means we cannot compile

if [ "$STATUS" != "fail" ]
then

#	LANGUAGE PARSING
# 	Given the selected language, prepare the necessary executables and remember the command needed to run our code
	
	case "$language" in

		"bash") 
                        echo -E "$code" > code.sh
                        cmd="bash code.sh"
                        ;;

		"c")
                        echo -E "$code" > code.c
                        error="$(g++ code.c 2>&1)"
                        status=$?
                        cmd="./a.out"
                        ;;

                "cpp")
                        echo -E "$code" > code.cpp
                        error="$(g++ code.cpp 2>&1)"
                        status=$?
                        cmd="./a.out" # Executable to run
                        ;;

                "c#")
                        echo -E "$code" > code.cs
                        error="$(mcs code.cs 2>&1)"
                        status=$?
                        cmd="mono code.exe"
                        ;;

		"java")
                        class="$(echo "$code" | grep -m 1 "public class" | sed "s/public class //g" | awk '{print $1}')"
                        filename="${class:-code}"
                        
                        echo -E "$code" > $filename.java
                        
                        error="$(javac $filename.java 2>&1)"
                        status=$?
                        
                        cmd="java "$(ls | grep '.class' | sed 's/.class//g')""
                        ;;

                "javascript")
                        echo -E "$code" > code.js
                        cmd="rhino code.js"
                        ;;

		"php")
			echo -E "$code" > code.php
			cmd="php code.php"
			;;

		"python2")
			echo -E "$code" > code.py # Copy users code to a file
			cmd="python2.7 code.py" # Prepare the command to execute the code
			;;

		"python3")
			echo -E "$code" > code.py
			cmd="python3.6 code.py"
			;;

		"ruby")
			echo -E "$code" > code.rb
			cmd="ruby code.rb"
			;;

		*)
			parseErr $E_HANDIE "Invalid language provided \"$language\"" "true" # FAIL STATE: Invalid language means we cannot compile the code
			;;

	esac

	if [ ${status:-0} != 0 ]
	then
		parseErr $E_CODECF "$error" "true"
	fi
fi	

# input; Test inputs (Not necessary):

input="$(parseJSON "$json" ".input")"
if [ "$STATUS" != "fail" ]
then	# Compile, run test inputs through program, compare to test outputs and return output
	testCode "$cmd" "$input"
fi

outputJSON "$STATUS" "$OUTPUT" "$ERROR"
