#!/bin/bash
# rosterbot ~ Subroutines/Commands
# Copyright (c) 2017 David Kim
# This program is licensed under the "MIT License".

read nick chan msg
IFS=''                  # internal field separator; variable which defines the char(s)
                        # used to separate a pattern into tokens for some operations
                        # (i.e. space, tab, newline)
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BOT_NICK="$(grep -P "BOT_NICK=.*" ${DIR}/bot.sh | cut -d '=' -f 2- | tr -d '"')"

function has { $(echo "$1" | grep -P "$2" > /dev/null) ; }

function say { echo "PRIVMSG $1 :$2" ; }

if [ "$chan" = "$BOT_NICK" ] ; then chan="$nick" ; fi

###############################################  Subroutines Begin  ###############################################

function send {
    while read -r line; do
      newdate=`date +%s%N`
      if [ $prevdate -gt $newdate ] ; then
        sleep `bc -l <<< "($prevdate - $newdate) / $nanos"`
        newdate=`date +%s%N`
      fi
      prevdate=$newdate+$interval
      echo "-> $1"
      echo "$line" >> ${BOT_NICK}.io
    done <<< "$1"
}

function outputSubroutine {
    filename=$1
    say $dest "$nick says:"             # show the sender's nick
    while read -r line
    do
        sleep .2
        say $dest "$line"
    done < $filename
}

function outputSubroutine2 {
    filename=$1
    while read -r line
    do
        sleep .2
        say $chan "$line"
    done < $filename
}

function countdownSubroutine {
    TIME=$(($1+1))
    CUR=$TIME
     
    t1=$(date +%T)
    while [ $CUR -gt 1 ]
    do
     CUR=$(($CUR - 1))
     sleep 1
    done
    t2=$(date +%T)
    say $chan "~~    COUNTDOWN ENDED: $t2  ~~"
    say $chan "~~  COUNTDOWN STARTED: $t1  ~~"
}

