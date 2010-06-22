package CloudForecast::Data::Traffic;

use CloudForecast::Data -base;
use CloudForecast::Log;

rrds map { [ $_, 'COUNTER' ] } qw /in out/;
graphs 'traffic' => 'Throughput';

title sub {
    my $c = shift;
    my $ifname = $c->args->[1] || $c->args->[0] || '0';
    return "Traffic ($ifname)";
};

fetcher {
    my $c = shift;
    my $interface = $c->args->[0] || 0;
    if ( $interface !~ /^\d+$/ ) {
        my $ifs = $c->component('SNMP')->walk(qw/ifIndex ifName/);
        my $if = List::Util::first { $_->{ifName} eq $interface } @$ifs;
        if ( !$if ) {
            CloudForecast::Log->warn("couldnot find network interface '$interface'");
        }
        else {
            CloudForecast::Log->debug("found network interface '$interface' with ifIndex: $if->{ifIndex}");
            $interface = $if->{ifIndex};
        }
    }

    my @oids = ( $c->component('SNMP')->config->{version} eq '1' ) ? qw/ifInOctets ifOutOctets/ : qw/ifHCInOctets ifHCOutOctets/;
    my @map = map { [ $_, $interface ] } @oids;
    my $ret = $c->component('SNMP')->get_by_int(@map);
    
    if ( $c->component('SNMP')->config->{version} ne '1' && $ret->[0] eq '' && $ret->[1] eq '' ) {
        CloudForecast::Log->warn("fall down to 32bit counter");
        $ret = $c->component('SNMP')->get_by_int( map { [ $_, $interface ] } qw/ifInOctets ifOutOctets/ );
    }
    $ret;
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


