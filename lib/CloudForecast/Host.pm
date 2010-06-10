package CloudForecast::Host;

use strict;
use warnings;
use base qw/Class::Accessor::Fast/;
use UNIVERSAL::require;
use CloudForecast::Log;

__PACKAGE__->mk_accessors(qw/address hostname details resources
                             component_config global_config/);

sub list_graph {
    my $self = shift;
    my @ret;
    my $resources = $self->resources;
    for my $resource ( @$resources ) {
        my $data = $self->load_resource($resource);
        my @graphs = $data->list_graph;
        push @ret, {
            graph_title => $data->graph_title,
            resource_class => $data->resource_class,
            resource => $resource,
            graphs => \@graphs,
        };
    }
    return @ret;
}

sub find_resource {
    my $self = shift;
    my $key = shift;
    
    my %resources_hash = map { $_ => $_  } @{$self->resources};
    my $resource = $resources_hash{$key};

    CloudForecast::Log->warn("find_resource $key failed in ",
                             $self->hostname, "(",$self->address,")" ) unless $resource;
    return unless $resource;
    my $data = $self->load_resource($resource);
    return $data;
}

sub draw_graph {
    my $self = shift;
    my ( $resource, $key, $span ) = @_;

    my $data = $self->find_resource($resource);
    return unless $data;
    my $img;
    eval {
        $img = $data->draw_graph( $key, $span );
    };
    my $err = $@;
    CloudForecast::Log->warn("draw_graph $resource failed: $@ in ",
                             $self->hostname, "(",$self->address,")" ) if $@;
    return ($img,$err);
}

sub run {
    my $self = shift;

    my $resources = $self->resources;
    for my $resource ( @$resources ) {
        eval {
            my $data = $self->load_resource($resource);
            $data->call_fetch();
        };
        CloudForecast::Log->warn("run_resource $resource failed: $@ in ",
                                 $self->hostname, "(",$self->address,")" ) if $@;
    }
}

sub load_data_module {
    my $self = shift;
    my $resource = shift;

    $resource = ucfirst $resource;
    my $module = "CloudForecast::Data::" . $resource;
    $module->require or die $@;
    $module;
}

sub load_resource {
    my $self = shift;
    my $resource_line = shift;

    my ($resource, @args) = split /:/,$resource_line;

    my $module = $self->load_data_module($resource);
    my $data = $module->new({
        hostname => $self->hostname,
        address => $self->address,
        details => $self->details,
        args    => \@args,
        component_config => $self->component_config,
        global_config => $self->global_config,
    });
    CloudForecast::Log->debug("load resource $resource ",
                             join(":", @args), 
                             " ", $self->hostname, "(",$self->address,")" );
    return $data;
}

1;


