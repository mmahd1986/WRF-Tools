#!/bin/bash

# Script to set up a WPS/WRF run folder on SciNet.
# Created 28/06/2012 by Andre R. Erler, GPL v3.
# Last revision 11/06/2013 by Andre R. Erler.


# Environment variables: $CODE_ROOT, $WPSSRC, $WRFSRC, $SCRATCH


# Abort if anything goes wrong
set -e 


# =================================================================================
# ============ Function to change common variables in run-scripts. ================
# =================================================================================

function RENAME () {

    # Input variables
    local FILE="$1" # File name.
    # NOTE: A variable declared as local is one that is visible only within the 
    #   block of code in which it appears. It has local scope. In a function, a 
    #   local variable has meaning only within that function block.
    
    # Infer queue system
    local Q="${FILE##*.}" 
    # NOTE: "${string##substring}" deletes longest match of substring from 
    #   front of $string.
    
    # Prompt on screen
    echo
    echo "RENAME function: Making changes in the file: ${FILE}."
    
    # ==================== Queue dependent changes ======================
    # WPS run-script
    if [[ "${FILE}" == *WPS* ]] && [[ "${WPSQ}" == "${Q}" ]]; then
      if [[ "${WPSQ}" == "pbs" ]]; then
        sed -i "/#PBS -N/ s/#PBS -N\ .*$/#PBS -N ${NAME}_WPS/" "${FILE}" # Name ($NAME is set within xconfig.sh).
        sed -i "/#PBS -l/ s/#PBS -l nodes=.*:\(.*\)$/#PBS -l nodes=${WPSNODES}:\1/" "${FILE}" # Number of nodes.
        sed -i "/#PBS -l/ s/#PBS -l procs=.*$/#PBS -l procs=${WPSNODES}/" "${FILE}" # Processes (alternative to nodes).
        sed -i "/#PBS -l/ s/#PBS -l walltime=.*$/#PBS -l walltime=${WPSWCT}/" "${FILE}" # Wallclock time.      
      elif [[ "${WPSQ}" == "sb" ]]; then
        sed -i "/#SBATCH -J/ s/#SBATCH -J\ .*$/#SBATCH -J ${NAME}_WPS/" "${FILE}" # Name ($NAME is set within xconfig.sh).
        sed -i "/#SBATCH --output/ s/#SBATCH --output=.*$/#SBATCH --output=${NAME}_WPS.%j.out/" "${FILE}" # Output file name.
        sed -i "/#SBATCH --nodes/ s/#SBATCH --nodes=.*$/#SBATCH --nodes=${WPSNODES}/" "${FILE}" # Number of nodes.
        sed -i "/#SBATCH --time/ s/#SBATCH --time=.*$/#SBATCH --time=${WPSWCT}/" "${FILE}" # Wallclock time.      
      else 
        sed -i "/export JOBNAME/ s+export\ JOBNAME=.*$+export JOBNAME=${NAME}_WPS  # Job name (dummy variable, since there is no queue)\.+" "${FILE}" # Name.
      fi 
    # WRF run-script
    elif [[ "${FILE}" == *WRF* ]] && [[ "${WRFQ}" == "${Q}" ]]; then
      if [[ "${WRFQ}" == "pbs" ]]; then
        sed -i "/#PBS -N/ s/#PBS -N\ .*$/#PBS -N ${NAME}_WRF/" "${FILE}" # Name.
        sed -i "/#PBS -l/ s/#PBS -l nodes=.*:\(.*\)$/#PBS -l nodes=${WRFNODES}:\1/" "${FILE}" # Number of nodes.
        sed -i "/#PBS -l/ s/#PBS -l procs=.*$/#PBS -l procs=${WRFNODES}/" "${FILE}" # Processes (alternative to nodes).
        sed -i "/#PBS -l/ s/#PBS -l walltime=.*$/#PBS -l walltime=${MAXWCT}/" "${FILE}" # Wallclock time.
        sed -i "/qsub/ s/qsub ${WRFSCRIPT} -v NEXTSTEP=*\ -W*$/qsub ${WRFSCRIPT} -v NEXTSTEP=*\ -W\ ${NAME}_WPS/" "${FILE}" # Dependency. ?????
      elif [[ "${WRFQ}" == "sb" ]]; then
        sed -i "/#SBATCH -J/ s/#SBATCH -J\ .*$/#SBATCH -J ${NAME}_WRF/" "${FILE}" # Name.
        sed -i "/#SBATCH --output/ s/#SBATCH --output=.*$/#SBATCH --output=${NAME}_WRF.%j.out/" "${FILE}" # Output file name.
        sed -i "/#SBATCH --nodes/ s/#SBATCH --nodes=.*$/#SBATCH --nodes=${WRFNODES}/" "${FILE}" # Number of nodes.
        sed -i "/#SBATCH --time/ s/#SBATCH --time=.*$/#SBATCH --time=${MAXWCT}/" "${FILE}" # Wallclock time.      
        sed -i "/#SBATCH --dependency/ s/#SBATCH --dependency=.*$/#SBATCH --dependency=afterok:${NAME}_WPS/" "${FILE}" # Dependency on WPS.
      elif [[ "${WRFQ}" == "sge" ]]; then
        sed -i "/#\$ -N/ s/#\$ -N\ .*$/#\$ -N ${NAME}_WRF/" "${FILE}" # Name. ?????
        sed -i "/#\$ -pe/ s/#\$ -pe .*$/#\$ -pe mpich $((WRFNODES*32))/" "${FILE}" # Number of MPI tasks. ?????
        sed -i "/#\$ -l/ s/#\$ -l h_rt=.*$/#\$ -l h_rt=${MAXWCT}/" "${FILE}" # Wallclock time. ?????
      elif [[ "${WRFQ}" == "ll" ]]; then
        sed -i "/#\ *@\ *job_name/ s/#\ *@\ *job_name\ *=.*$/# @ job_name = ${NAME}_WRF/" "${FILE}" # Name. ?????
        sed -i "/#\ *@\ *node/ s/#\ *@\ *node\ *=.*$/# @ node = ${WRFNODES}/" "${FILE}" # Number of nodes. ?????
        sed -i "/#\ *@\ *wall_clock_limit/ s/#\ *@\ *wall_clock_limit\ *=.*$/# @ wall_clock_limit = ${MAXWCT}/" "${FILE}" # Wallclock time. ?????
      else
        sed -i "/export JOBNAME/ s+export\ JOBNAME=.*$+export JOBNAME=${NAME}_WRF # job name (dummy variable, since there is no queue)+" "${FILE}" # Name. ?????
        sed -i "/export TASKS/ s+export\ TASKS=.*$+export TASKS=${WRFNODES} # number of MPI tasks+" "${FILE}" # Number of tasks (instead of nodes ...). ?????
      fi 
    # Archive-script
    elif [[ "${FILE}" == "${ARSCRIPT}" ]]; then
      if [[ "${WPSQ}" == "pbs" ]]; then
        sed -i "/#PBS -N/ s/#PBS -N\ .*$/#PBS -N ${NAME}_ar/" "${FILE}" # Name.
      elif [[ "${WPSQ}" == "sb" ]]; then
        sed -i "/#SBATCH -J/ s/#SBATCH -J\ .*$/#SBATCH -J ${NAME}_ar/" "${FILE}" # Name.
        sed -i "/#SBATCH --output/ s/#SBATCH --output=.*$/#SBATCH --output=${NAME}_ar.%j.out/" "${FILE}" # Output file name. 
      else
        sed -i "/export JOBNAME/ s+export\ JOBNAME=.*$+export JOBNAME=${NAME}_ar # Job name (dummy variable, since there is no queue).+" "${FILE}" # Name.                    
      fi 
    # Averaging-script
    elif [[ "${FILE}" == "${AVGSCRIPT}" ]]; then
      if [[ "${WPSQ}" == "pbs" ]]; then
        sed -i "/#PBS -N/ s/#PBS -N\ .*$/#PBS -N ${NAME}_avg/" "${FILE}" # Name.
      elif [[ "${WPSQ}" == "sb" ]]; then
        sed -i "/#SBATCH -J/ s/#SBATCH -J\ .*$/#SBATCH -J ${NAME}_avg/" "${FILE}" # Name.
        sed -i "/#SBATCH --output/ s/#SBATCH --output=.*$/#SBATCH --output=${NAME}_avg.%j.out/" "${FILE}" # Output file name.
      else
        sed -i "/export JOBNAME/ s+export\ JOBNAME=.*$+export JOBNAME=${NAME}_avg # Job name (dummy variable, since there is no queue).+" "${FILE}" # Name.                    
      fi 
    fi          
    # Set email address for notifications (why use Q, then WPSQ, then WRFQ, then Q again? ?????)
    # NOTE: $EMAIL is set within xconfig.sh.
    if [[ -n "$EMAIL" ]]; then 
      if [[ "${Q}" == "pbs" ]]; then
        sed -i "/#PBS -M/ s/#PBS -M\ .*$/#PBS -M \"${EMAIL}\"/" "${FILE}" 
      elif [[ "${WPSQ}" == "sb" ]]; then
        sed -i "/#SBATCH --mail-user/ s/#SBATCH --mail-user=.*$/#SBATCH --mail-user=${EMAIL}/" "${FILE}"
      elif [[ "${WRFQ}" == "sge" ]]; then
        sed -i "/#\$ -M/ s/#\$ -M\ .*$/#\$ -M ${EMAIL}/" "${FILE}"
      elif [[ "${Q}" == "ll" ]]; then
        : 
        # NOTE: In the above, the ":" is just a "do-nothing" place holder.
        # NOTE: Apparently email address is not set here. Is this true? ?????
      else
        sed -i "/\\\$EMAIL/ s/\\\$EMAIL/${EMAIL}/" "${FILE}" 
        # NOTE:  "\\" in the above is to print a single backslash.
        # NOTE: "\$" in the above skips $ (meaning it actually is a $).
        # NOTE: This is for other cases, where the literal string \$Email 
        #   is replace by the variable EMAIL.
      fi
    else
      sed -i '/\$EMAIL/d' "${FILE}" # Remove email address from the script.
    fi 
       
    # ==================== Queue independent changes ====================== 
    # NOTE: Variables that depend on other variables are not overwritten.
    # Change WRF script to the appropriate one
    sed -i "/WRFSCRIPT=/ s/WRFSCRIPT=[^$][^$].*$/WRFSCRIPT=\'run_${CASETYPE}_WRF.${WRFQ}\'/" "${FILE}" 
    # NOTE: A bracket expression is a list of characters enclosed by ‘[’ and ‘]’. It matches 
    #   any single character in that list; if the first character of the list is the caret ‘^’, 
    #   then it matches any character not in the list.
    # NOTE: In the above '[^$][^$]' means at least two charachters that are not dollar signs.
    #   As after the '=' we can get a quotation mark, this does make sense, as we do not want
    #   to replace dependencies on other variables (also WRFSCRIPT is usually more than two charachters). 
    # Change WPS script to the appropriate one
    sed -i "/WPSSCRIPT=/ s/WPSSCRIPT=[^$][^$].*$/WPSSCRIPT=\'run_${CASETYPE}_WPS.${WPSQ}\'/" "${FILE}"  
    # Change output folder to the appropriate one
    sed -i '/WRFOUT=/ s+WRFOUT=[^$][^$].*$+WRFOUT="${INIDIR}/wrfout/" # WRF output folder\.+' "${FILE}"         
    # Change metdata folder (optional WPS/metgrid output folder) to the appropriate one 
    [[ -n $METDATA ]] && sed -i "/METDATA=/ s+METDATA=[^$][^$].*$+METDATA=\'${METDATA}\' # Optional WPS/metgrid output folder\.+" "${FILE}"
    # Change WRF version (optional WRF version parameter (default: 3)) to the appropriate one
    [[ -n $WRFVERSION ]] && sed -i "/WRFVERSION=/ s/WRFVERSION=[^$].*$/WRFVERSION=${WRFVERSION} # Optional WRF version parameter (default: 3)\. /" "${FILE}"  
    # Change WRF wallclock time limit to the appropriate one
    sed -i "/WRFWCT=/ s/WRFWCT=[^$][^$].*$/WRFWCT=\'${WRFWCT}\' # WRF wallclock time\./" "${FILE}"     
    # Change WPS wallclock time limit to the appropriate one
    sed -i "/WPSWCT=/ s/WPSWCT=[^$][^$].*$/WPSWCT=\'${WPSWCT}\' # WPS wallclock time\./" "${FILE}"
    # Change number of WPS & WRF nodes on given system to the appropriate ones
    sed -i "/WPSNODES=/ s/WPSNODES=[^$][^$].*$/WPSNODES=${WPSNODES} # Number of WPS nodes\./" "${FILE}" 
    sed -i "/WRFNODES=/ s/WRFNODES=[^$][^$].*$/WRFNODES=${WRFNODES} # Number of WRF nodes\./" "${FILE}"   
    # Change script folder to the appropriate one
    sed -i '/SCRIPTDIR=/ s+SCRIPTDIR=[^$][^$].*$+SCRIPTDIR="${INIDIR}/scripts/"  # Location of component scripts (pre/post processing etc\.)\.+' "${FILE}"
    # Change executable folder to the appropriate one
    sed -i '/BINDIR=/ s+BINDIR=[^$][^$].*$+BINDIR="${INIDIR}/bin/"  # Location of executables (WRF and WPS)\.+' "${FILE}"    
    # Change archive script to the appropriate one
    sed -i "/ARSCRIPT=/ s/ARSCRIPT=[^$][^$].*$/ARSCRIPT=\'${ARSCRIPT}\' # Archive script to be executed in specified intervals\./" "${FILE}"
    # Change archive interval to the appropriate one
    sed -i "/ARINTERVAL=/ s/ARINTERVAL=[^$][^$].*$/ARINTERVAL=\'${ARINTERVAL}\' # Interval in which the archive script is to be executed (default: every time)\./" "${FILE}"
    # Change averaging script to the appropriate one
    sed -i "/AVGSCRIPT=/ s/AVGSCRIPT=[^$][^$].*$/AVGSCRIPT=\'${AVGSCRIPT}\' # Averaging script to be executed in specified intervals\./" "${FILE}"
    # Change averaging interval to the appropriate one
    sed -i "/AVGINTERVAL=/ s/AVGINTERVAL=[^$][^$].*$/AVGINTERVAL=\'${AVGINTERVAL}\' # Interval in which the averaging script is to be executed (default: every time)\./" "${FILE}"                
    # Change DOMAINS to the appropriate one    
    sed -i "/DOMAINS=/ s/'1234'/'${DOMS}'/" "${FILE}" 
    # NOTE: DOMS is '123...X', where X is ${MAXDOM} (set in xconfig.sh).    
    # Change type of initial and boundary focing data (mainly for WPS) to the appropriate one
    sed -i "/DATATYPE=/ s/DATATYPE=[^$][^$].*$/DATATYPE=\'${DATATYPE}\' # Type of initial and boundary focing  data\./" "${FILE}"
    # Change whether or not to restart job after a numerical instability (used by crashHandler.sh) to the appropriate one
    sed -i "/AUTORST=/ s/AUTORST=[^$][^$].*$/AUTORST=\'${AUTORST}\' # Whether or not to restart job after a numerical instability\./" "${FILE}"
    # Change time decrement to use in case of instability (used by crashHandler.sh) to the appropriate one
    sed -i "/DELT=/ s/DELT=[^$][^$].*$/DELT=\'${DELT}\' # Time decrement for auto restart\./" "${FILE}"
        
    # ==================== Geogrid number of tasks ======================
    sed -i "/export GEOTASKS=/ s/export GEOTASKS=.*$/export GEOTASKS=${GEOTASKS} # Number of geogrid processes\./" "${FILE}"
    
    # ==================== WRF Env ======================
    sed -i "/export WRFENV=/ s/export WRFENV=.*$/export WRFENV=\'${WRFENV}\' # WRF environment version\./" "${FILE}"

} 


