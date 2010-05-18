package CloudForecast::Component;

use strict;
use warnings;
use Carp qw//;
use base qw/Class::Accessor::Fast/;

__PACKAGE__->mk_accessors(qw/hostname address details args config/);

sub import {
    my ( $class, $name ) = @_;
    my $caller = caller;
    {
        no strict 'refs';
        if ( $name && $name =~ /^-adaptor/ ) {
            # build only component
            *{"$caller\::adaptor"} = \&adaptor;
        }
        elsif ( $name && $name =~ /^-connector/ ) {
            # build and instance component
            for my $name ( qw/hostname address details args config/ ) {
                *{"$caller\::$name"} = \&$name;
            }
            *{"$caller\::new"} = sub {
                my $proto = shift;
                my $fields = shift;
                $fields = {} unless defined $fields;
                bless {%$fields}, $proto;
            };
            *{"$caller\::_new_instance"} = sub {
                my $proto = shift;
                $proto->new(@_);
            };
        }
    }

    strict->import;
    warnings->import;
}

sub adaptor(&) {
    my $class = caller;
    my $function = shift;
    no strict 'refs';
    *{"$class\::_new_instance"} = sub {
        $function->(@_)
    }; 
}



1;


