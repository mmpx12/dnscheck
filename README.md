# DNSCheck.sk: DNS monitoring


Inspired from [netcheck](https://github.com/TristanBrotherton/netcheck) but for dns records.

## Usage:

```
-t, --target   [TARGET]       Domain name to check
-r, --record   [RECORD]       Record to monitor (default: A)
-d, --dns      [DNS]          Dns to use for finding authority one 
                                (default: 9.9.9.9)
-v, --value    [VALUE]        Check for specific value
-i, --interval [INTERVAL]     Interval in second (default: 30)
-l, --logfile  [LOGFILE]      Logfile name
-D, --daemon                  Install as daemon
-h, --help                    Print this help and exit
```


## Install:

```sh
git clone git@github.com:mmpx12/dnscheck.git
cd dnscheck
bash dnscheck.sh ...
```

or:

```sh
$ curl -sk https://raw.githubusercontent.com/mmpx12/dnscheck/master/dnschek.sh | \
  sudo tee -a /usr/bin/dnschech && chmod +x /usr/bin/dnscheck
$ dnscheck ...
```

#### Install as a systemd service:


```sh
$ sudo bash dnscheck.sh --daemon
``` 

with "local.me" as a target service file while be locate at **/etc/systemd/system/dnscheck_local-me.service**.


## Example:

- Monitor local.me for TXT record with "v=spf1 a -all" in it:

```sh
$ bash dnschek.sh  -t local.me -d 127.0.0.1 -r TXT -l LOCAL.txt -v "v=spf1 a -all" -i 10
NO RECORD:                                 Mon 16 May 20:14:00 UTC 2022
MISMATCH RECORD:                           Mon 16 May 20:14:21 UTC 2022
NO RECORD:                                 Mon 16 May 20:14:41 UTC 2022
RECORD FOUND:                              Mon 16 May 20:14:51 UTC 2022
TOTAL:                                     0 minutes and 51 seconds
```

- Monitor local.me for A record with value "172.17.0.1"
 
do 

```sh
$ echo "127.0.0.1 local.me" | sudo tee -a /etc/hosts
$ bash dnschek.sh  -t local.me -d 127.0.0.1 -l LOCAL.txt -v "172.17.0.1" -i 10
MISMATCH RECORD:                           Mon 16 May 20:18:04 UTC 2022
RECORD FOUND:                              Mon 16 May 20:19:45 UTC 2022
TOTAL:                                     1 minutes and 41 second
```

then when dnscheck is running run:

```sh
sudo sed -i 's/127.0.0.1 local.me/172.17.0.1 local.me/' /etc/hosts && \
  systemctl restart dnsmasq.service
```
