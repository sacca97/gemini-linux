#!/bin/sh
# Drive the charger's charge_behaviour (auto / inhibit-charge) from MODE in
# /etc/conf.d/battery-mode. Always falls back to normal charging on exit.
USB=/sys/class/power_supply/qcom-smbchg-usb
BAT=/sys/class/power_supply/qcom-battery
CONF=/etc/conf.d/battery-mode

set_behaviour() {
	cur=$(sed 's/.*\[\(.*\)\].*/\1/' $USB/charge_behaviour)
	[ "$cur" = "$1" ] && return
	echo "$1" > $USB/charge_behaviour && logger -t battery-mode "charge_behaviour -> $1 (capacity ${cap}%)"
}

nap() { sleep 30 & wait $!; }
trap 'kill $! 2>/dev/null; set_behaviour auto; exit 0' INT TERM
inhibit_hold=0
while :; do
	MODE=auto LIMIT_LOW=70 LIMIT_HIGH=80 FLOOR=20
	. $CONF
	cap=$(cat $BAT/capacity 2>/dev/null)
	online=$(cat $USB/online 2>/dev/null)
	case "$cap" in ''|*[!0-9]*) set_behaviour auto; nap; continue ;; esac
	case "$MODE" in
	bypass)
		if [ "$cap" -le "$FLOOR" ]; then inhibit_hold=1; fi
		if [ "$cap" -ge $((FLOOR + 10)) ]; then inhibit_hold=0; fi
		if [ "$inhibit_hold" = 1 ]; then set_behaviour auto; else set_behaviour inhibit-charge; fi ;;
	limit)
		if [ "$cap" -ge "$LIMIT_HIGH" ]; then set_behaviour inhibit-charge
		elif [ "$cap" -le "$LIMIT_LOW" ]; then set_behaviour auto; fi ;;
	*) set_behaviour auto ;;
	esac
	nap
done
