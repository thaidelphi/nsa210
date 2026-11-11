#!/ffp/bin/perl
use strict;
use warnings;
use IO::Socket::INET;
use IO::Select;
use Socket;

$| = 1; # autoflush
my $PORT = 8888;
my $CURL = '/usr/local/zy-pkgs/bin/curl-8.14';
my $TR_REMOTE = 'LD_LIBRARY_PATH=/usr/local/zy-pkgs/lib /usr/local/zy-pkgs/bin/transmission-remote';
my $TORRENT_DIR = '/etc/zyxel/zy-pkgs/Transmission/torrents';
my $LOG_FILE = '/usr/local/zy-pkgs/config/Transmission/tracker_proxy.log';
my $MAX_LOG_SIZE = 512000; # 500 KB

my %DNS_CACHE = (
    'sv-seed.com'       => '104.21.38.140',
    'files.bit-sv.net'  => '104.26.0.225',
    'files.bit-sv.cc'   => '172.67.74.62',
);

sub resolve_host {
    my ($host) = @_;
    $host =~ s/:\d+$//; # remove port if present
    return $DNS_CACHE{$host} if $DNS_CACHE{$host};
    my $packed = inet_aton($host);
    if ($packed) {
        my $ip = inet_ntoa($packed);
        $DNS_CACHE{$host} = $ip;
        return $ip;
    }
    return undef;
}

