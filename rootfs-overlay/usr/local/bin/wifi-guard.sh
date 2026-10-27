#!/bin/sh
# The QCA6174 sometimes misses PCIe link training at boot (about 1 boot in 8)
# and stays off the bus until the next boot. Reboot once or twice if that
# happens; a counter on the rootfs stops it from looping on dead hardware.
DEV=/sys/bus/pci/devices/0000:01:00.0
DIR=/var/lib/wifi-guard
MAX=2
mkdir -p $DIR
sleep 90
if [ -e $DEV ]; then
	rm -f $DIR/count
	exit 0
fi
n=$(cat $DIR/count 2>/dev/null || echo 0)
if [ "$n" -ge "$MAX" ]; then
	logger -t wifi-guard "no Wi-Fi on PCIe after $n reboots, giving up"
	exit 0
fi
echo $((n + 1)) > $DIR/count
logger -t wifi-guard "no Wi-Fi on PCIe, rebooting ($((n + 1))/$MAX)"
sync
reboot
