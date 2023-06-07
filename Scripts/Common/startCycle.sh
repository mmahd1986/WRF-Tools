#!/bin/bash

# Script to set up a cycling WPS/WRF run: common/machine-independent part.
# Reads stepfile and sets up run folders. 
# Created 07/04/2014 by Andre R. Erler, GPL v3.


# Clear screen
clear

# Abort if anything goes wrong
set -e 

# Pre-process arguments using getopt
if [ -z $( getopt -T ) ]; then
  TMP=$( getopt -o r:gsvqkwlmn:t:N:h --long restart:,clean,nogeo,nostat,verbose,quiet,skipwps,nowait,nowps,norst,setrst:,wait:,name:,help -n "$0" -- "$@" ) # Pre-process arguments.
  # NOTE: $0 bash parameter is used to reference the name of the shell script. 
  #   So you can use this if you want to print the name of shell script.
  # NOTE: $@ refers to all of a shell script’s command-line arguments.
  [ $? != 0 ] && exit 1 # Exit if getopt not successful.
  # NOTE: $? is the exit status of the last executed command.
  # NOTE: The above is like an IF statement.
  # NOTE: In case of "exit 1", getopt has already printed an error message.
  eval set -- "$TMP" # Change positional parameters (arguments) to $TMP list.
  # NOTE: -- above means positional parameters (arguments).
fi 

# Default settings
MODE='' # NOGEO, RESTART, START, CLEAN, or None (''). Default is ''.
VERBOSITY=1 # Level of output/feedback.
NEXTSTEP='' # Next step to be processed (argument to --restart).
SKIPWPS=0 # Whether or not to run WPS before the first step.
NOWPS='FALSE' # Passed to WRF.
RSTCNT=0 # Restart counter.
WAITTIME=0 # Minimum wait (sleep) time in seconds before WRF job is submitted.
DEFWCT="00:15:00" # Another variable is necessary to prevent the setup script from changing the value. ?????

# Parse arguments 
while true; do
  case "$1" in
    -r | --restart )   MODE='RESTART'; NEXTSTEP="$2"; shift 2 ;; # Second argument is restart step.
         --clean   )   MODE='CLEAN'; shift;; # Delete wrfout/ etc. (short option would be dangerous).
    -g | --nogeo   )   MODE='NOGEO'; shift;; # Don't run geogrid.
    -s | --nostat  )   MODE='NOSTAT'; shift;; # Don't run geogrid and don't archive static data.
    -v | --verbose )   VERBOSITY=2; shift;; # Print more output.
    -q | --quiet   )   VERBOSITY=0; shift;; # Don't print output.
    -k | --skipwps )   SKIPWPS=1; shift;; # Don't run WPS for *this* step.
    -w | --nowps   )   NOWPS='NOWPS'; shift;; # Don't run WPS for *next* step.
    -l | --nowait  )   QWAIT=0; shift;; # Don't wait for WPS to finish.
    -m | --norst   )   RSTCNT=1000; shift;; # Should be enough to prevent restarts.
    -n | --setrst  )   RSTCNT="$2"; shift 2 ;; # (re-)set restart counter.
    -t | --wait    )   WAITTIME="$2"; shift 2 ;; # Sleep timer.    
    -N | --name    )   JOBNAME="$2"; shift 2 ;; # Set WRF jobname - just for identification.
    -h | --help    )   echo -e " \
                          \n\
    -r | --restart     restart cycle at given step \n\
         --clean       delete all WRF output (wrfout/) --- be careful! \n\
    -g | --nogeo       don't run geogrid (has to be run before) \n\
    -s | --nostat      don't run geogrid and don't archive static data \n\
    -v | --verbose     print more output \n\
    -q | --quiet       don't print output \n\
    -k | --skipwps     don't run WPS for *this* step \n\
    -w | --nowps       don't run WPS for *next* step \n\
    -l | --nowait      don't wait for WPS to finish (and skip WPS completion check) \n\
    -m | --norst       suppress restarts \n\
    -n | --setrst      (re-)set restart counter \n\
    -t | --wait        sleep time (seconds) before submitting WRF job \n\
    -N | --name        set WRF jobname - just for identification \n\
    -h | --help        print this help \n\
                           "; exit 0;; 
    # NOTE: \n\ means 'line break, next line'. It is also for syntax highlighting.
    # break loop
    -- ) shift; break;; # This terminates the argument list, if GNU getopt is used.
    * ) break;;
  esac 
