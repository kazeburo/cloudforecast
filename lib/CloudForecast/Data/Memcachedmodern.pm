package CloudForecast::Data::Memcachedmodern;

use CloudForecast::Data -base;
use CloudForecast::TinyClient;

=head1 NAME

CloudForecast::Data::Memcachedmodern - memcached resource monitor for modern option

=head1 SYNOPSIS

  host_config)

    resources:
      - memcachedmodern[[:port]:title]]

  eg)
    - memcachedmodern  # memcachedを11211で動かしている場合
    - memcachedmodern:11212 # ほかのportで起動
    - memcachedmodern:1978:tokyotyrant # tokyotyrantを監視する場合

=cut

rrds map { [$_,'COUNTER'] } qw/cmdget cmdset gethits getmisses getexpired getflushed/;
rrds map { [$_,'GAUGE'] } qw/rate used max/;
extend_rrd $_,'COUNTER' for qw/evt_total evt_unfetched/;
extend_rrd $_,'GAUGE' for qw/items_cur/;
extend_rrd $_,'COUNTER' for qw/moves_to_cold moves_to_warm moves_within_lru/;
# rate is using for current_connections
graphs 'usage' => 'Cache Usage';
graphs 'items' => 'Items';
graphs 'evictions' => 'Evictions/sec';
graphs 'count' => 'Request Count';
graphs 'rate' => 'Cache Hit Rate';
graphs 'expire' => 'Expire items';
graphs 'conn' => 'Connections' => 'conn' => sub {
    my ($c,$template) = @_;
    my $sysinfo = $c->ledge_get('sysinfo') || [];
    my %sysinfo = @$sysinfo;
    if ( $sysinfo{max_connections} ) {
        $template .= "LINE:$sysinfo{max_connections}#C00000\n";
    }
    $template;
};
graphs 'moves' => 'Move items';

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

    my $client = CloudForecast::TinyClient->new($host,$port,3.5);
    $client->write("stats\r\n",1);
    my $raw_stats = $client->read(1);
    die "could not retrieve status from $host:$port" unless $raw_stats;

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

    if ( $stats{version} && $stats{version} =~ m!^1\.4! ) {
        $client->write("stats settings\r\n");
        my $raw_setting_stats = $client->read(1);
        my %setting_stats;
        foreach my $line ( split /\r?\n/, $raw_setting_stats ) {
            if ( $line =~ /^STAT\s([^ ]+)\s(.+)$/ ) {
                $setting_stats{$1} = $2;
            }
        }

        push @sysinfo, 'max_connections' => $setting_stats{maxconns};
    }

    $c->ledge_set( 'sysinfo', \@sysinfo );

    return [ $stats{cmd_get}, $stats{cmd_set}, $stats{get_hits}, $stats{get_misses}, $stats{get_expired}, $stats{get_flushed},
             $stats{curr_connections}, $stats{bytes}, $stats{limit_maxbytes},
             $stats{evictions}, $stats{evicted_unfetched},
             $stats{curr_items},
             $stats{moves_to_cold}, $stats{moves_to_warm}, $stats{moves_within_lru},
            ];

};


__DATA__
@@ usage
DEF:my1=<%RRD%>:used:AVERAGE
DEF:my2=<%RRD%>:max:AVERAGE
AREA:my1#eaaf00:Used
GPRINT:my1:LAST:Cur\:%5.2lf%sB
GPRINT:my1:AVERAGE:Ave\:%5.2lf%sB
GPRINT:my1:MAX:Max\:%5.2lf%sB
GPRINT:my1:MIN:Min\:%5.2lf%sB\l
LINE:my2#333333:Max 
GPRINT:my2:LAST:Cur\:%5.2lf%sB
GPRINT:my2:AVERAGE:Ave\:%5.2lf%sB
GPRINT:my2:MAX:Max\:%5.2lf%sB
GPRINT:my2:MIN:Min\:%5.2lf%sB\l

@@ count
DEF:my1a=<%RRD%>:cmdset:AVERAGE
DEF:my2a=<%RRD%>:cmdget:AVERAGE
CDEF:my1=my1a,0,1000000,LIMIT
CDEF:my2=my2a,0,1000000,LIMIT
AREA:my1#00C000:Set
GPRINT:my1:LAST:Cur\:%7.1lf
GPRINT:my1:AVERAGE:Ave\:%7.1lf
GPRINT:my1:MAX:Max\:%7.1lf
GPRINT:my1:MIN:Min\:%7.1lf\l
STACK:my2#0000C0:Get
GPRINT:my2:LAST:Cur\:%7.1lf
GPRINT:my2:AVERAGE:Ave\:%7.1lf
GPRINT:my2:MAX:Max\:%7.1lf
GPRINT:my2:MIN:Min\:%7.1lf\l

