#!/bin/bash
# rosterbot ~ Subroutines/Commands
# Copyright (c) 2017 David Kim
# This program is licensed under the "MIT License".

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
    while read -r line; do
      newdate=`date +%s%N`
      if [ "${prevdate}" -gt "${newdate}" ] ; then
        sleep `bc -l <<< "(${prevdate} - ${newdate}) / ${nanos}"`
        newdate=`date +%s%N`
      fi
      prevdate=${newdate}+${interval}
      echo "-> ${1}"
      echo "${line}" >> ${BOT_NICK}.io
    done <<< "${1}"
}

function join_by { local IFS="${1}" ; shift ; echo "$*" ; }

function removeTmpSubroutine {
    if [ -f ./requester.tmp ] ; then rm requester.tmp ; fi
    if [ -f ./oitLogin.tmp ] ; then rm oitLogin.tmp ; fi
    if [ -f ./catLogin.tmp ] ; then rm catLogin.tmp ; fi
}

function whoisSubroutine {

    echo "${chan}" > requester.tmp                  # Store ${chan} (requester's nick) in a file.
    found=0                                         # Initialize found flag to 0.
    pathToStaffRoster="$(pwd)/whois/roster/staff.roster"
    rosterList=( $(pwd)/whois/roster/*.roster )
    arg=$(echo ${1} | sed 's|[^a-zA-Z0-9_ ]||g')                           # Filter out malicious or meaningless characters.

    # Parse based on CAT handle.    ----------------------------------------------------------------------------------

    # handle=$(echo ${arg} | sed 's/ .*//')             # Capture the first word of the argument (i.e. first word -> first).
    handle=$(echo ${arg})                             # Allow whitespace within Handle.

    # say _sharp "Looking for Handle..."            # Debugging
    for file in "${rosterList[@]}" ; do             # Loop through each roster.

        # Look for the Handle in the file.
        # Otherwise, continue on the next file.
        # Note: grep matches based on regex anchors ^ (start-of-line) and $ (end-of-line).
        # The purpose is to mitigate unintented substring matches.
        handleLine=$(cat ${file} | grep -in "^handle: ${handle}$")                              # 129:handle: handle
        if [ ${handleLine} ] ; then
            handleLineNumber=$(echo ${handleLine} | sed -e 's/\([0-9]*\):.*/\1/')               # 129
        else
            continue
        fi

        # Get the Handle.
        handle=$(sed -n ${handleLineNumber}p ${file} | grep -Po '(?<=(handle: )).*')            # handle

        # Get the cat username and oit username.
        loginLineNumber="$((${handleLineNumber} - 2))"                                          # 127
        login=$(sed -n ${loginLineNumber}p ${file} | grep -Po '(?<=(login: )).*')               # $login refers to the user's cat username
        echo "${login}" > catLogin.tmp                                                          # Store cat login in a file.
        privmsg=$(echo '!cat2oit' ${login})                                                     # Send to catbot -> !cat2oit username
        say "catbot" ${privmsg}                                                                 # Refer to "Handler for catbot's !cat2oit responses" section below.

        # Get the Username.
        # Note: subpath == cat username in most cases.
        usernameLineNumber="$((${handleLineNumber} - 1))"                                       # 128
        subpath=$(sed -n ${usernameLineNumber}p ${file} | grep -Po '(?<=(subpath: )).*')        # username

        # Get the Realname.
        realnameLineNumber="$((${handleLineNumber} + 1))"                                       # 130
        realname=$(sed -n ${realnameLineNumber}p ${file} | grep -Po '(?<=(realname: )).*')      # login

        # Get the Title.
        titleLineNumber="$((${handleLineNumber} + 2))"                                          # 131
        title=$(sed -n ${titleLineNumber}p ${file} | grep -Po '(?<=(title: )).*')               # title

        # Get the Batch and Year.
        year=$(sed -n 1p ${file} | grep -Po '(?<=(year: )).*')                                  # 2017-2018
        batch=$(sed -n 2p ${file} | grep -Po '(?<=(batch: )).*')                                # Yet-To-Be-Named (YTBN)

        # Send results back to the client.
        if [ ${file} == "${pathToStaffRoster}" ] ; then                                         # Case: match was found in staff.roster
            say ${chan} "Try -> https://chronicle.cat.pdx.edu/projects/cat/wiki/${subpath}"
        else
            say ${chan} "Try -> https://chronicle.cat.pdx.edu/projects/braindump/wiki/${subpath}"
        fi
        if [ ${title} ] ; then                                                                  # Case: title field entry exists
            say ${chan} "${handle}'s real name is ${realname} | ${handle} ${title}"
        else
            say ${chan} "${handle}'s real name is ${realname}"
        fi
        say ${chan} "${handle} belongs to the ${batch}, ${year}"

        found=$((${found} + 1))                             # Set found flag to 1.
    done

    # Parse based on cat login name.    ----------------------------------------------------------------------------------

    if [ "${found}" -eq "0" ] ; then                        # If a Handle match was found, skip this if block.
        login=$(echo ${arg} | sed 's/ .*//')                  # Just capture the first word.

        arr=()                                                      # Declare an empty array.  (list of entries found)
        for file in "${rosterList[@]}" ; do                 # Loop through each roster.

            # Look for the Login in the file.
            # Otherwise, continue on the next file.
            # Note: grep matches based on anchors ^ and $.
            # The purpose is to mitigate unintentional substring matches.
            loginLine=$(cat ${file} | grep -in "^login: ${login}$")                               # 129:login: login
            if [ ${loginLine} ] ; then
                loginLineNumber=$(echo ${loginLine} | sed -e 's/\([0-9]*\):.*/\1/')               # 129
            else
                continue
            fi

            # Get the Handle.
            handleLineNumber="$((${loginLineNumber} + 2))"                                        # 128
            handle=$(sed -n ${handleLineNumber}p ${file} | grep -Po '(?<=(handle: )).*')          # username
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

        say ${chan} "${payload}"
    fi

    # Parse based on real name.    ----------------------------------------------------------------------------------

    if [ "${found}" -eq "0" ] ; then                                # If a Handle match or Login match was found, skip this if block.
        realname=$(echo ${arg} | sed 's/\(.* .*\) .*//')              # Just capture the first word.

        arr=()                                                      # Declare an empty array.  (list of entries found)
        for file in "${rosterList[@]}" ; do                         # Loop through each roster.

            # Look for the real name in the file.
            # Otherwise, continue on the next file.
            # Note: grep matches based on anchors ^ and $.
            # The purpose is to mitigate unintentional substring matches.
            realnameLine=$(cat ${file} | grep -in "^realname:" | grep -in " ${realname} \| ${realname}$" | sed -e 's/\([0-9]*\)://')          # 101:realname: realname ... (0, 1, or more lines)
            if [ ${realnameLine} ] ; then
                while read -r line ; do                      # For each found entry...
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
            fi
        done

        uniqArr=$(echo "${arr[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' ' | sed 's| $||')                    # Remove duplicate Handles in arr (get unique array values only)
        sep=' ~ '                                                                                           # Define the separator between Handles
        payload=$( echo ${uniqArr[@]} | sed "s/ /${sep}/g" | sed "s/^${sep}//" | sed 's/%20/ /g')           # e.g. Superman ~ Iron Man ~ Thor

        say ${chan} "${payload}"

        # If a match was not found, ask catbot.
        # Refer to "Handler for catbot's responses" section below.
        if [ "${found}" -eq "0" ] ; then
            privmsg=$(echo '!oit2cat' ${arg})                                     # Send to catbot -> !oit2cat username
            say "catbot" ${privmsg}
        fi
    fi
}

function whoisSubroutine2 {
    
    # Parse based on real name from catbot's !oit2cat response.

    dest=${1}
    oitLogin=${2}
    found=0    # Initialize found flag to 0.
    rosterList=( $(pwd)/whois/roster/*.roster )

    arr=()
    for file in "${rosterList[@]}" ; do                                         # Loop through each roster.

        # Find a line containing the real name.
        # Otherwise, continue on the next file.
        # Note: grep matches based on anchors ^ and $.
        # The purpose is to mitigate unintentional substring matches.
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

        # # Send a response to the client.
        # say ${dest} "${handle}"

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

    # If a match was not found..
    if [ "${found}" -eq "0" ] ; then
        say ${dest} "User not found in the CAT Roster."
    fi
}

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

        # Look for the Handle in the file.
        # Otherwise, continue on the next file.
        # Note: grep matches based on anchors ^ and $.
        # The purpose is to mitigate unintentional substring matches.
        handleLine=$(cat ${file} | grep -in "^handle: ${handle}$")                              # 129:handle: handle
        if [ ${handleLine} ] ; then
            handleLineNumber=$(echo ${handleLine} | sed -e 's/\([0-9]*\):.*/\1/')               # 129
        else
            continue
        fi

        # Modify the Title.
        titleLineNumber="$((${handleLineNumber} + 2))"
        oldTitle=$(sed -n ${titleLineNumber}p ${file} | grep -Po '(?<=(title: )).*')            # title

        if [[ ${newTitle} == ${handle} ]] ; then                                                # clear title
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

function helpSubroutine {

    # Randomly select a Handle and a Real Name as an example for usage.
    handle=$( cat $(pwd)/whois/roster/*.roster | egrep 'handle: [^ ]' | sed -e 's|handle: ||' | sort -R | head -n 1 )
    handle2=$( cat $(pwd)/whois/roster/*.roster | egrep 'handle: [^ ]' | sed -e 's|handle: ||' | sort -R | head -n 1 )
    rndRealname=$( cat $(pwd)/whois/roster/*.roster | egrep 'realname: [^ ]' | sed -e 's|realname: ||' | sort -R | head -n 1 )

    if [ ${1} == "whois" ] ; then
        say ${chan} "Usage: !whois ${handle} | !whois ${rndRealname} | !whois CATusername | !whois OITusername | !title ${handle2} is a DROOG-1, ..."
    elif [ ${1} == "title" ] ; then
        say ${chan} "Usage: !title ${handle} is a CLAW-1, ... | !title ${handle2}"
    fi
}

################################################  Subroutines End  ################################################

# Ω≈ç√∫˜µ≤≥÷åß∂ƒ©˙∆˚¬…ææœ∑´®†¥¨ˆøπ“‘¡™£¢∞••¶•ªº–≠«‘“«`
# ─━│┃┄┅┆┇┈┉┊┋┌┍┎┏┐┑┒┓└┕┖┗┘┙┚┛├┝┞┟┠┡┢┣┤┥┦┧┨┩┪┫┬┭┮┯┰┱┲┳┴┵┶┷┸┹┺┻┼┽┾┿╀╁╂╃╄╅╆╇╈╉╊╋╌╍╎╏
# ═║╒╓╔╕╖╗╘╙╚╛╜╝╞╟╠╡╢╣╤╥╦╧╨╩╪╫╬╭╮╯╰╱╲╳╴╵╶╷╸╹╺╻╼╽╾╿

################################################  Commands Begin  #################################################

# Help Command.

if has "${msg}" "^!rosterbot$" ; then
    helpSubroutine whois

elif has "${msg}" "^rosterbot: help$" ; then
    helpSubroutine whois

# Alive.

elif has "${msg}" "^!alive$" ; then
    say ${chan} "running!"

# Source.

elif has "${msg}" "^rosterbot: source$" ; then
    say ${chan} "Try -> https://github.com/kimdj/rosterbot  |  /u/dkim/sandbox/rosterbot"

# Whois.

elif has "${msg}" "^!whois$" ; then
    helpSubroutine whois
    
elif has "${msg}" "^!whois " ; then
    searchString=$(echo ${msg} | sed -r 's/^.{7}//')                # cut out the leading '!whois ' from ${msg}
    whoisSubroutine ${searchString}

# Handler for catbot's !oit2cat responses. (Whois)

elif has "${msg}" "^oit uid \(or alias\): " ; then
    oitLogin=$(echo ${msg} | sed -r 's/^.{20}//')                   # Get the oitLogin.
    echo "${oitLogin}" > oitLogin.tmp

elif has "${msg}" "^name: " ; then
    realname=$(echo ${msg} | sed -r 's/^.{6}//')
    while read dest ; do
        while read oitLogin ; do
            whoisSubroutine2 ${dest} ${oitLogin}
        done < oitLogin.tmp
    done < requester.tmp
    removeTmpSubroutine

elif has "${msg}" "^No matching MCECS uid found for " ; then
    while read dest ; do
        say ${dest} ${msg}
    done < requester.tmp
    removeTmpSubroutine

# Handler for catbot's !cat2oit responses. (Whois)
elif has "${msg}" "^cat uid \(or alias\): .* -> oit uid: " ; then
    oitLogin2=$(echo ${msg} | sed -e "s|.* -> oit uid: \(.*\)|\1|")
    while read dest ; do
        while read login ; do
            # echo ${oitLogin}2 > oitLogin2.tmp
            say ${dest} "oit username: ${oitLogin2}, cat username: ${login}"
        done < catLogin.tmp
    done < requester.tmp
    removeTmpSubroutine

elif has "${msg}" "^No matching OIT uid found for " ; then
    while read dest ; do
        say ${dest} ${msg}
    done < requester.tmp
    removeTmpSubroutine

# Change title.

elif has "${msg}" "^!title$" ; then
    helpSubroutine title

elif has "${msg}" "^!title " ; then
    title=$(echo ${msg} | sed -r 's/^.{7}//')                   # cut out '!title ' from ${msg}
    titleSubroutine ${title}

# Have rosterbot send an IRC command to the IRC server.

elif has "${msg}" "^!injectcmd " && [[ ${nick} == "_sharp" ]] ; then
    cmd=$(echo ${msg} | sed -r 's/^.{11}//')
    send "${cmd}"

# Have rosterbot send a message.

elif has "${msg}" "^!sendcmd " && [[ ${nick} == "_sharp" ]] ; then
    buffer=$(echo ${msg} | sed -re 's/^.{9}//')
    dest=$(echo ${buffer} | sed -e "s| .*||")
    message=$(echo ${buffer} | cut -d " " -f2-)
    say ${dest} "${message}"

fi

#################################################  Commands End  ##################################################
