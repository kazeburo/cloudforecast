package CloudForecast::Web;

use strict;
use warnings;
use Carp qw//;
use Scalar::Util qw/refaddr/;
use Plack::Runner;
use Plack::Request;
use Plack::Response;
use Router::Simple;
use Text::MicroTemplate;
use Data::Section::Simple;

my $_ROUTER;
my %CACHE;
our $KEY;
our $DATA_SECTION_LEVEL = 0;

our @EXPORT = qw/get post any render run_server/;

sub import {
    my ($class, $name) = @_;
    my $caller = caller;
    {
        no strict 'refs';
        if ( $name && $name =~ /^-base/ ) {

            $_ROUTER = Router::Simple->new();

            for my $func (@EXPORT) {
                *{"$caller\::$func"} = \&$func;
            }
        }
    }

    strict->import;
    warnings->import;
}

sub psgify (&) {
    my $code = shift;
    sub {
        my $env = shift;
        my $req = Plack::Request->new($env);
        my $p = delete $env->{'cloudforecast-web.args'};
        my $res = $code->($req, $p);
        my $res_t = ref $res || '';
        if ( $res_t eq 'Plack::Response' ) {
            return $res->finalize;
        }
        elsif ( $res_t eq 'ARRAY' ) {
            return $res;
        }
        elsif ( !$res_t ) {
            return [ 200, [ 'Content-Type' => 'text/html; charset=utf-8'], [ $res ] ];
        }
        else {
            Carp::croak("unknown response type: $res, $res_t");
        }
    };
}

sub router_to_app {
    my $router = shift;
    sub {
        if ( my $p = $router->match($_[0]) ) {
            my $code = delete $p->{action};
            return [ 500, [], ['Internal Server Error'] ] unless $code; 
            $_[0]->{'cloudforecast-web.args'} = $p;
            return $code->(@_)
        }
        else {
            return [ 404, [ 'Content-Type' => 'text/html; charset=utf-8' ], ['not found'] ];
        }
    }
}

sub run_server {
    my $runner = Plack::Runner->new;
    $runner->parse_options(@_);

    my $router_app = router_to_app($_ROUTER);
    my $app = sub {
        local $KEY = refaddr $router_app;
        $router_app->(@_);
    };

    $runner->run($app);
}


sub any($$;$) {
    if ( @_ == 3 ) {
        my ( $methods, $pattern, $code ) = @_;
        $_ROUTER->connect(
            $pattern,
            { action => psgify { goto $code } },
            { method => [ map { uc $_ } @$methods ] } 
        );        
    }
    else {
        my ( $pattern, $code ) = @_;
        $_ROUTER->connect(
            $pattern,
            { action => psgify { goto $code } }
        );
    }
}

sub get {
    any( ['GET','HEAD'], $_[0], $_[1]  );
}

sub post {
    any( ['POST'], $_[0], $_[1]  );
}

sub get_data_section {
    my $pkg = caller($DATA_SECTION_LEVEL);
    my $data = $CACHE{$KEY}->{__data_section} ||= Data::Section::Simple->new($pkg)->get_data_section;
    return @_ ? $data->{$_[0]} : $data;
}

sub render {
    my ( $key, @args ) = @_;
    my $code = $CACHE{$KEY}->{$key} ||= do {
        local $DATA_SECTION_LEVEL = $DATA_SECTION_LEVEL + 1;
        my $tmpl = get_data_section($key);
        Carp::croak("unknown template file:$key") unless $tmpl;
        Text::MicroTemplate->new(template => $tmpl, package_name => 'main')->code();
    };

    package DB;
    local *DB::render = sub {
        my $coderef = (eval $code); ## no critic
        die "Cannot compile template '$key': $@" if $@;
        $coderef->(@args);
    };
    goto &DB::render;
}

1;