@@ rate
DEF:hits=<%RRD%>:gethits:AVERAGE
DEF:misses=<%RRD%>:getmisses:AVERAGE
CDEF:total=hits,misses,+
CDEF:rate=hits,total,/,100,*,0,100,LIMIT
AREA:rate#990000:Rate
GPRINT:rate:LAST:Cur\:%5.1lf[%%]
GPRINT:rate:AVERAGE:Ave\:%5.1lf[%%]
GPRINT:rate:MAX:Max\:%5.1lf[%%]
GPRINT:rate:MIN:Min\:%5.1lf[%%]\l
LINE:100

@@ expire
DEF:expire=<%RRD%>:getexpired:AVERAGE
DEF:flush=<%RRD%>:getflushed:AVERAGE
CDEF:my1=expire,0,100000,LIMIT
CDEF:my2=flush,0,100000,LIMIT
AREA:my1#00C000:Expired
GPRINT:my1:LAST:Cur\:%7.1lf
GPRINT:my1:AVERAGE:Ave\:%7.1lf
GPRINT:my1:MAX:Max\:%7.1lf
GPRINT:my1:MIN:Min\:%7.1lf\l
STACK:my2#0000C0:Flushed
GPRINT:my2:LAST:Cur\:%7.1lf
GPRINT:my2:AVERAGE:Ave\:%7.1lf
GPRINT:my2:MAX:Max\:%7.1lf
GPRINT:my2:MIN:Min\:%7.1lf\l

@@ conn
DEF:conn=<%RRD%>:rate:AVERAGE
AREA:conn#00C000:Connection
GPRINT:conn:LAST:Cur\:%7.1lf
GPRINT:conn:AVERAGE:Ave\:%7.1lf
GPRINT:conn:MAX:Max\:%7.1lf
GPRINT:conn:MIN:Min\:%7.1lf\l

@@ evictions
DEF:my1=<%RRD_EXTEND evt_total %>:evt_total:AVERAGE
DEF:my2=<%RRD_EXTEND evt_unfetched %>:evt_unfetched:AVERAGE
AREA:my1#800040:Evictions Total    
GPRINT:my1:LAST:Cur\:%6.1lf
GPRINT:my1:AVERAGE:Ave\:%6.1lf
GPRINT:my1:MAX:Max\:%6.1lf
GPRINT:my1:MIN:Min\:%6.1lf\l
LINE2:my2#004080:Evictions Unfetched
GPRINT:my2:LAST:Cur\:%6.1lf
GPRINT:my2:AVERAGE:Ave\:%6.1lf
GPRINT:my2:MAX:Max\:%6.1lf
GPRINT:my2:MIN:Min\:%6.1lf\l
LINE1:10#ff0000:JudgeLine:dashes=2,8\l

@@ items
DEF:my1=<%RRD_EXTEND items_cur %>:items_cur:AVERAGE
AREA:my1#00A000:Current Items
GPRINT:my1:LAST:Cur\:%8.0lf
GPRINT:my1:AVERAGE:Ave\:%8.0lf
GPRINT:my1:MAX:Max\:%8.0lf
GPRINT:my1:MIN:Min\:%8.0lf\l

@@ moves
DEF:my1=<%RRD_EXTEND moves_to_cold %>:moves_to_cold:AVERAGE
DEF:my2=<%RRD_EXTEND moves_to_warm %>:moves_to_warm:AVERAGE
DEF:my3=<%RRD_EXTEND moves_within_lru %>:moves_within_lru:AVERAGE
LINE1:my1#800040:Moves to cold
GPRINT:my1:LAST:Cur\:%6.1lf
GPRINT:my1:AVERAGE:Ave\:%6.1lf
GPRINT:my1:MAX:Max\:%6.1lf
GPRINT:my1:MIN:Min\:%6.1lf\l
LINE1:my2#004080:Moves to warm
GPRINT:my2:LAST:Cur\:%6.1lf
GPRINT:my2:AVERAGE:Ave\:%6.1lf
GPRINT:my2:MAX:Max\:%6.1lf
GPRINT:my2:MIN:Min\:%6.1lf\l
LINE1:my3#FFBF00:Moves within LRUs
GPRINT:my3:LAST:Cur\:%6.1lf
GPRINT:my3:AVERAGE:Ave\:%6.1lf
GPRINT:my3:MAX:Max\:%6.1lf
GPRINT:my3:MIN:Min\:%6.1lf\l

