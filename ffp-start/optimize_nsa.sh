#!/ffp/bin/sh

# PROVIDE: optimize_nsa
# REQUIRE: LOGIN

. /ffp/etc/ffp.subr

name="optimize_nsa"
start_cmd="opt_start"

opt_start() {
    (
        sleep 10
        # 1. Hardware & Kernel SATA Protection against Oxford OX810 DMA Overload
        if [ -f /sys/block/sda/queue/nr_requests ]; then
            echo 32 > /sys/block/sda/queue/nr_requests
        fi

        # Flush dirty pages in small frequent chunks
        if [ -f /proc/sys/vm/dirty_writeback_centisecs ]; then
            echo 200 > /proc/sys/vm/dirty_writeback_centisecs
            echo 500 > /proc/sys/vm/dirty_expire_centisecs
            echo 10 > /proc/sys/vm/dirty_ratio
            echo 5 > /proc/sys/vm/dirty_background_ratio
        fi

        # Auto-reboot 10 seconds after kernel panic
        if [ -f /proc/sys/kernel/panic ]; then
            echo 10 > /proc/sys/kernel/panic
        fi

        # 2. Stop mediaserver and replace with lightweight dummy sleep to satisfy app_wd
        if [ -f /usr/local/dmsf/binary/mediaserver ] && [ ! -f /usr/local/dmsf/binary/mediaserver.real ]; then
            killall -9 mediaserver 2>/dev/null
            mv /usr/local/dmsf/binary/mediaserver /usr/local/dmsf/binary/mediaserver.real
            printf "#!/bin/sh\nexec sleep 864000\n" > /usr/local/dmsf/binary/mediaserver
            chmod +x /usr/local/dmsf/binary/mediaserver
            (/usr/local/dmsf/binary/mediaserver >/dev/null 2>&1 &)
        fi

        # 3. Stop unwanted ZyXEL bloatware services
        killall -9 dservice fileye.py fadd 2>/dev/null

        # 4. Restore Persistent Samba Configuration for Windows 11 & [download] share
        if [ -f /ffp/etc/smb.conf ]; then
            if ! grep -q '\[download\]' /etc/samba/smb.conf 2>/dev/null; then
                cp /ffp/etc/smb.conf /etc/samba/smb.conf
                killall -9 smbd nmbd 2>/dev/null
                sleep 1
                /usr/sbin/nmbd -D
                /usr/sbin/smbd -D
            fi
        fi

        # 5. Clean memory caches
        echo 3 > /proc/sys/vm/drop_caches
    ) >/dev/null 2>&1 &
}

run_rc_command "$1"
