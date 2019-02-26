#!/bin/bash
#===============================================================================
# LICENSE
#===============================================================================
# Copyright Aidan McPeake, 2019
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.
#===============================================================================
# PURPOSE
#===============================================================================
# This program serves as a multilanguage compiler. A user provides code
# which is compiled by this program with any output being returned to the
# user.
#===============================================================================
# PROCESS
#===============================================================================
# 1. JSON is passed to this script as an argument
# 2. JSON is parsed into required fields (language and code)
# 3. Code is compiled according to which language it is written in
# 4. If input is present, pipe test input and parse result into sets of output
# 5. Errors, output, etc. is parsed into a JSON string and output
#===============================================================================
# INPUT FORMAT
#===============================================================================
# A single argument is passed upon startup in the following JSON format;
# "" denotes a string, X denotes an integer, and [] denotes an array:
# {"language": "", "code": "", "timeout": X, "input": [[]]}
# i.e. '{"language": "bash", "code": "echo $1", "input": [["Hello"]]}'
#
#	LANGUAGE | STRING
#
#	The language field refers to the programming language in which
#	the code field is written. It is used to determine which commands
#	to run to correctly compile and execute the user-provided code.
#	i.e. 'python3'
#
#	CODE | STRING
#
#	The code field is the aforementioned user-provided code.
#	Is is an escaped string according to JSON standards.
#	i.e. 'print(\"Hello World!\")'
#
#	TIMEOUT | INTEGER
#
#	The timeout field is the amount of time any code is allowed
#	to run before it is considered 'hung' and killed accordingly.
#	i.e. '30'
#
#	INPUT | ARRAY
#
#	The input field is one or more sets of input (herein called 'cases')
#	which are to be piped into the given code via STDIN redirection
#	(See checkComp function)
#	i.e. '[[10, 20], [30, 40]]'
#===============================================================================
# OUTPUT FORMAT
#===============================================================================
# A single argument is returned upon exit in the following JSON format:
# {"status": "pass|fail", "error": [""], "output": [[]]}
# i.e. '{"status": "fail", "error": ["Program failed to compile"]}'
#
#	STATUS | STRING
#
#	The status field is an indication of the success of the compilation
#	and execution process of the code. If any errors occured anywhere in
#	this process, all related STDERR will be captured and placed
#	in the error field.
#	i.e. 'fail'
#
#	OUTPUT | ARRAY
#
#	The output field is similar to the input field in that it is
#	a set of cases of values gathered from running the program. If
#	your code takes in two integers and adds them, each output case
#	would be the sum of the corresponding input case.
#	i.e. '[[30], [70]]'
#
#	ERROR | ARRAY
#
#	The error field is a collection of STDERR messages in the form of
#	an array of strings. These messages may be custom error messages
#	(See sendError() function)
#	i.e. '["Program failed to execute", "Unknown command \"ehco\""]'
#===============================================================================
# GLOBAL DECLARATIONS
#===============================================================================
# STATUS: Indication of the status of the program's compilation/execution
# MAX_TIME: Maximum amount of time in seconds any program is allowed to run
# ERROR: An array used to store error messages
# OUTPUT: An array used to store output messages
#===============================================================================
STATUS=""
MAX_TIME=30
ERRORARRAY=()
OUTPUTARRAY=()
#===============================================================================
# EXIT CODES
#===============================================================================
# JSON ERROR CODES | 101-104
#	101: JSON Key Error (JSONKE)			| Field does not exist
#	102: JSON Parsing Error (JSONPE)		| Malformed JSON received
#	103: 
#	104: JSON General Failure (JSONGF)
#	
# HANDLER ERROR CODES | 105-109
#	105: Handler Input Error (HANDIE)		| Required field not provided
#	106:
#	107:
#	108:
#	109: Handler General Failure (HGF)
#
# COMPILATION/EXECUTION ERROR CODES | 110+
#	110: Code Compilation Failure (CODECF)	| Code failed to compile
#	111: Code Execution Error (CODEEE)		| Code failed to execute
#	124: Code Time Out (CODETO)				| Code timed out
#===============================================================================
E_JSONKE=101
E_JSONPE=102
E_HANDIE=105
E_CODECF=110
E_CODEEE=111
E_CODETO=124
#===============================================================================
# FUNCTIONS
#===============================================================================
# NAME:			outputJSON
# DESCRIPTION:	Reads global variables into correctly formatted 
#				JSON string for output
# FORMAT:		outputJSON()
# INPUT:		NONE
# OUTPUT:		NONE
# EXIT CODES:	NONE
#===============================================================================
function outputJSON { 
	local status="${STATUS:-pass}"
	local error="$(IFS=","; echo -n "${ERROR[*]}"; IFS=" \t\n")"
	local output="$(IFS=","; echo -n "${OUTPUT[*]}"; IFS=" \t\n")"
	local jstring="\"status\":\"$status\""
	
	if [[ ! -z "$output" ]]; then
		jstring+=",\"output\":[$output]"
	fi

	if [[ ! -z "$error" ]]; then
		jstring+=",\"error\":[$error]"
	fi

	parseJSON "{$jstring}" '.' &> /dev/null	\
		&& echo -En "{$jstring}"	\
			|| echo -En '{"status":"fail","error":["Failed to build JSON"]}'
	exit
}
#===============================================================================
# NAME:			parseJSON
# DESCRIPTION:	Reads fields from JSON string using JQ filtering
# FORMAT:		parseJSON(jstring, filter = '.')
# INPUT:		$jstring			| JSON string
#				$filter => '.'		| String used to filter JSON
# OUTPUT:		$field				| Field found by filter
# EXIT CODES:	101					| JSONKE
#				102					| JSONPE
#===============================================================================
function parseJSON {
	local jstring="${1:-$json}"
	local filter="${2:-.} // empty"
	local field=""
	
	field="$(jq -er "$filter" 2>/dev/null <<< "$(echo -E "$jstring")")"
	
	if [[ $? != 0 ]] ; then
		return $E_JSONPE

	elif [[ -z "$field" ]] ; then
		return $E_JSONKE
	
	else
		echo -En "$field"
	fi
}
#===============================================================================
# NAME:			parseError
# DESCRIPTION:	Takes exit codes and appends custom error messages to ERROR[]
#				accordingly
# FORMAT:		parseError(ecode, msg = '', fstate = 'false')
# INPUT:		$ecode				| Error code
#				$msg => ''			| Additional message
#				$fstate => 'false'	| If true, sets STATUS to 'fail' upon exit
# OUTPUT:		NONE
# EXIT CODES:	NONE 
#===============================================================================
function parseError {
	local ecode=$1
	local msg="${2:-}"
	local fstate="${3:-false}"
	
	case $ecode in
	0)
		;;

	$E_JSONPE )
		sendError "JSON Parsing Error: Malformed JSON received"
		;;

	$E_JSONKE )
		sendError "JSON Key Error: Filter \"$msg\" returned no value"
		;;

	$E_HANDIE )
		sendError "Handler Input Error:" "$msg"
		;;

	$E_CODECF )
		sendError "Code Compilation Error: Program failed to compile" "$msg"
		;;

	$E_CODEEE )
		sendError "Code Execution Error: Program failed to run" "$msg"
		;;

	$E_CODETO )
		sendError "Code Execution Error: Program hangs"
		;;

	* )
		sendError "Code Execution Error: Program failed to run" "$msg"
		;;
	esac

	if [[ "$fstate" == "true" ]]; then
		STATUS="fail"
	fi
}
#===============================================================================
# NAME:			sendError
# DESCRIPTION:	Use JQ to correctly escape error messages and add them to
#				ERROR[] array
# FORMAT:		sendError(*strings)
# INPUT:		$strings			| All arguments are sent as error messages
# OUTPUT:		NONE
# EXIT CODES:	NONE 
#===============================================================================
function sendError {
	for string in "$@"; do
		ERROR[${#ERROR[@]}]="$(jq -saR . <<< "$(echo "$string")")"
	done
}
#===============================================================================
# NAME:			sendOutput
# DESCRIPTION:	Use JQ to correctly escape output messages and add them to
#				OUTPUT[] array
# FORMAT:		sendOutput(*strings)
# INPUT:		$strings			| All arguments are sent as output messages
# OUTPUT: 		NONE
# EXIT CODES:	NONE
#===============================================================================
function sendOutput {
	for string in "$@"; do
		OUTPUT[${#OUTPUT[@]}]="$(jq -sraR . <<< "$(echo "$string")")"
	done
}
#===============================================================================
# NAME:			runCase
# DESCRIPTION:	Take an input case, run it through the program, and parse the
#				output as an output case
# FORMAT:		runCase(command, case = '', time = 30)
# INPUT:		$command			| Command to execute program
#				$inputcase => ''	| Input case to test
#				$timeout => 30		| Maximum time to allow program to run
# OUTPUT:		$outputcase			| String formatted as JSON array
# EXIT CODES:	111					| CODEEE
#				124					| CODETO
#===============================================================================
function runCase {
	local command="$1"
	local inputcase="${2:-}"
	local time=${3:-30}
	local output=""
	local outputcase=""
	
	output="$(timeout $time $command 2>&1 <<< "$(echo -e "$inputcase")")"
	local status=$?

	if [[ $status == 124 ]]; then
		return $E_CODETO
	
	elif [[ $status != 0 ]]; then
		echo -En "$output"
		return $E_CODEEE
	
	elif [[ $status == 0 ]] && [[ ! -z "$output" ]]; then
		outputcase+="$(jq -aR . <<< "$(echo -e "$output")")"	
		echo -En "[${outputcase}]" | tr '\n' ','
	fi
}
#===============================================================================
# NAME:			testCode
# DESCRIPTION:	Execute code and parse the status
# FORMAT:		testCode(command, input = '')
# INPUT:		$command			| Command to execute program
#				$inputcase => ''	| Input case
# OUTPUT:		NONE
# EXIT CODES:	NONE
#===============================================================================
function testCode {
	local command="$1"
	local inputcase="${2:-}"
	local outputcase=""
	local status=""

	if [[ -z "$inputcase" ]]; then
		outputcase="$(runCase "$command" "" $timeout)"
		status=$?
		
			
		if [[ $status == 0 ]] && [[ ! -z "$outputcase" ]]; then
			sendOutput "$outputcase"
		
		else
			parseError $status "$outputcase" "true"
		fi
	
	else
		local numCases=$(parseJSON "$inputcase" ".|length")
		
		for (( iCase = 0; iCase < numCases; iCase++ )); do
			if [[ "$STATUS" != "fail" ]]; then
				local input="$(parseJSON "$inputcase" ".[$iCase][]")"
				outputcase="$(runCase "$command" "$input" $timeout)"
				status=$?
				
				if [[ $status == 0 ]] && [[ ! -z "$outputcase" ]]; then
					sendOutput "$outputcase"

				else
					parseError $status "$outputcase" "true"
				fi
			fi
		done
	fi
}
#===============================================================================
# PROGRAM ENTRYPOINT
#===============================================================================
# INPUT PARSING
#===============================================================================
while [[ "$STATUS" != "fail" ]]; do
	if [[ -z "$1" ]]; then
		parseError $E_HANDIE "No argument provided" "true"
		break
	
	else
		json="$1" 
		parseJSON "$json" '.' &> /dev/null	\
			|| { parseError $E_JSONPE "" "true"	\
				; break; }
	fi
#===============================================================================
# JSON PARSING
#===============================================================================
# 	CODE
#===============================================================================
	code="$(parseJSON "$json" ".code")"	\
		|| { parseError $E_HANDIE "No code provided" "true"	\
			; break; }
#===============================================================================
#	TIMEOUT
#===============================================================================
	timeout=$(parseJSON "$json" ".timeout")
	if [[ -z "$timeout" ]]	\
		|| ! [[ $timeout =~ ^[0-9]+$ ]]	\
			|| [[ $timeout -ge $MAX_TIME ]]; then
		timeout=30
	fi
#===============================================================================
#	LANGUAGE
#===============================================================================
	language="$(parseJSON "$json" ".language")"	\
		|| { parseError $E_HANDIE "No language provided" "true"	\
			; break; }
	
	case "$language" in
	"x86" )
		echo -E "$code" > code.asm
		error="$(nasm -f elf code.asm && ld -m elf_i386 -s -o code code.o)"
		status=$?
		cmd="./code"
		;; 
	"bash" ) 
		echo -E "$code" > code.sh
		cmd="bash code.sh"
		;;

	"c" )
		echo -E "$code" > code.c
		error="$(g++ code.c 2>&1)"
		status=$?
		cmd="./a.out"
		;;

	"cpp" )
		echo -E "$code" > code.cpp
		error="$(g++ code.cpp 2>&1)"
		status=$?
		cmd="./a.out"
		;;

	"c#" )
		echo -E "$code" > code.cs
		error="$(mcs code.cs 2>&1)"
		status=$?
		cmd="mono code.exe"
		;;

	"java" )
		class="$(echo "$code"	\
			| grep -m 1 "public class"	\
				| sed "s/public class //g"	\
					| awk '{print $1}')"
		filename="${class:-code}"

		echo -E "$code" > $filename.java
                        
		error="$(javac $filename.java 2>&1)"
		status=$?
                        
		cmd="java "$(ls | grep '.class' | sed 's/.class//g')""
		;;

	"javascript" )
		echo -E "$code" > code.js
		cmd="rhino code.js"
		;;

	"php" )
		echo -E "$code" > code.php
		cmd="php code.php"
		;;

	"python2" )
		echo -E "$code" > code.py
		cmd="python2.7 code.py"
		;;

	"python3" )
		echo -E "$code" > code.py
		cmd="python3.6 code.py"
		;;

	"ruby" )
		echo -E "$code" > code.rb
		cmd="ruby code.rb"
		;;
	
	* )
		parseError $E_HANDIE "Invalid language \"$language\"" "true"
		break
		;;
	esac

	if [[ ${status:-0} != 0 ]]; then
		parseError $E_CODECF "$error" "true"
		break
	fi
#===============================================================================
#	INPUT
#===============================================================================
	input="$(parseJSON "$json" ".input")"
#===============================================================================
# CODE EXECUTION
#===============================================================================
	testCode "$cmd" "$input"
#===============================================================================
break
done
outputJSON "$STATUS" "$OUTPUT" "$ERROR"
