    # [opencmu:firewall-iptables-restore] restore the whole WCP ruleset in one call
    if [ "WCP" = "$1" ]; then
        insmod /lib/modules/3.0.35/kernel/net/netfilter/xt_hashlimit.ko 2>/dev/null
        if /usr/sbin/iptables-restore < /jci/scripts/jci-fw-wcp.rules &&
           /usr/sbin/iptables -L INPUT -n 2>/dev/null | head -1 | grep -q "policy DROP"; then
            log "opencmu: iptables-restore fast path active"
            return 0
        fi
        log "opencmu: iptables-restore did not yield a DROP policy; keeping the per-rule install"
    fi
