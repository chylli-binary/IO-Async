#!/usr/bin/perl

use strict;
use warnings;

use IO::Async::Test;

use Test::More;

use IO::Async::Loop;

use IO::Async::Handle;

my $loop = IO::Async::Loop->new_builtin;

testing_loop( $loop );

# ->bind a UDP service
{
   my $recv_count;

   my $receiver = IO::Async::Handle->new(
      on_read_ready => sub { $recv_count++ },
      on_write_ready => sub { },
   );
   $loop->add( $receiver );

   $receiver->bind(
      service  => "0",
      socktype => "dgram",
   )->get;

   ok( $receiver->read_handle->sockport, '$receiver bound to a read handle' );
}

done_testing;
