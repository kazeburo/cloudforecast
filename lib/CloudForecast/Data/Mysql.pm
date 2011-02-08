package CloudForecast::Data::Mysql;

use CloudForecast::Data -base;

rrds map { [ $_, 'DERIVE' ] } qw/cd ci cr cs cu sq/;
rrds map { [ $_, 'GAUGE' ] } qw/cac con run/;
graphs 'rate' => 'MySQL Queries Rate';
graphs 'count' => 'MySQL Queries Count';
graphs 'slow' => 'MySQL Slow Queries';
graphs 'thread' => 'MySQL Threads';

title {
    my $c = shift;
    my $title='MySQL';
    if ( my $port = $c->component('MySQL')->port ) {
        $title .= " (port=$port)"; 
    }
    return $title;
};

sysinfo {
    my $c = shift;
    my @sysinfo;
    if ( my $sysinfo = $c->ledge_get('sysinfo') ) {
        push @sysinfo, 'version', $sysinfo->{version} if $sysinfo->{version};
        push @sysinfo, 'version_comment', $sysinfo->{version_comment} if $sysinfo->{version_comment};

        if ( my $uptime = $sysinfo->{uptime} ) {
            my $day = int( $uptime /86400 );
            my $hour = int( ( $uptime % 86400 ) / 3600 );
            my $min = int( ( ( $uptime % 86400 ) % 3600) / 60 );
            push @sysinfo, 'uptime', sprintf("up %d days, %2d:%02d", $day, $hour, $min);
        }

        map { push @sysinfo, $_, $sysinfo->{$_} } grep { exists $sysinfo->{$_} } 
            qw/max_connections max_connect_errors thread_cache_size log_slow_queries long_query_time log_queries_not_using_indexes/;
        
    }
    return \@sysinfo;
};

fetcher {
    my $c = shift;
    my $mysql = $c->component('MySQL');
    
    my $query = 'show /*!50002 GLOBAL */ status';
    my %status;
    my $rows = $mysql->select_all($query);
    foreach my $row ( @$rows ) {
        $status{$row->{Variable_name}} = $row->{Value};
    }

    my %variable;
    my $varible_rows = $mysql->select_all(q!show variables!);
    foreach my $variable_row ( @$varible_rows ) {
        $variable{$variable_row->{Variable_name}} = $variable_row->{Value};
    }

    my %sysinfo;   
    $sysinfo{uptime} = $status{Uptime} || 0;
    map { $sysinfo{$_} = $variable{$_} } grep { exists $variable{$_} }
        qw/version version_comment log_slow_queries long_query_time log_queries_not_using_indexes max_connections max_connect_errors thread_cache_size/;
    $c->ledge_set('sysinfo', \%sysinfo );

    return [ map { $status{$_} } qw/Com_delete Com_insert Com_replace Com_select Com_update Slow_queries
                                    Threads_cached Threads_connected Threads_running/ ]; 
};


__DATA__
@@ rate
DEF:my1=<%RRD%>:cs:AVERAGE
DEF:my2=<%RRD%>:ci:AVERAGE
DEF:my3=<%RRD%>:cr:AVERAGE
DEF:my4=<%RRD%>:cu:AVERAGE
DEF:my5=<%RRD%>:cd:AVERAGE
CDEF:total=my1,my2,+,my3,+,my4,+,my5,+
CDEF:my1r=my1,total,/,100,*
CDEF:my2r=my2,total,/,100,*
CDEF:my3r=my3,total,/,100,*
CDEF:my4r=my4,total,/,100,*
CDEF:my5r=my5,total,/,100,*
AREA:my1r#c0c0c0:Select  
GPRINT:my1r:LAST:Cur\: %4.1lf[%%]
GPRINT:my1r:AVERAGE:Ave\: %4.1lf[%%]
GPRINT:my1r:MAX:Max\: %4.1lf[%%]
GPRINT:my1r:MIN:Min\: %4.1lf[%%]\l
STACK:my2r#000080:Insert  
GPRINT:my2r:LAST:Cur\: %4.1lf[%%]
GPRINT:my2r:AVERAGE:Ave\: %4.1lf[%%]
GPRINT:my2r:MAX:Max\: %4.1lf[%%]
GPRINT:my2r:MIN:Min\: %4.1lf[%%]\l
STACK:my3r#008080:Replace 
GPRINT:my3r:LAST:Cur\: %4.1lf[%%]
GPRINT:my3r:AVERAGE:Ave\: %4.1lf[%%]
GPRINT:my3r:MAX:Max\: %4.1lf[%%]
GPRINT:my3r:MIN:Min\: %4.1lf[%%]\l
STACK:my4r#800080:Update  
GPRINT:my4r:LAST:Cur\: %4.1lf[%%]
GPRINT:my4r:AVERAGE:Ave\: %4.1lf[%%]
GPRINT:my4r:MAX:Max\: %4.1lf[%%]
GPRINT:my4r:MIN:Min\: %4.1lf[%%]\l
STACK:my5r#C0C000:Delete  
GPRINT:my5r:LAST:Cur\: %4.1lf[%%]
GPRINT:my5r:AVERAGE:Ave\: %4.1lf[%%]
GPRINT:my5r:MAX:Max\: %4.1lf[%%]
GPRINT:my5r:MIN:Min\: %4.1lf[%%]\l

