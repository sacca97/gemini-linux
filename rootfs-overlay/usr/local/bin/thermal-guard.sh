#!/bin/sh
# Clean poweroff if the battery or a CPU zone stays too hot for two checks.
# Events go to /var/lib/thermal-guard.log (syslog is RAM only) and are synced.
BAT_MAX=550   # decidegrees C (55.0 C)
CPU_MAX=95000 # millidegrees C
LOG=/var/lib/thermal-guard.log
strikes=0

trip() {
	echo "$(date '+%F %T') $1, powering off" >> $LOG
	logger -t thermal-guard "$1, powering off"
	sync
	poweroff
}

while :; do
	hot=""
	bat=$(sed -n 's/^POWER_SUPPLY_TEMP=//p' /sys/class/power_supply/qcom-battery/uevent 2>/dev/null)
	if [ -n "$bat" ] && [ "$bat" -gt "$BAT_MAX" ]; then
		hot="battery ${bat} ddegC > ${BAT_MAX}"
	fi
	for z in /sys/class/thermal/thermal_zone*; do
		case "$(cat $z/type 2>/dev/null)" in cpu*) ;; *) continue ;; esac
		t=$(cat $z/temp 2>/dev/null) || continue
		if [ "$t" -gt "$CPU_MAX" ]; then
			hot="$(cat $z/type) ${t} mdegC > ${CPU_MAX}"
		fi
	done
	if [ -n "$hot" ]; then
		strikes=$((strikes + 1))
		[ "$strikes" -ge 2 ] && trip "$hot"
	else
		strikes=0
	fi
	sleep 30
done
