package CloudForecast::Data::Memcached;

use CloudForecast::Data -base;
use IO::Socket::INET;

rrds map { [$_,'COUNTER'] } qw/cmdget cmdset gethits getmisses/;
rrds map { [$_,'GAUGE'] } qw/rate used max/;
graphs 'usage' => 'memcached usage';
graphs 'count' => 'memcached request count';
graphs 'rate' => 'memcached hit rate';

title sub {
    my $c = shift;
    my $title = "memcached";
    if ( my $port = $c->args->[0] ) {
        $title .= " ($port)";
    }
    return $title;
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
    my $found = select( undef, $fbits, undef, 0.5 );

    die "could not connecet to $host:$port" unless $found;

    $sock->blocking(1);
    $sock->syswrite("stats\r\n");
    my $raw_stats;
    $sock->sysread( $raw_stats, 8192 );

    my $cmd_get = 0;
    my $cmd_set = 0;
    my $get_hits = 0;
    my $get_misses = 0;
    my $used = 0;
    my $max  = 0;
    foreach my $line ( split /\r?\n/, $raw_stats ) {
        if ( $line =~ /^STAT\scmd_get\s(\d+)$/ )    { $cmd_get = $1 }
        if ( $line =~ /^STAT\scmd_set\s(\d+)$/ )    { $cmd_set = $1 }
        if ( $line =~ /^STAT\s(?:cmd_)?get_hits\s(\d+)$/ )   { $get_hits = $1 }
        if ( $line =~ /^STAT\s(?:cmd_)?get_misses\s(\d+)$/ ) { $get_misses = $1 }
        if ( $line =~ /^STAT\sbytes\s(\d+)$/ )      { $used = $1 }
        if ( $line =~ /^STAT\slimit_maxbytes\s(\d+)$/ ) { $max = $1 }
    }

    my $rate = 0;
    eval {
        $rate = int($get_hits * 100 / ($get_hits+$get_misses))
    };
    
    return [ $cmd_get, $cmd_set, $get_hits, $get_misses, $rate, $used, $max ];
};


__DATA__
@@ usage
DEF:my1=<%RRD%>:used:AVERAGE
DEF:my2=<%RRD%>:max:AVERAGE
AREA:my1#00C000:Used  
GPRINT:my1:LAST:Cur\: %2.2lf%sB
GPRINT:my1:AVERAGE:Ave\: %2.2lf%sB
GPRINT:my1:MAX:Max\: %2.2lf%sB
GPRINT:my1:MIN:Min\: %2.2lf%sB\c
LINE:my2#0000C0:Max  
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
DEF:my1=<%RRD%>:rate:AVERAGE
AREA:my1#00C000:RATE  
GPRINT:my1:LAST:Cur\: %4.2lf%s
GPRINT:my1:AVERAGE:Ave\: %4.2lf%s
GPRINT:my1:MAX:Max\: %4.2lf%s
GPRINT:my1:MIN:Min\: %4.2lf%s\c


