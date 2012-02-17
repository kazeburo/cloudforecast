package CloudForecast::Data::Basic;

use CloudForecast::Data -base;

# RRDファイルを作成
# [定義名,タイプ]
rrds map { [ $_, 'DERIVE' ] } qw /user nice system idle wait kernel interrupt/;
rrds 'load' => 'GAUGE';
rrds map { [ $_, 'GAUGE' ] } qw/totalswap availswap totalreal availreal totalfree shared buffer cached/;
rrds 'tcpestab' => 'GAUGE';

# グラフのリスト。HTMLでの順番
# [key, title , def template, callback]
#templateがscalarはget_data_section(Data::Section::Simple), scalarrefはそのもの
# templateは<%RRD%>をファイル名に置き換えて改行区切りで、rrdtool graphに渡される
# #から始まる行、<%RRD%> 以外の<%  %>はコメント、空行は切り詰め
# callbackがある場合は、<%RRD%>を置き換える前に渡せる、フィルタとかの処理ができる。
graphs 'cpu' => 'CPU Usage [%]' => 'cpu.def';
graphs 'load' => 'Load Average' => 'load.def';
graphs 'memory' => 'Memory Usage' => 'memory.def';
graphs 'tcpestab' => 'TCP Established' => 'tcpestab.def',  sub {
    my ($c,$template) = @_;
    return $template;
};

# 補助情報を出せます。[ key => value, key => value ]な配列のリファレンスで返します
sysinfo {
    my $c = shift;
    $c->ledge_get('sysinfo') || [];
};

# データを取得してくるところ
# initで定義した順番で、配列のリファレンスで返す
fetcher {
    my $c = shift;
    #$c->hostname $c->address $c->detail $c->component(SNMP)->..
    #$c->args->[0]...
    #$c->ledge_(get|add|set|delete)..

    #cpu
    my @map = map { [ $_, 0 ] } qw/ssCpuRawUser ssCpuRawNice ssCpuRawSystem
                                ssCpuRawIdle ssCpuRawWait ssCpuRawKernel ssCpuRawInterrupt/;
    #load
    push @map, [ 'laLoad', 1 ];
    # memory
    # memSharedは取れないので削除。memIndexをdummyに入れておく
    push @map, map { [ $_, 0 ] } qw/memTotalSwap memAvailSwap memTotalReal memAvailReal memTotalFree 
                            memIndex memBuffer memCached/;

    # tcp established
    push @map, [ 'tcpCurrEstab', 0 ];

    # sysinfo
    push @map, [ 'sysDescr', 0];
    push @map, [ 'hrSystemUptime', 0];

    # SNMP->get 配列のリファレンスが最終的に戻る
    my $ret = $c->component('SNMP')->get(@map);
    my $processor = $c->component('SNMP')->table('hrProcessorTable',columns=>[qw/hrProcessorLoad/]);

    #sysinfo
    my @sysinfo;
    my $uptime = pop @$ret;
    if ( defined $uptime ) {
        $uptime = $uptime / 100;
        my $day = int( $uptime /86400 );
        my $hour = int( ( $uptime % 86400 ) / 3600 );
        my $min = int( ( ( $uptime % 86400 ) % 3600) / 60 );
        push @sysinfo, 'uptime', sprintf("up %d days, %2d:%02d", $day, $hour, $min);
    }
    if ( $processor ) {
        my $core = scalar keys %$processor;
        push @sysinfo, 'cpu core' => $core if $core;
    }

    my $sysdescr = pop @$ret;
    push @sysinfo, system => $sysdescr;

    $c->ledge_set('sysinfo', \@sysinfo );

    return $ret;
};



__DATA__
@@ cpu.def
DEF:my1=<%RRD%>:user:AVERAGE
DEF:my2=<%RRD%>:nice:AVERAGE
DEF:my3=<%RRD%>:system:AVERAGE
DEF:my4=<%RRD%>:idle:AVERAGE
DEF:my5t=<%RRD%>:wait:AVERAGE
DEF:my6t=<%RRD%>:kernel:AVERAGE
DEF:my7t=<%RRD%>:interrupt:AVERAGE

CDEF:my5=my5t,UN,0,my5t,IF
CDEF:my6=my6t,UN,0,my6t,IF
CDEF:my7=my7t,UN,0,my7t,IF

CDEF:total=my1,my2,+,my3,+,my4,+,my5,+,my6,+,my7,+
CDEF:my1r=my1,total,/,100,*,0,100,LIMIT
CDEF:my2r=my2,total,/,100,*,0,100,LIMIT
CDEF:my3r=my3,total,/,100,*,0,100,LIMIT
CDEF:my4r=my4,total,/,100,*,0,100,LIMIT
CDEF:my5r=my5,total,/,100,*,0,100,LIMIT
CDEF:my6r=my6,total,/,100,*,0,100,LIMIT
CDEF:my7r=my7,total,/,100,*,0,100,LIMIT

