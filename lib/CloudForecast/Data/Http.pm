package CloudForecast::Data::Http;

use CloudForecast::Data -base;
use HTTP::Request;

rrds map { [ $_, 'GAUGE' ] } qw /busy idle/;
graphs 'http' => 'Apache Status';

title {
    my $c = shift;
    my $title = "HTTP";
    if ( my $port = $c->args->[0] ) {
        $title .= " ($port)";
    }
    return $title;
};

sysinfo {
    my $c = shift;
    $c->ledge_get('sysinfo') || [];
};

fetcher {
    my $c = shift;
    my $address = $c->address;
    my $port = $c->args->[0] || 80;
    my $path = $c->args->[1] || '/server-status?auto';
    my $host = $c->args->[2];

    my $ua = $c->component('LWP');
    my $req = HTTP::Request->new( GET => "http://${address}:$port$path" );
    $req->header('Host', $host ) if $host;
    my $response = $ua->request($req);
    die "server-status failed: " .$response->status_line
        unless $response->is_success;

    if ( my $server_version = $response->header('Server') ) {
        $c->ledge_set('sysinfo', [ version => $server_version ] );
    }

    my $content = $response->content;
    my $busy;
    my $idle;
    foreach my $line ( split /[\r\n]+/, $content ) {
        if ( $line =~ /^Busy.+: (\d+)/ ) {
            $busy = $1;
        }
        if ( $line =~ /^Idle.+: (\d+)/ ) {
            $idle = $1;
        }
    }
    return [$busy,$idle];
};

__DATA__
@@ http
DEF:my1=<%RRD%>:busy:AVERAGE
DEF:my2=<%RRD%>:idle:AVERAGE
AREA:my1#00C000:Busy  
GPRINT:my1:LAST:Cur\: %4.1lf
GPRINT:my1:AVERAGE:Ave\: %4.1lf
GPRINT:my1:MAX:Max\: %4.1lf
GPRINT:my1:MIN:Min\: %4.1lf\c
STACK:my2#0000C0:Idle  
GPRINT:my2:LAST:Cur\: %4.1lf
GPRINT:my2:AVERAGE:Ave\: %4.1lf
GPRINT:my2:MAX:Max\: %4.1lf
GPRINT:my2:MIN:Min\: %4.1lf\c


