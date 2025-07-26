# RC-Cron

Both `crontab` and `rc.local` has been more or less removed or disabled on many distro's. Systemd is replacing most of the old features, and that is fine. It's a hell of a lot better than older init systems, crontab etc., but it's also more complex if you just want to quickly add a script during boot or to run each hour or each day. These are basic things that should be much quicker to add, which is a feature that this provides and more. 

RC-Cron merges the old `crontab` and `rc.local` within a single and much more powerful design. It allows you to quickly add scripts and have them being executed during boot, shutdown, on various timers and more, just by using a simple naming convention for their filenames. It can even be used to add other event based injections from other systems and allows scripts to be executed on the main RC-Cron thread or as a background daemon for longer running scripts. 

### Adding a script

Simply create a script `/etc/rc.cron.d/name@timer.sh` and fill it with your required code. There are many timers to use: 

| Timer | Description |
| -- | -- | 
| @startup | Run when the system boots |
| @shutdown | Run when the system shuts down |
| @network | Run when the network has been brought up |
| @hourly | Run ones every hour |
| @quarter-hourly | Run ones every 15 minutes |
| @daily | Run ones every day |
| @weekly | Run ones every week |
| @biweekly | Run ones every two weeks |
| @montly | Run ones every month |
| @quarterly | Run every 3 months |
| @semiannually | Run every 6 months |
| @annually | Run ones every year | 
| @weekday | Run only every weekday, monday through friday |
| @weekend | Run only on weekends, saturday and sunday |
| @any | Run on all timers | 

_The `@any` timer will match any timer that is run. The timer that was initiated can be fetched via the first argument `$1` within a script._

You can also have it run on a specific day each week

| Timer | Description |
| -- | -- | 
| @mondays | Run every monday |
| @tuesdays | Run every tuesday |
| @wednesdays | Run every wednesday |
| @thursdays | Run every thursday |
| @fridays | Run every friday |
| @saturdays | Run every saturday |
| @sundays | Run every sunday |

### Timer-less filenames 

If a file does not provide `@timer` in it's filename, it will be the same as `@any`. So `myscript@any.sh` is the same as simply `myscript.sh`. 

### Detached scripts

You can run a script in detached mode _(background without being coupled/depended on the main process)_. To do this, simply use the `.shd` file extension instead of `.sh`

| File Extension | Description |
| -- | -- |
| script@timer.sh | This will run in the main process. The main process will wait for this script to finish. | 
| script@timer.shd | This will run in it's own detached process. The main process will continue to the next script. |

### Multiple Timers

Even though you can run all timers against one script by naming it `@any`, a better way is using links, unless you absolutely must run it against __ALL__ timers. Even if you filter out the timers you don't need within the script, the script is still executed which does produce a little overheat, especially if it is executed as a detached process. Instead leave out the extension `.sh` and `.shd` and create links for the required timers.

```sh
# ls -l /etc/rc.cron.d/
-rwxr-xr-x 1 root root  000 xxx 0 0:00 myscript
lrwxrwxrwx 1 root root    0 xxx 0 0:00 myscript@daily.shd -> myscript
lrwxrwxrwx 1 root root    0 xxx 0 0:00 myscript@montly.shd -> myscript
lrwxrwxrwx 1 root root    0 xxx 0 0:00 myscript@quarterly.shd -> myscript
lrwxrwxrwx 1 root root    0 xxx 0 0:00 myscript@weekly.shd -> myscript
```

### Logs

The main log can be found in `journalctl` within the identifier `rc.cron`

```sh
$ journalctl -t rc.cron
```

Each detached process will have their own log entries using identifiers `rc.cron#<number>` where `<number>` is the script inode. You can find reference to this within the main log: 

```sh
$ journalctl -t rc.cron
<date> rc.cron: Starting script <file> (rc.cron#<inode>) in detached process
```

From here you can access the log entry from the detached script: 

```sh
$ journalctl -t rc.cron#<inode>
```

### Custom Events

By default RC-Cron is executed by `systemd` on various triggers, but it is not limited to this. 

Let's look at an example where we add `ufw` events for when the firewall is enabled or disabled. 

 * /etc/ufw/after.init
 
    ```sh
    case "$1" in
        start)
            /etc/rc.cron ufw enable
        ;;
    esac
    ```
    
 * /etc/ufw/before.init
 
    ```sh
    case "$1" in
        stop)
            /etc/rc.cron ufw disable
        ;;
    esac
    ```
    
Now you can create a script `/etc/rc.cron.d/rules@ufw.sh`

```sh
case "$2" in
    enable)
        iptables -A ...
    ;;
    
    disable)
        iptables -D ...
    ;;
esac
```

### Installation

Just download and run the script from a terminal

```sh
wget https://raw.githubusercontent.com/dk-zero-cool/crond/main/crond_install.sh
chmod +x crond_install.sh
./crond_install.sh
```