AREA:my1r#c0c0c0:User  
GPRINT:my1r:LAST:Cur\:%5.1lf[%%]
GPRINT:my1r:AVERAGE:Ave\:%5.1lf[%%]
GPRINT:my1r:MAX:Max\:%5.1lf[%%]
GPRINT:my1r:MIN:Min\:%5.1lf[%%]\l
STACK:my2r#000080:Nice  
GPRINT:my2r:LAST:Cur\:%5.1lf[%%]
GPRINT:my2r:AVERAGE:Ave\:%5.1lf[%%]
GPRINT:my2r:MAX:Max\:%5.1lf[%%]
GPRINT:my2r:MIN:Min\:%5.1lf[%%]\l
STACK:my3r#008080:System
GPRINT:my3r:LAST:Cur\:%5.1lf[%%]
GPRINT:my3r:AVERAGE:Ave\:%5.1lf[%%]
GPRINT:my3r:MAX:Max\:%5.1lf[%%]
GPRINT:my3r:MIN:Min\:%5.1lf[%%]\l
STACK:my4r#800080:Idle  
GPRINT:my4r:LAST:Cur\:%5.1lf[%%]
GPRINT:my4r:AVERAGE:Ave\:%5.1lf[%%]
GPRINT:my4r:MAX:Max\:%5.1lf[%%]
GPRINT:my4r:MIN:Min\:%5.1lf[%%]\l
STACK:my5r#f00000:Wait  
GPRINT:my5r:LAST:Cur\:%5.1lf[%%]
GPRINT:my5r:AVERAGE:Ave\:%5.1lf[%%]
GPRINT:my5r:MAX:Max\:%5.1lf[%%]
GPRINT:my5r:MIN:Min\:%5.1lf[%%]\l
STACK:my6r#500000:Kernel
GPRINT:my6r:LAST:Cur\:%5.1lf[%%]
GPRINT:my6r:AVERAGE:Ave\:%5.1lf[%%]
GPRINT:my6r:MAX:Max\:%5.1lf[%%]
GPRINT:my6r:MIN:Min\:%5.1lf[%%]\l
STACK:my7r#0000E0:Intr  
GPRINT:my7r:LAST:Cur\:%5.1lf[%%]
GPRINT:my7r:AVERAGE:Ave\:%5.1lf[%%]
GPRINT:my7r:MAX:Max\:%5.1lf[%%]
GPRINT:my7r:MIN:Min\:%5.1lf[%%]\l

@@ load.def
DEF:my1=<%RRD%>:load:AVERAGE
AREA:my1#00C000:Load Average
GPRINT:my1:LAST:Cur\:%6.2lf
GPRINT:my1:AVERAGE:Ave\:%6.2lf
GPRINT:my1:MAX:Max\:%6.2lf
GPRINT:my1:MIN:Min\:%6.2lf\l

@@ memory.def
DEF:my1=<%RRD%>:totalswap:AVERAGE
DEF:my2=<%RRD%>:totalreal:AVERAGE
DEF:my3=<%RRD%>:availreal:AVERAGE
DEF:my4=<%RRD%>:totalfree:AVERAGE
DEF:my6=<%RRD%>:buffer:AVERAGE
DEF:my7=<%RRD%>:cached:AVERAGE
DEF:my8=<%RRD%>:availswap:AVERAGE

# used
CDEF:myelse=my2,my3,-,my7,-,my6,-,1024,*,0,34359738368,LIMIT
AREA:myelse#ffdd67:used      
GPRINT:myelse:LAST:Cur\:%6.2lf%sByte
GPRINT:myelse:AVERAGE:Ave\:%6.2lf%sByte
GPRINT:myelse:MAX:Max\:%6.2lf%sByte\l

# buffer
CDEF:my66=my6,1024,*,0,34359738368,LIMIT
STACK:my66#8a8ae6:buffer    
GPRINT:my66:LAST:Cur\:%6.2lf%sByte
GPRINT:my66:AVERAGE:Ave\:%6.2lf%sByte
GPRINT:my66:MAX:Max\:%6.2lf%sByte\l

# cached
CDEF:my77=my7,1024,*,0,34359738368,LIMIT
STACK:my77#6060e0:cached    
GPRINT:my77:LAST:Cur\:%6.2lf%sByte
GPRINT:my77:AVERAGE:Ave\:%6.2lf%sByte
GPRINT:my77:MAX:Max\:%6.2lf%sByte\l

# avail real
CDEF:my33=my3,1024,*,0,34359738368,LIMIT
STACK:my33#80e080:avail real
GPRINT:my33:LAST:Cur\:%6.2lf%sByte
GPRINT:my33:AVERAGE:Ave\:%6.2lf%sByte
GPRINT:my33:MAX:Max\:%6.2lf%sByte\l

# total real
CDEF:my222=my2,1024,*,0,34359738368,LIMIT
LINE2:my222#000080:total real
GPRINT:my222:LAST:Cur\:%6.2lf%sByte
GPRINT:my222:AVERAGE:Ave\:%6.2lf%sByte
GPRINT:my222:MAX:Max\:%6.2lf%sByte\l

# used swap
CDEF:my11=my1,my8,-,1024,*,0,34359738368,LIMIT
LINE2:my11#ff6060:used  swap
GPRINT:my11:LAST:Cur\:%6.2lf%sByte
GPRINT:my11:AVERAGE:Ave\:%6.2lf%sByte
GPRINT:my11:MAX:Max\:%6.2lf%sByte\l

@@ tcpestab.def
DEF:tcpestab=<%RRD%>:tcpestab:AVERAGE
AREA:tcpestab#00C000:Established
GPRINT:tcpestab:LAST:Cur\:%6.0lf
GPRINT:tcpestab:AVERAGE:Ave\:%6.0lf
GPRINT:tcpestab:MAX:Max\:%6.0lf
GPRINT:tcpestab:MIN:Min\:%6.0lf\l

