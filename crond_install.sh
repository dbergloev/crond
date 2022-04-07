#!/bin/bash

##
# Trap on error
# Use 'exit-on-error' (set -e) (EXIT)
set -e
trap 'catch $?' EXIT SIGINT SIGTERM

##
# Function to deal with errors
catch() {
    if [ "$1" != "0" ]; then
        echo "Installation failed ($1)"
    fi
}


echo "Installing /etc/rc.cron"
sudo tee /etc/rc.cron > /dev/null <<'EOF'
#!/bin/bash

SCRIPT=$0
BASEDIR=$(dirname $(realpath "$SCRIPT"))
TIMERS=$1

# Not perfekt. For an axample during week 53 and week 1, which both will be bi-weekly
BIWEEK=$(($(date +%W) % 2));

# Do not run without any timer
if [ -z "$TIMERS" ]; then
	TIMERS=any
fi

# Calculate a bi-weekly run
case $TIMERS in
    weekly) 
    	if which xattr > /dev/null 2>&1; then
    		if xattr | grep -q user.last_run $SCRIPT; then
    	    	BIWEEK=$((($(xattr -p user.last_run $SCRIPT) + 1) % 2))
    	    fi
    	    
    	    xattr -w user.last_run $BIWEEK $SCRIPT >/dev/null 2>&1
    	
    	elif which getfattr > /dev/null 2>&1; then
    		if getfattr -n user.last_run $SCRIPT >/dev/null 2>&1; then
    	    	BIWEEK=$((($(getfattr -n user.last_run --only-values $SCRIPT) + 1) % 2))
    	    fi
    	    
    	    setfattr -n user.last_run -v $BIWEEK $SCRIPT >/dev/null 2>&1
    	fi
    	
    	if [ "$BIWEEK" != "0" ]; then
    		TIMERS="$TIMERS biweekly"
    	fi
    	
    	break
    ;;
    
    daily)
        DOM=$(date +%w)
    
        if [ $DOM -gt 0 ] && [ $DOM -lt 6 ]; then
        	TIMERS="$TIMERS weekdays"
        	
        else
        	TIMERS="$TIMERS weekends"
        fi
        
        case $DOM in
        	1) TIMERS="$TIMERS mondays" ;;
        	2) TIMERS="$TIMERS tuesdays" ;;
        	3) TIMERS="$TIMERS wednesdays" ;;
        	4) TIMERS="$TIMERS thursdays" ;;
        	5) TIMERS="$TIMERS fridays" ;;
        	6) TIMERS="$TIMERS saturdays" ;;
        	*) TIMERS="$TIMERS sundays" ;;
        esac
    ;;
    
    montly)
    	if [ $(date +%m) -eq 1 ]; then
    		TIMERS="$TIMERS annually"
    	fi
    	
    	if [ $(($(date +%m) % 3)) -eq 0 ]; then
    		TIMERS="$TIMERS quarterly"
    		
    	elif [ $(($(date +%m) % 6)) -eq 0 ]; then
    		TIMERS="$TIMERS semiannually"
    	fi
esac

for TIMER in $TIMERS; do
	for FILE in $BASEDIR/rc.cron.d/*.sh; do
		if [ -r $FILE ]; then
			if ! (echo $FILE | grep -q "@") || (echo $FILE | grep -qe "@\(any\|$TIMER\)\.sh$"); then
				$FILE $TIMER
			fi
		fi
	done
done
EOF

echo "Installing /etc/systemd/system/cron-startup.service"
sudo tee /etc/systemd/system/cron-startup.service > /dev/null <<EOF
[Unit]
  Description=Cronjob running @startup timer

[Service]
  Type=forking
  ExecStart=/etc/rc.cron startup
  TimeoutSec=0
  StandardOutput=tty
  RemainAfterExit=yes

[Install]
  WantedBy=multi-user.target
EOF

echo "Installing /etc/systemd/system/cron@.service"
sudo tee /etc/systemd/system/cron@.service > /dev/null <<EOF
[Unit]
  Description=Cronjob running @%i timer

[Service]
  Type=oneshot
  ExecStart=/etc/rc.cron %i
EOF

echo "Installing /etc/systemd/system/cron@.timer"
sudo tee /etc/systemd/system/cron@.timer > /dev/null <<EOF
[Unit]
  Description=Schedule a cronjob %i

[Timer]
  Persistent=true
  OnCalendar=%i
  Unit=cron@%i.service

[Install]
  WantedBy=timers.target
EOF

echo "Creating /etc/rc.cron.d/"
test -d /etc/rc.cron.d || sudo mkdir /etc/rc.cron.d

echo "Making /etc/rc.cron executable"
sudo chmod +x /etc/rc.cron

echo "Enaling @startup timer"
sudo systemctl enable -q cron-startup.service

echo "Enaling @hourly timer"
sudo systemctl enable -q --now cron@hourly.timer

echo "Enaling @daily timer"
sudo systemctl enable -q --now cron@daily.timer

echo "Enaling @weekly and @biweekly timer"
sudo systemctl enable -q --now cron@weekly.timer

echo "Enaling @montly timer"
sudo systemctl enable -q --now cron@monthly.timer

if ! (which xattr > /dev/null 2>&1) && ! (which getfattr > /dev/null 2>&1); then
	echo "Optional: Could not detect 'xattr' or 'attr'"
	echo "  - This is useful to make '@biweekly' more accurate"
fi

echo "Installation is complete"