sub auto_patch_torrents {
    my $list = `$TR_REMOTE -l 2>/dev/null`;
    return unless $list;
    while ($list =~ /^\s*(\d+)\s+/mg) {
        my $id = $1;
        next if $id == 0;
        my $tinfo = `$TR_REMOTE -t $id -it 2>/dev/null`;
        next unless $tinfo;
        
        # Check if there is an unproxied https tracker
        while ($tinfo =~ /Tracker (\d+):\s*(https:\/\/([^\s:\/]+)[^\r\n\s]*)/g) {
            my ($tid, $raw_tracker, $thost) = ($1, $2, $3);
            # Find the original announce URL from the .torrent file
            my $name_info = `$TR_REMOTE -t $id -i 2>/dev/null`;
            if ($name_info =~ /Hash:\s*([a-f0-9]+)/i) {
                my $hash_prefix = lc(substr($1, 0, 16));
                my @tfiles = glob("$TORRENT_DIR/*$hash_prefix*.torrent");
                for my $tf (@tfiles) {
                    if (open(my $th, "<:raw", $tf)) {
                        local $/;
                        my $content = <$th>;
                        close($th);
                        if ($content =~ /d8:announce(\d+):/s) {
                            my $len = $1;
                            my $pos = $+[0];
                            my $announce_url = substr($content, $pos, $len);
                            if ($announce_url =~ m{^https://([^/]+)(/.*)$}) {
                                my ($host, $path) = ($1, $2);
                                my $proxy_url = "http://127.0.0.1:8888/proxy/$host$path";
                                print "Auto-patching torrent $id tracker $tid -> $proxy_url\n";
                                system("$TR_REMOTE -t $id -td '$proxy_url' >/dev/null 2>&1");
                                system("$TR_REMOTE -t $id -tr $tid >/dev/null 2>&1");
                                system("$TR_REMOTE -t $id --reannounce >/dev/null 2>&1");
                                system("$TR_REMOTE -t $id -s >/dev/null 2>&1");
                            }
                        }
                    }
                }
            }
        }
    }
}

my $is_throttled = 0;
my $is_thermal_throttled = 0;
my $high_load_count = 0;
my $low_load_count = 0;

sub check_hardware_watchdog {
    my $ts = scalar localtime();

    # 1. CPU & I/O Load average check
    my $load = 0;
    if (open(my $lf, "<", "/proc/loadavg")) {
        my $line = <$lf>;
        close($lf);
        if ($line =~ /^([\d\.]+)/) {
            $load = $1;
        }
    }

    # 2. Temperature & Fan check from /proc/therm-fan
    my $temp = 0;
    my $fan = 0;
    if (open(my $tf, "<", "/proc/therm-fan")) {
        while (<$tf>) {
            $temp = $1 / 10.0 if /temperature\s*==\s*(\d+)/;
            $fan  = $1 if /measured-fan_speed\s*==\s*(\d+)/;
        }
        close($tf);
    }

    # Thermal throttle if temp >= 50.0 C
    if ($temp >= 50.0 && !$is_thermal_throttled) {
        $is_thermal_throttled = 1;
        system("$TR_REMOTE -d 800 >/dev/null 2>&1");
        print "[$ts] [Thermal Guard] High Temperature detected (${temp} C >= 50 C, Fan: ${fan} RPM) -> Throttling download speed to 800 kB/s to cool down\n";
    } elsif ($temp > 0 && $temp <= 44.0 && $is_thermal_throttled) {
        $is_thermal_throttled = 0;
        if (!$is_throttled) {
            system("$TR_REMOTE -D >/dev/null 2>&1");
            print "[$ts] [Thermal Guard] Temperature cooled down (${temp} C <= 44 C) -> Restoring full download speed\n";
        }
    }

    # Load throttle if load >= 1.8 for 60s
    if ($load >= 1.8) {
        $high_load_count++;
        $low_load_count = 0;
        if ($high_load_count >= 2 && !$is_throttled && !$is_thermal_throttled) {
            $is_throttled = 1;
            system("$TR_REMOTE -d 1200 >/dev/null 2>&1");
            print "[$ts] [CPU Watchdog] High load detected ($load >= 1.8 for 60s, Temp: ${temp} C) -> Throttling download speed to 1,200 kB/s to protect CPU\n";
        }
    } elsif ($load <= 1.1) {
        $low_load_count++;
        $high_load_count = 0;
        if ($low_load_count >= 2 && $is_throttled && !$is_thermal_throttled) {
            $is_throttled = 0;
            system("$TR_REMOTE -D >/dev/null 2>&1");
            print "[$ts] [CPU Watchdog] Load normalized ($load <= 1.1 for 60s) -> Restoring full unlimited download speed\n";
        }
    } else {
        $high_load_count = 0;
        $low_load_count = 0;
    }
}

my $server = IO::Socket::INET->new(
    LocalHost => '127.0.0.1',
    LocalPort => $PORT,
    Proto     => 'tcp',
    Listen    => 20,
    Reuse     => 1
) or die "Cannot bind to 127.0.0.1:$PORT: $!\n";

my $select = IO::Select->new($server);
print "Tracker proxy listening on 127.0.0.1:$PORT\n";

my $last_check = 0;

while (1) {
    my $now = time();
    if ($now - $last_check >= 30) {
        $last_check = $now;

        # Rotate log if it exceeds 500 KB to protect storage/RAM
        if (-f $LOG_FILE && -s $LOG_FILE > $MAX_LOG_SIZE) {
            rename($LOG_FILE, "$LOG_FILE.old");
            if (open(my $lh, ">", $LOG_FILE)) {
                close($lh);
            }
        }

        check_hardware_watchdog();
        auto_patch_torrents();
    }
    
    my @ready = $select->can_read(10);
    for my $fh (@ready) {
        if ($fh == $server) {
            my $client = $server->accept();
            next unless $client;
            
            my $req_line = <$client>;
            next unless defined $req_line;
            
            while (my $line = <$client>) {
                $line =~ s/\r?\n$//;
                last if $line eq '';
            }
            
            if ($req_line =~ /^GET\s+([^\s]+)\s+HTTP/i) {
                my $url_path = $1;
                
                # Check for disabled tracker requests
                if ($url_path =~ m{^/disabled}) {
                    my $err = "d14:failure reason16:Tracker disablede";
                    binmode($client);
                    print $client "HTTP/1.0 200 OK\r\n";
                    print $client "Content-Type: text/plain\r\n";
                    print $client "Content-Length: " . length($err) . "\r\n";
                    print $client "Connection: close\r\n\r\n";
                    print $client $err;
                    close($client);
                    next;
                }
                
                my ($target_host, $target_path);
                
                if ($url_path =~ m{^/proxy/([^/]+)(/.*)$}) {
                    $target_host = $1;
                    $target_path = $2;
                } elsif ($url_path =~ m{^/announce}) {
                    $target_host = 'sv-seed.com';
                    $target_path = $url_path;
                } elsif ($url_path =~ m{^/([^/]+)(/announce.*)$}) {
                    $target_host = $1;
                    $target_path = $2;
                } else {
                    $target_host = 'sv-seed.com';
                    $target_path = $url_path;
                }
                
                # Strip port if in host
                $target_host =~ s/:\d+$//;
                my $ip = resolve_host($target_host);
                
                if ($ip) {
                    my $target_url = "https://$target_host$target_path";
                    
                    my @cmd = (
                        $CURL,
                        '-s', '-k',
                        '--resolve', "$target_host:443:$ip",
                        '-H', 'User-Agent: Transmission/2.94',
                        $target_url
                    );
                    
                    my $response_body = '';
                    if (open(my $ch, "-|", @cmd)) {
                        binmode($ch);
                        local $/;
                        $response_body = <$ch> // '';
                        close($ch);
                    }
                    
                    my $exit_code = $? >> 8;
                    
                    if ($exit_code == 0 && length($response_body) > 0) {
                        binmode($client);
                        print $client "HTTP/1.0 200 OK\r\n";
                        print $client "Content-Type: text/plain\r\n";
                        print $client "Content-Length: " . length($response_body) . "\r\n";
                        print $client "Connection: close\r\n\r\n";
                        print $client $response_body;
                    } else {
                        my $err = "d14:failure reason25:Proxy error calling HTTPSe";
                        print $client "HTTP/1.0 200 OK\r\n";
                        print $client "Content-Type: text/plain\r\n";
                        print $client "Content-Length: " . length($err) . "\r\n";
                        print $client "Connection: close\r\n\r\n";
                        print $client $err;
                    }
                } else {
                    my $err = "d14:failure reason20:Could not resolve DNE";
                    print $client "HTTP/1.0 200 OK\r\n";
                    print $client "Content-Type: text/plain\r\n";
                    print $client "Content-Length: " . length($err) . "\r\n";
                    print $client "Connection: close\r\n\r\n";
                    print $client $err;
                }
            }
            close($client);
        }
    }
}
