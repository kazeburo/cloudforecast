package CloudForecast::Component::Jolokia;

use CloudForecast::Component -adaptor;

use JMX::Jmx4Perl;
use JMX::Jmx4Perl::Request;

adaptor {
    my $class = shift;
    my $args = shift;

    my $address  = $args->{address};
    my $protocol = $args->{args}[0] || 'http';
    my $port     = $args->{args}[1] || 8778;
    my $context  = $args->{args}[2] || '/jolokia';
    my $url      = "${protocol}://${address}:${port}${context}";

    JMX::Jmx4Perl->new(
        url     => $url,
        timeout => 3,
    );
};

1;


