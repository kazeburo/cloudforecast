use inc::Module::Install;
name 'CloudForecast';
all_from 'lib/CloudForecast.pm';

tests 't/*.t';
author_tests 'xt';

test_requires 'Test::More';

requires 'Class::Data::Inheritable';
requires 'Class::Accessor::Fast';
requires 'Data::Section::Simple';
requires 'UNIVERSAL::require';
requires 'Path::Class';
requires 'URI::Escape';
requires 'Scalar::Util';
requires 'Plack', 0.9937;
requires 'Router::Simple';
requires 'Text::MicroTemplate';
requires 'Gearman::Client', 1.10;
requires 'Gearman::Server';
requires 'Parallel::Prefork', 0.08;
requires 'YAML', 0.71;
requires 'Starlet', 0.08;
requires 'Filesys::Notify::Simple';
#requires 'RRDs'; $ yum install rrdtool-perl

if ( $^O eq 'linux' ) {
    requires 'Linux::Inotify2';
}

requires 'LWP::UserAgent';
#requires 'SNMP'; $ yum install net-snmp-perl
requires 'DBI';

#auto_set_repository;
auto_include;
WriteAll;