done   
# NOTE: Shift is a builtin command in bash which after getting executed, shifts/move 
#   the command line arguments to one position left (here one position means one 
#   whole argument and move to left means to delete). The first argument is lost after 
#   using shift command. This command takes only one integer as an argument. This 
#   command is useful when you want to get rid of the command line arguments which 
#   are not needed after parsing them. Syntax is "shift n". Here, n is the number 
#   of positions by which you want to shift command-line arguments to the left if 
#   you do not specify, the default value of n is assumed to be 1 i.e shift works 
#   the same as shift 1.
# NOTE: The break statement terminates the current loop and passes program control 
#   to the command that follows the terminated loop.

# External settings (any of these can be changed from the environment)
export INIDIR=${INIDIR:-"${PWD}"} # Current directory.
EXP="${INIDIR%/}"; EXP="${EXP##*/}" # Guess name of the experiment.
# NOTE: ${var%string} deletes the shortest match of string in $var from the end.
# NOTE: ${var##string} deletes the longest match of string in $var from the beginning.
export JOBNAME=${JOBNAME:-"${EXP}_WRF"} # Guess name of job.
export STATICTGZ=${STATICTGZ:-'static.tgz'} # File for static data backup.
export SCRIPTDIR="${INIDIR}/scripts" # Location of the setup-script.
export BINDIR="${INIDIR}/bin/"  # Location of executables and scripts (WPS and WRF).
export WRFOUT="${INIDIR}/wrfout/" # Output directory.
export METDATA='' # Folder to collect output data from metgrid.
export DATATYPE='' # Data type.
# NOTE: DATATYPE is needed to handle leap years.
export WPSSCRIPT='run_cycling_WPS.pbs' # WPS run-script.
export WRFSCRIPT='run_cycling_WRF.pbs' # WRF run-script.
export WRFVERSION='' # WRF version (default set in setup_WRF.sh).
WRFWCT='00:15:00' # Wait time for queue selector; only temporary; default set above ($DEFWCT). ?????
export PYTHONVERSION=3 # Python version. 
# NOTE: pyWPS and related codes are now converted to Python 3.
export GEOTASKS=4 # Number of geogrid procceses.
export WRFENV='2019b' # WRF environment version.

# Source machine setup
echo
source "${SCRIPTDIR}/setup_WRF.sh" > /dev/null 
# NOTE: "> /dev/null" suppresses output (not errors, though).

# Find previous step in stepfile
if [ -n $NEXTSTEP ]; then
  LASTSTEP=$( grep -B 1 "^${NEXTSTEP}[[:space:]]" stepfile | head -n 1 | cut -d ' ' -f 1 | cut -f 1 )
  # NOTE: For grep, "-B NUM" prints NUM lines of leading context before matching lines.
  # NOTE: [[:space:]] above represents space characters class. Some of these are:
  #   <space>, <newline> and <tab>.
  # NOTE: "head -n NUM" command prints NUM lines of the input to it.
  # NOTE: "cut" command allows you to cut parts of lines from specified files or 
  #   piped data and print the result to standard output. Default delimiter is
  #   TAB. "-d" option specifies a delimiter other than tab. "-f" option specifies 
  #   the field (or coloumn) within input.  
  # NOTE: We use cut twice to catch both space and tab delimiters.
  if [[ "$LASTSTEP" == "$NEXTSTEP" ]]; then LASTSTEP=''; fi # When we are at the first step.
else
  LASTSTEP='' # When we are at the first step.
fi 

# Move into INIDIR
cd "${INIDIR}"

# Get NEXTSTEP by running cycling.py on LASTSTEP
NEXTSTEP=$( python "${SCRIPTDIR}/cycling.py" "${LASTSTEP}" )
export NEXTSTEP

# Run (machine-independent) setup
export MODE
export VERBOSITY
export GEOTASKS
export WRFENV
eval "${SCRIPTDIR}/setup_cycle.sh" 
# NOTE: setup_cycle.sh requires geogrid command.

