package CloudForecast::Data::Diskio;

use CloudForecast::Data -base;

rrds map { [ $_, 'COUNTER' ] } qw/read write ioread iowrite/;
graphs 'byte' => 'DiskIO';
graphs 'count' => 'DiskIO Count';

fetcher {
    my $c = shift;
    my @map = map { [ $_, 17 ] } qw/diskIONWritten diskIONRead diskIOWrites diskIOReads/;
    $c->component('SNMP')->get(@map);
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
