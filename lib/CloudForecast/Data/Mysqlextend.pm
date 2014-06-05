package CloudForecast::Data::Mysqlextend;

use CloudForecast::Data -base;

rrds map { [ $_, 'DERIVE' ] } qw/cd ci cr cs cu sq/;
rrds map { [ $_, 'GAUGE' ] } qw/cac con run/;

# porting from percona-monitoring-plugins
# http://www.percona.com/doc/percona-monitoring-plugins/cacti/mysql-templates.html
# MyISAM Indexes
extend_rrd 'key_read_requests', 'DERIVE';
extend_rrd 'key_reads', 'DERIVE';
extend_rrd 'key_write_requests', 'DERIVE';
extend_rrd 'key_writes', 'DERIVE';
# MySQL Handlers
extend_rrd 'handler_write', 'DERIVE';
extend_rrd 'handler_update', 'DERIVE';
extend_rrd 'handler_delete', 'DERIVE';
extend_rrd 'handler_read_first', 'DERIVE';
extend_rrd 'handler_read_key', 'DERIVE';
extend_rrd 'handler_read_next', 'DERIVE';
extend_rrd 'handler_read_prev', 'DERIVE';
extend_rrd 'handler_read_rnd', 'DERIVE';
extend_rrd 'handler_red_rnd_nxt', 'DERIVE';
# MySQL Select Types
extend_rrd 'select_full_join', 'DERIVE';
extend_rrd 'select_full_rnge_jn', 'DERIVE';
extend_rrd 'select_range', 'DERIVE';
extend_rrd 'select_range_check', 'DERIVE';
extend_rrd 'select_scan', 'DERIVE';
# MySQL Sorts
extend_rrd 'sort_rows', 'DERIVE';
extend_rrd 'sort_range', 'DERIVE';
extend_rrd 'sort_merge_passes', 'DERIVE';
extend_rrd 'sort_scan', 'DERIVE';
# MySQL Temporary Objects
extend_rrd 'created_tmp_tables', 'DERIVE';
extend_rrd 'creatd_tmp_dsk_tbls', 'DERIVE';
extend_rrd 'created_tmp_files', 'DERIVE';
# MySQL Transaction Handler
extend_rrd 'handler_commit', 'DERIVE';
extend_rrd 'handler_rollback', 'DERIVE';
extend_rrd 'handler_savepoint', 'DERIVE';
extend_rrd 'handlr_svpnt_rllbck', 'GAUGE';
# MySQL Processlist
extend_rrd 'state_closing_tabls', 'GAUGE';
extend_rrd 'ste_cpyng_to_tp_tbl', 'GAUGE';
extend_rrd 'state_end', 'GAUGE';
extend_rrd 'state_freeing_items', 'GAUGE';
extend_rrd 'state_init', 'GAUGE';
extend_rrd 'state_locked', 'GAUGE';
extend_rrd 'state_login', 'GAUGE';
extend_rrd 'state_preparing', 'GAUGE';
extend_rrd 'state_readng_frm_nt', 'GAUGE';
extend_rrd 'state_sending_data', 'GAUGE';
extend_rrd 'state_sorting_reslt', 'GAUGE';
extend_rrd 'state_statistics', 'GAUGE';
extend_rrd 'state_updating', 'GAUGE';
extend_rrd 'state_writing_to_nt', 'GAUGE';
extend_rrd 'state_none', 'GAUGE';
extend_rrd 'state_other', 'GAUGE';

graphs 'rate' => 'MySQL Queries Rate';
graphs 'count' => 'MySQL Queries Count';
graphs 'slow' => 'MySQL Slow Queries';
graphs 'thread' => 'MySQL Threads';

