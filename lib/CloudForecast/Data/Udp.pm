package CloudForecast::Data::Udp;

use CloudForecast::Data -base;
use CloudForecast::Log;

rrds map { [ $_, 'COUNTER' ] } qw /udpin udpout udpinerr udpnoport/;
graphs 'udp' => 'UDP';

fetcher {
    my $c = shift;

    my @map = map { [ $_, 0 ] } qw/udpInDatagrams udpOutDatagrams udpInErrors udpNoPorts/;
    my $ret = $c->component('SNMP')->get(@map);

    return [ $ret->[0], $ret->[1], $ret->[2], $ret->[3] ];
};

__DATA__
@@ udp
DEF:udpin=<%RRD%>:udpin:AVERAGE
DEF:udpout=<%RRD%>:udpout:AVERAGE
DEF:udpinerr=<%RRD%>:udpinerr:AVERAGE
DEF:udpnoport=<%RRD%>:udpnoport:AVERAGE
AREA:udpin#00C000:InDatagrams 
GPRINT:udpin:LAST:Cur\:%7.0lf
GPRINT:udpin:AVERAGE:Ave\:%7.0lf
GPRINT:udpin:MAX:Max\:%7.0lf\l
LINE1:udpout#0000FF:OutDatagrams
GPRINT:udpout:LAST:Cur\:%7.0lf
GPRINT:udpout:AVERAGE:Ave\:%7.0lf
GPRINT:udpout:MAX:Max\:%7.0lf\l
AREA:udpinerr#FF0000:InErrors    
GPRINT:udpinerr:LAST:Cur\:%7.0lf
GPRINT:udpinerr:AVERAGE:Ave\:%7.0lf
GPRINT:udpinerr:MAX:Max\:%7.0lf\l
LINE1:udpnoport#00C0C0:NoPorts     
GPRINT:udpnoport:LAST:Cur\:%7.0lf
GPRINT:udpnoport:AVERAGE:Ave\:%7.0lf
GPRINT:udpnoport:MAX:Max\:%7.0lf\l


