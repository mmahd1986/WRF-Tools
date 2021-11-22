#!/bin/bash

# Script to resubmit next job after current job completed.
# Andre R. Erler, 28/02/2013.


# The following environment variables have to be set by the caller:
# INIDIR, RSTDIR, WRFSCRIPT, RESUBJOB, NEXTSTEP, NOWPS


# Set default for $NOWPS and $RSTCNT (to avoid problems when passing variables to next job)
NOWPS=${NOWPS:-'WPS'} # Launch WPS, unless instructed otherwise.
RSTCNT=${RSTCNT:-0} # Assume no restart by default.
# NOTE: $NEXTSTEP is handled below.

# Launch WRF for next step (if $NEXTSTEP is not empty)
if [[ -n "${NEXTSTEP}" ]]
then

  # Read date string for restart file
  RSTDATE=$(sed -n "/${NEXTSTEP}/ s/${NEXTSTEP}[[:space:]]\+'\([-_\:0-9]\{19\}\)'[[:space:]]\+'[-_\:0-9]\{19\}'$/\1/p" stepfile)
  # NOTE: \+ is as *, but matches one or more.
  # NOTE: [-_\:0-9] means any of - or _ or : or 0-9.
  # NOTE: \{19\} means the previous charachter, etc, but 19 times. 
  # NOTE: '[[:space:]]' also matches tabs; '\ ' only matches one space.   
    
  # If we could not find ${RSTDATE}
  if [[ -z "${RSTDATE}" ]]
  then 
    echo
    echo '   ERROR: Cannot read step file - aborting!   '
    echo
    echo '   Current PATH variable:'
    echo -n '   '
    echo "${PATH}"
    echo
    echo '   sed executable:'
    echo -n '   '
    which sed
    echo
    echo '   Stepfile line:'
    echo -n '   '
    grep "${NEXTSTEP}" stepfile        
    echo
    echo '   stepfile stat:'
    stat stepfile
    echo
    exit 1
  fi 

  # Move into next work dir  
  NEXTDIR="${INIDIR}/${NEXTSTEP}" 
  cd "${NEXTDIR}"
    
  # Prompt on screen
  echo
  echo "   ================================== Linking restart files to next working directory =================================="
  echo
  echo -n '   Next working directory: '
  echo "${NEXTDIR}"
  
  # Link restart files
  for RESTART in "${RSTDIR}"/wrfrst_d??_${RSTDATE//:/[_:]}; do 
  # NOTE: ${parameter/pattern/string} replaces the first occurrence of a pattern 
  #   with a given string. To replace all occurrences, we use ${parameter//pattern/string}. 
  # NOTE: The above matches both hh:mm:ss and hh_mm_ss.
    ln -sf "${RESTART}"; done  
    
  # Wait for the WPS to complete
  # NOTE: This option can potentially waste a lot of wall time and should be used with caution.
  if [[ "${WAITFORWPS}" == 'WAIT' ]] &&  [[ ! -f "${WPSSCRIPT}" ]]
  # NOTE: The -f verifies two things: The provided path exists and is a regular file. 		  
  then
    echo
    echo "   Waiting for WPS to complete ... "
    while [[ ! -f "${WPSSCRIPT}" ]]; do
      sleep 30 
    done
  fi
  # NOTE: The above method was the initial choice for waiting for WPS to finish before moving on,
  #   when WRF TOOLS was first developed. However, this leads to a lot of cpus waiting for a 
  #   potentially long time. So Andre changed this. WAITFORWPS is now not 'WAIT' by default and 
  #   the method in the next IF is used to submit a sleeper job that waits ON A SINGLE PROCESS
  #   until the WPS has finished running (much less costly). This is done through running startCycle
  #   and using QWAIT to check when the WPS is done. WPS is not ran again (--skipwps option is used
  #   inside sleeper job submission), but after the wait is over next step WPS is ran and then WRF.   

  # Go back to initial directory
  cd "${INIDIR}"            
                        
  # If WPS has finished
  if [[ -f "${NEXTDIR}/${WPSSCRIPT}" ]]
  then
    
    # If we find that REAL ran successfully    
    if [ 0 -lt $(grep -c 'SUCCESS COMPLETE REAL_EM INIT' "${NEXTDIR}/real/rsl.error.0000") ]
    then
            
      # Prompt on screen
      echo
      echo "   ================================== Launching WRF for next step: ${NEXTSTEP} =================================="
      echo
      
      # Submit next job (start next cycle)      
      set -x
      # NOTE: "set -x" prints commands and their arguments as they are executed.
      eval "${RESUBJOB}" 
      ERR=$? # Capture exit status.
      set +x
      # NOTE: In set, using + rather than - causes flags to be turned off.
      exit $? # Exit with exit status from reSubJob.
				    
    # If we find that REAL did not run successfully
    else 

      # Prompt on screen and exit
      echo
      echo "   WPS for next step (${NEXTSTEP}) failed --- aborting! "
      echo
      exit 1
		    
    fi 
		
  # If WPS has not finished (yet)
  else 
	    
    # Start a sleeper job, if available
    if [[ -n "{SLEEPERJOB}" ]]
    then
            
      # Prompt on screen
      echo
      echo "   WPS for next step (${NEXTSTEP}) has not finished yet. "
      echo "   Launching sleeper job to restart WRF when WPS finishes. "
      echo "   See log file below for details and job status. "
      echo
            
      # Submit sleeper script (set in setup-script; machine-specific)
      set -x
      eval "${SLEEPERJOB}" 
      ERR=$? # Capture exit status.
      set +x
      exit $? # Exit with exit status from SLEEPERJOB.
		    
    # If we can not start a sleeper job
    else 

      # Prompt on screen and exit 
      echo
      echo "   WPS for next step (${NEXTSTEP}) failed --- aborting! "
      echo
      exit 1
                        
    fi 
		    		  
  fi 
    
# If $NEXTSTEP is empty
else
  
  # Prompt on screen and exit
  echo
  echo '   No $NEXTSTEP --- cycle terminated. '
  echo '   No more jobs have been submitted. '
  echo
  exit 0 # This is most likely Ok.

fi 









