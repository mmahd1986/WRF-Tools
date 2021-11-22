#!/bin/bash

# Script to perform pre-processing and submit a WPS job before the next job starts.
# Andre R. Erler, 28/02/2013.


# The following environment variables have to be set by the caller:
# INIDIR, WRFSCRIPT, SUBMITWPS, NEXTSTEP and NOWPS (optional)


# Launch WPS for next step (if $NEXTSTEP is not empty and not NOWPS)
# NOTE: This is only for the first instance; unset for next one.
if [[ -n "${NEXTSTEP}" ]] && [[ "${NOWPS}" != 'NOWPS' ]]
then  
    
    # Prompt on screen
    echo
    echo "   ================================== Launching WPS for next step: ${NEXTSTEP} ================================== "
    echo
    
    # Submitting independent WPS job
    set -x 
    # NOTE: "set -x" means print commands and their arguments as they are executed.
    eval "${SUBMITWPS}" # Uses variables: $INIDIR, $DEPENDENCY, $NEXTSTEP.
    # NOTE: The queue selection process happens in the launch command ($SUBMITWPS),
    #   which is set in the setup-script.
    set +x
    # NOTE: Using a + rather than - causes set flags to be turned off.

else

    echo
    echo '   ================================== Skipping WPS ================================== '
    echo

fi 
