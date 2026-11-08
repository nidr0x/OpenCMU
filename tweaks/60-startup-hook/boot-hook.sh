
# [opencmu:boot-hook] run user hooks in the background; never block this stage
if [ -d /data/opencmu/boot.d ]; then
    for _opencmu_hook in /data/opencmu/boot.d/*.sh; do
        [ -x "$_opencmu_hook" ] || continue
        "$_opencmu_hook" >/dev/null 2>&1 &
    done
    unset _opencmu_hook
fi
