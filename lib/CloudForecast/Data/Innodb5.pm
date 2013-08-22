package CloudForecast::Data::Innodb5;

use CloudForecast::Data -base;

rrds map { [ $_, 'DERIVE'] }  qw/ir ur dr rr/;
rrds map { [ $_, 'GAUGE'] }   qw/cr/;
rrds map { [ $_, 'COUNTER'] } qw/pr pw/;
rrds map { [ $_, 'GAUGE'] }   qw/dirtyr/;
rrds map { [ $_, 'GAUGE'] }   qw/bp_total bp_free/;

# porting from percona-monitoring-plugins
# http://www.percona.com/doc/percona-monitoring-plugins/cacti/mysql-templates.html
# InnoDB Buffer Pool Activity
extend_rrd 'pages_created', 'DERIVE';
extend_rrd 'pages_read', 'DERIVE';
extend_rrd 'pages_written', 'DERIVE';
# InnoDB Checkpoint Age
extend_rrd 'uncheckpointed_byts', 'GAUGE';
# InnoDB Current Lock Waits
extend_rrd 'innodb_lock_wat_scs', 'GAUGE';
# InnoDB I/O
extend_rrd 'file_reads', 'DERIVE';
extend_rrd 'file_writes', 'DERIVE';
extend_rrd 'log_writes', 'DERIVE';
extend_rrd 'file_fsyncs', 'DERIVE';
# InnoDB I/O Pending
extend_rrd 'pending_aio_log_ios', 'GAUGE';
extend_rrd 'pending_aio_sync_is', 'GAUGE';
extend_rrd 'pending_bf_pl_flshs', 'GAUGE';
extend_rrd 'pending_chkp_writes', 'GAUGE';
extend_rrd 'pending_ibuf_ao_rds', 'GAUGE';
extend_rrd 'pending_log_flushes', 'GAUGE';
extend_rrd 'pending_log_writes', 'GAUGE';
extend_rrd 'pending_norml_o_rds', 'GAUGE';
extend_rrd 'pending_nrml_o_wrts', 'GAUGE';
# InnoDB Lock Structures
extend_rrd 'innodb_lock_structs', 'GAUGE';
# InnoDB Log
extend_rrd 'innodb_log_buffr_sz', 'GAUGE';
extend_rrd 'log_bytes_written', 'DERIVE';
extend_rrd 'log_bytes_flushed', 'DERIVE';
extend_rrd 'unflushed_log', 'GAUGE';
# InnoDB Row Lock Time
extend_rrd 'innodb_row_lock_tim', 'DERIVE';
# InnoDB Row Lock Waits
extend_rrd 'innodb_row_lock_wts', 'DERIVE';
# InnoDB Tables In Use
extend_rrd 'innodb_tables_in_us', 'GAUGE';
extend_rrd 'innodb_locked_tabls', 'GAUGE';
# InnoDB Transactions
extend_rrd 'innodb_transactions', 'DERIVE';
extend_rrd 'history_list', 'GAUGE';
# InnoDB Transactions Active/Locked
extend_rrd 'active_transactions', 'GAUGE';
extend_rrd 'locked_transactions', 'GAUGE';
extend_rrd 'current_transactins', 'GAUGE';
extend_rrd 'read_views', 'GAUGE';

graphs 'rows_rate',  'ROW OPERATIONS Rate';
graphs 'rows_count', 'ROW OPERATIONS Count';
graphs 'bp_usage',   'Buffer pool usage';
graphs 'cache',      'Buffer pool hit rate';
graphs 'page_io',    'Page read(+)/write(-) count';
graphs 'dirty_rate', 'Dirty pages rate';

graphs 'idb_buffer pool activity','Buffer Pool Activity';
graphs 'idb_checkpoint age','Checkpoint Age';
graphs 'idb_current lock waits','Current Lock Waits';
graphs 'idb_io','InnoDB I/O';
graphs 'idb_io_pending','InnoDB I/O Pending';
graphs 'idb_lock_structures','Lock Structures';
graphs 'idb_log','InnoDB Log';
graphs 'idb_row_lock_time', 'Row Lock Time';
graphs 'idb_row_lock_waits','Row Lock Waits';
graphs 'idb_tables_in_use','InnoDB Tables In Use';
graphs 'idb_transactions','InnoDB Transactions';
graphs 'idb_transactions_activelocked','Transactions Active/Locked';

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

