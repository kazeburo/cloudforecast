package CloudForecast::Data::Redis;

use CloudForecast::Data -base;
use CloudForecast::TinyClient;

=head1 NAME

CloudForecast::Data::Redis - redis resource monitor

=head1 SYNOPSIS

  host_config)

    resources:
      - redis[:port]

=cut

rrds map { [$_,'COUNTER'] } qw/totalcmd totalconn/;
rrds map { [$_,'GAUGE'] } qw/conncli connslv usedmem unsaved fragmentation/;
extend_rrd 'evicted', 'COUNTER';
extend_rrd 'pubsub_ch', 'GAUGE';
extend_rrd 'keys', 'GAUGE';
extend_rrd 'slowlog', 'GAUGE';

graphs 'cmd' => 'Command Processed';
graphs 'conn' => 'Connections';
graphs 'mem' => 'Memory Usage';
graphs 'keys' => 'Keys';
graphs 'evicted' => 'Evicted Keys/sec';
graphs 'fragmentation' => 'Fragmentation Ratio';
graphs 'pubsub_ch' => 'Pub/Sub Channels';
graphs 'slowlog' => 'Slowlog(total)';
graphs 'unsaved' => 'Unsaved Changes';

title {
    my $c = shift;
    my $title = "redis";
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
    my $port = $c->args->[0] || 6379;

    my $client = CloudForecast::TinyClient->new($host,$port,3.5);
    $client->write("info\r\n",1);
    my $raw_stats = $client->read(1);
    die "could not retrieve status from $host:$port" unless $raw_stats;

    my %stats;
    my $keys;
    foreach my $line ( split /\r?\n/, $raw_stats ) {
        chomp($line);chomp($line);
        if ( $line =~ /^([^:]+?):(.+)$/ ) {
            my($k,$v) = ($1,$2);
            $stats{$k} = $v;
            if ($k =~ /^db[0-9]+/) {
                $keys += $v =~ /keys=(\d+),/ ? $1 : 0;
            }
        }
    }

    my $raw_res;
    ### slowlog
    $client->write("slowlog len\r\n",1);
    $raw_res = $client->read(1);
    my $slowlog = $raw_res =~ /:([0-9]+)/ ? $1 : 0;

    ### config get
    my %config;
    $client->write("config get *\r\n",1);
    $raw_res = $client->read(1);
    my $ck;
    foreach my $line ( split /\r?\n/, $raw_res ) {
        chomp($line);chomp($line);
        next if $line =~ /^[\*\$]/;

        if (! $ck) {
            $ck = $line;
        } else {
            $config{$ck} = $line;
            $ck = "";
        }
    }

    my @sysinfo;
    if ( $stats{redis_version} ) {
        push @sysinfo, 'version' => $stats{redis_version};
    }
    if ( my $uptime = $stats{uptime_in_seconds} ) {
        my $day = int( $uptime /86400 );
        my $hour = int( ( $uptime % 86400 ) / 3600 );
        my $min = int( ( ( $uptime % 86400 ) % 3600) / 60 );
        push @sysinfo, 'uptime' =>  sprintf("up %d days, %2d:%02d", $day, $hour, $min);
    }
    foreach my $stats_key (qw/vm_enabled role/) {
        push @sysinfo, $stats_key => $stats{$stats_key}
            if exists $stats{$stats_key};
    }
    push @sysinfo, 'maxmemory' => _unit($config{maxmemory} || 0);
    foreach my $config_key (qw/maxclients rdbcompression appendonly maxmemory-policy appendfsync save slowlog-max-len/) {
        push @sysinfo, $config_key => $config{$config_key}
            if exists $config{$config_key};
    }

    $c->ledge_set( 'sysinfo', \@sysinfo );

    #rrds map { [$_,'COUNTER'] } qw/totalcmd totalconn/;
    #rrds map { [$_,'GAUGE'] } qw/conncli connslv usedmem unsaved fragmentation/;
    return [ 
        $stats{total_commands_processed}, 
        $stats{total_connections_received}, 
        $stats{connected_clients}, 
        $stats{connected_slaves},
        $stats{used_memory}, 
        $stats{changes_since_last_save},
        $stats{mem_fragmentation_ratio},
        $stats{evicted_keys},
        $stats{pubsub_channels},
        $keys,
        $slowlog,
    ];
};

sub _unit {
    my $n = shift;
    my($base, $unit);

    return $n unless $n =~ /^\d+$/;
    if ($n >= 1073741824) {
        $base = 1073741824;
        $unit = 'GB';
    } elsif ($n >= 1048576) {
        $base = 1048576;
        $unit = 'MB';
    } elsif ($n >= 1024) {
        $base = 1024;
        $unit = 'KB';
    } else {
        $base = 1;
        $unit = 'B';
    }

    $n = sprintf '%.2f', $n/$base;
    while($n =~ s/(.*\d)(\d\d\d)/$1,$2/){};

    return $n.$unit;
}

