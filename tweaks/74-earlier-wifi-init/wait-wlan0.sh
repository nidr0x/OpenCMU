# [opencmu:earlier-wifi-init] wait for wlan0 (modules are loaded by stage_wifi.sh)
_opencmu_ewi=20
while [ ! -e /sys/class/net/wlan0 ] && [ "$_opencmu_ewi" -ne 0 ]; do
    _opencmu_ewi=$((_opencmu_ewi - 1))
    sleep 0.5
done
mkdir -p /data/opencmu/logs 2>/dev/null
echo "[opencmu] earlier-wifi-init: wlan0 ready after $(((20 - _opencmu_ewi) * 500))ms" >> /data/opencmu/logs/boot.log 2>/dev/null
