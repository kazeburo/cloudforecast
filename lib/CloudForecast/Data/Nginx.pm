package CloudForecast::Data::Nginx;

use CloudForecast::Data -base;
use HTTP::Request;

rrds map { [ $_, 'GAUGE' ] } qw /read write wait/;
rrds 'request' => 'COUNTER';

graphs 'connection' => 'Nginx connections';
graphs 'request' => 'Nginx request counter';

title sub {
    my $c = shift;
    my $title = "Nginx";
    if ( my $port =$c->args->[0] ) {
        $title .= " ($port)";
    }
    return $title;
};

fetcher {
    my $c = shift;
    my $address = $c->address;
    my $port = $c->args->[0] || 80;
    my $path = $c->args->[1] || '/nginx_status';
    my $host = $c->args->[2];

    my $ua = $c->component('LWP');
    my $request = HTTP::Request->new( GET => "http://${address}:$port$path" );
    $request->header( 'Host', $host ) if $host;
    my $response = $ua->request($request);
    die "server-status failed: " .$response->status_line
        unless $response->is_success;

    my $read = -1;
    my $write = -1;
    my $wait = -1;
    my $req = -1;
    my $body = $response->content;

    if ( $body =~ /Reading: (\d+) Writing: (\d+) Waiting: (\d+)/ ) {
        $read = $1;
        $write = $2;
        $wait = $3;
    }
    if ( $body =~ /(\d+) (\d+) (\d+)/ ) {
        $req = $3;
    }
    
    return [$read, $write, $wait, $req];
};


__DATA__
@@ connection
DEF:my1=<%RRD%>:read:AVERAGE
DEF:my2=<%RRD%>:write:AVERAGE
DEF:my3=<%RRD%>:wait:AVERAGE
AREA:my1#c0c0c0:Reading  
GPRINT:my1:LAST:Cur\: %6.1lf
GPRINT:my1:AVERAGE:Ave\: %6.1lf
GPRINT:my1:MAX:Max\: %6.1lf
GPRINT:my1:MIN:Min\: %6.1lf\l
STACK:my2#000080:Writing  
GPRINT:my2:LAST:Cur\: %6.1lf
GPRINT:my2:AVERAGE:Ave\: %6.1lf
GPRINT:my2:MAX:Max\: %6.1lf
GPRINT:my2:MIN:Min\: %6.1lf\l
STACK:my3#008080:Waiting 
GPRINT:my3:LAST:Cur\: %6.1lf
GPRINT:my3:AVERAGE:Ave\: %6.1lf
GPRINT:my3:MAX:Max\: %6.1lf
GPRINT:my3:MIN:Min\: %6.1lf\l

@@ request
DEF:my1t=<%RRD%>:request:AVERAGE
CDEF:my1=my1t,0,25000,LIMIT
LINE1:my1#00C000:Request  
GPRINT:my1:LAST:Cur\: %4.1lf
GPRINT:my1:AVERAGE:Ave\: %4.1lf
GPRINT:my1:MAX:Max\: %4.1lf
GPRINT:my1:MIN:Min\: %4.1lf\l




