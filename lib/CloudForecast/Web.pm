package CloudForecast::Web;

use strict;
use warnings;
use Shirahata -base;
use CloudForecast::Host;
use CloudForecast::ConfigLoader;
use List::Util;
use Plack::Builder;
use Plack::Loader;
use Net::IP;
use Path::Class;

accessor(qw/configloader root_dir global_config server_list restarter port host allowfrom front_proxy/);

sub run {
    my $self = shift;

    my $configloader = CloudForecast::ConfigLoader->new({
        root_dir => $self->root_dir,
        global_config => $self->global_config,
        server_list => $self->server_list,
    });
    $configloader->load_all();
    # Webインターフェイス経由であることのマーク
    $configloader->global_config->{__do_web} = 1;

    $self->configloader($configloader);

    my $allowfrom = $self->allowfrom || [];
    my $front_proxy = $self->front_proxy || [];

    my @frontproxies;
    foreach my $ip ( @$front_proxy ) {
        my $netip = Net::IP->new($ip)
            or die "not supported type of rule argument [$ip] or bad ip: " . Net::IP::Error();
        push @frontproxies, $netip;
    }

    my $app = $self->psgi;
    $app = builder {
        enable 'Plack::Middleware::Lint';
        enable 'Plack::Middleware::StackTrace';
        if ( @frontproxies ) {
            enable_if {
                my $addr = $_[0]->{REMOTE_ADDR};
                my $netip;
                if ( defined $addr && ($netip = Net::IP->new($addr)) ) {
                    for my $proxy ( @frontproxies ) {
                       my $overlaps = $proxy->overlaps($netip);
                       if ( $overlaps == $IP_B_IN_A_OVERLAP || $overlaps == $IP_IDENTICAL ) {
                           return 1;
                       } 
                    }
                }
                return;
            } "Plack::Middleware::ReverseProxy";
        }
        if ( @$allowfrom ) {
            my @rule;
            for ( @$allowfrom ) {
                push @rule, 'allow', $_;
            }
            push @rule, 'deny', 'all';
            enable 'Plack::Middleware::Access', rules => \@rule;
        }
        enable 'Plack::Middleware::Static',
            path => qr{^/(favicon\.ico$|static/)},
            root =>Path::Class::dir($self->root_dir, 'htdocs')->stringify;
        $app;
    };

    my $loader = Plack::Loader->load(
        'Starlet',
        port => $self->port || 5000,
        host => $self->host || 0,
        max_workers => 2,
    );

    my @watchdog_pid;
    if ( $self->restarter ) {
        CloudForecast::Log->debug("restarter start");
        push @watchdog_pid, $self->configloader->watchdog;
    }

    $loader->run($app);

    for my $pid ( @watchdog_pid ) {
        kill 'TERM', $pid;
        waitpid( $pid, 0 );
    }
}

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


get '/' => sub {
    my ( $self, $c ) = @_;
    
    $c->render(
        'index',
        server_list => $self->configloader->server_list
    );
};

get '/group' => sub {
    my ( $self, $c ) = @_;
    return $c->res->not_found('ID Not Exists') unless $c->req->param('id');
    my $group = List::Util::first { $_->{title_key} eq $c->req->param('id') }
        @{$self->configloader->server_list};
    return $c->res->not_found('Group Not Found') unless $group;

    return $c->render(
        'group',
        server_list => $self->configloader->server_list,
        group => $group
    );
};

get '/server' => sub {
    my ( $self, $c ) = @_;
    my $daterange;

    my $address = $c->req->param('address');
    return $c->res->not_found('Address Not Exists') unless $address;

    my $host = $self->configloader->all_hosts->{$address};
    return $c->res->not_found('Host Not Found') unless $host;

    my $group_title;
    my $group_key;
    SEARCH_GROUP: for my $main_group ( @{$self->configloader->server_list} ) {
        for my $sub_group ( @{$main_group->{sub_groups}} ) {
            for my $group_host ( @{$sub_group->{hosts}} ) {
                if ( $group_host->{address} eq $address ) {
                    $group_title = $main_group->{title};
                    $group_key   = $main_group->{title_key};
                    last SEARCH_GROUP;
                }
            }
        }
    }

    my $host_instance = $self->get_host($host);
    my @graph_list = $host_instance->list_graph;

    if ( $c->req->param('mode') && $c->req->param('mode') eq 'range' ) {
        $daterange = 1;
    }
    my @today = localtime;
    my $today =  sprintf("%04d-%02d-%02d 00:00:00", $today[5]+1900, $today[4]+1, $today[3]);
    my @yesterday = localtime( time - 24* 60 * 60 );
    my $yesterday = sprintf("%04d-%02d-%02d 00:00:00", $yesterday[5]+1900, $yesterday[4]+1, $yesterday[3]);

    return $c->render(
        'server',
        host => $host,
        group_title => $group_title,
        group_key   => $group_key,
        graph_list => \@graph_list,
        daterange => $daterange,
        today => $today,
        yesterday => $yesterday
    );
};

