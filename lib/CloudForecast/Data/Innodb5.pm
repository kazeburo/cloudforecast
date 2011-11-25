package CloudForecast::Data::Innodb5;

use CloudForecast::Data -base;

rrds map { [ $_, 'DERIVE'] }  qw/ir ur dr rr/;
rrds map { [ $_, 'GAUGE'] }   qw/cr/;
rrds map { [ $_, 'COUNTER'] } qw/pr pw/;
rrds map { [ $_, 'GAUGE'] }   qw/dirtyr/;

graphs 'row_count',  'ROW OPERATIONS Count';
graphs 'row_speed',  'ROW OPERATIONS Speed';
graphs 'cache',      'Buffer pool hit rate';
graphs 'page_io',    'Page I/O count';
graphs 'dirty_rate', 'Dirty pages rate';

title {
    my $c = shift;
    my $title='MySQL 5 InnoDB';
    if ( my $port = $c->component('MySQL')->port ) {
        $title .= " (port=$port)";
    }
    return $title;
};

sysinfo {
    my $c = shift;
    $c->ledge_get('sysinfo') || [];
};

sub _select_all_show_statement {
    my $c = shift;
    my $query = shift;
    my %result;

    my $rows = $c->component('MySQL')->select_all($query);
    foreach my $row ( @$rows ) {
        $result{lc($row->{Variable_name})} = $row->{Value};
    }

    return %result;
}

fetcher {
    my $c = shift;

    my %variable = $c->_select_all_show_statement(q{show variables like 'innodb\_%'});
    my %status   = $c->_select_all_show_statement(q{show /*!50002 GLOBAL */ status like 'Innodb\_%'});


    my @sysinfo;
    $variable{innodb_flush_method} ||= 'fdatasync';

    map { my $key = $_; $key =~ s/^innodb_//; push @sysinfo, $key, $variable{$_} } grep { exists $variable{$_} } qw(
        innodb_version
        innodb_flush_method
        innodb_support_xa
        innodb_flush_log_at_trx_commit
        innodb_file_per_table
        innodb_file_format
        innodb_doublewrite
        );
    map { my $key = $_; $key =~ s/^innodb_//; push @sysinfo, $key, $status{$_} } grep { exists $status{$_} } qw(
        innodb_page_size
        );

    my $buffer_pool_size = int $variable{innodb_buffer_pool_size} / (1024*1024);
    while($buffer_pool_size =~ s/(.*\d)(\d\d\d)/$1,$2/){} ;
    $buffer_pool_size .= "MB";
    push @sysinfo, 'buffer_pool_size', $buffer_pool_size;

    $c->ledge_set('sysinfo', \@sysinfo);


    my $buffer_pool_hit_rate = sprintf "%.2f",
        (1.0 - $status{"innodb_buffer_pool_reads"} / $status{"innodb_buffer_pool_read_requests"}) * 100;

    my $buffer_pool_dirty_pages_rate = sprintf "%.2f",
        $status{"innodb_buffer_pool_pages_dirty"} / $status{"innodb_buffer_pool_pages_data"} * 100.0;

    # Should substruct Innodb_dblwr_writes from Innodb_pages_written?
    return [
        (map { $status{$_}} qw(innodb_rows_inserted innodb_rows_updated innodb_rows_deleted innodb_rows_read)),
        $buffer_pool_hit_rate,
        $status{innodb_pages_read}, $status{innodb_pages_written},
        $buffer_pool_dirty_pages_rate
       ];
};

=encoding utf-8

=head1 NAME

CloudForecast::Data::Innodb5 - monitor InnoDB for MySQL 5

=head1 SYNOPSIS

    component_config:
    resources:
      - innodb5

=head1 DESCRIPTION

monitor various InnoDB statuses. requires >= MySQL 5.0.

=head1 AUTHOR

HIROSE Masaaki E<lt>hirose31@gmail.comE<gt>

=head1 SEE ALSO

resouces on Innodb_pages_read and Innodb_pages_written:

L<http://www.facebook.com/notes/mysql-at-facebook/innodb-disk-io-counters-in-show-status/445139830932>

L<http://forums.innodb.com/read.php?4,1228,1233>

