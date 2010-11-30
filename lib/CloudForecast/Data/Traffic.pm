package CloudForecast::Data::Traffic;

use CloudForecast::Data -base;
use CloudForecast::Log;

rrds map { [ $_, 'COUNTER' ] } qw /in out/;
graphs 'traffic' => 'Throughput';

title {
    my $c = shift;
    my $ifname = $c->args->[1] || $c->args->[0] || '0';
    return "Traffic ($ifname)";
};

fetcher {
    my $c = shift;
    my $interface = $c->args->[0] || 0;

    if ( $interface !~ /^\d+$/ ) {
        my %interfaces = map { $_ => 1 } split /\|/, $interface;

        my $ifs = $c->component('SNMP')->table("ifTable",
            columns => [qw/ifIndex ifDescr ifHCOutOctets ifOutOctets ifHCInOctets ifInOctets/] );
        if ( !$ifs ) {
            CloudForecast::Log->warn("couldnot get iftable");
            return [undef, undef];
        }

        my $if = List::Util::first {
            exists $interfaces{$_->{ifDescr}}
        } values %{$ifs};
        if ( !$if ) {
            CloudForecast::Log->warn("couldnot find network interface '$interface'");
            return [undef, undef];
        }
        
        CloudForecast::Log->debug("found network interface '$interface' with ifIndex:$if->{ifIndex}");
        my $in = exists $if->{ifHCInOctets} ? $if->{ifHCInOctets} : $if->{ifInOctets};
        my $out = exists $if->{ifHCOutOctets} ? $if->{ifHCOutOctets} : $if->{ifOutOctets};
        return [$in, $out];
    }

    my @map = map { [ $_, $interface ] } qw/ifInOctets ifOutOctets/;
    push @map, map { [ $_, $interface] } qw/ifHCInOctets ifHCOutOctets/
        if $c->component('SNMP')->config->{version} eq '2';
    my $ret = $c->component('SNMP')->get(@map);

    if ( $c->component('SNMP')->config->{version} eq '2' && $ret->[2] ne '' && $ret->[3] ne '' ) {
        return [ $ret->[2], $ret->[3] ];
    }
    CloudForecast::Log->debug("use 32bit Traffic counter");
    return [ $ret->[0], $ret->[1] ];
};

__DATA__
@@ traffic
DEF:ind=<%RRD%>:in:AVERAGE
DEF:outd=<%RRD%>:out:AVERAGE
CDEF:in=ind,0,125000000,LIMIT,8,*
CDEF:out=outd,0,125000000,LIMIT,8,*
AREA:in#00C000: Inbound   
GPRINT:in:LAST:Current\:%6.2lf %sbps
GPRINT:in:AVERAGE:Ave\:%6.2lf %sbps
GPRINT:in:MAX:Max\:%6.2lf %sbps\c
LINE1:out#0000FF: Outbound  
GPRINT:out:LAST:Current\:%6.2lf %sbps
GPRINT:out:AVERAGE:Ave\:%6.2lf %sbps
GPRINT:out:MAX:Max\:%6.2lf %sbps\c