graphs 'mysql_processlist','MySQL Processlist';
graphs 'myisam_indexes','MyISAM Indexes';
graphs 'mysql_handlers','MySQL Handlers';
graphs 'mysql_select_types','MySQL Select Types';
graphs 'mysql_sorts','MySQL Sorts';
graphs 'mysql_temporary_objects','MySQL Temporary Objects';
graphs 'mysql_transaction_handler','MySQL Transaction Handler';

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
            qw/max_connections max_connect_errors thread_cache_size slow_query_log log_slow_queries long_query_time log_queries_not_using_indexes/;
        
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
        $status{lc($row->{Variable_name})} = $row->{Value};
    }

    my %variable;
    my $varible_rows = $mysql->select_all(q!show variables!);
    foreach my $variable_row ( @$varible_rows ) {
        $variable{$variable_row->{Variable_name}} = $variable_row->{Value};
    }

    my %state = (
        'state_closing_tables'       => 0,
        'state_copying_to_tmp_table' => 0,
        'state_end'                  => 0,
        'state_freeing_items'        => 0,
        'state_init'                 => 0,
        'state_locked'               => 0,
        'state_login'                => 0,
        'state_preparing'            => 0,
        'state_reading_from_net'     => 0,
        'state_sending_data'         => 0,
        'state_sorting_result'       => 0,
        'state_statistics'           => 0,
        'state_updating'             => 0,
        'state_writing_to_net'       => 0,
        'state_none'                 => 0,
        'state_other'                => 0, # everything not listed above
    );
    my $state_rows = $mysql->select_all(q!SHOW PROCESSLIST!);
    foreach my $state_row ( @$state_rows ) {
        my $st = $state_row->{State};
        if (! defined $st) {
            $st = 'NULL';
        } elsif ($st eq "") {
            $st = 'none';
        }
        # MySQL 5.5 replaces the 'Locked' state with a variety of "Waiting for
        # X lock" types of statuses.  Wrap these all back into "Locked" because
        # we don't really care about the type of locking it is.
        if ($st =~ /^(Table lock|Waiting for .*lock)$/) {
            $st = 'Locked';
        } elsif ($st eq "update") {
            $st = 'updating';
        }
        $st =~ s/\s+/_/g;
        $st = lc $st;
        if (exists $state{"state_$st"}) {
            $state{"state_$st"}++;
        } else {
            $state{"state_other"}++;
        }
    }

    my %sysinfo;   
    $sysinfo{uptime} = $status{uptime} || 0;
    map { $sysinfo{$_} = $variable{$_} } grep { exists $variable{$_} }
        qw/version version_comment slow_query_log log_slow_queries long_query_time log_queries_not_using_indexes max_connections max_connect_errors thread_cache_size/;
    delete $sysinfo{log_slow_queries} if exists $sysinfo{log_slow_queries} && exists $sysinfo{slow_query_log};
    $c->ledge_set('sysinfo', \%sysinfo );

    return [ (map { $status{$_} }
                 qw/
                       com_delete com_insert com_replace com_select com_update slow_queries
                       threads_cached threads_connected threads_running
                       key_read_requests key_reads key_write_requests key_writes
                       handler_write handler_update handler_delete handler_read_first handler_read_key handler_read_next handler_read_prev handler_read_rnd handler_read_rnd_next
                       select_full_join select_full_range_join select_range select_range_check select_scan
                       sort_rows sort_range sort_merge_passes sort_scan
                       created_tmp_tables created_tmp_disk_tables created_tmp_files
                       handler_commit handler_rollback handler_savepoint handler_savepoint_rollback
                   /),
             @state{qw(
                          state_closing_tables
                          state_copying_to_tmp_table
                          state_end
                          state_freeing_items
                          state_init
                          state_locked
                          state_login
                          state_preparing
                          state_reading_from_net
                          state_sending_data
                          state_sorting_result
                          state_statistics
                          state_updating
                          state_writing_to_net
                          state_none
                          state_other
                  )},
         ];
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
GPRINT:my1r:LAST:Cur\:%5.1lf[%%]
GPRINT:my1r:AVERAGE:Ave\:%5.1lf[%%]
GPRINT:my1r:MAX:Max\:%5.1lf[%%]
GPRINT:my1r:MIN:Min\:%5.1lf[%%]\l
STACK:my2r#000080:Insert 
GPRINT:my2r:LAST:Cur\:%5.1lf[%%]
GPRINT:my2r:AVERAGE:Ave\:%5.1lf[%%]
GPRINT:my2r:MAX:Max\:%5.1lf[%%]
GPRINT:my2r:MIN:Min\:%5.1lf[%%]\l
STACK:my3r#008080:Replace
GPRINT:my3r:LAST:Cur\:%5.1lf[%%]
GPRINT:my3r:AVERAGE:Ave\:%5.1lf[%%]
GPRINT:my3r:MAX:Max\:%5.1lf[%%]
GPRINT:my3r:MIN:Min\:%5.1lf[%%]\l
STACK:my4r#800080:Update 
GPRINT:my4r:LAST:Cur\:%5.1lf[%%]
GPRINT:my4r:AVERAGE:Ave\:%5.1lf[%%]
GPRINT:my4r:MAX:Max\:%5.1lf[%%]
GPRINT:my4r:MIN:Min\:%5.1lf[%%]\l
STACK:my5r#C0C000:Delete 
GPRINT:my5r:LAST:Cur\:%5.1lf[%%]
GPRINT:my5r:AVERAGE:Ave\:%5.1lf[%%]
GPRINT:my5r:MAX:Max\:%5.1lf[%%]
GPRINT:my5r:MIN:Min\:%5.1lf[%%]\l

