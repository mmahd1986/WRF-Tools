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
NAME='NA-ERA5-GL25_debug'

# GHG emission scenario
GHG='RCP8.5' # CAMtr_volume_mixing_ratio.* file to be used.

# Time period and cycling interval
CYCLING="2015-09-01:2018-01-01:1M" 
# NOTE: The date range is given as start:end:freq using the Pandas date_range format. 
#   The last number is the frequency used for the step file, with 1D meaning 1 day,
#   and 1M meaning 1 month.
# NOTE: The dates in the above are in the YYYY-MM-DD format.

# I/O, archiving and averaging
IO='fineIO' # This is used for namelist construction and archiving.
# NOTE: For ERA5, we may want to output some vars more frequently in finIO; For this we
#   use fineIOv9.highFreq (not fineIOv9) (we have to change the link of fineIO). This has
#   auxhist1_interval = 180, auxhist2_interval = 180, auxhist4_interval = 180, and
#   auxhist23_interval = 180, as opposed to the 360 minute values in fineIOv9.
ARSYS='HPSS' 
# NOTE: If we set ARSYS to '', archiving is not implimented. To do archiving we can  
#   set this variable to HPSS.
ARSCRIPT='arconfig_wrfout_fineIO_2' 
# NOTE: Options are arconfig_wrfout_fineIO_1 (old) and arconfig_wrfout_fineIO_2 (recent).
# NOTE: All CAPS keywords have special meanings, e.g., DEFAULT.
# NOTE: Archiving is only implimented for fine IO (not default IO).
# NOTE: If ARSYS is empty, then the ARSCRIPT variable is not important.
ARINTERVAL='YEARLY' 
# NOTE: If archiving is done and ARINTERVAL='', the archiving is done after every step
#   (not time step). This can also be YEARLY or MONTHLY as well. The YEARLY choice is
#   usually the best choice. The only cases where monthly could be prefered are those 
#   with 3 km or less resolution (for these a small job step, e.g., 3 days, is needed
#   as well).
# NOTE: If ARSYS is not set, but ARINTERVAL is set YEARLY, then archiving is tried at the
#   end of the year and this results in errors (because the archving script is not present).
#   To avoid this, set ARINTERVAL=''.        
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
DATATYPE='ERA5'
DATADIR='/project/p/peltier/WRF/ERA5-NA'


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
DOM="na-era5-${RES}" # Domain type.
# NOTE: The latter two options come in when selecting namelist snippets from   
#   "WRF Tools/misc/namelists/geogrid" and "WRF Tools/misc/namelists/domains".

# WPS settings
SHARE='arw' # Type of arw settings.
GEOGRID="${DOM},${DOM}-grid" # Type of geogrid.
METGRID='pywps' # Type of metgrid.
# NOTE: SHARE, GEOGRID, and METGRID usually don't have to be set manually, but
#   we set them here for the sake of clarification.

# WRF settings
TIME_CONTROL="cycling,${IO}v9.highFreq.lowFreq_dd_and_moist" # Type of time control.
DIAGS='hitop' # Type of diags.
PHYSICS='clim-CONUS-v43' # Type of physics.
NOAH_MP='' # Type for Noah_MP.
DOMAINS="${DOM},${DOM}-grid" # Type of domain.
# NOTE: ${VAR,,} is called "Parameter Expansion" available in bash and it is
#   to change the case of the string stored in the variable to lower case.
FDDA='' # Type of FDDA.
DYNAMICS='cordex' # Type of dynamics.
BDY_CONTROL='clim' # Type of boundary control.
NAMELIST_QUILT='' # Type of namelist quilt.


# ==================================================================================
# ======================== Namelist modifications by group =========================
# ==================================================================================

# NOTE: We can make modifications to namelist groups in the {NMLGRP}_MOD variables.
#   The line in the *_MOD variable will replace the corresponding entry in the template.
#   We can separate multiple modifications by colons ':'. An example is:
#   PHYSICS_MOD=' cu_physics = 3, 3, 3,: shcu_physics = 0, 0, 0,: sf_surface_physics = 4, 4, 4,'

TIME_CONTROL_MOD=' interval_seconds = 10800,: auxinput4_interval = 180,: io_form_auxhist11 = 2,: diag_print = 2,: debug_level = 300,'
# NOTE: The first two mods are for time_control.cycling snippet. We set these here 
#   for ERA5 (half values of ERA-I). The last mod is for time_control.fineIO and is 
#   to turn the snow output on.

DIAGS_MOD=' num_press_levels = 8: press_levels = 85000, 70000, 50000, 25000, 10000, 7000, 4000, 1500'
# NOTE: This is to add extra vertical plev outputs near 10 hPa to be able to make comparison,  
#   between high level (10 hPa) and lower level (50 hPa) model top run cases. 

# Modifications for lake stability
# DYNAMICS_MOD=' epssm = 0.78: time_step_sound = 6'
# DOMAINS_MOD=' time_step = 30' 


# ==================================================================================
# ========== Custom environment section (will be inserted in run script) ===========
# ==================================================================================

# --- begin custom environment ---
export WRFENV='2019b' # WRF environment version (current options 2018a or 2019b).
export WRFWAIT='1m' # Wait some time before launching WRF executable.
export METDATA="${SCRATCH}/ERAI_AND_ERA5_RUN_CASES/WRFTools_RC12c_debug/metdata" # Disk metdata storage.
# NOTE: If set, this stores metgrid data to disk (otherwise just within ram).
export RAMIN=1 # To store data in ram data folder (or disk data folder); or not.
export RAMOUT=1 # To write data to RAM and copy to HD later, or to write data directly to hard disk.
export REPLACE_IM_STLATSTLON='86.95000457763672,-199.20001220703125' # stlat_a and stlon_a for stlat and stlon correction.
# ---  end custom environment  ---
# NOTE: According to Andre, the above wait time probably has to do with file-system errors and 
#   caching. You can reduce or remove the wait time entirely.

# ==================================================================================
# ================================= System settings ================================
# ==================================================================================

# Root of WRF and WPS folders
WRFROOT="$CODE_ROOT/WRF_AND_WPS/"

# WPS and WRF Wall Clock Times
WPSWCT='06:00:00' # WPS wall clock time.
WRFWCT='24:00:00' # WRF wall clock time.  

# Some other timing settings that we can set        
#DELT='45' # Amount of time (secs) to decrease in case of instability.

# WPS executables
WPSSYS="Niagara" # WPS system. 
# NOTE: WPSSYS also affects unccsm.exe.
WPSBLD="ReA-fineIO"
# NOTE: WPSBLD is used to find the WPS executables.
# NOTE: We can also set paths for geogrid.exe, ungrib.exe and metgrid.exe explicitly using GEOEXE, UNGRIBEXE and METEXE.

# WRF executables
WRFSYS="Niagara" # WRF system.
WRFBLD="ReA-fineIO-GLERL25"
# NOTE: WRFBLD is used to find the WRF executables.
# NOTE: We can also set paths for real.exe and wrf.exe explicitly using REALEXE and WRFEXE.

# Number of geogrid procceses
GEOTASKS=40

# Number of nodes to run WRF
WRFNODES=16 










