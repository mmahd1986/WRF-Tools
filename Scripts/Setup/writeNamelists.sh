#!/bin/bash

# ==================================================================================
# ==================================================================================
# == This is a script to write WRF and WPS namelist files from selected snippets. ==
# == Developed by: Andre R. Erler, 27/09/2012.                                    ==
# ==================================================================================
# ==================================================================================


# Root folder where namelist snippets are located
WRFTOOLS=${WRFTOOLS:-"${CODE_ROOT}/WRF Tools/"}
NMLDIR=${NMLDIR:-"${WRFTOOLS}/misc/namelists/"}
# NOTE: Every namelist group is assumed to have its own folder.
#   The files will be written to the current directory.


# ===========================================================
# ==== Function to add namelist groups to namelist file. ====
# ===========================================================

function WRITENML () {

    # Arguments 
    NMLGRP="$1" # Namelist group.
    SNIPPETS="$2" # Snippet list.
    FILENAME="$3" # File name.
    MODLIST="$4" # List of modifications (optional).
    
    # Boundaries in the namelist group file
    BEGIN='0,/^\ *&\w.*$/d' # regex matching the namelist group opening.
    END='/^\ *\/\ *$/,$d' # regex matching the namelist group closing.
    # NOTE: regex is regular expression.
    # NOTE: The BEGIN regex starts at line 0 and finds a line starting with (\^)
    #   any number of spaces and then "&" and then a word with as many charachters
    #   as needed, and then the end of the line. This line is deleted.
    # NOTE: The END regex finds a line starting with any number of white spaces  
    #   and then "/", followed by any number of white spaces and then the
    #   end of the line, up until the end of the file ('/,$'). These lines are all
    #   deleted.
      
    # Write namelist group opening into temp file
    rm -f 'TEMPFILE'; touch 'TEMPFILE' # Temporary file.
    # NOTE: Command "touch" above creates an empty temp file.
    echo "&${NMLGRP}" >> 'TEMPFILE'
    # NOTE: The & above is what namelist groups start with, in WRF.
    
    # Insert snippets
    for SNIP in ${SNIPPETS//,/ }; do
        echo " ! --- ${SNIP} ---" >> 'TEMPFILE' # Document origin of snippet.
        sed -e "${BEGIN}" -e "${END}" "${NMLDIR}/${NMLGRP}/${NMLGRP}.${SNIP}" | cat - >> 'TEMPFILE'
    done
    # NOTE: "${SNIPPETS//,/ }" replaces "," in SNIPPETS with " ", so that e.g., 
    #   "cycling,fineIO" becomes "cycling fineIO".
    # NOTE: For how sed works, see the document "sed.pdf".
    # NOTE: A lone dash (-), with no option, usually means "read from standard input". 
    #   This is a very common convention used by many programs. In the above the dash in
    #   front of the cat command means pass the output of sed into cat.
             
    # Apply modifications
    while [[ -n "${MODLIST}" ]] && [[ "${MODLIST}" != "${TOKEN}" ]]
    do
      TOKEN="${MODLIST%%:*}" # Read first token (cut off all others)
      # NOTE: ${string%%substring} deletes longest match of $substring from back of $string.
      #   Since the elements are seperated by ":", the above deletes the first ":" and all
      #   that follows.       
      MODLIST="${MODLIST#*:}" # Cut off first token and save
      # NOTE: ${variable#pattern} removes the shortest match to the pattern from 
      #   the beginning of variable. So in the above the first ":" and everything before 
      #   it are removed.
      # NOTE: The second condition in the while loop above is because for the last token in 
      #   the MODLIST, token and MODLIST become the same.        
      NAME=$( echo ${TOKEN%%=*} | xargs ) # Cut off everything after '=' and trim extra spaces.
      # NOTE: "<string> | xargs" removes new lines and extra spaces between words in 
      #   string, leaving only one space between words in the output.          
      MSG='This namelist entry has been edited by the setup script.' 
      if [[ -n $( echo $TOKEN | grep "[\^$%\&/~*|]" ) ]]; then 
        echo "Invalid character in Token: $TOKEN"
        exit 1
      fi
      # NOTE: Token can contain "+" if using "/" as the delimiter.        
      if [[ -n $( grep "${NAME}" 'TEMPFILE' ) ]] # If NAME is in TEMPFILE.
      then sed -i "/${NAME}/ s/^\ *${NAME}\ *=\ *.*$/${TOKEN} ! ${MSG}/" 'TEMPFILE'
      # NOTE: The “i” option specifies that files are to be edited in-place (replace 
      #   input file), otherwise output is written to display.
      # NOTE: The /${NAME}/ above is so that the following replacing is only done in  
      #   the line with ${NAME}.
      # NOTE: We have to use '/' as delimiter, because we need '+' in namelist.
      else echo "${TOKEN} ! ${MSG}"  >> 'TEMPFILE' # Just append, if not already present.
      fi 
    done 
    
    # Close namelist group
    echo '/' >> 'TEMPFILE'; echo '' >> 'TEMPFILE'
    
    # Append namelist group
    cat 'TEMPFILE' >> "${FILENAME}"
    
    # Remove temprorary file
    rm 'TEMPFILE'
    
} 


# ===========================================================
# =============== Function to write preamble. ===============
# ===========================================================

function WRITEPREAMBLE () {
    DATE=$( date )
    # NOTE: "$( date )" generates date, e.g., "Thu 14 Oct 2021 10:55:25 AM EDT".
    echo "! This file was automatically generated on $DATE" >> "${1}"
    echo "! The namelist snippets from which this file was concatenated, can be found in" >> "${1}"
    echo "! ${NMLDIR}" >> "${1}"
    echo '' >> "${1}"
}


# ========================= Assemble WRF namelist =========================
NML='namelist.input'
rm -f "${NML}"; touch "${NML}" # Create WRF namelist file in current directory.
# Write preamble
WRITEPREAMBLE "${NML}"
# Namelist group &time_control
WRITENML 'time_control' "${TIME_CONTROL}" "${NML}" "${TIME_CONTROL_MOD}"
# Namelist group &diags
WRITENML 'diags' "${DIAGS}" "${NML}" "${DIAGS_MOD}"
# Namelist group &physics
WRITENML 'physics' "${PHYSICS}" "${NML}" "${PHYSICS_MOD}"
# Namelist group &noah_mp
WRITENML 'noah_mp' "${NOAH_MP}" "${NML}" "${NOAH_MP_MOD}"
# Namelist group &domains
WRITENML 'domains' "${DOMAINS}" "${NML}" "${DOMAINS_MOD}"
# Namelist group &fdda
WRITENML 'fdda' "${FDDA}" "${NML}" "${FDDA_MOD}"
# Namelist group &dynamics
WRITENML 'dynamics' "${DYNAMICS}" "${NML}" "${DYNAMICS_MOD}"
# Namelist group &bdy_control
WRITENML 'bdy_control' "${BDY_CONTROL}" "${NML}" "${BDY_CONTROL_MOD}"
# Namelist group &namelist_quilt
WRITENML 'namelist_quilt' "${NAMELIST_QUILT}" "${NML}" "${NAMELIST_QUILT_MOD}"

# ========================= Assemble WPS namelist =========================
NML='namelist.wps'
rm -f "${NML}"; touch "${NML}"  # Create WPS namelist file in current directory.
# Namelist group &share
WRITENML 'share' "${SHARE}" "${NML}" "${SHARE_MOD}"
# Namelist group &geogrid
WRITENML 'geogrid' "${GEOGRID}" "${NML}" "${GEOGRID_MOD}"
# Namelist group &metgrid
WRITENML 'metgrid' "${METGRID}" "${NML}" "${METGRID_MOD}"



































