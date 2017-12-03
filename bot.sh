#!/bin/bash
# rosterbot ~ main
# Copyright (c) 2017 David Kim
# This program is licensed under the "MIT License".

LOG_FILE_1=/home/dkim/sandbox/rosterbot/log.stdout        # Redirect file descriptors 1 and 2 to log.out
LOG_FILE_2=/home/dkim/sandbox/rosterbot/log.stderr
exec > >(tee -a ${LOG_FILE_1} )
exec 2> >(tee -a ${LOG_FILE_2} >&2)

BOT_NICK="rosterbot"
KEY="$(cat ./config.txt)"

nanos=1000000000
interval=$(( $nanos * 50 / 100 ))
declare -i prevdate
prevdate=0

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

rm ${BOT_NICK}.io
mkfifo ${BOT_NICK}.io

tail -f ${BOT_NICK}.io | openssl s_client -connect irc.cat.pdx.edu:6697 | while true ; do

    # If log.out is empty, reset logging.  (cron job empties log.out after backup)
    LOG_FILE_1=/home/dkim/sandbox/rosterbot/log.stdout
    LOG_FILE_2=/home/dkim/sandbox/rosterbot/log.stderr
    if [ ! -s ${LOG_FILE} ] ; then
        exec > >(tee -a ${LOG_FILE_1} )
        exec 2> >(tee -a ${LOG_FILE_2} >&2)
    fi

    if [[ -z $started ]] ; then
        send "NICK $BOT_NICK"
        send "USER 0 0 0 :$BOT_NICK"
        started="yes"
    fi

    if [ -e commands/cmd ] ; then               # if a cmd file exists, run the cmd
        while read line ; do
            send "$line"
        done < commands/cmd
        rm commands/cmd
    fi

    read irc
    if $(echo "$irc" | cut -d ' ' -f 1 | grep -P "PING" > /dev/null) ; then
        send "PONG"
    elif $(echo "$irc" | cut -d ' ' -f 2 | grep -P "PRIVMSG" > /dev/null) ; then 
#:nick!user@host.cat.pdx.edu PRIVMSG #bots :This is what an IRC protocol PRIVMSG looks like!
        nick="$(echo "$irc" | cut -d ':' -f 2- | cut -d '!' -f 1)"
        chan="$(echo "$irc" | cut -d ' ' -f 3)"
        if [ "$chan" = "$BOT_NICK" ] ; then chan="$nick" ; fi 
        msg="$(echo "$irc" | cut -d ' ' -f 4- | cut -c 2- | tr -d "\r\n")"
        echo "$(date) | $chan <$nick>: $msg"
        var="$(echo "$nick" "$chan" "$msg" | ./commands.sh)"
        if [[ ! -z $var ]] ; then
            send "$var"
        fi   
    fi
done
