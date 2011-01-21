package CloudForecast::Ledge;

use strict;
use warnings;
use base qw/Class::Accessor::Fast/;
use Storable qw//;
use MIME::Base64 qw//;
use Digest::MD5 qw//;
use Path::Class;
use DBI;
use Carp;

__PACKAGE__->mk_accessors(qw/data_dir db_name/);

sub new {
    my $class = shift;
    my $args = ref $_[0] ? shift : { @_ };

    Carp::croak "no data_dir" unless $args->{data_dir};
    my $self = $class->SUPER::new({
        data_dir => $args->{data_dir},
        db_name => $args->{db_name} || 'cloudforecast.db',
        _connection => '',
    });
    $self;
}

sub db_path {
    my $self = shift;
    return Path::Class::file(
        $self->data_dir,
        $self->db_name )->cleanup;
}

sub connection {
    my $self = shift;
    my $db_path = $self->db_path;

    my $dbh = DBI->connect( "dbi:SQLite:dbname=$db_path","","",
                            { RaiseError => 1, AutoCommit => 1 } );
    $dbh->do(<<EOF);
CREATE TABLE IF NOT EXISTS ledge (
    resource_name VARCHAR(255) NOT NULL,
    address VARCHAR(255) NOT NULL,
    key VARCHAR(255) NOT NULL,
    data TEXT,
    csum VARCHAR(16) NOT NULL,
    delete_in UNSIGNED INT NOT NULL DEFAULT 0,
    PRIMARY KEY ( resource_name, address, key )
)
EOF

    $dbh->do(<<EOF);
CREATE INDEX IF NOT EXISTS index_delete_in ON ledge ( delete_in )
EOF

    $dbh;
}

sub add {
    my $self = shift;
    my ( $resource_name, $address, $key, $data, $expire ) = @_;
    Carp::croak 'no resource_name' unless $resource_name;
    Carp::croak 'no address' unless $address;
    Carp::croak 'no key' unless $key;

    my $delete_in = 0;
    $delete_in = time + $expire if $expire;
    my $csum = substr Digest::MD5::md5_hex($$ . $self . join("\0", @_) . rand(1000) ), 0, 16;
    my $freeze = MIME::Base64::encode_base64(Storable::nfreeze(\$data));

    my $dbh = $self->connection;
    $dbh->begin_work;

    my $now = time;
    $dbh->do("DELETE FROM ledge WHERE resource_name = ? AND address = ? AND key = ? AND ( delete_in <= ? AND delete_in > 0 )",
         undef, $resource_name, $address, $key, $now );

    my $sth = $dbh->prepare(<<EOF);
INSERT OR IGNORE INTO ledge ( resource_name, address, key, data, csum, delete_in )
values ( ?, ?, ?, ?, ?, ? );
EOF

    my $row;
    eval {
        $row = $sth->execute( $resource_name, $address, $key, $freeze, $csum, $delete_in );
    };

    $dbh->commit;
    Carp::croak "add failed :$@" if $@;
    
    return $row != 0;
}

sub set {
    my $self = shift;
    my ( $resource_name, $address, $key, $data, $expire, $csum ) = @_;
    Carp::croak 'no resource_name' unless $resource_name;
    Carp::croak 'no address' unless $address;
    Carp::croak 'no key' unless $key;

    my $delete_in = 0;
    $delete_in = time + $expire if $expire;
    my $new_csum = substr Digest::MD5::md5_hex($$ . $self . join("\0", @_) . rand(1000) ), 0, 16;
    my $freeze = MIME::Base64::encode_base64(Storable::nfreeze(\$data));

    if ( $csum ) {
        # check_sum付きのupdateで対象レコードがなかった場合は、新たにinsertとかしない
        my $sth = $self->connection->prepare(<<EOF);
UPDATE ledge SET data = ?, delete_in = ?, csum = ?  WHERE resource_name = ? AND address = ? AND key = ? AND csum = ?
EOF
        my $row;
        eval {
            $row = $sth->execute( $freeze, $delete_in, $new_csum,
                       $resource_name, $address, $key, $csum );
        };
        Carp::croak "set failed :$@" if $@;
        return $row != 0;
    }
    
    my $dbh = $self->connection;
    $dbh->begin_work;
    my $sth = $dbh->prepare(<<EOF);
UPDATE ledge SET data = ?, delete_in =?, csum = ? WHERE resource_name = ? AND address = ? AND key = ?
EOF
    my $row;
    eval {
        $row = $sth->execute($freeze, $delete_in, $new_csum, 
                  $resource_name, $address, $key );
    };
    if ( $@ ) {
        eval { $dbh->rollback };
        Carp::croak "set(update) failed: $@";
    }

    if ( $row == 0 ) {
        my $sth = $dbh->prepare(<<EOF);
INSERT INTO ledge ( resource_name, address, key, data, csum, delete_in )
values ( ?, ?, ?, ?, ?, ? );
EOF
        eval {
            $row = $sth->execute($resource_name, $address, $key,
                                 $freeze, $new_csum, $delete_in );
        };
        if ( $@ ) {
            eval { $dbh->rollback };
            Carp::croak "set(insert) failed: $@";
        }
    }

    $dbh->commit;

    return $row != 0;
}

sub get {
    my $self = shift;
    my ( $resource_name, $address, $key ) = @_;
    my $dbh = $self->connection;
    my $sth = $dbh->prepare(<<EOF);
SELECT data, csum, delete_in FROM ledge WHERE resource_name = ? AND address = ? AND key =?
EOF
    eval {
        $sth->execute($resource_name, $address, $key);
    };
        Carp::croak "get failed :$@" if $@;

    my $row = $sth->fetchrow_hashref;
    return unless $row;
    return if $row->{delete_in} > 0 && $row->{delete_in} <= time;

    my $data;
    eval {
        $data = Storable::thaw(MIME::Base64::decode_base64($row->{data}));
        $data or die "failed";
    };
    Carp::croak "faied get(thaw): $@" if $@;
        
    return wantarray ? ( $$data, $row->{csum} ) : $$data;
}

sub get_multi_by_address {
    my $self = shift;
    my ( $resource_name, $key, $address ) = @_;
    Carp::croak "address must be arrayref" if !ref($address) || ref($address) ne 'ARRAY';

    my $dbh = $self->connection;
    my $placeholder =  "(" . join(",", map { "?" } @$address ) . ")";
    my $sth = $dbh->prepare(<<EOF);
SELECT address, data, csum, delete_in FROM ledge WHERE resource_name = ? AND key =? AND address IN $placeholder
EOF

    eval {
        $sth->execute($resource_name, $key, @$address);
    };
    Carp::croak "get failed :$@" if $@;

    my %ret;
    while( my $row = $sth->fetchrow_hashref ) {
        next if $row->{delete_in} > 0 && $row->{delete_in} <= time;
        my $data;
        eval {
            $data = Storable::thaw(MIME::Base64::decode_base64($row->{data}));
            $data or die "failed";
        };
        Carp::croak "faied get(thaw): $@" if $@;

        $ret{$row->{address}} = $$data;
    }

    return \%ret;
}

sub delete {
    my $self = shift;
    my ( $resource_name, $address, $key ) = @_;
    my $row = $self->connection->do("DELETE FROM ledge WHERE resource_name = ? AND address = ? AND key = ?",
         undef, $resource_name, $address, $key );
    return $row != 0;
}

sub expire {
    my $self = shift;
    my $now = time;
    my $row = $self->connection->do("DELETE FROM ledge WHERE delete_in <= ? AND delete_in > 0",
         undef, $now );
    return $row;
}

1;

