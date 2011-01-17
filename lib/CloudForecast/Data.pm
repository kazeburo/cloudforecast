package CloudForecast::Data;

use strict;
use warnings;
use Carp qw//;
use base qw/Class::Data::Inheritable Class::Accessor::Fast/;
use CloudForecast::Gearman;
use CloudForecast::Ledge;
use Data::Section::Simple;
use UNIVERSAL::require;
use Path::Class qw//;
use File::Path qw//;
use URI::Escape qw//;
use HTTP::Date qw//;
use RRDs;

__PACKAGE__->mk_accessors(qw/hostname address details args
                             component_config _component_instance
                             global_config/);
__PACKAGE__->mk_classdata('rrd_schema');
__PACKAGE__->mk_classdata('fetcher_func');
__PACKAGE__->mk_classdata('graph_key_list');
__PACKAGE__->mk_classdata('graph_defs');
__PACKAGE__->mk_classdata('title_func');
__PACKAGE__->mk_classdata('sysinfo_func');

our @EXPORT = qw/rrds fetcher graphs title sysinfo/;

sub import {
    my ($class, $name) = @_;
    my $caller = caller;
    {
        no strict 'refs';
        if ( $name && $name =~ /^-base/ ) {
            if ( ! $caller->isa($class) && $caller ne 'main' ) {
                push @{"$caller\::ISA"}, $class;
            }
            for my $func (@EXPORT) {
                *{"$caller\::$func"} = \&$func;
            }
        }
    }

    strict->import;
    warnings->import;
}

sub rrds {
    my $class = caller;
    my @args = @_;
    return unless @args;

    my $schema = $class->rrd_schema;
    if ( !$schema ) {
        $schema = $class->rrd_schema([]);
    }

    if ( ref $args[0] ) {
        push @$schema, @args;
    }
    else {
        my @args = @_;
        while ( @args ) {
            push @$schema, [ shift(@args), shift(@args) ];
        }
    }
}

sub fetcher(&) {
    my $class = caller;
    Carp::croak("already seted fetcher_func") if $class->fetcher_func;
    $class->fetcher_func(shift);
}

sub graphs {
    my $class = caller;
    my ($key, $title, $template, $callback) = @_;

    my $graph_defs = $class->graph_defs;
    if ( !$graph_defs ) {
        $graph_defs = $class->graph_defs({});
    }
    my $graph_key_list = $class->graph_key_list;
    if ( !$graph_key_list ) {
        $graph_key_list = $class->graph_key_list([]);
    }

    Carp::croak("no key") unless $key;
    Carp::croak("already exists graph: $key") if exists $graph_defs->{$key};
    $title ||= $key;
    $template ||= $key;

    if ( ! ref $template ) {
        my $reader = Data::Section::Simple->new($class);
        my $section = $reader->get_data_section($template);
        $template = $section;
    }
    else {
        $template = $$template;
    }

    Carp::croak("no template found") unless $template;

    $graph_defs->{$key} = {
        title => $title,
        template => $template,
        callback => $callback
    };
    push @$graph_key_list, $key;
    
    1;
}


sub title(&) {
    my $class = caller;
    if ( my $title = $_[0] ) {
        if ( ! ref $title ) {
            $class->title_func(sub{ $title });
        }
        elsif ( ref $title eq "CODE") {
            $class->title_func($title);
        }
        else {
            die "title must be coderef or scalar";
        }
    }
    1;
}

sub sysinfo(&) {
    my $class = caller;
    $class->sysinfo_func(shift);
}


sub new {
    my $class = shift;
    my $args = ref $_[0] ? shift : { @_ };

    Carp::croak 'no graphs, not setup' unless $class->graph_key_list;
    Carp::croak 'no rrd schema, not setup' unless $class->rrd_schema;
    
    Carp::croak "no hostname" unless $args->{hostname};
    Carp::croak "no ip address" unless $args->{address};

    $args->{args} ||= [];
    $args->{component_config} ||= {}; 
    $args->{global_config} ||= {};

    my $self = $class->SUPER::new({
        hostname   => $args->{hostname},
        address    => $args->{address},
        details    => $args->{details},
        args       => $args->{args},
        component_config => $args->{component_config},
        global_config => $args->{global_config},
        _component_instance => {},
    });
    return $self;
}

