=pod

=head1 NAME

SQE_Format::Parent - Parent class to define formats to give out text data.

=head1 VERSION

0.1.0

=head1 DESCRIPTION

To define a format, one should create a child of this class, in which normally only the _Lable constants
need to be defined.



Such a _Lable constant consist of an anonymous array with up to six fields.

0: Printed as first part - can be used, e.g. in JSON to give a key ('"sign":')
1: Printed as before a single value
2: Printed after a single value
3: Printed before the first value of an array
4: Printed afte the last value of an array
5: Printed between vaules of an array.

The print function automatically distinguishs between the case of a singel value or an array of values.

=head1 AUTHORS

Ingo Kottsieper

=head1 COPYRIGHT AND LICENSE


=cut

package SQE_Format::Parent;
use strict;
use warnings FATAL => 'all';
use SQE_sign;
#use Exporter 'import';
#our @EXPORT = qw (print);

use constant {
    EXCLUDED_ATTRIBUTE_VALUES     => { 1 => 1 },

    SCROLL_ID => 0,
    SCROLL_NAME => 1,
    FRAG_ID => 2,
    FRAG_NAME => 3,
    LINE_ID =>4,
    LINE_NAME => 5,

    OUT_LABLE                     => 0,
    OUT_START                     => 1,
    OUT_END                       => 2,
    OUT_ARRAY_START               => 3,
    OUT_ARRAY_END                 => 4,
    OUT_SEPARATOR                 => 5,

    ALL_LABLE                     => [ '', '', '', '', '' ],

    SCROLLS_LABLE                  => [ '', '', '', '', '' ],

    SCROLL_LABLE                  => [ '', '', '', '', '' ],
    SCROLL_ID_LABLE               => [ '', '', '', '', '' ],
    SCROLL_NAME_LABLE             => [ '', '', '', '', '' ],

    FRAGS_LABLE                    => [ '', '', '', '', '' ],


    FRAG_LABLE                    => [ '', '', '', '', '' ],
    FRAG_ID_LABLE                 => [ '', '', '', '', '' ],
    FRAG_NAME_LABLE               => [ '', '', '', '', '' ],

    LINES_LABLE                    => [ '', '', '', '', '' ],


    LINE_LABLE                    => [ '', '', '', '', '' ],
    LINE_ID_LABLE                 => [ '', '', '', '', '' ],
    LINE_NAME_LABLE               => [ '', '', '', '', '' ],

    SIGNS_LABLE => [ '', '', '', '', '' ],

    SIGN_LABLE                    => [ '', '', '', '', '' ],
    SIGN_ID_LABLE                 => [ '', '', '', '', '' ],
    NEXT_SIGN_IDS_LABLE           => [ '', '', '', '', '' ],

    CHARS_LABLE                   => [ '', '', '', '', '' ],
    SIGN_CHAR_LABLE               => [ '', '', '', '', '' ],
    SIGN_CHAR_ID_LABLE            => [ '', '', '', '', '' ],
    SIGN_CHAR_CHAR_LABLE          => [ '', '', '', '', '' ],
    ATTRIBUTES_LABLE              => [ '', '', '', '', '' ],
    ATTRIBUTE_LABLE               => [ '', '', '', '', '' ],
    ATTRIBUTE_ID_LABLE            => [ '', '', '', '', '' ],
    ATTRIBUTE_NAME_LABLE          => [ '', '', '', '', '' ],
    ATTRIBUTE_VALUE_LABLE         => [ '', '', '', '', '' ],
    ATTRIBUTE_VALUE_ID_LABLE      => [ '', '', '', '', '' ],
    ATTRIBUTE_STRING_VALUE_LABLE  => [ '', '', '', '', '' ],
    ATTRIBUTE_NUMERIC_VALUE_LABLE => [ '', '', '', '', '' ]


};

=head1 Internal functions

=head2 _prepare_value($lables, $value)

Prepares a single value with the first part of the lable followed by the string to be used before
a single value, the value, and the part to be printed after the value

=over 1

=item Parameters: reference to the array which holds the lable strings, the value

=item Returns the formated string

=back

=cut

sub _prepare_value {
    my ($lables, $value) = @_;
    return $lables->[OUT_LABLE] . $lables->[OUT_START] . $value . $lables->[OUT_END];
}

=head2 _prepare_values($lables, $value)

Prepares an array of values with the first part of the lable followed by the string to be used before
a value array, the values of the array separated with the string to be printed between the single values,
and the part to be printed after the value

=over 1

=item Parameters: reference to the array which holds the lable strings, reference to the value array

=item Returns the formated string

=back

=cut

sub _prepare_values {
    my ($lables, $values) = @_;
    if (@$values > 1) {
        return $lables->[OUT_LABLE] . $lables->[OUT_ARRAY_START] . join($lables->[OUT_SEPARATOR], @$values) . $lables->[OUT_ARRAY_END];
    } elsif (@$values == 1) {
        return _prepare_value($lables, $values->[0]);
    }
}

