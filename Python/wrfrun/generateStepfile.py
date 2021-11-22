#! /usr/bin/env python

# Python script to generate a valid stepfile for WRF cycling. 


# Import modules
import sys
import pandas
import calendar

# Default arguments
filename = 'stepfile' # Default filename.
lleap = True # Allow leap days.
# NOTE: Some GCM calendars do not use leap days.
dateargs = [] # List of date arguments passed to pandas date_range.
lecho = False # If true, just print results on screen (not into file).
lperiod = False # If true, we specify begin date, number of steps and
                #   frequency (otherwise we have to specify begin and 
                #   end dates and frequency). 

# Arguments passed onto this file run
# NOTE: sys.argv[0] is the name of the script.
for arg in sys.argv[1:]:
  # Interval argument
  if arg[:11] == '--interval=':
    freq = arg[11:].lower() 
    # NOTE: The string lower() method returns a string where all characters are lower case.
    # NOTE: Variable freq remains a string and is interpreted by date_range.
  # Steps argument 
  elif arg[:8] == '--steps=':
    lperiod = True; periods = int(arg[8:]) + 1 
    # NOTE: The int() function converts the specified value into an integer number.
    #   If the input has decimal places, it works by removing the numbers after the
    #   dot (it does not round).
    # NOTE: steps is number of intervals and periods is number of dates generated.
    # NOTE: Each step is bounded by two timestamps.
  # If applicable, remove leap days
  elif arg == '-l' or arg == '--noleap': 
    lleap = False 
    # NOTE: We sometimes omit leap days to accomodate some GCM calendars.
  # If applicable, print steps to stdout instead of writing to stepfile
  elif arg == '-e' or arg == '--echo': 
    lecho = True
  # Help argument
  elif arg == '-h' or arg == '--help':
    print('')
    print("Usage: "+sys.argv[0]+" [-e] [-h] [--interval=interval] [--steps=steps] begin-date [end-date]")
    print("       Interval, begin-date and end-date or steps must be specified.")
    print("")
    print("  --interval=    step spacing / interval (D=days, W=weeks, M=months)")
    print("  --steps=       number of steps in stepfile")
    print("  -l | --noleap  omit leap days (to accomodate some GCM calendars)")
    print("  -e | --echo    print steps to stdout instead of writing to stepfile")
    print("  -h | --help    print this message")
    print('')
    sys.exit(1)    
    # NOTE: sys.exit(arg) terminates the run. arg is an optional argument and if it is an 
    #   integer, zero is considered “successful termination” and any nonzero value is 
    #   considered “abnormal termination” by shells and the like.
  # Date arguments
  else: 
    dateargs.append(arg)
    
# Output patterns
dateform = '%Y-%m-%d_%H:%M:%S'
stepform = '%Y-%m-%d'
lmonthly = False # If frequency is monthly (adjusted below). 
offset = pandas.DateOffset() # No offset (adjusted below).

# Make pattern adjustments, for weekly frequency
if 'w' in freq:
  oo = 1 if '-sun' in freq else 0
  # NOTE: "value_when_true if condition else value_when_false" is an acceptable IF 
  #   statement in python.
  offset = pandas.DateOffset(days=pandas.to_datetime(dateargs[0]).dayofweek + oo) 
  # Why use offset for weekly cases and what is oo? ?????
  # NOTE: "dayofweek" above returns the day of the week with Monday=0, ..., Sunday=6.
  # NOTE: "DateOffset" has a temporal parameter that adds to the offset value (e.g. 
  #   years, months, weeks, days, hours, etc.). The offset is applied to the dates.
# Make pattern adjustments, for monthly frequency
elif 'm' in freq: 
  lmonthly = True
  stepform = '%Y-%m'
  offset = pandas.DateOffset(days=pandas.to_datetime(dateargs[0]).day) 
# NOTE: Because the pandas date_range always anchors intervals at the end of the month,
#   (meaning that if the frequency is 1 month, it adds number of days equal to the number of
#   days of the month to find the next date), we have to subtract days and add it again later, 
#   in order to get the same day of the month.

# Make begin date in pandas
begindate = pandas.to_datetime(dateargs[0]) - offset 

# Check input and generate datelist
if lperiod:
  if len(dateargs) != 1: raise ValueError('Can only specify begin-date, if the number of periods is given.')
  datelist = pandas.date_range(begindate, periods=periods, freq=freq) 
else:
  if len(dateargs) != 2: raise ValueError('Specify begin-date and end-date, if no number of periods is given.')
  enddate = pandas.to_datetime(dateargs[1]) - offset
  datelist = pandas.date_range(begindate, enddate, freq=freq) 

# Open file, if not writing to stdout
if not lecho: stepfile = open(filename, mode='w')

# Initialize lastdate and llastleap
lastdate = datelist[0] + offset
# NOTE: Last here means previous.
# NOTE: Offset is not the interval/frequency; it is an offset at the 
#   beginning of the week or month. 
llastleap = False
# What if lastdate IS a leapday? ?????

# Iterate over dates and make step file entries
for date in datelist[1:]:
  currentdate = date + offset
  lcurrleap = False
  # Take care of the case, when offset is larger than current month's number of days    
  if lmonthly:
    mon = date.month + 1 
    if mon == 2: maxdays = 29 if calendar.isleap(date.year) else 28  
    elif mon in [4, 6, 9, 11]: maxdays = 30
    else: maxdays = 31
    if currentdate > date + pandas.DateOffset(days=maxdays): 
      currentdate = date + pandas.DateOffset(days=maxdays)
  # Handle calendars without leap days (turn Feb. 29th into Mar. 1st)
  if not lleap and calendar.isleap(currentdate.year) and ( currentdate.month==2 and currentdate.day==29 ):
    lcurrleap = True
    currentdate += pandas.DateOffset(days=1)     
  # Generate line for last step
  if lleap or not (freq.lower()=='1d' and llastleap): 
    # NOTE: The if above is so that we skip if we have a non-leap calendar (lleap=FALSE)  
    #   and this is daily output and we have a leap last day. 
    stepline = "{0:s}   '{1:s}'  '{2:s}'\n".format(lastdate.strftime(stepform),lastdate.strftime(dateform),
                                                   currentdate.strftime(dateform))
    # Write to appropriate output 
    if lecho: sys.stdout.write(stepline)
    else: stepfile.write(stepline)
  # Remember last step
  lastdate = currentdate
  llastleap = lcurrleap

# Close file, if applicable
if not lecho: stepfile.close()