sub graph_title {
    my $self = shift;
    if ( my $title_func = $self->title_func ) {
        return $title_func->($self) || $self->resource_class;
    }
    return $self->resource_class;
}

sub graph_sysinfo {
    my $self = shift;
    if ( my $sysinfo_func = $self->sysinfo_func ) {
        return $sysinfo_func->($self) || [];
    }
    return [];
}

sub list_graph {
    my $self = shift;
    my $graph_key_list = $self->graph_key_list;
    return @$graph_key_list;
}

sub draw_graph {
    my $self = shift;
    my ($key, $span, $from, $to ) = @_;
    die 'key no defined' unless $key;
    $span ||= 'd';

    my $graph_def = $self->graph_defs->{$key};
    die 'invalid key' unless $graph_def;

    my $period_title;
    my $period;
    my $end = 'now';
    my $xgrid;
    if ( $span eq 'c' ) {
        my $from_time = HTTP::Date::str2time($from);  
        die "invalid from date: $from" unless $from_time;
        my $to_time = $to ? HTTP::Date::str2time($to) : time;
        die "invalid to date: $to" unless $to_time;
        die "from($from) is newer than to($to)" if $from_time > $to_time;

        $period_title = "$from to $to" ;
        $period = $from_time;
        $end = $to_time;
        my $diff = $to_time - $from_time;
        if ( $diff < 3 * 60 * 60 ) {
            $xgrid = 'MINUTE:10:MINUTE:10:MINUTE:10:0:%M';
        }
        elsif ( $diff < 2 * 24 * 60 * 60 ) {
            $xgrid = 'HOUR:1:HOUR:1:HOUR:2:0:%H';
        }
        elsif ( $diff < 14 * 24 * 60 * 60) {
            $xgrid = 'DAY:1:DAY:1:DAY:2:86400:%m/%d';
        }
        elsif ( $diff < 45 * 24 * 60 * 60) {
            $xgrid = 'DAY:1:WEEK:1:WEEK:1:0:%F';
        }
        else {
            $xgrid = 'WEEK:1:MONTH:1:MONTH:1:2592000:%b';
        }
    }
    elsif ( $span eq 'w' ) {
        $period_title = 'Weekly';
        $period = -1 * 60 * 60 * 24 * 8;
        $xgrid = 'DAY:1:DAY:1:DAY:1:86400:%a'
    }
    elsif ( $span eq 'm' ) {
        $period_title = 'Monthly';
        $period = -1 * 60 * 60 * 24 * 35;
        $xgrid = 'DAY:1:WEEK:1:WEEK:1:604800:Week %W'
    }
    elsif ( $span eq 'y' ) {
        $period_title = 'Yearly';
        $period = -1 * 60 * 60 * 24 * 400;
        $xgrid = 'WEEK:1:MONTH:1:MONTH:1:2592000:%b'
    }
    else {
        $period_title = 'Daily';
        $period = -1 * 60 * 60 * 33; # 33 hours
        $xgrid = 'HOUR:1:HOUR:2:HOUR:2:0:%H';
    }
    
    my $template = $graph_def->{template};
    if ( my $callback = $graph_def->{callback} ) {
        $template = $callback->($self, $template); 
        die 'invalid template' unless $template;
    }

    my ($tmpfh, $tmpfile) = File::Temp::tempfile(UNLINK => 0, SUFFIX => ".png");

    my @args = (
        $tmpfile,
        '-w', 400,
        '-a', 'PNG',
        '-t', "$period_title ". $self->address,
        '-l', 0, #minimum
        '-u', 2, #maximum
        '-v', $graph_def->{title},
        '-x', $xgrid,
        '-s', $period,
        '-e', $end,
    );

    my $rrd_path = "".$self->rrd_path;
    for my $line ( split /\n/, $template ) {
        next unless $line;
        next if $line =~ m!^\s*#!;
        next if $line =~ m!^\s+$!;
        $line =~ s!<%RRD%>!$rrd_path!g;
        push @args, $line;
    }

    eval {
        RRDs::graph(@args);
        my $ERR=RRDs::error;
        die $ERR if $ERR;
    };
    if ( $@ ) {
        unlink($tmpfile);
        die "draw graph failed: $@";
    }

    open( my $fh, $tmpfile ) or die "cannot open graph tmpfile: $!";
    my $graph_img = join "", <$fh>;
    unlink($tmpfile);

    die 'something wrong with image' unless $graph_img;

    return $graph_img;
}