@@ count
DEF:my1=<%RRD%>:cs:AVERAGE
DEF:my2=<%RRD%>:ci:AVERAGE
DEF:my3=<%RRD%>:cr:AVERAGE
DEF:my4=<%RRD%>:cu:AVERAGE
DEF:my5=<%RRD%>:cd:AVERAGE
AREA:my1#c0c0c0:Select 
GPRINT:my1:LAST:Cur\:%7.1lf
GPRINT:my1:AVERAGE:Ave\:%7.1lf
GPRINT:my1:MAX:Max\:%7.1lf
GPRINT:my1:MIN:Min\:%7.1lf\l
STACK:my2#000080:Insert 
GPRINT:my2:LAST:Cur\:%7.1lf
GPRINT:my2:AVERAGE:Ave\:%7.1lf
GPRINT:my2:MAX:Max\:%7.1lf
GPRINT:my2:MIN:Min\:%7.1lf\l
STACK:my3#008080:Replace
GPRINT:my3:LAST:Cur\:%7.1lf
GPRINT:my3:AVERAGE:Ave\:%7.1lf
GPRINT:my3:MAX:Max\:%7.1lf
GPRINT:my3:MIN:Min\:%7.1lf\l
STACK:my4#800080:Update 
GPRINT:my4:LAST:Cur\:%7.1lf
GPRINT:my4:AVERAGE:Ave\:%7.1lf
GPRINT:my4:MAX:Max\:%7.1lf
GPRINT:my4:MIN:Min\:%7.1lf\l
STACK:my5#C0C000:Delete 
GPRINT:my5:LAST:Cur\:%7.1lf
GPRINT:my5:AVERAGE:Ave\:%7.1lf
GPRINT:my5:MAX:Max\:%7.1lf
GPRINT:my5:MIN:Min\:%7.1lf\l

@@ slow
DEF:my1=<%RRD%>:sq:AVERAGE
AREA:my1#00c000:Query
GPRINT:my1:LAST:Cur\:%7.3lf
GPRINT:my1:AVERAGE:Ave\:%7.3lf
GPRINT:my1:MAX:Max\:%7.3lf
GPRINT:my1:MIN:Min\:%7.3lf\l

