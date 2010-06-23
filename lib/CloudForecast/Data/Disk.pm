package CloudForecast::Data::Disk;

use CloudForecast::Data -base;
use CloudForecast::Log;
use List::Util qw//;

rrds map { [ $_, 'GAUGE' ] } qw /total used/;
graphs 'disk' => 'Disk Usage';

title sub {
    my $c = shift;
    my $partition = $c->args->[1] || $c->args->[0] || '0';
    return "Disk ($partition)";
};

fetcher {
    my $c = shift;
    my $interface = $c->args->[0] || 0;

    if ( $interface !~ /^\d+$/ ) {
        my $disks = $c->component('SNMP')->table("dskTable", 
            columns => [qw/dskIndex dskPath dskTotal dskUsed/] );
        if ( !$disks ) {
            CloudForecast::Log->warn("couldnot get dskTable");
            return [-1, -1];
        }
        my $disk = List::Util::first { $_->{dskPath} eq $interface } values %{$disks};
        if ( !$disk ) {
            CloudForecast::Log->warn("couldnot find disk partition '$interface'");
            return [-1, -1];
        }
        CloudForecast::Log->debug("found partition '$interface' with dskIndex:$disk->{dskIndex}");
        return [ $disk->{dskTotal}, $disk->{dskUsed} ];
    }

    my @map = map { [ $_, $interface ] } qw/dskTotal dskUsed/;
    return $c->component('SNMP')->get_by_int(@map);
};

__DATA__
@@ disk
DEF:my1=<%RRD%>:total:AVERAGE
DEF:my2=<%RRD%>:used:AVERAGE
CDEF:my1b=my1,1000,*
CDEF:my2b=my2,1000,*
AREA:my1b#ff99ff:Total 
GPRINT:my1b:LAST:Current\: %3.2lf %sB
AREA:my2b#cc00ff:Used 
GPRINT:my2b:LAST:Current\: %3.2lf %sB

