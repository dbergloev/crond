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

GLB_SELF=$0
GLB_NAME=$(basename $GLB_SELF)
GLB_BASEDIR=$(dirname $(realpath "$GLB_SELF"))
GLB_SCRIPTDIR=$GLB_BASEDIR/${GLB_NAME}.d
GLB_LOCKDIR=/var/lock
GLB_LOGDIR=/var/log
GLB_LOGSIZE=65536
GLB_PIDOF=$$
GLB_COND=$1

if [ -z "$GLB_COND" ]; then
	GLB_COND=any
fi

FNC_RET=
FNC_NUM=

dir-find_inode() {
	local dir=$1
	local inode=$2
	local file
	
	for file in $dir/*; do
		if [ -f $file ] && [ "$inode" = "`ls -i $file | awk '{print $1}'`" ]; then
			FNC_RET=$(readlink -f $file)
			FNC_NUM=$(ls -i $FNC_RET | awk '{print $1}')
			
			return 0
		fi
	done
	
	FNC_RET=
	FNC_NUM=0
	
	return 1
}

if echo $GLB_COND | grep -qe '^[0-9]\+:[a-z]\+$'; then
	inode=$(echo $GLB_COND | sed 's/:/ /' | awk '{print $1}')
	timer=$(echo $GLB_COND | sed 's/:/ /' | awk '{print $2}')
	
	if ! dir-find_inode $GLB_SCRIPTDIR $inode; then
		echo "$GLB_PIDOF: (bg) E - Could not find script with inode $inode" | tee -a $GLB_LOGDIR/$GLB_NAME.log; exit 1
	else
		script=$FNC_RET
		inode=$FNC_NUM
		
		if [ ! -r $script ]; then
			echo "$GLB_PIDOF: (bg) E - The script $script is not executable" | tee -a $GLB_LOGDIR/$GLB_NAME.log; exit 1
		fi
	fi
	
	(
		if ! flock --exclusive -w 20 200; then
			echo "$GLB_PIDOF: (bg) The script $script is already running, skipping..." | tee -a $GLB_LOGDIR/$GLB_NAME.log; exit 0
		fi
		
		echo "Pid: $GLB_PIDOF" >&200 # Store PID in lock file
		
		$script $timer
	
	) 200>$GLB_LOCKDIR/${GLB_NAME}:${inode}.elock

else
	case $GLB_COND in
		weekly) 
			# Not perfekt. For an axample during week 53 and week 1, which both will be bi-weekly
			biweek=$(($(date +%W) % 2));

			if which xattr > /dev/null 2>&1; then
				if xattr $GLB_SELF | grep -q user.last_run; then
			    	biweek=$((($(xattr -p user.last_run $GLB_SELF) + 1) % 2))
			    fi

			    xattr -w user.last_run $biweek $GLB_SELF >/dev/null 2>&1

			elif which getfattr > /dev/null 2>&1; then
				if getfattr $GLB_SELF | grep -q user.last_run; then
			    	biweek=$((($(getfattr -n user.last_run --only-values $GLB_SELF) + 1) % 2))
			    fi

			    setfattr -n user.last_run -v $biweek $GLB_SELF >/dev/null 2>&1
			fi

			if [ $biweek -ne 0 ]; then
				GLB_COND="$GLB_COND biweekly"
			fi

			break
		;;

		daily)
		    dow=$(date +%w)

		    if [ $dow -gt 0 ] && [ $dow -lt 6 ]; then
		    	GLB_COND="$GLB_COND weekdays"

		    else
		    	GLB_COND="$GLB_COND weekends"
		    fi

		    case $dow in
		    	1) GLB_COND="$GLB_COND mondays" ;;
		    	2) GLB_COND="$GLB_COND tuesdays" ;;
		    	3) GLB_COND="$GLB_COND wednesdays" ;;
		    	4) GLB_COND="$GLB_COND thursdays" ;;
		    	5) GLB_COND="$GLB_COND fridays" ;;
		    	6) GLB_COND="$GLB_COND saturdays" ;;
		    	*) GLB_COND="$GLB_COND sundays" ;;
		    esac
		;;

		montly)
			if [ $(date +%m) -eq 1 ]; then
				GLB_COND="$GLB_COND annually"
			fi

			if [ $(($(date +%m) % 3)) -eq 0 ]; then
				GLB_COND="$GLB_COND quarterly"

			elif [ $(($(date +%m) % 6)) -eq 0 ]; then
				GLB_COND="$GLB_COND semiannually"
			fi
	esac
	
	(
		flock --exclusive 200
		
		echo "Pid: $GLB_PIDOF" >&200 # Store PID in lock file
		
		if [ -f $GLB_LOGDIR/$GLB_NAME.log ] && [ $(wc -c $GLB_LOGDIR/$GLB_NAME.log | awk '{print $1}') -gt $GLB_LOGSIZE ]; then
			tail -c $GLB_LOGSIZE $GLB_LOGDIR/$GLB_NAME.log > $GLB_LOGDIR/$GLB_NAME-old.log
			echo "" > $GLB_LOGDIR/$GLB_NAME.log
		fi
		
		echo "$GLB_PIDOF: Launched at $(date '+%Y-%m-%d %H:%M') using timer [$GLB_COND], pid=$GLB_PIDOF" | tee -a $GLB_LOGDIR/$GLB_NAME.log
		
		for timer in $GLB_COND; do
			echo "$GLB_PIDOF: Using timer '$timer'" | tee -a $GLB_LOGDIR/$GLB_NAME.log
			
			for file in $GLB_SCRIPTDIR/*; do
				if [ -r $file ] && echo $file | grep -qe "\.\(sh\|shd\)$"; then
					if ! echo $file | grep -q "@" || echo $file | grep -qe "@\(any\|$timer\)\.\(sh\|shd\)$"; then
						if echo $file | grep -qe "\.shd$"; then
							echo "$GLB_PIDOF: Starting script $(basename $file) in detached process" | tee -a $GLB_LOGDIR/$GLB_NAME.log
							systemctl start cron-detached@$(ls -i $file | awk '{print $1}'):$timer
						
						else
							echo "$GLB_PIDOF: Running script $(basename $file) in current process" | tee -a $GLB_LOGDIR/$GLB_NAME.log
							$file $timer 2>&1 | tee -a $GLB_LOGDIR/$GLB_NAME.log
						fi
					fi
				fi
			done
		done
		
		echo "$GLB_PIDOF: Finished running at $(date '+%Y-%m-%d %H:%M')" | tee -a $GLB_LOGDIR/$GLB_NAME.log
	
	) 200>$GLB_LOCKDIR/${GLB_NAME}.elock
fi
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

echo "Installing /etc/systemd/system/cron-detached@.service"
sudo tee /etc/systemd/system/cron-detached@.service > /dev/null <<EOF
[Unit]
  Description=Cronjob running @%i detached process

[Service]
  Type=simple
  ExecStart=/etc/rc.cron %i
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

sudo systemctl daemon-reload

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

echo "Enaling @weekly timer"
sudo systemctl enable -q --now cron@weekly.timer

echo "Enaling @montly timer"
sudo systemctl enable -q --now cron@monthly.timer

if ! (which xattr > /dev/null 2>&1) && ! (which getfattr > /dev/null 2>&1); then
	echo "Optional: Could not detect 'xattr' or 'attr'"
	echo "  - This is useful to make '@biweekly' more accurate"
fi

echo "Installation is complete"
