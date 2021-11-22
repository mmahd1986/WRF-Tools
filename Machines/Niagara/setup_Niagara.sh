#!/bin/bash

# Source script to load GPC-specific settings for pyWPS, WPS, and WRF
# created 16/04/2018 by Andre R. Erler, GPL v3.
# NOTE: GPC = General Purpose Cluster.


# If the run-script defined before, is not for this machine, we need to change the extension
if [[ -n "$QSYS" ]] && [[ -n "$WRFSCRIPT" ]] && [[ "$QSYS" != 'SB' ]]; then  
  # NOTE: "${variable%.*}" means take the value of $variable, strip off the pattern   
  #   .* from the tail of the value and give the result. 
  export WRFSCRIPT="${WRFSCRIPT%.*}.sb"
fi 

# This machine's info
export MAC='Niagara' # Machine name.
export QSYS='SB' # Queue system.

# Default WRF environment version
export WRFENV=${WRFENV:-'2019b'} 
# NOTE: We need to leave default at old envionrment. 

# Python Version
export PYTHONVERSION=${PYTHONVERSION:-3} 
# NOTE: Default Python version is 3 (most scripts are converted now).

# If we are on Niagara, or $SYSTEM is undefined
if [ -z $SYSTEM ] || [[ "$SYSTEM" == "$MAC" ]]; then 
# NOTE: This script may be sourced from other systems, to set certain variables.
#   Basically, everything that would cause errors on another machine, goes here.

  # Unload all loaded modules
  module purge
   	
  # '2018a' WRFENV modules requried by WRF and by PyWPS
  if [[ ${WRFENV} == '2018a' ]]; then
  
    # Load modules requried by WRF
    module load NiaEnv/2018a 
    module load intel/2018.2 
    module load intelmpi/2018.2 
    module load hdf5/1.8.20 
    module load netcdf/4.6.1  
    module load pnetcdf/1.9.0
           
    # Fix a potential problem with Anaconda's expected HDF version
    export HDF5_DISABLE_VERSION_CHECK=1 
    # NOTE: Anaconda has a different HDF5 version, so if we want to load 
    #   the Anaconda, we need this export. Otherwise a different HDF version 
    #   than expected can cause an error, even though it does not matter.
    
    # Load modules required by PyWPS    
    if [ $PYTHONVERSION -eq 2 ]; then module load python/2.7.14-anaconda5.1.0
    elif [ $PYTHONVERSION -eq 3 ]; then module load python/3.6.4-anaconda5.1.0
    else echo "Warning: Python Version '$PYTHONVERSION' not found."
    fi 
    
    # Print loaded python version
    python --version
    
    # Load ncl and source python env, if necessary
    if [[ ${RUNPYWPS} == 1 ]]; then      
      module load ncl/6.4.0
      source "${PYTHONENV}/bin/activate"
      # NOTE: PYTHONENV is a variable that needs to be set beforehand (possibly in user's
      #   .bashrc or .bash_profile). It contains the path to the folder of a virtual
      #   python environment that has netcdf4 and numexpr installed in it. These 
      #   modules are required within the averaging part of the code and are not
      #   accessible using simple python Niagara modules.    
    fi 
    # NOTE: NCL is only necessary for preprocessing CESM.
  
  # '2019b' WRFENV modules requried by WRF and by PyWPS  
  elif [[ ${WRFENV} == '2019b' ]]; then
  
    # Load modules requried by WRF
    module load NiaEnv/2019b 
    module load openjpeg/2.3.1 
    module load jasper/.experimental-2.0.14 
    module load intel/2019u4 
    module load intelmpi/2019u4 
    module load hdf5/1.8.21 
    module load netcdf/4.6.3
     
    # Load modules requried by PyWPS
    if [ $PYTHONVERSION -eq 2 ]; then module load python/2.7.15
    elif [ $PYTHONVERSION -eq 3 ]; then module load python/3.6.8
    else echo "Warning: Python Version '$PYTHONVERSION' not found."
    fi 
    
    # Print loaded python version
    echo
    echo -n "   Python Version = "
    python --version
    
    # Load ncl and source python env, if necessary
    if [[ ${RUNPYWPS} == 1 ]]; then      
      module load ncl/6.6.2
      source "${PYTHONENV}/bin/activate"
      # NOTE: PYTHONENV is a variable that needs to be set beforehand (possibly in user's
      #   .bashrc or .bash_profile). It contains the path to the folder of a virtual
      #   python environment that has netcdf4 and numexpr installed in it. These 
      #   modules are required within the averaging part of the code and are not
      #   accessible using simple python Niagara modules.
    fi 
    # NOTE: NCL is only necessary for preprocessing CESM.
  
  # If $WRFENV is something else  
  else echo "   Warning: WRF Environment Version '$WRFENV' not found."
  
  fi 
  
  # List loaded modules
  module list
  
  # Unlimit stack size 
  ulimit -s unlimited
  # NOTE: Unfortunately, this is necessary with WRF to prevent 
  #   segmentation faults.
  
  # Set the functions that are used in CMIP5 cases
  # TODO: Wrapper code for the following functions may have to be added
  #   (see GPC-file for examples): ncks, cdo, cdb_query_6hr, cdb_query_day,
  #   cdb_query_month.
    
