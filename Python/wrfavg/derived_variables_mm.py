
'''
Created on 2013-10-01, revised 2014-05-20.

A module defining a base class and some instances, which provide a mechanism to add derived/secondary variables
to WRF monthly means generated with the wrfout_average module. The DerivedVariable instances are imported by 
wrfout_average and its methods are executed at the appropriate points during the averaging process.   

@Author: Andre R. Erler.
'''


# ====================================== Imports ===========================================

# Import required standard modules
import netCDF4 as nc
import numpy as np
from scipy.integrate import simps # Simpson rule for integration.
import calendar
from datetime import datetime
from numexpr import evaluate, set_num_threads, set_vml_num_threads

# Import Andre's own netcdf stuff
from utils.nctools import add_var


# ================================ Some prerequisites ======================================

# Set the numbers of threads
set_num_threads(1); set_vml_num_threads(1)
# NOTE: For numexpr parallelisation: Don't parallelize at this point!

# Days per month without leap days (duplicate from datasets.common) 
days_per_month_365 = np.array([31,28,31,30,31,30,31,31,30,31,30,31])
# NOTE: Importing from datasets.common causes problems with GDAL, if it is not installed.

# Final precision used for derived floating point variables
dv_float = np.dtype('float32')  

# General floating point precision used for temporary arrays
dtype_float = dv_float 


# ===================================== Functions ==========================================

def getTimeStamp(dataset, idx, timestamp_var='Times'):
  ''' Read a timestamp and convert to pandas-readable format '''
  # Read timestamp
  timestamp = str(nc.chartostring(dataset.variables[timestamp_var][idx,:]))
  # NOTE: netCDF does not have a fixed-length string data-type (only characters and variable length 
  #   strings). The convenience function chartostring converts an array of characters to an array 
  #   of fixed-length strings. The array of fixed length strings has one less dimension, and the
  #   length of the strings is equal to the rightmost dimension of the array of characters. The 
  #   convenience function stringtochar goes the other way, converting an array of fixed-length 
  #   strings to an array of characters with an extra dimension (the number of characters per string) 
  #   appended on the right.
  # Remove underscore
  timestamp = timestamp.split('_') 
  # NOTE: The split method splits a string into sub-strings with the seperator as an optional argument. 
  assert len(timestamp)==2, timestamp  
  # NOTE: The assert statement is used to continue the execute if the given condition evaluates to True. If 
  #   the assert condition evaluates to False, then it raises the AssertionError exception with the specified 
  #   error message (that appears after the comma).
  timestamp = ' '.join(timestamp)
  # NOTE: The join method combines all the elements of its argument into one string with the string before  
  #   the dot as the joining element between different argument elements.
  return timestamp

def calcTimeDelta(timestamps, year=None, month=None):
  ''' Function to calculate time deltas and subtract leap-days, if necessary '''
  # Calculate first and last date data 
  y1, m1, d1 = tuple( int(i) for i in timestamps[0][:10].split('-') )
  y2, m2, d2 = tuple( int(i) for i in timestamps[-1][:10].split('-') )
  # The first timestamp has to be of this year and month, last can be one ahead
  if year is None: year = y1 
  else: assert year == y1
  assert ( year == y2 or year+1 == y2 )
  if month is None: month = m1 
  else: assert month == m1 
  assert  ( month == m2 or np.mod(month,12)+1 == m2 )                
  # Determine the interval                
  dt1 = datetime.strptime(timestamps[0], '%Y-%m-%d_%H:%M:%S')
  dt2 = datetime.strptime(timestamps[-1], '%Y-%m-%d_%H:%M:%S')
  # NOTE: The strptime() class method takes two arguments: string (that'll be converted to datetime) and 
  #   format code. Based on the string and format code used, the method returns its equivalent datetime object.  
  delta = float( (dt2-dt1).total_seconds() ) 
  # NOTE: The difference creates a timedelta object.
  # Determine number of time stamps
  n = len(timestamps)
  # Check if leap-day is present and whether to subtract the leap day
  if month == 2 and calendar.isleap(year):
    ld = datetime(year, 2, 29) # Datetime of leap day                   
    if ( d1 == 29 or  d2 == 29 ): # Trivial case; will be handled correctly by datetime.
      lsubld = False  
    elif dt1 < ld < dt2: # A leap day should be there; if not, then subtract it.      
      ild = int( ( n - 1 ) * float( ( ld - dt1 ).total_seconds() ) / delta ) # Index of leap-day.
      lsubld = True # Subtract, unless leap day is found, sicne it should be there.
      while lsubld and ild < n: # Search through timestamps for leap day.
        yy, mm, dd = tuple( int(i) for i in timestamps[ild][:10].split('-') )
        if mm == 3: break
        assert yy == year and mm == 2        
        if dd == 29: lsubld = False # Check if a leap day is present (if yes, then don't subtract).
        ild += 1 # Increment leap day search.
    else: 
      lsubld = False # No leap day in interval, no need to correct period. 
    if lsubld: delta -= 86400. # Subtract leap day from period. 
  # Return leap-day-checked period
  return delta
              
def ctrDiff(data, axis=0, delta=1):
  ''' Helper routine to compute central differences.
      NOTE: Due to the roll operation, this function is not fully thread-safe. '''
  # Check the input data types
  if not isinstance(data,np.ndarray): raise TypeError
  if not isinstance(delta,(float,np.inexact,int,np.integer)): raise TypeError
  if not isinstance(axis,(int,np.integer)): raise TypeError
  # If axis is not 0, roll axis until it is
  if axis != 0: data = np.rollaxis(data, axis=axis, start=0) 
  # NOTE: numpy.rollaxis(a, axis, start=0) rolls the specified axis backwards, until it lies in 
  #   a given position. The other axes are not changed, e.g., if a = np.ones((3,4,5,6)), then
  #   np.rollaxis(a, 2).shape is (5, 3, 4, 6). The start is 0 by default.
  # NOTE: This changes original - we need to undo it later.
  # Allocate array to prepare for calculation
  outdata = np.zeros_like(data, dtype=dtype_float)              
  # NOTE: numpy.zeros_like(a, dtype=None) returns an array of zeros with the same shape and type
  #   as a given array. The argument dtype overrides the data type of the result.  
  # Compute centered differences, except at the edges, where forward/backward difference are used
  outdata[1:,:] = np.diff(data, n=1, axis=0) 
  outdata[0:-1,:] += outdata[1:,:]
  # NOTE: numpy.diff(a, n=1, axis=-1) calculates the n-th discrete difference along the given axis.
  #   The first difference is given by out[i] = a[i+1] - a[i] along the given axis, higher differences 
  #   are calculated by using diff recursively. Axis default is the last axes (-1).    
  if delta == 1:
    outdata[1:-1,:] /= 2. # Normalize, except at boundaries.
  else:
    outdata[1:-1,:] /= (2.*delta) # Normalize (including "dx"), except at boundaries.
    outdata[[0,-1],:] /= delta # Apply the denominator "dx" at boundaries.      
  # Roll axis back to original position and return
  if axis != 0: outdata = np.rollaxis(outdata, axis=0, start=axis+1) 
  # NOTE: When start > axis, the axis is rolled until it lies before this position.
  return outdata

def pressureIntegral(var, T, p, RMg):
  ''' Helper routine to compute mass-weighted vertical integrals 
      (currently only works on pressure levels). '''
  # Make sure dimensions fit (pressure is the second dimension)
  assert T.ndim == 4 and p.ndim == 2 
  assert T.shape[:2] == p.shape 
  # Allocate extended array with boundary points (first and last plevs are just boundary conditions)
  tmpshape = list(T.shape)
  tmpshape[1] += 2 # Add two levels (integral boundaries).
  tmpdata = np.zeros(tmpshape, dtype=dv_float)
  # Make sure pressure is monotonically decreasing
  assert np.all( np.diff(p[0,:]) < 0 ), 'The pressure axis has to decrease monotonically.'    
  # Make extended plev axis
  pax = np.zeros((tmpshape[1],), dtype=dv_float)
  # NOTE: This gives a vector of length tmpshape[1]. 
  pax[1:-1] = p[0,:]; pax[0] = 1.e5; pax[-1] = 0. # We put boundary conditions at the ends.
  pax = -1 * pax # Invert, since we are integrating in the wrong direction.
  # Make p into a 4D array       
  p = p.reshape(p.shape+(1,1)) 
  # NOTE: This adds two singleton dimensions (for y,x), so we can broadcast against 3/4D fields.
  # Fill missing values and NaNs to allow integration
  var = np.nan_to_num(var); T = np.nan_to_num(T)
  # NOTE: np.nan_to_num replaces NaN with zero and infinity with large finite numbers. 
  # Compute weighted flux at each (non-boundary) level
  tmpdata[:,1:-1,:] = evaluate('RMg * var * T / p') # First and last are zero (see above).
  # NOTE: The 0 boundary conditions is an approximation (fixing it would be too difficult and 
  #   not worth the effort).
  # NOTE: RMg is R/(M*g).
  # Integrate using Simpson's rule
  outdata = simps(tmpdata, pax, axis=1, even='first') 
  # NOTE: simps(y, x, axis=-1, even='avg') integrates y(x) using samples along the given axis and
  #   the composite Simpson’s rule. If there are an even number of samples, N, then there are an 
  #   odd number of intervals (N-1), but Simpson’s rule requires an even number of intervals. The 
  #   parameter ‘even’ controls how this is handled. When even='first', it uses Simpson’s rule for
  #   the first N-2 intervals with a trapezoidal rule on the last interval.   
  return outdata


# ================================ Class for errors with derived variables ======================================

class DerivedVariableError(Exception):
  ''' Exceptions related to derived variables. '''
  pass
  # NOTE: In Python programming, the pass statement is a null statement. The difference between a 
  #   comment and a pass statement in Python is that while the interpreter ignores a comment entirely, 
  #   pass is not ignored. However, nothing happens when the pass is executed. It results in no 
  #   operation (NOP).


# NOTE: This could have been implemented much more efficiently, without the need for separate classes,
#   using a numexpr string and the variable dicts to define the computation.
 

# ====================================== Derived variable base class ============================================

