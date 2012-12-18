package CloudForecast::Radar;

use strict;
use warnings;
use base qw/Class::Accessor::Fast/;
use CloudForecast::ConfigLoader;
use CloudForecast::Host;
use CloudForecast::Log;
use POSIX ":sys_wait_h";

# preload
require CloudForecast::Data;

__PACKAGE__->mk_accessors(qw/restarter
                             root_dir
                             global_config
                             server_list/);


sub run {
    my $self = shift;

    my $configloader = CloudForecast::ConfigLoader->new({
        root_dir => $self->root_dir,
        global_config => $self->global_config,
        server_list => $self->server_list,
    });
    $configloader->load_all();

    my $global_config = $configloader->global_config;
    my $server_list = $configloader->server_list;

    CloudForecast::Log->debug("finished load config");
    
    my @watchdog_pid;
    if ( $self->restarter ) {
        CloudForecast::Log->debug("restarter start");
        push @watchdog_pid, $configloader->watchdog;
    }

    my $now = time;
    my $interval = $global_config->{interval} || 300;
    my $next = $now - ( $now % $interval )  + $interval;
    my $pid;

    my @signals_received;
    $SIG{$_} = sub {
        push @signals_received, $_[0];
    } for (qw/INT TERM HUP/);
    $SIG{$_} = sub {
        $next = 0;
    } for (qw/ALRM/);
    $SIG{PIPE} = 'IGNORE';

    CloudForecast::Log->warn( sprintf( "first radar start in %s", scalar localtime $next) );

    while ( 1 ) {
        select( undef, undef, undef, 0.5 );
        if ( $pid ) {
            my $kid = waitpid( $pid, WNOHANG );
            if ( $kid == -1 ) {
                CloudForecast::Log->warn( "no child process");
                $pid = undef;
            }
            elsif ( $kid ) {
                CloudForecast::Log->warn( sprintf("radar finish pid: %d, code:%d", $kid, $? >> 8) );
                CloudForecast::Log->warn( sprintf( "next radar start in %s", scalar localtime $next) );
                $pid = undef;
            }
        }

        if ( scalar @signals_received ) {
            CloudForecast::Log->warn( "signals_received:" . join ",",  @signals_received );
            last;
        }

        $now = time;
        if ( $now >= $next ) {
            CloudForecast::Log->warn( sprintf( "(%s) radar start ", scalar localtime $next) );
            $next = $now - ( $now % 300 ) + 300;

            if ( $pid ) {
                CloudForecast::Log->warn( "Previous radar exists, skipping this time");
                next;
            }

            $pid = fork();
            die "failed fork: $!" unless defined $pid;
            next if $pid; #main process

            # child process
            foreach my $group ( @$server_list ) {
                foreach my $sub_group ( @{$group->{sub_groups}} ) {
                    my $hosts = $sub_group->{hosts};
                    foreach my $host ( @$hosts ) {
                        $self->run_host($host, $global_config);
                    }
                }
            }
            exit 0;
        }
    }

    if ( $pid ) {
        CloudForecast::Log->warn( "waiting for radar process finishing" );
        waitpid( $pid, 0 );
    }
    
    for my $watchdog_pid ( @watchdog_pid ) {
        kill 'TERM', $watchdog_pid;
        waitpid( $watchdog_pid, 0 );
    }
}

sub run_host {
    my $self = shift;
    my ( $host_config, $global_config ) = @_;
    my $host = CloudForecast::Host->new({
        address => $host_config->{address},
        hostname => $host_config->{hostname},
        details => $host_config->{details},
        resources => $host_config->{resources},
        component_config => $host_config->{component_config},
        global_config => $global_config
    });
 
    CloudForecast::Log->debug("run host: $host_config->{hostname}($host_config->{address})");
    $host->run();
}


1;