@@ thread
DEF:my1=<%RRD%>:cac:AVERAGE
DEF:my2=<%RRD%>:con:AVERAGE
DEF:my3=<%RRD%>:run:AVERAGE
LINE1:my1#CC0000:Cached   
GPRINT:my1:LAST:Cur\:%6.1lf
GPRINT:my1:AVERAGE:Ave\:%6.1lf
GPRINT:my1:MAX:Max\:%6.1lf
GPRINT:my1:MIN:Min\:%6.1lf\l
LINE1:my2#000080:Connected
GPRINT:my2:LAST:Cur\:%6.1lf
GPRINT:my2:AVERAGE:Ave\:%6.1lf
GPRINT:my2:MAX:Max\:%6.1lf
GPRINT:my2:MIN:Min\:%6.1lf\l
LINE1:my3#008080:Running  
GPRINT:my3:LAST:Cur\:%6.1lf
GPRINT:my3:AVERAGE:Ave\:%6.1lf
GPRINT:my3:MAX:Max\:%6.1lf
GPRINT:my3:MIN:Min\:%6.1lf\l

@@ myisam_indexes
DEF:key_read_requests=<%RRD_EXTEND key_read_requests %>:key_read_requests:AVERAGE
DEF:key_reads=<%RRD_EXTEND key_reads %>:key_reads:AVERAGE
DEF:key_write_requests=<%RRD_EXTEND key_write_requests %>:key_write_requests:AVERAGE
DEF:key_writes=<%RRD_EXTEND key_writes %>:key_writes:AVERAGE
AREA:key_read_requests#157419:Key Read Requests 
GPRINT:key_read_requests:LAST:Cur\: %5.1lf
GPRINT:key_read_requests:AVERAGE:Ave\: %5.1lf
GPRINT:key_read_requests:MAX:Max\: %5.1lf\l
LINE1:key_reads#AFECED:Key Reads         
GPRINT:key_reads:LAST:Cur\: %5.1lf
GPRINT:key_reads:AVERAGE:Ave\: %5.1lf
GPRINT:key_reads:MAX:Max\: %5.1lf\l
AREA:key_write_requests#862F2F:Key Write Requests
GPRINT:key_write_requests:LAST:Cur\: %5.1lf
GPRINT:key_write_requests:AVERAGE:Ave\: %5.1lf
GPRINT:key_write_requests:MAX:Max\: %5.1lf\l
LINE1:key_writes#F51D30:Key Writes        
GPRINT:key_writes:LAST:Cur\: %5.1lf
GPRINT:key_writes:AVERAGE:Ave\: %5.1lf
GPRINT:key_writes:MAX:Max\: %5.1lf\l