class DerivedVariable(object):
  '''
    Instances of this class are imported by wrfout_average; it defines methods that the averaging script uses,
    to create the NetCDF variable and compute the values for a given derived variable.
    This is the base class and variable creation etc. is defined here.
    Computation of the values has to be defined in the appropriate child classes, as it depends on the variable.
  '''

  def __init__(self, name=None, units=None, prerequisites=None, constants=None, axes=None, 
               dtype=None, atts=None, linear=False, ignoreNaN=False, normalize=True):
    ''' Create an instance of the class, to be imported by wrfout_average. '''
    # Set general attributes
    self.prerequisites = prerequisites # A list of variables that this variable depends upon. 
    self.constants = constants # Similar list of constant fields necessary for computation.
    self.linear = linear # Only linear computation are supported, i.e. they can be performed after averaging (default=False).
    self.normalize = normalize # Whether or not to divide by number of records after aggregation (default=True).
    self.ignoreNaN = ignoreNaN # Use NaN-safe aggregation or not (i.e. ignore NaN's in sums etc.).
    self.checked = False # Indicates whether prerequisites were checked.
    self.tmpdata = None # Handle for temporary storage.
    self.carryover = False # Carry over temporary storage to next month.
    # Set NetCDF attributes
    self.axes = axes # Dimensions of NetCDF variable. 
    self.dtype = dtype # Data type of NetCDF variable.
    self.atts = atts # Attributes; mainly used as NetCDF attributes.
    # Infer more attributes
    self.atts = atts or dict()
    if name is not None: 
      self.atts['name'] = self.name = name # Name of the variable, also used as the NetCDF variable name.
    else: self.name = atts['name']
    if units is not None:    
      self.atts['units'] = self.units = units # Like the name arrangement above. 
    else: self.units = atts['units']
    
  def checkPrerequisites(self, target, const=None, varmap=None):
    ''' Check if all required variables are in the source NetCDF dataset. '''
    # Check variable types
    if not isinstance(target, nc.Dataset): raise TypeError
    if not (const is None or isinstance(const, nc.Dataset)): raise TypeError
    if not (varmap is None or isinstance(varmap, dict)): raise TypeError
    check = True # Any mismatch will set this to False.
    # Check all prerequisites
    for var in self.prerequisites:
      if varmap: var = varmap.get(var,var)
      # NOTE: In dictionary.get(keyname, value), keyname is required and is the keyname of the item you want 
      #   to return the value from. value is optional and is a value to return if the specified key does not 
      #   exist. Default value is None.
      if var not in target.variables:        
        check = False # Prerequisite variable not found.
    # Check constants too
    if const is not None:
      for var in self.constants:
        if var not in const.variables:
          check = False # Prerequisite variable not found.
    # Update check value and return it
    self.checked = check 
    return check
  
  def createVariable(self, target):
    ''' Create a NetCDF Variable for this variable. '''
    # Check target type
    if not isinstance(target, nc.Dataset): raise TypeError    
    # Check if prerequisites are checked
    if not self.checked: 
      raise DerivedVariableError("Prerequisites for variable '%s' are not satisfied."%(self.name))
    # Create netcdf variable; some parameters were omitted (zlib, fillValue)
    ncvar = add_var(target, name=self.name, dims=self.axes, data=None, atts=self.atts, dtype=self.dtype)
    return ncvar
    
  def computeValues(self, indata, aggax=0, delta=None, const=None, tmp=None):
    ''' Compute values for new variable from existing stock; child classes have to overload this method. '''
    # NOTE: This method is called directly for linear variables and through aggregateValues() for 
    #   non-linear variables.
    # Check types
    if not isinstance(indata,dict): raise TypeError
    if not isinstance(aggax,(int,np.integer)): raise TypeError # The aggregation axis (needed for extrema). 
    if not (const is None or isinstance(const,dict)): raise TypeError # Dictionary of constant(s)/fields.
    if not (delta is None or isinstance(delta,(float,np.inexact))): raise TypeError # Output interval period. 
    # NOTE: The const dictionary makes pre-loaded constant fields available for computations. 
    # Check if prerequisites are checked
    if not self.checked: 
      raise DerivedVariableError("Prerequisites for variable '%s' are not satisfied."%(self.name))
    # If this variable requires constants, check that
    if self.constants is not None and len(self.constants) > 0: 
      if const is None or len(const) == 0: 
        raise ValueError('The variable \'{:s}\' requires a constants dictionary!'.format(self.name))
    return NotImplemented
    # NOTE: NotImplemented just means output is not inpimented.
  
  def aggregateValues(self, comdata, aggdata=None, aggax=0):
    ''' Compute and aggregate values for non-linear variables over several input periods/files. '''
    # NOTE: Linear variables can go through this chain as well, if it is a pre-requisite for non-linear variable.
    # Check variable types
    if not isinstance(comdata,np.ndarray): raise TypeError # Newly computed values.
    if not isinstance(aggax,(int,np.integer)): raise TypeError # The aggregation axis (needed for extrema).
    # The default implementation is just a simple sum that will be normalized to an average
    if comdata is not None and comdata.size > 0:
      if aggdata is None: 
        if self.normalize: raise DerivedVariableError('The one-pass aggregation automatically normalizes.')
        if self.ignoreNaN: aggdata = np.nanmean(comdata, axis=aggax) # Ignores NaN's.
        else: aggdata = np.mean(comdata, axis=aggax) # We don't use in-place addition, because it destroys masks.
      else:
        if not self.normalize: raise DerivedVariableError('The default aggregation requires normalization.')
        if not isinstance(aggdata,np.ndarray): raise TypeError # Aggregate variable.
        if self.ignoreNaN: aggdata = aggdata + np.nansum(comdata, axis=aggax) # Ignore NaN's.
        else: aggdata = aggdata + np.sum(comdata, axis=aggax) # We don't use in-place addition, because it destroys masks.
    # Return aggregated value for further treatment
    return aggdata 


# ==================================== Regular derived variables: Rain ==========================================  
  
class Rain(DerivedVariable):
  ''' DerivedVariable child implementing computation of total precipitation for WRF output. '''
  
  def __init__(self):
    ''' Initialize with fixed values; constructor takes no arguments. '''
    super(Rain,self).__init__(name='RAIN', # Name of the variable.
                              units='kg/m^2/s', # Not accumulated. 
                              prerequisites=['RAINNC', 'RAINC'], # It's the sum of these two. 
                              axes=('time','south_north','west_east'), # Dimensions of NetCDF variable. 
                              dtype=dv_float, atts=None, linear=True) 
    # NOTE: The super() builtin returns a proxy object (temporary object of the superclass) that allows 
    #   us to access methods of the base class. It allows us to avoid using the base class name explicitly.

  def computeValues(self, indata, aggax=0, delta=None, const=None, tmp=None, ignoreNaN=False):
    ''' Compute total precipitation as the sum of convective and non-convective precipitation. '''
    # NOTE: This computation is actually linear, but some non-linear computations depend on it.
    # Perform some checks
    super(Rain,self).computeValues(indata, aggax=aggax, delta=delta, const=const, tmp=tmp) 
    if delta == 0: raise ValueError('RAIN depends on accumulated variables; differences can not be computed from single time steps (delta=0).')    
    # Compute the result
    outdata = evaluate('RAINNC + RAINC', local_dict=indata) 
    # NOTE: The local_dict above means that the data are taken from the indata variable.
    return outdata


# ==================================== Regular derived variables: RainMean ==========================================

# NOTE: Some other DerivedVariable's depend on RAINMEAN, so we are keepign it for now.
class RainMean(DerivedVariable):
  ''' DerivedVariable child implementing computation of total daily precipitation for WRF output. '''
  
  def __init__(self):
    ''' Initialize with fixed values; constructor takes no arguments. '''
    super(RainMean,self).__init__(name='RAINMEAN', # Name of the variable.
                                  units='kg/m^2/s', # Not accumulated. 
                                  prerequisites=['RAINNCVMEAN', 'RAINCVMEAN'], # It's the sum of these two. 
                                  axes=('time','south_north','west_east'), # Dimensions of NetCDF variable. 
                                  dtype=dv_float, atts=None, linear=True) 
    
  def computeValues(self, indata, aggax=0, delta=None, const=None, tmp=None, ignoreNaN=False):
    ''' Compute total precipitation as the sum of convective and non-convective precipitation. '''
    # NOTE: This computation is actually linear, but some non-linear computations depend on it.
    # Perform some type checks
    super(RainMean,self).computeValues(indata, aggax=aggax, delta=delta, const=const, tmp=tmp)     
    # Compute the result
    outdata = indata['RAINNCVMEAN'] + indata['RAINCVMEAN'] 
    return outdata


# ==================================== Regular derived variables: TimeOfConvection ==========================================

