use strict;
use Test::More qw/no_plan/;

use CloudForecast::Ledge;
use File::Temp qw//;

my $dir = File::Temp::tempdir( CLEANUP => 1 );

my $ledge = CloudForecast::Ledge->new( data_dir => $dir );
ok( $ledge );

{
    my $ret =  $ledge->set('resource1','address1','key1', { val => 'val1' } );
    is( $ret, 1 );
    my ($data, $sum) = $ledge->get('resource1','address1', 'key1');
    is_deeply( $data, { val => 'val1'} );
    ok( $sum );

    $ret = $ledge->set('resource1', 'address1', 'key1', { val => 'val2'}, 0, "blah" );
    ok( !$ret );

    $ret = $ledge->set('resource1', 'address1', 'key1', { val => 'val2'}, 0, $sum );
    ok( $ret );

    ($data, $sum) = $ledge->get('resource1','address1', 'key1');
    is_deeply( $data, { val => 'val2'} );

    $ret = $ledge->delete('resource1','address1', 'key1');
    ok( $ret );
    ($data, $sum) = $ledge->get('resource1','address1', 'key1');
    ok( !$data );
    ok( !$sum );
}


{
    my $ret =  $ledge->add('resource2','address2','key2', 'val2' );
    is( $ret, 1 );
    $ret =  $ledge->add('resource3','address3','key3', 'val3' );
    is( $ret, 1 );
   
    $ret =  $ledge->add('resource2','address2','key2', 'val3' );
    ok( !$ret );

    $ret = $ledge->delete('resource2','address2', 'key2');
    ok( $ret );
    my $ret =  $ledge->add('resource2','address2','key2', 'val2-1' );
    is( $ret, 1 );
    my ($data, $sum) = $ledge->get('resource2','address2', 'key2');
    is ( $data, 'val2-1' );

    $ret =  $ledge->set('resource3','address3','key3', 'val3-1' );
    is( $ret, 1 );
    my ($data, $sum) = $ledge->get('resource3','address3', 'key3');
    is ( $data, 'val3-1' );
}

{
    my $ret =  $ledge->add('resource4','address4','key4', 'val4', 2 );
    ok( $ret );
    my ($data, $sum) = $ledge->get('resource4','address4', 'key4');
    is ( $data, 'val4' );

    sleep 3;
    ($data, $sum) = $ledge->get('resource4','address4', 'key4');
    ok( !$data );
    ok( !$sum );
}
