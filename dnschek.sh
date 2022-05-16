#!/usr/bin/bash

[ -t 0 ] && stty -echoctl

tmp=$(mktemp -d --tmpdir=/tmp)
trap "rm -rf $tmp  && exit 1" TERM
trap "rm -rf $tmp" EXIT
export TOP_PID=$$

GET_AUTHORITY_DNS() {
  target="$1"
  dnsServer="$2"
  # local test with dnsmasq
  if [ "$target" == "local.me" ]; then
    echo -n "127.0.0.1"
    return
  fi
  mapfile -t ns < <(dig @"$dnsServer" "$target" ns +short | sed 's/.$//g' 2>/dev/null)
  if [[ ${#ns[@]} -ne 0 ]]; then
    echo "${ns[@]}"
    return
  else
    newTarget=$(cut -d . -f 2- <<<"$target")
    GET_AUTHORITY_DNS "$newTarget" "$dnsServer"
  fi
  echo -e "No authority dns found\nExit 1"
  EXIT
}
  
CHECK_RECORD() {
  target="$1"
  dns="$2"
  record="$3"
  dig "$target" @"$dns" "$record" +short
}


LOG_ERROR() {
  if [ ! -f "$tmp/norecord" ] && [ "$1" != "mismatch" ]; then
    [ -f "$tmp/down.log" ] ||  date +%s > "$tmp/down.log"
    touch "$tmp/norecord"
    (echo -n "NO RECORD:                                 "; date) | tee -a "$logfile"
  elif [ ! -f "$tmp/norecord" ] && [ ! -f "$tmp/mismatch" ] && [ "$1" == "mismatch" ]; then
    [ -f "$tmp/down.log" ] ||  date +%s > "$tmp/down.log"
    touch "$tmp/mismatch"
    (echo -n "MISMATCH RECORD:                           "; date) | tee -a "$logfile"
  fi
}
 
NO_ERROR() {
  if [ -f "$tmp/down.log" ]; then
    date1=$(cat "$tmp/down.log")
    date2=$(date +%s)
    diff="$((date2-date1))"
    rm -f "$tmp/down.log" "$tmp/norecord" "$tmp/mismatch"
    (echo -n "RECORD FOUND:                              "; date) | tee -a "$logfile"
    echo -n "TOTAL:                                     " | tee -a "$logfile"
    if [ $((diff /60/60)) -ne 0 ]; then  echo -n "$((diff /60/60)) hours "; fi | tee -a "$logfile" 
    echo "$(((diff/60) % 60)) minutes and $((diff % 60)) seconds" | tee -a "$logfile"
    echo "-----------------------------------------------------------------------------" >> "$logfile"
  fi
}

EXIT(){
  kill -s TERM $TOP_PID
}


SET_SERVICE(){
  [ $UID -ne 0 ] && echo "Run this as root" && exit 
  read -rep "Domain name to check? " target
  read -rep "Record type to check? (default A) " record
  read -rep "Interval in second? (default 20) " interval
  read -rep "Dns to use for finding authority one? (default 9.9.9.9) " dns
  read -rep "Monitoring specific value? (ex for txt: 'v=spf1 a -all') " value
  cmd="--target $target "
  [ -z "$record" ] || cmd+="--record $record "
  [[ "$interval" =~ ^[+-]?[0-9]+$ ]]  && cmd+="--interval $interval "
  [[ "$dns" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] && \
    cmd+="--dns $dns "
  [ -z  "$value" ] || cmd+="--value \"$value\""
  echo "Arguments are: '$cmd'"
  read -rep "Edit arguments list? (y/n) " resp
  if [ "$resp" != "${resp#[Yy]}" ] ;then
    echo "$cmd" >> "cmd.txt"
    [ -z "$EDITOR" ] && EDITOR="$(which vim)"
    $EDITOR "cmd.txt"
    cmd="$(<cmd.txt)"
    rm "cmd.txt"
  fi
  service="dnscheck_$(tr "." "-" <<<"$target").service"
  [ -f "/etc/systemd/system/$service" ] && \
    (systemctl stop "$service" 2>/dev/null || :) && \
    rm -f "/etc/systemd/system/$service"
  tee -a "/etc/systemd/system/$service"  <<EOF >/dev/null
[Unit]
Description=Dnscheck Service "$target"
  
[Service]
WorkingDirectory=$(pwd)
ExecStart=$(pwd)/$0 $cmd
  
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl start "$service"
  systemctl enable "$service"
  systemctl status --no-pager --full "$service"
  EXIT
}


USAGE(){
  cat << EOF
DNSCheck: monitor dns record

Usage:
-t, --target   [TARGET]       Domain name to check
-r, --record   [RECORD]       Record to monitor (default: A)
-d, --dns      [DNS]          Dns to use for finding authority one 
                                (default: 9.9.9.9)
-v, --value    [VALUE]        Check for specific value
-i, --interval [INTERVAL]     Interval in second (default: 30)
-l, --logfile  [LOGFILE]      Logfile name
-D, --daemon                  Install as daemon
-h, --help                    Print this help
EOF
  EXIT
}

MAIN() {
  target="$1"
  dns="$2"
  record="$3"
  value="$4"
  if [ -z "$(dig "$target" @"$dns" ns +short)" ]; then
    echo -e "$target dont have $record record" && exit 1
  fi
  mapfile -d " " -t authorityDns < <(GET_AUTHORITY_DNS "$target" "$dns")
  for i in "${authorityDns[@]}"; do
    mapfile -t resp < <(CHECK_RECORD "$target" "$i" "$record")
    if [ ${#resp[@]} -ge 0 ]; then break ; fi
  done
  if [ ${#resp[@]} -eq 0 ]; then
    [ -f "$tmp/mismatch" ] && rm "$tmp/mismatch"
    LOG_ERROR
  else
    [ -f "$tmp/norecord" ] && rm "$tmp/norecord"
    if [ ! -z "$value" ]; then
      grep -qE "$value" <<< "${resp[@]}" && NO_ERROR || LOG_ERROR "mismatch"
    else
      NO_ERROR
    fi
  fi
}

record="A"
interval=30
dns="9.9.9.9"
value=""

if [[ ${#@} -gt 0 ]]; then
  while [ "$1" != "" ]; do
    case $1 in
      -t|--target)
        shift
        target="$1"
        grep -qE '\-l|\-\-logfile' <<< "$@" || logfile="$( tr '.' '-' <<< "$target").log"
        ;;
      -r|--record)
        shift
        record="$1"
        ;;
      -v|--value)
        shift
        value="$1"
        ;;
      -d|--dns)
        shift
        dns="$1"
        ;;
      -i|--interval)
        shift
        interval="$1"
        ;;
      -l|--logfile)
        shift
        mkdir -p "$(dirname "$1")"
        logfile="$1"
        ;;
      -D|--daemon)
        SET_SERVICE
        ;;
      -h|--help)
        USAGE
        ;;
    esac
    shift
  done
else
  USAGE
fi

echo "******** Monitoring $target [$record] started at: $(date "+%a %d %b %Y %H:%M:%S %Z") ********" >> "$logfile"
while true; do
  MAIN "$target" "$dns"  "$record" "$value"
  sleep "$interval"
done