fi 

# Set python path for pyWPS.py and cycling.py
if [ -e "${CODE_ROOT}/WRF Tools/Python/" ]; then export PYTHONPATH="${CODE_ROOT}/WRF Tools/Python:${PYTHONPATH}";
# NOTE: "-e" above returns true if the target exists. Doesn't matter if it's a file, pipe, 
#   special device, whatever. The only condition where something may exist, and -e will 
#   return false is in the case of a broken symlink.
elif [ -e "${CODE_ROOT}/WRF-Tools/Python/" ]; then export PYTHONPATH="${CODE_ROOT}/WRF-Tools/Python:${PYTHONPATH}"; fi
# Why do we add the path at the end of the variable itself (${PYTHONPATH}), 
#   rather than just defining it? Because we want to add to the python path (not replace it).

# Add Geopy to PYTHONPATH
if [ -e "${CODE_ROOT}/GeoPy/src/" ]; then export PYTHONPATH="${CODE_ROOT}/GeoPy/src:${PYTHONPATH}"; fi
# NOTE: wrfout_average.py depends on some modules from GeoPy (nctools and processing).

# Display python path
echo "   PYTHONPATH: $PYTHONPATH"
echo

# RAM-disk settings if we run PyWPS and real.exe
if [[ ${RUNPYWPS} == 1 ]] && [[ ${RUNREAL} == 1 ]]
then

  # Extract the memory amount using "free" command, and display it 
  RAMGB=$(( $(free | grep 'Mem:' | awk '{print $2}') / 1024**2 ))
  echo "   Detected ${RAMGB} GB of Memory."
  
  # Assign RAMIN and RAMOUT defaults based on RAM amount
  if [ $RAMGB -gt 90 ]; then      
    export RAMIN=${RAMIN:-1}
    export RAMOUT=${RAMOUT:-1}
  else
    export RAMIN=${RAMIN:-1}
    export RAMOUT=${RAMOUT:-0}
  fi 
  # NOTE: Apparently Niagara nodes have 93GB, but that should be enough.
  # NOTE: Don't use hyperthreading for WPS.
   
# RAM-disk settings in other situations
else

  # Assign zero RAMIN and RAMOUT defaults
  export RAMIN=${RAMIN:-0}
  export RAMOUT=${RAMOUT:-0}

fi 

# Display RAMIN and RAMOUT
echo "   Set RAMIN=${RAMIN} and RAMOUT=${RAMOUT}."

# RAM disk folder
export RAMDISK="/dev/shm/${USER}/"

# If needed, check if the RAM-disk is actually there
if [[ ${RAMIN}==1 ]] || [[ ${RAMOUT}==1 ]]; then    
    mkdir -p "${RAMDISK}" # Try creating RAM-disk directory.    
    if [[ $? != 0 ]]; then # Report any problems.
    # NOTE: "$?" is the exit status of the last executed command.
      echo
      echo "   WARNING: RAM-disk at RAMDISK=${RAMDISK} - folder does not exist! "
      echo
    fi 
fi 
	
# cp command flag to prevent overwriting existing content
export NOCLOBBER='-n'
# NOTE: "-n" above means do not overwrite an existing file.

