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