@@ mysql_handlers
DEF:handler_write=<%RRD_EXTEND handler_write %>:handler_write:AVERAGE
DEF:handler_update=<%RRD_EXTEND handler_update %>:handler_update:AVERAGE
DEF:handler_delete=<%RRD_EXTEND handler_delete %>:handler_delete:AVERAGE
DEF:handler_read_first=<%RRD_EXTEND handler_read_first %>:handler_read_first:AVERAGE
DEF:handler_read_key=<%RRD_EXTEND handler_read_key %>:handler_read_key:AVERAGE
DEF:handler_read_next=<%RRD_EXTEND handler_read_next %>:handler_read_next:AVERAGE
DEF:handler_read_prev=<%RRD_EXTEND handler_read_prev %>:handler_read_prev:AVERAGE
DEF:handler_read_rnd=<%RRD_EXTEND handler_read_rnd %>:handler_read_rnd:AVERAGE
DEF:handler_red_rnd_nxt=<%RRD_EXTEND handler_red_rnd_nxt %>:handler_red_rnd_nxt:AVERAGE
AREA:handler_write#4D4A47:Handler Write        
GPRINT:handler_write:LAST:Cur\: %7.1lf
GPRINT:handler_write:AVERAGE:Ave\: %7.1lf
GPRINT:handler_write:MAX:Max\: %7.1lf\l
STACK:handler_update#C79F71:Handler Update       
GPRINT:handler_update:LAST:Cur\: %7.1lf
GPRINT:handler_update:AVERAGE:Ave\: %7.1lf
GPRINT:handler_update:MAX:Max\: %7.1lf\l
STACK:handler_delete#BDB8B3:Handler Delete       
GPRINT:handler_delete:LAST:Cur\: %7.1lf
GPRINT:handler_delete:AVERAGE:Ave\: %7.1lf
GPRINT:handler_delete:MAX:Max\: %7.1lf\l
STACK:handler_read_first#8C286E:Handler Read First   
GPRINT:handler_read_first:LAST:Cur\: %7.1lf
GPRINT:handler_read_first:AVERAGE:Ave\: %7.1lf
GPRINT:handler_read_first:MAX:Max\: %7.1lf\l
STACK:handler_read_key#BAB27F:Handler Read Key     
GPRINT:handler_read_key:LAST:Cur\: %7.1lf
GPRINT:handler_read_key:AVERAGE:Ave\: %7.1lf
GPRINT:handler_read_key:MAX:Max\: %7.1lf\l
STACK:handler_read_next#C02942:Handler Read Next    
GPRINT:handler_read_next:LAST:Cur\: %7.1lf
GPRINT:handler_read_next:AVERAGE:Ave\: %7.1lf
GPRINT:handler_read_next:MAX:Max\: %7.1lf\l
STACK:handler_read_prev#FA6900:Handler Read Prev    
GPRINT:handler_read_prev:LAST:Cur\: %7.1lf
GPRINT:handler_read_prev:AVERAGE:Ave\: %7.1lf
GPRINT:handler_read_prev:MAX:Max\: %7.1lf\l
STACK:handler_read_rnd#5A3D31:Handler Read Rnd     
GPRINT:handler_read_rnd:LAST:Cur\: %7.1lf
GPRINT:handler_read_rnd:AVERAGE:Ave\: %7.1lf
GPRINT:handler_read_rnd:MAX:Max\: %7.1lf\l
STACK:handler_red_rnd_nxt#69D2E7:Handler Read Rnd Next
GPRINT:handler_red_rnd_nxt:LAST:Cur\: %7.1lf
GPRINT:handler_red_rnd_nxt:AVERAGE:Ave\: %7.1lf
GPRINT:handler_red_rnd_nxt:MAX:Max\: %7.1lf\l

@@ mysql_select_types
DEF:select_full_join=<%RRD_EXTEND select_full_join %>:select_full_join:AVERAGE
DEF:select_full_rnge_jn=<%RRD_EXTEND select_full_rnge_jn %>:select_full_rnge_jn:AVERAGE
DEF:select_range=<%RRD_EXTEND select_range %>:select_range:AVERAGE
DEF:select_range_check=<%RRD_EXTEND select_range_check %>:select_range_check:AVERAGE
DEF:select_scan=<%RRD_EXTEND select_scan %>:select_scan:AVERAGE
AREA:select_full_join#3D1500:Select Full Join      
GPRINT:select_full_join:LAST:Cur\: %5.1lf
GPRINT:select_full_join:AVERAGE:Ave\: %5.1lf
GPRINT:select_full_join:MAX:Max\: %5.1lf\l
STACK:select_full_rnge_jn#AA3B27:Select Full Range Join
GPRINT:select_full_rnge_jn:LAST:Cur\: %5.1lf
GPRINT:select_full_rnge_jn:AVERAGE:Ave\: %5.1lf
GPRINT:select_full_rnge_jn:MAX:Max\: %5.1lf\l
STACK:select_range#EDAA41:Select Range          
GPRINT:select_range:LAST:Cur\: %5.1lf
GPRINT:select_range:AVERAGE:Ave\: %5.1lf
GPRINT:select_range:MAX:Max\: %5.1lf\l
STACK:select_range_check#13343B:Select Range Check    
GPRINT:select_range_check:LAST:Cur\: %5.1lf
GPRINT:select_range_check:AVERAGE:Ave\: %5.1lf
GPRINT:select_range_check:MAX:Max\: %5.1lf\l
STACK:select_scan#686240:Select Scan           
GPRINT:select_scan:LAST:Cur\: %5.1lf
GPRINT:select_scan:AVERAGE:Ave\: %5.1lf
GPRINT:select_scan:MAX:Max\: %5.1lf\l

