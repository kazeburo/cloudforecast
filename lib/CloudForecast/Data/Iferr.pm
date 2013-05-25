package CloudForecast::Data::Iferr;

use CloudForecast::Data -base;
use CloudForecast::Log;

rrds map { [ $_, 'COUNTER' ] } qw /inerr outerr indisc outdisc/;
graphs 'iferr' => 'Interface Errors';

title {
    my $c = shift;
    my $ifname = $c->args->[1] || $c->args->[0] || '0';
    return "Interface Errors ($ifname)";
};

fetcher {
    my $c = shift;
    my $interface = $c->args->[0] || 0;

    if ( $interface !~ /^\d+$/ ) {
        my %interfaces = map { $_ => 1 } split /\|/, $interface;

        my $ifs = $c->component('SNMP')->table("ifTable",
            columns => [qw/ifIndex ifDescr ifInErrors ifOutErrors ifInDiscards ifOutDiscards/] );
        if ( !$ifs ) {
            CloudForecast::Log->warn("couldnot get iftable");
            return [undef, undef, undef, undef];
        }

        my $if = List::Util::first {
            exists $interfaces{$_->{ifDescr}}
        } values %{$ifs};
        if ( !$if ) {
            CloudForecast::Log->warn("couldnot find network interface '$interface'");
            return [undef, undef, undef, undef];
        }

        CloudForecast::Log->debug("found network interface '$interface' with ifIndex:$if->{ifIndex}");
        return [$if->{ifInErrors}, $if->{ifOutErrors}, $if->{ifInDiscards}, $if->{ifOutDiscards}];
    }

    my @map = map { [ $_, $interface ] } qw/ifInErrors ifOutErrors ifInDiscards ifOutDiscards/;
    my $ret = $c->component('SNMP')->get(@map);

    return [ $ret->[0], $ret->[1], $ret->[2], $ret->[3] ];
};

__DATA__
@@ iferr
DEF:inerr=<%RRD%>:inerr:AVERAGE
DEF:outerr=<%RRD%>:outerr:AVERAGE
DEF:indisc=<%RRD%>:indisc:AVERAGE
DEF:outdisc=<%RRD%>:outdisc:AVERAGE
LINE1:inerr#00C000:InErrors   
GPRINT:inerr:LAST:Cur\:%7.0lf
GPRINT:inerr:AVERAGE:Ave\:%7.0lf
GPRINT:inerr:MAX:Max\:%7.0lf\l
LINE1:outerr#0000FF:OutErrors  
GPRINT:outerr:LAST:Cur\:%7.0lf
GPRINT:outerr:AVERAGE:Ave\:%7.0lf
GPRINT:outerr:MAX:Max\:%7.0lf\l
LINE1:indisc#00C0C0:InDiscards 
GPRINT:indisc:LAST:Cur\:%7.0lf
GPRINT:indisc:AVERAGE:Ave\:%7.0lf
GPRINT:indisc:MAX:Max\:%7.0lf\l
LINE1:outdisc#C0C000:OutDiscards
GPRINT:outdisc:LAST:Cur\:%7.0lf
GPRINT:outdisc:AVERAGE:Ave\:%7.0lf
GPRINT:outdisc:MAX:Max\:%7.0lf\l


