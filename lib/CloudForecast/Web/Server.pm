package CloudForecast::Web::Server;

use strict;
use warnings;
use CloudForecast::Web -base;
use CloudForecast::Host;

sub get_host {
    my ( $self, $host ) = @_;
    my $host_instance = CloudForecast::Host->new({
        address => $host->{address},
        hostname => $host->{hostname},
        details => $host->{details},
        resources => $host->{resources},
        component_config => $host->{component_config},
        global_config => $self->configloader->global_config,
    });
    $host_instance;
}

sub page_title {
    my $self = shift;
    my $page_title = $self->configloader->server_list_yaml;
    $page_title =~ s!^(.+)/!!;
    $page_title =~ s!\.[^.]+$!!;
    $page_title;
}

# shortcut
sub all_hosts {
    my $self = shift;
    $self->configloader->all_hosts;
}

sub server_list {
    my $self = shift;
    $self->configloader->server_list;
}

get '/' => sub {
    my ( $self, $req, $p )  = @_;
    return $self->render('index.mt');
};

get '/server' => sub {
    my ($self, $req, $p ) = @_;

    my $address = $req->param('address');
    return $self->not_found('Address Not Found') unless $address;

    my $host = $self->all_hosts->{$address};
    return $self->not_found('Host Not Found') unless $host;

    my $host_instance = $self->get_host($host);
    my @graph_list = $host_instance->list_graph;

    return $self->render('server.mt');
};


get '/graph' => sub {
    my ($self, $req )  = @_;

    my $address = $req->param('address');
    return $self->not_found('Address Not Found') unless $address;
    my $resource = $req->param('resource');
    return $self->not_found('Resource Not Found') unless $resource;
    my $key = $req->param('key');
    return $self->not_found('Graph type key Not Found') unless $key;

    my $span = $req->param('span') || 'd';
    my $host = $self->all_hosts->{$address};
    return $self->not_found('Host Not Found') unless $host;

    my $host_instance = $self->get_host($host);
    my ($img,$err) = $host_instance->draw_graph($resource,$key, $span);

    return $self->ise($err) unless $img;
    return [ 200, ['Content-Type','image/png'], [$img] ];
};

1;

__DATA__
@@ index.mt
<html>
<head>
<title>CloudForecast Server List</title>
<link rel="stylesheet" type="text/css" href="/static/default.css" />
</head>
<body>
<div id="container">
<div id="header">
<h1 class="title"><a href="/">CloudForecast : <?= $self->page_title ?></a></h1>
<div class="welcome">
<ul>
<li><a href="/">TOP</a></li>
</ul>
</div>
</div>

<div id="grouplist">
<ul>
<? my $i=0 ?>
<? for my $server ( @{$self->server_list} ) { ?>
<li><a href="#group-<?= $i ?>"><?= $server->{title} ?></a></li>
<? $i++ } ?>
</ul>
</div>

<div id="content">

<h2 id="ptitle">SERVER LIST</h2>

<ul id="group-ul">
<? my $k=0 ?>
<? for my $server ( @{$self->server_list} ) { ?>
<li class="group-name" id="group-<?= $k ?>">&gt;&nbsp;<?= $server->{title} ?></li>
<ul class="server-ul">
  <? for my $host ( @{$server->{hosts}} ) { ?>
  <li><a href="/server?address=<?= $host->{address} ?>"><?= $host->{address} ?></a> <strong><?= $host->{hostname} ?></strong> <span class="details"><?= $host->{details} ?></a></li>
  <? } ?>
</ul>
<? $k++ } ?>
</ul>

</div>

</div>
</body>
</html>

@@ server.mt
<html>
<head>
<title>CloudForecast : <?= $self->page_title ?> : <?= $host->{address} ?></title>
<link rel="stylesheet" type="text/css" href="/static/default.css" />
</head>
<body>
<div id="container">
<div id="header">
<h1 class="title"><a href="/">CloudForecast : <?= $self->page_title ?></a></h1>
<div class="welcome">
<ul>
<li><a href="/">TOP</a></li>
</ul>
</div>
</div>

<div id="content">

<h2 id="ptitle"><a href="/server?address=<?= $host->{address} ?>" class="address"><?= $host->{address} ?></a> <strong><?= $host->{hostname} ?></strong> <span class="details"><?= $host->{details} ?></a></h2>

<? for my $resource ( @graph_list ) { ?>
<h4 class="resource-title"><?= $resource->{graph_title} ?></h4>
<div class="resource-graph">
<? for my $graph ( @{$resource->{graphs}} ) { ?>
<div class="ngraph">
<? for my $term ( qw/d w m y/ ) { ?>
<img src="/graph?span=<?= $term ?>&amp;address=<?= $host->{address} ?>&amp;resource=<?= $resource->{resource} ?>&amp;key=<?= $graph ?>" />
<? } ?>
</div>
<? } ?>
</div>
<? } ?>


</div>

</div>
</body>
</html>




