package CloudForecast::Data::Apcupsd;

use CloudForecast::Data -base;

rrds map { [ $_, 'GAUGE' ] }
    qw(loadpct bcharge
       linev battv
       timeleft
     );
graphs 'pct'      => 'UPS Battery';
graphs 'volt'     => 'UPS Voltage';
graphs 'timeleft' => 'UPS Timeleft';

title {
    my $c = shift;
    my $title = "APC UPS";
    return $title;
};

sysinfo {
    my $c = shift;
    $c->ledge_get('sysinfo') || [];
};

fetcher {
    my $c = shift;
    my $apcaccess = $c->args->[0] || '/sbin/apcaccess';
    my @metrics = qw(loadpct bcharge linev battv timeleft);
    my %value;

    ### fetch metrics
    my @status_data = _retrieve_apcupsd_status($apcaccess)
        or die "failed: retrieve_apcupsd_status";
    my $status = _parse_status_data(@status_data);

    for my $metric (@metrics) {
        $value{$metric} = $status->{$metric} =~ /([\d.]+)/ ? $1 : undef;
    }

    ### set sysinfo
    my @sysinfo;
    map {
        push @sysinfo, $_, $status->{$_} || 'Unknown'
    } grep { exists $status->{$_} }
        qw(
              model
              status
              starttime
         );
    $c->ledge_set('sysinfo', \@sysinfo);

    return [@value{@metrics}];
};

sub _retrieve_apcupsd_status {
    my $apcaccess = shift;
    open my $apc, '-|', $apcaccess
        or die $!;
    my @status_data = <$apc>;
    close $apc;
    chomp @status_data;
    return @status_data;
}

sub _parse_status_data {
    my $status = {};
    my($k,$v);
    for (@_) {
        ($k,$v) = split /\s*:\s*/, $_, 2;
        $status->{lc($k)} = $v;
    }
    return $status;
}

=encoding utf-8

=head1 NAME

CloudForecast::Data::Apcupsd - monitor statuses of APC UPS

=head1 SYNOPSIS

    component_config:
    resources:
      - apcupsd:/sbin/apcaccess

=head1 DESCRIPTION

monitor statuses of APC UPS by apcupsd and apcaccess.

graphs:

    * Battery percentage
      * load capacity %
      * charge on the batteries pct
    * Voltage
      * line voltage as returned by the UPS
      * attery voltage as supplied by the UPS
    * Timeleft
      *remaining runtime left on batteries

args:

    [0]: path of "apcaccess" command. default is "/sbin/apcaccess".

=head1 AUTHOR

HIROSE Masaaki E<lt>hirose31@gmail.comE<gt>

=head1 SEE ALSO

L<http://www.apcupsd.com/>

=cut

__DATA__
@@ pct
DEF:my1=<%RRD%>:loadpct:AVERAGE
DEF:my2=<%RRD%>:bcharge:AVERAGE
COMMENT:                       
COMMENT: Cur
COMMENT:Ave
COMMENT:Max
COMMENT:Min     \j
LINE1:my1#330000:load capacity          
GPRINT:my1:LAST:%5.1lf
GPRINT:my1:AVERAGE:%5.1lf
GPRINT:my1:MAX:%5.1lf
GPRINT:my1:MIN:%5.1lf [%%]\j
LINE1:my2#00cf00:charge on the batteries
GPRINT:my2:LAST:%5.1lf
GPRINT:my2:AVERAGE:%5.1lf
GPRINT:my2:MAX:%5.1lf
GPRINT:my2:MIN:%5.1lf [%%]\j

@@ volt
DEF:my1=<%RRD%>:battv:AVERAGE
DEF:my2=<%RRD%>:linev:AVERAGE
COMMENT:                         
COMMENT: Cur
COMMENT:Ave
COMMENT:Max
COMMENT:Min     \j
LINE1:my1#330000:battery supplied voltage
GPRINT:my1:LAST:%5.1lf
GPRINT:my1:AVERAGE:%5.1lf
GPRINT:my1:MAX:%5.1lf
GPRINT:my1:MIN:%5.1lf [V]\j
LINE1:my2#00cf00:line voltage            
GPRINT:my2:LAST:%5.1lf
GPRINT:my2:AVERAGE:%5.1lf
GPRINT:my2:MAX:%5.1lf
GPRINT:my2:MIN:%5.1lf [V]\j

@@ timeleft
DEF:my1=<%RRD%>:timeleft:AVERAGE
COMMENT:                
COMMENT: Cur
COMMENT:Ave
COMMENT:Max
COMMENT:Min       \j
LINE1:my1#00cf00:remaining runtime
GPRINT:my1:LAST:%5.1lf
GPRINT:my1:AVERAGE:%5.1lf
GPRINT:my1:MAX:%5.1lf
GPRINT:my1:MIN:%5.1lf [min]\j