=cut

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
GPRINT:my1r:LAST:Cur\: %5.1lf[%%]
GPRINT:my1r:AVERAGE:Ave\: %5.1lf[%%]
GPRINT:my1r:MAX:Max\: %5.1lf[%%]
GPRINT:my1r:MIN:Min\: %5.1lf[%%]\l
STACK:my2r#000080:Update
GPRINT:my2r:LAST:Cur\: %5.1lf[%%]
GPRINT:my2r:AVERAGE:Ave\: %5.1lf[%%]
GPRINT:my2r:MAX:Max\: %5.1lf[%%]
GPRINT:my2r:MIN:Min\: %5.1lf[%%]\l
STACK:my3r#008080:Delete
GPRINT:my3r:LAST:Cur\: %5.1lf[%%]
GPRINT:my3r:AVERAGE:Ave\: %5.1lf[%%]
GPRINT:my3r:MAX:Max\: %5.1lf[%%]
GPRINT:my3r:MIN:Min\: %5.1lf[%%]\l
STACK:my4r#800080:Read  
GPRINT:my4r:LAST:Cur\: %5.1lf[%%]
GPRINT:my4r:AVERAGE:Ave\: %5.1lf[%%]
GPRINT:my4r:MAX:Max\: %5.1lf[%%]
GPRINT:my4r:MIN:Min\: %5.1lf[%%]\l

@@ row_speed
DEF:my1=<%RRD%>:ir:AVERAGE
DEF:my2=<%RRD%>:ur:AVERAGE
DEF:my3=<%RRD%>:dr:AVERAGE
DEF:my4=<%RRD%>:rr:AVERAGE
LINE1:my1#CC0000:Insert
GPRINT:my1:LAST:Cur\: %6.1lf
GPRINT:my1:AVERAGE:Ave\: %6.1lf
GPRINT:my1:MAX:Max\: %6.1lf
GPRINT:my1:MIN:Min\: %6.1lf\c
LINE1:my2#000080:Update
GPRINT:my2:LAST:Cur\: %6.1lf
GPRINT:my2:AVERAGE:Ave\: %6.1lf
GPRINT:my2:MAX:Max\: %6.1lf
GPRINT:my2:MIN:Min\: %6.1lf\c
LINE1:my3#008080:Delete
GPRINT:my3:LAST:Cur\: %6.1lf
GPRINT:my3:AVERAGE:Ave\: %6.1lf
GPRINT:my3:MAX:Max\: %6.1lf
GPRINT:my3:MIN:Min\: %6.1lf\c
LINE1:my4#800080:Read  
GPRINT:my4:LAST:Cur\: %6.1lf
GPRINT:my4:AVERAGE:Ave\: %6.1lf
GPRINT:my4:MAX:Max\: %6.1lf
GPRINT:my4:MIN:Min\: %6.1lf\c

@@ cache
DEF:my1=<%RRD%>:cr:AVERAGE
AREA:my1#990000:Hit Rate
GPRINT:my1:LAST:Cur\: %5.1lf
GPRINT:my1:AVERAGE:Ave\: %5.1lf
GPRINT:my1:MAX:Max\: %5.1lf
GPRINT:my1:MIN:Min\: %5.1lf [%%]\c
LINE:100

@@ dirty_rate
DEF:my1=<%RRD%>:dirtyr:AVERAGE
AREA:my1#5a2b09:Dirty pages rate
GPRINT:my1:LAST:Cur\:%5.1lf
GPRINT:my1:AVERAGE:Ave\:%5.1lf
GPRINT:my1:MAX:Max\:%5.1lf
GPRINT:my1:MIN:Min\:%5.1lf [%%]\c
LINE:100

@@ page_io
DEF:my1=<%RRD%>:pr:AVERAGE
DEF:my2r=<%RRD%>:pw:AVERAGE
CDEF:my2=my2r,-1,*
LINE1:my1#c0c0c0:Read 
GPRINT:my1:LAST:Cur\: %5.1lf%s
GPRINT:my1:AVERAGE:Ave\: %5.1lf%s
GPRINT:my1:MAX:Max\: %5.1lf%s
GPRINT:my1:MIN:Min\: %5.1lf%s\c
LINE1:my2#800080:Write
GPRINT:my2r:LAST:Cur\: %5.1lf%s
GPRINT:my2r:AVERAGE:Ave\: %5.1lf%s
GPRINT:my2r:MAX:Max\: %5.1lf%s
GPRINT:my2r:MIN:Min\: %5.1lf%s\c
