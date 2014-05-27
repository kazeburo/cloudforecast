package CloudForecast::Data::Jvm;

use CloudForecast::Data -base;
use CloudForecast::Log;

=head1 NAME

CloudForecast::Data::Jvm - JVM resource monitor

=head1 SYNOPSIS

host_config:

    jvm:PROTOCOL:PORT:CONTEXT:LABEL


PROTOCOL: "http" or "https". default is "http".

PORT: port number of Jolokia. default is 8778.

CONTEXT: context (path in URL) of jolokia. default is "/jolokia".

LABEL: Arbitrary string, eg: name of target application. optional.

In following config, fetch metrics from "http://IPADDR:8780/jolokia"

    resources:
      - jvm::8780::MyJavaWorker

=head1 NOTICE

JMX (Jolokia) can't fetch information of S0 and S1 separately, can fetch only an active space (S0 or S1), so this module treats only active space as "MemoryPool/New:Survivor". Please notice that "Max" and "Committed" in "MemoryPool/New:Survivor" are a size of S0 or S1, are not total size of survivor space (S0 + S1).

=cut

use POSIX qw(strftime);
use JMX::Jmx4Perl;
use JMX::Jmx4Perl::Request;

rrds 'class_c' => 'GAUGE';

rrds 'thread_c'  => 'GAUGE';
rrds 'dthread_c' => 'GAUGE';

rrds 'ygc_c' => 'DERIVE';
rrds 'ygc_t' => 'DERIVE';
rrds 'fgc_c' => 'DERIVE';
rrds 'fgc_t' => 'DERIVE';

rrds 'm_h_max_s'   => 'GAUGE';
rrds 'm_h_comt_s'  => 'GAUGE';
rrds 'm_h_used_s'  => 'GAUGE';

rrds 'm_nh_max_s'  => 'GAUGE';
rrds 'm_nh_comt_s' => 'GAUGE';
rrds 'm_nh_used_s' => 'GAUGE';

rrds 'mp_eden_max_s'   => 'GAUGE';
rrds 'mp_eden_comt_s'  => 'GAUGE';
rrds 'mp_eden_used_s'  => 'GAUGE';

rrds 'mp_surv_max_s'   => 'GAUGE';
rrds 'mp_surv_comt_s'  => 'GAUGE';
rrds 'mp_surv_used_s'  => 'GAUGE';

rrds 'mp_old_max_s'   => 'GAUGE';
rrds 'mp_old_comt_s'  => 'GAUGE';
rrds 'mp_old_used_s'  => 'GAUGE';

rrds 'mp_perm_max_s'   => 'GAUGE';
rrds 'mp_perm_comt_s'  => 'GAUGE';
rrds 'mp_perm_used_s'  => 'GAUGE';

graphs 'class_c'  => 'Loaded class';
graphs 'thread_c' => 'Threads';
graphs 'gc_c'    => 'GC count [GC/sec]';
graphs 'gc_t'    => 'GC time [Elapsed/sec]';

graphs 'm_heap_s'    => 'Memory/Heap';
graphs 'm_nonheap_s' => 'Memory/Non-Heap';

graphs 'mp_eden_s' => 'MemoryPool/New:Eden';
graphs 'mp_surv_s' => 'MemoryPool/New:Survivor';
graphs 'mp_old_s'  => 'MemoryPool/Old';
graphs 'mp_perm_s' => 'MemoryPool/Permanent';

title {
    my $c = shift;

    my $port = $c->args->[1] || 8778;

    my $subtitle = $c->args->[3] ? $c->args->[3].":$port" : $port;
    return "JVM ($subtitle)";
};

sysinfo {
    my $c = shift;
    $c->ledge_get('sysinfo') || [];
};

