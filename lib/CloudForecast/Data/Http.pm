package CloudForecast::Data::Http;

use CloudForecast::Data -base;

rrds map { [ $_, 'GAUGE' ] } qw /busy idle/;
graphs 'http' => 'Apache Status';

title sub {
    my $c = shift;
    my $title = "HTTP";
    if ( my $port = $c->args->[0] ) {
        $title .= " ($port)";
    }
    return $title;
};

fetcher {
    my $c = shift;
    my $address = $c->address;
    my $port = $c->args->[0] || 80;
    
    my $ua = $c->component('LWP');
    my $response = $ua->get("http://${address}:$port/server-status?auto");
    die "server-status failed: " .$response->status_line
        unless $response->is_success;
    my $content = $response->content;
    my $busy = -1;
    my $idle = -1;
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