@@ count
DEF:my1=<%RRD%>:cs:AVERAGE
DEF:my2=<%RRD%>:ci:AVERAGE
DEF:my3=<%RRD%>:cr:AVERAGE
DEF:my4=<%RRD%>:cu:AVERAGE
DEF:my5=<%RRD%>:cd:AVERAGE
AREA:my1#c0c0c0:Select  
GPRINT:my1:LAST:Cur\: %6.1lf
GPRINT:my1:AVERAGE:Ave\: %6.1lf
GPRINT:my1:MAX:Max\: %6.1lf
GPRINT:my1:MIN:Min\: %6.1lf\l
STACK:my2#000080:Insert  
GPRINT:my2:LAST:Cur\: %6.1lf
GPRINT:my2:AVERAGE:Ave\: %6.1lf
GPRINT:my2:MAX:Max\: %6.1lf
GPRINT:my2:MIN:Min\: %6.1lf\l
STACK:my3#008080:Replace 
GPRINT:my3:LAST:Cur\: %6.1lf
GPRINT:my3:AVERAGE:Ave\: %6.1lf
GPRINT:my3:MAX:Max\: %6.1lf
GPRINT:my3:MIN:Min\: %6.1lf\l
STACK:my4#800080:Update  
GPRINT:my4:LAST:Cur\: %6.1lf
GPRINT:my4:AVERAGE:Ave\: %6.1lf
GPRINT:my4:MAX:Max\: %6.1lf
GPRINT:my4:MIN:Min\: %6.1lf\l
STACK:my5#C0C000:Delete  
GPRINT:my5:LAST:Cur\: %6.1lf
GPRINT:my5:AVERAGE:Ave\: %6.1lf
GPRINT:my5:MAX:Max\: %6.1lf
GPRINT:my5:MIN:Min\: %6.1lf\l

@@ slow
DEF:my1=<%RRD%>:sq:AVERAGE
AREA:my1#00c000:Slow Queries  
GPRINT:my1:LAST:Cur\: %4.2lf
GPRINT:my1:AVERAGE:Ave\: %4.2lf
GPRINT:my1:MAX:Max\: %4.2lf
GPRINT:my1:MIN:Min\: %4.2lf\c

@@ thread
DEF:my1=<%RRD%>:cac:AVERAGE
DEF:my2=<%RRD%>:con:AVERAGE
DEF:my3=<%RRD%>:run:AVERAGE
LINE1:my1#CC0000:Cached   
GPRINT:my1:LAST:Cur\: %6.1lf
GPRINT:my1:AVERAGE:Ave\: %6.1lf
GPRINT:my1:MAX:Max\: %6.1lf
GPRINT:my1:MIN:Min\: %6.1lf\l
LINE1:my2#000080:Connected
GPRINT:my2:LAST:Cur\: %6.1lf
GPRINT:my2:AVERAGE:Ave\: %6.1lf
GPRINT:my2:MAX:Max\: %6.1lf
GPRINT:my2:MIN:Min\: %6.1lf\l
LINE1:my3#008080:Running  
GPRINT:my3:LAST:Cur\: %6.1lf
GPRINT:my3:AVERAGE:Ave\: %6.1lf
GPRINT:my3:MAX:Max\: %6.1lf
GPRINT:my3:MIN:Min\: %6.1lf\l


