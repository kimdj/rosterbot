#!/usr/bin/env bash
# rosterbot ~ Subroutines/Commands
# Copyright (c) 2017 David Kim
# This program is licensed under the "MIT License".
# Date of inception: 11/21/17

read nick chan msg      # Assign the 3 arguments to nick, chan and msg.

IFS=''                  # internal field separator; variable which defines the char(s)
                        # used to separate a pattern into tokens for some operations
                        # (i.e. space, tab, newline)

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BOT_NICK="$(grep -P "BOT_NICK=.*" ${DIR}/rosterbot.sh | cut -d '=' -f 2- | tr -d '"')"

if [ "${chan}" = "${BOT_NICK}" ] ; then chan="${nick}" ; fi

###############################################  Subroutines Begin  ###############################################

function has { $(echo "${1}" | grep -P "${2}" > /dev/null) ; }

function say { echo "PRIVMSG ${1} :${2}" ; }

function send {
    while read -r line; do                          # -r flag prevents backslash chars from acting as escape chars.
      currdate=$(date +%s%N)                         # Get the current date in nanoseconds (UNIX/POSIX/epoch time) since 1970-01-01 00:00:00 UTC (UNIX epoch).
      if [ "${prevdate}" -gt "${currdate}" ] ; then  # If 0.5 seconds hasn't elapsed since the last loop iteration, sleep. (i.e. force 0.5 sec send intervals).
        sleep $(bc -l <<< "(${prevdate} - ${currdate}) / ${nanos}")
        currdate=$(date +%s%N)
      fi
      prevdate=${currdate}+${interval}
      echo "-> ${1}"
      echo "${line}" >> ${BOT_NICK}.io
    done <<< "${1}"
}

function join_by { local IFS="${1}" ; shift ; echo "$*" ; }

function removeTmpSubroutine {
    if [ -f ./requester.tmp ] ; then rm requester.tmp ; fi
    if [ -f ./catLogin.tmp ] ; then rm catLogin.tmp ; fi
}

# This subroutine searches for a user in the CAT roster.

