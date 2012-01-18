package CloudForecast::Component::LWP;

use CloudForecast::Component -adaptor;
use LWP::UserAgent;

adaptor {
    my $class = shift;
    my $args = shift;
    LWP::UserAgent->new(
        timeout => 10,
        agent   => 'cloudforecastbot'
    );
};

1;


