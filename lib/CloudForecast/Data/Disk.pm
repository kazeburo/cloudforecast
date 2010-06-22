package CloudForecast::Data::Disk;

use CloudForecast::Data -base;
use CloudForecast::Log;
use List::Util qw//;

rrds map { [ $_, 'GAUGE' ] } qw /total used/;
graphs 'disk' => 'Disk Usage';

fetcher {
    my $c = shift;
    my $interface = $c->args->[0] || 0;
    if ( $interface =~ /^\d+$/ ) {
        my @map = map { [ $_, $interface ] } qw/dskTotal dskUsed/;
        return $c->component('SNMP')->get_by_int(@map);
    }

    my $ret = $c->component('SNMP')->walk(qw/dskPath dskTotal dskUsed/);
    if ( !$ret ) {
        CloudForecast::Log->warn('disk usage buldwalk failed');
        return;
    }

    my $disk = List::Util::first { $_->{dskPath} eq $interface } @$ret;
    if ( !$disk ) {
        CloudForecast::Log->warn("couldnot find partition '$interface'");
        return;
    }
    return [ $disk->{dskTotal}, $disk->{dskUsed} ];
};

__DATA__
@@ disk
DEF:my1=<%RRD%>:total:AVERAGE
DEF:my2=<%RRD%>:used:AVERAGE
CDEF:my1b=my1,1000,*
CDEF:my2b=my2,1000,*
AREA:my1b#ff99ff:Total 
GPRINT:my1b:LAST:Current\: %4.1lf%sB
AREA:my2b#cc00ff:Used 
GPRINT:my2b:LAST:Current\: %4.1lf%sB