fetcher {
    my $c = shift;

    my $gc = "Unknown";
    my $jmx = $c->component('Jolokia');
    my $res;
    my $value;

    ### LoadedClassCount
    $res = $jmx->request(
        JMX::Jmx4Perl::Request->new({
            type      => READ,
            mbean     => "java.lang:type=ClassLoading",
            attribute => "LoadedClassCount",
            method    => 'GET',
        }),
    );
    my $class_c = -1;
    if ($res->is_error) {
        CloudForecast::Log->warn($res->error_text);
    } else {
        $class_c = $res->value;
    }

    ### Threading
    $res = $jmx->request(
        JMX::Jmx4Perl::Request->new({
            type      => READ,
            mbean     => "java.lang:type=Threading",
            attribute => [qw(ThreadCount DaemonThreadCount)],
            method    => 'POST',
        }),
    );
    my($thread_c, $dthread_c) = (-1, -1);
    if ($res->is_error) {
        CloudForecast::Log->warn($res->error_text);
    } else {
        $value = $res->value;
        $thread_c  = $value->{ThreadCount};
        $dthread_c = $value->{DaemonThreadCount};
    }

    ### GarbageCollector
    $res = $jmx->request(
        JMX::Jmx4Perl::Request->new({
            type      => READ,
            mbean     => "java.lang:type=GarbageCollector,name=*",
            attribute => [qw(CollectionCount CollectionTime)],
            method    => 'POST',
        }),
    );
    my($ygc_c, $ygc_t, $fgc_c, $fgc_t) = (-1, -1, -1, -1);
    if ($res->is_error) {
        CloudForecast::Log->warn($res->error_text);
    } else {
        $value = $res->value;
        for my $collector (keys %$value) {
            if ($collector =~ /name=(?:PS Scavenge|ParNew)/) {
                $ygc_c = $value->{$collector}{CollectionCount};
                $ygc_t = $value->{$collector}{CollectionTime};
            } elsif ($collector =~ /name=(?:PS MarkSweep|ConcurrentMarkSweep)/) {
                $fgc_c = $value->{$collector}{CollectionCount};
                $fgc_t = $value->{$collector}{CollectionTime};
            } else {
                CloudForecast::Log->warn("unknown collector: $collector");
            }
        }

        # Detect name of garbage collector
        for my $collector (keys %$value) {
            if ($collector =~ /name=MarkSweep/) {
                $gc = "Serial";
                last;
            } elsif ($collector =~ /name=PS /) {
                $gc = "Parallel";
                last;
            } elsif ($collector =~ /name=ConcurrentMarkSweep/) {
                $gc = "Concurrent Mark & Sweep";
                last;
            } elsif ($collector =~ /name=G1 /) {
                $gc = "G1";
                last;
            }
        }
    }

    ### Memory
    $res = $jmx->request(
        JMX::Jmx4Perl::Request->new({
            type      => READ,
            mbean     => "java.lang:type=Memory",
            attribute => [qw(HeapMemoryUsage NonHeapMemoryUsage)],
            method    => 'POST',
        }),
    );
    my @m_heap = (-1, -1, -1);
    my @m_nonheap = (-1, -1, -1);
    if ($res->is_error) {
        CloudForecast::Log->warn($res->error_text);
    } else {
        $value = $res->value;
        @m_heap    = @{ $value->{HeapMemoryUsage} }{qw(max committed used)};
        @m_nonheap = @{ $value->{NonHeapMemoryUsage} }{qw(max committed used)};
    }

    ### MemoryPool
    $res = $jmx->request(
        JMX::Jmx4Perl::Request->new({
            type      => READ,
            mbean     => "java.lang:type=MemoryPool,name=*",
            attribute => [qw(Type Usage MemoryManagerNames)],
            method    => 'POST',
        }),
    );
    my @mp_eden = (-1, -1, -1);
    my @mp_surv = (-1, -1, -1);
    my @mp_old  = (-1, -1, -1);
    my @mp_perm = (-1, -1, -1);
    if ($res->is_error) {
        CloudForecast::Log->warn($res->error_text);
    } else {
        $value = $res->value;
        for my $mp (keys %$value) {
            if ($mp =~ /name=.*Eden Space/) {
                @mp_eden = @{ $value->{$mp}{Usage} }{qw(max committed used)}
            } elsif ($mp =~ /name=.*Survivor Space/) {
                @mp_surv = @{ $value->{$mp}{Usage} }{qw(max committed used)}
            } elsif ($mp =~ /name=.*(?:Tenured|Old) Gen/) {
                @mp_old  = @{ $value->{$mp}{Usage} }{qw(max committed used)}
            } elsif ($mp =~ /name=.*Perm Gen/) {
                @mp_perm = @{ $value->{$mp}{Usage} }{qw(max committed used)}
            } else {
                CloudForecast::Log->warn("unknown MemoryPool: $mp");
            }
        }
    }

    ### sysinfo
    $res = $jmx->request(
        JMX::Jmx4Perl::Request->new({
            type      => READ,
            mbean     => "java.lang:type=Runtime",
            attribute => [qw(StartTime VmVendor SystemProperties InputArguments VmName VmVendor)],
            method    => 'POST',
        }),
    );
    if ($res->is_error) {
        CloudForecast::Log->warn($res->error_text);
    } else {
        $value = $res->value;
        my @sysinfo;
        push @sysinfo, 'start', strftime("%Y-%m-%d %H:%M:%S", localtime( $value->{StartTime}/1000 ));
        push @sysinfo, 'VM', join(", ",
                                  $value->{VmName} || 'Unknown',
                                  $value->{SystemProperties}{'java.runtime.version'} || 'Unknown',
                                  $value->{VmVendor} || 'Unknown',
                              );
        push @sysinfo, 'GC', $gc;
        push @sysinfo, 'args', ref($value->{InputArguments}) eq 'ARRAY' ? join(" ", @{ $value->{InputArguments} }) : $value->{InputArguments};
        $c->ledge_set('sysinfo', \@sysinfo);
    }


    return [
        $class_c,
        $thread_c, $dthread_c,
        $ygc_c, $ygc_t, $fgc_c, $fgc_t,
        @m_heap, @m_nonheap,
        @mp_eden, @mp_surv, @mp_old, @mp_perm,
    ];
};

