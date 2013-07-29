package CloudForecast::Data::Ifpkt;

use CloudForecast::Data -base;
use CloudForecast::Log;

rrds map { [ $_, 'COUNTER' ] } qw /inucast outucast inmcast outmcast inbcast outbcast/;
graphs 'ifpkt' => 'Interface Packets';

title {
    my $c = shift;
    my $ifname = $c->args->[1] || $c->args->[0] || '0';
    return "Interface Packets ($ifname)";
};

fetcher {
    my $c = shift;
    my $interface = $c->args->[0] || 0;

    if ( $interface !~ /^\d+$/ ) {
        my %interfaces = map { $_ => 1 } split /\|/, $interface;

        my $ifs = $c->component('SNMP')->table(
            "ifTable",
            columns => [
                qw/ifIndex ifDescr/,
                qw/ifInUcastPkts     ifHCInUcastPkts     ifOutUcastPkts     ifHCOutUcastPkts
                   ifInMulticastPkts ifHCInMulticastPkts ifOutMulticastPkts ifHCOutMulticastPkts
                   ifInBroadcastPkts ifHCInBroadcastPkts ifOutBroadcastPkts ifHCOutBroadcastPkts/,
            ],
        );
        if ( !$ifs ) {
            CloudForecast::Log->warn("could not get iftable");
            return [ undef, undef, undef, undef, undef, undef ];
        }

        my $if = List::Util::first { exists $interfaces{ $_->{ifDescr} } } values %{$ifs};
        if ( !$if ) {
            CloudForecast::Log->warn("could not find network interface '$interface'");
            return [ undef, undef, undef, undef, undef, undef ];
        }

        CloudForecast::Log->debug("found network interface '$interface' with ifIndex:$if->{ifIndex}");

        my $in_u  = exists $if->{ifHCInUcastPkts}      ? $if->{ifHCInUcastPkts}      : $if->{ifInUcastPkts};
        my $out_u = exists $if->{ifHCOutUcastPkts}     ? $if->{ifHCOutUcastPkts}     : $if->{ifOutUcastPkts};
        my $in_m  = exists $if->{ifHCInMulticastPkts}  ? $if->{ifHCInMulticastPkts}  : $if->{ifInMulticastPkts};
        my $out_m = exists $if->{ifHCOutMulticastPkts} ? $if->{ifHCOutMulticastPkts} : $if->{ifOutMulticastPkts};
        my $in_b  = exists $if->{ifHCInBroadcastPkts}  ? $if->{ifHCInBroadcastPkts}  : $if->{ifInBroadcastPkts};
        my $out_b = exists $if->{ifHCOutBroadcastPkts} ? $if->{ifHCOutBroadcastPkts} : $if->{ifOutBroadcastPkts};

        return [ $in_u, $out_u, $in_m, $out_m, $in_b, $out_b ];
    }

    my @map = map { [ $_, $interface ] }
        qw/ifInUcastPkts     ifOutUcastPkts
           ifInMulticastPkts ifOutMulticastPkts
           ifInBroadcastPkts ifOutBroadcastPkts/;

    if ( $c->component('SNMP')->config->{version} eq '2' ) {
        push @map, map { [ $_, $interface ] }
            qw/ifHCInUcastPkts     ifHCOutUcastPkts
               ifHCInMulticastPkts ifHCOutMulticastPkts
               ifHCInBroadcastPkts ifHCOutBroadcastPkts/;
    }

    my $ret = $c->component('SNMP')->get(@map);

    for ( my $i = 6; $i < 12; $i++ ) {
        if ( !defined( $ret->[$i] ) || $ret->[$i] eq '' ) {
            CloudForecast::Log->debug("use 32bit Packet counter");
            return [ @{$ret}[ 0 .. 5 ] ];
        }
    }

    return [ @{$ret}[ 6 .. 11 ] ];
};

__DATA__
@@ ifpkt
DEF:inucast=<%RRD%>:inucast:AVERAGE
DEF:outucast=<%RRD%>:outucast:AVERAGE
DEF:inmcast=<%RRD%>:inmcast:AVERAGE
DEF:outmcast=<%RRD%>:outmcast:AVERAGE
DEF:inbcast=<%RRD%>:inbcast:AVERAGE
DEF:outbcast=<%RRD%>:outbcast:AVERAGE
LINE1:inucast#00C000:InUcast 
GPRINT:inucast:LAST:Cur\:%7.0lf
GPRINT:inucast:AVERAGE:Ave\:%7.0lf
GPRINT:inucast:MAX:Max\:%7.0lf\l
LINE1:outucast#0000FF:OutUcast
GPRINT:outucast:LAST:Cur\:%7.0lf
GPRINT:outucast:AVERAGE:Ave\:%7.0lf
GPRINT:outucast:MAX:Max\:%7.0lf\l
LINE1:inmcast#00C0C0:InMcast 
GPRINT:inmcast:LAST:Cur\:%7.0lf
GPRINT:inmcast:AVERAGE:Ave\:%7.0lf
GPRINT:inmcast:MAX:Max\:%7.0lf\l
LINE1:outmcast#C0C000:OutMcast
GPRINT:outmcast:LAST:Cur\:%7.0lf
GPRINT:outmcast:AVERAGE:Ave\:%7.0lf
GPRINT:outmcast:MAX:Max\:%7.0lf\l
LINE1:inbcast#000000:InBcast 
GPRINT:inbcast:LAST:Cur\:%7.0lf
GPRINT:inbcast:AVERAGE:Ave\:%7.0lf
GPRINT:inbcast:MAX:Max\:%7.0lf\l
LINE1:outbcast#C000C0:OutBcast
GPRINT:outbcast:LAST:Cur\:%7.0lf
GPRINT:outbcast:AVERAGE:Ave\:%7.0lf
GPRINT:outbcast:MAX:Max\:%7.0lf\l


