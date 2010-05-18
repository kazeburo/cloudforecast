package CloudForecast::Radar;

use strict;
use warnings;
use base qw/Class::Accessor::Fast/;
use CloudForecast::ConfigLoader;
use CloudForecast::Host;
use CloudForecast::Log;

__PACKAGE__->mk_accessors(qw/root_dir global_config server_list/);


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

    CloudForecast::Log->debug("finished parse yaml");
    
    foreach my $server ( @$server_list ) {
        my $hosts = $server->{hosts};
        foreach my $host ( @$hosts ) {
            $self->run_host($host, $global_config);
        }
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


