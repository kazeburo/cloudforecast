package CloudForecast::Gearman;

use strict;
use warnings;
use base qw/Class::Accessor::Fast/;
use Gearman::Client;
use Storable qw//;
use CloudForecast::Log;


__PACKAGE__->mk_accessors(qw/host port/);

our $GEARMAN_CONNECT = {};

sub new {
    my $class = shift;
    my $args = ref $_[0] ? shift : { @_ };

    Carp::croak "no gearman host" unless $args->{host};

    $class->SUPER::new({
        host => $args->{host},
        port => $args->{port} || 7003,
    });
}

sub gearman_client {
    my $self = shift;
    my $host = $self->host;
    my $port = $self->port || 7003;

    die 'no host' unless $host;

    my $client = $GEARMAN_CONNECT->{"${host}:$port"};
    return $client if $client;

    $client = Gearman::Client->new;
    $client->job_servers( "${host}:$port" );
    $GEARMAN_CONNECT->{"${host}:$port"} = $client;
    $client;
}


sub fetcher {
    my $self = shift;
    my $args = shift;
    $self->gearman_client->dispatch_background(
        'fetcher',
        Storable::nfreeze($args),
    );
}

sub updater {
    my $self = shift;
    my $args = shift;
    $self->gearman_client->dispatch_background(
        'updater',
        Storable::nfreeze($args),
    );
}

1

