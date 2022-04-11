# crond

Both `crontab` and `rc.local` has been more or less removed or disabled on many distro's. Systemd is replacing most of the old features, and that is fine. It's a hell of a lot better than older init systems, crontab etc. _(it is, deal with it)_, but it's also more complex if you just want to quickly add a script during boot or to run each hour or each day. These are basic things that should be much quicker to add, which is what this small install script provides. 

It creates a cron/startup script that will run custom scripts _(/etc/rc.cron.d/)_ depending on different timers that is provided by the filename itself. It is fast and simple to add and remove scripts and it covers most basic needs. 

### Adding a script

Simply create a script `/etc/rc.cron.d/name@timer.sh` and fill it with your required code. There are many timers to use: 

| Timer | Description |
| -- | -- | 
| @startup | Run when the system boots |
| @hourly | Run ones every hour |
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

 > Note that in detached mode, output from the scripts process is not gonna be redirected to the log file

### Installation

Just download and run the script from a terminal

```sh
wget https://raw.githubusercontent.com/dk-zero-cool/crond/main/crond_install.sh
chmod +x crond_install.sh
./crond_install.sh
```

Further help Linus' of the world? https://www.cyberciti.biz/faq/how-to-execute-a-shell-script-in-linux/

### Multiple Timers

Even though you can run all timers against one script by naming it `@any` or leaving out any timer in the name, a better way is using links, unless you absolutly must run it against __ALL__ timers. Even if you filter out the timers you don't need within the script, the script is still executed which does produce a litle overheat, especially if it is executed as a detached process. Instead leave out the extenstion `.sh` and `.shd` and create links for the required timers.

```sh
# ls -l /etc/rc.cron.d/
-rwxr-xr-x 1 root root  000 xxx 0 0:00 myscript
lrwxrwxrwx 1 root root    0 xxx 0 0:00 myscript@daily.shd -> myscript
lrwxrwxrwx 1 root root    0 xxx 0 0:00 myscript@montly.shd -> myscript
lrwxrwxrwx 1 root root    0 xxx 0 0:00 myscript@quarterly.shd -> myscript
lrwxrwxrwx 1 root root    0 xxx 0 0:00 myscript@weekly.shd -> myscript
```
