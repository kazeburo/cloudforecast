package CloudForecast::Gearman::Worker;

use strict;
use warnings;
use base qw/Class::Accessor::Fast/;
use Gearman::Worker;
use UNIVERSAL::require;
use Storable qw//;
use Parallel::Prefork::SpareWorkers;
use CloudForecast::Log;
use CloudForecast::ConfigLoader;
use CloudForecast::Gearman::Scoreboard;

__PACKAGE__->mk_accessors(qw/configloader
                             restarter
                             max_workers
                             max_requests_per_child
                             max_exection_time/);

our $GEARMAN_WORKER_CONNECT = {};

sub new {
    my $class = shift;
    my $args = ref $_[0] ? shift : { @_ };

    my $configloader = CloudForecast::ConfigLoader->new({
        root_dir => $args->{root_dir},
        global_config => $args->{global_config}
    });
    $configloader->load_global_config();
    my $global_config = $configloader->global_config;

    die 'gearman is disabled' unless $global_config->{gearman_enable};

    $class->SUPER::new({
        configloader => $configloader,
        restarter => $args->{restarter},
        max_workers => $args->{max_workers} || 4,
        max_requests_per_child => $args->{max_requests_per_child} || 50,
        max_exection_time => $args->{max_exection_time} || 60,
    });
}

sub gearman_worker {
    my $self = shift;
    my $global_config = $self->configloader->global_config;
    my $host = $global_config->{gearman_server}->{host};
    my $port = $global_config->{gearman_server}->{port} || 7003;

    my $worker = $GEARMAN_WORKER_CONNECT->{"${host}:$port"};
    return $worker if $worker;

    $worker = Gearman::Worker->new;
    $worker->job_servers( "${host}:$port" );
    $GEARMAN_WORKER_CONNECT->{"${host}:$port"} = $worker;
    $worker;
}


sub load_resource {
    my $self = shift;
    my $args = shift;

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
        global_config => $self->configloader->global_config,
    });

    return $resource;
}

sub fetcher_worker {
    my $self = shift;

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
            my $resource = $self->load_resource($args);
            $resource->exec_fetch;
        };
        CloudForecast::Log->warn("fetcher failed: $@") if $@;
        1;
    } );

    $self->run_worker(@_);
}

sub updater_worker {
    my $self  = shift;

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
            my $resource = $self->load_resource($args);
            $resource->exec_updater($args->{result});
        };
        CloudForecast::Log->warn("fetcher failed: $@") if $@;
        1;
    });
    $self->run_worker(@_);
}

sub watchdog_zombie {
    my $self = shift;
    my $scoreboard = shift;

    my $pid = fork();
    die "fork failed: $!" unless defined $pid;
    return $pid if($pid); # main process

    while ( 1 ) {
        my @statuses = $scoreboard->get_parsed_statuses;
        for my $status ( @statuses ) {
            if ( $status->{status} eq CloudForecast::Gearman::Scoreboard::STATUS_ACTIVE
                     && time - $status->{time} > $self->max_exection_time ) {
                CloudForecast::Log->warn("exection_time exceed, kill: " . $status->{pid});
                kill 'TERM', $status->{pid}
            }
        }
        sleep 30;
    }
}

sub run_worker {
    my $self = shift;
    my $worker = $self->gearman_worker;
 
    my $scoreboard = CloudForecast::Gearman::Scoreboard->new( 
        undef, $self->max_workers );

    my @watchdog_pid;
    push @watchdog_pid, $self->watchdog_zombie( $scoreboard );
    if ( $self->restarter ) {
        push @watchdog_pid, $self->configloader->watchdog;
    }

    my $pm = Parallel::Prefork::SpareWorkers->new({
        max_workers  => $self->max_workers,
        min_spare_workers => $self->max_workers,
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
            on_start => sub {
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
                $i++ >= $self->max_requests_per_child
            }
        );

        $pm->finish;
    }

    $pm->wait_all_children();

    for my $pid ( @watchdog_pid ) {
        kill 'TERM', $pid;
        waitpid( $pid, 0 );
    }
}

1;

