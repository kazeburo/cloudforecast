package CloudForecast::Data::Apache;

use CloudForecast::Data -base;
use HTTP::Request;

# TODO: ほんとは args とかで resouces 個別に有効/無効を選べるようにしたい。
my $ExtendedStatus = $ENV{CF_AP_EXTEND} || 0;

my @status_def = (
    { ds => 'wait', key => '_', desc => 'Waiting for Connection' },
    { ds => 'stup', key => 'S', desc => 'Starting up' },
    { ds => 'read', key => 'R', desc => 'Reading Request' },
    { ds => 'send', key => 'W', desc => 'Sending Reply' },
    { ds => 'keep', key => 'K', desc => 'Keepalive (read)' },
    { ds => 'dnsl', key => 'D', desc => 'DNS Lookup' },
    { ds => 'clos', key => 'C', desc => 'Closing connection' },
    { ds => 'logg', key => 'L', desc => 'Logging' },
    { ds => 'gfin', key => 'G', desc => 'Gracefully finishing' },
    { ds => 'idle', key => 'I', desc => 'Idle cleanup of worker' },
    { ds => 'open', key => '.', desc => 'Open slot with no current process' },
);
my @status_dsnames = map { $_->{ds} } @status_def;
my %dsname_of      = map { $_->{key} => $_->{ds} } @status_def;

rrds map { [ $_, 'GAUGE' ] } @status_dsnames;
graphs 'ap_status' => 'Apache Status';

# あとで追加するのは面倒なので、DS だけは作っておく。
rrds map { [ $_, 'GAUGE' ] } qw(rps bps bpr);
if ($ExtendedStatus) {
    graphs 'ap_rps' => 'Apache Req/s';
    graphs 'ap_bps' => 'Apache Bytes/s';
    graphs 'ap_bpr' => 'Apache Bytes/req';
}

title {
    my $c = shift;
    my $title = "Apache";
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
        $c->ledge_add('sysinfo', ['version', $server_version]);
    }
    if ($host) {
        $c->ledge_add('sysinfo', ['host', $host]);
    }

    my $content = $response->content;
    my %status = map { $_ => 0 } @status_dsnames;
    my($rps, $bps, $bpr);
    foreach my $line ( split /[\r\n]+/, $content ) {
        if ( $line =~ /^ReqPerSec: ([.\d]+)/ ) {
            $rps = $1;
        } elsif ( $line =~ /^BytesPerSec: ([.\d]+)/ ) {
            $bps = $1;
        } elsif ( $line =~ /^BytesPerReq: ([.\d]+)/ ) {
            $bpr = $1;
        } elsif ( $line =~ /^Scoreboard:\s*(.+)/ ) {
            for my $k (split //, $1) {
                $status{ $dsname_of{$k} }++;
            }
        }
    }

    if ($ExtendedStatus) {
        return [@status{@status_dsnames}, $rps, $bps, $bpr];
    } else {
        return [@status{@status_dsnames}];
    }
};

=encoding utf-8

=head1 NAME

CloudForecast::Data::Apache - monitor statuses of Apache

=head1 SYNOPSIS

    component_config:
    resources:
      - apache:80:/server-status?auto:www.example.com

=head1 DESCRIPTION

monitor statuses of Apache by mod_status

graphs:

    * Status of eash process
      * Waiting, Sending reply, ...
    * Request per second (requires ExtendedStatus On)
    * Bytes per second (requires ExtendedStatus On)
    * Bytes per request (requires ExtendedStatus On)

args:

    [0]: port number. default is 80.
    [1]: path of server status. default is '/server-status?auto'.
    [2]: hostname for Host header. optional.

=head1 AUTHOR

HIROSE Masaaki E<lt>hirose31@gmail.comE<gt>

=head1 SEE ALSO

L<http://httpd.apache.org/docs/2.2/en/mod/mod_status.html>

=cut