sub component {
    my $self = shift;
    my $component = shift;

    my $instance = $self->_component_instance->{$component};
    return $instance if $instance;

    my $module = "CloudForecast::Component::" . $component;
    $module->require or die $@;

    $self->_component_instance->{$component} = $module->_new_instance({
        hostname => $self->hostname,
        address => $self->address,
        details => $self->details,
        args    => $self->args || [],
        config  => $self->component_config->{$component} || {},
    });
    return $self->_component_instance->{$component};
}

sub resource_name {
    my $self = shift;
    my $class = ref($self);
    my $resource_name = $self->resource_class;
    $resource_name =~ s/::/-/g;
    $resource_name = lc( $resource_name );
    return $resource_name;
}

sub resource_class {
    my $self = shift;
    my $class = ref($self);
    my ($class1,$class2,$resource_class) = split /::/, $class, 3;
    return $resource_class;
}

sub rrd_path {
    my $self = shift;

    my $filename = sprintf "%s_%s.rrd",
        URI::Escape::uri_escape( $self->address ),
        join( "-", map { URI::Escape::uri_escape($_) } @{$self->args});
    return Path::Class::file(
        $self->global_config->{data_dir},
        $self->resource_name,
        $filename )->cleanup;
    
}

sub do_fetch {
    my $self = shift;
    my $ret = $self->fetcher_func->($self);
    die 'fetcher result undefind value' unless $ret;
    die 'fetcher result value isnot array ref'
        if ( !ref($ret) || ref($ret) ne 'ARRAY' );
    CloudForecast::Log->debug( 'fetcher result [' . join(",", map { !defined $_ ? 'U' : $_ } @$ret) . ']');

    my $schema = $self->rrd_schema;
    die 'schema and result values is no match' if ( scalar @$ret != scalar @$schema );
    return $ret;
}

sub exec_fetch {
    my $self = shift;
    CloudForecast::Log->debug('fetcher start');
    my $ret;
    eval {
        $ret = $self->do_fetch();
    };
    # alive
    my $err = $@;
    if ( $err && $self->resource_class eq "Basic" ) {
        $self->ledge_set_haserror('crit');
    }
    elsif ( $err ) {
        $self->ledge_set_haserror('warn');
    }
    else {
        $self->ledge_set_haserror('ok');
    }
    die $err if $err;
    $self->call_updater($ret);
}

sub call_fetch {
    my $self = shift;

    if ( $self->global_config->{gearman_enable} ) {
        # gearmanに渡す処理
        CloudForecast::Log->debug('dispath gearman fetcher');
        my $gearman = CloudForecast::Gearman->new({
            host => $self->global_config->{gearman_server}->{host},
            port => $self->global_config->{gearman_server}->{port},
        });
        $gearman->fetcher({
            resource_class => $self->resource_class,
            hostname => $self->hostname,
            address  => $self->address,
            details  => $self->details,
            args     => $self->args,
            component_config => $self->component_config,
        });
    }
    else {
        # 直接実行
        $self->exec_fetch();
    }
}

sub exec_updater {
    my ($self, $ret) = @_;
    CloudForecast::Log->debug('updater start');
    $self->init_rrd();
    $self->update_rrd($ret);
}

sub call_updater {
    my ($self, $ret) = @_;
    if ( $self->global_config->{gearman_enable} ) {
        # gearmanに渡す処理
        CloudForecast::Log->debug('dispath gearman updater');

        my $gearman = CloudForecast::Gearman->new({
            host => $self->global_config->{gearman_server}->{host},
            port => $self->global_config->{gearman_server}->{port},
        });
        $gearman->updater({
            resource_class => $self->resource_class,
            hostname => $self->hostname,
            address  => $self->address,
            details  => $self->details,
            args     => $self->args,
            component_config => $self->component_config,
            result => $ret,
        });
    }
    else {
        # 直接実行
        $self->exec_updater($ret);
    }
}


