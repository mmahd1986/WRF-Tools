# #!/bin/bash

# Script to perform post-processing and submit an archive job after the main job completed.
# Andre R. Erler, 28/02/2013.


# The following environment variables have to be set by the caller:
# INIDIR, SUBMITAR, CURRENTSTEP, NEXTSTEP, ARSCRIPT, AVGSCRIPT and ARINTERVAL (optional)


# ===========================================================================
# ==== Function that gives error if step name does not conform to naming ====
# ==== convention for archive interval.                                  ====
# ===========================================================================
# NOTE: This function uses global namespace and has no arguments.

function INTERVALERROR () { 
  echo
  echo "   Archive Error: Step name does not conform to naming convention for archive interval. "
  echo "      Step name: ${CURRENTSTEP}"
  echo "      Archive interval: ${ARINTERVAL}"
  echo
  exit 1 # Exit immediately with error.
} 


# ===============================================================================
# ==== Function to decide to launch or not and determine date parameter/tag. ====
# ===============================================================================
# NOTE: This mechanism assumes that step names represent dates in the format YYYY-MM-DD.

function CHECKINTERVAL () {

  # Input parameters
  local INTERVAL="${1}" # The string identifying the interval.
  local CURRENT="${2}" # The current step.
  local NEXT="${3}" # The next step.
  
  # Initialize the return parameter TAG
  TAG=''  
  
  # Find the TAG, if INTERVAL is yearly
  if [[ "${INTERVAL}" == 'YEARLY' ]]; then
  
    # Get current year
    CY=$( echo "${CURRENT}" | cut -d '-' -f 1 )
    # NOTE: The cut is a command-line utility that allows you to cut parts of lines 
    #   from specified files or piped data and print the result to standard output.
    #   "-d" is used to specify a delimiter that will be used instead of the default 
    #   TAB delimiter. "-f" is used to select by specifying a field, a set of fields, 
    #   or a range of fields.     
    
    # If we can't get current year
    if [[ -z "${CY}" ]]; then INTERVALERROR; fi 
    
    # Get next year
    NY=$( echo "${NEXT}" | cut -d '-' -f 1 )
    
    # Get TAG, if possible
    if [[ "${CY}" != "${NY}" ]]; then TAG="${CY}"; fi 
    # NOTE: If interval is yearly, we expect CY and NY to be different. Only
    #   then, we get a tag (CY).
  
  # Find the TAG, if INTERVAL is monthly
  elif [[ "${INTERVAL}" == 'MONTHLY' ]]; then
  
    # Get current year
    CY=$( echo "${CURRENT}" | cut -d '-' -f 1 )
    
    # Get current month
    CM=$( echo "${CURRENT}" | cut -d '-' -f 2 )
    
    # If we can't get current month
    if [[ -z "${CM}" ]]; then INTERVALERROR; fi 
    
    # Get next month
    NM=$( echo "${NEXT}" | cut -d '-' -f 2 )
    
    # Get TAG, if possible
    if [[ "${CM}" != "${NM}" ]]; then TAG="${CY}-${CM}"; fi 
    # NOTE: If interval is monthly, we expect CM and NM to be different. Only
    #   then, we get a tag (CY-CM).
  
  # Find the TAG, if INTERVAL is daily
  elif [[ "${INTERVAL}" == 'DAILY' ]]; then
  
    # Get current year
    CY=$( echo "${CURRENT}" | cut -d '-' -f 1 )
    
    # Get current month
    CM=$( echo "${CURRENT}" | cut -d '-' -f 2 )
    
    # Get current day
    CD=$( echo "${CURRENT}" | cut -d '-' -f 3 )
    
    # If we can't get current day
    if [[ -z "${CD}" ]]; then INTERVALERROR; fi 
    
    # Get next day
    ND=$( echo "${NEXT}" | cut -d '-' -f 3 )
    
    # Get TAG, if possible
    if [[ "${CD}" != "${ND}" ]]; then TAG="${CY}-${CM}-${CD}"; fi 
    # NOTE: If interval is daily, we expect CD and ND to be different. Only
    #   then, we get a tag (CY-CM-CD).
  
  # Find the TAG, otherwise 
  else
  
    # TAG is just ${CURRENT}
    TAG="${CURRENT}"
  
  fi 
  
  # Return TAG string
  echo "${TAG}" 
  # NOTE: Return only takes exit codes. Strings have to be returned via echo.

} 


