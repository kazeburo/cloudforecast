package CloudForecast::Component::MySQL;

use CloudForecast::Component -connector;
use DBI;

sub port {
    my $self = shift;
    $self->args->[0] || $self->config->{port};
}

sub connection {
    my $self = shift;

    my $dsn = "DBI:mysql:;hostname=".$self->address;
    if ( my $port = $self->port ) {
        $dsn .= ';port='.$port
    }

    eval {
        $self->{connection} ||= DBI->connect(
            $dsn,
            $self->config->{user} || 'root',
            $self->config->{password} || '',
            {
                RaiseError => 1,
            }
        );
    };
    die "connection failed to " . $self->address .": $@" if $@;

    $self->{connection};
}

sub version {
    my $self = shift;
    return $self->connection->get_info(18); # SQL_DBMS_VER
}

sub db {
    my $self = shift;
    if ( @_ ) {
        return $self->connection->do("use ?",undef,$_[0]);
    }
    $self->select_one("SELECT DATABASE()");
}

sub select_one {
    my $self = shift;
    my $query = shift;
    my @param = @_;
    my $row = $self->connection->selectrow_arrayref(
        $query,
        undef,
        @param
    );
    return unless $row;
    return $row->[0];
}

sub select_row {
    my $self = shift;
    my $query = shift;
    my @param = @_;
    my $row = $self->connection->selectrow_hashref(
        $query,
        undef,
        @param
    );
    return $row;
}

sub select_all {
    my $self = shift;
    my $query = shift;
    my @param = @_;
    my $rows = $self->connection->selectall_arrayref(
        $query,
        { Slice => {} },
        @param
    );
    return $rows;
}

1;


