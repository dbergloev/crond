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

##
# Trap on error
set -euo pipefail
trap 'catch $?' EXIT SIGINT SIGTERM

##
# Function to deal with errors
# Start by checking if it exited with error
catch() {
    if [ "$1" != "0" ]; then
    	systemd-cat --priority=emerg --identifier=rc.cron -- echo "rc.cron exited with code $1"
    fi
}

find_inode() {
	local dir=$1
	local inode=$2
	local file
	
	for file in $dir/*; do
		if [ -f $file ] && [ "$inode" = "`ls -i $file | awk '{print $1}'`" ]; then
			find_inode_ret=$(readlink -f $file)
			find_inode_num=$(ls -i $find_inode_ret | awk '{print $1}')
			
			return 0
		fi
	done
	
	find_inode_ret=
	find_inode_num=0
	
	return 1
}

find_inode_ret=
find_inode_num=

timer=${1:-"any"}
self_pid=$$
self_name=$(basename $0)
self_path="$(dirname $(realpath "$0"))"
script_path="$self_path/${self_name}.d"
lock_path=/var/lock

if echo $timer | grep -qe '^[0-9]\+:'; then
	inode=$(echo $timer | awk -v 'FS=:' '{print $1}')
	timer=$(echo $timer | awk -v 'FS=:' '{print $2}')
	
	if ! find_inode $script_path $inode; then
		systemd-cat --priority=err --identifier=rc.cron#$inode -- echo "Could not find script with inode $inode"; exit 1
		
	else
		script=$find_inode_ret
		inode=$find_inode_num
		
		if [ ! -x $script ]; then
			systemd-cat --priority=err --identifier=rc.cron#$inode -- echo "The script $script is not executable"; exit 1
		fi
	fi
	
	if ! (
			if ! flock --exclusive -w 20 200; then
				systemd-cat --priority=notice --identifier=rc.cron#$inode -- echo "The script $script is already running in a background task, skipping..."; exit 0
			fi
			
			echo "Pid: $self_pid, Path: $script" >&200 # Store PID in lock file
			systemd-cat --stderr-priority=err --identifier=rc.cron#$inode -- $script $timer
		
		) 200>$lock_path/${self_name}:${inode}.elock
	
	then
		systemd-cat --priority=alert --identifier=rc.cron#$inode -- echo "The script $script exited with error $? using timer '$timer'"
	fi
	
	exit $?
fi

case $timer in
	weekly) 
		# Not perfekt. For an axample during week 53 and week 1, which both will be bi-weekly
		if [ $(($(date +%W) % 2)) -ne 0 ]; then
			timer="$timer biweekly"
		fi
	;;

	daily)
	    dow=$(date +%w)

	    if [ $dow -gt 0 ] && [ $dow -lt 6 ]; then
	    	timer="$timer weekdays"

	    else
	    	timer="$timer weekends"
	    fi

	    case $dow in
	    	1) timer="$timer mondays" ;;
	    	2) timer="$timer tuesdays" ;;
	    	3) timer="$timer wednesdays" ;;
	    	4) timer="$timer thursdays" ;;
	    	5) timer="$timer fridays" ;;
	    	6) timer="$timer saturdays" ;;
	    	*) timer="$timer sundays" ;;
	    esac
	;;

	montly)
		if [ $(date +%m) -eq 1 ]; then
			timer="$timer annually"
		fi

		if [ $(($(date +%m) % 3)) -eq 0 ]; then
			timer="$timer quarterly"

		elif [ $(($(date +%m) % 6)) -eq 0 ]; then
			timer="$timer semiannually"
		fi
	;;
esac

(
	flock --exclusive 200
	echo "Pid: $self_pid" >&200 # Store PID in lock file
	
	systemd-cat --priority=notice --identifier=rc.cron -- echo "Launched at $(date '+%Y-%m-%d %H:%M') using timer [$timer]"
	
	for arg in $timer; do
		systemd-cat --priority=info --identifier=rc.cron -- echo "Using timer '$arg'"
		
		for file in $script_path/*; do
			if [ -x $file ] && echo $file | grep -qe "\.\(sh\|shd\)$"; then
				if ! echo $file | grep -q "@" || echo $file | grep -qe "@\(any\|$arg\)\.\(sh\|shd\)$"; then
					if echo $file | grep -qe "\.shd$"; then
						inode=$(ls -i $file | awk '{print $1}')
					
						systemd-cat --priority=info --identifier=rc.cron -- echo "Starting script $(basename $file) (rc.cron#$inode) in detached process"
						systemctl start cron-detached@$inode:$arg
					
					else
						systemd-cat --priority=info --identifier=rc.cron -- echo "Running script $(basename $file) in main process"
						
						if ! systemd-cat --stderr-priority=err --identifier=rc.cron -- $file $arg; then
							systemd-cat --priority=alert --identifier=rc.cron -- echo "The script $(basename $file) exited with error $? using timer '$arg'"
						fi
					fi
				fi
			fi
		done
	done
	
	systemd-cat --priority=info --identifier=rc.cron -- echo "Finished running at $(date '+%Y-%m-%d %H:%M')"

) 200>$lock_path/${self_name}.elock
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

echo "Installing /etc/systemd/system/cron-shutdown.service"
sudo tee /etc/systemd/system/cron-shutdown.service > /dev/null <<EOF
[Unit]
  Description=Cronjob running @shutdown timer
  Before=shutdown.target

[Service]
  Type=oneshot
  ExecStart=/etc/rc.cron shutdown
  TimeoutSec=0

[Install]
  WantedBy=shutdown.target
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

echo "Enaling @shutdown timer"
sudo systemctl enable -q cron-shutdown.service

echo "Enaling @hourly timer"
sudo systemctl enable -q --now cron@hourly.timer

echo "Enaling @daily timer"
sudo systemctl enable -q --now cron@daily.timer

echo "Enaling @weekly timer"
sudo systemctl enable -q --now cron@weekly.timer

echo "Enaling @montly timer"
sudo systemctl enable -q --now cron@monthly.timer

echo "Installation is complete"
