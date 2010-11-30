package CloudForecast::Web;

use strict;
use warnings;
use Shirahata -base;
use CloudForecast::Host;
use CloudForecast::ConfigLoader;
use CloudForecast::Ledge;
use List::Util;
use Plack::Builder;
use Plack::Loader;
use Net::IP;
use Path::Class;
use JSON;

accessor(qw/configloader root_dir global_config server_list restarter port host allowfrom front_proxy/);

our $GIF_DATA = pack "C35", (
    0x47, 0x49, 0x46, 0x38, 0x39, 0x61,
    0x01, 0x00, 0x01, 0x00, 0x80, 0xff,
    0x00, 0xff, 0xff, 0xff, 0x00, 0x00,
    0x00, 0x2c, 0x00, 0x00, 0x00, 0x00,
    0x01, 0x00, 0x01, 0x00, 0x00, 0x02,
    0x02, 0x44, 0x01, 0x00, 0x3b);

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

sub ledge {
    my $self = shift;
    $self->{__ledge} ||= CloudForecast::Ledge->new({
        data_dir => $self->configloader->global_config->{data_dir},
        db_name  => $self->configloader->global_config->{db_name}
    });
    $self->{__ledge};
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
    my $group = List::Util::first { $_->{title} eq $c->req->param('id') || $_->{title_key} eq $c->req->param('id') }
        @{$self->configloader->server_list};
    return $c->res->not_found('Group Not Found') unless $group;

    return $c->render(
        'group',
        server_list => $self->configloader->server_list,
        group => $group
    );
};

get '/exists_server' => sub {
    my ( $self, $c ) = @_;
    my $daterange;

    my $address = $c->req->param('address');
    return $c->res->not_found() unless $address;

    my $host = $self->configloader->all_hosts->{$address};
    return $c->res->not_found() unless $host;

    $c->res->content_type('image/gif');
    $c->res->body($GIF_DATA);
    return $c->res;

};

post '/api/haserror' => sub {
    my ( $self, $c ) = @_;

    my @servers = $c->req->param('address');
    return $c->res->not_found('Address Not Exists') unless @servers;

    my $crit = $self->ledge->get_multi_by_address(
        '__SYSTEM__',
        '__has_error__:crit',
        [@servers]
    );

    my $warn = $self->ledge->get_multi_by_address(
        '__SYSTEM__',
        '__has_error__:warn',
        [@servers]
    );

    my $ok = $self->ledge->get_multi_by_address(
        '__SYSTEM__',
        '__has_error__:ok',
        [@servers]
    );
    
    my %ret;
    for my $server ( @servers ) {
        if ( exists $crit->{$server} ) {
            $ret{$server} = 2;
        }
        elsif ( exists $warn->{$server} ) {
            $ret{$server} = 1;
        }
        elsif ( exists $ok->{$server} ) {
            $ret{$server} = 0;
        }
    }

    $c->res->content_type('application/json; charset=utf-8');
    $c->res->body(JSON->new->latin1->encode(\%ret));
    return $c->res;
};

