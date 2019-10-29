#!/usr/bin/perl -w

use strict;

use Test::More tests => 26;
use Test::Exception;

use IO::Socket::UNIX;
use IO::Async::Notifier;

use IO::Poll;

use IO::Async::Set::IO_Poll;

( my $S1, my $S2 ) = IO::Socket::UNIX->socketpair( AF_UNIX, SOCK_STREAM, PF_UNSPEC ) or
   die "Cannot create socket pair - $!";

# Need sockets in nonblocking mode
$S1->blocking( 0 );
$S2->blocking( 0 );

my $readready = 0;
my $writeready = 0;

my $notifier = IO::Async::Notifier->new( handle => $S1,
   on_read_ready  => sub { $readready = 1 },
   on_write_ready => sub { $writeready = 1 },
);

my $poll = IO::Poll->new();

my $set = IO::Async::Set::IO_Poll->new( poll => $poll );

# Empty

my @handles;
@handles = $poll->handles();

is( scalar @handles, 0, '@handles empty' );

# Idle

$set->add( $notifier );

is( $notifier->__memberof_set, $set, '$notifier->__memberof_set == $set' );

dies_ok( sub { $set->add( $notifier ) }, 'adding again produces error' );

my $ready;
$ready = $poll->poll( 0.1 );

is( $ready, 0, '$ready idle' );

@handles = $poll->handles();
is( scalar @handles, 1, '@handles idle' );

# Read-ready

$S2->syswrite( "data\n" );

# We should still wait a little while even thought we expect to be ready
# immediately, because talking to ourself with 0 poll timeout is a race
# condition - we can still race with the kernel.

$ready = $poll->poll( 0.1 );

is( $ready, 1, '$ready readready' );

is( $readready, 0, '$readready before post_poll' );
$set->post_poll();
is( $readready, 1, '$readready after post_poll' );

# Ready $S1 to clear the data
$S1->getline(); # ignore return

# Write-ready
$notifier->want_writeready( 1 );

$ready = $poll->poll( 0.1 );

is( $ready, 1, '$ready writeready' );

is( $writeready, 0, '$writeready before post_poll' );
$set->post_poll();
is( $writeready, 1, '$writeready after post_poll' );

# loop_once

$writeready = 0;

$ready = $set->loop_once( 0.1 );

is( $ready, 1, '$ready after loop_once' );
is( $writeready, 1, '$writeready after loop_once' );

# loop_forever

my $stdout_io = IO::Handle->new_from_fd( fileno(STDOUT), 'w' );
my $stdout_notifier = IO::Async::Notifier->new( handle => $stdout_io,
   on_read_ready => sub { },
   on_write_ready => sub { $set->loop_stop() },
   want_writeready => 1,
);
$set->add( $stdout_notifier );

$writeready = 0;

$SIG{ALRM} = sub { die "Test timed out"; };
alarm( 1 );

$set->loop_forever();

alarm( 0 );

is( $writeready, 1, '$writeready after loop_forever' );

$set->remove( $stdout_notifier );

# HUP

$notifier->want_writeready( 0 );
$readready = 0;
$ready = $set->loop_once( 0.1 );

is( $ready, 0, '$ready before HUP' );
is( $readready, 0, '$readready before HUP' );

close( $S2 );

$readready = 0;
$ready = $set->loop_once( 0.1 );

is( $ready, 1, '$ready after HUP' );
is( $readready, 1, '$readready after HUP' );

# Removal

$set->remove( $notifier );

is( $notifier->__memberof_set, undef, '$notifier->__memberof_set is undef' );

@handles = $poll->handles();
is( scalar @handles, 0, '@handles after removal' );

# HUP of pipe

pipe( my ( $P1, $P2 ) ) or die "Cannot pipe() - $!";
my $pipe_io = IO::Handle->new_from_fd( fileno( $P1 ), 'r' );
my $pipe_notifier = IO::Async::Notifier->new( handle => $pipe_io,
   on_read_ready  => sub { $readready = 1 },
   want_writeready => 0,
);
$set->add( $pipe_notifier );

$readready = 0;
$ready = $set->loop_once( 0.1 );

is( $ready, 0, '$ready before pipe HUP' );
is( $readready, 0, '$readready before pipe HUP' );

close( $P2 );

$readready = 0;
$ready = $set->loop_once( 0.1 );

is( $ready, 1, '$ready after pipe HUP' );
is( $readready, 1, '$readready after pipe HUP' );

$set->remove( $pipe_notifier );

# Constructor with implied poll object

undef $set;
$set = IO::Async::Set::IO_Poll->new();

$set->add( $notifier );
$notifier->want_writeready( 1 );

$writeready = 0;

$ready = $set->loop_once( 0.1 );
is( $ready, 1, '$ready after loop_once with implied IO::Poll' );
is( $writeready, 1, '$writeready after loop_once with implied IO::Poll' );