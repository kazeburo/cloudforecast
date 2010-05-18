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
requires 'Plack', 0.9931;
requires 'Router::Simple';
requires 'Text::MicroTemplate';
requires 'Gearman::Client', 1.10;
reuiress 'Gearman::Server';
requries 'Parallel::Prefork';
requires 'YAML', 0.71;
#requires 'RRDs'; $ yum install rrdtool-perl

requires 'LWP::UserAgent';
#requires 'SNMP'; $ yum install net-snmp-perl
requires 'DBI';

#auto_set_repository;
auto_include;
WriteAll;