function whoisSubroutine {

    echo "${chan}" > requester.tmp                  # Store ${chan} in a file (requester.tmp is used during catbot's response handler).
    found=0                                         # Initialize found flag to 0 (incremented when a match is found).
    pathToStaffRoster="$(pwd)/whois/roster/staff.roster"
    rosterList=( $(pwd)/whois/roster/*.roster )
    arg=$(echo "${1}" | sed 's|[^-a-zA-Z0-9_! ]||g')                           # Whitelist user input.

    # Parse based on the CAT handle.    ----------------------------------------------------------------------------------

    handle=$(echo ${arg})                             # Allow whitespace within $handle.
    for file in "${rosterList[@]}" ; do             # Loop through each roster.

        # Look for a line containing the handle within the file.
        # Otherwise, continue on to the next file.
        # Note: regex anchors ^ (start-of-line) and $ (end-of-line) to mitigate unintented substring matches.
        handleLine=$(cat ${file} | grep -in "^handle: ${handle}$")                              # 129:handle: handle
        if [ ! ${handleLine} ] ; then
            continue                                                                            # If a match isn't found, move on to the next file.
        fi

        # Get the line number.
        handleLineNumber=$(echo ${handleLine} | sed -e 's/\([0-9]*\):.*/\1/')                   # 129

        # Get the Handle.
        handle=$(sed -n ${handleLineNumber}p ${file} | grep -Po '(?<=(handle: )).*')            # handle

        # Get the CAT username and OIT username.
        loginLineNumber="$((${handleLineNumber} - 2))"                                          # 127
        login=$(sed -n ${loginLineNumber}p ${file} | grep -Po '(?<=(login: )).*')               # $login refers to the user's cat username.
        echo "${login}" > catLogin.tmp                                                          # Store cat login in a temporary file.
        privmsg=$(echo '!cat2oit' ${login})                                                     # Send '!cat2oit username' to catbot.
        say "catbot" ${privmsg}                                                                 # Catbot's responses are handled in the
                                                                                                # "Handler for catbot's !cat2oit responses. (Whois)" section below.
                                                                                                # Note: catbot's responses will be forwarded to the user/chan
                                                                                                # AFTER this subroutine is completed.

        # Get the Subpath to the user's CAT chronicle page.
        # Note: subpath = cat username in most cases (2010 and onward).
        subpathLineNumber="$((${handleLineNumber} - 1))"                                       # 128
        subpath=$(sed -n ${subpathLineNumber}p ${file} | grep -Po '(?<=(subpath: )).*')        # username or subpath

        # Get the Real Name.
        realnameLineNumber="$((${handleLineNumber} + 1))"                                       # 130
        realname=$(sed -n ${realnameLineNumber}p ${file} | grep -Po '(?<=(realname: )).*')      # realname

        # Get the Title.
        titleLineNumber="$((${handleLineNumber} + 2))"                                          # 131
        title=$(sed -n ${titleLineNumber}p ${file} | grep -Po '(?<=(title: )).*')               # title

        # Get the Batch and Year.
        year=$(sed -n 1p ${file} | grep -Po '(?<=(year: )).*')                                  # 2017-2018
        batch=$(sed -n 2p ${file} | grep -Po '(?<=(batch: )).*')                                # Yet-To-Be-Named (YTBN)

        # Convert batch chars to mitigate excessive pinging/highlighting.
        batch1=$(echo ${batch} | sed 's/\(.* \).*/\1/')                                         # Delightfully-Resourceful-Advisers-Going-On-No-Sleep
        batch2=$(echo ${batch} | sed 's/.* \(.*\)/\1/' | tr 'aeiostl' '43105+|' | tr 'AEIOSTL' '43105+|')          # (DR4G0N5)
        batch=$(echo ${batch1}${batch2})

        # Send results back to the user/channel.
        # Note: if a user send a pm to rosterbot, ${chan} will be set to the user's nick.
        if [ ${title} ] ; then                                                                  # Case: user has a title
            say ${chan} "${handle}'s real name is ${realname}, ${handle} ${title}"
        else
            say ${chan} "${handle}'s real name is ${realname}"
        fi

        say ${chan} "${handle} belongs to the ${batch}, ${year}"

        if [ ${file} = "${pathToStaffRoster}" ] ; then                                          # Case: match was found in staff.roster
            say ${chan} "Try -> https://chronicle.cat.pdx.edu/projects/cat/wiki/${subpath}"
        else
            say ${chan} "Try -> https://chronicle.cat.pdx.edu/projects/braindump/wiki/${subpath}"
        fi

        found=$((${found} + 1))                             # Set found flag to 1.
    done

    # Parse based on cat login name.    ----------------------------------------------------------------------------------

    if [ "${found}" -eq "0" ] ; then                        # If a Handle match was already found, skip this if block.
        # login=$(echo ${arg} | sed 's/ .*//')              # Just capture the first word.
        login=$(echo ${arg})

        arr=()                                              # Declare an empty array (list of entries found).
        for file in "${rosterList[@]}" ; do                 # Loop through each roster.

            # Look for a line containing the cat login within the file.
            # Otherwise, continue on to the next file.
            # Note: regex anchors ^ (start-of-line) and $ (end-of-line) to mitigate unintented substring matches.
            loginLine=$(cat ${file} | grep -in "^login: ${login}$")                                 # 129:login: login
            if [ ! ${loginLine} ] ; then
                continue
            fi

            # Get the line number.
            loginLineNumber=$(echo ${loginLine} | sed -e 's/\([0-9]*\):.*/\1/')                     # 129

            # Get the Handle.
            handleLineNumber="$((${loginLineNumber} + 2))"                                          # 128
            handle=$(sed -n ${handleLineNumber}p ${file} | grep -Po '(?<=(handle: )).*')            # username
            handle=$( echo ${handle} | sed 's| |%20|g')                                             # Temporarily URL-encode whitespaces.

            # Only append to arr if Handle exists for the user.
            if [ ${handle} ] ; then
                arr+=" ${handle}"
                found=$((${found} + 1))                     # Set found flag to 1.
            fi
        done

        uniqArr=$(echo "${arr[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' ' | sed 's| $||')                    # Remove duplicate Handles in arr (get unique array values only)
        sep=' ~ '                                                                                           # Define the separator between Handles
        payload=$( echo ${uniqArr[@]} | sed "s/ /${sep}/g" | sed "s/^${sep}//" | sed 's/%20/ /g')           # e.g. Superman ~ Iron Man ~ Thor

        say ${chan} "${payload}"
    fi

    # Parse based on real name.    ----------------------------------------------------------------------------------

    if [ "${found}" -eq "0" ] ; then                                # If a Handle match or Login match was already found, skip this if block.
        # realname=$(echo ${arg} | sed 's/\(.* .*\) .*//')            # Just capture the first word.
        realname=$(echo ${arg})

        arr=()                                                      # Declare an empty array (list of entries found).
        for file in "${rosterList[@]}" ; do                         # Loop through each roster.

            # Look for a line containing the real name within the file.
            # Otherwise, continue on to the next file.
            # Note: regex anchors ^ (start-of-line) and $ (end-of-line) to mitigate unintented substring matches.
            realnameLine=$(cat ${file} | grep -in "^realname:" | grep -in " ${realname} \| ${realname}$" | sed -e 's/\([0-9]*\)://')          # 101:realname: realname ... (0, 1, or more lines)
            if [ ! ${realnameLine} ] ; then
                continue
            fi

            while read -r line ; do                                                                     # For each found entry...
                realnameLineNumber=$(echo ${line} | sed -e 's/\([0-9]*\):.*/\1/')                       # 101

                # Get the Handle.
                handleLineNumber="$((${realnameLineNumber} - 1))"                                       # 100
                handle=$(sed -n ${handleLineNumber}p ${file} | grep -Po '(?<=(handle: )).*')            # handle
                handle=$( echo ${handle} | sed 's| |%20|g')                                             # Temporarily convert spaces to URL-encoded char code within Handles

                # Only append to arr if Handle exists for the user.
                if [ ${handle} ] ; then
                    arr+=" ${handle}"
                    found=$((${found} + 1))             # Set found flag to 1.
                fi
            done <<< "${realnameLine}"

        done

        uniqArr=$(echo "${arr[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' ' | sed 's| $||')                    # Remove duplicate Handles in arr (get unique array values only)
        sep=' ~ '                                                                                           # Define the separator between Handles
        payload=$( echo ${uniqArr[@]} | sed "s/ /${sep}/g" | sed "s/^${sep}//" | sed 's/%20/ /g')           # e.g. Superman ~ Iron Man ~ Thor

        say ${chan} "${payload}"

        # Finally, if a match was not found, see if catbot's !oit2cat yields any results.
        # Catbot's responses are handled in the "Handler for catbot's !oit2cat responses. (Whois)" section below.
        if [ "${found}" -eq "0" ] ; then
            privmsg=$(echo '!oit2cat' ${arg})                                     # Send '!oit2cat username' to catbot.
            say "catbot" ${privmsg}
        fi
    fi
}

# This subroutine handles the case where catbot's !oit2cat yields a result.

function whoisSubroutine2 {

    # Parse based on real name from catbot's !oit2cat response.

    dest=${1}
    found=0                                                                     # Initialize found flag to 0.
    rosterList=( $(pwd)/whois/roster/*.roster )

    arr=()
    for file in "${rosterList[@]}" ; do                                         # Loop through each roster.

        # Look for a line containing the real name within the file.
        # Otherwise, continue on to the next file.
        # Note: regex anchors ^ (start-of-line) and $ (end-of-line) to mitigate unintented substring matches.
        realnameLine=$(cat ${file} | grep -in "^realname:" | grep -in " ${realname} \| ${realname}$" | sed -e 's/\([0-9]*\)://')          # 129:realname: realname
        if [ ${realnameLine} ] ; then
            realnameLineNumber=$(echo ${realnameLine} | sed -e 's/\([0-9]*\):.*/\1/')         # 130
        else
            continue
        fi

        # Get the Handle.
        handleLineNumber="$((${realnameLineNumber} - 1))"                                     # 129
        handle=$(sed -n ${handleLineNumber}p ${file} | grep -Po '(?<=(handle: )).*')          # handle
        handle=$( echo ${handle} | sed 's| |%20|g')                                           # Temporarily convert spaces to URL-encoded char code within Handles

        # Only append to arr if Handle exists for the user.
        if [ ${handle} ] ; then
            arr+=" ${handle}"
            found=$((${found} + 1))             # Set found flag to 1.
        fi

    done

    uniqArr=$(echo "${arr[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' ' | sed 's| $||')                    # Remove duplicate Handles in arr (get unique array values only)
    sep=' ~ '                                                                                           # Define the separator between Handles
    payload=$( echo ${uniqArr[@]} | sed "s/ /${sep}/g" | sed "s/^${sep}//" | sed 's/%20/ /g')           # e.g. Superman ~ Iron Man ~ Thor

    say ${dest} "${payload}"

    # If a match was still not found after searching through all criteria,
    # it is very likely the user is not in the CAT roster.
    if [ "${found}" -eq "0" ] ; then
        say ${dest} "User not found in the CAT Roster."
    fi
}

# This subroutine searches based on basic regex (BRE) pattern matching.
# Note: Extended regular expression engine can be turned on. Just uncomment the line below.

function whoisRegexSubroutine {

    echo "${chan}" > requester.tmp                  # Store ${chan} in a file (requester.tmp is used during catbot's response handler).
    found=0                                         # Initialize found flag to 0 (incremented when a match is found).
    pathToStaffRoster="$(pwd)/whois/roster/staff.roster"
    rosterList=( $(pwd)/whois/roster/*.roster )
    arg=$(echo "${1}")
    # arg=$(echo "${1}" | sed 's|[^-a-zA-Z0-9_ ]||g')                           # Whitelist user input.
    arr=()                                          # ${arr} contains a space-separated found matches (list of Handles).
    count=0

    # Parse based on the CAT handle.    ----------------------------------------------------------------------------------

    pattern=$(echo ${arg} | sed 's/^\^//' | sed 's/\$$//')                          # Regex pattern.  If it exists, remove ^ and $ anchors because it is already in handleLines below.
    for file in "${rosterList[@]}" ; do             # Loop through each roster.

        # Look for a line containing the handle within the file.
        # Otherwise, continue on to the next file.
        # Note: regex anchors ^ (start-of-line) and $ (end-of-line) to mitigate unintented substring matches.
        # handleLines=$(cat ${file} -n | grep -w "^[[:space:]]*[0-9]*[[:space:]]*handle: ${pattern}")    # Match based on BRE, --word-regexp.
        handleLines=$(cat ${file} -n | egrep "^[[:space:]]*[0-9]*[[:space:]]*handle: ${pattern}$")    # Match based on ERE, --word-regexp.
        totalNumFound=$(echo -n ${handleLines} | wc -l)                                             # Note: echo's -n flag prevents output of the trailing newline
        count=$(( count + totalNumFound ))

        if [ "${count}" -gt 20 ] ; then  # Limited to 20 matches.
            say ${chan} "Please narrow your search."
            found=-1                                # Represents too many matches found (i.e. over 20 matches were found).
            break
        fi

        if [ ! ${handleLines} ] ; then
            continue                                                                            # If a match isn't found, move on to the next file.
        fi

        # For each handle in handleLines, append to arr.
        while read -r line ; do
            arr+=" $(echo ${line} | sed 's/.*handle: \(.*\)/\1/' | sed 's| |%20|g')"            # Temporarily URL-encode whitespaces.
        done <<< "${handleLines}"

        found=$((${found} + 1))                             # Set found flag to 1.
    done

    # Display the results.
    if [ ${found} -gt 0 ] ; then 
        uniqArr=$(echo "${arr[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' ' | sed 's| $||')                    # Remove duplicate Handles in arr (get unique array values only)
        sep=' ~ '                                                                                           # Define the separator between Handles
        payload=$( echo ${uniqArr[@]} | sed "s/ /${sep}/g" | sed "s/^${sep}//" | sed 's/%20/ /g')           # e.g. Superman ~ Iron Man ~ Thor

        say ${chan} "${payload}"
    fi

    # If a match was not found..
    if [ ${found} -eq 0 ] ; then
        say ${chan} "User not found in the CAT Roster."
    fi
}

# Modify or clear a user's title.

function titleSubroutine {
    found=0                                                 # Initialize found flag to 0.
    arg=${1}

    handle=$(echo ${arg} | sed 's/ .*//')                     # Just capture the first word.
    newTitle=$(echo ${arg} | cut -d " " -f2-)                 # Capture the remaining words.
    rosterList=( $(pwd)/whois/roster/*.roster )

    if [ ! ${handle} ] ; then
        say ${chan} "input error"
        return 1
    fi

    for file in "${rosterList[@]}" ; do                     # Loop through each roster.

        # Skip the staff roster.  (i.e. only titles within batch rosters can be edited)
        if [ $(echo ${file} | grep staff) ] ; then
            continue
        fi

        # Look for a line containing the Handle within the file.
        # Otherwise, continue on to the next file.
        # Note: regex anchors ^ (start-of-line) and $ (end-of-line) to mitigate unintented substring matches.
        handleLine=$(cat ${file} | grep -in "^handle: ${handle}$")                              # 129:handle: handle
        if [ ${handleLine} ] ; then
            handleLineNumber=$(echo ${handleLine} | sed -e 's/\([0-9]*\):.*/\1/')               # 129
        else
            continue
        fi

        # Modify the Title.
        titleLineNumber="$((${handleLineNumber} + 2))"
        oldTitle=$(sed -n ${titleLineNumber}p ${file} | grep -Po '(?<=(title: )).*')            # title

        if [[ ${newTitle} = ${handle} ]] ; then                                                # clear title
            newTitle=''
        fi

        if [ -n "${newTitle}" ] ; then
            say ${chan} "${handle}'s title was modified"
            $(sed -i "${titleLineNumber}s|.*|title: ${newTitle}|" ${file})                      # replace title with new title
            currentTitle=$(sed -n ${titleLineNumber}p ${file} | grep -Po '(?<=(title: )).*')    # title
        else
            say ${chan} "${handle}'s title was cleared"
            $(sed -i "${titleLineNumber}s/.*/title: /" ${file})                                 # clear title
        fi

        found=$((${found} + 1))             # Set found flag to 1.
    done

    # If a match was not found..
    if [ ${found} -lt 1 ] ; then
        say ${chan} "User not found in the CAT Roster."
    fi
}

# This subroutine searches for a user in the CAT roster.

function whoSubroutine {

    echo "${chan}" > requester.tmp                  # Store ${chan} in a file (requester.tmp is used during catbot's response handler).
    found=0                                         # Initialize found flag to 0 (incremented when a match is found).
    pathToStaffRoster="$(pwd)/whois/roster/staff.roster"
    rosterList=( $(pwd)/whois/roster/*.roster )
    arg=$(echo "${1}" | sed 's|[^-a-zA-Z0-9_! ]||g')                           # Whitelist user input.

    # Parse based on the CAT handle.    ----------------------------------------------------------------------------------

    handle=$(echo ${arg})                             # Allow whitespace within $handle.
    for file in "${rosterList[@]}" ; do             # Loop through each roster.

        # Look for a line containing the handle within the file.
        # Otherwise, continue on to the next file.
        # Note: regex anchors ^ (start-of-line) and $ (end-of-line) to mitigate unintented substring matches.
        handleLine=$(cat ${file} | grep -in "^handle: ${handle}$")                              # 129:handle: handle
        if [ ! ${handleLine} ] ; then
            continue                                                                            # If a match isn't found, move on to the next file.
        fi

        # Get the line number.
        handleLineNumber=$(echo ${handleLine} | sed -e 's/\([0-9]*\):.*/\1/')                   # 129

        # Get the Handle.
        handle=$(sed -n ${handleLineNumber}p ${file} | grep -Po '(?<=(handle: )).*')            # handle

        # Get the CAT username and OIT username.
        loginLineNumber="$((${handleLineNumber} - 2))"                                          # 127
        login=$(sed -n ${loginLineNumber}p ${file} | grep -Po '(?<=(login: )).*')               # $login refers to the user's cat username.
        echo "${login}" > catLogin.tmp                                                          # Store cat login in a temporary file.
        privmsg=$(echo '!cat2oit' ${login})                                                     # Send '!cat2oit username' to catbot.
        say "catbot" ${privmsg}                                                                 # Catbot's responses are handled in the
                                                                                                # "Handler for catbot's !cat2oit responses. (Whois)" section below.

        # Get the Subpath to the user's CAT chronicle page.
        # Note: subpath = cat username in most cases (2010 and onward).
        subpathLineNumber="$((${handleLineNumber} - 1))"                                       # 128
        subpath=$(sed -n ${subpathLineNumber}p ${file} | grep -Po '(?<=(subpath: )).*')        # username or subpath

        # Get the Real Name.
        realnameLineNumber="$((${handleLineNumber} + 1))"                                       # 130
        realname=$(sed -n ${realnameLineNumber}p ${file} | grep -Po '(?<=(realname: )).*')      # realname

        # Get the Title.
        titleLineNumber="$((${handleLineNumber} + 2))"                                          # 131
        title=$(sed -n ${titleLineNumber}p ${file} | grep -Po '(?<=(title: )).*')               # title

        # Get the Batch and Year.
        year=$(sed -n 1p ${file} | grep -Po '(?<=(year: )).*')                                  # 2017-2018
        batch=$(sed -n 2p ${file} | grep -Po '(?<=(batch: )).*')                                # Yet-To-Be-Named (YTBN)

        # Convert batch chars to mitigate excessive pinging/highlighting.
        batch1=$(echo ${batch} | sed 's/\(.* \).*/\1/')                                         # Delightfully-Resourceful-Advisers-Going-On-No-Sleep
        batch2=$(echo ${batch} | sed 's/.* \(.*\)/\1/' | tr 'aeiostl' '43105+|' | tr 'AEIOSTL' '43105+|')          # (DR4G0N5)
        batch=$(echo ${batch1}${batch2})

        # # Send results back to the user/channel.
        # # Note: if a user pm's rosterbot, ${chan} will be set to the user's nick
        # if [ ${file} = "${pathToStaffRoster}" ] ; then                                         # Case: match was found in staff.roster
        #     say ${chan} "Try -> https://chronicle.cat.pdx.edu/projects/cat/wiki/${subpath}"
        # else
        #     say ${chan} "Try -> https://chronicle.cat.pdx.edu/projects/braindump/wiki/${subpath}"
        # fi

        # if [ ${title} ] ; then                                                                  # Case: user has a title
        #     say ${chan} "${handle}'s real name is ${realname} | ${handle} ${title}"
        # else
        #     say ${chan} "${handle}'s real name is ${realname}"
        # fi

        # say ${chan} "${handle} belongs to the ${batch}, ${year}"

        found=$((${found} + 1))                             # Set found flag to 1.
    done

    # Parse based on cat login name.    ----------------------------------------------------------------------------------

    if [ "${found}" -eq "0" ] ; then                        # If a Handle match was already found, skip this if block.
        # login=$(echo ${arg} | sed 's/ .*//')                # Just capture the first word.
        login=$(echo ${arg})

        arr=()                                              # Declare an empty array (list of entries found).
        for file in "${rosterList[@]}" ; do                 # Loop through each roster.

            # Look for a line containing the cat login within the file.
            # Otherwise, continue on to the next file.
            # Note: regex anchors ^ (start-of-line) and $ (end-of-line) to mitigate unintented substring matches.
            loginLine=$(cat ${file} | grep -in "^login: ${login}$")                                 # 129:login: login
            if [ ! ${loginLine} ] ; then
                continue
            fi

            # Get the line number.
            loginLineNumber=$(echo ${loginLine} | sed -e 's/\([0-9]*\):.*/\1/')                     # 129

            # Get the Handle.
            handleLineNumber="$((${loginLineNumber} + 2))"                                          # 128
            handle=$(sed -n ${handleLineNumber}p ${file} | grep -Po '(?<=(handle: )).*')            # username
            handle=$( echo ${handle} | sed 's| |%20|g')                                             # Temporarily URL-encode whitespaces.

            # Only append to arr if Handle exists for the user.
            if [ ${handle} ] ; then
                arr+=" ${handle}"
                found=$((${found} + 1))                     # Set found flag to 1.
            fi
        done

        uniqArr=$(echo "${arr[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' ' | sed 's| $||')                    # Remove duplicate Handles in arr (get unique array values only)
        sep=' ~ '                                                                                           # Define the separator between Handles
        payload=$( echo ${uniqArr[@]} | sed "s/ /${sep}/g" | sed "s/^${sep}//" | sed 's/%20/ /g')           # e.g. Superman ~ Iron Man ~ Thor
# say _sharp "in cat login"
        say ${chan} "${payload}"
    fi

    # Parse based on real name.    ----------------------------------------------------------------------------------

    if [ "${found}" -eq "0" ] ; then                                # If a Handle match or Login match was already found, skip this if block.
        # realname=$(echo ${arg} | sed 's/\(.* .*\) .*//')            # Just capture the first word.
        realname=$(echo ${arg})

        arr=()                                                      # Declare an empty array (list of entries found).
        for file in "${rosterList[@]}" ; do                         # Loop through each roster.

            # Look for a line containing the real name within the file.
            # Otherwise, continue on to the next file.
            # Note: regex anchors ^ (start-of-line) and $ (end-of-line) to mitigate unintented substring matches.
            realnameLine=$(cat ${file} | grep -in "^realname:" | grep -in " ${realname} \| ${realname}$" | sed -e 's/\([0-9]*\)://')          # 101:realname: realname ... (0, 1, or more lines)
            if [ ! ${realnameLine} ] ; then
                continue
            fi

            while read -r line ; do                                                                     # For each found entry...
                realnameLineNumber=$(echo ${line} | sed -e 's/\([0-9]*\):.*/\1/')                       # 101

                # Get the Handle.
                handleLineNumber="$((${realnameLineNumber} - 1))"                                       # 100
                handle=$(sed -n ${handleLineNumber}p ${file} | grep -Po '(?<=(handle: )).*')            # handle
                handle=$( echo ${handle} | sed 's| |%20|g')                                             # Temporarily convert spaces to URL-encoded char code within Handles

                # Only append to arr if Handle exists for the user.
                if [ ${handle} ] ; then
                    arr+=" ${handle}"
                    found=$((${found} + 1))             # Set found flag to 1.
                fi
            done <<< "${realnameLine}"

        done

        uniqArr=$(echo "${arr[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' ' | sed 's| $||')                    # Remove duplicate Handles in arr (get unique array values only)
        sep=' ~ '                                                                                           # Define the separator between Handles
        payload=$( echo ${uniqArr[@]} | sed "s/ /${sep}/g" | sed "s/^${sep}//" | sed 's/%20/ /g')           # e.g. Superman ~ Iron Man ~ Thor
# say _sharp "in real name"
        say ${chan} "${payload}"

        # Finally, if a match was not found, see if catbot's !oit2cat yields any results.
        # Catbot's responses are handled in the "Handler for catbot's !oit2cat responses. (Whois)" section below.
        if [ "${found}" -eq "0" ] ; then
            privmsg=$(echo '!oit2cat' ${arg})                                     # Send '!oit2cat username' to catbot.
            say "catbot" ${privmsg}
        fi
    fi
}

# This subroutine checks to see if two files: 'whodat.handle.tmp' and 'whodat.clue.tmp'.
# If they exist, rosterbot sends the clue to the irc channel.
# Otherwise, a Handle is randomly selected from the whois/roster/*.roster (not including staff.roster).
# Then, the Handle (as an anagram, or masked) along with the batch + year is sent to the
# the irc channel.

function whodatSubroutine {

    if [ -f whodat.handle.tmp ] && [ -f whodat.clue.tmp ] ; then

        # Send the clue.
        say ${chan} "$(cat whodat.clue.tmp)"
        echo "correctAnswer -> $(cat whodat.handle.tmp)"

    else

        # # Randomly select a Handle from the entire CAT roster.
        # handle=$( cat $(pwd)/whois/roster/*.roster | egrep 'handle: [^ ]' | sed -e 's|handle: ||' | sort -R | head -n 1 )

        # Randomly select a Handle from 2014-2017 CAT rosters.
        handle=$( cat $(pwd)/whois/roster/2017*.roster $(pwd)/whois/roster/2016*.roster $(pwd)/whois/roster/2015*.roster $(pwd)/whois/roster/2014*.roster | egrep 'handle: [^ ]' | sed -e 's|handle: ||' | sort -R | head -n 1 )
        while [ ! $handle ] ; do
            handle=$( cat $(pwd)/whois/roster/2017*.roster $(pwd)/whois/roster/2016*.roster $(pwd)/whois/roster/2015*.roster $(pwd)/whois/roster/2014*.roster | egrep 'handle: [^ ]' | sed -e 's|handle: ||' | sort -R | head -n 1 )
        done

        # Save the Handle to a file.
        echo ${handle} > whodat.handle.tmp

        # Get the info to be used as the clue.
        rosterList=( $(pwd)/whois/roster/*.roster )
        for file in "${rosterList[@]}" ; do                     # Loop through each roster.

            # Skip the staff roster.  (i.e. only titles within batch rosters can be edited)
            if [ $(echo ${file} | grep staff) ] ; then
                continue
            fi

            # Look for a line containing the Handle within the file.
            # Otherwise, continue on to the next file.
            # Note: regex anchors ^ (start-of-line) and $ (end-of-line) to mitigate unintented substring matches.
            handleLine=$(cat ${file} | grep -in "^handle: ${handle}$")                              # 129:handle: handle
            if [ ${handleLine} ] ; then
                handleLineNumber=$(echo ${handleLine} | sed -e 's/\([0-9]*\):.*/\1/')               # 129
            else
                continue
            fi

            # # Get the info.
            # whateverNumber="$((${handleLineNumber} + 0))"
            # whatever=$(sed -n ${whateverLineNumber}p ${file} | grep -Po '(?<=(whatever: )).*')    # whatever

            # Get the Batch and Year.
            year=$(sed -n 1p ${file} | grep -Po '(?<=(year: )).*')                                  # 2017-2018
            batch=$(sed -n 2p ${file} | grep -Po '(?<=(batch: )).*')                                # Yet-To-Be-Named (YTBN)

            # Save the clue in a file.
            rand=$(shuf -i 1-2 -n 1) # Get random number between 1-2.
            case "${rand}" in

            # Scramble the handle.  (e.g. _sharp  -> ph_ras)
            1)  scramble=$(echo ${handle} | sed 's/./&\n/g' | shuf | tr -d "\n")
                while [[ "${scramble}" = "${handle}" ]] ; do                                                               # Make sure the handle is scrambled.
                    scramble=$(echo ${handle} | sed 's/./&\n/g' | shuf | tr -d "\n")
                done

                # echo ".oO ( ${scramble} was a ${batch}, ${year} )" > whodat.clue.tmp                                      # Save the clue in a file.
                batch1=$(echo ${batch} | sed 's/\(.* \).*/\1/')                                                             # Delightfully-Resourceful-Advisers-Going-On-No-Sleep
                batch2=$(echo ${batch} | sed 's/.* \(.*\)/\1/' | tr 'aeiostl' '43105+|' | tr 'AEIOSTL' '43105+|')           # (DR4G0N5)
                batch=$(echo ${batch1}${batch2})
                echo ".oO ( ${scramble} was a ${batch}, ${year} )" > whodat.clue.tmp                                        # Save the clue in a file.

                ;;

            # Randomly mask characters.  (e.g. _sharp  ->  _&ha*p)
            2)  masked=${handle}
                while read -r line; do
                    index=${line}
                    masked=$(echo "${masked}" | sed s/./*/${index})
                done <<< "$( shuf -i 1-${#handle} -n $(( ${#handle} / 2)) )"

                # echo ".oO ( ${masked} was a ${batch}, ${year} )" > whodat.clue.tmp                                        # Save the clue in a file.
                batch1=$(echo ${batch} | sed 's/\(.* \).*/\1/')                                                             # Delightfully-Resourceful-Advisers-Going-On-No-Sleep
                batch2=$(echo ${batch} | sed 's/.* \(.*\)/\1/' | tr 'aeiostl' '43105+|' | tr 'AEIOSTL' '43105+|')           # (DR4G0N5)
                batch=$(echo ${batch1}${batch2})
                echo ".oO ( ${masked} was a ${batch}, ${year} )" > whodat.clue.tmp                                          # Save the clue in a file.
                ;;

            *) echo "Error"
               ;;

            esac

            # Send the clue.
            say ${chan} "$(cat whodat.clue.tmp)"
            echo "correctAnswer -> $(cat whodat.handle.tmp)"

            # Break out of the for loop.
            break
        done
    fi
}

# This subroutine looks up a Handle's whodat points.

function whodatSubroutine2 {

    handle=${1}                                             # Assign the first argument to $handle.
    found=0                                                 # Initialize found flag to 0.

    rosterList=( $(pwd)/whois/roster/*.roster )
    for file in "${rosterList[@]}" ; do                     # Loop through each roster.
        
        # Skip the staff roster.  (i.e. only titles within batch rosters can be edited)
        if [ $(echo ${file} | grep staff) ] ; then
            continue
        fi

        # Look for a line containing the Handle within the file.
        # Otherwise, continue on to the next file.
        # Note: regex anchors ^ (start-of-line) and $ (end-of-line) to mitigate unintented substring matches.
        handleLine=$(cat ${file} | grep -in "^handle: ${handle}$")                              # 129:handle: handle
        if [ ${handleLine} ] ; then
            handleLineNumber=$(echo ${handleLine} | sed -e 's/\([0-9]*\):.*/\1/')               # 129
        else
            continue
        fi

        # Get the user's points.
        whodatPointsLineNumber="$((${handleLineNumber} + 4))"                                   # 133
        points=$(sed -n ${whodatPointsLineNumber}p ${file} | grep -Po '(?<=(whodatPoints: )).*')            # 0

        say ${chan} "${handle} has ${points} points."                                           # Send the message.

        found=$((${found} + 1))                                                                 # Set found flag to 1.

        break                                                                                   # Once found, break out of the for loop.
    done

    if [ "${found}" -eq "0" ] ; then                                                            # If a match was not found..
        say ${chan} "who dat?"
    fi
}

# This subroutine checks to see if a user's answer is correct.

function isdatSubroutine {

    handle=${nick}
    shopt -s nocasematch                                            # Turn off case-sensitive pattern matching.

    if [ -f whodat.handle.tmp ] ; then
        userAnswer=${1}
        correctAnswer="$(cat whodat.handle.tmp)"

        # Check if the answer is correct.  If correct, give the user +3 points.
        if [ "${userAnswer^^}" = "${correctAnswer^^}" ] ; then  # ${str,,} converts str to lowercase, ${str^^} converts str to uppercase

            # Increment whodatPoints.
            rosterList=( $(pwd)/whois/roster/*.roster )
            for file in "${rosterList[@]}" ; do                     # Loop through each roster.
                
                # Skip the staff roster.  (i.e. only titles within batch rosters can be edited)
                if [ $(echo ${file} | grep staff) ] ; then
                    continue
                fi

                # Look for a line containing the Handle within the file.
                # Otherwise, continue on to the next file.
                # Note: regex anchors ^ (start-of-line) and $ (end-of-line) to mitigate unintented substring matches.
                handleLine=$(cat ${file} | grep -in "^handle: ${handle}$")                              # 129:handle: handle
                if [ ${handleLine} ] ; then
                    handleLineNumber=$(echo ${handleLine} | sed -e 's/\([0-9]*\):.*/\1/')               # 129
                else
                    continue
                fi

                # Increment the user's points.
                whodatPointsLineNumber="$((${handleLineNumber} + 4))"
                points=$(sed -n ${whodatPointsLineNumber}p ${file} | grep -Po '(?<=(whodatPoints: )).*')            # 0
                points=$((points + 3))                                                                              # 1

                sed -i "${whodatPointsLineNumber}s|.*|whodatPoints\: ${points}|g" ${file}                           # whodatPoints: 1

                replySubroutine "correct" "${handle}" "${points}"

                # Break out of the for loop.
                break
            done

            rm whodat.handle.tmp whodat.clue.tmp                # Remove the tmp files.
        else
          
            # Decrement user's whodatPoints.
            rosterList=( $(pwd)/whois/roster/*.roster )
            for file in "${rosterList[@]}" ; do                     # Loop through each roster.
                
                # Skip the staff roster.  (i.e. only titles within batch rosters can be edited)
                if [ $(echo ${file} | grep staff) ] ; then
                    continue
                fi

                # Look for a line containing the Handle within the file.
                # Otherwise, continue on to the next file.
                # Note: regex anchors ^ (start-of-line) and $ (end-of-line) to mitigate unintented substring matches.
                handleLine=$(cat ${file} | grep -in "^handle: ${handle}$")                              # 129:handle: handle
                if [ ${handleLine} ] ; then
                    handleLineNumber=$(echo ${handleLine} | sed -e 's/\([0-9]*\):.*/\1/')               # 129
                else
                    continue
                fi

                # Decrement the user's points.
                whodatPointsLineNumber="$((${handleLineNumber} + 4))"
                points=$(sed -n ${whodatPointsLineNumber}p ${file} | grep -Po '(?<=(whodatPoints: )).*')            # 0
                points=$((points - 1))                                                                              # 1

                sed -i "${whodatPointsLineNumber}s|.*|whodatPoints\: ${points}|g" ${file}                           # whodatPoints: 1

                replySubroutine "wrong" "${handle}" "${points}"

                # Break out of the for loop.
                break
            done
        fi
    else
        say ${chan} 'Try !whodat'
    fi
    shopt -u nocasematch                                        # Turn on case-sensitive pattern matching.
}

# This subroutine allows for the user to give up and get the answer for a 1 point penalty.

function dunnoSubroutine {

    handle=${nick}
    shopt -s nocasematch                                            # Turn off case-sensitive pattern matching.

    if [ -f whodat.handle.tmp ] ; then
        correctAnswer="$(cat whodat.handle.tmp)"

        # Decrement whodatPoints by 5.
        rosterList=( $(pwd)/whois/roster/*.roster )
        for file in "${rosterList[@]}" ; do                     # Loop through each roster.
            
            # Skip the staff roster.  (i.e. only titles within batch rosters can be edited)
            if [ $(echo ${file} | grep staff) ] ; then
                continue
            fi

            # Look for a line containing the Handle within the file.
            # Otherwise, continue on to the next file.
            # Note: regex anchors ^ (start-of-line) and $ (end-of-line) to mitigate unintented substring matches.
            handleLine=$(cat ${file} | grep -in "^handle: ${handle}$")                              # 129:handle: handle
            if [ ${handleLine} ] ; then
                handleLineNumber=$(echo ${handleLine} | sed -e 's/\([0-9]*\):.*/\1/')               # 129
            else
                continue
            fi

            # Decrement the user's points by 5.
            whodatPointsLineNumber="$((${handleLineNumber} + 4))"
            points=$(sed -n ${whodatPointsLineNumber}p ${file} | grep -Po '(?<=(whodatPoints: )).*')            # 0
            points=$((points - 5))                                                                              # -1

            sed -i "${whodatPointsLineNumber}s|.*|whodatPoints\: ${points}|g" ${file}                           # whodatPoints: -1

            replySubroutine "dunno" "${handle}" "${points}" "${correctAnswer}"

            # Break out of the for loop.
            break
        done

        rm whodat.handle.tmp whodat.clue.tmp                # Remove the tmp files.
    else
        say ${chan} 'Try !whodat'
    fi
}

# This subroutine tells the user whether their !isdat answer was right or wrong.

function replySubroutine {

    handle=${2}
    points=${3}
    correctAnswer=${4}

    if [ "${1}" = "correct" ] ; then
        case "$(shuf -i 0-5 -n 1)" in           # Generate a random number between 0-5, then execute the following case.
            0)  say ${chan} "Correct! ${handle} now has ${points} points."
                ;;
            1)  say ${chan} "Bingo! ${handle} now has ${points} points."
                ;;
            2)  say ${chan} "Right! ${handle} now has ${points} points."
                ;;
            3)  say ${chan} "You got a whodat point! ${handle} now has ${points} points."
                ;;
            4)  say ${chan} "How'd you know?! ${handle} now has ${points} points."
                ;;
            5)  say ${chan} "You got it! ${handle} now has ${points} points."
                ;;
            *)  echo "Error"
                ;;
        esac

    elif [ "${1}" = "wrong" ] ; then
        case "$(shuf -i 0-5 -n 1)" in           # Generate a random number between 0-5, then execute the following case.
            0)  say ${chan} "Wrong... ${handle} now has ${points} points."
                ;;
            1)  say ${chan} "Try again... ${handle} now has ${points} points."
                ;;
            2)  say ${chan} "Erroneous... ${handle} now has ${points} points."
                ;;
            3)  say ${chan} "I admire your effort, really... ${handle} now has ${points} points."
                ;;
            4)  say ${chan} "You'll get it next time... ${handle} now has ${points} points."
                ;;
            5)  say ${chan} "Nice try ~:D ${handle} now has ${points} points."
                ;;
            *)  echo "Error"
                ;;
        esac

    elif [ "${1}" = "dunno" ] ; then
        case "$(shuf -i 0-5 -n 1)" in           # Generate a random number between 0-5, then execute the following case.
            0)  say ${chan} "Everyone has their limits, I suppose. The answer is ${correctAnswer}. ${handle} now has ${points} points"
                ;;
            1)  say ${chan} "You'll do better next time. The answer is ${correctAnswer}. ${handle} now has ${points} points"
                ;;
            2)  say ${chan} "Way to take one for the team. The answer is ${correctAnswer}. ${handle} now has ${points} points"
                ;;
            3)  say ${chan} "Had enough, I see. The answer is ${correctAnswer}. ${handle} now has ${points} points"
                ;;
            4)  say ${chan} "When in doubt, Chron it out. The answer is ${correctAnswer}. ${handle} now has ${points} points"
                ;;
            5)  say ${chan} "You tried your best. The answer is ${correctAnswer}. ${handle} now has ${points} points"
                ;;
            *)  echo "Error"
                ;;
        esac

    fi

}