# borrow from percona-monitoring-plugins's ss_get_mysql_stats.php
sub _get_innodb_status {
    my $c = shift;
    my %ibstatus = (
        'spin_waits'                => [],
        'spin_rounds'               => [],
        'os_waits'                  => [],
        'pending_normal_aio_reads'  => 0,
        'pending_normal_aio_writes' => 0,
        'pending_ibuf_aio_reads'    => 0,
        'pending_aio_log_ios'       => 0,
        'pending_aio_sync_ios'      => 0,
        'pending_log_flushes'       => 0,
        'pending_buf_pool_flushes'  => 0,
        'file_reads'                => 0,
        'file_writes'               => 0,
        'file_fsyncs'               => 0,
        'ibuf_inserts'              => 0,
        'ibuf_merged'               => 0,
        'ibuf_merges'               => 0,
        'log_bytes_written'         => 0,
        'unflushed_log'             => 0,
        'log_bytes_flushed'         => 0,
        'pending_log_writes'        => 0,
        'pending_chkp_writes'       => 0,
        'log_writes'                => 0,
        'pool_size'                 => 0,
        'free_pages'                => 0,
        'database_pages'            => 0,
        'modified_pages'            => 0,
        'pages_read'                => 0,
        'pages_created'             => 0,
        'pages_written'             => 0,
        'queries_inside'            => 0,
        'queries_queued'            => 0,
        'read_views'                => 0,
        'rows_inserted'             => 0,
        'rows_updated'              => 0,
        'rows_deleted'              => 0,
        'rows_read'                 => 0,
        'innodb_transactions'       => 0,
        'unpurged_txns'             => 0,
        'history_list'              => 0,
        'current_transactions'      => 0,
        'hash_index_cells_total'    => 0,
        'hash_index_cells_used'     => 0,
        'total_mem_alloc'           => 0,
        'additional_pool_alloc'     => 0,
        'last_checkpoint'           => 0,
        'uncheckpointed_bytes'      => 0,
        'ibuf_used_cells'           => 0,
        'ibuf_free_cells'           => 0,
        'ibuf_cell_count'           => 0,
        'adaptive_hash_memory'      => 0,
        'page_hash_memory'          => 0,
        'dictionary_cache_memory'   => 0,
        'file_system_memory'        => 0,
        'lock_system_memory'        => 0,
        'recovery_system_memory'    => 0,
        'thread_hash_memory'        => 0,
        'innodb_sem_waits'          => 0,
        'innodb_sem_wait_time_ms'   => 0,
        'innodb_lock_structs'       => 0,
        'active_transactions'       => 0,
        'innodb_lock_wait_secs'     => 0,
        'innodb_tables_in_use'      => 0,
        'innodb_locked_tables'      => 0,
        'locked_transactions'       => 0,
    );

    my $res = $c->component('MySQL')->select_row('SHOW /*!50000 ENGINE*/ INNODB STATUS');
    my $status = $res->{Status};

    my $prev_line;
    my $txn_seen = 0;
    for my $line (split /\n/, $status) {
        chomp $line;
        $line =~ s/^\s+//;
        $line =~ s/\s+$//;
        my @row = split /\s+/, $line;

        # SEMAPHORES
        if ($line =~ /Mutex spin waits/) {
            # Mutex spin waits 79626940, rounds 157459864, OS waits 698719
            # Mutex spin waits 0, rounds 247280272495, OS waits 316513438
            push @{ $ibstatus{'spin_waits'}  }, $row[3];
            push @{ $ibstatus{'spin_rounds'} }, $row[5];
            push @{ $ibstatus{'os_waits'}    }, $row[8];
        }
        elsif ($line =~ /RW-shared spins/
                   && $line =~ /;/) {
            # RW-shared spins 3859028, OS waits 2100750; RW-excl spins 4641946, OS waits 1530310
            push @{ $ibstatus{'spin_waits'} }, $row[2];
            push @{ $ibstatus{'spin_waits'} }, $row[8];
            push @{ $ibstatus{'os_waits'}   }, $row[5];
            push @{ $ibstatus{'os_waits'}   }, $row[11];
        } elsif ($line =~ /RW-shared spins/
                   && $line !~ /; RW-excl spins/) {
            # Post 5.5.17 SHOW ENGINE INNODB STATUS syntax
            # RW-shared spins 604733, rounds 8107431, OS waits 241268
            push @{ $ibstatus{'spin_waits'} }, $row[2];
            push @{ $ibstatus{'os_waits'}   }, $row[7];
        } elsif ($line =~ /RW-excl spins/) {
            # Post 5.5.17 SHOW ENGINE INNODB STATUS syntax
            # RW-excl spins 604733, rounds 8107431, OS waits 241268
            push @{ $ibstatus{'spin_waits'} }, $row[2];
            push @{ $ibstatus{'os_waits'}   }, $row[7];
        } elsif ($line =~ /seconds the semaphore:/) {
            # --Thread 907205 has waited at handler/ha_innodb.cc line 7156 for 1.00 seconds the semaphore:
            $ibstatus{'innodb_sem_waits'} += 1;
            $ibstatus{'innodb_sem_wait_time_ms'} += to_int($row[9]) * 1000;
        }

        # TRANSACTIONS
        elsif ($line =~ /Trx id counter/) {
            # The beginning of the TRANSACTIONS section: start counting
            # transactions
            # Trx id counter 0 1170664159
            # Trx id counter 861B144C
            $ibstatus{'innodb_transactions'} = make_bigint($row[3], ($row[4] || undef));
            $txn_seen = 1;
        }
        elsif ($line =~ /Purge done for trx/) {
            # Purge done for trx's n:o < 0 1170663853 undo n:o < 0 0
            # Purge done for trx's n:o < 861B135D undo n:o < 0
            my $purged_to = make_bigint($row[6], ($row[7] eq 'undo' ? undef : $row[7]));
            $ibstatus{'unpurged_txns'} = $ibstatus{'innodb_transactions'} - $purged_to;
        }
        elsif ($line =~ /History list length/) {
            # History list length 132
            $ibstatus{'history_list'} = $row[3];
        }
        elsif ($txn_seen && $line =~ /---TRANSACTION/) {
            # ---TRANSACTION 0, not started, process no 13510, OS thread id 1170446656
            $ibstatus{'current_transactions'} += 1;
            if ($line =~ /ACTIVE/) {
                $ibstatus{'active_transactions'} += 1;
            }
        }
        elsif ($txn_seen && $line =~ /------- TRX HAS BEEN/) {
            # ------- TRX HAS BEEN WAITING 32 SEC FOR THIS LOCK TO BE GRANTED:
            $ibstatus{'innodb_lock_wait_secs'} += to_int($row[5]);
        }
        elsif ($line =~ /read views open inside InnoDB/) {
            # 1 read views open inside InnoDB
            $ibstatus{'read_views'} = $row[0];
        }
        elsif ($line =~ /mysql tables in use/) {
            # mysql tables in use 2, locked 2
            $ibstatus{'innodb_tables_in_use'} += to_int($row[4]);
            $ibstatus{'innodb_locked_tables'} += to_int($row[6]);
        }
        elsif ($txn_seen && $line =~ /lock struct\(s\)/) {
            # 23 lock struct(s), heap size 3024, undo log entries 27
            # LOCK WAIT 12 lock struct(s), heap size 3024, undo log entries 5
            # LOCK WAIT 2 lock struct(s), heap size 368
            if ($line =~ /LOCK WAIT/) {
                $ibstatus{'innodb_lock_structs'} += to_int($row[2]);
                $ibstatus{'locked_transactions'} += 1;
            } else {
                $ibstatus{'innodb_lock_structs'} += to_int($row[0]);
            }
        }

        # FILE I/O
        elsif ($line =~ / OS file reads, /) {
            # 8782182 OS file reads, 15635445 OS file writes, 947800 OS fsyncs
            $ibstatus{'file_reads'}  = $row[0];
            $ibstatus{'file_writes'} = $row[4];
            $ibstatus{'file_fsyncs'} = $row[8];
        }
        elsif ($line =~ /Pending normal aio reads:/) {
            # Pending normal aio reads: 0, aio writes: 0,
            $ibstatus{'pending_normal_aio_reads'}  = $row[4];
            $ibstatus{'pending_normal_aio_writes'} = $row[7];
        }
        elsif ($line =~ /ibuf aio reads/) {
            #  ibuf aio reads: 0, log i/o's: 0, sync i/o's: 0
            $ibstatus{'pending_ibuf_aio_reads'} = $row[3];
            $ibstatus{'pending_aio_log_ios'}    = $row[6];
            $ibstatus{'pending_aio_sync_ios'}   = $row[9];
        }
        elsif ($line =~ /Pending flushes \(fsync\)/) {
            # Pending flushes (fsync) log: 0; buffer pool: 0
            $ibstatus{'pending_log_flushes'}      = $row[4];
            $ibstatus{'pending_buf_pool_flushes'} = $row[7];
        }

        # INSERT BUFFER AND ADAPTIVE HASH INDEX
        elsif ($line =~ /Ibuf for space 0: size /) {
            # Older InnoDB code seemed to be ready for an ibuf per tablespace.  It
            # had two lines in the output.  Newer has just one line, see below.
            # Ibuf for space 0: size 1, free list len 887, seg size 889, is not empty
            # Ibuf for space 0: size 1, free list len 887, seg size 889,
            $ibstatus{'ibuf_used_cells'} = $row[5];
            $ibstatus{'ibuf_free_cells'} = $row[9];
            $ibstatus{'ibuf_cell_count'} = $row[12];
        }
        elsif ($line =~ /Ibuf: size /) {
            # Ibuf: size 1, free list len 4634, seg size 4636,
            $ibstatus{'ibuf_used_cells'} = $row[2];
            $ibstatus{'ibuf_free_cells'} = $row[6];
            $ibstatus{'ibuf_cell_count'} = $row[9];
            if ($line =~ /merges/) {
                $ibstatus{'ibuf_merges'} = $row[10];
            }
        }
        elsif ($line =~ /, delete mark / && $prev_line =~ /merged operations:/) {
            # Output of show engine innodb status has changed in 5.5
            # merged operations:
            # insert 593983, delete mark 387006, delete 73092
            $ibstatus{'ibuf_inserts'} = $row[1];
            $ibstatus{'ibuf_merged'}  = $row[1] + $row[4] + $row[6];
        }
        elsif ($line =~ / merged recs, /) {
            # 19817685 inserts, 19817684 merged recs, 3552620 merges
            $ibstatus{'ibuf_inserts'} = $row[0];
            $ibstatus{'ibuf_merged'}  = $row[2];
            $ibstatus{'ibuf_merges'}  = $row[5];
        }
        elsif ($line =~ /Hash table size /) {
            # In some versions of InnoDB, the used cells is omitted.
            # Hash table size 4425293, used cells 4229064, ....
            # Hash table size 57374437, node heap has 72964 buffer(s) <-- no used cells
            $ibstatus{'hash_index_cells_total'} = $row[3];
            $ibstatus{'hash_index_cells_used'}
                = ($line =~ /used cells/) ? $row[6] : 0;
        }

        # LOG
        elsif ($line =~ m{ log i/o's done, }) {
            # 3430041 log i/o's done, 17.44 log i/o's/second
            # 520835887 log i/o's done, 17.28 log i/o's/second, 518724686 syncs, 2980893 checkpoints
            # TODO: graph syncs and checkpoints
            $ibstatus{'log_writes'} = $row[0];
        }
        elsif ($line =~ / pending log writes, /) {
            # 0 pending log writes, 0 pending chkp writes
            $ibstatus{'pending_log_writes'}  = $row[0];
            $ibstatus{'pending_chkp_writes'} = $row[4];
        }
        elsif ($line =~ /Log sequence number/) {
            # This number is NOT printed in hex in InnoDB plugin.
            # Log sequence number 13093949495856 //plugin
            # Log sequence number 125 3934414864 //normal
            $ibstatus{'log_bytes_written'}
                = $row[4]
                ? make_bigint($row[3], $row[4])
                : $row[3];
        }
        elsif ($line =~ /Log flushed up to/) {
            # This number is NOT printed in hex in InnoDB plugin.
            # Log flushed up to   13093948219327
            # Log flushed up to   125 3934414864
            $ibstatus{'log_bytes_flushed'}
                = $row[5]
                ? make_bigint($row[4], $row[5])
                : $row[4];
        }
        elsif ($line =~ /Last checkpoint at/) {
            # Last checkpoint at  125 3934293461
            $ibstatus{'last_checkpoint'}
                = $row[4]
                ? make_bigint($row[3], $row[4])
                : $row[3];
        }

        # BUFFER POOL AND MEMORY
        elsif ($line =~ /Total memory allocated/ && $line =~ /in additional pool allocated/) {
            # Total memory allocated 29642194944; in additional pool allocated 0
            # Total memory allocated by read views 96
            $ibstatus{'total_mem_alloc'}       = $row[3];
            $ibstatus{'additional_pool_alloc'} = $row[8];
        }
        elsif($line =~ /Adaptive hash index /) {
            #   Adaptive hash index 1538240664 (186998824 + 1351241840)
            $ibstatus{'adaptive_hash_memory'} = $row[3];
        }
        elsif($line =~ /Page hash           /) {
            #   Page hash           11688584
            $ibstatus{'page_hash_memory'} = $row[2];
        }
        elsif($line =~ /Dictionary cache    /) {
            #   Dictionary cache    145525560  (140250984 + 5274576)
            $ibstatus{'dictionary_cache_memory'} = $row[2];
        }
        elsif($line =~ /File system         /) {
            #   File system         313848  (82672 + 231176)
            $ibstatus{'file_system_memory'} = $row[2];
        }
        elsif($line =~ /Lock system         /) {
            #   Lock system         29232616  (29219368 + 13248)
            $ibstatus{'lock_system_memory'} = $row[2];
        }
        elsif($line =~ /Recovery system     /) {
            #   Recovery system     0  (0 + 0)
            $ibstatus{'recovery_system_memory'} = $row[2];
        }
        elsif($line =~ /Threads             /) {
            #   Threads             409336  (406936 + 2400)
            $ibstatus{'thread_hash_memory'} = $row[1];
        }
        elsif($line =~ /innodb_io_pattern   /) {
            #   innodb_io_pattern   0  (0 + 0)
            $ibstatus{'innodb_io_pattern_memory'} = $row[1];
        }
        elsif ($line =~ /Buffer pool size /) {
            # The " " after size is necessary to avoid matching the wrong line:
            # Buffer pool size        1769471
            # Buffer pool size, bytes 28991012864
            $ibstatus{'pool_size'} = $row[3];
        }
        elsif ($line =~ /Free buffers/) {
            # Free buffers            0
            $ibstatus{'free_pages'} = $row[2];
        }
        elsif ($line =~ /Database pages/) {
            # Database pages          1696503
            $ibstatus{'database_pages'} = $row[2];
        }
        elsif ($line =~ /Modified db pages/) {
            # Modified db pages       160602
            $ibstatus{'modified_pages'} = $row[3];
        }
        elsif ($line =~ /Pages read ahead/) {
            # Must do this BEFORE the next test, otherwise it'll get fooled by this
            # line from the new plugin (see samples/innodb-015.txt):
            # Pages read ahead 0.00/s, evicted without access 0.06/s
            # TODO: No-op for now, see issue 134.
            ;
        }
        elsif ($line =~ /Pages read/) {
            # Pages read 15240822, created 1770238, written 21705836
            $ibstatus{'pages_read'}    = $row[2];
            $ibstatus{'pages_created'} = $row[4];
            $ibstatus{'pages_written'} = $row[6];
        }

        # ROW OPERATIONS
        elsif ($line =~ /Number of rows inserted/) {
            # Number of rows inserted 50678311, updated 66425915, deleted 20605903, read 454561562
            $ibstatus{'rows_inserted'} = $row[4];
            $ibstatus{'rows_updated'}  = $row[6];
            $ibstatus{'rows_deleted'}  = $row[8];
            $ibstatus{'rows_read'}     = $row[10];
        }
        elsif ($line =~ / queries inside InnoDB, /) {
            # 0 queries inside InnoDB, 0 queries in queue
            $ibstatus{'queries_inside'} = $row[0];
            $ibstatus{'queries_queued'} = $row[4];
        }
        $prev_line = $line;
    }

    for my $k (qw(spin_waits spin_rounds os_waits)) {
        my $s = 0;
        for my $v (@{ $ibstatus{$k} }) {
            $s += to_int($v);
        }
        $ibstatus{$k} = $s;
    }

    $ibstatus{'unflushed_log'}
        = $ibstatus{'log_bytes_written'} - $ibstatus{'log_bytes_flushed'};
    $ibstatus{'uncheckpointed_bytes'}
        = $ibstatus{'log_bytes_written'} - $ibstatus{'last_checkpoint'};

    for my $k (keys %ibstatus) {
        $ibstatus{$k} = to_int($ibstatus{$k});
    }

    return %ibstatus;
}

sub make_bigint {
    my($hi,$lo) = @_;
    if (! $lo) {
        no warnings qw(portable);
        # suppress: "Hexadecimal number > 0xffffffff non-portable"
        return hex($hi);
    } else {
        $hi ||= 0;
        $lo ||= 0;
        return $hi * 4294967296 + $lo;
    }
}

sub to_int {
    my $v = shift;
    $v = $1 if $v =~ /([0-9]+)/;
    return $v;
}

fetcher {
    my $c = shift;

    my %variable = $c->_select_all_show_statement(q{show variables like 'innodb\_%'});
    my %status   = $c->_select_all_show_statement(q{show /*!50002 GLOBAL */ status like 'Innodb\_%'});
    my %ibstatus = $c->_get_innodb_status();

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

    my $buffer_pool_total = $status{"innodb_buffer_pool_pages_total"} * $status{"innodb_page_size"};
    my $buffer_pool_free  = $status{"innodb_buffer_pool_pages_free"}  * $status{"innodb_page_size"};

    # Should substruct Innodb_dblwr_writes from Innodb_pages_written?
    return [
        (map { $status{$_}} qw(innodb_rows_inserted innodb_rows_updated innodb_rows_deleted innodb_rows_read)),
        $buffer_pool_hit_rate,
        $status{innodb_pages_read}, $status{innodb_pages_written},
        $buffer_pool_dirty_pages_rate,
        $buffer_pool_total, $buffer_pool_free,
        # InnoDB Buffer Pool Activity
        $ibstatus{pages_created},
        $ibstatus{pages_read},
        $ibstatus{pages_written},
        # InnoDB Checkpoint Age
        $ibstatus{uncheckpointed_bytes},
        # InnoDB Current Lock Waits
        $ibstatus{innodb_lock_wait_secs},
        # InnoDB I/O
        $ibstatus{file_reads},
        $ibstatus{file_writes},
        $ibstatus{log_writes},
        $ibstatus{file_fsyncs},
        # InnoDB I/O Pending
        $ibstatus{pending_aio_log_ios},
        $ibstatus{pending_aio_sync_ios},
        $ibstatus{pending_buf_pool_flushes},
        $ibstatus{pending_chkp_writes},
        $ibstatus{pending_ibuf_aio_reads},
        $ibstatus{pending_log_flushes},
        $ibstatus{pending_log_writes},
        $ibstatus{pending_normal_aio_reads},
        $ibstatus{pending_normal_aio_writes},
        # InnoDB Lock Structures
        $ibstatus{innodb_lock_structs},
        # InnoDB Log
        $variable{innodb_log_buffer_size},
        $ibstatus{log_bytes_written},
        $ibstatus{log_bytes_flushed},
        $ibstatus{unflushed_log},
        # InnoDB Row Lock Time
        $status{innodb_row_lock_time},
        # InnoDB Row Lock Waits
        $status{innodb_row_lock_waits},
        # InnoDB Tables In Use
        $ibstatus{innodb_tables_in_use},
        $ibstatus{innodb_locked_tables},
        # InnoDB Transactions
        $ibstatus{innodb_transactions},
        $ibstatus{history_list},
        # InnoDB Transactions Active/Locked
        $ibstatus{active_transactions},
        $ibstatus{locked_transactions},
        $ibstatus{current_transactions},
        $ibstatus{read_views},

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
@@ rows_rate
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

@@ rows_count
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
AREA:my1#c0c0c0:Read 
GPRINT:my1:LAST:Cur\: %5.1lf%s
GPRINT:my1:AVERAGE:Ave\: %5.1lf%s
GPRINT:my1:MAX:Max\: %5.1lf%s
GPRINT:my1:MIN:Min\: %5.1lf%s\c
AREA:my2#800080:Write
GPRINT:my2r:LAST:Cur\: %5.1lf%s
GPRINT:my2r:AVERAGE:Ave\: %5.1lf%s
GPRINT:my2r:MAX:Max\: %5.1lf%s
GPRINT:my2r:MIN:Min\: %5.1lf%s\c
HRULE:0#ff0000

@@ bp_usage
DEF:total=<%RRD%>:bp_total:AVERAGE
DEF:free=<%RRD%>:bp_free:AVERAGE
CDEF:used=total,free,-
AREA:total#afffb2:Total\:
GPRINT:total:LAST:%5.2lf%S\l
AREA:used#ffc0c0:Used \:
LINE1:used#aa0000
GPRINT:used:LAST:Cur\: %5.1lf%S
GPRINT:used:AVERAGE:Ave\: %5.1lf%S
GPRINT:used:MAX:Max\: %5.1lf%S
GPRINT:used:MIN:Min\: %5.1lf%S\l

@@ idb_buffer pool activity
DEF:pages_created=<%RRD_EXTEND pages_created %>:pages_created:AVERAGE
DEF:pages_read=<%RRD_EXTEND pages_read %>:pages_read:AVERAGE
DEF:pages_written=<%RRD_EXTEND pages_written %>:pages_written:AVERAGE
LINE2:pages_created#D6883A:Pages Created
GPRINT:pages_created:LAST:Cur\: %5.1lf
GPRINT:pages_created:AVERAGE:Ave\: %5.1lf
GPRINT:pages_created:MAX:Max\: %5.1lf\l
LINE2:pages_read#E6D883:Pages Read   
GPRINT:pages_read:LAST:Cur\: %5.1lf
GPRINT:pages_read:AVERAGE:Ave\: %5.1lf
GPRINT:pages_read:MAX:Max\: %5.1lf\l
LINE2:pages_written#55AD84:Pages Written
GPRINT:pages_written:LAST:Cur\: %5.1lf
GPRINT:pages_written:AVERAGE:Ave\: %5.1lf
GPRINT:pages_written:MAX:Max\: %5.1lf\l

@@ idb_checkpoint age
DEF:uncheckpointed_byts=<%RRD_EXTEND uncheckpointed_byts %>:uncheckpointed_byts:AVERAGE
LINE1:uncheckpointed_byts#661100:Uncheckpointed Bytes
GPRINT:uncheckpointed_byts:LAST:Cur\: %5.1lf%S
GPRINT:uncheckpointed_byts:AVERAGE:Ave\: %5.1lf%S
GPRINT:uncheckpointed_byts:MAX:Max\: %5.1lf%S\l

@@ idb_current lock waits
DEF:innodb_lock_wat_scs=<%RRD_EXTEND innodb_lock_wat_scs %>:innodb_lock_wat_scs:AVERAGE
LINE1:innodb_lock_wat_scs#201A33:Innodb Lock Wait Secs
GPRINT:innodb_lock_wat_scs:LAST:Cur\: %5.1lf
GPRINT:innodb_lock_wat_scs:AVERAGE:Ave\: %5.1lf
GPRINT:innodb_lock_wat_scs:MAX:Max\: %5.1lf\l

@@ idb_io
DEF:file_reads=<%RRD_EXTEND file_reads %>:file_reads:AVERAGE
DEF:file_writes=<%RRD_EXTEND file_writes %>:file_writes:AVERAGE
DEF:log_writes=<%RRD_EXTEND log_writes %>:log_writes:AVERAGE
DEF:file_fsyncs=<%RRD_EXTEND file_fsyncs %>:file_fsyncs:AVERAGE
LINE1:file_reads#402204:File Reads 
GPRINT:file_reads:LAST:Cur\: %5.1lf
GPRINT:file_reads:AVERAGE:Ave\: %5.1lf
GPRINT:file_reads:MAX:Max\: %5.1lf\l
LINE1:file_writes#B3092B:File Writes
GPRINT:file_writes:LAST:Cur\: %5.1lf
GPRINT:file_writes:AVERAGE:Ave\: %5.1lf
GPRINT:file_writes:MAX:Max\: %5.1lf\l
LINE1:log_writes#FFBF00:Log Writes 
GPRINT:log_writes:LAST:Cur\: %5.1lf
GPRINT:log_writes:AVERAGE:Ave\: %5.1lf
GPRINT:log_writes:MAX:Max\: %5.1lf\l
LINE1:file_fsyncs#0ABFCC:File Fsyncs
GPRINT:file_fsyncs:LAST:Cur\: %5.1lf
GPRINT:file_fsyncs:AVERAGE:Ave\: %5.1lf
GPRINT:file_fsyncs:MAX:Max\: %5.1lf\l

@@ idb_io_pending
DEF:pending_aio_log_ios=<%RRD_EXTEND pending_aio_log_ios %>:pending_aio_log_ios:AVERAGE
DEF:pending_aio_sync_is=<%RRD_EXTEND pending_aio_sync_is %>:pending_aio_sync_is:AVERAGE
DEF:pending_bf_pl_flshs=<%RRD_EXTEND pending_bf_pl_flshs %>:pending_bf_pl_flshs:AVERAGE
DEF:pending_chkp_writes=<%RRD_EXTEND pending_chkp_writes %>:pending_chkp_writes:AVERAGE
DEF:pending_ibuf_ao_rds=<%RRD_EXTEND pending_ibuf_ao_rds %>:pending_ibuf_ao_rds:AVERAGE
DEF:pending_log_flushes=<%RRD_EXTEND pending_log_flushes %>:pending_log_flushes:AVERAGE
DEF:pending_log_writes=<%RRD_EXTEND pending_log_writes %>:pending_log_writes:AVERAGE
DEF:pending_norml_o_rds=<%RRD_EXTEND pending_norml_o_rds %>:pending_norml_o_rds:AVERAGE
DEF:pending_nrml_o_wrts=<%RRD_EXTEND pending_nrml_o_wrts %>:pending_nrml_o_wrts:AVERAGE
LINE1:pending_aio_log_ios#FF0000:Pending Aio Log Ios      
GPRINT:pending_aio_log_ios:LAST:Cur\: %5.1lf
GPRINT:pending_aio_log_ios:AVERAGE:Ave\: %5.1lf
GPRINT:pending_aio_log_ios:MAX:Max\: %5.1lf\l
LINE1:pending_aio_sync_is#FF7D00:Pending Aio Sync Ios     
GPRINT:pending_aio_sync_is:LAST:Cur\: %5.1lf
GPRINT:pending_aio_sync_is:AVERAGE:Ave\: %5.1lf
GPRINT:pending_aio_sync_is:MAX:Max\: %5.1lf\l
LINE1:pending_bf_pl_flshs#FFF200:Pending Buf Pool Flushes 
GPRINT:pending_bf_pl_flshs:LAST:Cur\: %5.1lf
GPRINT:pending_bf_pl_flshs:AVERAGE:Ave\: %5.1lf
GPRINT:pending_bf_pl_flshs:MAX:Max\: %5.1lf\l
LINE1:pending_chkp_writes#00A348:Pending Chkp Writes      
GPRINT:pending_chkp_writes:LAST:Cur\: %5.1lf
GPRINT:pending_chkp_writes:AVERAGE:Ave\: %5.1lf
GPRINT:pending_chkp_writes:MAX:Max\: %5.1lf\l
LINE1:pending_ibuf_ao_rds#6DC8FE:Pending Ibuf Aio Reads   
GPRINT:pending_ibuf_ao_rds:LAST:Cur\: %5.1lf
GPRINT:pending_ibuf_ao_rds:AVERAGE:Ave\: %5.1lf
GPRINT:pending_ibuf_ao_rds:MAX:Max\: %5.1lf\l
LINE1:pending_log_flushes#4444FF:Pending Log Flushes      
GPRINT:pending_log_flushes:LAST:Cur\: %5.1lf
GPRINT:pending_log_flushes:AVERAGE:Ave\: %5.1lf
GPRINT:pending_log_flushes:MAX:Max\: %5.1lf\l
LINE1:pending_log_writes#55009D:Pending Log Writes       
GPRINT:pending_log_writes:LAST:Cur\: %5.1lf
GPRINT:pending_log_writes:AVERAGE:Ave\: %5.1lf
GPRINT:pending_log_writes:MAX:Max\: %5.1lf\l
LINE1:pending_norml_o_rds#B90054:Pending Normal Aio Reads 
GPRINT:pending_norml_o_rds:LAST:Cur\: %5.1lf
GPRINT:pending_norml_o_rds:AVERAGE:Ave\: %5.1lf
GPRINT:pending_norml_o_rds:MAX:Max\: %5.1lf\l
LINE1:pending_nrml_o_wrts#8F9286:Pending Normal Aio Writes
GPRINT:pending_nrml_o_wrts:LAST:Cur\: %5.1lf
GPRINT:pending_nrml_o_wrts:AVERAGE:Ave\: %5.1lf
GPRINT:pending_nrml_o_wrts:MAX:Max\: %5.1lf\l

@@ idb_lock_structures
DEF:innodb_lock_structs=<%RRD_EXTEND innodb_lock_structs %>:innodb_lock_structs:AVERAGE
LINE1:innodb_lock_structs#0C4E5D:Innodb Lock Structs
GPRINT:innodb_lock_structs:LAST:Cur\: %5.1lf
GPRINT:innodb_lock_structs:AVERAGE:Ave\: %5.1lf
GPRINT:innodb_lock_structs:MAX:Max\: %5.1lf\l

@@ idb_log
DEF:innodb_log_buffr_sz=<%RRD_EXTEND innodb_log_buffr_sz %>:innodb_log_buffr_sz:AVERAGE
DEF:log_bytes_written=<%RRD_EXTEND log_bytes_written %>:log_bytes_written:AVERAGE
DEF:log_bytes_flushed=<%RRD_EXTEND log_bytes_flushed %>:log_bytes_flushed:AVERAGE
DEF:unflushed_log=<%RRD_EXTEND unflushed_log %>:unflushed_log:AVERAGE
AREA:innodb_log_buffr_sz#6E3803:Innodb Log Buffer Size
GPRINT:innodb_log_buffr_sz:LAST:Cur\: %5.1lf%S
GPRINT:innodb_log_buffr_sz:AVERAGE:Ave\: %5.1lf%S
GPRINT:innodb_log_buffr_sz:MAX:Max\: %5.1lf%S\l
AREA:log_bytes_written#5B8257:Log Bytes Written     
GPRINT:log_bytes_written:LAST:Cur\: %5.1lf%S
GPRINT:log_bytes_written:AVERAGE:Ave\: %5.1lf%S
GPRINT:log_bytes_written:MAX:Max\: %5.1lf%S\l
LINE1:log_bytes_flushed#AB4253:Log Bytes Flushed     
GPRINT:log_bytes_flushed:LAST:Cur\: %5.1lf%S
GPRINT:log_bytes_flushed:AVERAGE:Ave\: %5.1lf%S
GPRINT:log_bytes_flushed:MAX:Max\: %5.1lf%S\l
AREA:unflushed_log#AFECED:Unflushed Log         
GPRINT:unflushed_log:LAST:Cur\: %5.1lf%S
GPRINT:unflushed_log:AVERAGE:Ave\: %5.1lf%S
GPRINT:unflushed_log:MAX:Max\: %5.1lf%S\l

@@ idb_row_lock_time
DEF:innodb_row_lock_ms=<%RRD_EXTEND innodb_row_lock_tim %>:innodb_row_lock_tim:MAX
CDEF:innodb_row_lock_tim=innodb_row_lock_ms,1000,/
AREA:innodb_row_lock_tim#B11D03:Innodb Row Lock Time[sec]
GPRINT:innodb_row_lock_tim:LAST:Cur\: %6.3lf
GPRINT:innodb_row_lock_tim:AVERAGE:Ave\: %6.3lf
GPRINT:innodb_row_lock_tim:MAX:Max\: %6.3lf\l

@@ idb_row_lock_waits
DEF:innodb_row_lock_wts=<%RRD_EXTEND innodb_row_lock_wts %>:innodb_row_lock_wts:AVERAGE
AREA:innodb_row_lock_wts#E84A5F:Innodb Row Lock Waits
GPRINT:innodb_row_lock_wts:LAST:Cur\: %5.1lf
GPRINT:innodb_row_lock_wts:AVERAGE:Ave\: %5.1lf
GPRINT:innodb_row_lock_wts:MAX:Max\: %5.1lf\l

@@ idb_tables_in_use
DEF:innodb_tables_in_us=<%RRD_EXTEND innodb_tables_in_us %>:innodb_tables_in_us:AVERAGE
DEF:innodb_locked_tabls=<%RRD_EXTEND innodb_locked_tabls %>:innodb_locked_tabls:AVERAGE
AREA:innodb_tables_in_us#D99362:Innodb Tables In Use
GPRINT:innodb_tables_in_us:LAST:Cur\: %5.1lf
GPRINT:innodb_tables_in_us:AVERAGE:Ave\: %5.1lf
GPRINT:innodb_tables_in_us:MAX:Max\: %5.1lf\l
LINE1:innodb_locked_tabls#663344:Innodb Locked Tables
GPRINT:innodb_locked_tabls:LAST:Cur\: %5.1lf
GPRINT:innodb_locked_tabls:AVERAGE:Ave\: %5.1lf
GPRINT:innodb_locked_tabls:MAX:Max\: %5.1lf\l

@@ idb_transactions
DEF:innodb_transactions=<%RRD_EXTEND innodb_transactions %>:innodb_transactions:AVERAGE
DEF:history_list=<%RRD_EXTEND history_list %>:history_list:AVERAGE
LINE1:innodb_transactions#8F005C:Innodb Transactions
GPRINT:innodb_transactions:LAST:Cur\: %6.1lf
GPRINT:innodb_transactions:AVERAGE:Ave\: %6.1lf
GPRINT:innodb_transactions:MAX:Max\: %6.1lf\l
LINE1:history_list#FF7D00:History List       
GPRINT:history_list:LAST:Cur\: %6.1lf
GPRINT:history_list:AVERAGE:Ave\: %6.1lf
GPRINT:history_list:MAX:Max\: %6.1lf\l

@@ idb_transactions_activelocked
DEF:active_transactions=<%RRD_EXTEND active_transactions %>:active_transactions:AVERAGE
DEF:locked_transactions=<%RRD_EXTEND locked_transactions %>:locked_transactions:AVERAGE
DEF:current_transactins=<%RRD_EXTEND current_transactins %>:current_transactins:AVERAGE
DEF:read_views=<%RRD_EXTEND read_views %>:read_views:AVERAGE
AREA:active_transactions#C0C0C0:Active Transactions 
GPRINT:active_transactions:LAST:Cur\: %5.1lf
GPRINT:active_transactions:AVERAGE:Ave\: %5.1lf
GPRINT:active_transactions:MAX:Max\: %5.1lf\l
LINE1:locked_transactions#FF0000:Locked Transactions 
GPRINT:locked_transactions:LAST:Cur\: %5.1lf
GPRINT:locked_transactions:AVERAGE:Ave\: %5.1lf
GPRINT:locked_transactions:MAX:Max\: %5.1lf\l
LINE1:current_transactins#4444FF:Current Transactions
GPRINT:current_transactins:LAST:Cur\: %5.1lf
GPRINT:current_transactins:AVERAGE:Ave\: %5.1lf
GPRINT:current_transactins:MAX:Max\: %5.1lf\l
LINE1:read_views#74C366:Read Views          
GPRINT:read_views:LAST:Cur\: %5.1lf
GPRINT:read_views:AVERAGE:Ave\: %5.1lf
GPRINT:read_views:MAX:Max\: %5.1lf\l

