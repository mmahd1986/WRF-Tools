#!/bin/bash

# Driver script to run WRF itself: only runs wrf.exe.
# Created 25/06/2012 by Andre R. Erler, GPL v3.


# Variables defined in driver script:
# $TASKS, $THREADS, $HYBRIDRUN, $INIDIR, $WORKDIR
# For WRF:
# $RUNWRF, $WRFIN, $WRFOUT, $RAD, $LSM


# =================================================================================
# ============================ Prepare the environment ============================
# =================================================================================

# Script and executable locations
SCRIPTDIR=${SCRIPTDIR:-"${INIDIR}"} 
BINDIR=${BINDIR:-"${INIDIR}"} 

# NOCLOBBER option
NOCLOBBER=${NOCLOBBER:-'-n'} 
# NOTE: For 'cp', '-n' option prevents overwriting existing files.

# Related to WRF
RUNWRF=${RUNWRF:-1} # Whether to run WRF.
WRFIN=${WRFIN:-"${WORKDIR}"} # Location of wrfinput_d?? files, etc.
WRFOUT=${WRFOUT:-"${WORKDIR}"} # Final destination of WRF output.
RSTDIR=${RSTDIR:-"${WRFOUT}"} # Final destination of WRF restart files.
TABLES=${TABLES:-"${INIDIR}/tables/"} # Folder for WRF data tables.
WRFLOG="wrf" # Log folder for wrf.exe.
WRFTGZ="${RUNNAME}_${WRFLOG}.tgz" # Archive for log folder.

# Copy execWRF.sh into WORKDIR
cp "${SCRIPTDIR}/execWRF.sh" "${WORKDIR}"
# NOTE: We assume that working directory is already present.


# =================================================================================
# =============================== Run WRF: wrf.exe ================================
# =================================================================================

