#!/bin/bash

# Driver script to run WRF pre-processing: Runs pyWPS.py and real.exe on RAM disk.
# Created 25/06/2012 by Andre R. Erler, GPL v3.


# Variables defined in driver script:
# $TASKS, $THREADS, $HYBRIDRUN, $WORKDIR, $RAMDISK
# Optional arguments:
# $RUNPYWPS, $METDATA, $RUNREAL, $REALIN, $RAMIN, $REALOUT, $RAMOUT


# =================================================================================
# ============================ Prepare the environment ============================
# =================================================================================

# Script and executable locations
SCRIPTDIR=${SCRIPTDIR:-"${INIDIR}/scripts/"} 
BINDIR=${BINDIR:-"${INIDIR}/bin/"} 
# NOTE: These are most likely defined in the calling script previously.

# NOCLOBBER option
NOCLOBBER=${NOCLOBBER:-'-n'} 
# NOTE: For 'cp', '-n' option prevents overwriting existing files.

# RAM disk
RAMDATA="${RAMDISK}/data/" # Data folder used by the Python script.
RAMTMP="${RAMDISK}/tmp/" # Temporary folder used by the Python script.

# Related to pyWPS.py
RUNPYWPS=${RUNPYWPS:-1} # Whether to run pyWPS.py.
DATATYPE=${DATATYPE:-'CESM'} # Data source (also see $PYWPS_DATA_SOURCE).
PYLOG="pyWPS" # Log folder for Python script (use relative path for tar ?????).
PYTGZ="${RUNNAME}_${PYLOG}.tgz" # Archive for log folder.
METDATA=${METDATA:-''} # Folder to store metgrid data on disk (has to be absolute path).
# NOTE: Leave METDATA undefined to skip disk storage. Defining $METDATA will set 
#   "ldisk = True" in pyWPS.

# Related to real.exe, RAMIN, RAMOUT and RAMIN_CHANGED
RUNREAL=${RUNREAL:-1} # Whether to run real.exe.
REALIN=${REALIN:-"${METDATA}"} # Location of metgrid files.
REALTMP=${REALTMP:-"./metgrid"} # In case path to metgrid data is too long. ?????
RAMIN=${RAMIN:-1} # Copy input data to ramdisk or read from HD.
REALOUT=${REALOUT:-"${WORKDIR}"} # Output folder for WRF input data.
RAMOUT=${RAMOUT:-1} # Write output data to ramdisk or directly to HD.
REALLOG="real" # Log folder for real.exe.
REALTGZ="${RUNNAME}_${REALLOG}.tgz" # Archive for log folder.
RAMIN_CHANGED=${RAMIN_CHANGED:-0} # If RAMIN was changed.
# NOTE: RAMIN is changed artificially, if initally RAMIN=0 & METDATA is not set.
WRFWAIT="${WRFWAIT:-''}" # By default, don't wait.
# NOTE: WRFWAIT is optional delay for file system to settle down before launching WRF.

# Copy execWPS.sh into WORKDIR
cp "${SCRIPTDIR}/execWPS.sh" "${WORKDIR}"
# NOTE: Here we assume working directory is already present.


# =================================================================================
# ======================== Run WPS driver script: pyWPS.py ========================
# =================================================================================

