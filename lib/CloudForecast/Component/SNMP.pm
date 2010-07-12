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
            CloudForecast::Log->warn("SNMP get failed : " . join(".",@$id)  . " error: " . $self->session->{ErrorStr})
                if $self->session->{ErrorStr};
            $val = undef if $self->session->{ErrorStr} =~ m!\(noSuchName!i;
            push @ret, $val;
        }
    }
    else {
        @ret = $self->session->get( SNMP::VarList->new(@ids) );
        CloudForecast::Log->warn($self->session->{ErrorStr})
            if $self->session->{ErrorStr};
        my $i=0;
        my @filtered_ret;
        for my $ret ( @ret ) {
            if ( ! defined $ret || $ret eq 'NOSUCHOBJECT' ) {
                CloudForecast::Log->warn("SNMP get failed: " . join(".", @{$ids[$i]}) . " error: NOSUCHOBJECT");
                push @filtered_ret, undef;
            }
            else {
                push @filtered_ret, $ret;
            }
            $i++;
        }

        @ret = @filtered_ret;
    }
    return \@ret;
}

sub table {
    my $self = shift;
    my $ret = $self->session->gettable(@_);
    CloudForecast::Log->warn($self->session->{ErrorStr})
            if $self->session->{ErrorStr};
    $ret;
}

sub walk {
    my $self = shift;
    my @ids = @_;
    my $count = @ids;
    my $max = $self->config->{max_bulkwalk} || 10;
    my @ret = $self->session->bulkwalk( 0, $max, SNMP::VarList->new(map { [$_] } @ids) );

    if ( $self->session->{ErrorStr} ) {
        CloudForecast::Log->warn($self->session->{ErrorStr});
        return;
    }

    my $data_count = @{$ret[0]};
    my @data;
    for my $i ( 0..($data_count - 1) ) {
        my %hash;
        map {
            $hash{$ids[$_]} = $ret[$_]->[$i]->val
        }  0..($count-1);
        push @data,\%hash; 
    }
    return \@data;
}


1;

