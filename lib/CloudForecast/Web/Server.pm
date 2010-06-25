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
    my $daterange;
    my $address = $req->param('address');
    return $self->not_found('Address Not Found') unless $address;

    my $host = $self->all_hosts->{$address};
    return $self->not_found('Host Not Found') unless $host;

    my $host_instance = $self->get_host($host);
    my @graph_list = $host_instance->list_graph;

    if ( $req->param('mode') && $req->param('mode') eq 'range' ) {
        $daterange = 1;
    }
    my @today = localtime;
    my $today =  sprintf("%04d-%02d-%02d 00:00:00", $today[5]+1900, $today[4]+1, $today[3]);
    my @yesterday = localtime( time - 24* 60 * 60 );
    my $yesterday = sprintf("%04d-%02d-%02d 00:00:00", $yesterday[5]+1900, $yesterday[4]+1, $yesterday[3]);
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
    my ($img,$err) = $host_instance->draw_graph($resource,$key, $span,
        $req->param('from_date'), $req->param('to_date') );

    return $self->ise($err) unless $img;
    return [ 200, ['Content-Type','image/png'], [$img] ];
};

1;

__DATA__
@@ index.mt
<html>
<head>
<title> SERVER LIST : <?= $self->page_title ?> : CloudForecast</title>
<link rel="stylesheet" type="text/css" href="<?= $req->uri_for('/static/default.css') ?>" />
<link type="text/css" href="<?= $req->uri_for('/static/css/ui-lightness/jquery-ui-1.8.2.custom.css') ?>" rel="stylesheet" />
</head>
<body>
<div id="container">
<div id="header">
<h1 class="title"><a href="<?= $req->uri_for('/') ?>">CloudForecast : <?= $self->page_title ?></a></h1>
<div class="welcome">
<ul>
<li><a href="<?= $req->uri_for('/') ?>">TOP</a></li>
</ul>
</div>
</div>

<div id="grouplist">
<ul>
<? for my $group ( @{$self->server_list} ) { ?>
<li><a href="#group-<?= $group->{title_key} ?>"><?= $group->{title} ?></a></li>
<? } ?>
</ul>
</div>

<div id="content">

<h2 id="ptitle">SERVER LIST</h2>

<ul id="serverlist-ul">
<? for my $group ( @{$self->server_list} ) { ?>
<li class="group-name" id="group-<?= $group->{title_key} ?>"><span class="ui-icon ui-icon-triangle-1-s" style="float:left"></span><?= $group->{title} ?></li>
<ul class="group-ul" id="ul-group-<?= $group->{title_key} ?>">
<? for my $sub_group ( @{$group->{sub_groups}} ) { ?>
<? if ( $sub_group->{label} ) { ?><li id="sub-group-<?= $sub_group->{label_key} ?>" class="sub-group-name"><span class="ui-icon ui-icon-triangle-1-s" style="float:left"></span><?= $sub_group->{label} ?></li><? } ?>
<ul class="host-ul" id="ul-sub-group-<?= $sub_group->{label_key} ?>">
<? for my $host ( @{$sub_group->{hosts}} ) { ?>
<li><a href="<?= $req->uri_for('/server',[address => $host->{address} ]) ?>"><?= $host->{address} ?></a> <strong><?= $host->{hostname} ?></strong> <span class="details"><?= $host->{details} ?></li>
<? } ?>
</ul>
<? } ?>
</ul>
<? } ?>
</ul>

</div>

</div>
<script src="<?= $req->uri_for('/static/js/jquery-1.4.2.min.js') ?>" type="text/javascript"></script>
<script src="<?= $req->uri_for('/static/js/jquery-ui-1.8.2.custom.min.js') ?>" type="text/javascript"></script>
<script src="<?= $req->uri_for('/static/js/jstorage.js') ?>" type="text/javascript"></script>
<script type="text/javascript">
$(function() {
    $("li.group-name").click(function(){
        var li_group = this;
        $("#ul-" + li_group.id).toggle(100, function(){
            $(li_group).toggleClass('group-name-off');
            $(li_group).children().first().toggleClass('ui-icon-triangle-1-s','ui-icon-triangle-1-e');
            $(li_group).children().first().toggleClass('ui-icon-triangle-1-e','ui-icon-triangle-1-s');
            $.jStorage.set( "display-" + li_group.id, $(this).css('display') );   
        } );
    });
    $("li.sub-group-name").click(function(){
        var li_sub_group = this;
        $("#ul-" + li_sub_group.id).toggle(010, function(){
            $(li_sub_group).toggleClass('group-name-off');
            $(li_sub_group).children().first().toggleClass('ui-icon-triangle-1-s','ui-icon-triangle-1-e');
            $(li_sub_group).children().first().toggleClass('ui-icon-triangle-1-e','ui-icon-triangle-1-s');
            $.jStorage.set( "display-" + li_sub_group.id, $(this).css('display') );
        });
    });
    
    $("li.group-name, li.sub-group-name").map(function(){
        var li_group = this;
        var disp = $.jStorage.get( "display-" + this.id );
        if ( disp == 'none' ) {
            $("#ul-" + li_group.id).hide();
            $(li_group).toggleClass('group-name-off');
            $(li_group).children().first().removeClass('ui-icon-triangle-1-s');
            $(li_group).children().first().addClass('ui-icon-triangle-1-e');
        }
    });
})
</script>
</body>
</html>

