#!/bin/bash

# Script to automatically restart job after a crash due to numerical instability.
# Andre R. Erler, created 21/08/2013, revised 04/03/2014.


# The following environment variables have to be set by the caller:
# INIDIR, WORKDIR, SCRIPTDIR, CURRENTSTEP, WRFSCRIPT, RESUBJOB
# Optional: 
# AUTORST, MAXRST, DEL_DELT, MUL_EPSS, ENU_SNDT, DEN_SNDT
# NOTE: The variable RSTCNT is default-set and reused by this script, so it should  
#   also be passed on by the caller.


# Restart parameters
AUTORST=${AUTORST:-'RESTART'} # Restart once by default.
MAXRST=${MAXRST:--1} # This can be set externally (default here -1).
RSTCNT=${RSTCNT:-0} # We need to initialize, in case it is not set.
# NOTE: The default settings and behavior is for backward compatibility. 

# Stability parameters
DEL_DELT=${DELT:-'30'} # Negative time-step increment ($DELT is set in run-script).
MUL_EPSS=${MUL_EPSS:-'0.50'} # epssm factor.
ENU_SNDT=${ENU_SNDT:-5} # Sound time step enumerator.
DEN_SNDT=${DEN_SNDT:-4} # Sound time step denominator.


# Initialize Error counter
ERR=0