=head2 _prepare_chars($sign_chars_ref)

Prepares the chars-part of a sign (= the readings of the sign with all its attributes)

Must be called as Class->_prepare_chars($attributes_ref)


=over 1

=item Parameters: reference to the chars array of a SQE_sign

=item Returns reference of an array with one string for each char

=back

=cut

sub _prepare_chars {
    my ($class, $sign_chars_ref) = @_;
    my $data = [];
    foreach my $char_data (@$sign_chars_ref) {
        my   $out.=_prepare_value($class->SIGN_CHAR_ID_LABLE, $char_data->{sign_char_id});
        $out.= _prepare_value($class->SIGN_CHAR_CHAR_LABLE, $char_data->{sign_char});
        $out .= _prepare_values($class->ATTRIBUTES_LABLE, $class->_prepare_attributes($char_data->{sign_attributes}));
        push @{$data}, $out;
    }
    return $data;
}

=head2 _prepare_attributes($attributes_ref)

Prepares the attributes-part of a char (= the attributes of a reading of the sign).

Must be called as Class->_prepare_attributes($attributes_ref)


=over 1

=item Parameters: reference to the attributes of a char of a SQE_sign

=item Returns reference of an array with one string for each attribute

=back

=cut

sub _prepare_attributes {
    my ($class, $attributes_ref) = @_;
    my $data = [];
    foreach my $char_data (@$attributes_ref) {
        next if $class->EXCLUDED_ATTRIBUTE_VALUES->{$char_data->{attribute_values}->[0]->{attribute_value_id}};
        my  $out .=   _prepare_value($class->ATTRIBUTE_ID_LABLE, $char_data->{attribute_id});
        $out.= _prepare_value($class->ATTRIBUTE_NAME_LABLE, $char_data->{attribute_name});
        $out .= _prepare_values($class->ATTRIBUTE_VALUE_LABLE, $class->_prepare_attribute_values($char_data->{attribute_values}));
        push @{$data}, $out;
    }
    return $data;
}


=head2 _prepare_attribute_values($values_ref)

Prepares the values of an attribute of a reading of the sign)

Must be called as Class->_prepare_attribute_values($attributes_ref)


=over 1

=item Parameters: current class, reference to the values of an attribute of a char of a SQE_sign

=item Returns reference of an array with one string for each value

=back

=cut

sub _prepare_attribute_values {
    my ($class, $values_ref) = @_;
    my $data=[];
    foreach my $char_data (@$values_ref) {
        my   $out .= _prepare_value($class->ATTRIBUTE_VALUE_ID_LABLE, $char_data->{attribute_value_id});
        if ($char_data->{attribute_numeric_value}) {
            $out .= _prepare_value($class->ATTRIBUTE_NUMERIC_VALUE_LABLE, $char_data->{attribute_numeric_value});
        } else {
            $out .= _prepare_value($class->ATTRIBUTE_STRING_VALUE_LABLE, $char_data->{attribute_string_value});
        }
        push @{$data}, $out;
    }
    return $data;
}

=head1 Public functions

=head2 print($signs)

Prints the data of the signs given in an array

Must be called with ClassName->print

=over 1

=item Parameters: reference to an array of SQE_signs

=item Returns

=back

=cut