# =================================================================================
# ========================== Scenario definition section ==========================
# =================================================================================

# NOTE: Below are default values (these may be set or overwritten in xconfig.sh).

# Experiment name
NAME='test' 
# NOTE: This should be overwritten in xconfig.sh.

# Run and WRFOUT directories 
RUNDIR="${PWD}" # Experiment root.
WRFOUT="${RUNDIR}/wrfout/" # Folder to collect output data.
METDATA='' # Folder to collect output data from metgrid.

# GHG emission scenario 
GHG='RCP8.5' 
# NOTE: This identifies the CAMtr_volume_mixing_ratio.* file to be used.

# Time period and cycling interval
CYCLING="1979:2009:1M" # Stepfile to be used (leave empty if not cycling).
AUTORST='RESTART' # Whether or not to restart job after a numerical instability (used by crashHandler.sh).
DELT='DEFAULT' # Time decrement for auto restart (DEFAULT: select according to timestep).

# Boundary data
DATADIR='' # Root directory for data.
DATATYPE='CESM' # Boundary forcing type.

# CMIP6 model
CMIP6MODEL='MPI-ESM1-2-HR'
CMIP6MDLVER='HIST'

# WRFROOT and WRFTOOLS
WRFROOT="${CODE_ROOT}/WRFV3.9/"
WRFTOOLS="${CODE_ROOT}/WRF-Tools/"

