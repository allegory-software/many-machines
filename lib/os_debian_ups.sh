#!/bin/bash

# Eaton 3S NUT setup for Debian - root-only, standalone, USB permissions fixed

install_ups() {

package_install nut

service_stop nut-server nut-monitor
service_disable nut-monitor # we monitor with mm mon
service_enable nut-driver-enumerator # enable hot-plugging the USB
pkill usbhid-ups

set +f
file=/lib/udev/rules.d/*-nut-usbups.rules
set -f
rm_file $file
save '
SUBSYSTEM=="usb", ATTR{idVendor}=="0463", ATTR{idProduct}=="ffff", MODE="0660", GROUP="nut"
' /etc/udev/rules.d/99-eaton-ups.rules

udevadm control --reload-rules
udevadm trigger

save '
[ups]
    driver = usbhid-ups
    port = auto
    desc = "Eaton 3S UPS"
' /etc/nut/ups.conf

save "
" /etc/nut/upsd.users

save "
LISTEN 127.0.0.1 3493
" /etc/nut/upsd.conf

save '
MODE=standalone
' /etc/nut/nut.conf

service_enable nut-server

}

uninstall_ups() {
	service_disable nut-server nut-driver-enumerator
}
