package CloudForecast::Data::Memcached;

use CloudForecast::Data -base;
use IO::Socket::INET;

=head1 NAME

CloudForecast::Data::Memcached - memcached resource monitor

=head1 SYNOPSIS

  host_config)

    resources:
      - memcached[[:port]:title]]

  eg)
    - memcached  # memcachedを11211で動かしている場合
    - memcached:11212 # ほかのportで起動
    - memcached:1978:tokyotyrant # tokyotyrantを関する場合

=cut

rrds map { [$_,'COUNTER'] } qw/cmdget cmdset gethits getmisses/;
rrds map { [$_,'GAUGE'] } qw/rate used max/;
graphs 'usage' => 'memcached usage';
graphs 'count' => 'memcached request count';
graphs 'rate' => 'memcached hit rate';

title {
    my $c = shift;
    my $title = $c->args->[1] || "memcached";
    if ( my $port = $c->args->[0] ) {
        $title .= " ($port)";
    }
    return $title;
};

sysinfo {
    my $c = shift;
    $c->ledge_get('sysinfo') || [];
};

fetcher {
    my $c = shift;

    my $host = $c->address;
    my $port = $c->args->[0] || 11211;
    my $sock = IO::Socket::INET->new(
        PeerAddr => $host,
        PeerPort => $port,
        Proto    => 'tcp',
        Blocking => 0,
    );
    my $fbits = '';
    vec($fbits, fileno($sock), 1) = 1;
    my $found = select( undef, $fbits, undef, 3.5 );

    die "could not connecet to $host:$port" unless $found;

    $sock->blocking(1);
    $sock->syswrite("stats\r\n");
    my $raw_stats;
    $sock->sysread( $raw_stats, 8192 );

    my %stats;
    foreach my $line ( split /\r?\n/, $raw_stats ) {
        if ( $line =~ /^STAT\s([^ ]+)\s(.+)$/ ) {
            $stats{$1} = $2;
        }
    }
    
    my @sysinfo;
    if ( $stats{version} ) {
        push @sysinfo, 'version' => $stats{version};
    }
    if ( my $uptime = $stats{uptime} ) {
        my $day = int( $uptime /86400 );
        my $hour = int( ( $uptime % 86400 ) / 3600 );
        my $min = int( ( ( $uptime % 86400 ) % 3600) / 60 );
        push @sysinfo, 'uptime' =>  sprintf("up %d days, %2d:%02d", $day, $hour, $min);
    }
    $c->ledge_set( 'sysinfo', \@sysinfo );

    return [ $stats{cmd_get}, $stats{cmd_set}, $stats{get_hits}, $stats{get_misses},
             undef, $stats{bytes}, $stats{limit_maxbytes} ];
};


__DATA__
@@ usage
DEF:my1=<%RRD%>:used:AVERAGE
DEF:my2=<%RRD%>:max:AVERAGE
AREA:my1#eaaf00:Used 
GPRINT:my1:LAST:Cur\: %2.2lf%sB
GPRINT:my1:AVERAGE:Ave\: %2.2lf%sB
GPRINT:my1:MAX:Max\: %2.2lf%sB
GPRINT:my1:MIN:Min\: %2.2lf%sB\c
LINE:my2#333333:Max 
GPRINT:my2:LAST:Cur\: %2.2lf%sB 
GPRINT:my2:AVERAGE:Ave\: %2.2lf%sB 
GPRINT:my2:MAX:Max\: %2.2lf%sB 
GPRINT:my2:MIN:Min\: %2.2lf%sB\c

@@ count
DEF:my1a=<%RRD%>:cmdset:AVERAGE
DEF:my2a=<%RRD%>:cmdget:AVERAGE
CDEF:my1=my1a,0,100000,LIMIT
CDEF:my2=my2a,0,100000,LIMIT
AREA:my1#00C000:Set  
GPRINT:my1:LAST:Cur\: %6.1lf
GPRINT:my1:AVERAGE:Ave\: %6.1lf
GPRINT:my1:MAX:Max\: %6.1lf
GPRINT:my1:MIN:Min\: %6.1lf\c
STACK:my2#0000C0:Get  
GPRINT:my2:LAST:Cur\: %6.1lf
GPRINT:my2:AVERAGE:Ave\: %6.1lf
GPRINT:my2:MAX:Max\: %6.1lf
GPRINT:my2:MIN:Min\: %6.1lf\c


@@ rate
DEF:hits=<%RRD%>:gethits:AVERAGE
DEF:misses=<%RRD%>:getmisses:AVERAGE
CDEF:total=hits,misses,+
CDEF:rate=hits,total,/,100,*,0,100,LIMIT
AREA:rate#990000:RATE  
GPRINT:rate:LAST:Cur\: %4.2lf%s
GPRINT:rate:AVERAGE:Ave\: %4.2lf%s
GPRINT:rate:MAX:Max\: %4.2lf%s
GPRINT:rate:MIN:Min\: %4.2lf%s\c
LINE:100
