package CloudForecast::Data::Disk;

use CloudForecast::Data -base;
use CloudForecast::Log;
use List::Util qw//;

rrds map { [ $_, 'GAUGE' ] } qw /total used/;
graphs 'disk' => 'Disk Usage';

title {
    my $c = shift;
    my $partition = $c->args->[1] || $c->args->[0] || '0';
    return "Disk ($partition)";
};

sub hrstorage {
    my ($c,$interface) = @_;
    if ( $interface !~ /^\d+$/ ) {
        my $disks = $c->component('SNMP')->table("hrStorageTable",
            columns => [qw/hrStorageIndex hrStorageDescr hrStorageAllocationUnits hrStorageSize hrStorageUsed/] );
        if ( !$disks ) {
            CloudForecast::Log->debug("couldnot get htStorage, use dskTable");
            return;
        }

        my $disk = List::Util::first { $_->{hrStorageDescr} eq $interface } values %{$disks};
        if ( !$disk ) {
            CloudForecast::Log->warn("couldnot find disk partition '$interface'");
            return;
        }
        CloudForecast::Log->debug("found partition '$interface' with hrStorageIndex:$disk->{hrStorageIndex}");
        return [ $disk->{hrStorageSize}*$disk->{hrStorageAllocationUnits}/1024,
                 $disk->{hrStorageUsed}*$disk->{hrStorageAllocationUnits}/1024 ];
    }
    my @map = map { [ $_, $interface ] } qw/hrStorageAllocationUnits hrStorageSize hrStorageUsed/;
    my $ret = $c->component('SNMP')->get(@map);
    my $allocsize = shift @$ret;
    return [$ret->[0]*$allocsize/1024, $ret->[1]*$allocsize/1024];
}

fetcher {
    my $c = shift;
    my $interface = $c->args->[0] || 0;

    my $usage = $c->hrstorage($interface);
    return $usage if $usage;    

    if ( $interface !~ /^\d+$/ ) {
        my $disks = $c->component('SNMP')->table("dskTable", 
            columns => [qw/dskIndex dskPath dskTotal dskUsed/] );
        if ( !$disks ) {
            CloudForecast::Log->warn("couldnot get dskTable");
            return [undef, undef];
        }
        my $disk = List::Util::first { $_->{dskPath} eq $interface } values %{$disks};
        if ( !$disk ) {
            CloudForecast::Log->warn("couldnot find disk partition '$interface'");
            return [undef, undef];
        }
        CloudForecast::Log->debug("found partition '$interface' with dskIndex:$disk->{dskIndex}");
        return [ $disk->{dskTotal}, $disk->{dskUsed} ];
    }

    my @map = map { [ $_, $interface ] } qw/dskTotal dskUsed/;
    return $c->component('SNMP')->get(@map);
};

__DATA__
@@ disk
DEF:my1=<%RRD%>:total:AVERAGE
DEF:my2=<%RRD%>:used:AVERAGE
CDEF:my1b=my1,1000,*
CDEF:my2b=my2,1000,*
AREA:my1b#ff99ff:Total
GPRINT:my1b:LAST:Cur\:%4.2lf%sB
AREA:my2b#cc00ff:Used 
GPRINT:my2b:LAST:Cur\:%4.2lf%sB

