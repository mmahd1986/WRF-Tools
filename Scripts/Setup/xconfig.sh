#!/bin/bash

# This script is the first script that we should run. It sets up some configuration
# parameters, etc, before we set up the experiment (setupExperiment.sh, next step).


# ==================================================================================
# ============================== WRF Tools directory ===============================
# ==================================================================================

# WRF Tools directory
WRFTOOLS="${CODE_ROOT}/WRF-Tools"


# ==================================================================================
# ========================== Scenario definition section ===========================
# ==================================================================================

# Case Name
NAME='NA-ERAI-Test'

# GHG emission scenario
GHG='RCP8.5' # CAMtr_volume_mixing_ratio.* file to be used.

# Time period and cycling interval
CYCLING="1979-01-01:1982-01-01:1M" 
# NOTE: The date range is given as start:end:freq using the Pandas date_range format. 
#   The last number is the frequency used for the step file, with 1D meaning 1 day,
#   and 1M meaning 1 month.
# NOTE: The dates in the above are in the YYYY-MM-DD format.

# I/O, archiving and averaging
IO='fineIO' # This is used for namelist construction and archiving.
ARSYS='' 
# NOTE: If we set ARSYS to '', archiving is not implimented. To do archiving we can  
#   set this variable to HPSS.
ARSCRIPT='DEFAULT' 
# NOTE: Set ARSCRIPT='DEFAULT' to let $IO control archiving. 
# NOTE: All CAPS keywords have special meanings, e.g., DEFAULT.
# NOTE: Archiving is only implimented for fine IO (not default IO).
# NOTE: If ARSYS is empty, then the ARSCRIPT variable is not important.
ARINTERVAL='YEARLY' 
# NOTE: If archiving is done and ARINTERVAL='', the archiving is done after every step
#   (not time step). This can also be YEARLY or MONTHLY as well. The YEARLY choice is
#   usually the best choice. The only cases where monthly could be prefered are those 
#   with 3 km or less resolution (for these a small job step, e.g., 3 days, is needed
#   as well).       
AVGSYS='Niagara' 
# NOTE: If we set AVGSYS to '', averaging is not implimented. To do avergaing we can  
#   set this variable to e.g., Niagara.
AVGSCRIPT='DEFAULT' 
# NOTE: Set AVGSCRIPT='DEFAULT' to let $IO control averaging.
# NOTE: If AVGSYS is empty, then the AVGSCRIPT variable is not important.
AVGINTERVAL='MONTHLY' 
# NOTE: If averaging is done, it is always monthly. The AVGINTERVAL just determines 
#   how often the script is ran. If averaging is done and AVGINTERVAL='', the averaging 
#   is done after every step (not time step). Running averaging after every job is 
#   unnecessary. For monthly jobs, a good choice is usually to use YEARLY. If you run 
#   averaging monthly, the job just takes a few minutes, so not really worth the 
#   scheduling overhead. If the simulation is 0.5 years and you set it YEARLY, it 
#   does not compute averages at all. 
# NOTE: You can always disable averaging during run and run averaging after finishing 
#   the run.  
# NOTE: Archiving and averaging are all handled by the launchPostP.sh script.  


# ==================================================================================
# ============================ Configure data sources ==============================
# ==================================================================================

# Run directory
RUNDIR="${PWD}" # Must not contain spaces.

# Geographic data source
GEODATA='/project/p/peltier/WRF/geog_20210707/'

# Meteorological data source definitions
DATATYPE='ERA-I'
DATADIR='/project/p/peltier/WRF/ERA-I'


# ==================================================================================
# ========================= Email address for job scripts ==========================
# ==================================================================================

EMAIL='mani.mahdinia@utoronto.ca'


# ==================================================================================
# ========================== Namelist definition section ===========================
# ==================================================================================

# Maximum number of domains, domain resolution, and domain type
MAXDOM=1 # Number of domains in WRF and WPS.
RES='12km' # Domain resolution.
# NOTE: The RES parameter does not need to be more accurate than necessary. 
DOM="na-era-i-${RES}" # Domain type.
# NOTE: The latter two options come in when selecting namelist snippets from   
#   "WRF Tools/misc/namelists/geogrid" and "WRF Tools/misc/namelists/domains".

# WPS settings
SHARE='arw' # Type of arw settings.
GEOGRID="${DOM},${DOM}-grid" # Type of geogrid.
# NOTE: SHARE,GEOGRID, and METGRID usually don't have to be set manually.

# WRF settings
TIME_CONTROL="cycling,${IO}" # Type of time control.
DIAGS='hitop' # Type of diags.
PHYSICS='conus' # Type of physics.
NOAH_MP='conus' # Type for Noah_MP.
DOMAINS="${DOM},${DOM}-grid" # Type of domain.
# NOTE: ${VAR,,} is called "Parameter Expansion" available in bash and it is
#   to change the case of the string stored in the variable to lower case.
FDDA='conus' # Type of FDDA.
DYNAMICS='conus' # Type of dynamics.
BDY_CONTROL='conus' # Type of boundary control.
NAMELIST_QUILT='' # Type of namelist quilt.
 

# ==================================================================================
# ======================== Namelist modifications by group =========================
# ==================================================================================

# NOTE: We can make modifications to namelist groups in the {NMLGRP}_MOD variables.
#   The line in the *_MOD variable will replace the corresponding entry in the template.
#   We can separate multiple modifications by colons ':'. An example is:
#   PHYSICS_MOD=' cu_physics = 3, 3, 3,: shcu_physics = 0, 0, 0,: sf_surface_physics = 4, 4, 4,'


# ==================================================================================
# ========== Custom environment section (will be inserted in run script) ===========
# ==================================================================================

# --- begin custom environment ---
export WRFENV='2019b' # WRF environment version (current options 2018a or 2019b).
export WRFWAIT='1m' # Wait some time before launching WRF executable.
export METDATA="${SCRATCH}/WRF4.3_Verification_Runs/WRFTools_RC3/metdata" # Disk metdata storage.
# NOTE: If set, this stores metgrid data to disk (otherwise just within ram).
export RAMIN=1 # To store data in ram data folder (or disk data folder); or not.
export RAMOUT=1 # To write data to RAM and copy to HD later, or to write data directly to hard disk.
# ---  end custom environment  ---
# NOTE: According to Andre, the above wait time probably has to do with file-system errors and 
#   caching. You can reduce or remove the wait time entirely.

# ==================================================================================
# ================================= System settings ================================
# ==================================================================================

# Root of WRF and WPS folders
WRFROOT="$CODE_ROOT/WRF_AND_WPS/"

# Some other timing settings that we can set 
#WPSWCT='00:06:00' # WPS wall clock time.
#WRFWCT='00:15:00' # WRF wall clock time.
#WRFNODES=4 # Number of nodes to run WRF.         
#DELT='45' # Amount of time (secs) to decrease in case of instability.

# WPS executables
WPSSYS="Niagara" # WPS system. 
# NOTE: WPSSYS also affects unccsm.exe.
# NOTE: We can also specify WPSBLD, e.g., WPSBLD='Clim-fineIO'.
# NOTE: We can set paths for metgrid.exe and real.exe explicitly using METEXE and REALEXE.

# WRF executables
WRFSYS="Niagara" # WRF system.
# NOTE: We can also specify WRFBLD, e.g., WRFBLD='Clim-fineIO'.
# NOTE: We can also set paths for geogrid.exe and wrf.exe explicitly using GEOEXE and WRFEXE.

# Number of geogrid procceses
GEOTASKS=10