get '/graph' => sub {
    my ($self, $c )  = @_;

    my $address = $c->req->param('address');
    return $c->res->not_found('Address Not Found') unless $address;
    my $resource = $c->req->param('resource');
    return $c->res->not_found('Resource Not Found') unless $resource;
    my $key = $c->req->param('key');
    return $c->res->not_found('Graph type key Not Found') unless $key;

    my $span = $c->req->param('span') || 'd';
    my $host = $self->configloader->all_hosts->{$address};
    return $c->res->not_found('Host Not Found') unless $host;

    my $host_instance = $self->get_host($host);
    my ($img,$err) = $host_instance->draw_graph($resource,$key, $span,
        $c->req->param('from_date'), $c->req->param('to_date') );

    return $c->res->server_error($err) unless $img;

    $c->res->content_type('image/png');
    $c->res->body($img);
    return $c->res;
};

__DATA__
@@ base
<html>
<head>
<title><: block title -> {} :> CloudForecast</title>
<link rel="stylesheet" type="text/css" href="<: $c.req.uri_for('/static/default.css') :>" />
<link rel="stylesheet" type="text/css" href="<: $c.req.uri_for('/static/css/ui-lightness/jquery-ui-1.8.2.custom.css') :>" />
<link rel="stylesheet" type="text/css" href="<: $c.req.uri_for('/static/css/anytimec.css') :>" />
</head>
<body>
<div id="container">
<div id="header">
<h1 class="title"><a href="<: $c.req.uri_for('/') :>">CloudForecast</a></h1>
<div class="welcome">
<ul>
<li><a href="<: $c.req.uri_for('/') :>">TOP</a></li>
</ul>
</div>
</div>

: block headmenu -> { } 

<div id="content">

<h2 id="ptitle">
: block ptitle -> {
<a href="<: $c.req.uri_for('/') :>">SERVER LIST</a>
: }
</h2>

<div id="display-control">
: block displaycontrol -> {
<input type="checkbox" id="open_target" /><label for="open_target">open in current window</label>
: }
</div>

: block content -> { }

</div>
</div>

<script src="<: $c.req.uri_for('/static/js/jquery-1.4.2.min.js') :>" type="text/javascript"></script>
<script src="<: $c.req.uri_for('/static/js/jquery-ui-1.8.2.custom.min.js') :>" type="text/javascript"></script>
<script src="<: $c.req.uri_for('/static/js/jstorage.js') :>" type="text/javascript"></script>
<script src="<: $c.req.uri_for('/static/js/anytimec.js') :>" type="text/javascript"></script>
<script type="text/javascript">
: block javascript -> { } 
</script>
</body>
</html>

@@ index
: cascade 'base'
: around title -> {
SERVER LIST « 
: }

: around headmenu -> {
<div id="grouplist">
<ul>
  : for $server_list -> $group {
<li><a href="#group-<: $group.title_key :>"><: $group.title :></a></li>
  : }
</ul>
</div>
: }

: around content -> {
<ul id="serverlist-ul">
  : for $server_list -> $group {
<li class="group-name" id="group-<: $group.title_key :>"><span class="ui-icon ui-icon-triangle-1-s" style="float:left"></span><: $group.title :><a href="#" class="ui-icon ui-icon-arrowthick-1-n" style="float:right">↑</a><a href="<: $c.req.uri_for('/group',[ id => $group.title_key]) :>" class="ui-icon ui-icon-arrowthick-1-ne" style="float:right" >↗</a></li>
<ul class="group-ul" id="ul-group-<: $group.title_key :>">
    : for $group.sub_groups -> $sub_group {
      : if $sub_group.label {
<li id="sub-group-<: $sub_group.label_key :>" class="sub-group-name"><span class="ui-icon ui-icon-triangle-1-s" style="float:left"></span><: $sub_group.label :></li>
      : }
<ul class="host-ul" id="ul-sub-group-<: $sub_group.label_key :>">
      : for $sub_group.hosts -> $host {
<li class="host-li"><a href="<: $c.req.uri_for('/server',[address => $host.address ]) :>"><: $host.address :></a> <strong><: $host.hostname :></strong> <span class="details"><: $host.details :></li>
      : }
</ul>
    : } # sub_group
</ul>
  : } # group
</ul>
: } # content