get '/servers' => sub {
    my ( $self, $c ) = @_;

    my @servers = $c->req->param('address');
    return $c->res->not_found('Address Not Exists') unless @servers;

    my @hosts = grep { $_ } map {
        $self->configloader->all_hosts->{$_}
    } @servers;
    return $c->res->not_found('Host Not Found') unless @hosts;
    my @addresses = map { (address => $_->{address}) } @hosts;

    my @all;
    for my $host ( @hosts ) {
        my $host_instance = $self->get_host($host);
        my @graph_list = $host_instance->list_graph;

        my $group_title;
        my $group_key;
        SEARCH_GROUP: for my $main_group ( @{$self->configloader->server_list} ) {
            for my $sub_group ( @{$main_group->{sub_groups}} ) {
                for my $group_host ( @{$sub_group->{hosts}} ) {
                    if ( $group_host->{address} eq $host->{address} ) {
                        $group_title = $main_group->{title};
                        $group_key   = $main_group->{title_key};
                        last SEARCH_GROUP;
                    }
                }
            }
        }

        push @all, {
            host => $host,
            graph_list => \@graph_list,
            group_title => $group_title,
            group_key => $group_key,
        };
    }

     my $daterange;
     if ( $c->req->param('mode') && $c->req->param('mode') eq 'range' ) {
         $daterange = 1;
     } 
     my @today = localtime;
     my $today =  sprintf("%04d-%02d-%02d 00:00:00", $today[5]+1900, $today[4]+1, $today[3]);
     my @yesterday = localtime( time - 24* 60 * 60 );
     my $yesterday = sprintf("%04d-%02d-%02d 00:00:00", $yesterday[5]+1900, $yesterday[4]+1, $yesterday[3]);

    return $c->render(
        'servers',
        hosts => \@all,
        addresses => \@addresses,
        daterange => $daterange,
        today => $today,
        yesterday => $yesterday
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

<div id="header">
<h1 class="title"><a href="<: $c.req.uri_for('/') :>">CloudForecast</a></h1>
<div class="welcome">
<ul>
<li><a href="<: $c.req.uri_for('/') :>">TOP</a></li>
</ul>
</div>
<div id="headmenu">
: block headmenu -> {
&nbsp;
: }
</div>

<h2 id="ptitle">
: block ptitle -> {
<a href="<: $c.req.uri_for('/') :>">TOP</a>
: }
</h2>

<div id="display-control-wrap"><div id="display-control">
: block displaycontrol -> {
<div id="display-control-main">
<span style="display:inline-box;border: 1px solid #ccc;background-color:#eee;padding:3px;-webkit-border-radius: 2px;-moz-border-radius: 2px;"><input type="checkbox" name="uncheckall" /></span>
<a href="<: $c.req.uri_for('/') :>" id="open_selected">View Selected Hosts</a>
</div>
<div id="display-control-sub">
<input type="checkbox" id="open_target" /><label for="open_target">target window</label>
</div>
: } #displaycontrol
</div></div>

</div>
<div id="headspacer"></div>

<div id="content">

: block content -> { }

</div>

<script src="<: $c.req.uri_for('/static/js/jquery-1.4.4.min.js') :>" type="text/javascript"></script>
<script src="<: $c.req.uri_for('/static/js/jquery-ui-1.8.2.custom.min.js') :>" type="text/javascript"></script>
<script src="<: $c.req.uri_for('/static/js/jquery.field.min.js') :>" type="text/javascript"></script>
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
TOP « 
: }

: around headmenu -> {
<ul>
<li><a href="#">TOP</a></li>
  : for $server_list -> $group {
<li><a href="#group-<: $group.title | uri :>"><: $group.title :></a></li>
  : }
</ul>
: }

: around content -> {
<form>
<ul id="serverlist-ul">
  : for $server_list -> $group {
<li class="group-name" id="group-<: $group.title | uri :>"><span class="ui-icon ui-icon-triangle-1-s" style="float:left"></span><: $group.title :><a href="#" class="ui-icon ui-icon-arrowthick-1-n" style="float:right">↑</a><a href="<: $c.req.uri_for('/group',[ id => $group.title]) :>" class="ui-icon ui-icon-arrowthick-1-ne" style="float:right" >↗</a></li>
<ul class="group-ul" id="ul-group-<: $group.title | uri :>">
    : for $group.sub_groups -> $sub_group {
      : if $sub_group.label {
<li id="sub-group-<: $sub_group.label_key :>" class="sub-group-name"><span class="ui-icon ui-icon-triangle-1-s" style="float:left"></span><: $sub_group.label :></li>
      : }
<ul class="host-ul" id="ul-sub-group-<: $sub_group.label_key :>">
      : for $sub_group.hosts -> $host {
<li class="host-li configgroup-<: $host.config_group_num  :>"><span class="host-status">&#x2716;</span> <input class="addresscb" name="addresscb" type="checkbox" value="<: $host.address :>" /> <a href="<: $c.req.uri_for('/server',[address => $host.address ]) :>" class="host-address"><: $host.address :></a> <strong><: $host.hostname :></strong> <span class="details"><: $host.details :></span></li>
      : }
</ul>
    : } # sub_group
</ul>
  : } # group
</ul>
</form>
: } # content

: around javascript -> {
$(function() {
     var page_scroll = function (id) {
         id = id.replace(/(~|%|:|\.)/g,'\\$1');
         if ( $(id).length > 0 ) {
             var offset = $(id).offset().top - $('#header').outerHeight(true) - 5;
             $('html,body').animate( { scrollTop: offset }, 50);
         }
     };

    $("#headmenu > ul > li > a:gt(0)").click( function(){
        if ( $(this).data('dblc') == true ) return false;
        var tag = this;
        var id = setTimeout( function(){
            var match = $(tag).attr('href').match(/#group-(.+)$/);
             $(tag).data('dblc', false);
            location.hash = '#lgroup-'+match[1];
            page_scroll( '#group-'+match[1]);
        }, 300 );
        $(this).data('dblc',true);
        $(this).data('ctimer', id );
        return false;
    });
    $("#headmenu > ul > li > a:gt(0)").dblclick( function(){
        clearTimeout($(this).data('ctimer'));
        var match = $(this).attr('href').match(/#group-(.+)$/);
        $(this).data('dblc', false);
        var id = match[1].replace(/(~|%|:|\.)/g,'\\$1');
        location.href = $('#group-'+id+' a.ui-icon-arrowthick-1-ne').attr('href');
        return false;
    });

    $("#headmenu > ul > li > a:first").button( { text: false, icons: {primary:'ui-icon-arrowstop-1-n' }});
    $("#headmenu > ul > li > a:first").click(function(){
        $('html,body').animate( { scrollTop: 0 }, 50);
    });
    $("#headmenu > ul > li > a:gt(0)").button( { icons: {primary:'ui-icon-document-b' }});

    var addresscbClick = function () {
        $("input.addresscb").each(function(){
            if( $(this).is(":checked") ) {
                $(this).parent().addClass("host-li-checked");
            }
            else {
                $(this).parent().removeClass("host-li-checked")
            }
        });
        if ( $("input.addresscb:checked").length >= 2 ) {
            $("input[name=uncheckall]").attr('disabled',false);
            $("input[name=uncheckall]").attr('checked', true);
            $("#open_selected").button({disabled:false});
        }
        else {
            $("input[name=uncheckall]").attr('disabled',true);
            $("input[name=uncheckall]").attr('checked', false);
            $("#open_selected").button({disabled:true});
        } 
    };

    $("input.addresscb").createCheckboxRange();
    $("input.addresscb").click(addresscbClick);
    addresscbClick.call();

    $("#open_selected").click(function(){
        var form = $('<form/>');
        $("input.addresscb:checked").each( function () {
            var input = $('<input/>');
            input.attr('name','address');
            input.attr('value',$(this).val());
            form.append(input);
        });
        $(this).attr('href','<: $c.req.uri_for('/servers') :>?' + form.serialize());
    });
    $("input[name=uncheckall]").click(function(){
        $("input.addresscb:checked").attr('checked',false);
        addresscbClick.call();
    });


    var opentarget = $.jStorage.get( "open_target" );
    if ( opentarget == true ) {
        $("#open_target").attr("checked", true );
    }
    $("#open_target").button({ text:null, icons: {primary:'ui-icon-newwin' }});
    $("#open_target").change(function(){
        $.jStorage.set( "open_target", $(this).attr("checked") );
        if ( $(this).attr("checked") ) {
            $(".host-li a").attr("target","_blank");
            $("#open_selected").attr("target","_blank");
        }
        else {
            $(".host-li a").attr("target","_self");
            $("#open_selected").attr("target","_self");
        }
    });
    $("#open_target").change();
    

    $("li.group-name").click(function(){
        if ( $(this).data('dblc') == true ) return false;
        $(this).data('dblc', true );
        var li_group = this;
        var gid = li_group.id.replace(/(~|%|:|\.)/g,'\\$1');
        var id = setTimeout(function(){ $("#ul-" + gid).toggle(100, function(){
                $(li_group).toggleClass('group-name-off');
                $(li_group).children().first().toggleClass('ui-icon-triangle-1-s','ui-icon-triangle-1-e');
                $(li_group).children().first().toggleClass('ui-icon-triangle-1-e','ui-icon-triangle-1-s');
                $.jStorage.set( "display-" + gid, $(this).css('display') );
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

    $('window').resize(function(){ $('headspacer').height( $('#header').outerHeight(true) ) } );
    $('#headspacer').height( $('#header').outerHeight(true) );

    var hostslen = $("a.host-address").length;
    var haserror_api = function (startnum) {
        var form = $('<form/>');
        var endnum = (startnum+100 < hostslen) ? startnum+100 : hostslen;
        $("a.host-address").slice(startnum, endnum).each(function(){
            var input = $('<input/>');
            input.attr('name','address');
            input.attr('value',$(this).text());
            form.append(input);
        });
        $.post(
            '<: $c.req.uri_for('/api/haserror') :>',
            form.serialize(),
            function (data) {
                $("a.host-address").slice(startnum, endnum).each(function(){
                    var ip = $(this).text();
                    var tag = $(this).parent().children("span.host-status");
                    if ( data[ip] == 2 ) {
                        tag.addClass("host-status-crit");
                    }
                    else if ( data[ip] == 1 ) {
                        tag.addClass("host-status-warn");
                    }
                    else if ( data[ip] == 0 ) {
                        tag.addClass("host-status-ok");
                    }
                    else {
                        tag.addClass("host-status-wait");
                    }
                });
                if ( endnum < hostslen ) haserror_api(startnum+100);
            },
            "json"
        );
    };
    haserror_api(0);
})
: } #content

@@ group
: cascade 'base'
: around title -> {
<: $group.title :> « TOP « 
: }

: around headmenu -> {
<ul>
<li><a href="<: $c.req.uri_for('/') :>">TOP</a></li>
  : for $server_list -> $group {
<li><a href="<: $c.req.uri_for('/group',[ id => $group.title ]) :>"><: $group.title :></a></li>
  : }
</ul>
: }

: around ptitle -> {
<a href="<: $c.req.uri_for('/') :>">TOP</a> » <: $group.title :>
: }

: around content -> {
<form>
<ul id="serverlist-ul">
<li class="group-name" id="group-<: $group.title | uri :>"><span class="ui-icon ui-icon-stop" style="float:left"></span><: $group.title :></li>
<ul class="group-ul" id="ul-group-<: $group.title| uri :>">
  : for $group.sub_groups ->  $sub_group {
    : if $sub_group.label {
<li id="sub-group-<: $sub_group.label_key :>" class="sub-group-name"><span class="ui-icon ui-icon-triangle-1-s" style="float:left"></span><: $sub_group.label :></li>
    : }
<ul class="host-ul" id="ul-sub-group-<: $sub_group.label_key :>">
    : for $sub_group.hosts -> $host {
<li class="host-li"><span class="host-status">&#x2716;</span> <input class="addresscb" name="addresscb" type="checkbox" value="<: $host.address :>" /> <a href="<: $c.req.uri_for('/server',[address => $host.address ]) :>" class="host-address"><: $host.address :></a> <strong><: $host.hostname :></strong> <span class="details"><: $host.details :></li>
    : }
</ul>
  : }
</ul>
</ul>
</form>
: }

: around javascript -> {
$(function() {
    $("#headmenu > ul > li > a:first").button( { text: false, icons: {primary:'ui-icon-arrowstop-1-n' }});
    $("#headmenu > ul > li > a:gt(0)").button({ icons: {primary:'ui-icon-transfer-e-w' }});

     var addresscbClick = function () {
         $("input.addresscb").each(function(){
             if( $(this).is(":checked") ) {
                 $(this).parent().addClass("host-li-checked");
             }
             else {
                 $(this).parent().removeClass("host-li-checked")
             }
         });
         if ( $("input.addresscb:checked").length >= 2 ) {
             $("input[name=uncheckall]").attr('disabled',false);
             $("input[name=uncheckall]").attr('checked', true);
             $("#open_selected").button({disabled:false});
         }
         else {
             $("input[name=uncheckall]").attr('disabled',true);
             $("input[name=uncheckall]").attr('checked', false);
             $("#open_selected").button({disabled:true});
         } 
     };
 
     $("input.addresscb").createCheckboxRange();
     $("input.addresscb").click(addresscbClick);
     addresscbClick.call();
 
     $("#open_selected").click(function(){
         var form = $('<form/>');
         $("input.addresscb:checked").each( function () {
             var input = $('<input/>');
             input.attr('name','address');
             input.attr('value',$(this).val());
             form.append(input);
         });
         $(this).attr('href','<: $c.req.uri_for('/servers') :>?' + form.serialize());
     });
     $("input[name=uncheckall]").click(function(){
         $("input.addresscb:checked").attr('checked',false);
         addresscbClick.call();
     });
 
    var opentarget = $.jStorage.get( "open_target" );
    if ( opentarget == true ) {
        $("#open_target").attr("checked", true );
    }
    $("#open_target").button({ text:null, icons: {primary:'ui-icon-newwin' }});
    $("#open_target").change(function(){
        $.jStorage.set( "open_target", $(this).attr("checked") );
        if ( $(this).attr("checked") ) {
            $(".host-li a").attr("target","_blank");
            $("#open_selected").attr("target","_blank");
        }
        else {
            $(".host-li a").attr("target","_self");
            $("#open_selected").attr("target","_self");
        }
    });
    $("#open_target").change();

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

    $('window').resize(function(){ $('headspacer').height( $('#header').outerHeight(true) ) } );
    $('#headspacer').height( $('#header').outerHeight(true) );
    var hostslen = $("a.host-address").length;
    var haserror_api = function (startnum) {
        var form = $('<form/>');
        var endnum = (startnum+100 < hostslen) ? startnum+100 : hostslen;
        $("a.host-address").slice(startnum, endnum).each(function(){
            var input = $('<input/>');
            input.attr('name','address');
            input.attr('value',$(this).text());
            form.append(input);
        });
        $.post(
            '<: $c.req.uri_for('/api/haserror') :>',
            form.serialize(),
            function (data) {
                $("a.host-address").slice(startnum, endnum).each(function(){
                    var ip = $(this).text();
                    var tag = $(this).parent().children("span.host-status");
                    if ( data[ip] == 2 ) {
                        tag.addClass("host-status-crit");
                    }
                    else if ( data[ip] == 1 ) {
                        tag.addClass("host-status-warn");
                    }
                    else if ( data[ip] == 0 ) {
                        tag.addClass("host-status-ok");
                    }
                    else {
                        tag.addClass("host-status-wait");
                    }
                });
                if ( endnum < hostslen ) haserror_api(startnum+100);
            },
            "json"
        );
    };
    haserror_api(0);
})
: } 

@@ server
: cascade 'base'
: around title -> {
<: $host.hostname :> <: $host.address :> « 
: } 

: around headmenu -> {
<ul>
<li><a href="#">TOP</a></li>
: for $graph_list -> $resource {
<li><a class="resource-anchor" href="#lresource-<: $resource.graph_title | uri :>"><: $resource.graph_title :></a></li>
: }
</ul>
: } #around headmenu

: around ptitle -> {
<a href="<: $c.req.uri_for('/group', [id => $group_title]) :>"><: $group_title :></a> » <a href="<: $c.req.uri_for('/server', [address => $host.address]) :>" class="address"><: $host.address :></a> <strong><: $host.hostname :></strong> <span class="details"><: $host.details :></span><span class="ui-icon ui-icon-copy" style="display:inline-block;cursor:pointer;" id="clipboard_open"></span>
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
<div id="to_clipboard"><form><textarea id="clipboard_text"><: $c.req.uri_for('/server', [address => $host.address]) :> <: $host.hostname :></textarea></form></div>
: for $graph_list -> $resource {
<h4 class="resource-title" id="resource-<: $resource.graph_title | uri :>"><: $resource.graph_title :></h4>
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
     var page_scroll = function (id) {
         id = id.replace(/(~|%|:|\.)/g,'\\$1');
         if ( $(id).length > 0 ) {
             var offset = $(id).offset().top - $('#header').outerHeight(true) - 5;
             $('html,body').animate( { scrollTop: offset }, 50);
         }
     };

     $("#headmenu > ul > li > a:first").button( { text: false, icons: {primary:'ui-icon-arrowstop-1-n' }});
     $("#headmenu > ul > li > a:first").click( function() {
         $('html,body').animate( { scrollTop: 0 }, 50);
     });
     $("#headmenu > ul > li > a.resource-anchor").button( { icons: {primary:'ui-icon-image' }});
     $("#headmenu > ul > li > a.resource-anchor").click( function(){
         var href = $(this).attr('href');
         if ( href.match(/^#lresource-/) ) {
             var id = href.replace( /^#lresource-/, '#resource-' );
             page_scroll(id);
         }
     });
     $("#display-control a:first").button({ icons: {primary:'ui-icon-transfer-e-w' }});

     $("#pickdate_submit").button();
     $("#from_date").AnyTime_picker( { format: "%Y-%m-%d %H:00:00",
                                       monthAbbreviations: ['01','02','03','04','05','06','07','08','09','10','11','12'] });
     $("#to_date").AnyTime_picker( { format: "%Y-%m-%d %H:00:00",
                                    monthAbbreviations: ['01','02','03','04','05','06','07','08','09','10','11','12'] });
    $('window').resize(function(){ $('headspacer').height( $('#header').outerHeight(true) ) } );
    $('#headspacer').height( $('#header').outerHeight(true) );

    var hash = location.hash;
    if ( hash.length > 0 && hash.match(/^#l?resource-/) ) {
        var id = hash.replace( /^#lresource-/, '#resource-' );
        page_scroll(id);
    }

    $('.ui-widget-overlay').live("click", function() {
        $("#to_clipboard").dialog("close");
    });   
    $('#to_clipboard').dialog({
        autoOpen: false,
        modal: true,
        title: "Copy to Clipboard",
        width: 497,
        height: 95,
        resizable: false,
        open: function(){ $('#clipboard_text').select();  }
    });

    $("#clipboard_open").click( function() { $( "#to_clipboard" ).dialog( "open" ); return false } );
});
: }


@@ servers
: cascade 'base'
: around title -> {
Selected Servers « 
: } #title


: around headmenu -> {
<ul>
<li><a href="<: $c.req.uri_for('/') :>">TOP</a></li>
</ul>
: } #around headmenu


: around ptitle -> {
Selected Servers
: }

: around displaycontrol -> {
<form id="pickdate" method="get" action="<: $c.req.uri_for('/servers') :>">
<a href="<: $c.req.uri_for('/servers', $addresses) :>">Disply Latest Graph</a>
<span>Date Range:</span>
<label for="from_date">From</label>
<input type="text" id="from_date" name="from_date" value="<: $c.req.param('from_date') || $yesterday :>" size="21" />
<label for="to_date">To</label>
<input type="text" id="to_date" name="to_date" value="<: $c.req.param('to_date') || $c.req.param('from_date') || $today :>" size="21" />
<input type="hidden" name="mode" value="range" />
<span>ex: 2004-05-23 12:00:00</span>
<input type="submit" id="pickdate_submit" value="Display">
: for $hosts -> $host {
<input type="hidden" name="address" value="<: $host.host.address :>" />
: } #for
</form>
: }

: around content -> {
<table>
<tr>
: for $hosts -> $host {
<td valign="top">
<div style="width: 501px; overflow: hidden">
<h3 class="host-title"><a href="<: $c.req.uri_for('/server', [address => $host.host.address]) :>" class="address""><: $host.host.address :></a> <strong><: $host.host.hostname :></strong></h3>
<p class="host-detail"><: $host.host.details :></p>
<p class="host-detail">[<a href="<: $c.req.uri_for('/group', [id => $host.group_title]) :>"><: $host.group_title :></a>]</p>
: for $host.graph_list -> $resource {
<h4 class="resource-title" id="resource-<: $resource.graph_title | uri :>"><: $resource.graph_title :></h4>
  : if ( $resource.sysinfo.size() ) {
<div class="resource-sysinfo">
    : for $resource.sysinfo -> $sysinfo {
      : if ( ($~sysinfo.index % 2) == 0 ) {
<div>
<span><: $sysinfo :></span>
      : } else {
<: $sysinfo :>
</div>
      : } # if index % 2
    : } # for sysnfo
</div>
  : } # if resource.sysinfo.size

<div class="resource-graph">
  : for $resource.graphs -> $graph {
<div class="ngraph">
    : if $daterange {
<img src="<: $c.req.uri_for('/graph', [span => 'c', from_date => $c.req.param('from_date'), to_date => $c.req.param('to_date'), address => $host.host.address, resource => $resource.resource, key => $graph ]) :>" />
    : } else {
<img src="<: $c.req.uri_for('/graph', [span => 'd', address => $host.host.address, resource => $resource.resource, key => $graph]) :>" />
    : } # if daterange
</div>
  : } # for resource.graphs
</div>
: } # for host.graph_list
<h3 class="host-title"><a href="<: $c.req.uri_for('/server', [address => $host.host.address]) :>" class="address""><: $host.host.address :></a> <strong>
<: $host.host.hostname :></strong></h3>
</div>
</td>
: } # for hosts
</tr>
</table>
: } #content

: around javascript -> {
$(function() {
    var page_scroll = function (id) {
        id = id.replace(/(~|%|:|\.)/g,'\\$1');
        if ( $(id).length > 0 ) {
            var offset = $(id).offset().top - $('#header').outerHeight(true) - 5;
            $('html,body').animate( { scrollTop: offset }, 50);
        }
    };
    $("#headmenu > ul > li > a:first").button( { text: false, icons: {primary:'ui-icon-arrowstop-1-n' }});

     $("#display-control a:first").button({ icons: {primary:'ui-icon-transfer-e-w' }});

     $("#pickdate_submit").button();
     $("#from_date").AnyTime_picker( { format: "%Y-%m-%d %H:00:00",
                                       monthAbbreviations: ['01','02','03','04','05','06','07','08','09','10','11','12'] });
     $("#to_date").AnyTime_picker( { format: "%Y-%m-%d %H:00:00",
                                    monthAbbreviations: ['01','02','03','04','05','06','07','08','09','10','11','12'] });

    $('window').resize(function(){ $('headspacer').height( $('#header').outerHeight(true) ) } );
    $('#headspacer').height( $('#header').outerHeight(true) );

});
: }