# =======================================================================================
# ======================== Launch archive script, if specified ==========================
# =======================================================================================
 
if [[ -n "${ARSCRIPT}" ]]
then

  # Test interval and date parameter
  ARTAG=$( CHECKINTERVAL "${ARINTERVAL}" "${CURRENTSTEP}" "${NEXTSTEP}" )
    
    # Collect logs and launch archive job
    if [[ -n "${ARTAG}" ]]
    then
	      
      # Collect and archive logs
      echo
      echo "   Cleaning up and archiving log files in ${ARTAG}_logs.tgz. "
      cd "${INIDIR}"
      tar czf "${WRFOUT}/${ARTAG}_logs.tgz" *.out # *.out means all log files.
      # NOTE: For tar "-c" means create a new archive, "-z" means filter the 
      #   archive through gzip, and "-f" gives the output tar file name.
      mkdir -p "${INIDIR}/logs" # Make sure log folder exists.
      # NOTE: For mkdir, "-p" means no error if existing, and make parent 
      #   directories as needed.
      mv *.out "${INIDIR}/logs" # Move log files to log folder.
	      
      # Launch archive job
      echo
      echo "   ================================== Launching archive script for WRF output: ${ARTAG} ================================== "
      echo
      set -x
      # NOTE: The "set -x" command prints commands and their arguments during execution.
      eval "${SUBMITAR}" 
      # NOTE: This uses variables: $ARTAG, and $ARINTERVAL.
      # NOTE: This uses these default options: TAGS=${ARTAG}, MODE=BACKUP, and 
      #   INTERVAL=${ARINTERVAL}. Additional default options set in archive 
      #   script: RMSRC, VERIFY, DATASET, DST, and SRC.
      set +x
      # NOTE: "set +x" reverses the effects of "set -x".      
    
    fi 
    
    # Also launch another archive job, if this is the final step (according to Andre, 
    #   this is mainly for the last restart files, which otherwise would get missed, 
    #   but also includes static.tgz and it may also contain wrfconst).
    # NOTE: If this action triggers, a regular archive job for the last interval should
    #   already have been submitted. This should also be the case, when the archive 
    #   interval does not coincide with the last step ($CURRENTSTEP will be
    #   different from $NEXTSTEP, because $NEXTSTEP will be empty).
    if [[ -n "${CURRENTSTEP}" ]] && [[ -z "${NEXTSTEP}" ]]
    then
				
      # Prompt on screen
      echo
      echo "   ================================== Launching FINAL archive job for WRF experiment clean-up ================================== "
      echo
      
      # Check if ARTAG is set (just a precaution)
      if [[ -z "${ARTAG}" ]] 
      then echo "   WARNING: No regular archive job was submitted for the final stage!"; fi
	      
      # Set $ARTAG environment variable to communicate command
      ARTAG='FINAL'
      
      # Launch archive job
      set -x
      eval "${SUBMITAR}" 
      set +x
      # NOTE: This uses variables: $ARTAG, and $ARINTERVAL.
      # NOTE: This uses these default options: TAGS=${ARTAG}, MODE=BACKUP, and 
      #   INTERVAL=${ARINTERVAL}. Additional default options set in archive 
      #   script: RMSRC, VERIFY, DATASET, DST, and SRC.
    
    fi 

fi 


# =======================================================================================
# ======================= Launch averaging script, if specified =========================
# =======================================================================================
 
if [[ -n "${AVGSCRIPT}" ]]
then

    # Test interval and date parameter
    AVGTAG=$( CHECKINTERVAL "${AVGINTERVAL}" "${CURRENTSTEP}" "${NEXTSTEP}" )
    
    # Launch averaging job, if applicable
    if [[ -n "${AVGTAG}" ]]
    then
        echo
        echo "   ================================== Launching averaging script for WRF output: ${AVGTAG} ================================== "
        echo
        set -x
        eval "${SUBMITAVG}" 
        set +x
        # NOTE: This uses variables: $AVGTAG, and $AVGINTERVAL.        
    fi 

fi 