: around javascript -> {
$(function() {
    $("#grouplist > ul > li > a").click( function(){
        if ( $(this).data('dblc') == true ) return false;
        var tag = this;
        var id = setTimeout( function(){
            var match = $(tag).attr('href').match(/([0-9a-z]+)$/);
             $(tag).data('dblc', false);
            location.hash = '#group-'+match[0];
        }, 300 );
        $(this).data('dblc',true);
        $(this).data('ctimer', id );
        return false;
    });
    $("#grouplist > ul > li > a").dblclick( function(){
        clearTimeout($(this).data('ctimer'));
        var match = $(this).attr('href').match(/([0-9a-z]+)$/);
        $(this).data('dblc', false);
        location.href = $('#group-'+match[0]+' a.ui-icon-arrowthick-1-ne').attr('href');
        return false;
    });
    $("#grouplist > ul > li > a").button( { icons: {primary:'ui-icon-document-b' }});

    var opentarget = $.jStorage.get( "open_target" );
    if ( opentarget == true ) {
        $("#open_target").attr("checked", true );
    }
    $("#open_target").button({ icons: {primary:'ui-icon-newwin' }});
    $("#open_target").change(function(){
        $.jStorage.set( "open_target", $(this).attr("checked") );
        if ( $(this).attr("checked") ) {
            $(".host-li a").attr("target","_blank");
            $(this).button({ label: "open in new window"});
        }
        else {
            $(".host-li a").attr("target","_self");
            $(this).button({ label: "open in currnet window"});
        }
    });
    if ( $("#open_target").attr("checked") ) {
        $(".host-li a").attr("target","_blank");
        $("#open_target").button({ label: "open in new window"});
    }
    else {
        $(".host-li a").attr("target","_self");
        $("#open_target").button({ label: "open in current window"});
    }

    $("li.group-name").click(function(){
        if ( $(this).data('dblc') == true ) return false;
        $(this).data('dblc', true );
        var li_group = this;
        var id = setTimeout(function(){ $("#ul-" + li_group.id).toggle(100, function(){
                $(li_group).toggleClass('group-name-off');
                $(li_group).children().first().toggleClass('ui-icon-triangle-1-s','ui-icon-triangle-1-e');
                $(li_group).children().first().toggleClass('ui-icon-triangle-1-e','ui-icon-triangle-1-s');
                $.jStorage.set( "display-" + li_group.id, $(this).css('display') );
            }); 
            $(li_group).data('dblc', false ); } ,
            300 );
        $(this).data('ctimer', id );
        return false;
    });
    $("li.group-name").dblclick(function(){
        clearTimeout( $(this).data('ctimer') );
        $(this).data('dblc', false);
        location.href = $(this).children("a.ui-icon-arrowthick-1-ne").attr('href');
        return false;
    });
    $("li.group-name a.ui-icon-arrowthick-1-ne, li.group-name a.ui-icon-arrowthick-1-n").click(function(){
        location.href = $(this).attr('href');
        return false;
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
: } #content

@@ group
: cascade 'base'
: around title -> {
<: $group.title :> « SERVER LIST « 
: }

: around headmenu -> {
<div id="grouplist">
<ul>
  : for $server_list -> $group {
<li><a href="<: $c.req.uri_for('/group',[ id => $group.title_key ]) :>"><: $group.title :></a></li>
  : }
</ul>
</div>
: }

: around ptitle -> {
<a href="<: $c.req.uri_for('/') :>">SERVER LIST</a> » <: $group.title :>
: }

: around displaycontrol -> {
<input type="checkbox" id="open_target" /><label for="open_target">open in current window</label>
: }

: around content -> {
<ul id="serverlist-ul">
<li class="group-name" id="group-<: $group.title_key :>"><span class="ui-icon ui-icon-stop" style="float:left"></span><: $group.title :></li>
<ul class="group-ul" id="ul-group-<: $group.title_key :>">
  : for $group.sub_groups ->  $sub_group {
    : if $sub_group.label {
<li id="sub-group-<: $sub_group.label_key :>" class="sub-group-name"><span class="ui-icon ui-icon-triangle-1-s" style="float:left"></span><: $sub_group.label :></li>
    : }
<ul class="host-ul" id="ul-sub-group-<: $sub_group.label_key :>">
    : for $sub_group.hosts -> $host {
<li class="host-li"><a href="<: $c.req.uri_for('/server',[address => $host.address ]) :>"><: $host.address :></a> <strong><: $host.hostname :></strong> <span class="details"><: $host.details :></li>
    : }
</ul>
  : }
</ul>
</ul>
: }

: around javascript -> {
$(function() {
    $("#grouplist > ul > li > a").button({ icons: {primary:'ui-icon-document-b' }});

    var opentarget = $.jStorage.get( "open_target" );
    if ( opentarget == true ) {
        $("#open_target").attr("checked", true );
    }
    $("#open_target").button({ icons: {primary:'ui-icon-newwin' }});
    $("#open_target").change(function(){
        $.jStorage.set( "open_target", $(this).attr("checked") );
        if ( $(this).attr("checked") ) {
            $(".host-li a").attr("target","_blank");
            $(this).button({ label: "open in new window"});
        }
        else {
            $(".host-li a").attr("target","_self");
            $(this).button({ label: "open in currnet window"});
        }
    });
    if ( $("#open_target").attr("checked") ) {
        $(".host-li a").attr("target","_blank");
        $("#open_target").button({ label: "open in new window"});
    }
    else {
        $(".host-li a").attr("target","_self");
        $("#open_target").button({ label: "open in current window"});
    }

    $("li.sub-group-name").click(function(){
        var li_sub_group = this;
        $("#ul-" + li_sub_group.id).toggle(010, function(){
            $(li_sub_group).toggleClass('group-name-off');
            $(li_sub_group).children().first().toggleClass('ui-icon-triangle-1-s','ui-icon-triangle-1-e');
            $(li_sub_group).children().first().toggleClass('ui-icon-triangle-1-e','ui-icon-triangle-1-s');
            $.jStorage.set( "display-" + li_sub_group.id, $(this).css('display') );
        });
    });
    
    $("li.sub-group-name").map(function(){
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
: } 

@@ server
: cascade 'base'
: around title -> {
<: $host.hostname :> <: $host.address :> « 
: } 

: around ptitle -> {
<a href="<: $c.req.uri_for('/group', [id => $group_key]) :>"><: $group_title :></a> » <a href="<: $c.req.uri_for('/server', [address => $host.address]) :>" class="address"><: $host.address :></a> <strong><: $host.hostname :></strong> <span class="details"><: $host.details :>
: }

: around displaycontrol -> {
<form id="pickdate" method="get" action="<: $c.req.uri_for('/server') :>">
: if $daterange {
<a href="<: $c.req.uri_for('/server', [ address => $host.address ]) :>">Disply Latest Graph</a>
: } else {
<a href="<: $c.req.uri_for('/server', [ address => $host.address, displaymy => $c.req.param('displaymy') ? 0 : 1 ]) :>"><: $c.req.param('displaymy') ? 'Hide' : 'Show' :> Monthly Graph</a>
: }
<span>Date Range:</span>
<label for="from_date">From</label>
<input type="text" id="from_date" name="from_date" value="<: $c.req.param('from_date') || $yesterday :>" size="21" />
<label for="to_date">To</label>
<input type="text" id="to_date" name="to_date" value="<: $c.req.param('to_date') || $c.req.param('from_date') || $today :>" size="21" />
<input type="hidden" name="address" value="<: $host.address :>" />
<input type="hidden" name="mode" value="range" />
<span>ex: 2004-05-23 12:00:00</span>
<input type="submit" id="pickdate_submit" value="Display">
</form>
: }

: around content -> {
: if $graph_list.size() > 1 {
<ul id="resource-list">
: for $graph_list -> $resource {
<li><a href="#resource-<: $resource.graph_title :>"><: $resource.graph_title :></a></li>
: }
</ul>
: }

: for $graph_list -> $resource {
<h4 class="resource-title" id="resource-<: $resource.graph_title :>"><: $resource.graph_title :></h4>
  : if ( $resource.sysinfo.size() ) {
<div class="resource-sysinfo">
    : for $resource.sysinfo -> $sysinfo {
      : if ( ($~sysinfo.index % 2) == 0 ) {
<div>
<span><: $sysinfo :></span>
      : } else {
<: $sysinfo :>
</div>
      : }
    : }
</div>
  : }
<div class="resource-graph">
  : for $resource.graphs -> $graph {
<div class="ngraph">
    : if $daterange {
<img src="<: $c.req.uri_for('/graph', [span => 'c', from_date => $c.req.param('from_date'), to_date => $c.req.param('to_date'), address => $host.address, resource => $resource.resource, key => $graph ]) :>" />
    : } else {
      : my $terms = ( $c.req.param('displaymy') ) ? ['d','w','m','y'] : ['d','w']
      : for $terms -> $term {
<img src="<: $c.req.uri_for('/graph', [span => $term, address => $host.address, resource => $resource.resource, key => $graph]) :>" />
      : }
    : }
</div>
  : }
</div>
: }

: } # content

: around javascript -> {
$(function() {
     $("#display-control a:first").button({ icons: {primary:'ui-icon-transfer-e-w' }});
     $("#pickdate_submit").button();
     $("#from_date").AnyTime_picker( { format: "%Y-%m-%d %H:00:00",
                                       monthAbbreviations: ['01','02','03','04','05','06','07','08','09','10','11','12'] });
     $("#to_date").AnyTime_picker( { format: "%Y-%m-%d %H:00:00",
                                    monthAbbreviations: ['01','02','03','04','05','06','07','08','09','10','11','12'] });
});
: }