# Set up hybrid envionment: OpenMP and MPI (Intel)
export NODES=${NODES:-${SLURM_JOB_NUM_NODES}} 
export TASKS=${TASKS:-40} # Number of MPI tasks per node.
# NOTE: Using TASKS we can enable hyperthreading.
export THREADS=${THREADS:-1} # Number of OpenMP threads.
export I_MPI_DEBUG=1 # Less output (currently no problems).
export HYBRIDRUN=${HYBRIDRUN:-'mpirun -ppn ${TASKS} -np $((NODES*TASKS))'} # Intel hybrid (mpi/openmp) job launch command.
# NOTE: HYBRIDRUN is evaluated by execWRF and execWPS.

# Geogrid command (executed during machine-independent setup)
export GEOTASKS=${GEOTASKS:-4} 
export RUNGEO=${RUNGEO:-"mpirun -n ${GEOTASKS} ${BINDIR}/geogrid.exe"}
# NOTE: The code runs geogrid with 4 processes by default. This is fine for smaller 
#   domains, but we may need to change this to use more processes for larger domains.
#   This may be done in xconfig.sh. 

# WPS/preprocessing submission command (for next step)
export SUBMITWPS=${SUBMITWPS:-'ssh -o LogLevel=quiet nia-login07 "cd \"${INIDIR}\"; sbatch --export=NEXTSTEP=${NEXTSTEP} ./${WPSSCRIPT}"'} # Evaluated by launchPreP.
# NOTE: This is a "here document"; variable substitution should happen at the eval stage.
# NOTE: When this code was written, you could not submit jobs from the compute nodes (that
#   may have been changed by now). That is why we ssh into nia-login07 above. The reason
#   why we choose nia-login07 node, is because according to SciNet this one sees the least 
#   traffic.
# NOTE: "-o LogLevel=quiet" above is to get rid of extra messages that ssh may display.

# Stay on compute node until WPS for next step is finished, in order to submit next WRF job
export WAITFORWPS=${WAITFORWPS:-'NO'} 

# Archive submission command (for last step in the interval)
export SUBMITAR=${SUBMITAR:-'ssh -o LogLevel=quiet nia-login07 "cd \"${INIDIR}\"; sbatch --export=TAGS=${ARTAG},MODE=BACKUP,INTERVAL=${ARINTERVAL} ./${ARSCRIPT}"'} # Evaluated by launchPostP.
# NOTE: This requires $ARTAG to be set in the launch script. 
# NOTE: If HPSS is not working or full, use below command to log archive backlog.
# export SUBMITAR=${SUBMITAR:-'ssh nia-login07 "cd \"${INIDIR}\"; echo \"${ARTAG}\" >> HPSS_backlog.txt"; echo "Logging archive tag \"${ARTAG}\" in 'HPSS_backlog.txt' for later archiving."'} # Evaluated by launchPostP.
# NOTE: About above script: Instead of archiving, just log the year to be archived; this is temporarily necessary, because HPSS is full.

# Averaging submission command (for last step in the interval)
export SUBMITAVG=${SUBMITAVG:-'ssh -o LogLevel=quiet nia-login07 "cd \"${INIDIR}\"; sbatch --export=PERIOD=${AVGTAG} ./${AVGSCRIPT}"'} # Evaluated by launchPostP.
# NOTE: This requires $AVGTAG to be set in the launch script.

# Job submission command (for next step)
export RESUBJOB=${RESUBJOB-'ssh -o LogLevel=quiet nia-login07 "cd \"${INIDIR}\"; sbatch --export=NOWPS=${NOWPS},NEXTSTEP=${NEXTSTEP},RSTCNT=${RSTCNT} ./${WRFSCRIPT}"'} # Evaluated by resubJob.

# Sleeper job submission (for next step when WPS is delayed)
export SLEEPERJOB=${SLEEPERJOB-'ssh -o LogLevel=quiet nia-login07 "cd \"${INIDIR}\"; nohup ./${STARTSCRIPT} --skipwps --restart=${NEXTSTEP} --name=${JOBNAME} &> ${STARTSCRIPT%.sh}_${JOBNAME}_${NEXTSTEP}.log &"'} # Evaluated by resubJob; relaunches WPS.
# NOTE: ${variable%A} notation means take the value of $variable, strip off the pattern A from the tail of the value and give the result.










