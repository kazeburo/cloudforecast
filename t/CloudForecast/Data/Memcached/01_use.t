use strict;
use Test::More tests => 3;

BEGIN { use_ok 'CloudForecast::Data::Memcached' }

my $resource;
eval {
    $resource = CloudForecast::Data::Memcached->new({ hostname => 'dummy', address => 'dummy'  });
};
ok( ! $@ );
isa_ok( $resource, 'CloudForecast::Data::Memcached' );



