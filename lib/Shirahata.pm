package Shirahata;

use strict;
use warnings;
use MRO::Compat;
use mro;

use Carp qw//;
use Scalar::Util qw/blessed/;
use Plack::Util::Accessor;
use Router::Simple;

use Text::Xslate;
use Data::Section::Simple;
use HTML::FillInForm::Lite qw//;

sub import {
    my ($class, $name) = @_;
    my $caller = caller;
    {
        no strict 'refs';
        if ( $name && $name =~ /^-base/ ) {
            if ( ! $caller->isa($class) && $caller ne 'main' ) {
                push @{"$caller\::ISA"}, $class;
            }
        }
        if ( $name && $name =~ /^-(?:base|import)/ ) {
            for my $func ( qw/get post any accessor/ ) {
                *{"$caller\::$func"} = \&$func;
            }
        }
        
    }
    strict->import;
    warnings->import;
}

sub accessor {
    my $class = caller;
    Plack::Util::Accessor::mk_accessors( $class, @_ );
}

sub new {
    my $class = shift;
    my %args = ( @_ && ref $_[0] ) ? %{$_[0]} : @_;
    bless \%args, $class;
}

sub psgi {
    my $self = shift;
    if ( ! ref $self ) {
        $self = $self->new( @_ );    
    }

    my $app = $self->build_app;
    $app;
}

sub build_app {
    my $self = shift;

    my @inheri;
    for my $parent ( @{mro::get_linear_isa(ref $self)} ) {
        next if ! $parent->can('build_app');
        next if $parent eq __PACKAGE__;
        push @inheri, $parent;
    } 

    #router
    my $router = Router::Simple->new;
    for my $parent ( @inheri ) {      
        $router->connect(@{$_}) for @{$parent->router};
    }

    #template
    my %templates;
    for my $parent ( @inheri ) {
        my $reader = Data::Section::Simple->new($parent);
        my $template_hashref = $reader->get_data_section;
        next if ! $template_hashref;
        %templates = ( %$template_hashref, %templates );
    }

    #xslate
    my $fif = HTML::FillInForm::Lite->new(layer => ':raw');
    my $tx = Text::Xslate->new(
        path => [ \%templates ],
        cache => 0,
        input_layer => '',
        function => {
            fillinform => sub {
                my $q = shift;
                return sub {
                    my ($html) = @_;
                    return Text::Xslate::mark_raw( $fif->fill( \$html, $q ) );
                }
            }
        },
    );

    sub {
        my $env = shift;
        my $psgi_res;

        my $s_req = Shirahata::Request->new($env);
        my $s_res = Shirahata::Response->new(200);
        $s_res->content_type('text/html; charset=UTF-8');

        my $c = Shirahata::Connection->new({
            tx => $tx,
            req => $s_req,
            res => $s_res,
            stash => {},
        });

        if ( my $p = $router->match($env) ) {
            my $code = delete $p->{action};
            return $self->ise('uri match but no action found') unless $code;

            $c->args($p);

            my $res = $code->($self, $c );
            Carp::croak( "undefined response") if ! defined $res;

            my $res_t = ref($res) || '';
            if ( blessed $res && $res->isa('Plack::Response') ) {
                $psgi_res = $res->finalize;
            }
            elsif ( $res_t eq 'ARRAY' ) {
                $psgi_res = $res;
            }
            elsif ( !$res_t ) {
                $s_res->body($res);
                $psgi_res = $s_res->finalize;
            }
            else {
                Carp::croak("unknown response type: $res, $res_t");
            }
        }
        else {
            # router not match
            $psgi_res = $c->res->not_found()->finalize;
        }

        $psgi_res;
    };
}

my $_ROUTER={};
sub router {
    my $klass = shift;
    my $class = ref $klass ? ref $klass : $klass; 
    if ( !$_ROUTER->{$class} ) {
        $_ROUTER->{$class} = [];
    }    
    if ( @_ ) {
        push @{ $_ROUTER->{$class} }, [@_];
    }
    $_ROUTER->{$class};
}

sub _any($$$;$) {
    my $class = shift;
    if ( @_ == 3 ) {
        my ( $methods, $pattern, $code ) = @_;
        $class->router(
            $pattern,
            { action => $code },
            { method => [ map { uc $_ } @$methods ] } 
        );        
    }
    else {
        my ( $pattern, $code ) = @_;
        $class->router(
            $pattern,
            { action => $code }
        );
    }
}

sub any {
    my $class = caller;
    $class->_any( @_ );
}

sub get {
    my $class = caller;
    $class->_any( ['GET','HEAD'], $_[0], $_[1]  );
}

sub post {
    my $class = caller;
    $class->_any( ['POST'], $_[0], $_[1]  );
}

1;


package Shirahata::Connection;

use strict;
use warnings;
use base qw/Class::Accessor::Fast/;

__PACKAGE__->mk_accessors(qw/req res stash args tx/);

*request = \&req;
*response = \&res;

sub render {
    my $self = shift;
    my $file = shift;
    my %args = ( @_ && ref $_[0] ) ? %{$_[0]} : @_;
    my %vars = (
        c => $self,
        stash => $self->stash,
        %args,
    );

    my $body = $self->tx->render($file, \%vars);
    $self->res->status( 200 );
    $self->res->content_type('text/html; charset=UTF-8');
    $self->res->body( $body );
    $self->res;
}

1;

package Shirahata::Request;

use strict;
use warnings;
use base qw/Plack::Request/;

sub uri_for {
     my($self, $path, $args) = @_;
     my $uri = $self->base;
     $uri->path($path);
     $uri->query_form(@$args) if $args;
     $uri;
}

1;

package Shirahata::Response;

use strict;
use warnings;
use base qw/Plack::Response/;

sub redirect {
    my $self = shift;
    if ( @_ ) {
        $self->SUPER::redirect(@_);
        return $self;
    }
    $self->SUPER::redirect();
}

sub server_error {
    my $self = shift;
    my $error = shift;
    $self->status( 500 );
    $self->content_type('text/html; charset=UTF-8');
    $self->body( $error || 'Internal Server Error' );
    $self;
}

sub not_found {
    my $self = shift;
    my $error = shift;
    $self->status( 500 );
    $self->content_type('text/html; charset=UTF-8');
    $self->body( $error || 'Not Found' );
    $self;
}



1;