sub _ledge_address_key {
    my $self = shift;
    my $address = sprintf "%s_%s",
        $self->address,
        join( "-", map { URI::Escape::uri_escape($_) } @{$self->args});
    return $address;
}

sub _ledge {
    my $self = shift;
    my $method = shift;
    my @args = @_;

    $self->_ledge_do(
        $method,
        $self->resource_class,
        $self->_ledge_address_key,
        @args
    );
}

sub _ledge_do {
    my $self = shift;
    my $method = shift;
    my $resource_class = shift;
    my $address = shift;

    ### Webインターフェイスからのアクセスセスは直接DBにアクセス
    if ( !$self->global_config->{__do_web} && $self->global_config->{gearman_enable} ) {
        if ( $method !~ m!^background_! && ! defined wantarray ) {
            $method = 'background_' . $method;
        }
        my $gearman = CloudForecast::Gearman->new({
            host => $self->global_config->{gearman_server}->{host},
            port => $self->global_config->{gearman_server}->{port},
        });
        $gearman->can( 'ledge_' . $method )->( $gearman, $resource_class, $address, @_  );
    }
    else {
        $method =~ s!^background_!!g;
        $self->{_ledge} ||= CloudForecast::Ledge->new({
            data_dir => $self->global_config->{data_dir},
            db_name  => $self->global_config->{db_name}
        });
        $self->{_ledge}->can($method)->( $self->{_ledge}, $resource_class, $address, @_  );
    }
}

sub ledge_add { my $self = shift; $self->_ledge('add', @_ ) }
sub ledge_set { my $self = shift; $self->_ledge('set', @_ ) }
sub ledge_delete { my $self = shift; $self->_ledge('delete', @_ ) }
sub ledge_expire { my $self = shift; $self->_ledge('expire', @_ ) }
sub ledge_background_add { my $self = shift; $self->_ledge('background_add', @_ ) }
sub ledge_background_set { my $self = shift; $self->_ledge('background_set', @_ ) }
sub ledge_background_delete { my $self = shift; $self->_ledge('background_delete', @_ ) }
sub ledge_background_expire { my $self = shift; $self->_ledge('background_expire', @_ ) }

sub ledge_get { my $self = shift; $self->_ledge('get', @_ ) }

sub ledge_set_haserror {
    my $self = shift;
    my $type = shift;
    $self->_ledge_do(
        'background_set',
        '__SYSTEM__',
        $self->address,
        '__has_error__:'.$type,
        1,
        540,
    );
}

sub init_rrd {
    my $self = shift;
    my $file = $self->rrd_path;
    return if -f $file;
    
    #init
    CloudForecast::Log->debug('mkdir:' . $file->dir);
    File::Path::mkpath("".$file->dir);
    my @ds = map { sprintf "DS:%s:%s:600:0:U", $_->[0], $_->[1] } @{$self->rrd_schema};
    
    CloudForecast::Log->debug('create rrd file:' . $file);
    eval {
        RRDs::create(
            $file,
            '--step', '60',
            @ds,
            'RRA:AVERAGE:0.5:5:9216',
            'RRA:AVERAGE:0.5:30:1536',
            'RRA:AVERAGE:0.5:120:768',
            'RRA:AVERAGE:0.5:1440:794',
            'RRA:MAX:0.5:30:1536',
            'RRA:MAX:0.5:120:768',
            'RRA:MAX:0.5:1440:794'
        );
        my $ERR=RRDs::error;
        die $ERR if $ERR;
    };
    die "create rrd failed: $@ " if $@;
}

sub update_rrd {
    my $self = shift;
    my $ret = shift;
    my $file = $self->rrd_path;

    # update
    my $ds = join ":", map { sprintf "%s", $_->[0] } @{$self->rrd_schema};
    my $data= join ":", "N", map { ! defined $_ ? 'U' : $_ } @$ret;
    CloudForecast::Log->debug('update rrd file: '. $file. " -t $ds $data");
    eval {
        RRDs::update(
            $file,
            '-t', $ds,
            $data,
        );
        my $ERR=RRDs::error;
        die $ERR if $ERR;
    };
    die "udpate rrdfile failed: $@" if $@;
}


1;