#@method
sub print {
    my ($class, $signs, $key, $ref_data_sth, $scroll_verson_group_id) = @_;

    my $line_id=-1;
    my ($old_scroll_id, $old_frag_id, $old_line_id);
    # Start with the outer frame of text
    my $out = $class->ALL_LABLE->[OUT_LABLE] . $class->ALL_LABLE->[OUT_START];

    while (defined $key && defined $signs->{$key}->{line_id}) {
        if ($line_id != $signs->{$key}->{line_id}) {
            # If we start with a new line
            $line_id =$signs->{$key}->{line_id};

            # Retrieve the reference data
            $ref_data_sth->execute($key, $scroll_verson_group_id);
            my $ref_data_ref =$ref_data_sth->fetchrow_arrayref;

            # If a new scroll is starting
            if (!defined $old_scroll_id || $old_scroll_id != $ref_data_ref->[SCROLL_ID]) {
                if ($old_scroll_id) {
                    # If it is not the first scroll, colse the line and frag part and add a separator

                    $out .= $class->LINE_LABLE->[OUT_END];
                    $out .= $class->LINES_LABLE->[OUT_END];
                    $out .= $class->FRAG_LABLE->[OUT_END];
                    $out .= $class->FRAGS_LABLE->[OUT_END];

                    $out .= $class->SCROLLS_LABLE->[OUT_SEPARATOR];
                } else {
                    # If it is the first scroll start with the scroll array
                    $out .= $class->SCROLLS_LABLE->[OUT_LABLE] . $class->SCROLLS_LABLE->[OUT_START];
                }

                $out .= $class->SCROLL_LABLE->[OUT_LABLE] . $class->SCROLL_LABLE->[OUT_START];

                $old_scroll_id =$ref_data_ref->[SCROLL_ID];
                $old_frag_id = $ref_data_ref->[FRAG_ID];
                $old_line_id = $ref_data_ref->[LINE_ID];

                $out .= _prepare_value($class->SCROLL_ID_LABLE, $old_scroll_id);
                $out .= _prepare_value($class->SCROLL_NAME_LABLE, $ref_data_ref->[SCROLL_NAME]);

                $out .= $class->FRAGS_LABLE->[OUT_LABLE] . $class->FRAGS_LABLE->[OUT_START];
                $out .= $class->FRAG_LABLE->[OUT_LABLE] . $class->FRAG_LABLE->[OUT_START];
                $out .= _prepare_value($class->FRAG_ID_LABLE, $old_frag_id);
                $out .= _prepare_value($class->FRAG_NAME_LABLE, $ref_data_ref->[FRAG_NAME]);

                $out .= $class->LINES_LABLE->[OUT_LABLE] . $class->LINES_LABLE->[OUT_START];
                $out .= $class->LINE_LABLE->[OUT_LABLE] . $class->LINE_LABLE->[OUT_START];
                $out .= _prepare_value($class->LINE_ID_LABLE, $old_line_id);
                $out .= _prepare_value($class->LINE_NAME_LABLE, $ref_data_ref->[LINE_NAME]);
                $out .= $class->SIGNS_LABLE->[OUT_LABLE] . $class->SIGNS_LABLE->[OUT_START];
                $out .= $class->SIGN_LABLE->[OUT_START];

            } elsif ($old_frag_id != $ref_data_ref->[FRAG_ID]) {

                $out .= $class->SIGN_LABLE->[OUT_END];
                $out .= $class->SIGNS_LABLE->[OUT_END];
                $out .= $class->LINE_LABLE->[OUT_END];
                $out .= $class->LINES_LABLE->[OUT_END];
                $out .= $class->FRAGS_LABLE->[OUT_SEPARATOR];

                $out .= $class->FRAG_LABLE->[OUT_LABLE] . $class->FRAG_LABLE->[OUT_START];
                $old_frag_id = $ref_data_ref->[FRAG_ID];
                $old_line_id = $ref_data_ref->[LINE_ID];


                $out .= $class->LINES_LABLE->[OUT_LABLE] . $class->LINES_LABLE->[OUT_START];
                $out .= $class->LINE_LABLE->[OUT_LABLE] . $class->LINE_LABLE->[OUT_START];
                $out .= $class->SIGNS_LABLE->[OUT_LABLE] . $class->SIGNS_LABLE->[OUT_START];
                $out .= $class->SIGN_LABLE->[OUT_START];

            } else {
                $out .= $class->SIGN_LABLE->[OUT_END];
                $out .= $class->SIGNS_LABLE->[OUT_END];
                $out .= $class->LINES_LABLE->[OUT_SEPARATOR];
                $out .= _prepare_value($class->LINE_ID_LABLE, $old_line_id);
                $out .= _prepare_value($class->LINE_NAME_LABLE, $ref_data_ref->[LINE_NAME]);
                $out .= $class->SIGNS_LABLE->[OUT_LABLE] . $class->SIGNS_LABLE->[OUT_START];
                $out .= $class->SIGN_LABLE->[OUT_START];

            }

        } else {
                $out .= $class->SIGNS_LABLE->[OUT_SEPARATOR];
        }


        $out .= _prepare_value($class->SIGN_ID_LABLE, $key);
        $out .= _prepare_values($class->NEXT_SIGN_IDS_LABLE, $signs->{$key}->{next_sign_ids}) if $signs->{$key}->{next_sign_ids}->[0];
        $out .= _prepare_values($class->CHARS_LABLE, $class->_prepare_chars($signs->{$key}->{sign_chars}));

       #
        $key = $signs->{$key}->{next_sign_ids}->[0];
    }

    $out .= $class->SIGN_LABLE->[OUT_END];
    $out .= $class->SIGNS_LABLE->[OUT_END];
    $out .= $class->LINE_LABLE->[OUT_END];
    $out .= $class->LINES_LABLE->[OUT_END];
    $out .= $class->FRAG_LABLE->[OUT_END];
    $out .= $class->FRAGS_LABLE->[OUT_END];
    $out .= $class->SCROLL_LABLE->[OUT_END];
    $out .= $class->SCROLLS_LABLE->[OUT_END];

   print $out . $class->ALL_LABLE->[OUT_END];

}



1;