@@ mysql_sorts
DEF:sort_rows=<%RRD_EXTEND sort_rows %>:sort_rows:AVERAGE
DEF:sort_range=<%RRD_EXTEND sort_range %>:sort_range:AVERAGE
DEF:sort_merge_passes=<%RRD_EXTEND sort_merge_passes %>:sort_merge_passes:AVERAGE
DEF:sort_scan=<%RRD_EXTEND sort_scan %>:sort_scan:AVERAGE
AREA:sort_rows#FFAB00:Sort Rows        
GPRINT:sort_rows:LAST:Cur\: %5.1lf
GPRINT:sort_rows:AVERAGE:Ave\: %5.1lf
GPRINT:sort_rows:MAX:Max\: %5.1lf\l
LINE1:sort_range#157419:Sort Range       
GPRINT:sort_range:LAST:Cur\: %5.1lf
GPRINT:sort_range:AVERAGE:Ave\: %5.1lf
GPRINT:sort_range:MAX:Max\: %5.1lf\l
LINE1:sort_merge_passes#DA4725:Sort Merge Passes
GPRINT:sort_merge_passes:LAST:Cur\: %5.1lf
GPRINT:sort_merge_passes:AVERAGE:Ave\: %5.1lf
GPRINT:sort_merge_passes:MAX:Max\: %5.1lf\l
LINE1:sort_scan#4444FF:Sort Scan        
GPRINT:sort_scan:LAST:Cur\: %5.1lf
GPRINT:sort_scan:AVERAGE:Ave\: %5.1lf
GPRINT:sort_scan:MAX:Max\: %5.1lf\l

@@ mysql_temporary_objects
DEF:created_tmp_tables=<%RRD_EXTEND created_tmp_tables %>:created_tmp_tables:AVERAGE
DEF:creatd_tmp_dsk_tbls=<%RRD_EXTEND creatd_tmp_dsk_tbls %>:creatd_tmp_dsk_tbls:AVERAGE
DEF:created_tmp_files=<%RRD_EXTEND created_tmp_files %>:created_tmp_files:AVERAGE
AREA:created_tmp_tables#FFAB00:Created Tmp Tables     \l
LINE1:created_tmp_tables#837C04:Created Tmp Tables     
GPRINT:created_tmp_tables:LAST:Cur\: %5.1lf
GPRINT:created_tmp_tables:AVERAGE:Ave\: %5.1lf
GPRINT:created_tmp_tables:MAX:Max\: %5.1lf\l
LINE1:creatd_tmp_dsk_tbls#F51D30:Created Tmp Disk Tables
GPRINT:creatd_tmp_dsk_tbls:LAST:Cur\: %5.1lf
GPRINT:creatd_tmp_dsk_tbls:AVERAGE:Ave\: %5.1lf
GPRINT:creatd_tmp_dsk_tbls:MAX:Max\: %5.1lf\l
LINE2:created_tmp_files#157419:Created Tmp Files      
GPRINT:created_tmp_files:LAST:Cur\: %5.1lf
GPRINT:created_tmp_files:AVERAGE:Ave\: %5.1lf
GPRINT:created_tmp_files:MAX:Max\: %5.1lf\l