__DATA__
@@ class_c
DEF:my1=<%RRD%>:class_c:AVERAGE
AREA:my1#6060e0:Loaded class
GPRINT:my1:LAST:Cur\:%6.1lf
GPRINT:my1:AVERAGE:Ave\:%6.1lf
GPRINT:my1:MAX:Max\:%6.1lf
GPRINT:my1:MIN:Min\:%6.1lf\l

@@ thread_c
DEF:my1=<%RRD%>:thread_c:AVERAGE
DEF:my2=<%RRD%>:dthread_c:AVERAGE
LINE2:my1#008080:Total threads 
GPRINT:my1:LAST:Cur\:%6.1lf
GPRINT:my1:AVERAGE:Ave\:%6.1lf
GPRINT:my1:MAX:Max\:%6.1lf
GPRINT:my1:MIN:Min\:%6.1lf\l
LINE1:my2#000080:Daemon threads
GPRINT:my2:LAST:Cur\:%6.1lf
GPRINT:my2:AVERAGE:Ave\:%6.1lf
GPRINT:my2:MAX:Max\:%6.1lf
GPRINT:my2:MIN:Min\:%6.1lf\l

@@ gc_c
DEF:my1=<%RRD%>:ygc_c:AVERAGE
DEF:my2=<%RRD%>:fgc_c:AVERAGE
LINE2:my1#d1a2f6:Young Gen
GPRINT:my1:LAST:Cur\:%6.1lf
GPRINT:my1:AVERAGE:Ave\:%6.1lf
GPRINT:my1:MAX:Max\:%6.1lf
GPRINT:my1:MIN:Min\:%6.1lf\l
LINE1:my2#7020AF:Full     
GPRINT:my2:LAST:Cur\:%6.1lf
GPRINT:my2:AVERAGE:Ave\:%6.1lf
GPRINT:my2:MAX:Max\:%6.1lf
GPRINT:my2:MIN:Min\:%6.1lf\l

@@ gc_t
DEF:my1=<%RRD%>:ygc_t:AVERAGE
DEF:my2=<%RRD%>:fgc_t:AVERAGE
LINE2:my1#F0B300:Young Gen
GPRINT:my1:LAST:Cur\:%6.1lf
GPRINT:my1:AVERAGE:Ave\:%6.1lf
GPRINT:my1:MAX:Max\:%6.1lf
GPRINT:my1:MIN:Min\:%6.1lf\l
LINE1:my2#906D08:Full     
GPRINT:my2:LAST:Cur\:%6.1lf
GPRINT:my2:AVERAGE:Ave\:%6.1lf
GPRINT:my2:MAX:Max\:%6.1lf
GPRINT:my2:MIN:Min\:%6.1lf\l

@@ m_heap_s
DEF:my1=<%RRD%>:m_h_max_s:AVERAGE
DEF:my2=<%RRD%>:m_h_comt_s:AVERAGE
DEF:my3=<%RRD%>:m_h_used_s:AVERAGE
GPRINT:my1:LAST:Max\: %6.1lf%S\l
AREA:my2#afffb2:Committed
GPRINT:my2:LAST:Cur\:%6.1lf%S
GPRINT:my2:AVERAGE:Ave\:%6.1lf%S
GPRINT:my2:MAX:Max\:%6.1lf%S
GPRINT:my2:MIN:Min\:%6.1lf%S\l
LINE1:my2#00A000
AREA:my3#FFC0C0:Used     
GPRINT:my3:LAST:Cur\:%6.1lf%S
GPRINT:my3:AVERAGE:Ave\:%6.1lf%S
GPRINT:my3:MAX:Max\:%6.1lf%S
GPRINT:my3:MIN:Min\:%6.1lf%S\l
LINE1:my3#aa0000