# Run pyWPS, if applicable
if [[ ${RUNPYWPS} == 1 ]]
then

  # Prompt on screen
  echo
  echo '   ******************** Running WPS ******************** '
  
  # Handle a special case for WPS output data storage
  if [[ "${RAMIN}" == 0 ]] && [[ -z  "${METDATA}" ]] 
  then
    echo
    echo "   Using disk folder ${RAMDISK} as temporary work folder instead of RAM disk."
    RAMIN=1
    export RAMDISK="$WORKDIR/ram_disk/"
    RAMDATA="${RAMDISK}/data/" 
    RAMTMP="${RAMDISK}/tmp/" 
    RAMIN_CHANGED=1
  fi 
  # NOTE: If RAMIN=0 and METDATA is not set, then the ${WORKDIR}/data/ folder will
  #   not be created in pyWPS.sh because ldata (or quivalantly PYWPS_KEEP_DATA or 
  #   equivalantly RAMIN) is set to false. As the Tmp folder is also deleted in 
  #   this script before REAL is run, the data would be lost and real would not 
  #   have an input. Therefore, for this case, we artifically change RAMIN to 1 and
  #   set RAMDISK to an alternative disk path (and update RAMDATA and RAMTMP) above.
  #   The variable RAMIN_CHANGED is to keep track of this artifical change and
  #   reset the code at the end of this script. 
  
  # Remove and recreate the temporary ramdisk data folder
  rm -rf "${RAMDATA}"
  mkdir -p "${RAMDATA}" 
  # NOTE: 'mkdir $RAMTMP' is actually done by the Python script.
  
  # Move into ${INIDIR}   
  cd "${INIDIR}"
    
  # Copy pyWPS.py and metgrid.exe into WORKDIR
  cp ${NOCLOBBER} -P "${BINDIR}/pyWPS.py" "${BINDIR}/metgrid.exe" "${WORKDIR}"    
  # NOTE: "-P" means never follow symbolic links in SOURCE (in "cp [OPTIONS] SOURCE DEST").
    
  # Copy files/links for source data: CESM/CCSM global climate model 
  if [[ "${DATATYPE}" == 'CESM' || "${DATATYPE}" == 'CCSM' ]]; then 
    cp ${NOCLOBBER} -P "${INIDIR}/atm" "${INIDIR}/lnd" "${INIDIR}/ice" "${WORKDIR}"
    cp ${NOCLOBBER} -P "${BINDIR}/unccsm.ncl" "${BINDIR}/unccsm.exe" "${WORKDIR}"
  # Copy files/links for source data: CFSR reanalysis data
  elif [[ "${DATATYPE}" == 'CFSR' ]]; then 
    cp ${NOCLOBBER} -P "${INIDIR}/plev" "${INIDIR}/srfc" "${WORKDIR}"
    cp ${NOCLOBBER} -P "${BINDIR}/ungrib.exe" "${WORKDIR}"
  # Copy files/links for source data: CMIP5 global climate model series data  
  elif [[ "${DATATYPE}" == 'CMIP5' ]]; then 
    # cp ${NOCLOBBER} -P "${INIDIR}/MIROC5_rcp85_2085_pointer_local_full.validate.nc" "${WORKDIR}/CMIP5data.validate.nc"      
    # NOTE: This copies the validate file used by cdb_query.
    cp ${NOCLOBBER} -P "${INIDIR}/init" "${WORKDIR}" # Copy the initial step data.
    cp ${NOCLOBBER} -P "${BINDIR}/unCMIP5.ncl" "${BINDIR}/unccsm.exe" "${WORKDIR}" # Copy the executables.
    find ./meta -maxdepth 1 -name "*validate*" -exec cp ${NOCLOBBER} -P {} "${WORKDIR}/CMIP5data.validate.nc" \;
    # NOTE: '{}' in the above gets passed on the find outputs. The exec part should be termianted with a "\;".
    # cp ${NOCLOBBER} -P "${INIDIR}/orog_fx_MIROC5_rcp85_r0i0p0.nc" "${WORKDIR}/orog_file.nc" # This was commented. Why? ?????      
    # NOTE: This copies the coordinate files used by unCMIP5.ncl.
    find ./meta -maxdepth 1 -name "*orog*" -exec cp ${NOCLOBBER} -P {} "${WORKDIR}/orog_file.nc" \;
    # cp ${NOCLOBBER} -P "${INIDIR}/sftlf_fx_MIROC5_rcp85_r0i0p0.nc" "${WORKDIR}/sftlf_file.nc" # This was commented. Why? ?????     
    find ./meta -maxdepth 1 -name "*sftlf*" -exec cp ${NOCLOBBER} -P {} "${WORKDIR}/sftlf_file.nc" \;
    # cp ${NOCLOBBER} -P "${INIDIR}/MIROC5_ocn2atm_linearweight.nc" "${WORKDIR}/ocn2atmweight_file.nc" # This was commented. Why? ?????     
    find ./meta -maxdepth 1 -name "*linearweight*" -exec cp ${NOCLOBBER} -P {} "${WORKDIR}/ocn2atmweight_file.nc" \;
  # Copy files/links for source data: CMIP6 projection data
  elif [[ "${DATATYPE}" == 'CMIP6' ]]; then
    cp ${NOCLOBBER} -P "${INIDIR}/cmip6_data" "${WORKDIR}"
    cp ${NOCLOBBER} -P "${BINDIR}/unCMIP6.py" "${WORKDIR}"
  # Copy files/links for source data: ERA-I reanalysis data
  elif [[ "${DATATYPE}" == 'ERA-I' ]]; then
    cp ${NOCLOBBER} -P "${INIDIR}/uv" "${INIDIR}/sc" "${INIDIR}/sfc" "${WORKDIR}"
    cp ${NOCLOBBER} -P "${BINDIR}/ungrib.exe" "${WORKDIR}"
  # Copy files/links for source data: ERA5 reanalysis data
  elif [[ "${DATATYPE}" == 'ERA5' ]]; then
    cp ${NOCLOBBER} -P "${INIDIR}/pl" "${INIDIR}/sl" "${WORKDIR}"
    cp ${NOCLOBBER} -P "${BINDIR}/fixIM.py" "${WORKDIR}"
    cp ${NOCLOBBER} -P "${BINDIR}/ungrib.exe" "${WORKDIR}"  
  fi # $DATATYPE
  
  # Copy meta folder, geo_em files & namelist.wps file (or their links) into ${WORKDIR}
  cp ${NOCLOBBER} -r "${INIDIR}/meta/" "${WORKDIR}"
  cp ${NOCLOBBER} -P "${INIDIR}/"geo_em.d??.nc "${WORKDIR}" 
  # NOTE: In shell, the asterisk represents zero or more characters, while
  #   the question mark represents only one character.
  # NOTE: geo_em files are in geo_em.d01.nc, geo_em.d02.nc, etc format.
  cp ${NOCLOBBER} "${INIDIR}/namelist.wps" "${WORKDIR}" 

  # Set OpenMP environment
  export OMP_NUM_THREADS=1 
  
  # Environment variables required by Python script pyWPS
  export PYWPS_THREADS=$(( TASKS*THREADS ))
  # NOTE: The (( ... )) construct permits arithmetic expansion and evaluation. 
  #   In its simplest form, a=$(( 5 + 3 )) would set a to 5 + 3, or 8. However, 
  #   this double-parentheses construct is also a mechanism for allowing C-style 
  #   manipulation of variables in Bash, for example, (( var++ )).
  export PYWPS_DATA_TYPE="${DATATYPE}"
  export PYWPS_KEEP_DATA="${RAMIN}"
  export PYWPS_MET_DATA="${METDATA}"
  export PYWPS_RAMDISK="${RAMIN}"
  
  # Prompt on screen
  echo
  echo "   OMP_NUM_THREADS=${OMP_NUM_THREADS}"
  echo "   PYWPS_THREADS=${PYWPS_THREADS}"
  echo "   PYWPS_DATA_TYPE=${DATATYPE}"
  echo "   PYWPS_KEEP_DATA=${RAMIN}"
  echo "   PYWPS_MET_DATA=${METDATA}"
  echo "   PYWPS_RAMDISK=${RAMIN}"
  echo
  echo "   Running ""python pyWPS.py""."
  echo
  if [[ -n "${METDATA}" ]];
  then 
    echo "   Writing metgrid files to ${METDATA}."
  else 
    echo "   Not writing metgrid files to disk."
  fi

  # Run and time main pre-processing script (this script is in python)
  cd "${WORKDIR}" # Move into current working directory.      
  eval "time -p python pyWPS.py"
  PYERR=$? # Save the error code (and later pass on to exit).    
  # NOTE: "$?" is used to find the return value of the last executed 
  #   command. Trying "ls <somefile>; echo $?", if somefile exists 
  #   (regardless of whether it is a file or directory), you will get 
  #   the return value thrown by the ls command, which should be 0 
  #   (default "success" return value). If it doesn't exist, you should 
  #   get a number other then 0. The exact number depends on the program.
  #   For many programs you can find the numbers and their meaning in 
  #   the corresponding man page. These will usually be described as 
  #   "exit status" and may have their own section.  
  echo
  wait

  # Remove data files
  rm -f "${RAMTMP}"/*.nc "${RAMTMP}"/*/*.nc 
  
  # NOTE: When RAMIN is set to 0 by the user and -n METDATA, then in a few places, 
  #   such as the above rm -f, we may get errors due to being unable to delete or make 
  #   files or folders (e.g., if we do not have access to ram), etc. However, these
  #   are minor errors and the code should work overall. These errors were not fixed 
  #   at the moment, due to their lower priority. 

  # Remove existing logs
  rm -rf "${WORKDIR}/${PYLOG}/" 

  # Copy log files to disk
  cp -r "${RAMTMP}" "${WORKDIR}/${PYLOG}/" # Copy entire folder and rename.  
    
  # Remove RAMTMP folder 
  rm -rf "${RAMTMP}"
    
  # Archive log files
  tar cf - "${PYLOG}/" | gzip > ${PYTGZ} 
  # NOTE: Pipe and gzip are necessary for AIX compatibility.
  # NOTE: "tar cf" is equivalant to "tar -cf".
  # NOTE: For tar, "c" option means create archive.
  # NOTE: For tar, "f" option means read or write files to disk.
  # NOTE: When creating/writing a tarfile with "tar cf", the dashes mean stdout. 
  
  # Copy ${PYTGZ} to "${METDATA}", if applicable
  if [[ -n "${METDATA}" ]] && [[ "${METDATA}" != "${WORKDIR}" ]]; then
    mkdir -p "${METDATA}"
    # NOTE: For mkdir, "-p" or "--parents" option means no error if existing, 
    #   and make parent directories as needed.
    cp ${PYTGZ} "${METDATA}"
  fi
    
  # Prompt on screen that WPS is finished  
  echo '   ******************** Finished WPS run ******************** '
  echo

