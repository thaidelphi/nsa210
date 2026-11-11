#!/ffp/bin/sh

# PROVIDE: optimize_nsa
# REQUIRE: LOGIN

. /ffp/etc/ffp.subr

name="optimize_nsa"
start_cmd="opt_start"

opt_start() {
    (
        sleep 15
        if [ -f /usr/local/dmsf/binary/mediaserver ] && [ ! -f /usr/local/dmsf/binary/mediaserver.real ]; then
            killall -9 mediaserver 2>/dev/null
            mv /usr/local/dmsf/binary/mediaserver /usr/local/dmsf/binary/mediaserver.real
            printf "#!/bin/sh\nexec sleep 864000\n" > /usr/local/dmsf/binary/mediaserver
            chmod +x /usr/local/dmsf/binary/mediaserver
            (/usr/local/dmsf/binary/mediaserver >/dev/null 2>&1 &)
        fi
        killall -9 dservice fileye.py fadd 2>/dev/null
    ) >/dev/null 2>&1 &
}

run_rc_command "$1"