# I/O, archiving and averaging 
IO='fineIO' # This is used for namelist construction and archiving.
ARSYS='' # Archive system. Define in xconfig.sh. 
ARSCRIPT='arconfig_wrfout_fineIO_2' # This is a dummy name, as it can get replaced later.
ARINTERVAL='YEARLY' # Default value.
AVGSYS='' # Averaging system. Define in xconfig.sh.
AVGSCRIPT='DEFAULT' # This is a dummy name, as if it's DEFAULT, it gets replaced later.
AVGINTERVAL='YEARLY' # Default value.
# NOTE: Archiving/averaging interval options are YEARLY, MONTHLY & DAILY, with YEARLY 
#   being preferred. Unknown/empty intervals trigger archiving/averaging after every 
#   step.

# WPS system
WPSSYS='' # WPS system. Define in xconfig.sh.

# Other WPS configuration files
GEODATA="/project/p/peltier/WRF/geog/" # Location of geogrid data.

# WRF system
WRFSYS='' # WRF system. Define in xconfig.sh.

# Maximum Wall clock time
MAXWCT='' 
# NOTE: This is dependent on cluster, to some extent.

# PolarWRF switch
POLARWRF=0  

# FLake lake model (in-house; only V3.4 & V3.5)
FLAKE=0  

# Number of domains in WRF and WPS
MAXDOM=2 
# NOTE: Some settings depend on the number of domains.


# ===============================================================
# ======================== Clear screen =========================
# ===============================================================

clear
echo
echo "============================================================================================================"
echo " Preliminary steps for the setup. "
echo "============================================================================================================"


# ===============================================================
# =================== Load configuration file ===================
# ===============================================================

echo
echo "Sourcing experimental setup file (xconfig.sh)." 
source xconfig.sh


# ===============================================================
# ==================== Other configurations =====================
# ===============================================================

# Apply command line argument for WRFSYS (overrides xconfig)
[[ -n $1 ]] && WRFSYS="$1"
# NOTE: See notes for the meaning of double brackets.
# NOTE: [[ -n STRING ]] means "not empty string" ("-z" means "empty string").
# NOTE: The && above works like an if condition. It only does the after, if  
#   the before condition is met.
# Note: In the above $1 is a possible argument when calling this script. 

# Set default wallclock limit depending on machine
if [[ -z "${MAXWCT}" ]]; then
  if [[ "${WRFSYS}" == 'Niagara' ]]; then
    MAXWCT='24:00:00' # Niagara has reduced wallclock limit time.
  elif [[ "${WRFSYS}" == 'P7' ]]; then
    MAXWCT='72:00:00' # P7 has increased wallclock limit time.
  else
    MAXWCT='48:00:00' # This is common on most clusters.
  fi # WRFSYS
fi 

# Create run and wrfout folders
echo
echo "Setting up Experiment ${NAME}."
echo
mkdir -p "${RUNDIR}"
mkdir -p "${WRFOUT}"
# NOTE: "-p" means no error if existing, and make parent directories 
#   as needed.


# ===============================================================
# ==================== Fix default settings =====================
# ===============================================================

# WPS defaults 
SHARE=${SHARE:-'arw'} # Share section of WPS namelist.
METGRID=${METGRID:-'pywps'} # Metgrid section of WPS namelist.
# NOTE: "${parameter:-word}" means that if parameter is unset or null, 
#   the expansion of word is substituted. Otherwise, the value of  
#   parameter is substituted.

# Infer default $CASETYPE (can also set $CASETYPE in xconfig.sh) 
if [[ -z "${CASETYPE}" ]]; then
  if [[ -n "${CYCLING}" ]]; then CASETYPE='cycling';
  else CASETYPE='test'; fi
fi

# Boundary data definition for WPS
if [[ "${DATATYPE}" == 'CMIP5' ]]; then
  POPMAP=${POPMAP:-'map_gx1v6_to_fv0.9x1.25_aave_da_090309.nc'} 
  METGRIDTBL=${METGRIDTBL:-'METGRID.TBL.CESM'}
elif [[ "${DATATYPE}" == 'CMIP6' ]]; then
  VTABLE=${VTABLE:-'Vtable.CMIP6.'${CMIP6MODEL}'_'${CMIP6MDLVER}'.csv'}
  METGRIDTBL=${METGRIDTBL:-'METGRID.TBL.CMIP6'}
elif [[ "${DATATYPE}" == 'CESM' ]]; then
  POPMAP=${POPMAP:-'map_gx1v6_to_fv0.9x1.25_aave_da_090309.nc'}
  METGRIDTBL=${METGRIDTBL:-'METGRID.TBL.CESM'}
elif [[ "${DATATYPE}" == 'CFSR' ]]; then
  VTABLE_PLEV=${VTABLE_PLEV:-'Vtable.CFSR_press_pgbh06'}
  VTABLE_SRFC=${VTABLE_SRFC:-'Vtable.CFSR_sfc_flxf06'}
  METGRIDTBL=${METGRIDTBL:-'METGRID.TBL.ARW'}
elif [[ "${DATATYPE}" == 'ERA-I' ]]; then
  VTABLE=${VTABLE:-'Vtable.ERA-interim.pl'}
  METGRIDTBL=${METGRIDTBL:-'METGRID.TBL.ERAI'}
elif [[ "${DATATYPE}" == 'ERA5' ]]; then
  VTABLE=${VTABLE:-'Vtable.ERA5.pl'}
  METGRIDTBL=${METGRIDTBL:-'METGRID.TBL.ERA5'}
elif [[ "${DATATYPE}" == 'NARR' ]]; then
  VTABLE=${VTABLE:-'Vtable.NARR'}
  METGRIDTBL=${METGRIDTBL:-'METGRID.TBL.ARW'}
else # WPS default
  METGRIDTBL=${METGRIDTBL:-'METGRID.TBL.ARW'}
fi 
# NOTE: POPMAP is for ocean grid definition. ?????

# Geogrid table file
if [[ ${FLAKE} == 1 ]]; then
  GEOGRIDTBL=${GEOGRIDTBL:-'GEOGRID.TBL.FLAKE'}
else
  GEOGRIDTBL=${GEOGRIDTBL:-'GEOGRID.TBL.ARW'}
fi 

# Figure out WRF and WPS build 
if [[ -z "$WRFBLD" ]]; then
  # GCM or reanalysis with current I/O version
  if [[ "${DATATYPE}" == 'CESM' ]] || [[ "${DATATYPE}" == 'CCSM' ]] || [[ "${DATATYPE}" == 'CMIP5' ]]; then
    WRFBLD="Clim-${IO}" # Variable GHG scenarios and no leap-years. ?????
    LLEAP='--noleap' # Option for Python script to omit leap days. 
  elif [[ "${DATATYPE}" == 'ERA-I' ]] || [[ "${DATATYPE}" == 'ERA5' ]] || [[ "${DATATYPE}" == 'CMIP6' ]] || [[ "${DATATYPE}" == 'CFSR' ]] || [[ "${DATATYPE}" == 'NARR' ]]; then
    WRFBLD="ReA-${IO}" # Variable GHG scenarios with leap-years. ?????
  else
    WRFBLD="Default-${IO}" # Standard WRF build with current I/O version. ?????
  fi 
  # Standard or PolarWRF (add Polar-prefix) ?????
  if [ ${POLARWRF} == 1 ]; then WRFBLD="Polar-${WRFBLD}"; fi