# Restart, if applicable
if [[ "${AUTORST}" == 'RESTART' ]]  
then

  # Parse WRF log file (rsl.error.0000) to check if crash occurred during run-time
  cd "${WORKDIR}"
  if [[ -e 'wrf/rsl.error.0000' ]] && [[ -n $(grep 'Timing for main:' 'wrf/rsl.error.0000') ]]
  # NOTE: [ -e FILE ] is true if FILE exists.
  then RTERR='RTERR'
  else RTERR='NO'
  fi

  # Check for known non-run-time errors
  if grep -q "Error in \`mpiexec.hydra': corrupted size vs. prev_size:" ${INIDIR}/${SLURM_JOB_NAME}.${SLURM_JOB_ID}.out; then

    # Move into ${INIDIR}
    cd "${INIDIR}"

    # Prompt on screen
    echo
    echo "   The mpiexec.hydra corrupted size error has occured. Restarting."
    echo

    # Export parameters as needed
    export RSTDIR # Set in job script; usually output dir.
    export NEXTSTEP="${CURRENTSTEP}"
    export NOWPS='NOWPS' # Do not submit another WPS job.
    export RSTCNT # Restart counter, set above.

    # Resubmit job for next step
    export WAITTIME=120
    set -x
    eval "${SLEEPERJOB}" # This requires submission command from setup script.
    set +x
    ERR=$(( ${ERR} + $? )) # Update exit code.

  # Restart if error occurred at run-time, not if it is an initialization error
  elif [[ "${RTERR}" == 'RTERR' ]]
  then

    # If RSTCNT >= MAXRST
    if [ ${RSTCNT} -gt ${MAXRST} ]; then
    # NOTE: "-ge" means greater than or equal to.
    # NOTE: This happens, if RSTCNT or MAXRST were set incorrectly or not set at all.
      
      echo
      echo "   No auto-restart because restart counter (${RSTCNT}) exceeds maximum number of restarts (${MAXRST}) "
      echo "      (i.e. RSTCNT and/or MAXRST were set to an invalid value, intentionally or unintentionally)."
      echo
      ERR=$(( ${ERR} + 1 )) # Increase exit code.
    
    # If $RSTCNT < $MAXRST
    else    
    # NOTE: The question here is: Is numerical instability the only error that can 
    #   happen during run-time? The answer is: If you set up your model correctly, 
    #   and there are no issues with the system itself, it is by far the most common 
    #   error, so it makes sense to assume that first, before wasting your time on 
    #   investigation. 
		            
      # Parse current namelist for stability parameters
      cd "${WORKDIR}"
      CUR_DELT=$(sed -n '/time_step/ s/^\s*time_step\s*=\s*\([0-9]*\).*$/\1/p' namelist.input) # Time step.
      # NOTE: "\s" matches whitespace characters (spaces and tabs). Newlines embedded 
      #   in the pattern will also match.
      CUR_SNDT=$(sed -n '/time_step_sound/ s/^\s*time_step_sound\s*=\s*\([0-9]*\).*$/\1/p' namelist.input) # Sound time step multiplier.
      # NOTE: This assumes time_step_sound is an integer.
      CUR_EPSS=$(sed -n '/epssm/ s/^\s*epssm\s*=\s*\([0-9]\?.[0-9]*\).*$/\1/p' namelist.input) # epssm parameter.  
      # NOTE: "\?" is as *, but only matches zero or one times (so that [0-9]\?.5 
      #   matches .5 and 0.5).

      # Parse default namelist for stability parameters
      cd "${INIDIR}"
      INI_DELT=$(sed -n '/time_step/ s/^\s*time_step\s*=\s*\([0-9]*\).*$/\1/p' namelist.input) # Time step.
	
      # The restart will only be triggered, if: 
      #   1) The timestep has not been changed yet (no previous restart),
      #   or
      #   2) The restart counter is set and larger than 0 (and smaller than MAXRST)
      #      and 
      #      the timestep is larger than the DELT increment.
      if  [ ${RSTCNT} -gt 0 ] && [ ${CUR_DELT} -gt ${DEL_DELT} ] || [ ${CUR_DELT} -eq ${INI_DELT} ]
      # NOTE: In single brackets the < > operators act as in shell commands; So 
      #   for the comparison purposes, -lt and -gt have to be used.
      then
		
        # Increment restart counter 
        RSTCNT=$(( $RSTCNT + 1 )) 
        # NOTE: If RSTCNT is not defined, 0 is assumed and the result will be 1.
	
        # Calculate new stability parameters			    
        NEW_DELT=$( echo "${CUR_DELT} - ${DEL_DELT}" | bc ) # Decrease time step by fixed amount.
        NEW_SNDT=$( echo "${ENU_SNDT}*${CUR_SNDT}/${DEN_SNDT}" | bc ) # Change time_step_sound parameter.
        NEW_EPSS=$( echo "1.00 - ${MUL_EPSS}*(1.00 - ${CUR_EPSS})" | bc ) # Increase epssm parameter.
        # NOTE: We need to use bc for floating-point math. bc is a language that supports arbitrary 
        #   precision numbers with interactive execution of statements. There are some similarities 
        #   in the syntax to the C programming language. 
        
        # Check if new time step is less than or equal to zero
        if  [ ${NEW_DELT} -le 0 ]
        then
        
          echo
          echo "   No auto-restart because new dt becomes zero or negative."
          echo
          ERR=$(( ${ERR} + 1 )) # Increase exit code.
        
        # If new dt is positive
        else  	
			    
          # Change namelist entries accordingly
          cd "${WORKDIR}"
          sed -i "/time_step/ s/^\s*time_step\s*=\s*[0-9]*.*$/ time_step = ${NEW_DELT}, ! Edited by the auto-restart script; previous value: ${CUR_DELT}./" namelist.input
          sed -i "/time_step_sound/ s/^\s*time_step_sound\s*=\s*[0-9]*.*$/ time_step_sound = ${NEW_SNDT}, ${NEW_SNDT}, ${NEW_SNDT}, ${NEW_SNDT}, ! Edited by the auto-restart script; previous value: ${CUR_SNDT}./" namelist.input
					# some special options that work more aggressively
          if [ ${RSTCNT} -gt 2 ]; then
            echo "   RSTCNT > 2: turning off sf_urban_physics and setting epssm = 1."
            sed -i "/epssm/ s/^\s*epssm\s*=\s*[0-9]\?.[0-9]*.*$/ epssm = 1., 1., 1., 1., ! Edited by the auto-restart script; previous value: ${CUR_EPSS}./" namelist.input    
            sed -i "/sf_urban_physics/ s/^\s*sf_urban_physics\s*=\s*.*$/ sf_urban_physics = 0., 0., 0., 0., ! Edited by the auto-restart script./" namelist.input    
          else
            sed -i "/epssm/ s/^\s*epssm\s*=\s*[0-9]\?.[0-9]*.*$/ epssm = ${NEW_EPSS}, ${NEW_EPSS}, ${NEW_EPSS}, ${NEW_EPSS}, ! Edited by the auto-restart script; previous value: ${CUR_EPSS}./" namelist.input    
          fi # RSTCNT > 2
          
          # Move into ${INIDIR}
          cd "${INIDIR}"
        
          # Prompt on screen
          echo
          echo "   Modified namelist parameters for auto-restart.   "    
          echo "   This is restart attempt number ${RSTCNT} of ${MAXRST}."
          echo "      TIME_STEP = ${NEW_DELT}."
          echo "      EPSSM = ${NEW_EPSS}."
          echo "      TIME_STEP_SOUND = ${NEW_SNDT}."
          echo
			    
          # Export parameters as needed
          export RSTDIR # Set in job script; usually output dir.
          export NEXTSTEP="${CURRENTSTEP}"
          export NOWPS='NOWPS' # Do not submit another WPS job.
          export RSTCNT # Restart counter, set above.
			    					
	  # Resubmit job for next step
          eval "${SCRIPTDIR}/resubJob.sh" # This requires submission command from setup script.
          ERR=$(( ${ERR} + $? )) # Update exit code.
          
        fi
	      
      # Otherwise, e.g., when stability parameters have been changed
      else 
	
        # Print appropriate error message
	echo
        if [[ 0 == ${MAXRST} ]]; then 
          echo "   No auto-restart because maximum number of restarts is set to 0 "
          echo "   (one restart may have been performed nevertheless)."
        elif [[ ${RSTCNT} == ${MAXRST} ]]; then 
          echo "   No auto-restart because maximum number of restarts (${MAXRST}) has been reached "
          echo "   (a severe numberical instability is likely!). "
        elif [ ${CUR_DELT} -le ${DEL_DELT} ]; then 
          echo "   No auto-restart because the time step would become negative! "
          echo "   Consider reducing the maximum number of restarts. "        
        else
          echo "   No auto-restart because namelist parameters have been modified "
          echo "   (and no restart counter was set; likely due to manual restart). "
        fi
					
	# Prompt on screen
	echo
	echo "   TIME_STEP  = ${CUR_DELT};   EPSSM  = ${CUR_EPSS};   TIME_STEP_SOUND  = ${CUR_SNDT}."
	echo
	
	# Increase exit code
	ERR=$(( ${ERR} + 1 )) 
	      
      fi 

    fi 

  # Crash did not occur at run time (i.e. not during time-stepping)
  else 
    
      # Print error message
    echo
    echo "   No auto-restart because the crash did not occur during run-time or via a known non-run-time mechanism! "
    echo "   A numerical instability is unlikely."
    echo
    
    # Increase exit code
    ERR=$(( ${ERR} + 1 )) 

  fi 

fi 


# Exit with number of errors as exit code
exit ${ERR} 