# Run WRF, if applicable
if [[ ${RUNWRF} == 1 ]]
then

  # Prompt on screen
  echo
  echo '   ******************** Running WRF ******************** '
  echo

  # Declare WRFDIR
  WRFDIR="${WORKDIR}" 
  # NOTE: WRF could potentially be executed in RAM disk as well.
    
  # Make sure data destination folder exists
  mkdir -p "${WRFOUT}" 
  # NOTE: "-p" above means no error if existing, make parent directories as needed.
   
  # Move into ${INIDIR} 
  cd "${INIDIR}" 
    
  # Copy wrf.exe and namelist.input into ${WRFDIR}
  cp -P "${BINDIR}/wrf.exe" "${WRFDIR}"
  # NOTE: "-P" means never follow symbolic links in SOURCE (in "cp [OPTIONS] SOURCE DEST").
  cp ${NOCLOBBER} "${INIDIR}/namelist.input" "${WRFDIR}"
  
  # Move into ${WRFDIR}
  cd "${WRFDIR}"

  # ============== Figure out data tables (for radiation and surface scheme) ================  
  # Radiation scheme: try to infer from namelist using 'sed'
  SEDRAD=$(sed -n '/ra_lw_physics/ s/^[[:space:]]*ra_lw_physics[[:space:]]*=[[:space:]]*\(.\),.*$/\1/p' namelist.input) 
  # NOTE: By default, sed prints out the pattern space at the end of each cycle through 
  #   the script. '-n' option disables this automatic printing, and sed only produces 
  #   output when explicitly told to via the p command.
  # NOTE: [[:space:]] above represents space characters class. Some of these are:
  #   <space>, <newline> and <tab>.
  # NOTE: In sed, \digit matches the digit-th \(...\) parenthesized subexpression in 
  #   the regular expression. This is called a back reference. Subexpressions are 
  #   implicitly numbered by counting occurrences of \( left-to-right.
  # NOTE: In sed, the character . (dot) matches any single character.
  # If retrieval was successful, use it   
  if [[ -n "${SEDRAD}" ]]; then
    RAD="${SEDRAD}" 
    echo "   Determining radiation scheme from namelist: RAD=${RAD}."
  fi
  # NOTE: We prefer namelist value over pre-set default.      
  # Select scheme and print confirmation
  if [[ ${RAD} == 'RRTM' ]] || [[ ${RAD} == 1 ]]; then
    echo "   Using RRTM radiation scheme."
    RADTAB="RRTM_DATA RRTM_DATA_DBL"
  elif [[ ${RAD} == 'CAM' ]] || [[ ${RAD} == 3 ]]; then
    echo "   Using CAM radiation scheme."
    RADTAB="CAM_ABS_DATA CAM_AEROPT_DATA ozone.formatted ozone_lat.formatted ozone_plev.formatted"
  elif [[ ${RAD} == 'RRTMG' ]] || [[ ${RAD} == 4 ]]; then
    echo "   Using RRTMG radiation scheme."
    RADTAB="RRTMG_LW_DATA RRTMG_LW_DATA_DBL RRTMG_SW_DATA RRTMG_SW_DATA_DBL"
    # Check additional radiation options: aer_opt & o3input     
    SEDAER=$(sed -n '/aer_opt/ s/^\ *aer_opt\ *=\ *\(.\).*$/\1/p' namelist.input) 
    if [[ -n $SEDAER ]] && [ $SEDAER -eq 1 ]; then 
      RADTAB="${RADTAB} aerosol.formatted aerosol_plev.formatted aerosol_lat.formatted aerosol_lon.formatted"; fi
      # NOTE: The above can add aerosol climatology of Tegen, if applicable.
    SEDO3=$(sed -n '/o3input/ s/^\ *o3input\ *=\ *\(.\).*$/\1/p' namelist.input) 
    if [[ -z $SEDO3 ]] || [ $SEDO3 -eq 2 ]; then 
      RADTAB="${RADTAB} ozone.formatted ozone_plev.formatted ozone_lat.formatted"; fi
      # NOTE: The above can add ozone climatology from CAM, if applicable.
      # NOTE: The default changed in V3.7 from o3input=0 to o3input=2, which means 
      #   the input files are required by default.
  else
    echo '   WARNING: No radiation scheme selected!'
    # NOTE: This will only happen if no defaults are set and inferring from namelist 
    #   via 'sed' fails.
  fi
  # Add extra display line
  echo
  # Urban surface scheme: try to infer from namelist using 'sed'
  SEDURB=$(sed -n '/sf_urban_physics/ s/^[[:space:]]*sf_urban_physics[[:space:]]*=[[:space:]]*\(.\),.*$/\1/p' namelist.input) 
  # If retrieval was successful, use it
  if [[ -n "${SEDURB}" ]]; then
    URB="${SEDURB}" 
    echo "   Determining urban surface scheme from namelist: URB=${URB}."
  fi
  # NOTE: We prefer namelist value over pre-set default.
  # Select scheme and print confirmation
  if [[ ${URB} == 0 ]]; then
    echo '   No urban surface scheme selected.'
    URBTAB=""
  elif [[ ${URB} == 'single' ]] || [[ ${URB} == 1 ]]; then
    echo "   Using single layer urban surface scheme."
    URBTAB="URBPARM.TBL"
  elif [[ ${URB} == 'multi' ]] || [[ ${URB} == 2 ]]; then
    echo "   Using multi-layer urban surface scheme."
    URBTAB="URBPARM_UZE.TBL"
    # Check PBL: This URB choice works only with PBL choice of 2 or 8
    PBL=$(sed -n '/bl_pbl_physics/ s/^[[:space:]]*bl_pbl_physics[[:space:]]*=[[:space:]]*\(.\),.*$/\1/p' namelist.input) 
    if [[ ${PBL} != 2 ]] && [[ ${PBL} != 8 ]]; then
      echo '   WARNING: sf_urban_physics = 2 requires bl_pbl_physics = 2 or 8!'; fi
  else
    echo '   No urban scheme selected! Default: none.'
  fi
  # Add extra display line
  echo
  # Land-surface scheme: try to infer from namelist using 'sed'
  SEDLSM=$(sed -n '/sf_surface_physics/ s/^[[:space:]]*sf_surface_physics[[:space:]]*=[[:space:]]*\(.\),.*$/\1/p' namelist.input) 
  # If retrieval was successful, use it
  if [[ -n "${SEDLSM}" ]]; then
    LSM="${SEDLSM}" 
    echo "   Determining land-surface scheme from namelist: LSM=${LSM}."
  fi
  # NOTE: We prefer namelist value over pre-set default.
  # Select scheme and print confirmation
  if [[ ${LSM} == 'Diff' ]] || [[ ${LSM} == 1 ]]; then
    echo "   Using diffusive land-surface scheme."
    LSMTAB="LANDUSE.TBL"
  elif [[ ${LSM} == 'Noah' ]] || [[ ${LSM} == 2 ]]; then
    echo "   Using Noah land-surface scheme."
    LSMTAB="SOILPARM.TBL VEGPARM.TBL GENPARM.TBL LANDUSE.TBL"
  elif [[ ${LSM} == 'RUC' ]] || [[ ${LSM} == 3 ]]; then
    echo "   Using RUC land-surface scheme."
    LSMTAB="SOILPARM.TBL VEGPARM.TBL GENPARM.TBL LANDUSE.TBL"
  elif [[ ${LSM} == 'Noah-MP' ]] || [[ ${LSM} == 4 ]]; then
    echo "   Using Noah-MP land-surface scheme."
    LSMTAB="SOILPARM.TBL VEGPARM.TBL GENPARM.TBL LANDUSE.TBL MPTABLE.TBL"
  elif [[ ${LSM} == 'CLM4' ]] || [[ ${LSM} == 5 ]]; then
    echo "   Using CLM4 land-surface scheme."
    LSMTAB="SOILPARM.TBL VEGPARM.TBL GENPARM.TBL LANDUSE.TBL CLM_ALB_ICE_DFS_DATA CLM_ASM_ICE_DFS_DATA CLM_DRDSDT0_DATA CLM_EXT_ICE_DRC_DATA CLM_TAU_DATA CLM_ALB_ICE_DRC_DATA CLM_ASM_ICE_DRC_DATA CLM_EXT_ICE_DFS_DATA CLM_KAPPA_DATA"
  else
    echo '   WARNING: No land-surface model selected!'
    # NOTE: This will only happen if no defaults are set and inferring from namelist 
    #   via 'sed' fails.
  fi
    
  # Copy appropriate tables for physics options
  cd "${TABLES}"
  cp ${NOCLOBBER} ${RADTAB} ${LSMTAB} ${URBTAB} "${WRFDIR}"
    
  # Copy data file and prompt on screen for emission scenario, if applicable
  if [[ -n "${GHG}" ]]; then 
    echo
    if [[ ${RAD} == 'RRTM' ]] || [[ ${RAD} == 1 ]] || [[ ${RAD} == 'CAM' ]]  || [[ ${RAD} == 3 ]] || [[ ${RAD} == 'RRTMG' ]] || [[ ${RAD} == 4 ]]; then
      echo "   GHG emission scenario: ${GHG}."
      cp ${NOCLOBBER} "CAMtr_volume_mixing_ratio.${GHG}" "${WRFDIR}/CAMtr_volume_mixing_ratio"
    else
      echo "   WARNING: Variable GHG emission scenarios not available with the ${RAD} scheme!"
      unset GHG
      # NOTE: $GHG is used later to test if a variable GHG scenario has been used (for logging purposes).
    fi
    echo
  fi

  # Link to input data, if necessary
  cd "${WRFDIR}"
  if [[ "${WRFIN}" != "${WRFDIR}" ]]; then
    echo
    echo "   Linking input data from location:"
    echo "   ${WRFIN}"
    for INPUT in "${WRFIN}"/wrf*_d??; do
      ln -s "${INPUT}"
    done
    echo
  fi
    
  # ============== Run and time hybrid (mpi/openmp) job ================  
  # Set OpenMP environment   
  export OMP_NUM_THREADS=${THREADS} 
  # Prompt on screen  
  echo "   OMP_NUM_THREADS=${OMP_NUM_THREADS}"
  echo "   NODES=${NODES}"
  echo "   TASKS=${TASKS}"
  echo
  echo "   WRF command: ${HYBRIDRUN} ./wrf.exe"
  echo
  # Wait (${WRFWAIT}), if applicable  
  if [ -n "${WRFWAIT}" ]; then
    echo "   Waiting ${WRFWAIT} to allow file system to adjust ..."
    echo -e -n "     Current time = "
    date
    sleep "${WRFWAIT}"
    echo
  fi 
  # Launch wrf.exe
  echo "   Launching WRF executable."
  eval "time -p ${HYBRIDRUN} ./wrf.exe"
  wait # Wait for all threads to finish.
  # Check WRF exit status
  echo
  if [[ -n $(grep 'SUCCESS COMPLETE WRF' 'rsl.error.0000') ]]; then
    WRFERR=0
    echo '   WRF COMPLETED SUCCESSFULLY!!!'
  elif [[ -n $(grep 'NaN' 'rsl.error.'*) ]] || [[ -n $(grep 'NAN' 'rsl.error.'*) ]]; then
    WRFERR=1
    echo '   WRF FAILED: NUMERICAL INSTABILITY.'
  elif [[ -n $(grep 'segmentation fault' 'rsl.error.'*) ]]; then
    WRFERR=1
    echo '   WRF FAILED: SEGMENTATION FAULT.'
  else 
    WRFERR=10
    echo '   WRF FAILED (UNKNOWN ERROR).'
  fi
  echo

  # ==================== Clean-up and move output to destination ====================
  # Remove old logs
  rm -rf "${WORKDIR}/${WRFLOG}" 
  # Make folder for log files locally
  mkdir -p "${WRFLOG}" 
  # NOTE: For mkdir "-p" means no error if existing, make parent directories 
  #   as needed.
  # Save log files and meta data
  mv rsl.*.???? namelist.output "${WRFLOG}" 
  # NOTE: We do not add tables (${RADTAB} ${LSMTAB}, etc) to logs. 
  cp -P namelist.input wrf.exe "${WRFLOG}" 
  # NOTE: For cp, "-P" means never follow symbolic links in source.
  # NOTE: This leaves namelist.input in place.
  # Also add emission scenario to log, if applicable  
  if [[ -n "${GHG}" ]]; then 
    mv 'CAMtr_volume_mixing_ratio' "${WRFLOG}/CAMtr_volume_mixing_ratio.${GHG}"
  fi
  # Display info about tar
  echo -n "   Using tar executable at: "  
  which tar
  # Archive logs with data   
  tar cf - "${WRFLOG}" | gzip > ${WRFTGZ} 
  # NOTE: Pipe and gzip are necessary for AIX compatibility.
  # NOTE: "tar cf" is equivalant to "tar -cf".
  # NOTE: For tar, "c" option means create archive.
  # NOTE: For tar, "f" option means read or write files to disk.
  # NOTE: When creating/writing a tarfile with "tar cf", the dashes mean stdout.   
  # Move log folder to working directory, if applicable  
  if [[ ! "${WRFDIR}" == "${WORKDIR}" ]]; then
    mv "${WRFLOG}" "${WORKDIR}" 
  fi
  # Copy/move data to output directory (hard disk), if necessary
  if [[ ! "${WRFDIR}" == "${WRFOUT}" ]]; then
    # Move restart files
    for RESTART in "${WORKDIR}"/wrfrst_d??_????-??-??_??[_:]??[_:]??; do 
    # NOTE: [_:] means underscore or colon.
      if [[ ! -h "${RESTART}" ]]; then
      # NOTE: "[ -h FILE ]" is true if FILE exists and is a symbolic link.
        mv "${RESTART}" "${RSTDIR}" 
        # NOTE: ${RSTDIR} defaults to ${WRFOUT}.
      fi 
    done
    # NOTE: This moves new restart files as well.    
    # Move data and log files to ${WRFOUT}
    echo
    echo "   Moving data (*.nc) and log-files (*.tgz) to ${WRFOUT}"
    mv wrfconst_d??.nc "${WRFOUT}" &>/dev/null # This one doesn't have a date string.
    # NOTE: I added the "&>/dev/null" because for defaultIO, there are no constant files and that could
    #   give unwanted errors.
    mv wrf*_d??_????-??-??_??[_:]??[_:]??.nc "${WRFOUT}" # Otherwise identify output files by date string.
    # NOTE: Andre says he doesn't know how to avoid the error message cause by the restart-symlinks. ?????
    mv "${WORKDIR}"/*.tgz "${WRFOUT}"
  fi

  # Finish
  echo
  echo '   ******************** Finished wrf.exe ******************** '
  echo

fi 


# Handle exit code
exit ${WRFERR}