@@ mysql_transaction_handler
DEF:handler_commit=<%RRD_EXTEND handler_commit %>:handler_commit:AVERAGE
DEF:handler_rollback=<%RRD_EXTEND handler_rollback %>:handler_rollback:AVERAGE
DEF:handler_savepoint=<%RRD_EXTEND handler_savepoint %>:handler_savepoint:AVERAGE
DEF:handlr_svpnt_rllbck=<%RRD_EXTEND handlr_svpnt_rllbck %>:handlr_svpnt_rllbck:AVERAGE
LINE1:handler_commit#DE0056:Handler Commit            
GPRINT:handler_commit:LAST:Cur\: %6.1lf
GPRINT:handler_commit:AVERAGE:Ave\: %6.1lf
GPRINT:handler_commit:MAX:Max\: %6.1lf\l
LINE1:handler_rollback#784890:Handler Rollback          
GPRINT:handler_rollback:LAST:Cur\: %6.1lf
GPRINT:handler_rollback:AVERAGE:Ave\: %6.1lf
GPRINT:handler_rollback:MAX:Max\: %6.1lf\l
LINE1:handler_savepoint#D1642E:Handler Savepoint         
GPRINT:handler_savepoint:LAST:Cur\: %6.1lf
GPRINT:handler_savepoint:AVERAGE:Ave\: %6.1lf
GPRINT:handler_savepoint:MAX:Max\: %6.1lf\l
LINE1:handlr_svpnt_rllbck#487860:Handler Savepoint Rollback
GPRINT:handlr_svpnt_rllbck:LAST:Cur\: %6.1lf
GPRINT:handlr_svpnt_rllbck:AVERAGE:Ave\: %6.1lf
GPRINT:handlr_svpnt_rllbck:MAX:Max\: %6.1lf\l

