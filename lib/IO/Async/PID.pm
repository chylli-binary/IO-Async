#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2010 -- leonerd@leonerd.org.uk

package IO::Async::PID;

use strict;
use warnings;
use base qw( IO::Async::Notifier );

our $VERSION = '0.32';

use Carp;

=head1 NAME

C<IO::Async::PID> - event callback on exit of a child process

=head1 SYNOPSIS

 use IO::Async::PID;
 use POSIX qw( WEXITSTATUS );

 use IO::Async::Loop;
 my $loop = IO::Async::Loop->new();

 my $kid = $loop->detach_child(
    code => sub {
       print "Child sleeping..\n";
       sleep 10;
       print "Child exiting\n";
       return 20;
    },
 );

 print "Child process $kid started\n";

 my $pid = IO::Async::PID->new(
    pid => $kid,

    on_exit => sub {
       my ( $self, $exitcode ) = @_;
       printf "Child process %d exited with status %d\n",
          $self->pid, WEXITSTATUS($exitcode);
    },
 );

 $loop->add( $pid );

 $loop->loop_forever;

=head1 DESCRIPTION

This subclass of L<IO::Async::Notifier> invokes its callback when a process
exits.

=cut

=head1 EVENTS

The following events are invoked, either using subclass methods or CODE
references in parameters:

=head2 on_exit $exitcode

Invoked when the watched process exits.

=cut

=head1 PARAMETERS

The following named parameters may be passed to C<new> or C<configure>:

=over 8

=item pid => INT

The process ID to watch. Can only be given at construction time.

=item on_exit => CODE

CODE reference for the C<on_exit> event.

=back

Once the C<on_exit> continuation has been invoked, the C<IO::Async::PID>
object is removed from the containing C<IO::Async::Loop> object.

=cut

sub _init
{
   my $self = shift;
   my ( $params ) = @_;

   # Not valid to watch for 0
   my $pid = delete $params->{pid} or croak "Expected 'pid'";

   $self->{pid} = $pid;

   $self->SUPER::_init( $params );
}

sub configure
{
   my $self = shift;
   my %params = @_;

   if( exists $params{on_exit} ) {
      $self->{on_exit} = delete $params{on_exit};

      undef $self->{cb};

      if( my $loop = $self->get_loop ) {
         $self->_remove_from_loop( $loop );
         $self->_add_to_loop( $loop );
      }
   }

   $self->SUPER::configure( %params );
}

sub _add_to_loop
{
   my $self = shift;
   my ( $loop ) = @_;

   # on_exit continuation gets passed PID value; need to replace that with
   # $self
   $self->{cb} ||= $self->_capture_weakself( sub {
      my ( $self, $pid, $exitcode ) = @_;

      $self->{on_exit} ? $self->{on_exit}->( $self, $exitcode )
                       : $self->on_exit( $exitcode );

      # Since this is a oneshot, we'll have to remove it from the loop or
      # parent Notifier
      $self->parent ? $self->parent->remove_child( $self ) 
                    : $self->get_loop->remove( $self );
   } );

   $loop->watch_child( $self->pid, $self->{cb} );
}

sub _remove_from_loop
{
   my $self = shift;
   my ( $loop ) = @_;

   $loop->unwatch_child( $self->pid );
}

=head1 METHODS

=cut

=head2 $process_id = $pid->pid

Returns the underlying process ID

=cut

sub pid
{
   my $self = shift;
   return $self->{pid};
}

=head2 $pid->kill( $signal )

Sends a signal to the process

=cut

sub kill
{
   my $self = shift;
   my ( $signal ) = @_;

   kill $signal, $self->pid or croak "Cannot kill() - $!";
}

# Keep perl happy; keep Britain tidy
1;

__END__

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>