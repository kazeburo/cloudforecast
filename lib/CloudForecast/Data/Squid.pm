package CloudForecast::Data::Squid;

use CloudForecast::Data -base;
use CloudForecast::Log;
use SNMP;

rrds map { [ $_, 'COUNTER' ] } qw /request httphit httperror/;
rrds map { [ $_, 'GAUGE' ] } qw/allsvc misssvc nmsvc hitsvc hitratio/;

graphs 'request' => 'number of request';
graphs 'ratio' => 'cache hit ratio';
graphs 'svc' => 'response time (msec)';

sysinfo {
    my $c = shift;
    $c->ledge_get('sysinfo') || [];
};

fetcher {
    my $c = shift;
    my $port = $c->args->[0] || 3401;
    my $community = $c->args->[1] || 'public';
    
    my $sess = SNMP::Session->new(
        DestHost => $c->address,
        Community => $community,
        Version => 2,
        RemotePort => $port
    );

# SQUID-MIB::cacheProtoClientHttpRequests.0 = Counter32: 124343  Number of HTTP requests received 1.3.6.1.4.1.3495.1.3.2.1.1
# SQUID-MIB::cacheHttpHits.0 = Counter32: 91776  Number of HTTP Hits 1.3.6.1.4.1.3495.1.3.2.1.2
# SQUID-MIB::cacheHttpErrors.0 = Counter32: 0  Number of HTTP Errors 1.3.6.1.4.1.3495.1.3.2.1.3
# SQUID-MIB::cacheHttpAllSvcTime.5 = INTEGER: 0  HTTP all service time 1.3.6.1.4.1.3495.1.3.2.2.1.2.5
# SQUID-MIB::cacheHttpMissSvcTime.5 = INTEGER: 74  HTTP miss service time 1.3.6.1.4.1.3495.1.3.2.2.1.3.5
# SQUID-MIB::cacheHttpNmSvcTime.5 = INTEGER: 0  HTTP hit not-modified service time 1.3.6.1.4.1.3495.1.3.2.2.1.4.5
# SQUID-MIB::cacheHttpHitSvcTime.5 = INTEGER: 0  HTTP hit service time 1.3.6.1.4.1.3495.1.3.2.2.1.5.5
# SQUID-MIB::cacheRequestHitRatio.5 = INTEGER: 75 Request Hit Ratios 1.3.6.1.4.1.3495.1.3.2.2.1.9.5

    my @oid = map { [$_] } qw/
        .1.3.6.1.4.1.3495.1.3.2.1.1
        .1.3.6.1.4.1.3495.1.3.2.1.2
        .1.3.6.1.4.1.3495.1.3.2.1.3
        .1.3.6.1.4.1.3495.1.3.2.2.1.2.5
        .1.3.6.1.4.1.3495.1.3.2.2.1.3.5
        .1.3.6.1.4.1.3495.1.3.2.2.1.4.5
        .1.3.6.1.4.1.3495.1.3.2.2.1.5.5
        .1.3.6.1.4.1.3495.1.3.2.2.1.9.5
        .1.3.6.1.4.1.3495.1.1.3.0
        .1.3.6.1.4.1.3495.1.2.3.0
    /;
    
    my @ret = $sess->get( SNMP::VarList->new(@oid) );
    CloudForecast::Log->warn($sess->{ErrorStr})
        if $sess->{ErrorStr};
    my $version = pop @ret;
    my $uptime;
    if ( $uptime = pop @ret ) {
        $uptime = $uptime / 100;
        my $day = int( $uptime /86400 );
        my $hour = int( ( $uptime % 86400 ) / 3600 );
        my $min = int( ( ( $uptime % 86400 ) % 3600) / 60 );
        $uptime = sprintf("up %d days, %2d:%02d", $day, $hour, $min);
    }

    $c->ledge_set('sysinfo', [ version => $version, uptime => $uptime ] );

    return \@ret;
};

1;

__DATA__
@@ request
DEF:my1a=<%RRD%>:request:AVERAGE
DEF:my2a=<%RRD%>:httphit:AVERAGE
DEF:my3a=<%RRD%>:httperror:AVERAGE
CDEF:my1=my1a,0,25000,LIMIT
CDEF:my2=my2a,0,25000,LIMIT
CDEF:my3=my3a,0,25000,LIMIT
LINE1:my1#000080:Request    
GPRINT:my1:LAST:Cur\:%6.1lf
GPRINT:my1:AVERAGE:Ave\:%6.1lf
GPRINT:my1:MAX:Max\:%6.1lf
GPRINT:my1:MIN:Min\:%6.1lf\l
LINE1:my2#008080:Hit Request
GPRINT:my2:LAST:Cur\:%6.1lf
GPRINT:my2:AVERAGE:Ave\:%6.1lf
GPRINT:my2:MAX:Max\:%6.1lf
GPRINT:my2:MIN:Min\:%6.1lf\l
LINE1:my3#CC0000:Err Request
GPRINT:my3:LAST:Cur\:%6.1lf
GPRINT:my3:AVERAGE:Ave\:%6.1lf
GPRINT:my3:MAX:Max\:%6.1lf
GPRINT:my3:MIN:Min\:%6.1lf\l

@@ ratio
DEF:my1=<%RRD%>:hitratio:AVERAGE
AREA:my1#990000:Ratio
GPRINT:my1:LAST:Cur\:%5.1lf[%%]
GPRINT:my1:AVERAGE:Ave\:%5.1lf[%%]
GPRINT:my1:MAX:Max\:%5.1lf[%%]
GPRINT:my1:MIN:Min\:%5.1lf[%%]\l
LINE:100

@@ svc
DEF:my1=<%RRD%>:allsvc:AVERAGE
DEF:my2=<%RRD%>:misssvc:AVERAGE
DEF:my3=<%RRD%>:nmsvc:AVERAGE
DEF:my4=<%RRD%>:hitsvc:AVERAGE
LINE1:my1#CC0000:All        
GPRINT:my1:LAST:Cur\:%4.0lf
GPRINT:my1:AVERAGE:Ave\:%4.0lf
GPRINT:my1:MAX:Max\:%4.0lf
GPRINT:my1:MIN:Min\:%4.0lf\l
LINE1:my2#000080:Miss       
GPRINT:my2:LAST:Cur\:%4.0lf
GPRINT:my2:AVERAGE:Ave\:%4.0lf
GPRINT:my2:MAX:Max\:%4.0lf
GPRINT:my2:MIN:Min\:%4.0lf\l
LINE1:my3#008080:NotModified
GPRINT:my3:LAST:Cur\:%4.0lf
GPRINT:my3:AVERAGE:Ave\:%4.0lf
GPRINT:my3:MAX:Max\:%4.0lf
GPRINT:my3:MIN:Min\:%4.0lf\l
LINE1:my4#800080:Hit        
GPRINT:my4:LAST:Cur\:%4.0lf
GPRINT:my4:AVERAGE:Ave\:%4.0lf
GPRINT:my4:MAX:Max\:%4.0lf
GPRINT:my4:MIN:Min\:%4.0lf\l