@@ server.mt
<html>
<head>
<title><?= $host->{hostname} ?> <?= $host->{address} ?> : <?= $self->page_title ?> : CloudForecast</title>
<link rel="stylesheet" type="text/css" href="<?= $req->uri_for('/static/default.css') ?>" />
<link type="text/css" href="<?= $req->uri_for('/static/css/ui-lightness/jquery-ui-1.8.2.custom.css') ?>" rel="stylesheet" />
<link rel="stylesheet" type="text/css" href="<?= $req->uri_for('/static/css/anytimec.css') ?>" />
</head>
<body>
<div id="container">
<div id="header">
<h1 class="title"><a href="<?= $req->uri_for('/') ?>">CloudForecast : <?= $self->page_title ?></a></h1>
<div class="welcome">
<ul>
<li><a href="<?= $req->uri_for('/') ?>">TOP</a></li>
</ul>
</div>
</div>

<div id="content">

<h2 id="ptitle"><a href="<? $req->uri_for('/server', [address => $host->{address}]) ?>" class="address"><?= $host->{address} ?></a> <strong><?= $host->{hostname} ?></strong> <span class="details"><?= $host->{details} ?></h2>

<div id="display-control">
<form id="pickdate" method="get" action="<?= $req->uri_for('/server') ?>">
<? if ( $daterange ) { ?>
<a href="<?= $req->uri_for('/server', [ address => $host->{address} ]) ?>">Disply Latest Graph</a>
<? } else { ?>
<a href="<?= $req->uri_for('/server', [ address => $host->{address}, displaymy => $req->param('displaymy') ? 0 : 1 ]) ?>"><?= $req->param('displaymy') ? 'Hide' : 'Show' ?>  Monthly Graph</a>
<? } ?>
|
Date Range:
<label for="from_date">From</label>
<input type="text" id="from_date" name="from_date" value="<?= $req->param('from_date') || $yesterday ?>" size="21" />
<label for="to_date">To</label>
<input type="text" id="to_date" name="to_date" value="<?= $req->param('to_date') || $req->param('from_date') || $today ?>" size="21" />
<input type="hidden" name="address" value="<?= $host->{address} ?>" />
<input type="hidden" name="mode" value="range" />
<span>ex: 2004-05-23 12:00:00</span>
<input type="submit" id="pickdate_submit" value="Display">
</form>
</div>

<? for my $resource ( @graph_list ) { ?>
<h4 class="resource-title"><?= $resource->{graph_title} ?></h4>
<div class="resource-graph">
<? for my $graph ( @{$resource->{graphs}} ) { ?>
<div class="ngraph">
<? if ( $daterange ) { ?>
<img src="<?= $req->uri_for('/graph', [span => 'c', from_date => $req->param('from_date'), to_date => $req->param('to_date'), address => $host->{address}, resource => $resource->{resource}, key => $graph]) ?>" />
<? } else { ?>
<? for my $term ( $req->param('displaymy') ? qw/d w m y/ : qw/d w/) { ?>
<img src="<?= $req->uri_for('/graph', [span => $term, address => $host->{address}, resource => $resource->{resource}, key => $graph]) ?>" />
<? } ?>
<? } ?>
</div>
<? } ?>
</div>
<? } ?>

</div>

</div>
<script src="<?= $req->uri_for('/static/js/jquery-1.4.2.min.js') ?>" type="text/javascript"></script>
<script src="<?= $req->uri_for('/static/js/jquery-ui-1.8.2.custom.min.js') ?>" type="text/javascript"></script>
<script src="<?= $req->uri_for('/static/js/anytimec.js') ?>" type="text/javascript"></script>
<script type="text/javascript">
$(function() {
     $("#from_date").AnyTime_picker( { format: "%Y-%m-%d %H:00:00",
                                       monthAbbreviations: ['01','02','03','04','05','06','07','08','09','10','11','12'] });
     $("#to_date").AnyTime_picker( { format: "%Y-%m-%d %H:00:00",
                                    monthAbbreviations: ['01','02','03','04','05','06','07','08','09','10','11','12'] });
});
</script>
</body>
</html>




