binmode STDOUT, ":encoding(UTF-8)";
=pod

=head1 NAME

SQE_sign - Manages data of a sign

=head1 VERSION

0.1.0

=head1 DESCRIPTION

The constructor tales a rekerence to a record of sign data to which other data can be added.

The collected data can be returned in different formats defined in format files

=head1 AUTHORS

Ingo Kottsieper

=head1 COPYRIGHT AND LICENSE


=cut

package SQE_sign;
use strict;
use warnings FATAL => 'all';

=head1 Constants

Defining constants to access the data fields which are stored in an array.

The values must be synchronised with the MYSQL-FRAGMENT 'SIGN_QUERY_START' defined in SQE_dbi_queries.pm

=cut

use constant {
    NEXT_SIGN_ID            => 0,
    SIGN_ID                 => 1,
    SIGN_CHAR_ID            => 2,
    SIGN_CHAR               => 3,
    IS_VARIANT              => 4,
    ATTRIBUTE_ID            => 5,
    ATTRIBUTE_VALUE_ID      => 6,
    ATTRIBUTE_NAME          => 7,
    ATTRIBUTE_STRING_VALUE  => 8,
    ATTRIBUTE_NUMERIC_VALUE => 9,
    LINE_ID                 => 10

};

=head2 new($sign_data_ref)

Creates a new instance of SQE_sign from a given refrence to sign data

=over 1

=item Parameters: Reference to sign data

=item Returns SQE_sign

=back

=cut

#@returns SQE_sign
sub new {
    my ( $class, $sign_data_ref ) = @_;
    my $self = {
        sign_id       => $sign_data_ref->[SIGN_ID],
        next_sign_ids => [ $sign_data_ref->[NEXT_SIGN_ID]  ],
        line_id => $sign_data_ref->[LINE_ID],
        sign_chars    => []
    };
    bless $self, $class;
    $self->_add_new_char($sign_data_ref);
    return $self;
}

=head2 _add_new_char($sign_data_ref)

Internal function which creates the sign_char part of a sign from a given refernece to sign data

=over 1

=item Parameters: Reference to sign data

=item Returns nothing

=back

=cut

sub _add_new_char {
    my ( $self, $sign_data_ref ) = @_;
    push @{$self->{sign_chars}},
      {
        sign_char_id    => $sign_data_ref->[SIGN_CHAR_ID],
        sign_char       => $sign_data_ref->[SIGN_CHAR],
        sign_attributes => []
      };
    $self->_add_new_attribute($sign_data_ref);

}

=head2 _add_new_attribute($sign_data_ref)

Internal function which creates the attribute part of a sign from a given refernece to sign data

=over 1

=item Parameters: Reference to sign data

=item Returns nothing

=back

=cut

sub _add_new_attribute {
    my ( $self, $sign_data_ref ) = @_;
    push @{$self->{sign_chars}->[-1]->{sign_attributes}},

      {
        attribute_id     => $sign_data_ref->[ATTRIBUTE_ID],
        attribute_name   => $sign_data_ref->[ATTRIBUTE_NAME],
        attribute_values => []
      };
    $self->_add_new_attribute_value($sign_data_ref);

}

sub _add_new_attribute_value {
    my ( $self, $sign_data_ref ) = @_;
    push @{$self->{sign_chars}->[-1]->{sign_attributes}->[-1]->{attribute_values}},
      {
        attribute_value_id     => $sign_data_ref->[ATTRIBUTE_VALUE_ID],
        attribute_string_value => $sign_data_ref->[ATTRIBUTE_STRING_VALUE],
        attribute_numeric_value =>
          $sign_data_ref->[ATTRIBUTE_NUMERIC_VALUE]
      };
}

=head2 add_data($sign_data_ref)

Adds the data referenced by $sign_data_ref to the sign.

If the data refer to a different sign, a new SQE_sign instance with these data will be returned, otherwise sef

=over 1

=item Parameters: Reference to sign data

=item Returns SQE_sign (either $self or a new instance)

=back

=cut

#@returns SQE_sign
sub add_data {
    my ( $self, $sign_data_ref ) = @_;

    # Test whether we deal with data of this sign
    # If not, create a ndew instance of SQE_sign with the given data
    # and return the new instance
    if ( $sign_data_ref->[SIGN_ID] != $self->{sign_id} ) {
        return SQE_sign->new($sign_data_ref);
    }

    # Otherwise add the data this instance
    # First we add the next sign id if different from the last one

    push @{$self->{next_sign_ids}}, $sign_data_ref->[NEXT_SIGN_ID]
      if defined $sign_data_ref->[NEXT_SIGN_ID] && $self->{next_sign_ids}->[-1] != $sign_data_ref->[NEXT_SIGN_ID];

    # Test whether the data refers to a new char(reading) of the sing
    if ( $self->{sign_chars}->[-1]->{sign_char_id} !=
        $sign_data_ref->[SIGN_CHAR_ID] )
    {
        # In this case add the new char with the data referred to
        $self->_add_new_char($sign_data_ref);
    }
    elsif (
        # Otherwise test, if we handle a new attribute
        $self->{sign_chars}->[-1]->{sign_attributes}->[-1]->{attribute_id}
        != $sign_data_ref->[ATTRIBUTE_ID]
      )
    {
        # In this case add the new atttribute with its values
        $self->_add_new_attribute($sign_data_ref);
    }
    else {
        # Otherwise si ple adds the values to the last attribute added
        $self->_add_new_attribute_value($sign_data_ref);
    }

    return $self;
}

1;