__DATA__
@@ ap_status
DEF:stup=<%RRD%>:stup:AVERAGE
DEF:read=<%RRD%>:read:AVERAGE
DEF:send=<%RRD%>:send:AVERAGE
DEF:keep=<%RRD%>:keep:AVERAGE
DEF:dnsl=<%RRD%>:dnsl:AVERAGE
DEF:clos=<%RRD%>:clos:AVERAGE
DEF:logg=<%RRD%>:logg:AVERAGE
DEF:gfin=<%RRD%>:gfin:AVERAGE
DEF:idle=<%RRD%>:idle:AVERAGE
DEF:wait=<%RRD%>:wait:AVERAGE
DEF:open=<%RRD%>:open:AVERAGE
CDEF:total=stup,read,send,keep,dnsl,clos,logg,gfin,idle,wait,+,+,+,+,+,+,+,+,+
COMMENT:                        
COMMENT:  Cur
COMMENT:  Ave 
COMMENT:  Max
COMMENT:  Min\j
AREA:stup#FFD660:Starting up           :STACK
GPRINT:stup:LAST:%5.1lf
GPRINT:stup:AVERAGE:%5.1lf
GPRINT:stup:MAX:%5.1lf
GPRINT:stup:MIN:%5.1lf\j
AREA:read#FF0000:Reading Request       :STACK
GPRINT:read:LAST:%5.1lf
GPRINT:read:AVERAGE:%5.1lf
GPRINT:read:MAX:%5.1lf
GPRINT:read:MIN:%5.1lf\j
AREA:send#157419:Sending Reply         :STACK
GPRINT:send:LAST:%5.1lf
GPRINT:send:AVERAGE:%5.1lf
GPRINT:send:MAX:%5.1lf
GPRINT:send:MIN:%5.1lf\j
AREA:keep#00CF00:Keepalive (read)      :STACK
GPRINT:keep:LAST:%5.1lf
GPRINT:keep:AVERAGE:%5.1lf
GPRINT:keep:MAX:%5.1lf
GPRINT:keep:MIN:%5.1lf\j
AREA:dnsl#55D6D3:DNS Lookup            :STACK
GPRINT:dnsl:LAST:%5.1lf
GPRINT:dnsl:AVERAGE:%5.1lf
GPRINT:dnsl:MAX:%5.1lf
GPRINT:dnsl:MIN:%5.1lf\j
AREA:clos#797C6E:Closing connection    :STACK
GPRINT:clos:LAST:%5.1lf
GPRINT:clos:AVERAGE:%5.1lf
GPRINT:clos:MAX:%5.1lf
GPRINT:clos:MIN:%5.1lf\j
AREA:logg#942D0C:Logging               :STACK
GPRINT:logg:LAST:%5.1lf
GPRINT:logg:AVERAGE:%5.1lf
GPRINT:logg:MAX:%5.1lf
GPRINT:logg:MIN:%5.1lf\j
AREA:gfin#C0C0C0:Gracefuly finishing   :STACK
GPRINT:gfin:LAST:%5.1lf
GPRINT:gfin:AVERAGE:%5.1lf
GPRINT:gfin:MAX:%5.1lf
GPRINT:gfin:MIN:%5.1lf\j
AREA:idle#F9FD5F:Idle cleanup of worker:STACK
GPRINT:idle:LAST:%5.1lf
GPRINT:idle:AVERAGE:%5.1lf
GPRINT:idle:MAX:%5.1lf
GPRINT:idle:MIN:%5.1lf\j
AREA:wait#FFC3C0:Waiting for connection:STACK
GPRINT:wait:LAST:%5.1lf
GPRINT:wait:AVERAGE:%5.1lf
GPRINT:wait:MAX:%5.1lf
GPRINT:wait:MIN:%5.1lf\j

@@ ap_rps
DEF:my1=<%RRD%>:rps:AVERAGE
LINE1:my1#aa0000:Request/sec
GPRINT:my1:LAST:Cur\:%6.2lf
GPRINT:my1:AVERAGE:Ave\:%6.2lf
GPRINT:my1:MAX:Max\:%6.2lf
GPRINT:my1:MIN:Min\:%6.2lf [req]\l

@@ ap_bps
DEF:my1=<%RRD%>:bps:AVERAGE
AREA:my1#00cf00:Bytes/sec
GPRINT:my1:LAST:Cur\:%5.1lf%S
GPRINT:my1:AVERAGE:Ave\:%5.1lf%S
GPRINT:my1:MAX:Max\:%5.1lf%S
GPRINT:my1:MIN:Min\:%5.1lf%S [Byte]\l

@@ ap_bpr
DEF:my1=<%RRD%>:bpr:AVERAGE
AREA:my1#00cf00:Bytes/req
GPRINT:my1:LAST:Cur\:%5.1lf%S
GPRINT:my1:AVERAGE:Ave\:%5.1lf%S
GPRINT:my1:MAX:Max\:%5.1lf%S
GPRINT:my1:MIN:Min\:%5.1lf%S [Byte]\l
