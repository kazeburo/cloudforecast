package CloudForecast::Web::Request;

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