# This subroutine finds users who have the highest and lowest whodat points.

function whodaSubroutine {

    if [ "${1}" = "highest" ] ; then                           # Get the user with the highest whodat points.

        # Find the user with the highest whodatPoints.
        highestPoints=0
        highestUser=''
        rosterList=( $(pwd)/whois/roster/*.roster )
        for file in "${rosterList[@]}" ; do                     # Loop through each roster.

            # Skip the staff roster.  (i.e. only titles within batch rosters can be edited)
            if [ $(echo ${file} | grep staff) ] ; then
                continue
            fi

            topLine=$(cat ${file} -n | grep whodatPoints | sort -k3 -n -r | sed -n 1p)
            whodatPointsLineNumber=$(echo ${topLine} | sed 's/whodat.*//' | sed 's/ //g')
            points=$(sed -n ${whodatPointsLineNumber}p ${file} | grep -Po '(?<=(whodatPoints: )).*')            # Handle
            handleLineNumber="$((${whodatPointsLineNumber} - 4))"
            handle=$(sed -n ${handleLineNumber}p ${file} | grep -Po '(?<=(handle: )).*')            # Handle

            if [ "${points}" -gt "${highestPoints}" ] ; then
                highestPoints=${points}
                highestUser=${handle}
            fi
        done

        say ${chan} "${highestUser} is on top with ${highestPoints} points!"
    else

        # Find the user with the lowest whodatPoints.
        lowestPoints=0
        lowestUser=''
        rosterList=( $(pwd)/whois/roster/*.roster )
        for file in "${rosterList[@]}" ; do                     # Loop through each roster.

            # Skip the staff roster.  (i.e. only titles within batch rosters can be edited)
            if [ $(echo ${file} | grep staff) ] ; then
                continue
            fi

            topLine=$(cat ${file} -n | grep whodatPoints | sort -k3 -n | sed -n 1p)
            whodatPointsLineNumber=$(echo ${topLine} | sed 's/whodat.*//' | sed 's/ //g')
            points=$(sed -n ${whodatPointsLineNumber}p ${file} | grep -Po '(?<=(whodatPoints: )).*')            # Handle
            handleLineNumber="$((${whodatPointsLineNumber} - 4))"
            handle=$(sed -n ${handleLineNumber}p ${file} | grep -Po '(?<=(handle: )).*')            # Handle

            if [ "${points}" -lt "${lowestPoints}" ] ; then
                lowestPoints=${points}
                lowestUser=${handle}
            fi
        done

        if [ ${lowestUser} ] ; then
            say ${chan} "${lowestUser} is the underdog with ${lowestPoints} points."
        else
            say ${chan} "No lo at the mo."
        fi
    fi
}

# This subroutine displays documentation for rosterbot's functionalities.

function helpSubroutine {

    # Randomly select a Handle and a Real Name as an example for usage.
    rndHandle=$( cat $(pwd)/whois/roster/*.roster | egrep 'handle: [^ ]' | sed -e 's|handle: ||' | sort -R | head -n 1 )
    rndHandle1=$( cat $(pwd)/whois/roster/*.roster | egrep 'handle: [^ ]' | sed -e 's|handle: ||' | sort -R | head -n 1 )
    rndHandle2=$( cat $(pwd)/whois/roster/*.roster | egrep 'handle: [^ ]' | sed -e 's|handle: ||' | sort -R | head -n 1 )
    rndHandle3=$( cat $(pwd)/whois/roster/*.roster | egrep 'handle: [^ ]' | sed -e 's|handle: ||' | sort -R | head -n 1 )
    rndHandle4=$( cat $(pwd)/whois/roster/*.roster | egrep 'handle: [^ ]' | sed -e 's|handle: ||' | sort -R | head -n 1 )
    rndRealname=$( cat $(pwd)/whois/roster/*.roster | egrep 'realname: [^ ]' | sed -e 's|realname: ||' | sort -R | head -n 1 )

    if [ ${1} = "whois" ] ; then
        say ${chan} "Usage: !whois ${rndHandle1} -OR- rosterbot: whois ${rndHandle} | !whois ${rndRealname} | !whois CAT.username | !whois OIT.username | !whois =~ ^_.[^s-zA-Z]{3}.+$ | !whois =~ | !title ${rndHandle2} is a DROOG-1 | !whodat | !whodat ${rndHandle3} | !isdat ${rndHandle4} | !dunno | !whodahi | !whodalo | rosterbot: source"
    elif [ ${1} = "title" ] ; then
        say ${chan} "Usage: !title ${rndHandle} is a CLAW-1, ... | !title ${rndHandle2}"
    fi

}

################################################  Subroutines End  ################################################

# Ω≈ç√∫˜µ≤≥÷åß∂ƒ©˙∆˚¬…ææœ∑´®†¥¨ˆøπ“‘¡™£¢∞••¶•ªº–≠«‘“«`
# ─━│┃┄┅┆┇┈┉┊┋┌┍┎┏┐┑┒┓└┕┖┗┘┙┚┛├┝┞┟┠┡┢┣┤┥┦┧┨┩┪┫┬┭┮┯┰┱┲┳┴┵┶┷┸┹┺┻┼┽┾┿╀╁╂╃╄╅╆╇╈╉╊╋╌╍╎╏
# ═║╒╓╔╕╖╗╘╙╚╛╜╝╞╟╠╡╢╣╤╥╦╧╨╩╪╫╬╭╮╯╰╱╲╳╴╵╶╷╸╹╺╻╼╽╾╿

################################################  Commands Begin  #################################################

# Help Command.

if has "${msg}" "^!rosterbot$" || has "${msg}" "^rosterbot: help$" ; then
    helpSubroutine whois

# Alive.

elif has "${msg}" "^!alive$" || has "${msg}" "^rosterbot: alive(\?)?$" ; then
    say ${chan} "running!"

# Source.

elif has "${msg}" "^rosterbot: source$" ; then
    say ${chan} "Try -> https://github.com/kimdj/rosterbot -OR- /u/dkim/rosterbot"

# Whois Regex Pattern Matching.  (Note: Must precede Whois, to check for '=~')

elif has "${msg}" "^!whois =~ " || has "${msg}" "^rosterbot: whois =~ " ; then
    searchString=$(echo ${msg} | sed -r 's/^!whois =~ //' | sed -r 's/^rosterbot: whois =~ //')                # cut out the leading part from ${msg}
    whoisRegexSubroutine ${searchString}

# Whois Regex Pattern Matching documentation.

elif has "${msg}" "^!whois =~$" || has "${msg}" "^rosterbot: whois =~$" ; then
    say ${chan} ". matches any character | b{2} matches 2 b's | .* matches 0 or more characters | .+ matches 1 or more characters | [a-eX-Z]{2} matches 2 characters in the range from a to e or X to Z | [^0-9]{4} matches any 4 non-digit characters"

# Whois.

elif has "${msg}" "^!whois$" || has "${msg}" "^rosterbot: whois$" ; then
    helpSubroutine whois

elif has "${msg}" "^!whois " || has "${msg}" "^rosterbot: whois " ; then
    searchString=$(echo ${msg} | sed -r 's/^!whois //' | sed -r 's/^rosterbot: whois //')                # cut out the leading part from ${msg}
    whoisSubroutine ${searchString}

# Who.

elif has "${msg}" "^!who$" || has "${msg}" "^rosterbot: who$" ; then
    helpSubroutine whois

elif has "${msg}" "^!who " || has "${msg}" "^rosterbot: who " ; then
    searchString=$(echo ${msg} | sed -r 's/^!who //' | sed -r 's/^rosterbot: who //')                # cut out the leading part from ${msg}
    whoSubroutine ${searchString}

# Handler for catbot's !oit2cat responses. (Whois)

elif has "${msg}" "^name: " ; then
    realname=$(echo ${msg} | sed -r 's/^.{6}//')
    while read dest ; do
        whoisSubroutine2 ${dest}
    done < requester.tmp
    removeTmpSubroutine

elif has "${msg}" "^No matching MCECS uid found for " ; then
    while read dest ; do
        # say ${dest} ${msg}
        say ${dest} "User not found in CAT roster."
    done < requester.tmp
    removeTmpSubroutine

# Handler for catbot's !cat2oit responses. (Whois)

elif has "${msg}" "^cat uid \(or alias\): .* -> oit uid: " ; then
    oitLogin=$(echo ${msg} | sed -e "s|.* -> oit uid: \(.*\)|\1|")
    while read dest ; do
        while read login ; do
            say ${dest} "oit username: ${oitLogin}, cat username: ${login}"
        done < catLogin.tmp
    done < requester.tmp
    removeTmpSubroutine

elif has "${msg}" "^No matching OIT uid found for " ; then
    while read dest ; do
        say ${dest} ${msg}
    done < requester.tmp
    removeTmpSubroutine

# Change title.

elif has "${msg}" "^!title$" || has "${msg}" "^rosterbot: title$" ; then
    helpSubroutine title

elif has "${msg}" "^!title " || has "${msg}" "^rosterbot: title " ; then
    title=$(echo ${msg} | sed -r 's/^!title //' | sed -r 's/^rosterbot: title //')                   # cut out '!title ' from ${msg}
    titleSubroutine ${title}

# Have rosterbot send an IRC command to the IRC server.

elif has "${msg}" "^!injectcmd " || has "${msg}" "^rosterbot: injectcmd " && [[ ${nick} = "_sharp" ]] ; then
    cmd=$(echo ${msg} | sed -r 's/^!injectcmd //' | sed -r 's/^rosterbot: injectcmd //')
    send "${cmd}"

# Have rosterbot send a message.

elif has "${msg}" "^!sendcmd " || has "${msg}" "^rosterbot: sendcmd " && [[ ${nick} = "_sharp" ]] ; then
    buffer=$(echo ${msg} | sed -re 's/^!sendcmd //' | sed -re 's/^rosterbot: sendcmd //')
    dest=$(echo ${buffer} | sed -e "s| .*||")
    message=$(echo ${buffer} | cut -d " " -f2-)
    say ${dest} "${message}"

# Whodat game.

elif has "${msg}" "^!whodat$" || has "${msg}" "^rosterbot: whodat$" ; then
    whodatSubroutine

elif has "${msg}" "^!whodat " || has "${msg}" "^rosterbot: whodat " ; then
    handle=$(echo ${msg} | sed -r 's/^!whodat //' | sed -r 's/rosterbot: whodat //')
    whodatSubroutine2 ${handle}

elif has "${msg}" "^!isdat$" || has "${msg}" "^rosterbot: isdat$" ; then
    say ${chan} "isdat who? !whodat"

elif has "${msg}" "^!isdat " || has "${msg}" "^rosterbot: isdat " ; then
    answer=$(echo ${msg} | sed -r 's/^!isdat //' | sed -r 's/rosterbot: isdat //')
    isdatSubroutine ${answer}

elif has "${msg}" "^!dunno$" || has "${msg}" "^rosterbot: dunno$" ; then
    dunnoSubroutine

elif has "${msg}" "^!whodahi$" || has "${msg}" "^rosterbot: whodahi$" ; then
    whodaSubroutine "highest"

elif has "${msg}" "^!whodalo$" || has "${msg}" "^rosterbot: whodalo$" ; then
    whodaSubroutine "lowest"

fi

#################################################  Commands End  ##################################################
