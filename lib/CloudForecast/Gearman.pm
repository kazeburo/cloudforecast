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

sub _ledge_update {
    my $self = shift;
    my @args = @_;
    my $freeze = $self->gearman_client->do_task(
        'ledge',
        Storable::nfreeze(\@args),
        { high_priority => 1 },
    );
    my $ret = Storable::thaw($$freeze);
    die $ret->{errorstr} if $ret->{error};
    $ret->{status};
}

sub _ledge_background_update {
    my $self = shift;
    my @args = @_;
    my $freeze = $self->gearman_client->dispatch_background(
        'ledge',
        Storable::nfreeze(\@args),
    );
}

sub ledge_add { shift->_ledge_update('add', @_ ) }
sub ledge_set { shift->_ledge_update('set', @_ ) }
sub ledge_delete { shift->_ledge_update('delete', @_ ) }
sub ledge_expire { shift->_ledge_update('expire', @_ ) }

sub ledge_background_add { shift->_ledge_background_update('add', @_ ) }
sub ledge_background_set { shift->_ledge_background_update('set', @_ ) }
sub ledge_background_delete { shift->_ledge_background_update('delete', @_ ) }
sub ledge_background_expire { shift->_ledge_background_update('expire', @_ ) }

sub ledge_get {
    my $self = shift;
    my @args = @_;
    unshift @args, 'get';
    my $freeze = $self->gearman_client->do_task(
        'ledge',
        Storable::nfreeze(\@args),
    );
    my $ret = Storable::thaw($$freeze);
    die $ret->{errorstr} if $ret->{error};
    wantarray ? ( $ret->{data}, $ret->{csum} ) : $ret->{data};
}

1;


