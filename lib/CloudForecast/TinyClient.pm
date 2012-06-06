package CloudForecast::TinyClient;

use strict;
use warnings;
use Errno qw(EAGAIN ECONNRESET EINPROGRESS EINTR EWOULDBLOCK ECONNABORTED EISCONN);
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK SEEK_SET SEEK_END);
use Socket qw(
    PF_INET SOCK_STREAM
    IPPROTO_TCP
    TCP_NODELAY
    pack_sockaddr_in
);
use Time::HiRes qw(time);

use constant WIN32 => $^O eq 'MSWin32';

my $BUFSIZE = 10240;

sub new {
    my $class = shift;
    my ( $host, $port, $timeout ) = @_;
    $timeout ||= 10;
    my $self = bless {
        host => $host,
        port => $port,
        timeout => $timeout
    }, $class;
    my ($sock, $error) = $self->connect( $host, $port, time + $self->{timeout} );
    die $error unless $sock;
    $self->{sock} = $sock;
    $self;
}

sub write : method {
    my $self = shift;
    my $buf = shift;
    my $timeout = shift;
    $timeout ||= $self->{timeout};
    my $timeout_at = time + $timeout;

    my $off = 0;
    while (my $len = length($buf) - $off) {
        my $ret = $self->write_timeout($self->{sock}, $buf, $len, $off, $timeout_at)
            or return undef;
        $off += $ret;
    }
    return $off;
}


sub read : method {
    my $self = shift;
    my $timeout = shift;
    $timeout ||= $self->{timeout};
    my $timeout_at = time + $timeout;
    my $buf = '';
    my $n = $self->read_timeout($self->{sock},
        \$buf, 10240, length($buf), $timeout_at);
    die _strerror_or_timeout() if ( ! defined $n );
    return $buf;
}


sub connect : method {
    my $self = shift;
    my ( $host, $port, $timeout_at ) = @_;

    my $timeout = $timeout_at - time;
    return (undef, "Failed to resolve host name: timeout")
        if $timeout <= 0;
    my $sock;

    my $ipaddr = Socket::inet_aton($host)
        or return (undef, "Cannot resolve host name: $host, $!");
    my $sock_addr = pack_sockaddr_in($port, $ipaddr);

 RETRY:
    socket($sock, PF_INET, SOCK_STREAM, 0)
        or Carp::croak("Cannot create socket: $!");
    _set_sockopts($sock);
    if (connect($sock, $sock_addr)) {
        # connected
    } elsif ($! == EINPROGRESS || (WIN32 && $! == EWOULDBLOCK)) {
        $self->do_select(1, $sock, $timeout_at)
            or return (undef, "Cannot connect to ${host}:${port}: timeout");
        # connected
    } else {
        if ($! == EINTR && ! $self->{stop_if}->()) {
            close $sock;
            goto RETRY;
        }
        return (undef, "Cannot connect to ${host}:${port}: $!");
    }
    $sock;
}

sub write_timeout {
    my ($self, $sock, $buf, $len, $off, $timeout_at) = @_;
    my $ret;
    while(1) {
        # try to do the IO
        defined($ret = syswrite($sock, $buf, $len, $off))
            and return $ret;
        if ($! == EAGAIN || $! == EWOULDBLOCK || (WIN32 && $! == EISCONN)) {
            # pass thru
        } elsif ($! == EINTR) {
            return undef if $self->{stop_if}->();
            # otherwise pass thru
        } else {
            return undef;
        }
        $self->do_select(1, $sock, $timeout_at) or return undef;
    }
}

sub read_timeout {
    my ($self, $sock, $buf, $len, $off, $timeout_at) = @_;
    my $ret;
    # NOTE: select-read-select may get stuck in SSL,
    #       so we use read-select-read instead.
    while(1) {
        # try to do the IO
        defined($ret = sysread($sock, $$buf, $len, $off))
            and return $ret;
        if ($! == EAGAIN || $! == EWOULDBLOCK || (WIN32 && $! == EISCONN)) {
            # pass thru
        } elsif ($! == EINTR) {
            return undef if $self->{stop_if}->();
            # otherwise pass thru
        } else {
            return undef;
        }
        # on EINTER/EAGAIN/EWOULDBLOCK
        $self->do_select(0, $sock, $timeout_at) or return undef;
    }
}

sub _set_sockopts {
    my $sock = shift;

    setsockopt( $sock, IPPROTO_TCP, TCP_NODELAY, 1 )
        or Carp::croak("Failed to setsockopt(TCP_NODELAY): $!");
    if (WIN32) {
        if (ref($sock) ne 'IO::Socket::SSL') {
            my $tmp = 1;
            ioctl( $sock, 0x8004667E, \$tmp )
                or Carp::croak("Cannot set flags for the socket: $!");
        }
    } else {
        my $flags = fcntl( $sock, F_GETFL, 0 )
            or Carp::croak("Cannot get flags for the socket: $!");
        $flags = fcntl( $sock, F_SETFL, $flags | O_NONBLOCK )
            or Carp::croak("Cannot set flags for the socket: $!");
    }

    {
        # no buffering
        my $orig = select();
        select($sock); $|=1;
        select($orig);
    }

    binmode $sock;
}

sub _strerror_or_timeout {
    $! != 0 ? "$!" : 'timeout';
}

sub do_select {
    my($self, $is_write, $sock, $timeout_at) = @_;
    # wait for data
    while (1) {
        my $timeout = $timeout_at - time;
        if ($timeout <= 0) {
            $! = 0;
            return 0;
        }
        my($rfd, $wfd);
        my $efd = '';
        vec($efd, fileno($sock), 1) = 1;
        if ($is_write) {
            $wfd = $efd;
        } else {
            $rfd = $efd;
        }
        my $nfound   = select($rfd, $wfd, $efd, $timeout);
        return 1 if $nfound > 0;
        return 0 if $nfound == -1 && $! == EINTR && $self->{stop_if}->();
    }
    die 'not reached';
}

1;



