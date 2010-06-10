package CloudForecast::Component::SNMP;

use CloudForecast::Component -connector;
use CloudForecast::Log;
use SNMP;

sub session {
    my $self = shift;
    $self->{session} ||= SNMP::Session->new(
        DestHost => $self->address,
        Community => $self->config->{community},
        Version => $self->config->{version},
        Timeout => 1000000,
    );
    $self->{session};
}

sub get {
    my $self = shift;
    my @ids = @_;
    my @ret;
    if ( $self->config->{version} eq '1' ) {
        for my $id ( @ids ) {
            my $val = $self->session->get( $id );
            CloudForecast::Log->warn("SNMP get failed : " . join(".",@$id)  . " : " . $self->session->{ErrorStr})
                if $self->session->{ErrorStr};
            push @ret, $val;
        }
    }
    else {
        @ret = $self->session->get( SNMP::VarList->new(@ids) );
        CloudForecast::Log->warn($self->session->{ErrorStr})
            if $self->session->{ErrorStr};

    }
    return \@ret;
}

sub get_by_int {
    my $self = shift;
    my $ret = $self->get(@_);
    return [ map { $_ =~ /^[0-9\.]+$/ ? $_ : '' } @$ret ];
}


1;

