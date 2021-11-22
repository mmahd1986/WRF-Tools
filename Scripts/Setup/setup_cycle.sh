#!/bin/bash

# Short script to setup a new experiment and/or re-link restart files.
# Andre R. Erler, 02/03/2013, GPL v3.


# Output verbosity
VERBOSITY=${VERBOSITY:-1} 

# ========================== Figure out the run type ==========================
# NOGEO mode
if [[ "${MODE}" == 'NOGEO'* ]]; then  
  NOGEO='NOGEO' # Run without geogrid.
  NOTAR='FALSE' # Star static.
  RESTART='FALSE' # Cold start.
# NOSTAT mode
elif [[ "${MODE}" == 'NOSTAT'* ]]; then  
  NOGEO='NOGEO' # Run without geogrid.
  NOTAR='NOTAR' # No static.
  RESTART='FALSE' # Cold start.
# RESTART mode
elif [[ "${MODE}" == 'RESTART' ]]; then 
  # Check if geogrid file for first domain is present (checking all is too 
  #   complicated)
  if [ -f "${INIDIR}/geo_em.d01.nc" ]; then NOGEO='NOGEO' # Run without geogrid.
  # NOTE: The -f flag verifies two things: The provided path exists and it is 
  #   a regular file.
  else NOGEO='FALSE'; fi # Run with geogrid. 
  NOTAR='FALSE' # Star static. 
  RESTART='RESTART' # Restart previously terminated run.   
# CLEAN mode
elif [[ "${MODE}" == 'CLEAN' ]] || [[ "${MODE}" == '' ]]; then  
  NOGEO='FALSE' # Run with geogrid.
  NOTAR='FALSE' # Star static.
  RESTART='FALSE' # Cold start.
# Otherwise, it's not clear what we're doing
else
  echo
  echo "   Unknown command ${MODE} - aborting!!!   "
  echo
  exit 1
fi

# Prompt on screen
if [ $VERBOSITY -gt 0 ]; then
  if [[ "${RESTART}" == 'RESTART' ]]
  then
    echo "   ================================= Re-starting Cycle ================================= "
    echo
    echo "   Next Step: ${NEXTSTEP}."
  else
    echo "   ================================== Starting Cycle =================================== "
    echo
    echo "   First Step: ${NEXTSTEP}."
  fi
  echo
  echo "   Root Dir: ${INIDIR}."
  echo
fi 

# Move into ${INIDIR}
cd "${INIDIR}"

# Run geogrid, if applicable
if [[ "${NOGEO}" == 'NOGEO' ]]
then
  [ $VERBOSITY -gt 0 ] && echo "   Not running geogrid.exe."
else   
  rm -f geo_em.d??.nc geogrid.log* # Clear files.  
  [ $VERBOSITY -gt 0 ] && echo "   Running geogrid.exe (suppressing output)."
  if [ $VERBOSITY -gt 1 ]
  then eval "${RUNGEO}" # Run with parallel processes & display output.  
  else eval "${RUNGEO}" > /dev/null # Run with parallel processes & do not display output.
  # NOTE: ${RUNGEO} command is specified in caller instance.
  fi 
fi

