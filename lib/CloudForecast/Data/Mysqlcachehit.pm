package CloudForecast::Data::Mysqlcachehit;

use CloudForecast::Data -base;

rrds map { [ $_, 'GAUGE'] }
    qw(
          key_cache
          query_cache
          tablelock_immediate
          thread_cache
          tmp_table_on_memory
     );

graphs 'cachehit',  'Cache hit rate';

title {
    my $c = shift;
    my $title='MySQL Cache hit rate';
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

sub _unit {
    my $n = shift;
    my($base, $unit);

    return $n unless $n =~ /^\d+$/;
    if ($n >= 1073741824) {
        $base = 1073741824;
        $unit = 'GB';
    } elsif ($n >= 1048576) {
        $base = 1048576;
        $unit = 'MB';
    } elsif ($n >= 1024) {
        $base = 1024;
        $unit = 'KB';
    } else {
        $base = 1;
        $unit = 'B';
    }

    $n = sprintf '%.2f', $n/$base;
    while($n =~ s/(.*\d)(\d\d\d)/$1,$2/){};

    return $n.$unit;
}

fetcher {
    my $c = shift;

    my %variable = $c->_select_all_show_statement(q{show variables});
    my %status   = $c->_select_all_show_statement(q{show /*!50002 GLOBAL */ status});


    my @sysinfo;
    map {
        my $key = $_;
        my $val = $key =~ /_size$/ ? _unit($variable{$_}) : $variable{$_};
        push @sysinfo, $key, $val;
    } grep { exists $variable{$_} }
        qw(
              key_buffer_size
              query_cache_size
              query_cache_type
              thread_cache_size
              thread_concurrency
              tmp_table_size
         );
    $c->ledge_set('sysinfo', \@sysinfo);


    my $key_cache            = sprintf '%.2f',
        (1.0 - $status{'key_reads'} / ( $status{'key_read_requests'} || 1 ) ) * 100;

    my $query_cache          = sprintf '%.2f',
        ($status{'qcache_hits'} / ( ($status{'qcache_inserts'} + $status{'qcache_hits'} + $status{'qcache_not_cached'}) || 1 ) ) * 100;

    my $table_lock_immediate = sprintf '%.2f',
        ($status{'table_locks_immediate'} / ( ($status{'table_locks_immediate'} + $status{'table_locks_waited'}) || 1 ) ) * 100;

    my $thread_cache         = sprintf '%.2f',
        (1.0 - $status{'threads_created'} / ( $status{'connections'} || 1 ) ) * 100;

    my $tmp_table_on_memory  = sprintf '%.2f',
        ($status{'created_tmp_tables'} / (($status{'created_tmp_tables'} + $status{'created_tmp_disk_tables'}) || 1) ) * 100;

    return [
        $key_cache,
        $query_cache,
        $table_lock_immediate,
        $thread_cache,
        $tmp_table_on_memory,
       ];
};

=encoding utf-8

=head1 NAME

CloudForecast::Data::Mysqlcachehit - monitor various cache hit rate

=head1 SYNOPSIS

    component_config:
    resources:
      - mysqlcachehit

=head1 DESCRIPTION

monitor various cache hit rate

=head1 AUTHOR

HIROSE Masaaki E<lt>hirose31@gmail.comE<gt>

=cut

__DATA__
@@ cachehit
DEF:my1=<%RRD%>:key_cache:AVERAGE
DEF:my2=<%RRD%>:query_cache:AVERAGE
DEF:my3=<%RRD%>:tablelock_immediate:AVERAGE
DEF:my4=<%RRD%>:thread_cache:AVERAGE
DEF:my5=<%RRD%>:tmp_table_on_memory:AVERAGE
COMMENT:                           Cur    Ave     Max    Min\l
LINE1:my1#ff8000:key cache            
GPRINT:my1:LAST:%5.1lf
GPRINT:my1:AVERAGE:%5.1lf
GPRINT:my1:MAX:%5.1lf
GPRINT:my1:MIN:%5.1lf [%%]\l
LINE1:my2#00FF00:query cache          
GPRINT:my2:LAST:%5.1lf
GPRINT:my2:AVERAGE:%5.1lf
GPRINT:my2:MAX:%5.1lf
GPRINT:my2:MIN:%5.1lf [%%]\l
LINE1:my3#00FFFF:table lock immediate 
GPRINT:my3:LAST:%5.1lf
GPRINT:my3:AVERAGE:%5.1lf
GPRINT:my3:MAX:%5.1lf
GPRINT:my3:MIN:%5.1lf [%%]\l
LINE1:my4#0000FF:thread cache         
GPRINT:my4:LAST:%5.1lf
GPRINT:my4:AVERAGE:%5.1lf
GPRINT:my4:MAX:%5.1lf
GPRINT:my4:MIN:%5.1lf [%%]\l
LINE1:my5#800080:tmp table on memory  
GPRINT:my5:LAST:%5.1lf
GPRINT:my5:AVERAGE:%5.1lf
GPRINT:my5:MAX:%5.1lf
GPRINT:my5:MIN:%5.1lf [%%]\l
