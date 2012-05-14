package CloudForecast::Data::Redis;

use CloudForecast::Data -base;
use IO::Socket::INET;

=head1 NAME

CloudForecast::Data::Redis - redis resource monitor

=head1 SYNOPSIS

  host_config)

    resources:
      - redis[:port]

=cut

rrds map { [$_,'COUNTER'] } qw/totalcmd totalconn/;
rrds map { [$_,'GAUGE'] } qw/conncli connslv usedmem unsaved fragmentation/;
graphs 'cmd' => 'Command Processed';
graphs 'conn' => 'Connections';
graphs 'mem' => 'Memory Usage';
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
    $sock->syswrite("info\r\n");
    my $raw_stats;
    $sock->sysread( $raw_stats, 8192 );
    my %stats;
    foreach my $line ( split /\r?\n/, $raw_stats ) {
        chomp($line);chomp($line);
        if ( $line =~ /^([^:]+?):(.+)$/ ) {
            $stats{$1} = $2;
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
        int($stats{mem_fragmentation_ratio} * 100)
    ];
}


__DATA__
@@ cmd
DEF:my1=<%RRD%>:totalcmd:AVERAGE
AREA:my1#00C000:Total Command
GPRINT:my1:LAST:Cur\:%5.1lf
GPRINT:my1:AVERAGE:Ave\:%5.1lf
GPRINT:my1:MAX:Max\:%5.1lf
GPRINT:my1:MIN:Min\:%5.1lf\l

@@ conn
DEF:my1=<%RRD%>:totalconn:AVERAGE
DEF:my2=<%RRD%>:conncli:AVERAGE
DEF:my3=<%RRD%>:connslv:AVERAGE
LINE1:my1#C00000:Clients
GPRINT:my1:LAST:Cur\:%5.1lf
GPRINT:my1:AVERAGE:Ave\:%5.1lf
GPRINT:my1:MAX:Max\:%5.1lf
GPRINT:my1:MIN:Min\:%5.1lf\l
LINE1:my2#990033:Slaves
GPRINT:my1:LAST:Cur\:%5.1lf
GPRINT:my1:AVERAGE:Ave\:%5.1lf
GPRINT:my1:MAX:Max\:%5.1lf
GPRINT:my1:MIN:Min\:%5.1lf\l
LINE1:my3#33cc66:Received
GPRINT:my1:LAST:Cur\:%5.1lf
GPRINT:my1:AVERAGE:Ave\:%5.1lf
GPRINT:my1:MAX:Max\:%5.1lf
GPRINT:my1:MIN:Min\:%5.1lf\l

@@ mem
DEF:my1=<%RRD%>:usedmem:AVERAGE
AREA:my1#00C000:Used
GPRINT:my1:LAST:Cur\:%5.1lf%sB
GPRINT:my1:AVERAGE:Ave\:%5.1lf%sB
GPRINT:my1:MAX:Max\:%5.1lf%sB
GPRINT:my1:MIN:Min\:%5.1lf%sB\l

@@ unsaved
DEF:my1=<%RRD%>:unsaved:AVERAGE
AREA:my1#00C000:Items
GPRINT:my1:LAST:Cur\:%5.1lf
GPRINT:my1:AVERAGE:Ave\:%5.1lf
GPRINT:my1:MAX:Max\:%5.1lf
GPRINT:my1:MIN:Min\:%5.1lf\l