@@ m_nonheap_s
DEF:my1=<%RRD%>:m_nh_max_s:AVERAGE
DEF:my2=<%RRD%>:m_nh_comt_s:AVERAGE
DEF:my3=<%RRD%>:m_nh_used_s:AVERAGE
GPRINT:my1:LAST:Max\: %6.1lf%S\l
AREA:my2#73b675:Committed
GPRINT:my2:LAST:Cur\:%6.1lf%S
GPRINT:my2:AVERAGE:Ave\:%6.1lf%S
GPRINT:my2:MAX:Max\:%6.1lf%S
GPRINT:my2:MIN:Min\:%6.1lf%S\l
LINE1:my2#3d783f
AREA:my3#b67777:Used     
GPRINT:my3:LAST:Cur\:%6.1lf%S
GPRINT:my3:AVERAGE:Ave\:%6.1lf%S
GPRINT:my3:MAX:Max\:%6.1lf%S
GPRINT:my3:MIN:Min\:%6.1lf%S\l
LINE1:my3#8b4444

@@ mp_eden_s
DEF:my1=<%RRD%>:mp_eden_max_s:AVERAGE
DEF:my2=<%RRD%>:mp_eden_comt_s:AVERAGE
DEF:my3=<%RRD%>:mp_eden_used_s:AVERAGE
GPRINT:my1:LAST:Max\: %6.1lf%S\l
AREA:my2#afffb2:Committed
GPRINT:my2:LAST:Cur\:%6.1lf%S
GPRINT:my2:AVERAGE:Ave\:%6.1lf%S
GPRINT:my2:MAX:Max\:%6.1lf%S
GPRINT:my2:MIN:Min\:%6.1lf%S\l
LINE1:my2#00A000
AREA:my3#FFC0C0:Used     
GPRINT:my3:LAST:Cur\:%6.1lf%S
GPRINT:my3:AVERAGE:Ave\:%6.1lf%S
GPRINT:my3:MAX:Max\:%6.1lf%S
GPRINT:my3:MIN:Min\:%6.1lf%S\l
LINE1:my3#aa0000

@@ mp_surv_s
DEF:my1=<%RRD%>:mp_surv_max_s:AVERAGE
DEF:my2=<%RRD%>:mp_surv_comt_s:AVERAGE
DEF:my3=<%RRD%>:mp_surv_used_s:AVERAGE
GPRINT:my1:LAST:Max\: %6.1lf%S\l
AREA:my2#afffb2:Committed
GPRINT:my2:LAST:Cur\:%6.1lf%S
GPRINT:my2:AVERAGE:Ave\:%6.1lf%S
GPRINT:my2:MAX:Max\:%6.1lf%S
GPRINT:my2:MIN:Min\:%6.1lf%S\l
LINE1:my2#00A000
AREA:my3#FFC0C0:Used     
GPRINT:my3:LAST:Cur\:%6.1lf%S
GPRINT:my3:AVERAGE:Ave\:%6.1lf%S
GPRINT:my3:MAX:Max\:%6.1lf%S
GPRINT:my3:MIN:Min\:%6.1lf%S\l
LINE1:my3#aa0000

@@ mp_old_s
DEF:my1=<%RRD%>:mp_old_max_s:AVERAGE
DEF:my2=<%RRD%>:mp_old_comt_s:AVERAGE
DEF:my3=<%RRD%>:mp_old_used_s:AVERAGE
GPRINT:my1:LAST:Max\: %6.1lf%S\l
AREA:my2#afffb2:Committed
GPRINT:my2:LAST:Cur\:%6.1lf%S
GPRINT:my2:AVERAGE:Ave\:%6.1lf%S
GPRINT:my2:MAX:Max\:%6.1lf%S
GPRINT:my2:MIN:Min\:%6.1lf%S\l
LINE1:my2#00A000
AREA:my3#FFC0C0:Used     
GPRINT:my3:LAST:Cur\:%6.1lf%S
GPRINT:my3:AVERAGE:Ave\:%6.1lf%S
GPRINT:my3:MAX:Max\:%6.1lf%S
GPRINT:my3:MIN:Min\:%6.1lf%S\l
LINE1:my3#aa0000

@@ mp_perm_s
DEF:my1=<%RRD%>:mp_perm_max_s:AVERAGE
DEF:my2=<%RRD%>:mp_perm_comt_s:AVERAGE
DEF:my3=<%RRD%>:mp_perm_used_s:AVERAGE
GPRINT:my1:LAST:Max\: %6.1lf%S\l
AREA:my2#73b675:Committed
GPRINT:my2:LAST:Cur\:%6.1lf%S
GPRINT:my2:AVERAGE:Ave\:%6.1lf%S
GPRINT:my2:MAX:Max\:%6.1lf%S
GPRINT:my2:MIN:Min\:%6.1lf%S\l
LINE1:my2#3d783f
AREA:my3#b67777:Used     
GPRINT:my3:LAST:Cur\:%6.1lf%S
GPRINT:my3:AVERAGE:Ave\:%6.1lf%S
GPRINT:my3:MAX:Max\:%6.1lf%S
GPRINT:my3:MIN:Min\:%6.1lf%S\l
LINE1:my3#8b4444
