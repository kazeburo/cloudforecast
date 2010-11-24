use inc::Module::Install;
name 'CloudForecast';
all_from 'lib/CloudForecast.pm';

tests 't/*.t';
#author_tests 'xt';

test_requires 'Test::More';

requires 'local::lib';
requires 'Class::Data::Inheritable';
requires 'Class::Accessor::Fast';
requires 'Data::Section::Simple';
requires 'UNIVERSAL::require';
requires 'Path::Class';
requires 'URI::Escape';
requires 'Scalar::Util';
requires 'Plack', 0.9937;
requires 'Net::IP';
requires 'Plack::Middleware::Access';
requires 'Plack::Middleware::ReverseProxy';
requires 'Router::Simple';
requires 'Text::Xslate', 0.1054;
requires 'HTML::FillInForm::Lite', 1.09;
requires 'MRO::Compat';
requires 'Gearman::Client', 1.10;
requires 'Gearman::Server';
requires 'Parallel::Prefork', 0.08;
requires 'YAML::Syck', 1.10;
requires 'JSON', 2.27;
requires 'Starlet', 0.08;
requires 'Filesys::Notify::Simple';
requires 'Proc::Daemon';
requires 'PadWalker';
#requires 'RRDs'; $ yum install rrdtool-perl

if ( $^O eq 'linux' && -d "/proc/sys/fs/inotify" ) {
    requires 'Linux::Inotify2';
}

requires 'LWP::UserAgent';
#requires 'SNMP'; $ yum install net-snmp-perl
requires 'DBI';
requires 'DBD::SQLite', 1.25;

#auto_set_repository;
auto_include;
WriteAll;