class TimeOfConvection(DerivedVariable):
  ''' DerivedVariable child implementing computation of time of convection for WRF output. '''
  
  def __init__(self):
    ''' Initialize with fixed values; constructor takes no arguments. '''
    super(TimeOfConvection,self).__init__(name='TimeOfConvection', # Name of the variable.
                              units='s', # Units in wrfout are actually minutes.
                              prerequisites=['TRAINCVMAX', 'Times'],  
                              axes=('time','south_north','west_east'), # Dimensions of NetCDF variable. 
                              constants=['XLONG'], # Local longitudes.
                              dtype=dv_float, atts=None, linear=False, ignoreNaN=True) 
    self.time_offset = 0 # Shift clock 6 hours back, to avoid errors from averaging over midnight. ?????
    
  def computeValues(self, indata, aggax=0, delta=None, const=None, tmp=None, ignoreNaN=False):
    ''' Compute time of convection. '''
    # Perform some type checks
    super(TimeOfConvection,self).computeValues(indata, aggax=aggax, delta=delta, const=const, tmp=tmp)     
    # Get times and tcv and check the times' length
    times = indata['Times']; tcv = indata['TRAINCVMAX']
    assert len(times) == tcv.shape[0]
    # Longitude, to transform to local solar time
    if 'XLONG_360' not in const:
      xlon = const['XLONG']
      xlon = np.where(xlon < 0, 360.+xlon, xlon) # Avoid discontinuity at dateline.
      const['XLONG_360'] = xlon
    else: xlon = const['XLONG_360']
    # Save time of simulation start and its offset
    if 'TimeOfSimulationStart' not in const:       
      toss = datetime.strptime(times[0], '%Y-%m-%d_%H:%M:%S') # This is the first time step.
      # NOTE: The strptime() method creates a datetime object from the given string.
      if times[0][10:] !='_00:00:00': # 0-UTC correction, if ToSS is not 0 UTC. 
        dtoss = int( (toss - datetime.strptime(times[0][:10], '%Y-%m-%d')).total_seconds() //60 ) # In minutes.
      else: dtoss = 0
      dtoss += self.time_offset # Apply time offset.
      const['TimeOfSimulationStart'] = toss # Save value for later use.
      const['DeltaToSS'] = dtoss # Save value for later use. 
    else: 
      toss = const['TimeOfSimulationStart']
      dtoss = const['DeltaToSS']
    # Compute time delta to ToSS
    deltas = np.asarray([(datetime.strptime(time, '%Y-%m-%d_%H:%M:%S') - toss).total_seconds()//60 for time in times], dtype='int')
    deltas = deltas.reshape((len(deltas),1,1)) # Add singleton spatial dimensions for broadcasting.
    # NOTE: np.asarray converts the input to an array. 
    if not np.all( np.diff(deltas) == 1440 ):
      raise NotImplementedError('TimeOfConvection only works with daily output intervals!')
    deltas -= 1440 # Go back one day (convection happened during the previous day).
    # Isolate time of day and remove days that didn't rain
    tod = tcv - deltas
    tod = np.where(tod <= 0, np.NaN, tod) # NaN if no convection occurred.
    # Convert to local solar time
    tod += 4*xlon # xlon already has a (singleton) time dimension.
    # NOTE: Because there is 360 degrees around the earth, 1 degree longitude change is equal to 1/360*24*3600 s 
    #   or 240 s or 4 mins. xlon is in degrees, so to convert to minutes we multiply by 4. 
    # Apply correction for not starting at 0 UTC & time offset to avoid averaging errors
    if dtoss > 0: tod += dtoss 
    # Correct "overflows"; also necessary, because of time offset
    tod %= 1440  
    # NOTE: "x %= 3" is the same as "x = x % 3".
    # Return the result
    tod *= 60 # Convert to seconds.
    outdata = np.asarray(tod, dtype=dv_float) 
    return outdata

    
# ==================================== Regular derived variables: LiquidPrecip ==========================================

class LiquidPrecip(DerivedVariable):
  ''' DerivedVariable child implementing computation of liquid precipitation for WRF output. '''
  
  def __init__(self):
    ''' Initialize with fixed values; constructor takes no arguments. '''
    super(LiquidPrecip,self).__init__(name='LiquidPrecip', # Name of the variable.
                              units='kg/m^2/s', # Not accumulated. 
                              prerequisites=['RAINNC', 'RAINC', 'ACSNOW'], 
                              axes=('time','south_north','west_east'), # Dimensions of NetCDF variable. 
                              dtype=dv_float, atts=None, linear=True) 

  def computeValues(self, indata, aggax=0, delta=None, const=None, tmp=None, ignoreNaN=False):
    ''' Compute liquid precipitation as the difference between total and solid precipitation. '''
    # NOTE: This computation is actually linear.
    # Perform some type checks
    super(LiquidPrecip,self).computeValues(indata, aggax=aggax, delta=delta, const=const, tmp=tmp) 
    # Compute the result
    RAINNC = indata['RAINNC']; RAINC = indata['RAINC']; ACSNOW = indata['ACSNOW']; 
    outdata = evaluate('RAINNC + RAINC - ACSNOW') 
    return outdata


# ==================================== Regular derived variables: SolidPrecip ==========================================

class SolidPrecip(DerivedVariable):
  ''' DerivedVariable child implementing computation of solid precipitation for WRF output. '''
  
  def __init__(self):
    ''' Initialize with fixed values; constructor takes no arguments. '''
    super(SolidPrecip,self).__init__(name='SolidPrecip', # Name of the variable.
                              units='kg/m^2/s', # Not accumulated. 
                              prerequisites=['ACSNOW'], # It's identical to this field. 
                              axes=('time','south_north','west_east'), # Dimensions of NetCDF variable. 
                              dtype=dv_float, atts=None, linear=True) 

  def computeValues(self, indata, aggax=0, delta=None, const=None, tmp=None, ignoreNaN=False):
    ''' Just copy the snow accumulation as solid precipitation. '''
    # NOTE: This computation is actually linear.
    # Perform some type checks
    super(SolidPrecip,self).computeValues(indata, aggax=aggax, delta=delta, const=const, tmp=tmp) 
    # Compute the result
    outdata = indata['ACSNOW'].copy() 
    return outdata


# ==================================== Regular derived variables: LiquidPrecipSR ==========================================

class LiquidPrecipSR(DerivedVariable):
  ''' 
      DerivedVariable child implementing computation of liquid precipitation for WRF output. 
      SR means it is computed using total precip and the solid-to-liquid ratio, rather than the snowfall variable.
  '''
  
  def __init__(self):
    ''' Initialize with fixed values; constructor takes no arguments. '''
    super(LiquidPrecipSR,self).__init__(name='LiquidPrecip_SR', # Name of the variable.
                              units='kg/m^2/s', # Not accumulated. 
                              prerequisites=['RAIN', 'SR'],  
                              axes=('time','south_north','west_east'), # Dimensions of NetCDF variable. 
                              dtype=dv_float, atts=None, linear=False) 

  def computeValues(self, indata, aggax=0, delta=None, const=None, tmp=None, ignoreNaN=False):
    ''' Compute liquid precipitation from total precipitation and the solid fraction. '''
    # Perform some type checks
    super(LiquidPrecipSR,self).computeValues(indata, aggax=aggax, delta=delta, const=const, tmp=tmp) 
    # Get RAIN and SR
    RAIN = indata['RAIN']; SR = indata['SR'] 
    # Compute the result 
    if np.max(indata['SR']) > 1: outdata = evaluate('RAIN * ( 1 - SR / 2. )') 
    else: outdata = evaluate('RAIN * ( 1 - SR )') 
    # NOTE: Andre says SR seemed to vary between 0 and 2 (at least at the time he chekced this), therefore we should
    #   probably avoid using this (as we are unsure about it).
    return outdata


# ==================================== Regular derived variables: SolidPrecipSR ==========================================

class SolidPrecipSR(DerivedVariable):
  ''' 
      DerivedVariable child implementing computation of solid precipitation for WRF output. 
      SR means it is computed using total precip and the solid-to-liquid ratio, rather than the snowfall variable.
  '''
  
  def __init__(self):
    ''' Initialize with fixed values; constructor takes no arguments. '''
    super(SolidPrecipSR,self).__init__(name='SolidPrecip_SR', # Name of the variable.
                              units='kg/m^2/s', # Not accumulated. 
                              prerequisites=['RAIN', 'SR'],  
                              axes=('time','south_north','west_east'), # Dimensions of NetCDF variable. 
                              dtype=dv_float, atts=None, linear=False) 

  def computeValues(self, indata, aggax=0, delta=None, const=None, tmp=None, ignoreNaN=False):
    ''' Compute solid precipitation from total precipitation and the solid fraction. '''
    # Perform some type checks
    super(SolidPrecipSR,self).computeValues(indata, aggax=aggax, delta=delta, const=const, tmp=tmp) 
    # Compute the result
    outdata = indata['RAIN'] * indata['SR'] # If SR ranges from 0 to 1.
    if np.max(indata['SR']) > 1: outdata /= 2. # If SR ranges from 0 to 2.
    return outdata


# ==================================== Regular derived variables: NetPrecip ==========================================

class NetPrecip(DerivedVariable):
  ''' DerivedVariable child implementing computation of net precipitation for WRF output. '''  
  
  def __init__(self, sfcevp='SFCEVP'): # 'SFCEVP' for hydro and 'QFC' for srfc files.
    ''' Initialize with fixed values and name of surface evaporation variable as argument. '''
    super(NetPrecip,self).__init__(name='NetPrecip', # Name of the variable.
                              units='kg/m^2/s', # Not accumulated. 
                              prerequisites=['RAIN', sfcevp], # It's the difference of these two. 
                              axes=('time','south_north','west_east'), # Dimensions of NetCDF variable. 
                              dtype=dv_float, atts=None, linear=True) 
    self.sfcevp = sfcevp

  def computeValues(self, indata, aggax=0, delta=None, const=None, tmp=None, ignoreNaN=False):
    ''' Compute net precipitation as the difference between total precipitation and evapo-transpiration. '''
    # This computation is actually linear.
    # Perform some type checks 
    super(NetPrecip,self).computeValues(indata, const=None)    
    # Compute the result
    outdata = indata['RAIN'] - indata[self.sfcevp] 
    return outdata


# ==================================== Regular derived variables: NetWaterFlux ==========================================

class NetWaterFlux(DerivedVariable):
  ''' DerivedVariable child implementing computation of net water flux at the surface for WRF output. '''
  
  def __init__(self):
    ''' Initialize with fixed values; constructor takes no arguments. '''
    super(NetWaterFlux,self).__init__(name='NetWaterFlux', # Name of the variable.
                              units='kg/m^2/s', # Not accumulated.
                              prerequisites=['LiquidPrecip', 'SFCEVP', 'ACSNOM'],   
                              axes=('time','south_north','west_east'), # Dimensions of NetCDF variable. 
                              dtype=dv_float, atts=None, linear=True) 

  def computeValues(self, indata, aggax=0, delta=None, const=None, tmp=None, ignoreNaN=False):
    ''' Compute net water flux as the sum of liquid precipitation and snowmelt minus evapo-transpiration. '''
    # This computation is actually linear.
    # Perform some type checks
    super(NetWaterFlux,self).computeValues(indata, const=None) 
    # Compute the result
    outdata = evaluate('LiquidPrecip - SFCEVP + ACSNOM', local_dict=indata)  
    return outdata


# ==================================== Regular derived variables: WaterForcing ==========================================

class WaterForcing(DerivedVariable):
  ''' DerivedVariable child implementing computation of water flux/forcing at the surface for WRF output. '''
  
  def __init__(self):
    ''' Initialize with fixed values; constructor takes no arguments. '''
    super(WaterForcing,self).__init__(name='WaterForcing', # Name of the variable.
                              units='kg/m^2/s', # Not accumulated. 
                              prerequisites=['LiquidPrecip', 'ACSNOM'],   
                              axes=('time','south_north','west_east'), # Dimensions of NetCDF variable. 
                              dtype=dv_float, atts=None, linear=True) 

  def computeValues(self, indata, aggax=0, delta=None, const=None, tmp=None, ignoreNaN=False):
    ''' Compute water flux/forcing as the sum of liquid precipitation and snowmelt. '''
    # This computation is actually linear.
    # Perform some type checks
    super(WaterForcing,self).computeValues(indata, const=None) 
    # Compute the result
    outdata = evaluate('LiquidPrecip + ACSNOM', local_dict=indata)  
    return outdata


# ==================================== Regular derived variables: RunOff ==========================================

class RunOff(DerivedVariable):
  ''' DerivedVariable child implementing computation of total run off for WRF output. '''
  
  def __init__(self):
    ''' Initialize with fixed values; constructor takes no arguments. '''
    super(RunOff,self).__init__(name='Runoff', # Name of the variable.
                              units='kg/m^2/s', # Not accumulated. 
                              prerequisites=['SFROFF', 'UDROFF'], # It's the sum of these two. 
                              axes=('time','south_north','west_east'), # Dimensions of NetCDF variable. 
                              dtype=dv_float, atts=None, linear=True) 

  def computeValues(self, indata, aggax=0, delta=None, const=None, tmp=None, ignoreNaN=False):
    ''' Compute total runoff as the sum of surface and underground runoff. '''
    # This computation is actually linear.
    # Perform some type checks
    super(RunOff,self).computeValues(indata, aggax=aggax, delta=delta, const=const, tmp=tmp)     
    # Compute the result
    outdata = indata['SFROFF'] + indata['UDROFF'] 
    return outdata


# ==================================== Regular derived variables: WaterVapor ==========================================

class WaterVapor(DerivedVariable):
  ''' DerivedVariable child implementing computation of water vapor partial pressure for WRF output. '''
  
  def __init__(self):
    ''' Initialize with fixed values; constructor takes no arguments. '''
    super(WaterVapor,self).__init__(name='WaterVapor', # Name of the variable.
                              units='Pa', # Not accumulated. 
                              prerequisites=['Q2', 'PSFC'], # It's the sum of these two. 
                              axes=('time','south_north','west_east'), # Dimensions of NetCDF variable. 
                              dtype=dv_float, atts=None, linear=False)
    self.Mratio = 28.96 / 18.02 # g/mol, molecular mass ratio of dry air over water. 

  def computeValues(self, indata, aggax=0, delta=None, const=None, tmp=None, ignoreNaN=False):
    ''' Compute water vapor partial pressure as the product of Mratio, Q2 and PSFC. ????? '''
    # Perform some type checks
    super(WaterVapor,self).computeValues(indata, aggax=aggax, delta=delta, const=const, tmp=tmp) 
    # Compute the result
    Mratio = self.Mratio; Q2 = indata['Q2']; PSFC = indata['PSFC']     
    outdata =  evaluate('Mratio * Q2 * PSFC') # This is an approximation (Q or p variations under 2m are small).
    return outdata
  

# ==================================== Regular derived variables: WetDays ==========================================

class WetDays(DerivedVariable):
  ''' DerivedVariable child for counting the fraction of wet days for WRF output. '''
  
  def __init__(self, threshold=1., rain='RAIN', ignoreNaN=False):
    ''' Initialize with fixed values and selected dry-day threshold (defined by argument in mm/day). '''
    name = 'WetDays_{:03d}'.format(int(10*threshold))
    threshold /= 86400. # Convert to SI units (argument assumed mm/day).
    atts = dict(threshold=threshold) # Save threshold value in SI units.
    super(WetDays,self).__init__(name=name, # Name of the variable.
                              units='', # Fraction of days. 
                              prerequisites=[rain], # Above threshold. 
                              axes=('time','south_north','west_east'), # Dimensions of NetCDF variable. 
                              dtype=dv_float, atts=atts, linear=False, ignoreNaN=ignoreNaN)
    self.threshold = threshold # Store for computation.
    self.rain = rain # Name of the rain variable.
    
  def computeValues(self, indata, aggax=0, delta=None, const=None, tmp=None):
    ''' Count the number of events above a threshold. '''
    # Perform some type checks
    super(WetDays,self).computeValues(indata, aggax=aggax, delta=delta, const=const, tmp=tmp) 
    # Check that delta does not change
    if tmp is not None:
      if 'WETDAYS_DELTA' in tmp: 
        if delta != tmp['WETDAYS_DELTA']: 
          raise NotImplementedError('Output interval is assumed to be constant for conversion to days (delta={:f}).'.format(delta))
      else: tmp['WETDAYS_DELTA'] = delta # Save and check next time.
    # NOTE: Sampling does not have to be daily, meaning that this will simply compute the fraction of 
    #   timesteps that exceed the threshold, irrespective of what the output frequency is.
    # Compute the result
    if self.ignoreNaN:
      outdata = np.where(indata[self.rain] > self.threshold, 1,0) # Comparisons with NaN always yield False.
      outdata = np.where(np.isnan(indata[self.rain]), np.NaN,outdata)     
    else:
      outdata = indata[self.rain] > self.threshold 
    # NOTE: The definition according to AMS Glossary is: precip > 0.02 mm/day.
    # NOTE: This can be used to calculate the fraction of wet days in a month. In fact somewhere else in the code wetdays
    #   is averaged to become the average fraction of wet days (e.g., it was wet 45% of the time on average this month).        
    return outdata


# ==================================== Regular derived variables: WetDayRain ==========================================

class WetDayRain(DerivedVariable):
  ''' DerivedVariable child for precipitation amounts exceeding the wet day threshold. '''
    
  def __init__(self, threshold=1., rain='RAIN', ignoreNaN=False):
    ''' Initialize with fixed values and selected dry-day threshold (defined by argument in mm/day). '''
    name = 'WetDayRain_{:03d}'.format(int(10*threshold))
    wetdays = 'WetDays_{:03d}'.format(int(10*threshold))
    threshold /= 86400. # Convert to SI units (argument assumed mm/day).
    atts = dict(threshold=threshold) # Save threshold value in SI units.
    super(WetDayRain,self).__init__(name=name, # Name of the variable.
                              units='kg/m^2/s', # The unit is that of rain.  
                              prerequisites=[rain,wetdays], # Above threshold. 
                              axes=('time','south_north','west_east'), # Dimensions of NetCDF variable. 
                              dtype=dv_float, atts=atts, linear=False, ignoreNaN=ignoreNaN)
    self.rain = rain # Name of the rain variable.
    self.wetdays = wetdays 
    
  def computeValues(self, indata, aggax=0, delta=None, const=None, tmp=None):
    ''' Report the precipitation for the times when events are above a threshold. '''
    # Perform some type checks
    super(WetDayRain,self).computeValues(indata, aggax=aggax, delta=delta, const=const, tmp=tmp) 
    # Compute the result (just set precip to zero if it is below a threshold) 
    outdata = np.where(indata[self.wetdays] == 0, 0., indata[self.rain])
    # NOTE: This gives the amount of precipitation on the days, when it was above a threshold, which can be used to calculate
    #   the average precipitation rate. In fact somewhere else in the code this is average to become the average pericipitation
    #   rate. The reason for calculating this is because some models (specially GCMs) have a drizzle problem, where they add a 
    #   small amount of precipitation on days that are not supposed to be wet. These then can add up to large amounts. Andre
    #   thought that this problem could also exist in WRF, so he tried writing this code for that. It turned out that this was 
    #   not that big of an issue in WRF.
    # NOTE: The normal total and average precipitation rates are calculated via the variable Rain above.  
    return outdata


# ==================================== Regular derived variables: WetDayPrecip ========================================== 
# NOTE: The names WetDays, WetDayRain and WetDayPrecip are not very intuitive about the quantities that they represent.
#   Be careful when interpreting their meaning.

class WetDayPrecip(DerivedVariable):
  ''' DerivedVariable child for precipitation amounts on wet days for WRF output. '''
  
  def __init__(self, threshold=1., rain='RAIN', ignoreNaN=False):
    ''' Initialize with fixed values and selected dry-day threshold (defined by argument in mm/day). '''
    name = 'WetDayPrecip_{:03d}'.format(int(10*threshold))
    wetdays = 'WetDays_{:03d}'.format(int(10*threshold))
    wetdayrain = 'WetDayRain_{:03d}'.format(int(10*threshold))
    threshold /= 86400. # Convert to SI units (argument assumed mm/day).
    atts = dict(threshold=threshold) # Save threshold value in SI units.
    super(WetDayPrecip,self).__init__(name=name, # Name of the variable.
                              units='kg/m^2/s', # Fraction of days. ????? 
                              prerequisites=[wetdayrain,wetdays], # Above threshold. 
                              axes=('time','south_north','west_east'), # Dimensions of NetCDF variable. 
                              dtype=dv_float, atts=atts, linear=True, ignoreNaN=ignoreNaN)
    self.wetdays = wetdays
    self.wetdayrain = wetdayrain 
    
  def computeValues(self, indata, aggax=0, delta=None, const=None, tmp=None):
    ''' Count the number of events above a threshold. '''
    # Perform some type checks
    super(WetDayPrecip,self).computeValues(indata, aggax=aggax, delta=delta, const=const, tmp=tmp) 
    # Compute monthly wet-day-precip as a quasi-linear operation at the end of each month 
    outdata = np.where(indata[self.wetdays] == 0, 0., indata[self.wetdayrain] / indata[self.wetdays])
    # NOTE: The difference between WetDayRain and WetDayPrecip is that the former is averaged over all the available
    #   time slots, whereas the latter is only averaged over wet days.
    # NOTE: WetDays (after being processed here and elsewhere) is actually the average fraction of wet days in a 
    #   month (i.e. not really days). So, because WetDayPrecip is also averaged over a month, the denuminators are
    #   cancelled, so we get the right quantity.          
    return outdata


# ==================================== Regular derived variables: FrostDays ==========================================

class FrostDays(DerivedVariable):
  ''' DerivedVariable child for counting the fraction of frost days for WRF output. '''
  
  def __init__(self, threshold=0., temp='T2MIN', ignoreNaN=False):
    ''' Initialize with fixed values and selected frost-day threshold (defined by argument in Celsius). '''
    name = 'FrostDays_{:+02d}'.format(int(threshold))
    threshold += 273.15 # Convert to SI units (argument assumed Celsius).
    atts = dict(threshold=threshold) # Save threshold value in SI units.
    super(FrostDays,self).__init__(name=name, # Name of the variable.
                              units='', # Fraction of days. 
                              prerequisites=[temp], # Below threshold.
                              axes=('time','south_north','west_east'), # Dimensions of NetCDF variable. 
                              dtype=dv_float, atts=atts, linear=False, ignoreNaN=ignoreNaN)
    self.threshold = threshold 
    self.temp = temp
    
  def computeValues(self, indata, aggax=0, delta=None, const=None, tmp=None):
    ''' Count the number of events below a threshold. '''
    # Perform some type checks
    super(FrostDays,self).computeValues(indata, aggax=aggax, delta=delta, const=const, tmp=tmp)     
    # Check delta, if applicable 
    if delta != 86400. and self.temp != 'T2': 
      raise ValueError('WRF extreme values are suppposed to be daily; encountered delta={:f}.'.format(delta))
    # NOTE: T2 is a snapshot value, so it can make sense regardless of time interval, while Tmin and Tmax 
    #   are diurnal values that only make sense for daily output.
    # Compute the result
    if self.ignoreNaN:
      outdata = np.where(indata[self.temp] < self.threshold, 1,0) # Comparisons with NaN always yield False.
      outdata = np.where(np.isnan(indata[self.temp]), np.NaN,outdata)     
    else:
      outdata = indata[self.temp] < self.threshold # Event below threshold (default 0 deg. Celsius).    
    return outdata


# ==================================== Regular derived variables: SummerDays ==========================================

class SummerDays(DerivedVariable):
  ''' DerivedVariable child for counting the fraction of summer days for WRF output. '''
  
  def __init__(self, threshold=25., temp='T2MAX', ignoreNaN=False):
    ''' Initialize with fixed values and selected threshold (defined by argument in Celsius). '''
    name = 'SummerDays_{:+02d}'.format(int(threshold))
    threshold += 273.15 # Convert to SI units (argument assumed Celsius).
    atts = dict(threshold=threshold) # Save threshold value in SI units.
    super(SummerDays,self).__init__(name=name, # Name of the variable.
                              units='', # Fraction of days. 
                              prerequisites=[temp], # Above threshold.
                              axes=('time','south_north','west_east'), # Dimensions of NetCDF variable. 
                              dtype=dv_float, atts=atts, linear=False, ignoreNaN=ignoreNaN)
    self.threshold = threshold 
    self.temp = temp

  def computeValues(self, indata, aggax=0, delta=None, const=None, tmp=None):
    ''' Count the number of events above a threshold. '''
    # Perform some type checks
    super(SummerDays,self).computeValues(indata, aggax=aggax, delta=delta, const=const, tmp=tmp)     
    # Check delta, if applicable
    if delta != 86400. and self.temp != 'T2': 
      raise ValueError('WRF extreme values are suppposed to be daily; encountered delta={:f}.'.format(delta))
    # NOTE: T2 is a snapshot value, so it can make sense regardless of time interval, while Tmin and Tmax 
    #   are diurnal values that only make sense for daily output.
    # Compute the result
    if self.ignoreNaN:
      outdata = np.where(indata[self.temp] > self.threshold, 1,0) # Comparisons with NaN always yield False.
      outdata = np.where(np.isnan(indata[self.temp]), np.NaN,outdata)     
    else:
      outdata = indata[self.temp] > self.threshold # Event above threshold (default 25 deg. Celsius).    
    return outdata


# ==================================== Regular derived variables: WindSpeed ==========================================

class WindSpeed(DerivedVariable):
  ''' DerivedVariable child for computing total wind speed at 10m. '''
  
  def __init__(self):
    ''' Initialize with fixed values; constructor takes no arguments. '''
    super(WindSpeed,self).__init__(name='WindSpeed', # Name of the variable.
                              units='m/s', # Velocity. 
                              prerequisites=['U10','V10'], # It's the mag. of vector sum of these two.
                              axes=('time','south_north','west_east'), # Dimensions of NetCDF variable. 
                              dtype=dv_float, atts=None, linear=False) 

  def computeValues(self, indata, aggax=0, delta=None, const=None, tmp=None, ignoreNaN=False):
    ''' The surface wind speed at 10m. '''
    # Perform some type checks
    super(WindSpeed,self).computeValues(indata, aggax=aggax, delta=delta, const=const, tmp=tmp) 
    # Compute the length of wind vector
    U = indata['U10']; V = indata['V10']
    outdata = evaluate('sqrt( U**2 + V**2 )') 
    return outdata


# ==================================== Regular derived variables: NetRadiation ==========================================

class NetRadiation(DerivedVariable):
  ''' DerivedVariable child for computing total net radiation at the surface (downward). '''
  
  def __init__(self):
    ''' Initialize with fixed values; constructor takes no arguments. '''
    super(NetRadiation,self).__init__(name='NetRadiation', # Name of the variable.
                              units='J m-2/s', # Radiation. 
                              prerequisites=['ACSWDNB','ACSWUPB','ACLWDNB','ACLWUPB'], # It's the combination of these four.
                              axes=('time','south_north','west_east'), # Dimensions of NetCDF variable. 
                              dtype=dv_float, atts=None, linear=True) 

  def computeValues(self, indata, aggax=0, delta=None, const=None, tmp=None, ignoreNaN=False):
    ''' Downward net radiation at the surface. '''
    # Perform some type checks
    super(NetRadiation,self).computeValues(indata, aggax=aggax, delta=delta, const=const, tmp=tmp) 
    # Compute downward net radiation at the surface
    SWDN = indata['ACSWDNB']; SWUP= indata['ACSWUPB']; LWDN = indata['ACLWDNB']; LWUP = indata['ACLWUPB']
    outdata = evaluate('SWDN - SWUP + LWDN - LWUP') 
    return outdata


# ==================================== Regular derived variables: NetLWRadiation ==========================================

class NetLWRadiation(DerivedVariable):
  ''' DerivedVariable child for computing net long-wave radiation at the surface (downward). '''
  
  def __init__(self):
    ''' Initialize with fixed values; constructor takes no arguments. '''
    super(NetLWRadiation,self).__init__(name='NetLWRadiation', # Name of the variable.
                              units='J m-2/s', # Radiation. 
                              prerequisites=['ACLWDNB','ACLWUPB'], # It's the combination of these two.
                              axes=('time','south_north','west_east'), # Dimensions of NetCDF variable. 
                              dtype=dv_float, atts=None, linear=True) 

  def computeValues(self, indata, aggax=0, delta=None, const=None, tmp=None, ignoreNaN=False):
    ''' Downward LW net radiation at the surface. '''
    # Perform some type checks
    super(NetLWRadiation,self).computeValues(indata, aggax=aggax, delta=delta, const=const, tmp=tmp) 
    # Compute the downward net radiation at the surface
    LWDN = indata['ACLWDNB']; LWUP = indata['ACLWUPB']
    outdata = evaluate('LWDN - LWUP') 
    return outdata


# ==================================== Regular derived variables: OrographicIndex ==========================================

class OrographicIndex(DerivedVariable):
  ''' DerivedVariable child for computing the correlation of (surface) winds with the topographic gradient. '''
  
  def __init__(self):
    ''' Initialize with fixed values; constructor takes no arguments. '''
    super(OrographicIndex,self).__init__(name='OrographicIndex', # Name of the variable.
                              units='m/s', # The unit is that of velocity. 
                              prerequisites=['U10','V10'], # We need these two.
                              constants=['HGT','DY','DX'], # Constants from topography field.
                              axes=('time','south_north','west_east'), # Dimensions of NetCDF variable. 
                              dtype=dv_float, atts=None, linear=False) 

  def computeValues(self, indata, aggax=0, delta=None, const=None, tmp=None, ignoreNaN=False):
    ''' Project surface winds onto topographic gradient. '''
    # Perform some type checks
    super(OrographicIndex,self).computeValues(indata, aggax=aggax, delta=delta, const=const, tmp=tmp) 
    # Compute topographic gradients and save in constants (for later use)
    if 'hgtgrd_sn' not in const:
      if 'HGT' not in const: raise ValueError
      if 'DY' not in const: raise ValueError
      hgtgrd_sn = ctrDiff(const['HGT'], axis=1, delta=const['DY'])
      const['hgtgrd_sn'] = hgtgrd_sn
    else: hgtgrd_sn = const['hgtgrd_sn']  
    if 'hgtgrd_we' not in const:
      if 'HGT' not in const: raise ValueError
      if 'DX' not in const: raise ValueError
      hgtgrd_we = ctrDiff(const['HGT'], axis=2, delta=const['DX'])
      const['hgtgrd_we'] = hgtgrd_we
    else: hgtgrd_we = const['hgtgrd_we']
    # Get the U and V
    U = indata['U10']; V = indata['V10']
    # Compute covariance (projection, scalar product, etc.)    
    outdata = evaluate('U * hgtgrd_we + V * hgtgrd_sn') 
    return outdata


# ==================================== Regular derived variables: CovOIP ==========================================

class CovOIP(DerivedVariable):
  ''' DerivedVariable child for computing the correlation of the orographic index with precipitation. '''
  
  def __init__(self):
    ''' Initialize with fixed values; constructor takes no arguments. '''
    super(CovOIP,self).__init__(name='OIPX', # Name of the variable.
                              units='kg/m^2/s', # The unit is that of rain. 
                              prerequisites=['OrographicIndex', 'RAIN'], # It's the product of these two.
                              axes=('time','south_north','west_east'), # Dimensions of NetCDF variable. 
                              dtype=dv_float, atts=None, linear=False) 

  def computeValues(self, indata, aggax=0, delta=None, const=None, tmp=None, ignoreNaN=False):
    ''' Covariance of Origraphic Index and Precipitation (needed to calculate correlation coefficient). '''
    # Perform some type checks
    super(CovOIP,self).computeValues(indata, aggax=aggax, delta=delta, const=const, tmp=tmp) 
    # Compute covariance
    outdata = evaluate('OrographicIndex * RAIN', local_dict=indata) 
    return outdata


# ==================================== Regular derived variables: OrographicIndexPlev ==========================================

class OrographicIndexPlev(DerivedVariable):
  ''' DerivedVariable child for computing the correlation of (plev) winds with the topographic gradient. '''
  
  def __init__(self):
    ''' Initialize with fixed values; constructor takes no arguments. '''
    super(OrographicIndexPlev,self).__init__(name='OrographicIndex', # Name of the variable.
                              units='m/s', # The unit is that of velocity. 
                              prerequisites=['U_PL','V_PL'], # We need these two.
                              constants=['HGT','DY','DX'], # Constants from topography field.
                              axes=('time','num_press_levels_stag','south_north','west_east'), # Dimensions of NetCDF variable. 
                              dtype=dv_float, atts=None, linear=False) 
    
  def computeValues(self, indata, aggax=0, delta=None, const=None, tmp=None, ignoreNaN=False):
    ''' Project atmospheric winds onto underlying topographic gradient. '''
    # Perform some type checks
    super(OrographicIndexPlev,self).computeValues(indata, aggax=aggax, delta=delta, const=const, tmp=tmp) 
    # Compute topographic gradients and save in constants (for later use)
    if 'hgtgrd_sn' not in const:
      if 'HGT' not in const: raise ValueError
      if 'DY' not in const: raise ValueError
      hgtgrd_sn = ctrDiff(const['HGT'], axis=1, delta=const['DY'])
      const['hgtgrd_sn'] = hgtgrd_sn
    else: hgtgrd_sn = const['hgtgrd_sn']  
    if 'hgtgrd_we' not in const:
      if 'HGT' not in const: raise ValueError
      if 'DX' not in const: raise ValueError
      hgtgrd_we = ctrDiff(const['HGT'], axis=2, delta=const['DX'])
      const['hgtgrd_we'] = hgtgrd_we
    else: hgtgrd_we = const['hgtgrd_we']
    # Get U and V
    U = indata['U_PL']; V = indata['V_PL']
    # Compute covariance (projection, scalar product, etc.)    
    outdata = evaluate('U * hgtgrd_we + V * hgtgrd_sn') 
    return outdata


# ==================================== Regular derived variables: WaterDensity ==========================================

class WaterDensity(DerivedVariable):
  ''' DerivedVariable child for computing water vapor density at a pressure level. '''
  
  def __init__(self):
    ''' Initialize with fixed values; constructor takes no arguments. '''
    super(WaterDensity,self).__init__(name='WaterDensity', # Name of the variable.
                              units='kg/m^3', # Units of density. 
                              prerequisites=['TD_PL','T_PL'], # We need these two.
                              axes=('time','num_press_levels_stag','south_north','west_east'), # Dimensions of NetCDF variable. 
                              dtype=dv_float, atts=None, linear=False)
    self.MR = np.asarray( 0.01802 / 8.3144621, dtype=dv_float) # Mh2o / R ([kg/mol] / [J/K.mol]); from AMS Glossary.
    # NOTE: It is necessary to enforce the type of scalars, otherwise numexpr casts everything as doubles.
    
  def computeValues(self, indata, aggax=0, delta=None, const=None, tmp=None, ignoreNaN=False):
    ''' Compute mass denisty of water vapor using the Magnus formula. '''
    # Perform some type checks
    super(WaterDensity,self).computeValues(indata, aggax=aggax, delta=delta, const=const, tmp=tmp) 
    # Compute partial pressure using Magnus formula (Wikipedia) and then mass per volume = "density"
    # (based on: pV = m T (R/M) -> m/V = M/R * p/T)
    MR = self.MR; Td = indata['TD_PL']; T = indata['T_PL']     
    outdata = evaluate('MR * 100. * 6.1094 * exp( 17.625 * (Td - 273.15) / (Td - 273.15 + 243.04) ) / T')
    # NOTE: The Magnus formula uses Celsius and returns hecto-Pascale: need to convert to/from SI.
    # NOTE: According to Andre, when we want to get the non-saturated water vapor pressure, we use the Td in
    #   the Magnus formula and when we want the saturated water vapor pressure, we use T in it. I think that it
    #   should be the other way around, but Andre is 100 percent certain about this, so I accept that. ?????  
    return outdata


# ==================================== Regular derived variables: ColumnWater ==========================================

class ColumnWater(DerivedVariable):
  ''' DerivedVariable child for computing the column-integrated atmospheric water vapor content. '''
  
  def __init__(self):
    ''' Initialize with fixed values; constructor takes no arguments. '''
    super(ColumnWater,self).__init__(name='ColumnWater', # Name of the variable.
                              units='kg/m^2', # Water content per m^2.
                              prerequisites=['T_PL','P_PL','WaterDensity'], # We need these.
                              axes=('time','south_north','west_east'), # Dimensions of NetCDF variable. 
                              dtype=dv_float, atts=None, linear=False) 
    self.RMg = np.asarray( 8.3144621 / ( 0.01802 *  9.80616 ), dtype=dv_float) # R / (Mh2o g); from AMS Glossary (g at 45 lat).
    # NOTE: It is necessary to enforce the type of scalars, otherwise numexpr casts everything as doubles.
    
  def computeValues(self, indata, aggax=0, delta=None, const=None, tmp=None, ignoreNaN=False):
    ''' Compute column-integrated atmospheric water vapor content. '''
    # Perform some type checks
    super(ColumnWater,self).computeValues(indata, aggax=aggax, delta=delta, const=const, tmp=tmp) 
    # Compute the result
    outdata = pressureIntegral(var=indata['WaterDensity'], T=indata['T_PL'], 
                               p=indata['P_PL'], RMg=self.RMg)
    return outdata


# ==================================== Regular derived variables: WaterFlux_U ==========================================

class WaterFlux_U(DerivedVariable):
  ''' DerivedVariable child for computing the atmospheric transport of water vapor (West-East). '''
  
  def __init__(self):
    ''' Initialize with fixed values; constructor takes no arguments. '''
    super(WaterFlux_U,self).__init__(name='WaterFlux_U', # Name of the variable.
                              units='kg/m^2/s', # Flux. 
                              prerequisites=['U_PL','WaterDensity'], # West-east direction: U.
                              axes=('time','num_press_levels_stag','south_north','west_east'), # Dimensions of NetCDF variable. 
                              dtype=dv_float, atts=None, linear=False) 
    
  def computeValues(self, indata, aggax=0, delta=None, const=None, tmp=None, ignoreNaN=False):
    ''' Compute West-East atmospheric water vapor transport. '''
    # Perform some type checks
    super(WaterFlux_U,self).computeValues(indata, aggax=aggax, delta=delta, const=const, tmp=tmp) 
    # Compute the result    
    outdata = indata['U_PL']*indata['WaterDensity'] 
    return outdata


# ==================================== Regular derived variables: WaterFlux_V ==========================================

class WaterFlux_V(DerivedVariable):
  ''' DerivedVariable child for computing the atmospheric transport of water vapor (South-North). '''
  
  def __init__(self):
    ''' Initialize with fixed values; constructor takes no arguments. '''
    super(WaterFlux_V,self).__init__(name='WaterFlux_V', # Name of the variable.
                              units='kg/m^2/s', # Flux. 
                              prerequisites=['V_PL','WaterDensity'], # South-north direction: V.
                              axes=('time','num_press_levels_stag','south_north','west_east'), # Dimensions of NetCDF variable. 
                              dtype=dv_float, atts=None, linear=False) 
    
  def computeValues(self, indata, aggax=0, delta=None, const=None, tmp=None, ignoreNaN=False):
    ''' Compute South-North atmospheric water vapor transport. '''
    # Perform some type checks
    super(WaterFlux_V,self).computeValues(indata, aggax=aggax, delta=delta, const=const, tmp=tmp) 
    # Compute the result    
    outdata = indata['V_PL']*indata['WaterDensity'] 
    return outdata


# ==================================== Regular derived variables: WaterTransport_U ==========================================

class WaterTransport_U(DerivedVariable):
  ''' DerivedVariable child for computing the column-integrated atmospheric transport of water vapor (West-East). '''
  
  def __init__(self):
    ''' Initialize with fixed values; constructor takes no arguments. '''
    super(WaterTransport_U,self).__init__(name='WaterTransport_U', # Name of the variable.
                              units='kg/m/s', # Flux. 
                              prerequisites=['T_PL','P_PL','WaterFlux_U'], # West-east direction: U.
                              axes=('time','south_north','west_east'), # Dimensions of NetCDF variable. 
                              dtype=dv_float, atts=None, linear=False) 
    self.RMg = np.asarray( 8.3144621 / ( 0.01802 *  9.80616 ), dtype=dv_float) # R / (M g); from AMS Glossary (g at 45 lat).
    # NOTE: It is necessary to enforce the type of scalars, otherwise numexpr casts everything as doubles.
    
  def computeValues(self, indata, aggax=0, delta=None, const=None, tmp=None, ignoreNaN=False):
    ''' Compute West-East atmospheric water vapor transport. '''
    # Perform some type checks
    super(WaterTransport_U,self).computeValues(indata, aggax=aggax, delta=delta, const=const, tmp=tmp) 
    # Calculate the result
    outdata = pressureIntegral(var=indata['WaterFlux_U'], T=indata['T_PL'], 
                               p=indata['P_PL'], RMg=self.RMg)
    return outdata


# ==================================== Regular derived variables: WaterTransport_V ==========================================

class WaterTransport_V(DerivedVariable):
  ''' DerivedVariable child for computing the column-integrated atmospheric transport of water vapor (South-North). '''
  
  def __init__(self):
    ''' Initialize with fixed values; constructor takes no arguments. '''
    super(WaterTransport_V,self).__init__(name='WaterTransport_V', # Name of the variable.
                              units='kg/m/s', # Flux. 
                              prerequisites=['T_PL','P_PL','WaterFlux_V'], # South-north direction: V.
                              axes=('time','south_north','west_east'), # Dimensions of NetCDF variable. 
                              dtype=dv_float, atts=None, linear=False) 
    self.RMg = np.asarray( 8.3144621 / ( 0.01802 *  9.80616 ), dtype=dv_float)  # R / (M g); from AMS Glossary (g at 45 lat).
    # NOTE: It is necessary to enforce the type of scalars, otherwise numexpr casts everything as doubles.
    
  def computeValues(self, indata, aggax=0, delta=None, const=None, tmp=None, ignoreNaN=False):
    ''' Compute South-North atmospheric water vapor transport. '''
    # Perform some type checks
    super(WaterTransport_V,self).computeValues(indata, aggax=aggax, delta=delta, const=const, tmp=tmp) 
    # Compute the result
    outdata = pressureIntegral(var=indata['WaterFlux_V'], T=indata['T_PL'], 
                               p=indata['P_PL'], RMg=self.RMg)
    return outdata


# ==================================== Regular derived variables: ColumnHeat ==========================================

class ColumnHeat(DerivedVariable):
  ''' DerivedVariable child for computing the column-integrated cp * T. '''
  
  def __init__(self):
    ''' Initialize with fixed values; constructor takes no arguments. '''
    super(ColumnHeat,self).__init__(name='ColumnHeat', # Name of the variable.
                              units='J m/kg', # J.m/kg.
                              prerequisites=['T_PL','P_PL'], 
                              axes=('time','south_north','west_east'), # Dimensions of NetCDF variable. 
                              dtype=dv_float, atts=None, linear=False) 
    self.RMg = np.asarray( 8.3144621 / ( 0.01802 *  9.80616 ), dtype=dv_float) # R / (M g); from AMS Glossary (g at 45 lat).
    self.cp = np.asarray( 1005.7, dtype=dv_float) # J/(kg K), specific heat of dry air per mass (AMS Glossary).
    # NOTE: It is necessary to enforce the type of scalars, otherwise numexpr casts everything as doubles.

  def computeValues(self, indata, aggax=0, delta=None, const=None, tmp=None, ignoreNaN=False):
    ''' Compute the column-integrated cp * T. '''
    # Perform some type checks
    super(ColumnHeat,self).computeValues(indata, aggax=aggax, delta=delta, const=const, tmp=tmp) 
    # Compute the result
    outdata = pressureIntegral(var=indata['T_PL'], T=indata['T_PL'], 
                               p=indata['P_PL'], RMg=self.RMg)
    outdata *= self.cp 
    # NOTE: The ColumnHeat at the moment has the units of J.m/kg, which does not seem physcially intuitive. It may be that
    #   we are missing a density factor in the calculation (which'd make the units J/m^2 and more sensible). ?????
    return outdata


# ==================================== Regular derived variables: HeatFlux_U ==========================================

class HeatFlux_U(DerivedVariable):
  ''' DerivedVariable child for computing the atmospheric (sensible) heat transport (West-East). '''
  
  def __init__(self):
    ''' Initialize with fixed values; constructor takes no arguments. '''
    super(HeatFlux_U,self).__init__(name='HeatFlux_U', # Name of the variable.
                              units='J/m^2/s', # Flux. 
                              prerequisites=['U_PL','P_PL'], # West-east direction: U.
                              axes=('time','num_press_levels_stag','south_north','west_east'), # Dimensions of NetCDF variable. 
                              dtype=dv_float, atts=None, linear=False) 
    self.cpMR = np.asarray( 1005.7 * 0.0289644 / 8.3144621, dtype=dv_float) # cp * Mair / R (AMS Glossary).
    
  def computeValues(self, indata, aggax=0, delta=None, const=None, tmp=None, ignoreNaN=False):
    ''' Compute West-East atmospheric sensible heat transport. '''
    # Perform some type checks
    super(HeatFlux_U,self).computeValues(indata, aggax=aggax, delta=delta, const=const, tmp=tmp) 
    # Compute the result    
    p=indata['P_PL']; u = indata['U_PL']; cpMR = self.cpMR
    p = p.reshape(p.shape+(1,1)) # Extend singleton dimensions.
    outdata = evaluate('u * p * cpMR')
    # NOTE: u * T*cp * rho; rho = p / (R/M * T) => u * p * (cp * M / R). 
    return outdata


# ==================================== Regular derived variables: HeatFlux_V ==========================================

class HeatFlux_V(DerivedVariable):
  ''' DerivedVariable child for computing the atmospheric (sensible) heat transport (South-North). '''
  
  def __init__(self):
    ''' Initialize with fixed values; constructor takes no arguments. '''
    super(HeatFlux_V,self).__init__(name='HeatFlux_V', # Name of the variable.
                              units='J/m^2/s', # Flux. 
                              prerequisites=['V_PL','P_PL'], # South-north direction: V.
                              axes=('time','num_press_levels_stag','south_north','west_east'), # Dimensions of NetCDF variable. 
                              dtype=dv_float, atts=None, linear=False) 
    self.cpMR = np.asarray( 1005.7 * 0.0289644 / 8.3144621, dtype=dv_float) # cp * Mair / R (AMS Glossary).
    
  def computeValues(self, indata, aggax=0, delta=None, const=None, tmp=None, ignoreNaN=False):
    ''' Compute South-North atmospheric sensible heat transport. '''
    # Perform some type checks
    super(HeatFlux_V,self).computeValues(indata, aggax=aggax, delta=delta, const=const, tmp=tmp) 
    # Compute the result    
    p=indata['P_PL']; v = indata['V_PL']; cpMR = self.cpMR
    p = p.reshape(p.shape+(1,1)) # Extend singleton dimensions.
    outdata = evaluate('v * p * cpMR')
    # NOTE: v * T*cp * rho; rho = p / (R/M * T) => v * p * (cp * M / R). 
    return outdata


# ==================================== Regular derived variables: HeatTransport_U ==========================================

class HeatTransport_U(DerivedVariable):
  ''' DerivedVariable child for computing the column-integrated atmospheric heat transport (West-East). '''
  
  def __init__(self):
    ''' Initialize with fixed values; constructor takes no arguments. '''
    super(HeatTransport_U,self).__init__(name='HeatTransport_U', # Name of the variable.
                              units='J/m/s', # Flux. 
                              prerequisites=['T_PL','P_PL','HeatFlux_U'], # West-east direction: U.
                              axes=('time','south_north','west_east'), # Dimensions of NetCDF variable. 
                              dtype=dv_float, atts=None, linear=False) 
    self.RMg = np.asarray( 8.3144621 / ( 0.01802 *  9.80616 ), dtype=dv_float) # R / (M g); from AMS Glossary (g at 45 lat).
    # NOTE: It is necessary to enforce the type of scalars, otherwise numexpr casts everything as doubles.
    
  def computeValues(self, indata, aggax=0, delta=None, const=None, tmp=None, ignoreNaN=False):
    ''' Compute West-East atmospheric heat transport. '''
    # Perform some type checks
    super(HeatTransport_U,self).computeValues(indata, aggax=aggax, delta=delta, const=const, tmp=tmp) 
    # Compute the result
    outdata = pressureIntegral(var=indata['HeatFlux_U'], T=indata['T_PL'], 
                               p=indata['P_PL'], RMg=self.RMg)
    return outdata


# ==================================== Regular derived variables: HeatTransport_V ==========================================

class HeatTransport_V(DerivedVariable):
  ''' DerivedVariable child for computing the column-integrated atmospheric heat transport (South-North). '''
  
  def __init__(self):
    ''' Initialize with fixed values; constructor takes no arguments. '''
    super(HeatTransport_V,self).__init__(name='HeatTransport_V', # Name of the variable.
                              units='J/m/s', # Flux. 
                              prerequisites=['T_PL','P_PL','HeatFlux_V'], # South-north direction: V.
                              axes=('time','south_north','west_east'), # Dimensions of NetCDF variable. 
                              dtype=dv_float, atts=None, linear=False) 
    self.RMg = np.asarray( 8.3144621 / ( 0.01802 *  9.80616 ), dtype=dv_float) # R / (M g); from AMS Glossary (g at 45 lat).
    # NOTE: It is necessary to enforce the type of scalars, otherwise numexpr casts everything as doubles.
    
  def computeValues(self, indata, aggax=0, delta=None, const=None, tmp=None, ignoreNaN=False):
    ''' Compute South-North atmospheric heat transport. '''
    # Perform some type checks
    super(HeatTransport_V,self).computeValues(indata, aggax=aggax, delta=delta, const=const, tmp=tmp) 
    # Compute the result
    outdata = pressureIntegral(var=indata['HeatFlux_V'], T=indata['T_PL'], 
                               p=indata['P_PL'], RMg=self.RMg)
    return outdata


# ==================================== Regular derived variables: Vorticity ==========================================

class Vorticity(DerivedVariable):
  ''' DerivedVariable child for computing relative vorticity. '''
  
  def __init__(self):
    ''' Initialize with fixed values; constructor takes no arguments. '''
    super(Vorticity,self).__init__(name='Vorticity', # Name of the variable.
                              units='1/s', 
                              prerequisites=['U_PL','V_PL'],
                              axes=('time','num_press_levels_stag','south_north','west_east'), # Dimensions of NetCDF variable. 
                              dtype=dv_float, atts=None, linear=True) 

  def computeValues(self, indata, aggax=0, delta=None, const=None, tmp=None, ignoreNaN=False):
    ''' Calculate the vorticity. '''
    # Perform some type checks
    super(Vorticity,self).computeValues(indata, aggax=aggax, delta=delta, const=const, tmp=tmp) 
    # Compute relative vorticity on pressure levels (zeta = dv/dx - du/dy)
    outdata = ( ctrDiff(indata['V_PL'], axis=3, delta=const['DX']) 
                -  ctrDiff(indata['U_PL'], axis=2, delta=const['DY']) )
    # NOTE: Order of dimensions is t,p,y,x.
    return outdata


# ==================================== Regular derived variables: Vorticity_Var ==========================================

class Vorticity_Var(DerivedVariable):
  ''' DerivedVariable child for computing the variance of relative vorticity. '''
  
  def __init__(self):
    ''' Initialize with fixed values; constructor takes no arguments. '''
    super(Vorticity_Var,self).__init__(name='Vorticity_Var', # Name of the variable.
                              units='1/s^2', 
                              prerequisites=['Vorticity'],
                              axes=('time','num_press_levels_stag','south_north','west_east'), # Dimensions of NetCDF variable. 
                              dtype=dv_float, atts=None, linear=False) 

  def computeValues(self, indata, aggax=0, delta=None, const=None, tmp=None, ignoreNaN=False):
    ''' Calculate vorticity squared. '''
    # Perform some type checks
    super(Vorticity_Var,self).computeValues(indata, aggax=aggax, delta=delta, const=const, tmp=tmp) 
    # Compute variance without subtracting the mean 
    outdata = indata['Vorticity']**2
    # NOTE: To get actual variance, the square of the mean has to be subtracted after the final stage of aggregation. 
    #   That is because Var(Z) = mean(Z^2) - (mean(Z))^2. Note that this has not been done in the code before. This 
    #   can easily be done in the analysis code, but that should not be forgotten about.    
    return outdata


# ==================================== Regular derived variables: GHT_Var ==========================================

class GHT_Var(DerivedVariable):
  ''' DerivedVariable child for computing the variance of geopotential height on pressure levels. '''
  
  def __init__(self):
    ''' Initialize with fixed values; constructor takes no arguments. '''
    super(GHT_Var,self).__init__(name='GHT_Var', # Name of the variable.
                              units='m^2', 
                              prerequisites=['GHT_PL'],
                              axes=('time','num_press_levels_stag','south_north','west_east'), # Dimensions of NetCDF variable. 
                              dtype=dv_float, atts=None, linear=False) 

  def computeValues(self, indata, aggax=0, delta=None, const=None, tmp=None, ignoreNaN=False):
    ''' Calculate GHT_PL squared. '''
    # Perform some type checks
    super(GHT_Var,self).computeValues(indata, aggax=aggax, delta=delta, const=const, tmp=tmp) 
    # Compute variance without subtracting the mean 
    outdata = indata['GHT_PL']**2
    # NOTE: To get actual variance, the square of the mean has to be subtracted after the final stage of aggregation. 
    #   That is because Var(Z) = mean(Z^2) - (mean(Z))^2. Note that this has not been done in the code before. This 
    #   can easily be done in the analysis code, but that should not be forgotten about. 
    return outdata


# ==================================== Extreme values: Base class for extrema ==========================================
 
class Extrema(DerivedVariable):
  ''' DerivedVariable child implementing computation of extrema in monthly WRF output. '''
  
  def __init__(self, var, mode, name=None, long_name=None, dimmap=None, ignoreNaN=False):
    ''' Constructor; takes variable object as argument and infers meta data. '''
    # NOTE: The name should be constructed with prefix 'Max'/'Min' and camel-case.
    # NOTE: Camel case (sometimes stylized as camelCase or CamelCase, also known as camel caps or more formally 
    #   as medial capitals) is the practice of writing phrases without spaces or punctuation, indicating the 
    #   separation of words with a single capitalized letter, and the first word starting with either case. 
    #   Common examples include "iPhone" and "eBay".
    # Get varname, axes and atts
    if isinstance(var, DerivedVariable):
      varname = var.name; axes = var.axes; atts = var.atts.copy() or dict()
    elif isinstance(var, nc.Variable):
      varname = var._name; axes = var.dimensions; atts = dict()
    else: raise TypeError
    # Select mode
    if mode.lower() == 'max':      
      atts['Aggregation'] = 'Monthly Maximum'; prefix = 'Max'; exmode = 1
    elif mode.lower() == 'min':      
      atts['Aggregation'] = 'Monthly Minimum'; prefix = 'Min'; exmode = 0
    # Handle long_name, dimmap and name
    if long_name is not None: atts['long_name'] = long_name
    if isinstance(dimmap,dict): axes = [dimmap[dim] if dim in dimmap else dim for dim in axes]
    if name is None: name = '{0:s}{1:s}'.format(prefix,varname[0].upper() + varname[1:])
    # Infer attributes of extreme variable
    super(Extrema,self).__init__(name=name, units=var.units, prerequisites=[varname], axes=axes, 
                                 dtype=var.dtype, atts=atts, linear=False, normalize=False, ignoreNaN=ignoreNaN)
    self.mode = exmode
    self.tmpdata = None # Don't need temporary storage. 

  def computeValues(self, indata, aggax=0, delta=None, const=None, tmp=None):
    ''' Compute field of maxima. '''
    # Perform some type checks
    super(Extrema,self).computeValues(indata, aggax=aggax, delta=delta, const=const, tmp=tmp) 
    # Decide, what to do
    if self.mode == 1:
      if self.ignoreNaN: outdata = np.nanmax(indata[self.prerequisites[0]], axis=aggax) # Ignore NaNs.
      else: outdata = np.max(indata[self.prerequisites[0]], axis=aggax) # Compute maximum.
    elif self.mode == 0:
      if self.ignoreNaN: outdata = np.nanmin(indata[self.prerequisites[0]], axis=aggax) # Ignore NaNs.
      else: outdata = np.min(indata[self.prerequisites[0]], axis=aggax) # Compute minimum.
    # NOTE: Already partially aggregating here, saves memory.
    return outdata
  
  def aggregateValues(self, comdata, aggdata=None, aggax=0):
    ''' Compute and aggregate values for non-linear cases over several input periods/files. '''
    # NOTE: Linear variables can go through this chain as well, if it is a pre-requisite for a non-linear variable.
    # Check the types
    if not isinstance(aggdata,np.ndarray) and aggdata is not None: raise TypeError # Aggregate variable.
    if not isinstance(comdata,np.ndarray) and comdata is not None: raise TypeError # Newly computed values.
    if not isinstance(aggax,(int,np.integer)): raise TypeError # The aggregation axis (needed for extrema).
    # Check the normalize
    if self.normalize: raise DerivedVariableError('Aggregated extrema should not be normalized!')
    # NOTE: The default implementation is just a simple sum that will be normalized to an average.
    # Do the computation
    if comdata is not None and comdata.size > 0:
      # NOTE: comdata can be None if the record was not long enough to compute this variable.
      if aggdata is None:
        aggdata = comdata # If e.g., no intermediate accumulation step (already monthly data).
      else:
        if self.mode == 1: 
          if self.ignoreNaN: aggdata = np.fmax(aggdata,comdata)
          else: aggdata = np.maximum(aggdata,comdata) 
        elif self.mode == 0:
          if self.ignoreNaN: aggdata = np.fmin(aggdata,comdata)
          else: aggdata = np.minimum(aggdata,comdata) 
        # NOTE: numpy.fmin(x1, x2) returns the element-wise-compared minimum of x1 and x2. A similar definition
        #   holds for numpy.fmax function.   
    # Return aggregated value for further treatment
    return aggdata
  
  
# ====================== Extreme values: Base class for 'period over threshold'-type extrema ============================

class ConsecutiveExtrema(Extrema):
  ''' Class of variables that tracks the period of exceedance of a threshold. '''

  def __init__(self, var, mode, threshold=0, name=None, long_name=None, dimmap=None, ignoreNaN=False):
    ''' Constructor; takes variable object as argument and infers meta data. '''
    # NOTE: The name should be constructed with prefix 'Max'/'Min' and camel-case.
    # Get varname, axes and atts
    if isinstance(var, DerivedVariable):
      varname = var.name; axes = var.axes; atts = var.atts.copy() or dict()
    elif isinstance(var, nc.Variable):
      varname = var._name; axes = var.dimensions; atts = dict()
    else: raise TypeError
    # Select mode
    if mode.lower() == 'above':      
      atts['Aggregation'] = 'Maximum Monthly Consecutive Days Above Threshold'
      name_prefix = 'ConAb'; exmode = 1; prefix = '>'
    elif mode.lower() == 'below':      
      atts['Aggregation'] = 'Maximum Monthly Consecutive Days Below Threshold'
      name_prefix = 'ConBe'; exmode = 0; prefix = '<'
    else: raise ValueError("Only 'above' and 'below' are valid modes.")
    # Assign some attributes
    atts['Variable'] = '{0:s} {1:s} {2:s} {3:s}'.format(varname,prefix,str(threshold),var.units) 
    atts['ThresholdValue'] = str(threshold); atts['ThresholdVariable'] = varname 
    # Handle long_name, dimmap and name
    if long_name is not None: atts['long_name'] = long_name 
    if isinstance(dimmap,dict): axes = [dimmap[dim] if dim in dimmap else dim for dim in axes]
    if name is None: name = '{0:s}{1:f}{2:s}'.format(prefix,threshold,varname[0].upper() + varname[1:])
    # Infer attributes of consecutive extreme variable
    super(Extrema,self).__init__(name=name, units='days', prerequisites=[varname], axes=axes, ignoreNaN=ignoreNaN, 
                                 dtype=np.dtype('int16'), atts=atts, linear=False, normalize=False)    
    self.lengthofday = 86400. # delta's are in units of seconds (24 * 60 * 60).
    self.period = 0. # Will be set later.
    self.thresmode = exmode # Above (=1) or below (=0). 
    self.threshold = threshold # Threshold value.
    self.mode = 1 # Aggregation method is always maximum (longest period).
    self.tmpdata = 'COX_'+self.name # Handle for temporary storage. "COX" stands for "COnsecutive eXtrema".   
    self.carryover = True # Don't stop counting - this is vital.    
    
  def computeValues(self, indata, aggax=0, delta=None, const=None, tmp=None):
    ''' Count consecutive above/below threshold days. '''
    # Perform some type checks
    super(Extrema,self).computeValues(indata, aggax=aggax, delta=delta, const=const, tmp=tmp) 
    # Check that delta does not change
    if 'COX_DELTA' in tmp: 
      if delta != tmp['COX_DELTA']: 
        raise NotImplementedError('Consecutive extrema currently only work, if the output interval is constant.')
    else: 
      tmp['COX_DELTA'] = delta # Save and check next time.
    # Handle period
    if self.period == 0.: 
      self.period = delta / self.lengthofday 
    # Get data
    data = indata[self.prerequisites[0]]
    # If axis is not 0 (outermost), roll axis until it is
    if aggax != 0: data = np.rollaxis(data, axis=aggax, start=0).copy() # Should make a copy.
    # Get tlen and xshape
    tlen = data.shape[0] # Aggregation axis.
    xshape = data.shape[1:] # Rest of the map.
    # Initialize counter of consecutive exceedances
    if self.tmpdata in tmp: xcnt = tmp[self.tmpdata] # Carry over from previous period. 
    else: xcnt = np.zeros(xshape, dtype='int16')# Initialize as zero.
    # Initialize output array
    maxdata = np.zeros(xshape, dtype=np.dtype('int16')) # Record of maximum consecutive days in computation period. 
    # March along aggregation axis
    for t in range(tlen):
      # Detect threshold changes
      if self.thresmode == 1: xmask = ( data[t,:] > self.threshold ) # Above.
      elif self.thresmode == 0: xmask = ( data[t,:] < self.threshold ) # Below.
      # NOTE: Comparisons with NaN always yield False, i.e. non-exceedance.
      # Update maxima of exceedances
      xnew = np.where(xmask,0,xcnt) * self.period # Extract periods before reset.
      maxdata = np.maximum(maxdata,xnew)        
      # Set counter for all non-exceedances to zero
      xcnt[np.invert(xmask)] = 0
      # Increment exceedance counter
      xcnt[xmask] += 1      
    # Carry over current counter to next period or month
    tmp[self.tmpdata] = xcnt
    # Return output for further aggregation
    if self.ignoreNaN:
      maxdata = np.ma.masked_where(np.isnan(data).sum(axis=0) > 0, maxdata) 
      # NOTE: Here we are masking a grid point, if there is a NaN anywhere in the timeseries at that point. This is 
      #   not entirely correct, as there may be an extremum period during non-nan times. Andre says he does not know 
      #   of any gridpoint of interest that was masked, so that was not an issue in the past. Just be careful about
      #   this in the future runs (or maybe fix the porblem). 
    return maxdata
  

# ====================== Extreme values: Base class for interval-averaged extrema (sort of similar to running mean) ============================

class MeanExtrema(Extrema):
  ''' Extrema child implementing extrema of interval-averaged values in monthly WRF output. '''
  
  def __init__(self, var, mode, interval=5, name=None, long_name=None, dimmap=None, ignoreNaN=False):
    ''' Constructor; takes variable object as argument and infers meta data. '''
    # Infer attributes of maximum variable and check length of prerequisites
    super(MeanExtrema,self).__init__(var, mode, name=name, long_name=long_name, dimmap=dimmap, ignoreNaN=ignoreNaN)
    if len(self.prerequisites) > 1: raise ValueError("Extrema can only have one Prerquisite")
    self.atts['name'] = self.name = '{0:s}_{1:d}d'.format(self.name,interval)
    self.atts['Aggregation'] = 'Averaged ' + self.atts['Aggregation']
    self.atts['AverageInterval'] = '{0:d} days'.format(interval) # Interval in days.
    self.interval = interval * 24*60*60 # In seconds, since delta will be in seconds, too.
    self.tmpdata = 'MEX_'+self.name # Handle for temporary storage.
    self.carryover = True # Don't drop data.    

  def computeValues(self, indata, aggax=0, delta=None, const=None, tmp=None):
    ''' Compute field of maxima. '''
    # Check delta
    if delta == 0: raise ValueError('No interval to average over.')
    # Assemble data
    data = indata[self.prerequisites[0]]
    # If axis is not 0 (outermost), roll axis until it is
    if aggax != 0: data = np.rollaxis(data, axis=aggax, start=0).copy() # Rollaxis just provides a view.
    # If old data available, concatenate it (along time axis)
    if self.tmpdata in tmp:
      data = np.concatenate((tmp[self.tmpdata], data), axis=0)
    # Determine length of interval, etc
    lt = data.shape[0] # Available time steps.
    pape = data.shape[1:] # Remaining shape (must be preserved).
    ilen = int( self.interval / delta )
    nint = int( lt / ilen ) # Number of intervals.
    # Do the computation
    if nint > 0:
      # Truncate and reshape data
      ui = ilen*nint # Usable interval: split data here.
      data = data[:ui,:] # Use this portion.
      rest = data[ui:,:] # Save the rest for next iteration.
      data = data.reshape((nint,ilen) + pape)
      # Average intervals
      meandata = data.mean(axis=1) # Average over interval dimension.
      # Make the mean data into a dictionary 
      datadict = {self.prerequisites[0]:meandata} # Next method expects a dictionary.
      # Perform some type checks ?????
      outdata = super(MeanExtrema,self).computeValues(datadict, aggax=0, delta=delta, const=const, 
                                                      tmp=None)  
    else:
      rest = data # Carry over everything.
      outdata = None # Nothing to return (handled in aggregation).
    # Add remaining data to temporary storage
    tmp[self.tmpdata] = rest       
    # NOTE: Already partially aggregating here, saves memory. ?????
    return outdata
