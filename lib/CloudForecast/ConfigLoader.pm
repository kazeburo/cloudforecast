package CloudForecast::ConfigLoader;

use strict;
use warnings;
use base qw/Class::Accessor::Fast/;
use Path::Class qw//;
use YAML::Syck qw//;
use Cwd;
use Filesys::Notify::Simple;
use Digest::MD5 qw//;
use CloudForecast::Log;

__PACKAGE__->mk_accessors(qw/root_dir global_config_yaml server_list_yaml 
                           global_config global_component_config server_list
                           all_hosts host_config_cache/);

sub new {
    my $class = shift;
    my $args = shift;
    bless { 
        root_dir => $args->{root_dir},
        global_config_yaml => $args->{global_config},
        server_list_yaml => $args->{server_list},
        global_config => {},
        global_component_config => {},
        server_list => [],
        all_hosts => [],
        host_config_cache => {},
    }, $class;
}

sub load_all {
    my $self = shift;
    $self->load_global_config();
    $self->load_server_list();
}

sub load_yaml {
    my $self = shift;
    my $file = shift;

    my @data;
    eval {
        if ( ref $file ) {
            @data = YAML::Syck::Load($$file);
        }
        else {
            @data = YAML::Syck::LoadFile($file);
        }
        die "no yaml data in $file" unless @data;
    };
    die "cannot parse $file: $@" if $@;

    return wantarray ? @data : $data[0];
}

sub load_global_config {
    my $self = shift;

    my $config = $self->load_yaml(
        $self->global_config_yaml
    );

    $self->global_component_config( $config->{component_config} || {} );
    $self->global_config( $config->{config} || {} );


    my $host_config_dir = $self->global_config->{host_config_dir} || 'host_config';
    if ( $host_config_dir !~ m!^/! ) {
        $self->global_config->{host_config_dir} = Path::Class::dir(
            $self->root_dir,
            $host_config_dir );
    }

    my $data_dir = $self->global_config->{data_dir};
    die 'data_dir isnot defined in config' unless $data_dir; 
    if ( $data_dir !~ m!^/! ) {
        $self->global_config->{data_dir} = Path::Class::dir(
            $self->root_dir,
            $data_dir );
    }
    CloudForecast::Log->debug( "Load global_config done: " . $self->global_config_yaml );
}

sub load_server_list {
    my $self = shift;

    # load global config first
    if ( !$self->global_config ) {
        $self->load_global_config();
    }

    my $file = $self->server_list_yaml;
    open( my $fh, $file ) or die "cannot open $file: $!";
    my @group_titles;
    my %group_titles;
    my $data="";
    while ( my $line = <$fh> ) {
        if ( $line =~ m!^---\s+#(.+)$! ) {
            $data .= "---\n";
            die "duplicated group keyword: $1" if exists $group_titles{$1};
            push @group_titles, $1;
            $group_titles{$1}=1;
        }
        else {
            $data .= $line;
        }
    }

    my @groups = $self->load_yaml( \$data );
    die 'number of titles and groups not match' 
        if scalar @groups != scalar @group_titles;

    my @hosts_by_group;
    my %all_hosts;
    my $i=0;
    my $sub_config_group_num=0;
    foreach my $group ( @groups ) {

        my @sub_groups;
        my %sub_group_label;
        my $server_count=0;
        foreach my $sub_group ( @{$group->{servers}} ) {

            my $host_config = $sub_group->{config}
                or die "cannot find config in $group_titles[$i] (# $server_count)";
            $server_count++;

            my $hosts = $sub_group->{hosts} || [];
            if ( $sub_group->{label} ) {
                die "duplicated label found in $group_titles[$i] : $sub_group->{label}"
                    if exists $sub_group_label{$sub_group->{label}};
                $sub_group_label{$sub_group->{label}}=1;
            }
            my @sub_group_hosts;
            for my $host_line ( @$hosts ) {
                my $host = $self->parse_host( $host_line, $host_config );
                $host->{config_group_num}=$sub_config_group_num;
                push @sub_group_hosts, $host;
                $all_hosts{$host->{address}} = $host;
                $sub_config_group_num++;
            }
            
            if ( @sub_groups && ! $sub_group->{label} ) {
                push @{$sub_groups[-1]->{hosts}}, @sub_group_hosts;
                next;
            }

            my $label = $sub_group->{label} ? $sub_group->{label} : Digest::MD5::md5_hex($$ . $sub_group . rand(1000) );
            push @sub_groups, {
                label => $sub_group->{label} || '',
                label_key => substr(Digest::MD5::md5_hex( $group_titles[$i] . '\0' . $label),0,12),
                hosts => \@sub_group_hosts,
            };
        }

        push @hosts_by_group, {
            title => $group_titles[$i],
            title_key => substr(Digest::MD5::md5_hex($group_titles[$i]),0,12),
            sub_groups => \@sub_groups,
        };
        $i++;
    }

    $self->server_list( \@hosts_by_group );
    $self->all_hosts( \%all_hosts );
    CloudForecast::Log->debug( "Load server list done: $file");
}

sub load_host_config {
    my $self = shift;
    my $file = shift;
    my $host_config_cache = $self->host_config_cache;
    return $host_config_cache->{$file} 
        if $host_config_cache->{$file};

    my $config = $self->load_yaml(
        Path::Class::file( $self->global_config->{host_config_dir},
                          $file
                      )->stringify );
    $config ||= {};
    $config->{resources} ||= [];
    $config->{component_config} ||= {};

    my $global_config = $self->global_component_config;

    for my $component ( keys %{$global_config} ) {
        my $component_config = $config->{component_config}->{$component} || {};
        my %merge = ( %{$global_config->{$component}}, %{ $component_config } );
        $config->{component_config}->{$component} = \%merge;
    }

    $host_config_cache->{$file} = $config;
    return $config;
}

sub parse_host {
    my $self = shift;
    my $line = shift;
    my $config_yaml = shift;

    my ( $address, $hostname, $details )  = split /\s+/, $line, 3;
    die "no address" unless $address;
    $hostname ||= $address;
    $details ||= "";

    my $config = $self->load_host_config( $config_yaml );

    return {
        address => $address,
        hostname => $hostname,
        details => $details,
        component_config => $config->{component_config},
        resources => $config->{resources}
    };
}


sub watchdog {
    my $self = shift;
    my $parent_pid = $$;

    my $root_dir = $self->root_dir;
    die "root_dir is undefined" unless $root_dir;
    my @path;
    push @path, "$root_dir/lib", "$root_dir/site-lib";
    my $program_name = Cwd::realpath($0);
    push @path, $program_name if -f $program_name;
    push @path, $self->global_config_yaml if $self->global_config_yaml;
    push @path, $self->server_list_yaml if $self->server_list_yaml;
    push @path, $self->global_config->{host_config_dir}
        if $self->global_config->{host_config_dir};

    my $pid = fork();
    die "failed fork: $!" unless defined $pid;
    return $pid if($pid); # main process

    $0 = "$0 (restarter)";
    my $watcher = Filesys::Notify::Simple->new(\@path);
    while (1) {
        $watcher->wait( sub {
            my @path = grep { $_ !~ m![/\\][\._]|\.bak$|~$!  } map { $_->{path} } @_;
            return if ! @path;
            CloudForecast::Log->warn( "File updates: " . join(",", @path) );
            sleep 1;
            kill 'TERM', $parent_pid;
        } );
    }
}

1;



