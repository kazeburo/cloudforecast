package CloudForecast::Data::Disk;

use CloudForecast::Data -base;

rrds map { [ $_, 'GAUGE' ] } qw /total used/;
graphs 'disk' => 'Disk Usage';

fetcher {
    my $c = shift;
    my $interface = $c->args->[0] || 0;

    my @map = map { [ $_, $interface ] } qw/dskTotal dskUsed/;
    $c->component('SNMP')->get_by_int(@map);
};

__DATA__
@@ disk
DEF:my1=<%RRD%>:total:AVERAGE
DEF:my2=<%RRD%>:used:AVERAGE
AREA:my1#ff99ff:Total  
GPRINT:my1:AVERAGE:Ave\: %4.0lf
AREA:my2#cc00ff:Used  
GPRINT:my2:AVERAGE:Ave\: %4.0lf

