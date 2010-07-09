package CloudForecast::Log;

use strict;
use warnings;
use PadWalker qw//;
use JSON::Syck qw//;

sub warn {
    my $class = shift;
    $class->_log("WARN",@_);
}

sub debug {
    my $class = shift;
    return unless $ENV{CF_DEBUG};
    $class->_log('DEBUG',@_);
}

my $root_dir="";
sub _log {
    my $class = shift;
    my $tag = shift;

    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) =
      localtime(time);
    my $time    = sprintf(
        "%04d-%02d-%02dT%02d:%02d:%02d",
        $year + 1900,
        $mon + 1, $mday, $hour, $min, $sec
    );

    my %info;
    my $h = PadWalker::peek_my(2);
    my @caller = caller(2);
    while (my ($key, $val) = each %$h) {
        if ( ref $val eq 'REF' && ref($$val) =~ m!CloudForecast\:\:ConfigLoader! ) {
            $root_dir = $$val->root_dir;
        }
        if ( ref $val eq 'REF' && ref($$val) =~ m!^CloudForecast\:\:Data\:\:(.+)$! ) {
            $info{ad} = $$val->address;
            $info{h} = $$val->hostname;
            $info{as} = join ":", @{$$val->args};
            $info{c} = "Data::$1";
        }
        elsif ( ref $val eq 'REF' && ref($$val) =~ m!^CloudForecast\:\:Component\:\:(.+)$! ) {
            $info{ad} = $$val->address;
            $info{h} = $$val->hostname;
            $info{as} = join ":", @{$$val->args};
            $info{c} = "Component::$1";
        }
        elsif ( ref $val eq 'REF' && ref($$val) =~ m!^CloudForecast\:\:Host! ) {
            $info{ad} = $$val->address;
            $info{h} = $$val->hostname;
            $info{c} = "Host";
        }
    }
    my $info = ( keys %info ) ? join(",", map { "$_:$info{$_}" } keys %info) . " " : ""; 
    my $file = $caller[1];
    $file =~ s!$root_dir/!!;

    CORE::warn "$time [$tag] $info" . join(" ", @_) . " {$file#$caller[2]}\n";
}

1;