# Submit first WPS instance, if applicable
if [ $SKIPWPS == 1 ]; then
  [ $VERBOSITY -gt 0 ] && echo 'Skipping WPS!'
else  
  # $WRFWCT is set above
  if [[ "${WRFWCT}" != '00:00:00' ]] && [[ "${WRFWCT}" != '0' ]]; then
    WRFWCT="${DEFWCT}" # Default wait time.
    # NOTE: The above means if WRFWCT is 0, leave it.
  fi 
  # NOTE: INIDIR, NEXTSTEP and WPSSCRIPT variables are set above.
  # Prompt on screen, if applicable
  [ $VERBOSITY -gt 0 ] && echo "   Submitting WPS/REAL for experiment ${EXP}: NEXTSTEP=${NEXTSTEP}."
  [ $VERBOSITY -gt 0 ] && echo -n -e "\n   "
  # Launch WPS (required vars: INIDIR, NEXTSTEP, WPSSCRIPT and WRFWCT)
  eval "${SUBMITWPS}" # on the same machine (default)
fi 

# Figure out if we have to wait until WPS job is completed
if [ -z $QWAIT ] && [ -n $QSYS ]; then
  if [[ "$QSYS" == 'LL' ]]; then QWAIT=1
  elif [[ "$QSYS" == 'PBS' ]]; then QWAIT=1 
  elif [[ "$QSYS" == 'SB' ]]; then QWAIT=1 
  elif [[ "$QSYS" == 'SGE' ]]; then QWAIT=1
  else QWAIT=1 # Otherwise, assume the system does not support dependencies.
  # NOTE: At the time of writing the code, dependencies did not work for PBS    
  #   and SB systems (if they did, wait times would be unnecessary). 
fi; fi 

# Wait until WPS job is completed. Check presence of the WPS script as signal  
#   of completion (this is only necessary, if the queue system does not support 
#   job dependencies)
if [ $QWAIT == 1 ]; then
# NOTE: We can use -l/--nowait option to skip the WPS verification step.  
  # Wait cycle
  if [[ ! -f "${INIDIR}/${NEXTSTEP}/${WPSSCRIPT}" ]]; then
  # NOTE: [ -f FILE ] returns true if FILE exists and is a regular file.     
    [ $VERBOSITY -gt 0 ] && echo
    [ $VERBOSITY -gt 0 ] && echo "   Waiting for WPS/REAL job to complete..."
    while [[ ! -f "${INIDIR}/${NEXTSTEP}/${WPSSCRIPT}" ]]
      do sleep 30
    done
    [ $VERBOSITY -gt 0 ] && echo
    [ $VERBOSITY -gt 0 ] && echo "   ... WPS/REAL completed."
  fi 
  # Check WPS exit status
  if [ 1 -ne $(grep -c 'SUCCESS COMPLETE REAL_EM INIT' "${INIDIR}/${NEXTSTEP}/real/rsl.error.0000") ]; then
  # NOTE: "grep -c" prints a count of matching lines for each input.
    echo
    echo "   WPS/REAL for step ${NEXTSTEP} failed --- aborting! "
    echo
    exit 1
  fi 
fi 

# optional wait before launching WRF
if [ -n "$WAITTIME" ]; then
  echo "... sleeping for $WAITTIME seconds..."
  sleep $WAITTIME
fi

# Add extra display line, if applicable
[ $VERBOSITY -gt 0 ] && echo

# Prompt on screen, if applicable
[ $VERBOSITY -gt 0 ] && echo "   Submitting WRF experiment ${EXP} on ${MAC}: NEXTSTEP(WRF)=${NEXTSTEP}; NOWPS=${NOWPS}."

# Add extra display line, if applicable
[ $VERBOSITY -gt 0 ] && echo

# Launch WRF (required vars: INIDIR, NEXTSTEP, WRFSCRIPT, NOWPS, RSTCNT)
if [ -z "$ALTSUBJOB" ] || [[ "$MAC" == "$SYSTEM" ]]
  then eval "${RESUBJOB}" # On the same machine (default).
  else eval "${ALTSUBJOB}" # Alternate/remote command.
fi 

# Add extra display line, if applicable
[ $VERBOSITY -gt 0 ] && echo

# Exit with 0 exit code (if anything went wrong we would already have aborted)
exit 0