# If not running Python script, get data from disk
elif [[ ${RAMIN} == 1 ]]; then
# NOTE: I did not check how this works. ?????
  
  # Remove and recreate the temporary ramdisk data folder
  rm -rf "${RAMDATA}"
  mkdir -p "${RAMDATA}" 
  # NOTE: 'mkdir $RAMTMP' is actually done by the Python script.
  
  # Prompt on screen
  echo
  echo '   Copying source data to ramdisk.'
  echo
  
  # Copy alternate data to ramdisk 
  time -p cp "${REALIN}"/*.nc "${RAMDATA}" 

fi 


# =================================================================================
# ======================== Run WRF pre-processor: real.exe ========================
# =================================================================================

# Run real.exe, if applicable
if [[ ${RUNREAL} == 1 ]]
then

  # Prompt on screen
  echo '   ******************** Running real.exe ******************** '
  echo

  # Copy namelist.input and link to real.exe into working directory
  cd "${WORKDIR}"  
  cp ${NOCLOBBER} "${INIDIR}/namelist.input" "${WORKDIR}"
  cp -P "${BINDIR}/real.exe" "${WORKDIR}" 
  
  # Resolve working directory for real.exe
  if [[ ${RAMOUT} == 1 ]]; then
    REALDIR="${RAMDATA}" # Write data to RAM and copy to HD later.
  else
    REALDIR="${REALOUT}" # Write data directly to hard disk.
  fi
  
  # Make sure data destination folder exists
  mkdir -p "${REALOUT}" 
    
  # Copy namelist.input and link to real.exe into actual working directory, if REALDIR 
  #   is different than WORKDIR. Otherwise, backup namelist.input.
  # NOTE: In the latter case, the namelist for real is modified in-place, hence the 
  #   backup is necessary.
  if [[ "${REALDIR}" == "${WORKDIR}" ]]; then
    cp "${WORKDIR}/namelist.input" "${WORKDIR}/namelist.input.backup" # Backup namelist.input.    
  else
    cp -P "${WORKDIR}/real.exe" "${REALDIR}" 
    cp "${WORKDIR}/namelist.input" "${REALDIR}" 
  fi

  # Move into REALDIR
  cd "${REALDIR}" 
  
  # Check namelist.input, and if present, remove 'nocolon' option (not supported by PyWPS) ?????
  if [[ -n "$( grep 'nocolon' namelist.input )" ]]; then
    echo "Namelist option 'nocolon' is not supported by PyWPS - removing option for real.exe." 
    sed -i '/.*nocolon.*/d' namelist.input 
  fi # if nocolon
  # NOTE: 'nocolon' is an encoding that removes the need of colons in python files.
    
  # Change input directory in namelist.input
  sed -i '/.*auxinput1_inname.*/d' namelist.input 
  if [[ ${RAMIN} == 1 ]]; then
    sed -i '/\&time_control/ a\ auxinput1_inname = "'"${RAMDATA}"'/met_em.d<domain>.<date>"' namelist.input
    # NOTE: '\a' in the above, appends text after a line.
  else
    ln -sf "${REALIN}" "${REALTMP}" 
    # NOTE: In the above, "-f" removes existing destination files.
    # NOTE: The above creates a temporary link to metgrid data, in case path is too long for real.exe.
    sed -i '/\&time_control/ a\ auxinput1_inname = "'"${REALTMP}"'/met_em.d<domain>.<date>"' namelist.input
  fi

  # Move into REALDIR (so that output is written here)
  cd "${REALDIR}" 
  
  # Set OpenMP environment
  export OMP_NUM_THREADS=${THREADS} 
  
  # Prompt on screen
  echo "   OMP_NUM_THREADS = ${OMP_NUM_THREADS}."
  echo
  echo "   REAL command: ${HYBRIDRUN} ./real.exe"
  echo
  echo "   Writing output to ${REALDIR}."
  echo
  
  # Wait, if necessary
  if [ -n "${WRFWAIT}" ]; then
    echo "   Waiting ${WRFWAIT} to allow file system to adjust ..."
    echo -e -n "     Current time = "
    date
    sleep "${WRFWAIT}"
    echo
  fi   
  
  # Run and time hybrid (mpi/openmp) job  
  echo "   Launching real.exe executable."
  eval "time -p ${HYBRIDRUN} ./real.exe" &> /dev/null
  wait # Wait for all threads to finish.
  echo
  
  # Check and display REAL exit status
  if [[ -n $(grep 'SUCCESS COMPLETE REAL_EM INIT' rsl.error.0000) ]]; then 
    REALERR=0
    echo '   REAL COMPLETED SUCCESSFULLY!!!   '
  else 
    REALERR=1
    echo '   REAL FAILED! (UNKNOWN ERROR).'              
  fi  
  echo

  # If needed, remove temporary link to metgrid data
  if [[ ${RAMIN} != 1 ]]; then rm "${REALTMP}"; fi 
    
  # Remove existing logs (just in case)
  rm -rf "${WORKDIR}/${REALLOG}"  
  
  # Make folder for log files locally   
  mkdir -p "${REALLOG}" 
  
  # Save log files and meta data
  mv rsl.*.???? namelist.output "${REALLOG}"    
  cp -P namelist.input real.exe "${REALLOG}"
  # NOTE: The above leaves namelist.input and real.exe in place.
  
  # Archive log files with data 
  tar cf - "${REALLOG}" | gzip > ${REALTGZ}
  # NOTE: Pipe and gzip are necessary for AIX compatibility. 
  
  # Move log folder REALLOG to working directory WORKDIR, if REALDIR 
  #   is different than WORKDIR. Otherwise, restore namelist.input 
  #   from namelist.input.backup.
  # NOTE: In the latter case, the namelist for real is modified in-place, hence the 
  #   backup is necessary.      
  if [[ "${REALDIR}" == "${WORKDIR}" ]]; then
    cp "${WORKDIR}/namelist.input.backup" "${WORKDIR}/namelist.input" 
  else
    mv "${REALLOG}" "${WORKDIR}"  
  fi
  
  # Move data to output directory (hard disk), if necessary
  if [[ ! "${REALDIR}" == "${REALOUT}" ]]; then
    echo "   Moving real data to ${REALOUT}."
    echo
    time -p mv wrf* ${REALTGZ} "${REALOUT}"
  fi

  # Prompt on screen
  echo
  echo '   ******************** Finished real.exe ******************** '
  echo

fi 


# =================================================================================
# =============================== Finish / Clean up ===============================
# =================================================================================

# Delete temporary data
rm -rf "${RAMDATA}"

# Revert changes, if RAMIN was changed before
if [[ "${RAMIN_CHANGED}" == 1 ]]
then
  rm -rf "${RAMDISK}"
  RAMIN=0  
  export RAMDISK="/dev/shm/${USER}/"
  RAMDATA="${RAMDISK}/data/"
  RAMTMP="${RAMDISK}/tmp/"
  RAM_CHANGED=0
fi

# Exit code handling
exit $(( PYERR + REALERR ))







