keep-cluster-compass
====================

Installs /data/opencmu/boot.d/61-cluster-compass.sh. Tweak 60 starts it at
boot, in the background.

What it does
------------
While the navigation service owns its bus name, the body control module lets
the touchscreen work above the speed threshold. When that service is not
running, the restriction comes back. The runtime watches NameOwnerChanged for
the navigation name on unix:path=/tmp/dbus_service_socket and sends:

    /usr/bin/dbus-send --address=unix:path=/tmp/dbus_service_socket \
      --type=signal --dest=com.jci.vbs.bcm /com/jci/vbs/bcm \
      com.jci.vbs.bcm.NoSpeedRestrict_TouchDisplay byte:1

when the service appears, and the same command with byte:0 when it goes away.

Controls
--------
    /data/opencmu/boot.d/61-cluster-compass.sh --status
    /data/opencmu/boot.d/61-cluster-compass.sh --stop
    /data/opencmu/boot.d/61-cluster-compass.sh --send 1
    /data/opencmu/boot.d/61-cluster-compass.sh --probe

--probe prints every NameOwnerChanged on the service bus. Open and close the
navigation app while it runs: the name you see is the one to put in
OPENCMU_NAVI_SERVICE if the default does not match.

Environment overrides (set them before starting it):
    OPENCMU_DBUS_SOCKET    default unix:path=/tmp/dbus_service_socket
    OPENCMU_NAVI_SERVICE   default com.jci.navi2NNG
    OPENCMU_COMPASS_LOG    default /data/opencmu/logs/cluster-compass.log

Rollback
--------
Stops the runtime on the live root and removes the boot entry. A dbus-monitor
left behind by a killed runtime exits on the next bus event.

Not verified on hardware
------------------------
The bus name, the socket, and the two signal bytes come from static analysis of
the reference agent. The runtime is a new implementation, not a copy, and has
not been exercised on a bench unit. Test it parked, with the navigation app
open and closed, before relying on it.
