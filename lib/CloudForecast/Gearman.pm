package CloudForecast::Gearman;

use strict;
use warnings;
use base qw/Class::Accessor::Fast/;
use Gearman::Client;
use Gearman::Worker;
use CloudForecast::Log;
use Parallel::Prefork::SpareWorkers;
use UNIVERSAL::require;
use Storable qw//;
use CloudForecast::Gearman::Scoreboard;


__PACKAGE__->mk_accessors(qw/host port/);

our $GEARMAN_CONNECT = {};
our $GEARMAN_WORKER_CONNECT = {};

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

sub gearman_worker {
    my $self = shift;
    my $host = $self->host;
    my $port = $self->port || 7003;

    my $worker = $GEARMAN_WORKER_CONNECT->{"${host}:$port"};
    return $worker if $worker;

    $worker = Gearman::Worker->new;
    $worker->job_servers( "${host}:$port" );
    $GEARMAN_WORKER_CONNECT->{"${host}:$port"} = $worker;
    $worker;
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

sub load_resource {
    my $self = shift;
    my ( $args, $global_config ) = @_;

    my $resource_class = $args->{resource_class};
    die "resource_class not defined" unless $resource_class;
    $resource_class = ucfirst $resource_class;
    $resource_class = "CloudForecast::Data::" . $resource_class;
    $resource_class->require or die $@;
    
    my $resource = $resource_class->new({
        hostname => $args->{hostname},
        address => $args->{address},
        details => $args->{details},
        args => $args->{args},
        component_config => $args->{component_config},
        global_config => $global_config,
    });

    return $resource;
}

sub fetcher_worker {
    my $self = shift;
    my $global_config = shift;

    my $worker = $self->gearman_worker;
    $worker->register_function('fetcher', sub {
        my $job = shift;
        eval {
            my $args;
            eval {
                $args = Storable::thaw($job->arg);
                $args or die "invalid arg";
            };
            die "failed thaw: $@" if $@;
            my $resource = $self->load_resource($args, $global_config);
            $resource->exec_fetch;
        };
        CloudForecast::Log->warn("fetcher failed: $@") if $@;
        1;
    } );

    $self->run_worker(@_);
}

sub updater_worker {
    my $self  = shift;
    my $global_config = shift;

    my $worker = $self->gearman_worker;
    $worker->register_function('updater', sub {
        my $job = shift;
        eval {
            my $args;
            eval {
                $args = Storable::thaw($job->arg);
                $args or die "invalid arg";
            };
            die "failed thaw: $@" if $@;
            my $resource = $self->load_resource($args, $global_config);
            $resource->exec_updater($args->{result});
        };
        CloudForecast::Log->warn("fetcher failed: $@") if $@;
        1;
    });
    $self->run_worker(@_);
}

sub fork_watch_zombie {
    my $self = shift;
    my $scoreboard = shift;
    my $max_exection_time = shift;

    my $pid = fork();
    return if($pid); # main process

    while ( 1 ) {
        my @statuses = $scoreboard->get_parsed_statuses;
        my @long_active = grep {
            $_->{status} eq CloudForecast::Gearman::Scoreboard::STATUS_ACTIVE
                && time - $_->{time} > $max_exection_time
            } @statuses;
        map { kill 'TERM', $_->{pid} } @long_active;
        sleep 30;
    }
}

sub run_worker {
    my $self = shift;
    my ($max_workers, $max_requests_per_child, $max_exection_time ) = @_;
    $max_workers ||= 4;
    $max_requests_per_child ||= 50;
    $max_exection_time ||= 60;

    my $worker = $self->gearman_worker;
 
    my $scoreboard = CloudForecast::Gearman::Scoreboard->new( undef, $max_workers );
    $self->fork_watch_zombie( $scoreboard, $max_exection_time );

    my $pm = Parallel::Prefork::SpareWorkers->new({
        max_workers  => $max_workers,
        scoreboard   => $scoreboard,
        trap_signals => {
            TERM => 'TERM',
            HUP  => 'TERM',
            USR1 => undef,
        }
    });

    while ( $pm->signal_received ne 'TERM' ) {
        $pm->start and next;

        my $i = 0;
        $worker->work(
            start_cb => sub {
                $i++;
                $pm->set_status( CloudForecast::Gearman::Scoreboard::STATUS_ACTIVE );
            },
            on_fail => sub {
                $pm->set_status( CloudForecast::Gearman::Scoreboard::STATUS_IDLE );
            },
            on_complete => sub {
                $pm->set_status( CloudForecast::Gearman::Scoreboard::STATUS_IDLE );
            },
            stop_if => sub {
                $i++ >= $max_requests_per_child
            }
        );

        $pm->finish;
    }

    $pm->wait_all_children();
}


1;

