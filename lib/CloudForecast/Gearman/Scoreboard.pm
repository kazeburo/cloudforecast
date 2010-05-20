package CloudForecast::Gearman::Scoreboard;

use strict;
use warnings;

use Fcntl qw(:DEFAULT :flock);
use File::Temp qw();
use POSIX qw(SEEK_SET);
use Scope::Guard;

use constant STATUS_NEXIST => '.';
use constant STATUS_IDLE   => '_';
use constant STATUS_ACTIVE => 'A';

=head1 ScoreBoard file format

score_board := slot | score_board slot ;
slot := status  pid  time "\n" ;
status := "." | "_" | "A"; # NEXIST or IDLE or Active
pid    := \d{14} ;
time := \d{14} ;
=cut

our $SLOT_SIZE = 1 + 14 + 14 + 1; # STATUS + PID + TIME + "\n";
our $EMPTY_SLOT = STATUS_NEXIST . (' ' x ($SLOT_SIZE - 2)) . "\n";

sub _format_slot {
    my ( $status, $pid, $time ) = @_;
    sprintf( "%1.1s%-14d%-14d\n",
             $status,
             $pid || 0,
             $time || time );
}

sub new {
    my ($klass, $filename, $max_workers) = @_;

    $filename ||= File::Temp::tempdir(CLEANUP => 1) . '/scoreboard';
    sysopen my $fh, $filename, O_RDWR | O_CREAT
        or die "failed to create scoreboard file:$filename:$!";
    my $wlen = syswrite $fh, $EMPTY_SLOT x $max_workers;
warn $filename;
    my $self = bless {
        filename    => $filename,
        fh          => $fh,
        max_workers => $max_workers,
        slot        => undef,
    }, $klass;
    $self;
}

sub get_statuses {
    my $self = shift;
    my $raw = $self->get_raw_statuses;
    my @s = map {
        $_ =~ /^(.)/ ? ($1) : ()
    } split /\n/, $raw;
    @s;
}

sub get_parsed_statuses {
    my $self = shift;
    my $raw = $self->get_raw_statuses;
    my @statuses;
    foreach my $line (split(/\n/, $raw)){
        my $status = substr( $line, 0, 1 );
        my $pid = substr( $line, 1, 14 );
        $pid =~ s/\D//g;
        my $time = substr( $line, 15, 14 );
        $time =~ s/\D//g;
        push @statuses, {
            status => $status,
            pid => $pid,
            time => $time,
        };
    }
    @statuses;
}

sub get_raw_statuses {
    my $self = shift;

    sysseek $self->{fh}, 0, SEEK_SET or die "seek failed:$!";
    sysread($self->{fh}, my $raw, $self->{max_workers} * $SLOT_SIZE)
        == $self->{max_workers} * $SLOT_SIZE
            or die "failed to read status:$!";
    $raw;
}


sub clear_child {
    my ($self, $pid) = @_;
    my $lock = $self->_lock_file;
    sysseek $self->{fh}, 0, SEEK_SET
        or die "seek failed:$!";
    for (my $slot = 0; $slot < $self->{max_workers}; $slot++) {
        my $rlen = sysread($self->{fh}, my $data, $SLOT_SIZE);
        die "unexpected eof while reading scoreboard file:$!"
            unless $rlen == $SLOT_SIZE;
        if ($data =~ /^.$pid .*\n$/) {
            # found
            sysseek $self->{fh}, $SLOT_SIZE * $slot, SEEK_SET
                or die "seek failed:$!";
            my $wlen = syswrite $self->{fh}, $EMPTY_SLOT;
            die "failed to clear scoreboard file:$self->{filename}:$!"
                unless $wlen == $SLOT_SIZE;
            last;
        }
    }
}

sub child_start {
    my $self = shift;

    die "child_start cannot be called twite"
        if defined $self->{slot};
    close $self->{fh}
        or die "failed to close scoreboard file:$!";
    sysopen $self->{fh}, $self->{filename}, O_RDWR
        or die "failed to create scoreboard file:$self->{filename}:$!";
    my $lock = $self->_lock_file;
    for ($self->{slot} = 0;
         $self->{slot} < $self->{max_workers};
         $self->{slot}++) {
        my $rlen = sysread( $self->{fh}, my $data, $SLOT_SIZE );
        die "unexpected response from sysread:$rlen, expected $SLOT_SIZE:$!"
            if $rlen != $SLOT_SIZE;
        if ($data =~ /^.[ ]+\n$/o) {
            last;
        }
    }
    die "no empty slot in scoreboard"
        if $self->{slot} >= $self->{max_workers};
    $self->set_status(STATUS_IDLE);
}

sub set_status {
    my ($self, $status) = @_;
    die "child_start not called?"
        unless defined $self->{slot};
    sysseek $self->{fh}, $self->{slot} * $SLOT_SIZE, SEEK_SET
        or die "seek failed:$!";
    my $wlen = syswrite $self->{fh}, _format_slot($status, $$);
    die "failed to write status into scoreboard:$!"
        unless $wlen == $SLOT_SIZE;
}

sub _lock_file {
    my $self = shift;
    my $fh = $self->{fh};
    flock $fh, LOCK_EX
        or die "failed to lock scoreboard file:$!";
    return Scope::Guard->new(
        sub {
            flock $fh, LOCK_UN
                or die "failed to unlock scoreboard file:$!";
        },
    );
}

1;


