package CloudForecast::Data::Traffic;

use CloudForecast::Data -base;

rrds map { [ $_, 'COUNTER' ] } qw /in out/;
graphs 'traffic' => 'Throughput';

fetcher {
    my $c = shift;
    my $interface = $c->args->[0] || 0;

    my @map = map { [ $_, $interface ] } qw/ifHCInOctets ifHCOutOctets/;
    $c->component('SNMP')->get_by_int(@map);
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


