
# ==============================================================================
# === A short script to write namelists for cycling/resubmitting WRF runs.   ===
# === The script reads an environment argument that indicates the current    ===
# === step, reads the parameters for the next step, writes the new WPS       ===
# === and WRF namelists with the new parameters, based on templates, and     ===
# === returns the new step name.                                             ===
# ===                                                                        ===
# === Created on 2012-07-06.                                                 ===
# ===                                                                        ===
# === Author: Andre R. Erler                                                 ===
# ==============================================================================


# =================================================================================
# =================================== Imports =====================================
# =================================================================================

# System modules
import os # Directory operations.
import fileinput # Reading and writing config files.
import shutil # File operations.
import sys # Writing to stdout.
import datetime # To compute run time.
import calendar # To locate leap years.

# Andre's modules
import wrfrun.namelist_time as nlt


# =================================================================================
# ==================================== Setup ======================================
# =================================================================================

# Pass current/last step name as argument
if len(sys.argv) == 1:
  currentstep = '' 
  # NOTE: In this case, the code just returns first step.
elif len(sys.argv) == 2:
  currentstep = sys.argv[1]
  lcurrent = False 
  # NOTE: The above assumes input was the previous step.
elif len(sys.argv) == 3 : 
  currentstep = sys.argv[2]
  if sys.argv[1].lower() == 'last': lcurrent = False # Process next step.
  elif sys.argv[1].lower() == 'next': lcurrent = True # Process input step.
  else: raise ValueError("First argument has to be 'last' or 'next'.")
else: raise ValueError("Only two arguments are supported.")

# Environment variables
if 'STEPFILE' in os.environ:
  stepfile = os.environ['STEPFILE'] # Name of file with step listing.
else: stepfile = 'stepfile' # Default name.
if 'INIDIR' in os.environ:
  IniDir = os.environ['INIDIR'] # Where the step file is found.
else: IniDir = os.getcwd() + '/' # Current directory.
if os.environ['LLEAP'] == 'LLEAP':
  lly = True
else:
  lly = False  
if 'RSTINT' in os.environ:
  rstint = int(os.environ['RSTINT']) # Number of restart files per step.
else: rstint = 1
nmlstwps = 'namelist.wps' # WPS namelist file.
nmlstwrf = 'namelist.input' # WRF namelist file.


# =================================================================================
# =============================== Start execution =================================
# =================================================================================
 
