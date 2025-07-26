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

##
# Find a script based on it's inode number
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

# Return arguments for the 'find_inode' function
find_inode_ret=
find_inode_num=

timer=${1:-"any"}
inode=
args=( )
self_pid=$$
self_name=$(basename $0)
self_path="$(dirname $(realpath "$0"))"
script_path="$self_path/${self_name}.d"
lock_path=/var/lock

case "$#" in
    0)
        echo "Invalid number of arguments!" >&2; exit 1
    ;;
    
    1)
        ##
        # Systemd arguments passing
        #   * timer
        #   * timer:arg1[:arg2:...]
        #   * inode:timer
        #   * inode:timer:arg1[:arg2:...]
        #
        IFS=':' read -r -a parts <<< "$timer"
        if [[ "${parts[0]}" =~ ^[0-9]+$ ]]; then
            inode="${parts[0]}"
            timer="${parts[1]}"
            args=("${parts[@]:2}")

        else
            timer="${parts[0]}"
            args=("${parts[@]:1}")
        fi
    ;;
    
    *)
        ##
        # Normal argument passing
        #   * timer arg1 [arg2 ...]
        #
        shift
        for arg in "$@"; do
            args+=("$arg")
        done
    ;;
esac

##
# If we have an inode, then this script was launched in daemon mode
# 
if [ -n "$inode" ]; then
	if ! find_inode $script_path $inode; then
		systemd-cat --priority=err --identifier=rc.cron#$inode -- echo "Could not find script with inode $inode"; exit 1
		
	else
		script=$find_inode_ret
		inode=$find_inode_num
		
		if [ ! -x $script ]; then
			systemd-cat --priority=err --identifier=rc.cron#$inode -- echo "The script $script is not executable"; exit 1
		fi
	fi
	
	ret=0
	
	if ! (
			if ! flock --exclusive -w 180 200; then
				systemd-cat --priority=notice --identifier=rc.cron#$inode -- echo "The script $script is already running in a background task, skipping..."; exit 0
			fi
			
			echo "Pid: $self_pid, Path: $script" >&200 # Store PID in lock file
			systemd-cat --stderr-priority=err --identifier=rc.cron#$inode -- $script $timer "${args[@]}"
		
		) 200>$lock_path/${self_name}:${inode}.elock
	
	then
	    ret=$?
		systemd-cat --priority=alert --identifier=rc.cron#$inode -- echo "The script $script exited with error $ret using timer '$timer'"
	fi
	
	exit $ret
fi

##
# Fill in related timers
#
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

##
# Normal cron call from systemd
#
(
	flock --exclusive 200
	echo "Pid: $self_pid" >&200 # Store PID in lock file
	ret=0
	
	systemd-cat --priority=notice --identifier=rc.cron -- echo "Launched at $(date '+%Y-%m-%d %H:%M') using timer [$timer]"
	
	for x in $timer; do
		systemd-cat --priority=info --identifier=rc.cron -- echo "Using timer '$x'"
		
		for file in $script_path/*; do
			if [ -x $file ] && echo $file | grep -qe "\.\(sh\|shd\)$"; then
				if ! echo $file | grep -q "@" || echo $file | grep -qe "@\(any\|$x\)\.\(sh\|shd\)$"; then
					if echo $file | grep -qe "\.shd$"; then
						inode=$(ls -i $file | awk '{print $1}')
					
					    # We need the root inode for logging in case of symlinks
					    find_inode $script_path $inode
					    
						systemd-cat --priority=info --identifier=rc.cron -- echo "Starting script $(basename $file) (rc.cron#$find_inode_num) in detached process"
						
						if [ ${#args[@]} -gt 0 ]; then
						    systemctl start cron-detached@$inode:$x:$(IFS=:; echo "${args[*]}")
						
						else
						    systemctl start cron-detached@$inode:$x
						fi
					
					else
						systemd-cat --priority=info --identifier=rc.cron -- echo "Running script $(basename $file) in main process"
						
						if ! systemd-cat --stderr-priority=err --identifier=rc.cron -- $file $x "${args[@]}"; then
						    ret=$?
							systemd-cat --priority=alert --identifier=rc.cron -- echo "The script $(basename $file) exited with error $ret using timer '$x'"
						fi
					fi
				fi
			fi
		done
	done
	
	systemd-cat --priority=info --identifier=rc.cron -- echo "Finished running at $(date '+%Y-%m-%d %H:%M')"
	
	exit $ret

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
DefaultDependencies=no
Conflicts=shutdown.target
Before=shutdown.target

[Service]
Type=oneshot
ExecStart=/etc/rc.cron shutdown
TimeoutStartSec=120

[Install]
WantedBy=multi-user.target
EOF

echo "Installing /etc/systemd/system/cron-network.service"
sudo tee /etc/systemd/system/cron-network.service > /dev/null <<EOF
[Unit]
  Description=Cronjob running @network timer
  Wants=network-online.target
  After=network.target network-online.target

[Service]
  Type=oneshot
  ExecStart=/etc/rc.cron network
  
[Install]
  WantedBy=multi-user.target
EOF

echo "Installing /etc/systemd/system/cron-detached@.service"
sudo tee /etc/systemd/system/cron-detached@.service > /dev/null <<EOF
[Unit]
  Description=Cronjob running @%i timer

[Service]
  Type=oneshot
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

echo "Installing /etc/systemd/system/cron-quarter-hourly.timer"
sudo tee /etc/systemd/system/cron-quarter-hourly.timer > /dev/null <<EOF
[Unit]
  Description=Schedule a cronjob quarter-hourly

[Timer]
  Persistent=true
  OnCalendar=*:0/15
  Unit=cron@quarter-hourly.service

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

echo "Enaling @network timer"
sudo systemctl enable -q cron-network.service

echo "Enaling @hourly timer"
sudo systemctl enable -q --now cron@hourly.timer

echo "Enaling @quarter-hourly timer"
sudo systemctl enable -q --now cron-quarter-hourly.timer

echo "Enaling @daily timer"
sudo systemctl enable -q --now cron@daily.timer

echo "Enaling @weekly timer"
sudo systemctl enable -q --now cron@weekly.timer

echo "Enaling @montly timer"
sudo systemctl enable -q --now cron@monthly.timer

echo "Installation is complete"