# If this is a restart run
if [[ "${RESTART}" == 'RESTART' ]]; then 

  # Read date string for restart file
  RSTDATE=$(sed -n "/${NEXTSTEP}/ s/${NEXTSTEP}[[:space:]]\+'\([-_\:0-9]\{19\}\)'[[:space:]]\+'[-_\:0-9]\{19\}'$/\1/p" stepfile)
  # NOTE: \+ is as *, but matches one or more.
  # NOTE: [-_\:0-9] means any of - or _ or : or 0-9.
  # NOTE: \{19\} means the previous charachter, etc, but 19 times.
  
  # Make and move into NEXTDIR
  NEXTDIR="${INIDIR}/${NEXTSTEP}" 
  cd "${NEXTDIR}"
  
  # Prompt on screen
  [ $VERBOSITY -gt 0 ] && echo "   Linking restart files to next working directory:"
  [ $VERBOSITY -gt 0 ] && echo "     ${NEXTDIR}"
  
  # Link restart files
  for RST in "${WRFOUT}"/wrfrst_d??_${RSTDATE//:/[_:]}; do 
  # NOTE: ${parameter/pattern/string} replaces the first occurrence of a pattern 
  #   with a given string. To replace all occurrences, we use ${parameter//pattern/string}. 
  # NOTE: The above matches both hh:mm:ss and hh_mm_ss.
    ln -sf "${RST}" 
    [ $VERBOSITY -gt 0 ] && echo  "${RST}"
  done

# If not restarting
else 

  # Move into ${INIDIR}
  cd "${INIDIR}"
  
  # Clear some folders
  [ $VERBOSITY -gt 0 ] && [[ "${MODE}" == 'CLEAN' ]] && echo "   Clearing Output Folders:"
  if [[ -n ${METDATA} ]]; then
    if [[ "${MODE}" == 'CLEAN' ]]; then 
      [ $VERBOSITY -gt 0 ] && echo "${METDATA}"
      rm -rf "${METDATA}" 
    fi
    mkdir -p "${METDATA}" 
    # NOTE: "-p" means no error if existing, make parent directories as needed.
    # NOTE: This mkdir will fail, if path depends on job step, but can be ignored.
  fi
  if [[ -n ${WRFOUT} ]]; then
    if [[ "${MODE}" == 'CLEAN' ]]; then 
      [ $VERBOSITY -gt 0 ] && echo "${WRFOUT}"
      rm -rf "${WRFOUT}" 
    fi
    mkdir -p "${WRFOUT}"
  fi
  
  # Remove all existing step folders (however for next step, we need to preserve namelists)
  if [[ "${MODE}" == 'CLEAN' ]] && [ -f stepfile ]; then
  # NOTE: The -f verifies two things: The provided path exists and is a regular file.    
    for STEP in $( awk '{print $1}' stepfile ); do
      if [[ "${STEP}" == "${NEXTSTEP}" ]]; then         
        mv "${NEXTSTEP}/namelist.input" 'zzz.input'; mv "${NEXTSTEP}/namelist.wps" 'zzz.wps'
        [ $VERBOSITY -gt 0 ] && echo "${STEP}"
        rm -r "${STEP}"; mkdir "${STEP}"
        mv 'zzz.input' "${NEXTSTEP}/namelist.input"; mv 'zzz.wps' "${NEXTSTEP}/namelist.wps"
      elif [ -e "${STEP}/" ]; then
      # NOTE: [ -e FILE ] returns true if FILE exists.
        [ $VERBOSITY -gt 0 ] && echo "${STEP}"
        rm -r "${STEP}"
      fi    
    done 
  fi
  
  # Add an extra display line, if applicable
  [ $VERBOSITY -gt 0 ] && echo

  # ========================= Prepare first working directory =========================
  # Set restart to False for first step
  sed -i '/restart\ / s/restart\ *=\ *\.true\..*$/restart = .false.,/' "${NEXTSTEP}/namelist.input"
  # Make sure the rest of the cases are on restart
  sed -i '/restart\ / s/restart\ *=\ *\.false\..*$/restart = .true.,/' "namelist.input"
  [ $VERBOSITY -gt 0 ] && echo "   Set restart option in namelist."

  # Create backup of static files, if applicable
  if [[ "${NOTAR}" != 'NOTAR' ]]; then
    cd "${INIDIR}"
    rm -rf 'static/'
    mkdir -p 'static'
    echo $( cp -P * 'static/' &> /dev/null ) # Can we remove echo from here? ?????
    # NOTE: The above does not display output messages or errors.
    # NOTE: "-P" means never follow symbolic links in the source.
    cp -rL 'scripts/' 'bin/' 'meta/' 'tables/' 'static/'
    # NOTE: "-L" means always follow symbolic links in the source.
    tar cf - 'static/' | gzip > "${STATICTGZ}"
    # NOTE: Pipe and gzip are necessary for AIX compatibility.
    # NOTE: "tar cf" is equivalant to "tar -cf".
    # NOTE: For tar, "c" option means create archive.
    # NOTE: For tar, "f" option means read or write files to disk.
    # NOTE: When creating/writing a tarfile with "tar cf", the dashes mean stdout.
    rm -r 'static/'
    mv "${STATICTGZ}" "${WRFOUT}"
    if [ $VERBOSITY -gt 0 ]; then
      echo "   Saved backup file for static data: ${WRFOUT}/${STATICTGZ}."
      echo
    fi 
  fi 

fi 