fi 
WPSBLD=${WPSBLD:-"${WRFBLD}"} # Should be analogous.
# NOTE: We can omit leap days only for GCMs and not reanalyses. Reanalyses usually
#   have to have the leap days. GCMs usually do not have leap days.
#   What about standard cases? ????? 

# Source folders (depending on $WRFROOT; can be set in xconfig.sh)
WPSSRC=${WPSSRC:-"${WRFROOT}/WPS/"}
WRFSRC=${WRFSRC:-"${WRFROOT}/WRFV3/"}
 
# Figure out queue systems from machine setup scripts
TMP=$( eval $( grep 'QSYS=' "${WRFTOOLS}/Machines/${WPSSYS}/setup_${WPSSYS}.sh" ); echo "${QSYS}" )
# NOTE: In the above, first grep grabs the line containing QSYS and then the code 
#   evaluates that line (it's an export command), so ${QSYS} (the Q system variable) 
#   is assigned. The code then echo's that var's contents, so TMP has its contents.
#   Do note that since QSYS is defined internal to the command, it is not accessible 
#   outside of the command.
WPSQ=${WPSQ:-$( echo "${TMP}" | tr '[:upper:]' '[:lower:]' )} # Convert WPSQ to all lower case.
TMP=$( eval $( grep 'QSYS=' "${WRFTOOLS}/Machines/${WRFSYS}/setup_${WRFSYS}.sh" ); echo "${QSYS}" )
WRFQ=${WRFQ:-$( echo "${TMP}" | tr '[:upper:]' '[:lower:]' )}

# Fallback queue: shell script 
if [ ! -f "${WRFTOOLS}/Machines/${WPSSYS}/run_cycling_WPS.${WPSQ}" ]; then WPSQ='sh'; fi
if [ ! -f "${WRFTOOLS}/Machines/${WRFSYS}/run_cycling_WRF.${WRFQ}" ]; then WRFQ='sh'; fi
# NOTE: The queue names are also used as file name extension for the run scripts.

# Figure out default wallclock times
TMP=$( eval $( grep 'WPSWCT=' "${WRFTOOLS}/Machines/${WPSSYS}/run_cycling_WPS.${WPSQ}" ); echo "$WPSWCT" )
WPSWCT=${WPSWCT:-"${TMP}"}
TMP=$( eval $( grep 'WRFWCT=' "${WRFTOOLS}/Machines/${WRFSYS}/run_cycling_WRF.${WRFQ}" ); echo "$WRFWCT" )
WRFWCT=${WRFWCT:-"${TMP}"}

# Read number of WPS & WRF nodes/processes
TMP=$( eval $( grep 'WPSNODES=' "${WRFTOOLS}/Machines/${WPSSYS}/run_cycling_WPS.${WPSQ}" ); echo "${WPSNODES:-1}" )
WPSNODES=${WPSNODES:-$TMP}
TMP=$( eval $( grep 'WRFNODES=' "${WRFTOOLS}/Machines/${WRFSYS}/run_cycling_WRF.${WRFQ}" ); echo "${WRFNODES:-1}" )
WRFNODES=${WRFNODES:-$TMP}

# Default WPS, real and WRF executables ?????
GEOEXE=${GEOEXE:-"${WPSSRC}/${WPSSYS}-MPI/${WPSBLD}/Default/geogrid.exe"} 
UNGRIBEXE=${UNGRIBEXE:-"${WPSSRC}/${WPSSYS}-MPI/${WPSBLD}/Default/ungrib.exe"}
METEXE=${METEXE:-"${WPSSRC}/${WPSSYS}-MPI/${WPSBLD}/Default/metgrid.exe"}
REALEXE=${REALEXE:-"${WRFSRC}/${WPSSYS}-MPI/${WRFBLD}/Default/real.exe"} # Shouldn't these be WRFSYS and WRFBLD? ?????
WRFEXE=${WRFEXE:-"${WRFSRC}/${WRFSYS}-MPI/${WRFBLD}/Default/wrf.exe"}
# NOTE: The folder 'Default' can be a symlink to the default directory for executables.

# Archive script name (no $ARSCRIPT means no archiving)
if [[ -n "${IO}" ]]; then
  if [[ "${ARSCRIPT}" == 'DEFAULT_V1' ]]; then 
    ARSCRIPT="arconfig_wrfout_${IO}_1.${WPSQ}"  
  elif [[ "${ARSCRIPT}" == 'DEFAULT_V2' ]]; then 
    ARSCRIPT="arconfig_wrfout_${IO}_2.${WPSQ}"  
  fi   
fi  

# Default averaging script name (no $AVGSCRIPT means no averaging)
if [[ "${AVGSCRIPT}" == 'DEFAULT' ]]; then AVGSCRIPT="run_wrf_avg.${WPSQ}"; fi

# String of single-digit dimensions for archvie and averaging script
DOMS=''; for I in $( seq 1 ${MAXDOM} ); do DOMS="${DOMS}${I}"; done
# NOTE: '$( seq 1 ${MAXDOM} )' means sequence of 1 to ${MAXDOM}.    
# NOTE: The above makes '123...X', where X is ${MAXDOM}.
   
      
# =========================================================================
# ====================== Backup existing files/folders ====================
# =========================================================================

# Prompt on screen
echo 'Backing-up existing files (moved to folder "backup/").'
echo

# Backup the backup
if [[ -e 'backup' ]]; then mv 'backup' 'backup_backup'; fi 
# NOTE: This is because things can go wrong during backup.
# NOTE: "-e" returns true if the target exists. Doesn't matter if it's a file,  
#   pipe, special device, whatever. The only condition where something may exist,  
#   and "-e" will return false is in the case of a broken symlink.

# Make backup folder
mkdir -p 'backup'

# Backup data
eval $( cp -df --preserve=all * 'backup/' &> /dev/null ) 
# NOTE: This moves-on if there're errors (see below) and hides output.
# NOTE: for cp, "-d" is same as "--no-dereference --preserve=links". "--no-dereference" means
#   never follow symbolic links in SOURCE. "--preserve[=ATTR_LIST]" preserve the specified 
#   attributes (default: mode,ownership,timestamps), if possible additional attributes: 
#   context, links, xattr, all.
# NOTE: The point of eval (and $( ... )) here is that as we "set -e" in the initial part of 
#   the code, if there is an error during cp the code will stop. So, we use eval and $( ... ) 
#   to skip errors that might occur.
# NOTE: This backup is not that important (when a simulation finishes, the run folders are 
#   archived in zip files). 
# NOTE: Some of the errors that may occor when copying everything (*) are: We can not copy
#   backup into itself, and that using cp without "-r" to copy folders can result in
#   errors (folders are copied below).
eval $( cp -dRf --preserve=all 'scripts' 'bin' 'meta' 'tables' 'backup/' &> /dev/null ) 
# NOTE: This moves-on if there're errors (see above) and hides output.
# NOTE: "-R", "-r", or "--recursive" copy directories recursively.
# NOTE: We don't append '/' to folders so that links to folders are also removed.

