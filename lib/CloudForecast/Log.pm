package CloudForecast::Log;

use strict;
use warnings;

sub warn {
    my $class = shift;
    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) =
      localtime(time);
    my $time    = sprintf(
        "%04d-%02d-%02dT%02d:%02d:%02d",
        $year + 1900,
        $mon + 1, $mday, $hour, $min, $sec
    );
    my $warn = ( $_[0] && $_[0] =~ m!^\[[A-Z]+\]\s*$! ) ? '' : '[WARN] '; 
    warn "$time ", $warn, @_, "\n";
}

sub debug {
    my $class = shift;
    return unless $ENV{CF_DEBUG};
    $class->warn('[DEBUG] ',@_);
}

1;

