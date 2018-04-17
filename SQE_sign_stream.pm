=pod

=head1 NAME

SQE_sign_stream - manages a stream of signs created by SQE_db->create_sign_stream_for_XXXX

=head1 VERSION

0.1.0

=head1 DESCRIPTION

The class manages the stream of signs which are connected by NEXT_SIGN_ID which points to a sibling.

The data are passed to this class as a reference to a hash containing all data of the signs.

The key is the SIGN_ID-

The value is an array containing arrays of the single data connected to this sign
(a sign may have more than one reading and a reading different attributes):

{
sign_id=>[
            [
             NEXT_SIGN_ID,
             SIGN_ID, SIGN,
             IS_VARIANT,
             ATTRIBUTE_ID,
             ATTRIBUTE_VALUE_ID,
             HAS_MULTIVALUES,
             ATTRIBUTE_NAME,
             ATTRIBUTE_VALUE
            ],
            [
             NEXT_SIGN_ID,
             SIGN_ID, SIGN,
             IS_VARIANT,
             ATTRIBUTE_ID,
             ATTRIBUTE_VALUE_ID,
             HAS_MULTIVALUES,
             ATTRIBUTE_NAME,
             ATTRIBUTE_VALUE
            ],
            ...
          ],
sign_id=>[ ... ]
}

This class provides the main functions to transform this data into strings with different formats.

The formats are defined in special classes

=head1 AUTHORS

Ingo Kottsieper

=head1 COPYRIGHT AND LICENSE


=cut


package SQE_sign_stream;
use strict;
use warnings FATAL => 'all';

=head1 Constants

Defining constants to access the data fields which are stored in an array.

The values must be synchronised with the MYSQL-FRAGMENT 'SIGN_QUERY_START' defined in SQE_dbi_queries.pm

=cut

use constant {
    NEXT_SIGN_ID       => 0,
    SIGN_ID            => 1,
    SIGN               => 2,
    IS_VARIANT         => 3,
    ATTRIBUTE_ID       => 4,
    ATTRIBUTE_VALUE_ID => 5,
    HAS_MULTIVALUES    => 6,
    ATTRIBUTE_NAME     => 7,
    ATTRIBUTE_VALUE    => 8
};


=head1 Functions

=head2 new($signs_ref, $current_sign_id)

Constructor

=over 1

=item Parameters: Reference to the data hash

=item Returns SQE_sign_stream

=back

=cut

#@returns SQE_sign_stream
sub new {
    my ($class, $signs_ref, $current_sign_id) = @_;
    my $self  = bless {
        signs_ref       => $signs_ref,
        current_sign_id => $current_sign_id,
        current_var_id  => 0,
    }, $class;
    return $self;
}



=head2 set_start_id($sign_id)

Sets the current_sign_id, which functions as start for further calls of next_sign

=over 1

=item Parameters: sign_id

=item Returns nothing

=back

=cut


sub set_start_id {
    my ($self, $sign_id) = @_;
    $self->{current_sign_id} = $sign_id;
    $self->{current_var_id} = 0;
}

=head2 set_signs_ref($signs_ref)

Sets a new referenc to a sign data hash.

=over 1

=item Parameters: Reference to sign data hash

=item Returns nothing

=back

=cut

sub set_signs_ref {
    my ($self, $signs_ref) = @_;
    $self->{current_signs_ref} = $signs_ref;

}

# Internal function which sets the the current sign id to the next value or to undef, if the end of the stream is reached.
# Returns the new id
sub _next_sign_id {
    my $self = shift;
    return $self->{current_sign_id} =
      $self->{signs_ref}->{ $self->{current_sign_id} }->[0]->[0];
}

# Returns the next sign in the stream or undef if the end was reached.
# Note - the next sign may also be a variant of the foregoing sign
# thus the sequence is: sign1 - sign2 - sign2_var1 - sign2_var_2 -sign3 ...
sub next_sign {
    my $self        = shift;
    my $old_sign_id = $self->{current_sign_id};
    my $next_sign;

# Try to load into $next_sign the next variant of the current_sign
# on succes, the variant index current_var_id is increased and points already
# to the next possible variant and $next_sign contains the reference to the next sign
# In this case we jump to elsif
    if ( $self->{current_sign_id} && not $next_sign =
        $self->{signs_ref}->{ $self->{current_sign_id} }
        ->[ ++$self->{current_var_id} ] )

 #this block is processed when no variant entrance for the current sign is found
    {
        #reset the variant index
        $self->{current_var_id} = 0;

        # return the next new sign if it exist
        if ( my $next_sign_id = $self->_next_sign_id ) {
            $next_sign = $self->{signs_ref}->{$next_sign_id}->[0];
            if ( $next_sign->[14] ) {
                pop @{$next_sign};
                $next_sign->[12] = undef;
            }
            return $next_sign;
        }
    }

# the next sign is a variant
# test whether it is a real variant for this scrollversion
# or found because there had been an entrance to sign_char_reading_data by a different scrollversion
# which should only be taken if there was no previous record whith the same sign_char_id
# in this case we proceed to the next sign by simply calling this function recursively
    elsif ( defined $next_sign && $next_sign->[14] ) {
        return $self->next_sign;
    }

# At this point $next_sign either refers to the next variant or is undefined because the end
# of the sign stream had been reached
    return $next_sign;
}

1;
