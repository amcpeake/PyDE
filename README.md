# PyDE
A multilanguage IDE with a handler written in bash. Intended to be run within a docker container

## Getting started

First of all, you need to evaluate whether or not you want to containerize the IDE using docker.
This is generally recommended and should only be avoided if the code you wish to compile is 100% safe and trusted.
This would prevent any compiled code from harming your system in any way.

## Containerizing
The containerized version of PyDE simply requires you to install docker

### Installing PyDE
To install the containerized version of PyDE, run:

```git clone -b docker https://github.com/amcpeake/PyDE```

### Installing docker
If you already have docker installed, you can skip this step.

To install docker, follow [these](https://docs.docker.com/install/) instructions for your operating system.

### Building the container

1. Store init.sh, pyde, and pydebase in the same folder
2. Open a command line in said folder
3. Run ```docker build -t pydebase -f pydebase .```
4. Run ```docker build -t pyde -f pyde .```

### Running the container

If your code is not trusted (i.e. web sourced) it is important to impose resource limitations on the container to avoid fork bombs and other such attacks.
This can be done by adding the following flags to the ```docker run``` command:
* ```--memory=[bytes]``` ~ Set the maximum amount of system RAM the container can use, i.e. 256m
* ```--memory-swap=[bytes]``` ~ Set the maximum amount of swap memory the container can use, i.e. 256m
* ```--kernel-memory=[bytes]``` ~ Set the maximum amount of kernel memory the container can use, i.e. 512m
* ```--cpus=[x]``` ~ Set the maximum number of CPU cores the container can use (Can be a fraction), i.e. 0.1

You can read more about these flags [here](https://docs.docker.com/config/containers/resource_constraints/)

You may also wish to isolate the container from your local network to avoid DDoS attacks sourced from the container.
This can be done by adding the ```--network none``` flag

Finally, to run the container:

```docker run [flags] pyde [arguments]```

For which arguments to provide, see the [arguments](https://github.com/amcpeake/PyDE/new/master?readme=1#arguments) section.

## Raw script
The raw script requires a UNIX bash environment and requires you to install the necessary packages to compile your code.

### Installing PyDE
To install the unprotected version of PyDE, run:

```git clone -b master https://github.com/amcpeake/PyDE```

### Installing packages
You will also need the required packages to compile/run your code, as well as [JQ](https://stedolan.github.io/jq/), a bash based JSON interpreter.

i.e., for Debian systems, run:

```sudo apt-get install jq python g++ openjdk-11-jdk```

### Running the script
To execute the script, run:

```bash init.sh [arguments]```

For which arguments to provide, see the [arguments](https://github.com/amcpeake/PyDE/new/master?readme=1#arguments) section.

## Arguments

Communication between the host and the container/script is handled as JSON in the following form:

```{"language": " ", "code": " ", "timeout": X, "input": [ [], [], ... ] }``` 

Where " " represents a string, X represents an integer, and [ ] represents a list

### Language
Language is a string which denotes the language in which your provided code is written. 
Currently accepted languages include Python3, C++, Bash, and Java.

These are entered as "python3", "cpp", "bash", and "java" respectively

### Code
Code is a string which denotes the code to be compiled and run. 
For whitespace-conscious languages (i.e. Python), indents can be represented with "\t". 
You can also use any other valid bash escape sequences.

Also note that all double quotes must be escaped

i.e. ```"x = input()\nif x is 5:\n\tprint(\"x is 5\")"```

### Timeout
Timeout is an integer which denotes how long the code is allowed to be run for before it is killed.

As PyDE is designed for small pieces of code, the maximum timeout is 30 seconds.
To extend this, you will have to edit init.sh and change the MAX_TIME variable in the global definitions section.
Keep in mind, if you are using the containerized version you will have to rebuild the container after any alterations to init.sh.

i.e. 25

### Input
Input consists of a list of lists.
The values in these lists can be of any type and are passed into your program, and the corresponding output is collected.

If this confuses you, consider your code simply takes in two integers and returns their sum.

Your input might look like this:

```[ [5, 10], [15, 5], [100, 1] ]```

And the corresponding output would look like this:

```[ [15], [20], [101] ]```

### Putting it all together
Now that you grasp the required arguments, let's compile an example program. 
In the [output](https://github.com/amcpeake/PyDE/new/master?readme=1#output) section you can see the result of this compilation.

If you're running the script raw, your command might look like this:

```bash init.sh '{"language": "python3", "code": "x = int(input())\ny = int(input())\nprint(x + y)", "timeout": 5, "input": [ [1, 1], [10, 20] ] }'```

Or if you're using a docker container, your command might look like this:

```docker run [flags] pyde '{"language": "python3", "code": "x = int(input())\ny = int(input())\nprint(x + y)", "timeout": 5, "input": [ [1, 1], [10, 20] ] }'```
## Output
PyDE outputs the result/status of the compilation as JSON in the following form:

```{"status": " ", "error": [ " ", " ", ... ], "output": [ [], [], ... ] }```

Note that null (empty) keys will be ommited from the output

### Status
Status is a string that denotes whether or not your code compiled. 
This will either be "pass" meaning your code compiled, or "fail" meaning it did not.

### Error
Error is a list of strings that represent all the error messages gather while compiling/running your code.
Some of these will come directly from the program used to compile your code, others are custom, such as a message which indicates your code has hung (timed out).

### Putting it all together
Looking at our previous example input:

```{"language": "python3", "code": "x = int(input())\ny = int(input())\nprint(x + y)", "timeout": 5, "input": [ [1, 1], [10, 20] ] }```

We would expect the output to be:

```{"status": "pass", "output": [ [2], [30] ] }```

## Accredation
All code, unless otherwise specified, was written by Aidan McPeake
