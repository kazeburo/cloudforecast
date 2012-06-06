use strict;
use Test::More tests => 5;
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

            my $sysinfo = $resource->graph_sysinfo();
            my %sysinfo = @$sysinfo;
            ok ( $sysinfo{version} );
            ok ( $sysinfo{uptime} );

            if ( $sysinfo{version} =~ m!^1\.4! ) {
                is_deeply( $ret, [0,0,0,0,10,0,67108864] );
                ok( $sysinfo{max_connections} );
            }
            else {
                is_deeply( $ret, [0,0,0,0,4,0,67108864] );
                ok( 1 );
            }
                       
            my $title = $resource->graph_title();
            is( $title, "testcached ($port)" );

        },
        server => sub {
            my $port = shift;
            exec 'memcached', '-p', $port;
        },
);