# Clean-up if back up went correctly (else give error)
if [[ -e 'backup/xconfig.sh' && -e 'backup/setupExperiment.sh' ]]
  then # Presumably everything went OK, if these two are in the backup folder.
    eval $( rm -f *.sh *.pbs *.ll &> /dev/null ) # Delete scripts.
    eval $( rm -rf 'scripts' 'bin' 'meta' 'tables' &> /dev/null ) # Delete script and table folders.
    eval $( rm -f 'atm' 'lnd' 'ice' 'plev' 'srfc' 'uv' 'sc' 'sfc' 'pl' 'sl' &> /dev/null ) # Delete input data folders. 
    eval $( rm -f 'GPC' 'TCS' 'P7' 'i7' 'Bugaboo' 'Rocks' 'Niagara' &> /dev/null ) # Delete machine markers. 
    # NOTE: We don't specify "-r" in the above for the folder deletion, as these are  
    #   simlinks and to delete folder simlinks you do not need "-r".
    # NOTE: We don't append '/', so that links to folders are removed.
    # NOTE: If something happens to be a folder (other than script and table folders), we do not want 
    #   to delete that, since it may contain a lot of our data.    
    cp -P 'backup/setupExperiment.sh' 'backup/xconfig.sh' . # Copy back the 2 main files that got deleted.
    # NOTE: "-P" or "--no-dereference" means never follow symbolic links in SOURCE.
    rm -rf 'backup_backup/' # Remove backup of backup, because we have a new backup.
  else echo 'ERROR: backup failed - aborting!'; exit 1
fi 


# =========================================================================
# ========================== Create namelist files ========================
# =========================================================================

# Export relevant variables so that writeNamelist.sh can read them (this is for WRF)
export TIME_CONTROL
export TIME_CONTROL_MOD
export DIAGS
export DIAGS_MOD
export PHYSICS
export PHYSICS_MOD
export NOAH_MP
export NOAH_MP_MOD
export DOMAINS
export DOMAINS_MOD
export FDDA
export FDDA_MOD
export DYNAMICS
export DYNAMICS_MOD
export BDY_CONTROL
export BDY_CONTROL_MOD
export NAMELIST_QUILT
export NAMELIST_QUILT_MOD

# Export relevant variables so that writeNamelist.sh can read them (this is for WPS)
export SHARE
export SHARE_MOD
export GEOGRID
export GEOGRID_MOD
export METGRID
export METGRID_MOD
# NOTE: The "_MOD" variables can be set in xconfig.sh and will modify the existing 
#   namelist entries as specified (see xconfig.sh for more details). 

# Create namelists
echo "Creating WRF and WPS namelists (using ${WRFTOOLS}/Scripts/Setup/writeNamelists.sh)."
cd "${RUNDIR}"
mkdir -p "${RUNDIR}/scripts/"
ln -sf "${WRFTOOLS}/Scripts/Setup/writeNamelists.sh"
# NOTE: "-s" or "--symbolic" is to make symbolic links instead of hard links.
# NOTE: "-f" or "--force" removes existing destination files.
# NOTE: If you do not specify the ln command's destination, it creates the
#   link at the current directory.
mv writeNamelists.sh scripts/
export WRFTOOLS
./scripts/writeNamelists.sh

# Fix number of domains in WRF and WPS namelists
sed -i "/max_dom/ s/^\ *max_dom\ *=\ *.*$/ max_dom = ${MAXDOM}, ! This entry was edited by the setup script./" namelist.input namelist.wps

# Remove references to FLake from namelist.input, if not used
if [[ "${FLAKE}" != 1 ]]; then
  sed -i "/flake_update/ s/^\ *flake_update\ *=\ *.*$/! flake_update was removed because FLake is not used./" namelist.input
  sed -i "/tsk_flake/ s/^\ *tsk_flake\ *=\ *.*$/! tsk_flake was removed because FLake is not used./" namelist.input
  sed -i "/transparent/ s/^\ *transparent\ *=\ *.*$/! transparent was removed because FLake is not used./" namelist.input
  sed -i "/lake_depth_limit/ s/^\ *lake_depth_limit\ *=\ *.*$/! lake_depth_limit was removed because FLake is not used./" namelist.input
fi 

# Set the correct path for geogrid data
echo
echo "Setting path for geogrid data:"
if [[ -n "${GEODATA}" ]]; then
  sed -i "/geog_data_path/ s+\ *geog_data_path\ *=\ *.*$+ geog_data_path = \'${GEODATA}\',+" namelist.wps
  # NOTE: Here we are using "+" as the delimeter for the s command (instead of "\").
  echo "  ${GEODATA}"
else echo "  WARNING: no geogrid path selected!"; fi


# ========================================================================================
# == Determine time step & restart decrement (reduce dt how much, if run goes unstable) ==
# ========================================================================================

if [[ "${DELT}" == 'DEFAULT' ]]; then 
  DT=$(sed -n '/time_step/ s/^\ *time_step\ *=\ *\([0-9]\+\).*$/\1/p' namelist.input) 
  # NOTE: By default, sed prints out the pattern space at the end of each cycle through the 
  #   script. '-n' disables this automatic printing, and sed only produces output when 
  #   explicitly told to via the p command (like at the end of the above s command).
  # NOTE: \(regexp\) groups the inner regexp as a whole, this is used to apply postfix  
  #   operators, like \(abcd\)*: this will search for zero or more whole sequences of ‘abcd’.
  # NOTE: \+ is as *, but matches one or more. It is a GNU extension.
  # NOTE: In the above, \1 is just the repetition of \([0-9]\+\). Back-references are regular
  #   expression commands which refer to a previous part of the matched regular expression. 
  #   Back-references are specified with backslash and a single digit (e.g. ‘\1’). The part 
  #   of the regular expression they refer to is called a subexpression, and is designated 
  #   with parentheses.
  # NOTE: By definition, time_step is an integer (number of seconds).
  if [[ -z "$DT" ]]; then echo -e '\nERROR: No time step identified in namelist - aborting!\n'; exit 1;
  elif [ $DT -gt 400 ]; then DELT='120'
  elif [ $DT -gt 200 ]; then DELT='60'
  elif [ $DT -gt 100 ]; then DELT='30'
  elif [ $DT -gt  50 ]; then DELT='15'
  elif [ $DT -gt  30 ]; then DELT='10'
  else DELT='5'; fi 
fi 


# =================================================================================
# ========================== Link WPS meta data and data ==========================
# =================================================================================

# Prompt on screen
echo
echo "Linking WPS meta data and data."

# Make meta folder and move inside
mkdir -p "${RUNDIR}/meta"
cd "${RUNDIR}/meta"

# Link GEOGRID.TBL and METGRID.TBL from WPS folder
ln -sf "${WPSSRC}/geogrid/${GEOGRIDTBL}" 'GEOGRID.TBL'
ln -sf "${WPSSRC}/metgrid/${METGRIDTBL}" 'METGRID.TBL'

# Link POPMAP or VTABLE, if needed (POPMAP is for ocean grid definition)
if [[ "${DATATYPE}" == 'CESM' ]] || [[ "${DATATYPE}" == 'CCSM' ]] || [[ "${DATATYPE}" == 'CMIP5' ]]; then
  ln -sf "${WRFTOOLS}/misc/data/${POPMAP}"
elif [[ "${DATATYPE}" == 'CFSR' ]]; then
  ln -sf "${WPSSRC}/ungrib/Variable_Tables/${VTABLE_PLEV}" 'Vtable.CFSR_plev'
  ln -sf "${WPSSRC}/ungrib/Variable_Tables/${VTABLE_SRFC}" 'Vtable.CFSR_srfc'
elif [[ -n "${VTABLE}" ]]; then 
  ln -sf "${WPSSRC}/ungrib/Variable_Tables/${VTABLE}" 'Vtable'
else 
  echo "VTABLE variable is needed but not defined. Aborting." 
  exit 1
fi     

# Link boundary data
echo
echo "Linking boundary data: ${DATADIR} (boundary data type: ${DATATYPE})."
cd "${RUNDIR}"
if [[ "${DATATYPE}" == 'CESM' ]] || [[ "${DATATYPE}" == 'CCSM' ]]; then
  rm -f 'atm' 'lnd' 'ice'
  ln -sf "${DATADIR}/atm/hist/" 'atm' # Atmosphere.
  ln -sf "${DATADIR}/lnd/hist/" 'lnd' # Land surface.
  ln -sf "${DATADIR}/ice/hist/" 'ice' # Sea ice.
elif [[ "${DATATYPE}" == 'CMIP5' ]]; then
  rm -f 'init'
  ln -sf "${DATADIR}/" 'init'  # Initial file directory.
elif [[ "${DATATYPE}" == 'CMIP6' ]]; then
  rm -f 'cmip6_data'
  ln -sf "${DATADIR}/" 'cmip6_data'  # CMIP6 data file directory.  