function reverbSubroutine {
    # t1=$(($(date +%s%N)/1000000))    # DEBUG: running time
    sentence=$(echo $message | sed 's/\s+/\+/')
    if [ $# -ne 0 ] ; then                                                  # case: function argument(s) exist
        d="$1"                                                              # allow user to choose font
        # pathComponent=$(echo $sentence | sed -r 's/^\w*\ *//' |           # catch the first word
        pathComponent=$(echo $sentence | sed -r 's/\+/%2B/'   |             # replace special characters with URL-encoded characters
                                         sed -r 's/!/%21/'    |
                                         sed -r 's/\?/%3F/'   |
                                         sed -r 's/@/%40/'    |
                                         sed -r 's/#/%23/'    |
                                         sed -r 's/:/%3A/'    |
                                         sed -r 's/,/%2C/'    |
                                         tr ' ' '+')                        # replace all whitespaces with '+'
    else
        d="smshadow"                                                        # or set default font to cybermedium
        pathComponent=$(echo $sentence | sed -r 's/\+/%2B/'   |
                                         sed -r 's/!/%21/'    |
                                         sed -r 's/\?/%3F/'   |
                                         sed -r 's/@/%40/'    |
                                         sed -r 's/#/%23/'    |
                                         sed -r 's/:/%3A/'    |
                                         sed -r 's/,/%2C/'    |
                                         tr ' ' '+')
    fi

    a="http://www.network-science.de/ascii/ascii.php?TEXT="
    b=$pathComponent
    c="&x=34&y=5&FONT="
    e="&RICH=no&FORM=left&STRE=no&WIDT=180"
    a+=$b
    a+=$c
    a+=$d
    a+=$e                                                                       # a is the crafted link to the ASCII art generator.

    $(curl "$a" > ascii_art/tmp/tmp.ascii.art)                                  # Download the html source code.

    ######## ORIGINAL ALGORITHM #########
    sed 's/.*<TR><TD><PRE>//' ascii_art/tmp/tmp.ascii.art > ascii_art/tmp/b
    tail -n +34 ascii_art/tmp/b > ascii_art/tmp/c                               # chopped of the first 34 lines
    grep -n '</PRE>' ascii_art/tmp/c > ascii_art/tmp/d                          # then chop off the html portion
    cat ascii_art/tmp/d | sed 's/[^0-9]*//g' > ascii_art/tmp/e                  # find the line number to delete from
    num="$(cat ascii_art/tmp/e)"
    num=$((num-1))
    head -n ${num} ascii_art/tmp/c > ascii_art/tmp/f                            # get the ascii art lines
    cat ascii_art/tmp/f | perl -MHTML::Entities -pe 'decode_entities($_);' > ascii_art/tmp/convertedAscii  # convert HTML entities to characters

    filename="ascii_art/tmp/convertedAscii"
    outputSubroutine $filename                                                  # output to irc
    # t2=$(($(date +%s%N)/1000000))    # DEBUG: running time
    # say #rosterbottestchannel "DEBUG: running time (in milliseconds) -> $((t2-t1))"
}

function whoisSubroutine {

    # Parse based on CAT handle.
say $chan "1"
    found=0    # Initialize found flag to 0.
    dir=`pwd`
    if [ $# -gt 0 ] ; then                          # If an arg exists...
        handle=$(echo $1 | sed 's/ .*//')           # Just capture the first word.

        for file in "$dir"/whois/roster/* ; do      # Loop through each roster.

            # Look for the Handle in the file.
            # Otherwise, continue on the next file.
            # Note: grep matches based on anchors ^ and $.
            # The purpose is to mitigate unintentional substring matches.
            handleLine=$(cat $file | grep -in "^handle: $handle$")                              # 129:handle: handle
            if [ $handleLine ] ; then
                handleLineNumber=$(echo $handleLine | sed -e 's/\([0-9]*\):.*/\1/')             # 129
            else
                continue
            fi

            # Get the Handle.
            handle=$(sed -n ${handleLineNumber}p $file | grep -Po '(?<=(handle: )).*')          # handle

            # Get the Username.
            # Note: subpath == username in most cases.
            usernameLineNumber="$(($handleLineNumber - 1))"                                     # 128
            subpath=$(sed -n ${usernameLineNumber}p $file | grep -Po '(?<=(subpath: )).*')      # username
            if [ $file == "/u/dkim/sandbox/rosterbot/whois/roster/staff.roster" ] ; then
                say $chan "Try ⤑ https://chronicle.cat.pdx.edu/projects/cat/wiki/$subpath"
            else
                say $chan "Try ⤑ https://chronicle.cat.pdx.edu/projects/braindump/wiki/$subpath"
            fi

            # Get the Realname.
            realnameLineNumber="$(($handleLineNumber + 1))"                                     # 130
            realname=$(sed -n ${realnameLineNumber}p $file | grep -Po '(?<=(realname: )).*')    # login
            say $chan "$handle's real name is $realname"

            # Get the Title.
            titleLineNumber="$(($handleLineNumber + 2))"                                        # 131
            title=$(sed -n ${titleLineNumber}p $file | grep -Po '(?<=(title: )).*')             # title
            if [ $title ] ; then
                say $chan "$handle $title"
            fi

            # Get the Batch and Year.
            year=$(sed -n 1p $file | grep -Po '(?<=(year: )).*')                                # 2017-2018
            batch=$(sed -n 2p $file | grep -Po '(?<=(batch: )).*')                              # Yet-To-Be-Named (YTBN)
            say $chan "$handle belongs to the $batch, $year"

            found=$(($found + 1))    # Set found flag to 1. ; done
        done
    else
        say $chan "Usage: !whois username"
    fi

###############################################################################################

    # Parse based on login name.
    say $chan "2"
        if [ $# -gt 0 ] ; then                          # If an arg exists and not found based on CAT handle...
            login=$(echo $1 | sed 's/ .*//')           # Just capture the first word.

            for file in "$dir"/whois/roster/* ; do      # Loop through each roster.

                # Look for the Login in the file.
                # Otherwise, continue on the next file.
                # Note: grep matches based on anchors ^ and $.
                # The purpose is to mitigate unintentional substring matches.
                loginLine=$(cat $file | grep -in "^login: $login$")                              # 129:login: login
                if [ $loginLine ] ; then
                    loginLineNumber=$(echo $loginLine | sed -e 's/\([0-9]*\):.*/\1/')             # 129
                else
                    continue
                fi

                # Get the Login.
                login=$(sed -n ${loginLineNumber}p $file | grep -Po '(?<=(login: )).*')          # login

                # Get the Username.
                # Note: subpath == username in most cases.
                usernameLineNumber="$(($loginLineNumber))"                                          # 128
                subpath=$(sed -n ${usernameLineNumber}p $file | grep -Po '(?<=(subpath: )).*')      # username
                if [ $file == "/u/dkim/sandbox/rosterbot/whois/roster/staff.roster" ] ; then
                    say $chan "Try ⤑ https://chronicle.cat.pdx.edu/projects/cat/wiki/$subpath"
                else
                    say $chan "Try ⤑ https://chronicle.cat.pdx.edu/projects/braindump/wiki/$subpath"
                fi

                # Get the Realname.
                realnameLineNumber="$(($loginLineNumber + 3))"                                     # 130
                realname=$(sed -n ${realnameLineNumber}p $file | grep -Po '(?<=(realname: )).*')   # realname
                say $chan "$login's real name is $realname"

                # Get the Title.
                titleLineNumber="$(($loginLineNumber + 4))"                                        # 131
                title=$(sed -n ${titleLineNumber}p $file | grep -Po '(?<=(title: )).*')             # title
                if [ $title ] ; then
                    say $chan "$login $title"
                fi

                # Get the Batch and Year.
                year=$(sed -n 1p $file | grep -Po '(?<=(year: )).*')                                # 2017-2018
                batch=$(sed -n 2p $file | grep -Po '(?<=(batch: )).*')                              # Yet-To-Be-Named (YTBN)
                say $chan "$login belongs to the $batch, $year"

                found=$(($found + 1))    # Set found flag to 1. ; done
            done

        else
            say $chan "Usage: !whois username"
        fi

###############################################################################################

    # Parse based on real name.
    say $chan "3"
    if [ "$found" -eq "0" ] ; then
        if [ $# -gt 0 ] ; then                          # If an arg exists and not found based on CAT handle...
            realname=$(echo $1 | sed 's/\(.* .*\) .*//')           # Just capture the first word.
    say $chan "4"
            for file in "$dir"/whois/roster/* ; do      # Loop through each roster.
    say $chan "5"
                # Look for the real name in the file.
                # Otherwise, continue on the next file.
                # Note: grep matches based on anchors ^ and $.
                # The purpose is to mitigate unintentional substring matches.
                realnameLine=$(cat $file | grep -in "^realname:" | grep -in " ${realname} \| ${realname}$" | sed -e 's/\([0-9]*\)://')                              # 129:realname: realname
                if [ $realnameLine ] ; then
                    realnameLineNumber=$(echo $realnameLine | sed -e 's/\([0-9]*\):.*/\1/')             # 129
                else
                    continue
                fi
    say $chan "8"
                # Get the Handle.
                handleLineNumber="$(($realnameLineNumber - 1))"                                     # 130
                handle=$(sed -n ${handleLineNumber}p $file | grep -Po '(?<=(handle: )).*')          # handle
    say $chan "9"
                # Get the Realname.
                _realname=$(sed -n ${realnameLineNumber}p $file | grep -Po '(?<=(realname: )).*')   # realname
                say $chan "${_realname}'s CAT handle is ${handle}"
    say $chan "10"
                found=$(($found + 1))    # Set found flag to 1. ; done
    say $chan "11"
            done

        else
            say $chan "Usage: !whois username"
        fi
    fi

    # If a match was not found..
    if [ "$found" -eq "0" ] ; then
        say $chan "User not found in the CAT Roster."
    fi
}

function titleSubroutine {
    found=0    # Initialize found flag to 0.
    dir=`pwd`
    if [ $# -gt 0 ] ; then                              # If an arg exists...
        handle=$(echo $1 | sed 's/ .*//')               # Just capture the first word.
        newTitle=$(echo $1 | cut -d " " -f2-)           # Capture the remaining words.

        if [ ! $handle ] ; then
            say $chan "input error"
            return 1
        fi

        for file in "$dir"/whois/roster/* ; do      # Loop through each roster.

            # Look for the Handle in the file.
            # Otherwise, continue on the next file.
            # Note: grep matches based on anchors ^ and $.
            # The purpose is to mitigate unintentional substring matches.
            handleLine=$(cat $file | grep -in "^handle: $handle$")                              # 129:handle: handle
            if [ $handleLine ] ; then
                handleLineNumber=$(echo $handleLine | sed -e 's/\([0-9]*\):.*/\1/')             # 129
            else
                continue
            fi

            # Modify the Title.
            titleLineNumber="$(($handleLineNumber + 2))"
            oldTitle=$(sed -n ${titleLineNumber}p $file | grep -Po '(?<=(title: )).*')          # title

            if [[ $newTitle == $handle ]] ; then                                                # clear title
                newTitle=''
            fi

            if [ -n "$newTitle" ] ; then
                say $chan "$handle's title was modified"
                $(sed -i "${titleLineNumber}s|.*|title: ${newTitle}|" $file)                    # replace title with new title
                currentTitle=$(sed -n ${titleLineNumber}p $file | grep -Po '(?<=(title: )).*')  # title
            else
                say $chan "$handle's title was cleared"
                $(sed -i "${titleLineNumber}s/.*/title: /" $file)                               # clear title
            fi

            found=$(($found + 1))    # Set found flag to 1. ; done
        done

        # If a match was not found..
        if [ $found -lt 1 ] ; then
            say $chan "User not found in the CAT Roster."
        fi
    else
        say $chan "Usage: !whois username"
    fi
}

function helpSubroutine {
    say $chan "Usage: !whois _sharp || !whois david kim || !whois dkim || !title _sharp is a DOG"
}

################################################  Subroutines End  ################################################

# Ω≈ç√∫˜µ≤≥÷åß∂ƒ©˙∆˚¬…ææœ∑´®†¥¨ˆøπ“‘¡™£¢∞••¶•ªº–≠«‘“«`
# ─━│┃┄┅┆┇┈┉┊┋┌┍┎┏┐┑┒┓└┕┖┗┘┙┚┛├┝┞┟┠┡┢┣┤┥┦┧┨┩┪┫┬┭┮┯┰┱┲┳┴┵┶┷┸┹┺┻┼┽┾┿╀╁╂╃╄╅╆╇╈╉╊╋╌╍╎╏
# ═║╒╓╔╕╖╗╘╙╚╛╜╝╞╟╠╡╢╣╤╥╦╧╨╩╪╫╬╭╮╯╰╱╲╳╴╵╶╷╸╹╺╻╼╽╾╿

################################################  Commands Begin  #################################################

# Help Command.

if has "$msg" "!rosterbot" ; then
    helpSubroutine

elif has "$msg" "rosterbot: help" ; then
    helpSubroutine

# Alive?.

elif has "$msg" "rosterbot: !alive?" || has "$msg" "!alive?" ; then
    a="^rosterbot:[[:space:]]!alive?"
    b="^gb:[[:space:]]!alive?"
    c="^!alive?"
    if [[ "$msg" =~ $a ]] || [[ "$msg" =~ $b ]] || [[ "$msg" =~ $c ]] ; then
        say $chan "running!"
    fi

# Whois.

elif has "$msg" "!whois" ; then
    if [[ "$msg" =~ ^!whois ]] ; then
        handle=$(echo $msg | sed -r 's/^.{7}//') 
        whoisSubroutine $handle
    fi

# Change title.

elif has "$msg" "!title" ; then
    if [[ "$msg" =~ ^!title ]] ; then
        title=$(echo $msg | sed -r 's/^.{7}//') 
        titleSubroutine $title
    fi

# Inject a command.
# Have rosterbot send an IRC command to the IRC server.
elif has "$msg" "!injectcmd" ; then
    if [[ $nick == "_sharp" ]] || [[ $nick == "MattDamon" ]]; then    # only _sharp can execute this command
        if [[ "$msg" =~ ^!injectcmd ]] ; then
            message=$(echo $msg | sed -r 's/^.{11}//') 
            send "$message"
        fi
    fi

# Have rosterbot send a message.
elif has "$msg" "!sendcmd" ; then
    if [[ $nick == "_sharp" ]] || [[ $nick == "MattDamon" ]]; then    # only _sharp can execute this command
        if [[ "$msg" =~ ^!sendcmd ]] ; then
            buffer=$(echo $msg | sed -re 's/^.{9}//')
            user=$(echo $buffer | sed -e "s| .*||")
            message=$(echo $buffer | cut -d " " -f2-)
            say $user "$message"
        fi
    fi
fi
#################################################  Commands End  ##################################################
