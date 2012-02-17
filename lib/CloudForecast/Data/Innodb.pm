package CloudForecast::Data::Innodb;

use CloudForecast::Data -base;

rrds map { [ $_, 'DERIVE'] } qw/ir ur dr rr/;
rrds map { [ $_, 'GAUGE'] } qw/iv uv dv rv cr/;

graphs 'row_count', 'ROW OPERATIONS Count';
graphs 'row_speed', 'ROW OPERATIONS Speed';
graphs 'cache', 'Cache Hit Ratio';

title {
    my $c = shift;
    my $title='MySQL InnoDB';
    if ( my $port = $c->component('MySQL')->port ) {
        $title .= " (port=$port)";
    }
    return $title;
};

sysinfo {
    my $c = shift;
    $c->ledge_get('sysinfo') || [];
};

fetcher {
    my $c = shift;
    
    my $row = $c->component('MySQL')->select_row('show /*!50000 ENGINE*/ innodb status');
    my $status = $row->{Status} or die 'could not get innodb status';

    my ($insert_row, $update_row, $delete_row, $read_row, $insert_vel, $update_vel, $delete_vel, $read_vel, $cache_hit, $cache_total);
    for my $line ( split /\n/, $status ) {
        if ( $line =~ /Number of rows inserted (\d+), updated (\d+), deleted (\d+), read (\d+)/ ){
                ($insert_row, $update_row, $delete_row, $read_row) = ($1, $2, $3, $4);
        }
        if ( $line =~ /([\d\.]+) inserts\/s, ([\d\.]+) updates\/s, ([\d\.]+) deletes\/s, ([\d\.]+) reads\/s/ ){
                ($insert_vel, $update_vel, $delete_vel, $read_vel) = ($1, $2, $3, $4);
        }
        if ( $line =~ /Buffer pool hit rate (\d+) \/ (\d+)/ ){
                ($cache_hit, $cache_total) = ($1, $2);
        }
    }

    my $cache_rate = 0;
    if ($cache_total && $cache_total > 0){
        $cache_rate = sprintf("%3.5f", $cache_hit / $cache_total * 100);
    }


    my %variable;
    my $varible_rows = $c->component('MySQL')->select_all(q!show variables!);
    foreach my $variable_row ( @$varible_rows ) {
        $variable{$variable_row->{Variable_name}} = $variable_row->{Value};
    }
    
    $variable{innodb_buffer_pool_size} = int $variable{innodb_buffer_pool_size} / (1024*1024);
    while($variable{innodb_buffer_pool_size} =~ s/(.*\d)(\d\d\d)/$1,$2/){} ;
    $variable{innodb_buffer_pool_size} .= "MB";
    $variable{innodb_flush_method} ||= 'fdatasync';

    my @sysinfo;
    map { my $key = $_; $key =~ s/^innodb_//; push @sysinfo, $key, $variable{$_} } grep { exists $variable{$_} } qw/
        innodb_version
        innodb_buffer_pool_size
        innodb_flush_method
        innodb_support_xa
        innodb_flush_log_at_trx_commit
        innodb_file_per_table
        innodb_file_format/;
    $c->ledge_set('sysinfo', \@sysinfo);

    return [$insert_row, $update_row, $delete_row, $read_row, 
            $insert_vel, $update_vel, $delete_vel, $read_vel, $cache_rate];
};

__DATA__
@@ row_count
DEF:my1=<%RRD%>:ir:AVERAGE
DEF:my2=<%RRD%>:ur:AVERAGE
DEF:my3=<%RRD%>:dr:AVERAGE
DEF:my4=<%RRD%>:rr:AVERAGE
CDEF:total=my1,my2,+,my3,+,my4,+
CDEF:my1r=my1,total,/,100,*
CDEF:my2r=my2,total,/,100,*
CDEF:my3r=my3,total,/,100,*
CDEF:my4r=my4,total,/,100,*
AREA:my1r#c0c0c0:Insert
GPRINT:my1r:LAST:Cur\:%5.1lf[%%]
GPRINT:my1r:AVERAGE:Ave\:%5.1lf[%%]
GPRINT:my1r:MAX:Max\:%5.1lf[%%]
GPRINT:my1r:MIN:Min\:%5.1lf[%%]\l
STACK:my2r#000080:Update
GPRINT:my2r:LAST:Cur\:%5.1lf[%%]
GPRINT:my2r:AVERAGE:Ave\:%5.1lf[%%]
GPRINT:my2r:MAX:Max\:%5.1lf[%%]
GPRINT:my2r:MIN:Min\:%5.1lf[%%]\l
STACK:my3r#008080:Delete
GPRINT:my3r:LAST:Cur\:%5.1lf[%%]
GPRINT:my3r:AVERAGE:Ave\:%5.1lf[%%]
GPRINT:my3r:MAX:Max\:%5.1lf[%%]
GPRINT:my3r:MIN:Min\:%5.1lf[%%]\l
STACK:my4r#800080:Read  
GPRINT:my4r:LAST:Cur\:%5.1lf[%%]
GPRINT:my4r:AVERAGE:Ave\:%5.1lf[%%]
GPRINT:my4r:MAX:Max\:%5.1lf[%%]
GPRINT:my4r:MIN:Min\:%5.1lf[%%]\l

@@ row_speed
DEF:my1=<%RRD%>:ir:AVERAGE
DEF:my2=<%RRD%>:ur:AVERAGE
DEF:my3=<%RRD%>:dr:AVERAGE
DEF:my4=<%RRD%>:rr:AVERAGE
LINE1:my1#CC0000:Insert
GPRINT:my1:LAST:Cur\:%6.1lf%s
GPRINT:my1:AVERAGE:Ave\:%6.1lf%s
GPRINT:my1:MAX:Max\:%6.1lf%s
GPRINT:my1:MIN:Min\:%6.1lf%s\l
LINE1:my2#000080:Update
GPRINT:my2:LAST:Cur\:%6.1lf%s
GPRINT:my2:AVERAGE:Ave\:%6.1lf%s
GPRINT:my2:MAX:Max\:%6.1lf%s
GPRINT:my2:MIN:Min\:%6.1lf%s\l
LINE1:my3#008080:Delete
GPRINT:my3:LAST:Cur\:%6.1lf%s
GPRINT:my3:AVERAGE:Ave\:%6.1lf%s
GPRINT:my3:MAX:Max\:%6.1lf%s
GPRINT:my3:MIN:Min\:%6.1lf%s\l
LINE1:my4#800080:Read  
GPRINT:my4:LAST:Cur\:%6.1lf%s
GPRINT:my4:AVERAGE:Ave\:%6.1lf%s
GPRINT:my4:MAX:Max\:%6.1lf%s
GPRINT:my4:MIN:Min\:%6.1lf%s\l

@@ cache
DEF:my1=<%RRD%>:cr:AVERAGE
AREA:my1#990000:Ratio
GPRINT:my1:LAST:Cur\:%5.1lf[%%]
GPRINT:my1:AVERAGE:Ave\:%5.1lf[%%]
GPRINT:my1:MAX:Max\:%5.1lf[%%]
GPRINT:my1:MIN:Min\:%5.1lf[%%]\l
LINE:100