@@ mysql_processlist
DEF:state_closing_tabls=<%RRD_EXTEND state_closing_tabls %>:state_closing_tabls:AVERAGE
DEF:ste_cpyng_to_tp_tbl=<%RRD_EXTEND ste_cpyng_to_tp_tbl %>:ste_cpyng_to_tp_tbl:AVERAGE
DEF:state_end=<%RRD_EXTEND state_end %>:state_end:AVERAGE
DEF:state_freeing_items=<%RRD_EXTEND state_freeing_items %>:state_freeing_items:AVERAGE
DEF:state_init=<%RRD_EXTEND state_init %>:state_init:AVERAGE
DEF:state_locked=<%RRD_EXTEND state_locked %>:state_locked:AVERAGE
DEF:state_login=<%RRD_EXTEND state_login %>:state_login:AVERAGE
DEF:state_preparing=<%RRD_EXTEND state_preparing %>:state_preparing:AVERAGE
DEF:state_readng_frm_nt=<%RRD_EXTEND state_readng_frm_nt %>:state_readng_frm_nt:AVERAGE
DEF:state_sending_data=<%RRD_EXTEND state_sending_data %>:state_sending_data:AVERAGE
DEF:state_sorting_reslt=<%RRD_EXTEND state_sorting_reslt %>:state_sorting_reslt:AVERAGE
DEF:state_statistics=<%RRD_EXTEND state_statistics %>:state_statistics:AVERAGE
DEF:state_updating=<%RRD_EXTEND state_updating %>:state_updating:AVERAGE
DEF:state_writing_to_nt=<%RRD_EXTEND state_writing_to_nt %>:state_writing_to_nt:AVERAGE
DEF:state_none=<%RRD_EXTEND state_none %>:state_none:AVERAGE
DEF:state_other=<%RRD_EXTEND state_other %>:state_other:AVERAGE
AREA:state_closing_tabls#DE0056:State Closing Tables      
GPRINT:state_closing_tabls:LAST:Cur\: %6.1lf
GPRINT:state_closing_tabls:AVERAGE:Ave\: %6.1lf
GPRINT:state_closing_tabls:MAX:Max\: %6.1lf\l
STACK:ste_cpyng_to_tp_tbl#784890:State Copying To Tmp Table
GPRINT:ste_cpyng_to_tp_tbl:LAST:Cur\: %6.1lf
GPRINT:ste_cpyng_to_tp_tbl:AVERAGE:Ave\: %6.1lf
GPRINT:ste_cpyng_to_tp_tbl:MAX:Max\: %6.1lf\l
STACK:state_end#D1642E:State End                 
GPRINT:state_end:LAST:Cur\: %6.1lf
GPRINT:state_end:AVERAGE:Ave\: %6.1lf
GPRINT:state_end:MAX:Max\: %6.1lf\l
STACK:state_freeing_items#487860:State Freeing Items       
GPRINT:state_freeing_items:LAST:Cur\: %6.1lf
GPRINT:state_freeing_items:AVERAGE:Ave\: %6.1lf
GPRINT:state_freeing_items:MAX:Max\: %6.1lf\l
STACK:state_init#907890:State Init                
GPRINT:state_init:LAST:Cur\: %6.1lf
GPRINT:state_init:AVERAGE:Ave\: %6.1lf
GPRINT:state_init:MAX:Max\: %6.1lf\l
STACK:state_locked#DE0056:State Locked              
GPRINT:state_locked:LAST:Cur\: %6.1lf
GPRINT:state_locked:AVERAGE:Ave\: %6.1lf
GPRINT:state_locked:MAX:Max\: %6.1lf\l
STACK:state_login#1693A7:State Login               
GPRINT:state_login:LAST:Cur\: %6.1lf
GPRINT:state_login:AVERAGE:Ave\: %6.1lf
GPRINT:state_login:MAX:Max\: %6.1lf\l
STACK:state_preparing#783030:State Preparing           
GPRINT:state_preparing:LAST:Cur\: %6.1lf
GPRINT:state_preparing:AVERAGE:Ave\: %6.1lf
GPRINT:state_preparing:MAX:Max\: %6.1lf\l
STACK:state_readng_frm_nt#FF7F00:State Reading From Net    
GPRINT:state_readng_frm_nt:LAST:Cur\: %6.1lf
GPRINT:state_readng_frm_nt:AVERAGE:Ave\: %6.1lf
GPRINT:state_readng_frm_nt:MAX:Max\: %6.1lf\l
STACK:state_sending_data#54382A:State Sending Data        
GPRINT:state_sending_data:LAST:Cur\: %6.1lf
GPRINT:state_sending_data:AVERAGE:Ave\: %6.1lf
GPRINT:state_sending_data:MAX:Max\: %6.1lf\l
STACK:state_sorting_reslt#B83A04:State Sorting Result      
GPRINT:state_sorting_reslt:LAST:Cur\: %6.1lf
GPRINT:state_sorting_reslt:AVERAGE:Ave\: %6.1lf
GPRINT:state_sorting_reslt:MAX:Max\: %6.1lf\l
STACK:state_statistics#6E3803:State Statistics          
GPRINT:state_statistics:LAST:Cur\: %6.1lf
GPRINT:state_statistics:AVERAGE:Ave\: %6.1lf
GPRINT:state_statistics:MAX:Max\: %6.1lf\l
STACK:state_updating#B56414:State Updating            
GPRINT:state_updating:LAST:Cur\: %6.1lf
GPRINT:state_updating:AVERAGE:Ave\: %6.1lf
GPRINT:state_updating:MAX:Max\: %6.1lf\l
STACK:state_writing_to_nt#6E645A:State Writing To Net      
GPRINT:state_writing_to_nt:LAST:Cur\: %6.1lf
GPRINT:state_writing_to_nt:AVERAGE:Ave\: %6.1lf
GPRINT:state_writing_to_nt:MAX:Max\: %6.1lf\l
STACK:state_none#521808:State None                
GPRINT:state_none:LAST:Cur\: %6.1lf
GPRINT:state_none:AVERAGE:Ave\: %6.1lf
GPRINT:state_none:MAX:Max\: %6.1lf\l
STACK:state_other#194240:State Other               
GPRINT:state_other:LAST:Cur\: %6.1lf
GPRINT:state_other:AVERAGE:Ave\: %6.1lf
GPRINT:state_other:MAX:Max\: %6.1lf\l