elif [[ "${DATATYPE}" == 'CFSR' ]]; then
  rm -f 'plev' 'srfc'
  ln -sf "${DATADIR}/plev/" 'plev' # Pressure level date (3D, 0.5 deg).
  ln -sf "${DATADIR}/srfc/" 'srfc' # Surface data (2D, 0.33 deg).
elif [[ "${DATATYPE}" == 'ERA-I' ]]; then
  rm -f 'uv' 'sc' 'sfc' 
  ln -sf "${DATADIR}/uv/" 'uv' # Pressure level date (3D, 0.7 deg).
  ln -sf "${DATADIR}/sc/" 'sc' # Pressure level date (3D, 0.7 deg).
  ln -sf "${DATADIR}/sfc/" 'sfc' # Surface data (2D, 0.7 deg).
elif [[ "${DATATYPE}" == 'ERA5' ]]; then
  rm -f 'pl' 'sl' 
  ln -sf "${DATADIR}/pl/" 'pl' # Pressure level date (3D, 0.25 deg).
  ln -sf "${DATADIR}/sl/" 'sl' # Surface data (2D, 0.25 deg).
fi 


# =================================================================================
# =================== Link in WPS/REAL scripts and executables ====================
# =================================================================================

# Displaying info about WPS/REAL scripts and executables
echo
echo "============================================================================================================"
echo " Linking WPS/REAL scripts and executables (WRF TOOLS is ${WRFTOOLS}) "
echo " System: ${WPSSYS}, Queue: ${WPSQ}.                                 "
echo "============================================================================================================"

# Move into run dir (user scripts are in the root folder)
cd "${RUNDIR}"

# Initialize WPS run script (concatenate machine specific and common components)
cat "${WRFTOOLS}/Machines/${WPSSYS}/run_${CASETYPE}_WPS.${WPSQ}" > "run_${CASETYPE}_WPS.${WPSQ}"
cat "${WRFTOOLS}/Scripts/Common/run_${CASETYPE}.environment" >> "run_${CASETYPE}_WPS.${WPSQ}"
# NOTE: If we do not set ${CASETYPE} in xconfig, it is set within this script 
#   to 'cycling' (if '${CYCLING} was set before) or 'test' (if ${CYCLING} is empty).
# NOTE: ">" overwrites an exisiting file, while ">>" appends to an existing file.
#   Both make a new file, if it does not exist.

# If there are custom environment settings in xconfig.sh, add them here
if [ $( grep -c 'custom environment' xconfig.sh ) -gt 0 ]; then
  # NOTE: "-c" option above outputs count of matching lines only.
  RUNSCRIPT="run_${CASETYPE}_WPS.${WPSQ}"
  echo
  echo "Adding custom environment section from xconfig.sh to run-script '${RUNSCRIPT}'."
  echo '' >> "${RUNSCRIPT}"; echo '' >> "${RUNSCRIPT}" # Add line breaks.
  sed -n '/begin\ custom\ environment/,/end\ custom\ environment/p' xconfig.sh >>  "${RUNSCRIPT}"
  # NOTE: By default, sed prints out the pattern space at the end of each cycle through 
  #   the script. "-n" option disables this automatic printing, and sed only produces 
  #   output when explicitly told to via the p command.
  # NOTE: In sed, an address range can be specified by specifying two addresses separated
  #   by a comma (,). In the above the lines from "begin ..." to "end ..." are selected  
  #   and then command p tells the sed to print them to output.
  echo '' >> "${RUNSCRIPT}"; echo '' >> "${RUNSCRIPT}" # Add line breaks.
fi 

# Add another WPS run script component
cat "${WRFTOOLS}/Scripts/Common/run_${CASETYPE}_WPS.common" >> "run_${CASETYPE}_WPS.${WPSQ}"

# Make the necessary changes in the WPS run script 
RENAME "run_${CASETYPE}_WPS.${WPSQ}"

# If WPSQ is shell, then make executable
if [[ "${WPSQ}" == "sh" ]]; then 
  chmod u+x "run_${CASETYPE}_WPS.${WPSQ}"; fi 

# Run-script components (go into "scripts" folder)
mkdir -p "${RUNDIR}/scripts/"
cd "${RUNDIR}/scripts/"
ln -sf "${WRFTOOLS}/Scripts/Common/execWPS.sh"
# NOTE: For "ln", the "-f" option means remove existing destination files.
ln -sf "${WRFTOOLS}/Machines/${WPSSYS}/setup_${WPSSYS}.sh" 'setup_WPS.sh' 
# NOTE: The above renames the link to "setup_WPS.sh".
if [[ "${WPSSYS}" == "GPC" ]] || [[ "${WPSSYS}" == "i7" ]]; then 
  ln -sf "${WRFTOOLS}/Python/wrfrun/selectWPSqueue.py"; fi 
cd "${RUNDIR}"

# WPS/real executables (go into "bin" folder)
mkdir -p "${RUNDIR}/bin/"
# NOTE: -p above means no error if existing, make parent directories as needed.
cd "${RUNDIR}/bin/"
ln -sf "${WRFTOOLS}/Python/wrfrun/pyWPS.py"
ln -sf "${GEOEXE}"
ln -sf "${METEXE}"
ln -sf "${REALEXE}"
if [[ "${DATATYPE}" == 'CESM' ]] || [[ "${DATATYPE}" == 'CCSM' ]]; then
  ln -sf "${WRFTOOLS}/NCL/unccsm.ncl"
  ln -sf "${WRFTOOLS}/bin/${WPSSYS}/unccsm.exe"
elif  [[ "${DATATYPE}" == 'CMIP5' ]]; then
  ln -sf "${WRFTOOLS}/NCL/unCMIP5.ncl"
  ln -sf "${WRFTOOLS}/bin/${WPSSYS}/unccsm.exe"
elif  [[ "${DATATYPE}" == 'CMIP6' ]]; then
  ln -sf "${WRFTOOLS}/Python/wrfrun/unCMIP6.py"   
elif  [[ "${DATATYPE}" == 'ERA5' ]]; then
  ln -sf "${WRFTOOLS}/Python/wrfrun/fixIM.py"
  ln -sf "${UNGRIBEXE}"
else
  ln -sf "${UNGRIBEXE}"
fi 
cd "${RUNDIR}"


# =================================================================================
# ====================== Link in WRF scripts and executables ======================
# =================================================================================

# Displaying info about WRF scripts and executables
echo
echo "============================================================================================================"
echo " Linking WRF scripts and executables (WRF TOOLS is ${WRFTOOLS}):"
echo " System: ${WRFSYS}, Queue: ${WRFQ}."
echo "============================================================================================================"

# Initialize a file named ${WRFSYS} and make it executable
touch "${WRFSYS}" 
chmod u+x "${WRFSYS}" 
# NOTE: This file will be empty. This is just so that we know, on which system
#   we are running, when we do an "ls" command. We make the file executable so
#   that it appears highlighted within "ls" command output. 

# Move into run dir (user scripts are in the root folder)
cd "${RUNDIR}"

