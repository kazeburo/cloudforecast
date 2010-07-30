use strict;
use Test::More tests => 4;
use Test::TCP;
use File::Temp;

use CloudForecast::Data::Memcached;

test_tcp(
        client => sub {
            my $port = shift;
            my $dir = File::Temp::tempdir( CLEANUP => 1 );

            my $resource = CloudForecast::Data::Memcached->new({
                hostname => 'localhost',
                address => '127.0.0.1',
                args => [ $port, "testcached" ],
                global_config => { data_dir => $dir },
            });

            my $ret = $resource->do_fetch();
            is_deeply( $ret, [0,0,0,0,undef,0,67108864] );

            my $sysinfo = $resource->graph_sysinfo();
            my %sysinfo = @$sysinfo;
            ok ( $sysinfo{version} );
            ok ( $sysinfo{uptime} );
            
            my $title = $resource->graph_title();
            is( $title, "testcached ($port)" );

        },
        server => sub {
            my $port = shift;
            exec 'memcached', '-p', $port;
        },
);

