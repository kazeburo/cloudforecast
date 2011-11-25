package CloudForecast::Data::Innodbtablespace;

use CloudForecast::Data -base;

rrds map { [ $_, 'GAUGE'] } qw/free/;

graphs 'free', 'InnoDB free tablespace';

title {
    my $c = shift;
    my $title='MySQL InnoDB free tablespace';
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

    die "missing args#2: db name"    unless $c->args->[1];
    die "missing args#3: table name" unless $c->args->[2];

    my $free;
    {
        my $query = sprintf(q{show table status from %s like '%s'},
                            $c->args->[1],
                            $c->args->[2],
                           );
        my $row = $c->component('MySQL')->select_row($query);
        $free = $row->{'Data_free'} if exists $row->{'Data_free'};
    }

    my %variable;
    {
        my $rows = $c->component('MySQL')->select_all(q{show variables like 'innodb\_%'});
        foreach my $row ( @$rows ) {
            $variable{lc($row->{Variable_name})} = $row->{Value};
        }
    }

    my @sysinfo;

    map { my $key = $_; $key =~ s/^innodb_//; push @sysinfo, $key, $variable{$_} } grep { exists $variable{$_} } qw(
        innodb_file_per_table
        innodb_data_file_path
        );

    $c->ledge_set('sysinfo', \@sysinfo);

    return [ $free ];
};

=encoding utf-8

=head1 NAME

CloudForecast::Data::Innodbtablespace - monitor free space of InnoDB tablespace

=head1 SYNOPSIS

    component_config:
    resources:
      - innodbtablespace::db_for_monitor:table_for_monitor

=head1 DESCRIPTION

InnoDBのテーブルスペースの残容量を監視します。

以下の場合にはこの監視項目は用なしです。

  * innodb_file_per_table を有効にして運用している。
  * innodb_file_per_table は無効だが、innodb_data_file_path で autoextend を指定している。

とはいえ、innodb_file_per_table を有効にしていても innodb_data_file_path は必要なので、その残量を監視したい場合は、一時的に innodb_file_per_table をオフにして監視用のテーブルを作るとよいです。

    set global innodb_file_per_table = 1;
    use db_for_monitor;
    create table table_for_monitor (i tinyint) engine=innodb;

=head1 AUTHOR

HIROSE Masaaki E<lt>hirose31@gmail.comE<gt>

=cut

__DATA__
@@ free
DEF:my1=<%RRD%>:free:AVERAGE
AREA:my1#1d71ff:Free 
GPRINT:my1:LAST:Cur\: %4.1lf%s
GPRINT:my1:MAX:Max\: %4.1lf%s
GPRINT:my1:MIN:Min\: %4.1lf%s\l