if __name__ == '__main__':

  # Open step file
  filehandle = fileinput.FileInput([IniDir + '/' + stepfile]) 
  
  # Initialize stepline 
  stepline = -1 
  # NOTE: -1 is flag for last step not found.
  
  # If currentstep is set
  if currentstep:
    
    # Scan for current/last step 
    for line in filehandle:
      
      # If stepline == -1, find stepline   
      if (stepline == -1) and (currentstep in line.split()[0]):
      # NOTE: split() above splits a string into a list where each word is a list item.  
        if lcurrent: stepline = filehandle.filelineno()
        # NOTE: filelineno() returns its line number in the current file.
        else: stepline = filehandle.filelineno() + 1
      
      # Read line with current step
      if stepline == filehandle.filelineno(): linesplit = line.split()
    
    # Check against end of file
    if stepline > filehandle.filelineno():
      stepline = 0 # Flag for last step (end of file).
      
  # Otherwise read first line
  else:
  
    stepline = 1
    linesplit = filehandle[0].split()
  
  # Close file
  fileinput.close()
        
  # Set up next step (if no next step)   
  if stepline <= 0:
  
    # Reached end of file 
    if stepline == 0: 
      
      sys.stdout.write('')
      sys.exit(0)
    
    # Last/current step not found
    elif stepline == -1:
      
      sys.exit(currentstep+' not found in '+stepfile)
    
    # Unknown error
    else:
      
      sys.exit(127)
  
  # Set up next step (if there is a next step) 
  else:
  
    # Extract information
    nextstep = linesplit[0] # Next step name.
    startdatestr = linesplit[1] # Next start date.
    startdate = nlt.splitDateWRF(startdatestr[1:-1])
    enddatestr = linesplit[2] # Next end date.
    enddate = nlt.splitDateWRF(enddatestr[1:-1])
    
    # Screen for leap days 
    if lly == False: # If we don't use leap-years in WRF.
      if calendar.isleap(startdate[0]) and startdate[2]==29 and startdate[1]==2:
        startdate = (startdate[0], startdate[1], 28, startdate[3])
      if calendar.isleap(enddate[0]) and enddate[2]==29 and enddate[1]==2:
        enddate = (enddate[0], enddate[1], 28, enddate[3])
    # NOTE: The above treats Feb. 29th as 28th.
    # I think here we may end up with two 28ths in the results, but according to
    #   Andre, if we do monthly steps, this would not be an issue; this is only
    #   an issue if we do daily or sub-daily steps. I do not see this. ?????
    
    # Create next step folder
    StepFolder = IniDir + '/' + nextstep + '/'
    if not os.path.isdir(StepFolder):                    
      os.mkdir(StepFolder)  
    
    # Copy namelist templates  
    shutil.copy(IniDir+'/'+nmlstwps, StepFolder)
    shutil.copy(IniDir+'/'+nmlstwrf, StepFolder)
  
    # Print next step name to stdout
    sys.stdout.write(nextstep)
    
    # Determine number of domains
    filehandle = fileinput.FileInput([StepFolder+nmlstwps]) 
    for line in filehandle: 
      if 'max_dom' in line: 
        maxdom = int(line.split()[2].strip(','))
        # NOTE: In python "strip(CHARS)", removes CHARS from the string beginning/end.
        break 
    fileinput.close()    

    # =========================== WPS namelist ===========================
    # Construct date strings
    startstr = ' start_date = '; endstr = ' end_date   = '
    for i in range(maxdom):
    # NOTE: range(x) gives 0,1,2,...,X-1.
      startstr = startstr + startdatestr + ','
      endstr = endstr + enddatestr + ','
    startstr = startstr + '\n'; endstr = endstr + '\n'
    # Modify namelist to include the correct dates 
    filehandle = fileinput.FileInput([StepFolder+nmlstwps], inplace=True)
    lstart = False; lend = False    
    for line in filehandle:       
      if 'start_date' in line:
        if not lstart:          
          sys.stdout.write(startstr)
          lstart = True 
          # NOTE: If start date already written, and we find another one, this
          #   omits that extra line.             
      elif 'end_date' in line:
        if not lend:          
          sys.stdout.write(endstr)
          lend = True 
          # NOTE: If end date already written, and we find another one, this
          #   omits that extra line.
      else:        
        sys.stdout.write(line) # Otherwise write (repeat) original file contents.    
    fileinput.close()
    
    # =========================== WRF namelist ===========================
    # Compute run time
    startdt = datetime.datetime(year=startdate[0], month=startdate[1], day=startdate[2], hour=startdate[3])
    enddt = datetime.datetime(year=enddate[0], month=enddate[1], day=enddate[2], hour=enddate[3])
    rtdelta = enddt - startdt 
    # Handle leap days (if we don't want leap-years, we have to subtract the leap-days)
    leapdays = 0 # Counter for leap days in timedelta.
    if lly == False:       
      if (startdate[0] == enddate[0]) and calendar.isleap(enddate[0]):
        if (startdate[1] < 3) and (enddate[1] > 2):
          leapdays += 1 
        # NOTE: This only counts days if timedelta crosses leap day.  
      else:
        if calendar.isleap(startdate[0]) and (startdate[1] < 3):
          leapdays += 1 
        leapdays += calendar.leapdays(startdate[0]+1, enddate[0])
        if calendar.isleap(enddate[0]) and (enddate[1] > 2):
          leapdays += 1 
    # Figure out actual duration in days, hours, minutes and seconds
    rtdays = rtdelta.days - leapdays
    rtmins, rtsecs = divmod(rtdelta.seconds, 60)
    # NOTE: In the above ".seconds" has number of seconds less than number of days.
    # NOTE: divmod(X,Y) returns the quotient and the remainder of X/Y.
    rthours, rtmins = divmod(rtmins, 60)
    runtime = (rtdays, rthours, rtmins, rtsecs)
    # Make restart interval an integer fraction of run time
    runmins = rtdays*1440 + rthours*60 + rtmins 
    rstmins = int(runmins/rstint)
    if rstmins*rstint != runmins: raise ValueError("Runtime is not an integer multiple of the restart interval (RSTINT={:d})!".format(rstint)) 
    # Make restart string
    rststr = ' restart_interval = '+str(rstmins)+',\n'
    # Construct run time strings
    timecats = ('days', 'hours', 'minutes', 'seconds')
    ltc = len(timecats); runcats = ['',]*ltc
    for i in range(ltc):
      runcats[i] = ' run_'+timecats[i]+' = '+str(runtime[i])+',\n'
    # Construct date strings
    datecats = ('year', 'month', 'day', 'hour')
    ldc = len(datecats); startcats = ['',]*ldc; endcats = ['',]*ldc
    for i in range(ldc): 
      startcat = ' start_'+datecats[i]+' ='; endcat = ' end_'+datecats[i]+'   ='
      for j in range(maxdom):
        startcat = startcat + ' ' + str(startdate[i]) + ','
        endcat = endcat + ' ' + str(enddate[i]) + ','
      startcats[i] = startcat + '\n'; endcats[i] = endcat + '\n'
    # Modify namelist to include the correct dates, etc
    filehandle = fileinput.FileInput([StepFolder+nmlstwrf], inplace=True)
    for line in filehandle: 
      if ' run_' in line:
        for runcat, timecat in zip(runcats, timecats):
          if timecat in line:             
            sys.stdout.write(runcat)
      elif ' restart_interval' in line:
        sys.stdout.write(rststr)
      elif ' start_' in line:
        for startcat, datecat in zip(startcats, datecats):
          if datecat in line:             
            sys.stdout.write(startcat)    
      elif ' end_' in line:
        for endcat, datecat in zip(endcats, datecats):
          if datecat in line:             
            sys.stdout.write(endcat)
      else:
        sys.stdout.write(line) # Otherwise write (repeat) original file contents.
    fileinput.close() 
    
    
    
    
    
    
    
    
    
    
    
