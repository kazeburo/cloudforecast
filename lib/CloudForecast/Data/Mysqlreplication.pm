package CloudForecast::Data::Mysqlreplication;

use CloudForecast::Data -base;

rrds map { [ $_, 'GAUGE' ] } qw/sec readpos execpos/;
graphs 'sec' => 'SecondsBehindMaster';
graphs 'pos' => 'PositionBehindMaster';

title {
    my $c = shift;
    my $title='MySQL Replication';
    if ( my $port = $c->component('MySQL')->port ) {
        $title .= " (port=$port)"; 
    }
    return $title;
};

sysinfo {
    my $c = shift;
    my @sysinfo;
    if ( my $sysinfo = $c->ledge_get('sysinfo') ) {
        if ( $sysinfo->{Replication} eq 'Yes' ) {
            map { push @sysinfo, $_, $sysinfo->{$_} } 
                qw/Replication Master_Host Master_Port IO_Running SQL_Running Last_Error/;
        }
        else {
            push @sysinfo, 'Replication', 'None';
        }
    }
    return \@sysinfo;
};

fetcher {
    my $c = shift;
    my $mysql = $c->component('MySQL');

    my $sth = $mysql->connection->prepare(q{show slave status});
    $sth->execute();
    my $status = $sth->fetchrow_hashref('NAME');

    if ( !$status ) {
        $c->ledge_set('sysinfo', {
            Replication => 'None',
        });
        return [undef,undef,undef];
    }

    my $io_running = $status->{Slave_IO_Running};
    my $sql_running = $status->{Slave_SQL_Running};
    my $sec = exists $status->{Seconds_Behind_Master} ? $status->{Seconds_Behind_Master} : undef;
    my $read = $status->{Read_Master_Log_Pos};
    my $exec = exists $status->{Exec_Master_Log_Pos} ? $status->{Exec_Master_Log_Pos} : $status->{Exec_master_log_pos};

    $c->ledge_set('sysinfo', {
        Replication => 'Yes',
        IO_Running => $io_running,
        SQL_Running => $sql_running,
        Master_Host => $status->{Master_Host},
        Master_Port => $status->{Master_Port},
        Last_Error => $status->{Last_Error},
    });
    return [$sec,$read,$exec];
};


__DATA__
@@ sec
DEF:my1=<%RRD%>:sec:AVERAGE
LINE1:my1#c03300:Seconds
GPRINT:my1:LAST:Cur\:%6.1lf
GPRINT:my1:AVERAGE:Ave\:%6.1lf
GPRINT:my1:MAX:Max\:%6.1lf
GPRINT:my1:MIN:Min\:%6.1lf\l

@@ pos
DEF:read=<%RRD%>:readpos:AVERAGE
DEF:exec=<%RRD%>:execpos:AVERAGE
CDEF:my1=read,exec,-,0,1000000000,LIMIT
AREA:my1#c00066:Position
GPRINT:my1:LAST:Cur\:%6.1lf
GPRINT:my1:AVERAGE:Ave\:%6.1lf
GPRINT:my1:MAX:Max\:%6.1lf
GPRINT:my1:MIN:Min\:%6.1lf\l