# Handle CYCLING related stuff, if applicable
if [[ -n "${CYCLING}" ]]; then
  # If possible, use existing step file in archive (works without pandas)
  if [[ -f "${WRFTOOLS}/misc/stepfiles/stepfile.${CYCLING}" ]]; then    
    cp "${WRFTOOLS}/misc/stepfiles/stepfile.${CYCLING}" 'stepfile'
  # Otherwise, generate the step file
  else    
    # Interprete step definition string (begin:end:interval)
    BEGIN=${CYCLING%:*:*}
    END=${CYCLING%:*}; END=${END#*:}
    INT=${CYCLING#*:*:}
    # NOTE: ${var%string} means delete the shortest match of string in $var from 
    #   the end, whereas ${var#string} means delete the shortest match of string 
    #   in $var from the beginning.    
    # Python script to generate stepfiles
    GENSTEPS=${GENSTEPS:-"${WRFTOOLS}/Python/wrfrun/generateStepfile.py"} 
    # Prompt on screen
    echo
    echo "Creating new stepfile: Begin=${BEGIN}, End=${END}, Interval=${INT}."    
    # Generate step file
    python "${GENSTEPS}" ${LLEAP} --interval="${INT}" "${BEGIN}" "${END}" 
    # NOTE: LLEAP can be set before above. If true, it allows for leap days. We
    #   want to set it to false for GCM calenders without leap days. In the python
    #   script, it is set to true by default. 
  fi
  # Add start cycle script and modify it as needed
  cp "${WRFTOOLS}/Scripts/Common/startCycle.sh" .
  RENAME "startCycle.sh"
fi 

# Initialize WRF run script (concatenate machine specific and common components)
cat "${WRFTOOLS}/Machines/${WRFSYS}/run_${CASETYPE}_WRF.${WRFQ}" > "run_${CASETYPE}_WRF.${WRFQ}"
cat "${WRFTOOLS}/Scripts/Common/run_${CASETYPE}.environment" >> "run_${CASETYPE}_WRF.${WRFQ}"
# NOTE: If we do not set ${CASETYPE} in xconfig, it is set within this script 
#   to 'cycling' (if '${CYCLING} was set before) or 'test' (if ${CYCLING} is empty).
# NOTE: ">" overwrites an exisiting file, while ">>" appends to an existing file.
#   Both make a new file, if it does not exist.

# If there are custom environment settings in xconfig.sh, add them here
if [ $( grep -c 'custom environment' xconfig.sh ) -gt 0 ]; then
  # NOTE: "-c" option above outputs count of matching lines only.
  RUNSCRIPT="run_${CASETYPE}_WRF.${WRFQ}"
  echo
  echo "Adding custom environment section from xconfig.sh to run-script '${RUNSCRIPT}'."
  echo '' >> "${RUNSCRIPT}"; echo '' >> "${RUNSCRIPT}" # Add line breaks.
  sed -n '/begin\ custom\ environment/,/end\ custom\ environment/p' xconfig.sh >>  "${RUNSCRIPT}"
  # NOTE: By default, sed prints out the pattern space at the end of each cycle through 
  #   the script. "-n" option disables this automatic printing, and sed only produces 
  #   output when explicitly told to via the p command.
  # NOTE: In sed, an address range can be specified by specifying two addresses separated
  #   by a comma (,). In the above the lines from "begin ..." to "end ..." are selected  
  #   and then command p tells the sed to print them to output.
  echo '' >> "${RUNSCRIPT}"; echo '' >> "${RUNSCRIPT}" # Add line breaks.
fi 

# Add another WRF run script component
cat "${WRFTOOLS}/Scripts/Common/run_${CASETYPE}_WRF.common" >> "run_${CASETYPE}_WRF.${WRFQ}"

# Make the necessary changes in the WRF run script
RENAME "run_${CASETYPE}_WRF.${WRFQ}"

# If WRFQ is shell, then make executable
if [[ "${WRFQ}" == "sh" ]]; then 
  chmod u+x "run_${CASETYPE}_WRF.${WRFQ}"; fi 

# Make scripts folder and move into it 
mkdir -p "${RUNDIR}/scripts/"
# NOTE: "-p" above means no error if existing, make parent directories 
#   as needed.
cd "${RUNDIR}/scripts/"

# Run-script components (go into "scripts" folder)
ln -sf "${WRFTOOLS}/Scripts/Common/execWRF.sh"
ln -sf "${WRFTOOLS}/Machines/${WRFSYS}/setup_${WRFSYS}.sh" 'setup_WRF.sh' 
if [[ -n "${CYCLING}" ]]; then
    ln -sf "${WRFTOOLS}/Scripts/Setup/setup_cycle.sh"
    ln -sf "${WRFTOOLS}/Scripts/Common/launchPreP.sh"
    ln -sf "${WRFTOOLS}/Scripts/Common/launchPostP.sh"
    ln -sf "${WRFTOOLS}/Scripts/Common/resubJob.sh"
    ln -sf "${WRFTOOLS}/Scripts/Common/crashHandler.sh"
    ln -sf "${WRFTOOLS}/Python/wrfrun/cycling.py"
fi 

# Move into "${RUNDIR}"
cd "${RUNDIR}"

# WRF executable (goes into 'bin' folder)
mkdir -p "${RUNDIR}/bin/"
# NOTE: "-p" means no error if existing, make parent directories as needed.
cd "${RUNDIR}/bin/"
ln -sf "${WRFEXE}"
cd "${RUNDIR}"


# =================================================================================
# ========================= Setup archiving and averaging =========================
# =================================================================================

# Displaying info about archiving and averaging
echo
echo "============================================================================================================"
echo " Setting up archiving and averaging."
echo "============================================================================================================"

# Prepare archiving script, if applicable
if [[ -n "${ARSCRIPT}" ]] && [[ -n "${ARSYS}" ]]; then
  cp -f "${WRFTOOLS}/Machines/${ARSYS}/${ARSCRIPT}" .    
  echo
  echo "Setting up archiving: ${ARSCRIPT}."  
  RENAME "${ARSCRIPT}" # Update folder names and queue parameters.
fi 

# Prepare averaging scripts and make wrfavg folder, if applicable
if [[ -n "${AVGSCRIPT}" ]] && [[ -n "${AVGSYS}" ]]; then
    ln -s "${WRFTOOLS}/Python/wrfavg/wrfout_average.py" "./scripts/"
    # NOTE: The absence of "-f" above means we do not remove existing destination files.
    ln -s "${WRFTOOLS}/Machines/${AVGSYS}/addVariable.sh" "./scripts/"
    cp -f "${WRFTOOLS}/Machines/${AVGSYS}/${AVGSCRIPT}" .
    mkdir -p 'wrfavg' # Folder for averaged output.    
    echo
    echo "Setting up averaging: ${AVGSCRIPT}"
    RENAME "${AVGSCRIPT}" # Update folder names and queue parameters.
fi 


# =================================================================================
# ==================== Handle selected physics options' needs =====================
# =================================================================================

# Displaying info about handling selected physics options' needs
echo
echo "============================================================================================================"
echo " Handling selected physics options' needs."
echo "============================================================================================================"

# ================================ Radiation scheme ================================
# Obtain radiation scheme from namelist.input
RAD=$(sed -n '/ra_lw_physics/ s/^\ *ra_lw_physics\ *=\ *\(.\),.*$/\1/p' namelist.input) 
# Check if schemes for SW and LW radiation are the same
if [[ "${RAD}" != $(sed -n '/ra_sw_physics/ s/^\ *ra_sw_physics\ *=\ *\(.\),.*$/\1/p' namelist.input) ]]; then
  echo 'Error: Different schemes for SW and LW radiation are currently not supported.'
  exit 1
fi 
# Prompt on screen 
echo
echo "Determining radiation scheme from namelist: RAD=${RAD}."
# Write RAD into job script run_${CASETYPE}_WRF.${WRFQ}
sed -i "/export RAD/ s/export\ RAD=.*$/export RAD=\'${RAD}\' # Radiation scheme set by setup script./" "run_${CASETYPE}_WRF.${WRFQ}"
# Select scheme tables and print confirmation
if [[ ${RAD} == 1 ]]; then
  echo "  Using RRTM radiation scheme."
  RADTAB="RRTM_DATA RRTM_DATA_DBL"
elif [[ ${RAD} == 3 ]]; then
  echo "  Using CAM radiation scheme."
  RADTAB="CAM_ABS_DATA CAM_AEROPT_DATA ozone.formatted ozone_lat.formatted ozone_plev.formatted"
elif [[ ${RAD} == 4 ]]; then
  echo "  Using RRTMG radiation scheme."
  RADTAB="RRTMG_LW_DATA RRTMG_LW_DATA_DBL RRTMG_SW_DATA RRTMG_SW_DATA_DBL"
  # Check additional radiation options: aer_opt & o3input     
  AER=$(sed -n '/aer_opt/ s/^\ *aer_opt\ *=\ *\(.\).*$/\1/p' namelist.input) 
  if [[ -n $AER ]] && [ $AER -eq 1 ]; then # Add aerosol climatology of Tegen.
    RADTAB="${RADTAB} aerosol.formatted aerosol_plev.formatted aerosol_lat.formatted aerosol_lon.formatted"; fi
  O3=$(sed -n '/o3input/ s/^\ *o3input\ *=\ *\(.\).*$/\1/p' namelist.input) 
  if [[ -z $O3 ]] || [ $O3 -eq 2 ]; then # Add ozone climatology from CAM.
    RADTAB="${RADTAB} ozone.formatted ozone_plev.formatted ozone_lat.formatted"; fi
    # NOTE: The default changed in V3.7 from o3input=0 to o3input=2, which means the input files are required by default.
else
  echo '  WARNING: No radiation scheme selected, or selection not supported!'
fi

# ================================ Urban surface scheme ================================
# Obtain urban surface scheme from namelist.input
URB=$(sed -n '/sf_urban_physics/ s/^\ *sf_urban_physics\ *=\ *\(.\),.*$/\1/p' namelist.input) 
# Prompt on screen
echo
echo "Determining urban surface scheme from namelist: URB=${URB}."
# Write URB into job script run_${CASETYPE}_WRF.${WRFQ}
sed -i "/export URB/ s/export\ URB=.*$/export URB=\'${URB}\' # Urban surface scheme set by setup script./" "run_${CASETYPE}_WRF.${WRFQ}"
# Select scheme tables and print confirmation
if [[ ${URB} == 0 ]]; then
  echo '  No urban surface scheme selected.'
  URBTAB=""
elif [[ ${URB} == 1 ]]; then
  echo "  Using single layer urban surface scheme."
  URBTAB="URBPARM.TBL"
elif [[ ${URB} == 2 ]]; then
  echo "  Using multi-layer urban surface scheme."
  URBTAB="URBPARM_UZE.TBL"
  # Check bl_pbl_physics compatibility
  PBL=$(sed -n '/bl_pbl_physics/ s/^\ *bl_pbl_physics\ *=\ *\(.\),.*$/\1/p' namelist.input) 
  if [[ ${PBL} != 2 ]] && [[ ${PBL} != 8 ]]; then
    echo '  WARNING: sf_urban_physics = 2 requires bl_pbl_physics = 2 or 8!'; fi
else
  echo '  No urban scheme selected! Default: none.'
fi

# ================================ Land-surface scheme ================================
# Obtain land-surface scheme from namelist.input
LSM=$(sed -n '/sf_surface_physics/ s/^\ *sf_surface_physics\ *=\ *\(.\),.*$/\1/p' namelist.input) 
# Prompt on screen
echo
echo "Determining land-surface scheme from namelist: LSM=${LSM}."
# Write LSM into job script run_${CASETYPE}_WRF.${WRFQ}
sed -i "/export LSM/ s/export\ LSM=.*$/export LSM=\'${LSM}\' # Land surface scheme set by setup script./" "run_${CASETYPE}_WRF.${WRFQ}"
# Select scheme tables and print confirmation
if [[ ${LSM} == 1 ]]; then
    echo "  Using diffusive land-surface scheme."
    LSMTAB="LANDUSE.TBL"
elif [[ ${LSM} == 2 ]]; then
    echo "  Using Noah land-surface scheme."
    LSMTAB="SOILPARM.TBL VEGPARM.TBL GENPARM.TBL LANDUSE.TBL"
elif [[ ${LSM} == 3 ]]; then
    echo "  Using RUC land-surface scheme."
    LSMTAB="SOILPARM.TBL VEGPARM.TBL GENPARM.TBL LANDUSE.TBL"
elif [[ ${LSM} == 4 ]]; then
    echo "  Using Noah-MP land-surface scheme."
    LSMTAB="SOILPARM.TBL VEGPARM.TBL GENPARM.TBL LANDUSE.TBL MPTABLE.TBL"    
elif [[ ${LSM} == 5 ]]; then
    echo "  Using CLM4 land-surface scheme."
    LSMTAB="SOILPARM.TBL VEGPARM.TBL GENPARM.TBL LANDUSE.TBL CLM_ALB_ICE_DFS_DATA CLM_ASM_ICE_DFS_DATA CLM_DRDSDT0_DATA CLM_EXT_ICE_DRC_DATA CLM_TAU_DATA CLM_ALB_ICE_DRC_DATA CLM_ASM_ICE_DRC_DATA CLM_EXT_ICE_DFS_DATA CLM_KAPPA_DATA"
else
    echo '  WARNING: No land-surface model selected!'
fi

# Determine tables folder
if [[ ${LSM} == 4 ]] && [[ -e "${WRFSRC}/run-NoahMP/" ]]; then # NoahMP.
# NOTE: "-e" returns true if the target exists. Doesn't matter if it's a file,  
#   pipe, special device, whatever. The only condition where something may exist,  
#   and "-e" will return false is in the case of a broken symlink.  
  TABLES="${WRFSRC}/run-NoahMP/"
  echo
  echo "Linking Noah-MP tables: ${TABLES}."
elif [[ ${POLARWRF} == 1 ]] && [[ -e "${WRFSRC}/run-PolarWRF/" ]]; then # PolarWRF.
  TABLES="${WRFSRC}/run-PolarWRF/"
  echo
  echo "Linking PolarWRF tables: ${TABLES}."
else
  TABLES="${WRFSRC}/run/"
  echo
  echo "Linking default tables: ${TABLES}."
fi

# Link appropriate tables for physics options
mkdir -p "${RUNDIR}/tables/"
# NOTE: "-p" means no error if existing, make parent directories as needed.
cd "${RUNDIR}/tables/"
for TBL in ${RADTAB} ${LSMTAB} ${URBTAB}; do
  ln -sf "${TABLES}/${TBL}"
done

# Copy/link data file for emission scenario, if applicable
if [[ -n "${GHG}" ]]; then 
  echo
  if [[ ${RAD} == 'RRTM' ]] || [[ ${RAD} == 1 ]] || [[ ${RAD} == 'CAM' ]] || [[ ${RAD} == 3 ]] || [[ ${RAD} == 'RRTMG' ]] || [[ ${RAD} == 4 ]]
  then
    echo "GHG emission scenario: ${GHG}."
    ln -sf "${TABLES}/CAMtr_volume_mixing_ratio.${GHG}" # Does not clip scenario extension (yet).
  else
    echo "WARNING: Variable GHG emission scenarios not available with the selected ${RAD} scheme!"
    unset GHG # Unset GHG for later use.
  fi
fi

# Return to run directory
cd "${RUNDIR}" 

# Add GHG emission scenario to run_${CASETYPE}_WRF.${WRFQ} 
sed -i "/export GHG/ s/export\ GHG=.*$/export GHG=\'${GHG}\' # GHG emission scenario set by setup script./" "run_${CASETYPE}_WRF.${WRFQ}"
# NOTE: If no GHG scenario is selected, the variable will be empty.


# =================================================================================
# =================================== Finish up ===================================
# =================================================================================

# Prompt user to create data links, etc
echo
echo "============================================================================================================"
echo " Remaining tasks:"
echo "============================================================================================================"
echo
echo " * Review meta data and namelists."
echo " * Edit run scripts, if necessary."
if  [[ "${DATATYPE}" == 'CMIP5' ]]; then
  echo
  echo "For CMIP5 data:"
  echo " * Copy the necessary meta files for CMIP5 into the meta folder."
  echo " * These files include the ocn2atm, orog, and sftlf files for grid info."
  echo " * Copy the cdb_query CMIP5 validate file into the meta folder."
fi
echo

# Count number of broken links
CNT=0
for FILE in * bin/* scripts/* meta/* tables/*; do 
# NOTE: */ includes data links (e.g. atm/).
  if [[ ! -e $FILE ]]; then
  # NOTE: "-e" returns true if the target exists. Doesn't matter if it's a file,  
  #   pipe, special device, whatever. The only condition where something may exist,  
  #   and "-e" will return false is in the case of a broken symlink.
    CNT=$(( CNT + 1 ))
    if  [ $CNT -eq 1 ]; then
      echo " * Fix broken links."
      echo
      echo "  Broken links:"
      echo
    fi
    ls -l "${FILE}"
  fi
done
if [ $CNT -gt 0 ]; then
  echo "   >>>   WARNING: There are ${CNT} broken links!!!   <<<   "
  echo
fi
echo

exit ${CNT} # Return number of broken links as error code.





 













