package CloudForecast::Data::Diskio;

use CloudForecast::Data -base;

rrds map { [ $_, 'COUNTER' ] } qw/read write ioread iowrite/;
graphs 'byte' => 'DiskIO';
graphs 'count' => 'DiskIO Count';

title {
    my $c = shift;
    my $device = $c->args->[0] || '17';
    if ( $device =~ /^\d+$/ ) {
        $device = $c->ledge_get('device_name') || $device;
    }
    return "DiskIO ($device)";
};

fetcher {
    my $c = shift;
    my $device = $c->args->[0] || 17;

    if ( $device !~ /^\d+$/ ) {
        my $disks = $c->component('SNMP')->table("diskIOTable",
            columns => [qw/diskIOIndex diskIODevice diskIONRead diskIONWritten diskIOReads diskIOWrites/] );
        if ( !$disks ) {
            CloudForecast::Log->warn("couldnot get disk table");
            return [undef, undef, undef, undef];
        }
        my $disk = List::Util::first { $_->{diskIODevice} eq $device } values %{$disks};
        if ( !$disk ) {
            CloudForecast::Log->warn("couldnot find disk partition '$device'");
            return [undef, undef, undef, undef];
        }
        CloudForecast::Log->debug("found partition '$device' with diskIOIndex:$disk->{diskIOIndex}");
        return [ map { $disk->{$_} } qw/diskIONRead diskIONWritten diskIOReads diskIOWrites/ ];
    }
    else {
        my @map = map { [ $_, $device ] } qw/diskIODevice diskIONRead diskIONWritten diskIOReads diskIOWrites/;
        my $ret = $c->component('SNMP')->get(@map);
        my $device_name = shift @$ret;
        if ( $device_name ) {
            $c->ledge_set('device_name', $device_name);
        }
        return $ret;
    }
};


__DATA__
@@ byte
DEF:my1=<%RRD%>:read:AVERAGE
DEF:my2=<%RRD%>:write:AVERAGE
AREA:my1#00C000:Read(B/S)  
GPRINT:my1:LAST:Cur\: %4.1lf%s
GPRINT:my1:AVERAGE:Ave\: %4.1lf%s
GPRINT:my1:MAX:Max\: %4.1lf%s
GPRINT:my1:MIN:Min\: %4.1lf%s\l
STACK:my2#0000C0:Write(B/S) 
GPRINT:my2:LAST:Cur\: %4.1lf%s
GPRINT:my2:AVERAGE:Ave\: %4.1lf%s
GPRINT:my2:MAX:Max\: %4.1lf%s
GPRINT:my2:MIN:Min\: %4.1lf%s\l

@@ count
DEF:my1a=<%RRD%>:ioread:AVERAGE
DEF:my2a=<%RRD%>:iowrite:AVERAGE
CDEF:my1=my1a,0,100000,LIMIT
CDEF:my2=my2a,0,100000,LIMIT
AREA:my1#c0c0c0:Read  
GPRINT:my1:LAST:Cur\: %4.1lf%s
GPRINT:my1:AVERAGE:Ave\: %4.1lf%s
GPRINT:my1:MAX:Max\: %4.1lf%s
GPRINT:my1:MIN:Min\: %4.1lf%s\l
STACK:my2#800080:Write 
GPRINT:my2:LAST:Cur\: %4.1lf%s
GPRINT:my2:AVERAGE:Ave\: %4.1lf%s
GPRINT:my2:MAX:Max\: %4.1lf%s
GPRINT:my2:MIN:Min\: %4.1lf%s\l