__DATA__
@@ cmd
DEF:my1=<%RRD%>:totalcmd:AVERAGE
AREA:my1#FF8C00:Total Command
GPRINT:my1:LAST:Cur\:%5.1lf
GPRINT:my1:AVERAGE:Ave\:%5.1lf
GPRINT:my1:MAX:Max\:%5.1lf
GPRINT:my1:MIN:Min\:%5.1lf\l

@@ conn
DEF:my1=<%RRD%>:conncli:AVERAGE
DEF:my2=<%RRD%>:connslv:AVERAGE
DEF:my3=<%RRD%>:totalconn:AVERAGE
LINE1:my1#C00000:Clients 
GPRINT:my1:LAST:Cur\:%5.1lf
GPRINT:my1:AVERAGE:Ave\:%5.1lf
GPRINT:my1:MAX:Max\:%5.1lf
GPRINT:my1:MIN:Min\:%5.1lf\l
LINE1:my2#990033:Slaves  
GPRINT:my2:LAST:Cur\:%5.1lf
GPRINT:my2:AVERAGE:Ave\:%5.1lf
GPRINT:my2:MAX:Max\:%5.1lf
GPRINT:my2:MIN:Min\:%5.1lf\l
LINE1:my3#2E8B57:Received
GPRINT:my3:LAST:Cur\:%5.1lf
GPRINT:my3:AVERAGE:Ave\:%5.1lf
GPRINT:my3:MAX:Max\:%5.1lf
GPRINT:my3:MIN:Min\:%5.1lf\l

@@ mem
DEF:my1=<%RRD%>:usedmem:AVERAGE
CDEF:sm=my1,900,TREND
CDEF:cf=86400,-8,1800,sm,PREDICT
AREA:my1#4682B4:Used
GPRINT:my1:LAST:Cur\:%5.1lf%sB
GPRINT:my1:AVERAGE:Ave\:%5.1lf%sB
GPRINT:my1:MAX:Max\:%5.1lf%sB
GPRINT:my1:MIN:Min\:%5.1lf%sB\l
LINE1:cf#780a85:Prediction:dashes=4,6

@@ unsaved
DEF:my1=<%RRD%>:unsaved:AVERAGE
AREA:my1#BDB76B:Changes
GPRINT:my1:LAST:Cur\:%5.1lf
GPRINT:my1:AVERAGE:Ave\:%5.1lf
GPRINT:my1:MAX:Max\:%5.1lf
GPRINT:my1:MIN:Min\:%5.1lf\l

@@ fragmentation
DEF:my1=<%RRD%>:fragmentation:AVERAGE
LINE1:my1#491815:Fragmentation
GPRINT:my1:LAST:Cur\:%5.1lf
GPRINT:my1:AVERAGE:Ave\:%5.1lf
GPRINT:my1:MAX:Max\:%5.1lf
GPRINT:my1:MIN:Min\:%5.1lf\l

@@ evicted
DEF:my1=<%RRD_EXTEND evicted %>:evicted:AVERAGE
LINE1:my1#800040:Evicted Keys/sec
GPRINT:my1:LAST:Cur\:%5.1lf
GPRINT:my1:AVERAGE:Ave\:%5.1lf
GPRINT:my1:MAX:Max\:%5.1lf
GPRINT:my1:MIN:Min\:%5.1lf\l

@@ pubsub_ch
DEF:my1=<%RRD_EXTEND pubsub_ch %>:pubsub_ch:AVERAGE
LINE2:my1#2E8B57:Pub/Sub Channels
GPRINT:my1:LAST:Cur\:%5.1lf
GPRINT:my1:AVERAGE:Ave\:%5.1lf
GPRINT:my1:MAX:Max\:%5.1lf
GPRINT:my1:MIN:Min\:%5.1lf\l

@@ keys
DEF:my1=<%RRD_EXTEND keys %>:keys:AVERAGE
CDEF:sm=my1,900,TREND
CDEF:cf=86400,-8,1800,sm,PREDICT
AREA:my1#00A000:Keys
GPRINT:my1:LAST:Cur\:%5.1lf
GPRINT:my1:AVERAGE:Ave\:%5.1lf
GPRINT:my1:MAX:Max\:%5.1lf
GPRINT:my1:MIN:Min\:%5.1lf\l
LINE1:cf#780a85:Prediction:dashes=4,6

@@ slowlog
DEF:my1=<%RRD_EXTEND slowlog %>:slowlog:AVERAGE
AREA:my1#00c000:Slowlog
GPRINT:my1:LAST:Cur\:%5.1lf
GPRINT:my1:AVERAGE:Ave\:%5.1lf
GPRINT:my1:MAX:Max\:%5.1lf
GPRINT:my1:MIN:Min\:%5.1lf\l
