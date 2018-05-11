=head1 NAME

SQE_CGI - an expanded Perl-CGI

=head1 VERSION

0.1.0

=head1 DESCRIPTION



=head1 AUTHORS

Ingo Kottsieper

=head1 COPYRIGHT AND LICENSE


=head1 Predefined Keys


=over 1

=item CGIDATA = Hashref to JSON object conatining the parameters send to the CGI by the browser

=item DBH = SQE_db database handler


=back

=head1 Methods

=cut

package SQE_CGI;
use strict;
use warnings FATAL => 'all';
use Data::UUID;
use SQE_DBI;
use SQE_CGI_queries;
use SQE_Session::Container;
use JSON qw( decode_json );
use CGI::Carp qw(fatalsToBrowser);

use parent 'CGI';

our Container $sqe_sessions;

#@returns SQE_CGI
sub new {
    my ( $class) = @_;

    # $sqe->sessions should be initialised only once
    $sqe_sessions = Container->new if !defined $sqe_sessions;

    my SQE_CGI $self = $class->SUPER::new(@ARGV);
    bless $self, 'SQE_CGI';

    #We give out only JSON objects
    $self->print( $self->header('application/json;charset=UTF-8') );


    my $content_type   = $self->content_type();
    my $request_method = $self->request_method();
    my $error_ref;

    # We only want JSON as POST-parameter
    if (  !$request_method
        || $request_method ne 'POST'
        || !$content_type
        || $self->content_type() !~ m/application\/json/
        || !$self->param('POSTDATA') )
    {
        $self->throw_error(SQE_Error::NO_JSON_POST_REQUEST);
    }

    #We got JSON as POST-parameter - let's test if they are correct formatted
    $self->{CGIDATA} = eval { decode_json( '' . $self->param('POSTDATA') ) };
    $self->throw_error(SQE_Error::WRONG_JSON_FORMAT) if !$self->{CGIDATA};

    #We got correct formatted JSON-data, let's check if we should continue a running session
    if ($self->{CGIDATA}->{SESSION_ID}) {
        ($self->{DBH}, $error_ref) = $sqe_sessions->get_session_dbh_by_id($self->{CGIDATA}->{SESSION_ID},
            $self->{CGIDATA}->{SCROLL_VERSION_ID});
        $self->throw_error($error_ref) if !$self->dbh;
    } else {
        #A new session is required
        ($self->{DBH}, $error_ref) = $sqe_sessions->new_session_dbh($self->{CGIDATA});
        $self->throw_error($error_ref) if !$self->dbh;
    }

    # At this point, we should have a valid SQE_CGI instance
    return $self;

}

sub DESTROY {
    my $self = shift;
    if ( $self->dbh ) {
        $self->dbh->do( SQE_CGI_queries::SET_SESSION_END,
            undef, $self->dbh->scrollversion,
            $self->session_id
        );
    }
}

# Retrieves the current databse handler
#@returns SQE_db
sub dbh {
    return $_[0]->{DBH};
}

#  the current session id
sub session_id {
    return $_[0]->dbh->session_id;
}

# Prints a JSON-formated error to the CGI-output
# Use print_json_error
#@deprecated
sub sent_json_error {
    shift->print_json_error;
}

# Prints a JSON-formated error to the CGI-output
# Parameters:
#     error_ref: reference to an error array
#@deprecated
sub print_json_error {
    my ( $self, $error_ref ) = @_;
    $self->print( '"TYPE":"ERROR","ERROR_CODE":'
          . $error_ref->[0]
          . ',"ERROR_TEXT":"'
          . $error_ref->[1]
          . '"' );
}

# Print a JSON header to the CGI-output and opnes a JSON-object
# Should be used instead of the header fundtion of the normal CGI
sub start_json_output {
    my $self = shift;
    $self->header('application/json;charset=UTF-8');
    $self->print('{');
}

# Prints the  Session Id in JSON format to the CGI output
sub print_session_id {
    my $self = shift;
    $self->print( '"SESSION_ID":"' . $self->session_id . '",' );

}

sub finish_json_output {
    shift->print('}');
}

=head2 finish_session($session_id)

Finishs as ession. This also deletes the coinnected session record
from the table sqe_sessions

=over 1

=item Parameters: the id of the session to finish

=item Returns nothing

=back

=cut

sub finish_session {
    my ($self, $session_id) = @_;
    if (my $session = $sqe_sessions->{$self->session_id}) {
        $session->finish;
        delete $sqe_sessions->{$self->session_id};
    }
}


=head2 finish_own_session()

Finishs the session connected with this instance of CGI. This also deletes the coinnected session record
from the table sqe_sessions


=over 1

=item Parameters: none

=item Returns nothing

=back

=cut

sub finish_own_session {
    my ($self) = @_;
    $self->finish_session($self->session_id)
}


=head2 throw_error($error_code)

Sends an error message as an JSON-object to the browser and terminates the CGI process

=over 1

=item Parameters: Arrayref with error-data, cf. SQE_Error.pm

=item Returns nothing

=back

=cut

sub throw_error {
    my ( $self, $error_ref ) = @_;
    $self->print( '{"TYPE":"ERROR","ERROR_CODE":'
          . $error_ref->[0]
          . ',"ERROR_TEXT":"'
          . $error_ref->[1]
          . '"}' );
    exit;
}


=head2 get_roi_data($sign_char_roi_id, $as_text)

Retrieves the ROI data for the given sign_char_roi id. The path will be given either as WKT (as_text set) or as GeoJSON

=over 1

=item Parameters: id of the sign_char_roi
                  flag whether the path should be given as WKT (set) or as GeoJSON (not set)

=item Returns sign_char_id
               path as WKT or GeoJSON
               transform matrix
               values set flag
               exceptional flag

=back

=cut

sub get_roi_data {
    my ($self, $sign_char_roi_id, $as_text) = @_;

    return $self->dbh->get_roi_data($sign_char_roi_id, $as_text);
}

=head2 set_roi_data($sign_char_roi_id, $new_path, $new_matrix, $new_values_set, $new_exceptional)

Sets the given data to sign char roi and returns the new sign_char_roi_id;

For all data given as undef the odl data will be retained


=over 1

=item Parameters: id of the sign char roi
                  path as WKT
                  transfrom matrix
                  flag for values set
                  flag for exceptional

=item Returns the new id of sign char roi

=back

=cut


sub set_roi_data {
    my ($self, $sign_char_roi_id, $new_path, $new_matrix, $new_values_set, $new_exceptional) = @_;
    my $new_id;
    if ($self->start_logged_writing) {
        $new_id=$self->dbh->set_roi_data($sign_char_roi_id, $new_path, $new_matrix, $new_values_set, $new_exceptional);
    $self->stop_logged_writing;
    }
    return $new_id;
}

=head2 set_roi_path($sign_char_roi_id, $new_path)

Sets the given path to sign char roi and returns the new sign_char_roi_id;

=over 1

=item Parameters: id of the sign char roi
                  path as WKT

=item Returns the new id of sign char roi

=back

=cut

sub set_roi_path {
    my ($self, $sign_char_roi_id, $new_path) = @_;
    return $self->set_roi_data ($sign_char_roi_id, $new_path);
}

=head2 set_roi_position($sign_char_roi_id, $new_matrix)

Sets the given matrix to place the path to sign char roi and returns the new sign_char_roi_id;

=over 1

=item Parameters: id of the sign char roi
                  transform matrix

=item Returns the new id of sign char roi

=back

=cut

sub set_roi_position {
    my ($self, $sign_char_roi_id, $new_matrix) = @_;
    return $self->set_roi_data ($sign_char_roi_id, undef, $new_matrix);
}


=head2 set_roi_geo($sign_char_roi_id, $new_path, $new_path)

Sets the given path and the matrix to place it to sign char roi and returns the new sign_char_roi_id;

=over 1

=item Parameters: id of the sign char roi
                  path as WKT
                  transform matrix

=item Returns the new id of sign char roi

=back

=cut


sub set_roi_geo {
    my ($self, $sign_char_roi_id, $new_path, $new_matrix) = @_;
    return $self->set_roi_data ($sign_char_roi_id, $new_path, $new_matrix);

}

=head2 set_roi_values_set($sign_char_roi_id, $new_values_set)

Sets the flag whether the values are finally set to sign char roi and returns the new sign_char_roi_id;

=over 1

=item Parameters: id of the sign char roi
                  flag of values set

=item Returns the new id of sign char roi

=back

=cut



sub set_roi_values_set {
    my ($self, $sign_char_roi_id, $new_values_set) = @_;
    return $self->set_roi_data ($sign_char_roi_id, undef, undef, $new_values_set);
}

=head2 set_roi_exceptional($sign_char_roi_id, $new_exceptional)

Sets the the flag whether are taken as exceptional  to sign char roi and returns the new sign_char_roi_id;

=over 1

=item Parameters: id of the sign char roi
                  exceptional flag

=item Returns the new id of sign char roi

=back

=cut



sub set_roi_exceptional {
    my ($self, $sign_char_roi_id, $new_exceptional) = @_;
    return $self->set_roi_data ($sign_char_roi_id, undef, undef, undef, $new_exceptional);
}



sub get_text_of_fragment {
    my ($self, $frag_id, $class) = @_;
    my ($erg, $error_ref) = $self->dbh->get_text_of_fragment($frag_id, $class);
    $self->throw_error($error_ref) if $error_ref;
}

sub get_text_of_line {
    my ($self, $line_id, $class, $own_version) = @_;
    my ($erg, $error_ref) = $self->dbh->get_text_of_line($line_id, $class, $own_version);
    $self->throw_error($error_ref) if $error_ref;
}

=head3 get_sign_char_commentary($sign_char_commentary_id)

Retrieves the text of the referrenced sign char commentary

=over 1

=item Parameters: id of sign char commentary

=item Returns commentary text

=back

=cut

sub get_sign_char_commentary {
    my ($self, $sign_char_commentary_id) = @_;
    return $self->dbh->get_sign_char_commentary($sign_char_commentary_id);
}


sub user_id {
    $_[0]->dbh->user_id;
}

sub scrollversion_id {
    $_[0]->dbh->scroll_version_id;
}

=head2 clone_scrollversion()

Clones the scroll referred to by the current scrollversion and returns the new scrollversion id.

Beware: the function does not set automatically the new scrollversion as the current one. Thus,
if one wants to use the new scrollversion immediately the CGI script should set the new scrollversion
using set_scrollversion:

``self->set_scrollversion($self->clone_scrollversion);´´

=over 1

=item Parameters: none

=item Returns the id of the new scrollversion

=back

=cut

sub clone_scrollversion {
    my ($self) = @_;
    my $new_scrollversion_id = $self->dbh->clone_current_scroll();
    return $new_scrollversion_id
}


=head2 delete_scrollversion()

Deletes a scollversion and all it's data.

Beware: This step can't be redone and the current scrollversion is no more valid.
Thus, the script should not try to do anything more on the current scrollversion and return or
set a new scrollversion instead.


=over 1

=item Parameters: id of scroll version to be deleted; if not set the current scroll version is deleted

=item Returns nothing

=back

=cut

sub delete_scrollversion {
    my ($self, $scroll_version_id) = @_;
    $scroll_version_id = $scroll_version_id ? $scroll_version_id : $self->scrollversion_id;
    my ($erg, $error_ref) = $self->dbh->delete_scroll_version($scroll_version_id);
    $self->throw_error($error_ref) if $error_ref;
}

=head2 set_scrollversion($scroll_version_id)

Sets the scrollversion with the given id as the current one. All actions are than executed
on the new scrollversion

=over 1

=item Parameters: id of the new scrollversion

=item Returns nothing

=back

=cut


sub set_scrollversion {
    my ($self, $scroll_version_id) = @_;
    $self->dbh->set_scrollversion($scroll_version_id);
}


=head2 remove_sign_char_attribute($sign_char_attribute_id)

Removes the sign char attribute with the given id.

Note: Do not confuse this with attribute_value_id or an attribute_id!

=over 1

=item Parameters: id of the sign_char_attribute to be removed

=item Returns nothing

=back

=cut

sub remove_sign_char_attribute {
    my ($self, $sign_char_attribute_id) = @_;
    if ($self->start_logged_writing) {
        $self->dbh->remove_sign_char_attribute($sign_char_attribute_id);
        $self->stop_logged_writing;
    }
}

=head2 set_sign_char_attribute($sign_char_id, $attribute_value_id, $numeric_value)

Set the attribute value with the given id as an attribute of the sign char with the given id

=over 1

=item Parameters:  id of the sign char,
                   id of the attribute value,
                   optional a numeric value

=item Returns id of the new sign_char_attribute

=back

=cut

sub set_sign_char_attribute {
    my ($self, $sign_char_id, $attribute_value_id, $numeric_value) = @_;
    if ($self->start_logged_writing) {

        my $new_sign_char_attribute_id = $self->dbh->set_sign_char_attribute($sign_char_id, $attribute_value_id, $numeric_value);
        $self->stop_logged_writing;
        return $new_sign_char_attribute_id;
    }
}


=head2 set_sign_char_attribute_ordered_values($sign_char_id, @attribute_value_ids)

Sets to a sign char a set of attribute_values for one attribute ordered according to the sequence of the appearance
in their array.

Note: make sure that this values belong all to one and the same attribute. Do not misuse this function
to set several different attributes

=over 1

=item Parameters: id of the sign char
                    array of id's of attribute values

=item Returns a ref to an array of the new sign char attributes

=back

=cut

sub set_sign_char_attribute_ordered_values {
    my ($self, $sign_char_id, @attribute_value_ids) = @_;
    if ($self->start_logged_writing) {

        $self->dbh->delete_sign_char_attributes_for_attribute($sign_char_id, $attribute_value_ids[0]);
        my $numeric_value = 0;
        my $new_ids = [];
        for my $attribute_value_id (@attribute_value_ids) {
            push @$new_ids, $self->dbh->set_sign_char_attribute($sign_char_id, $attribute_value_id, undef, $numeric_value++);

        }
        $self->stop_logged_writing;
        return $new_ids;
    }
}

=head2 remove_sign_char_commentary($sign_char_commentary_id)

Removes the sign char commentary with the given id.

=over 1

=item Parameters: id of the sign_char_commentary to be removed

=item Returns nothing

=back

=cut

sub remove_sign_char_commentary {
    my ($self, $sign_char_commetary_id) = @_;
    if ($self->start_logged_writing) {
        $self->dbh->remove_sign_char_commentary($sign_char_commetary_id);
        $self->stop_logged_writing;
    }
}

=head2 set_sign_char_commentary($sign_char_id, $attribute_id, $commentary)

Sets acommentary to a certain attribute with the given id as an attribute of the sign char with the given id

=over 1

=item Parameters:  id of the sign char,
                   id of the attribute value,
                   commentary text

=item Returns id of the new sign_char_commentary

=back

=cut

sub set_sign_char_commentary {
    my ($self, $sign_char_id, $attribute_id, $commentary) = @_;
    if ($self->start_logged_writing) {

        my $new_sign_char_commentary_id = $self->dbh->set_sign_char_commentary($sign_char_id, $attribute_id, $commentary);
        $self->stop_logged_writing;
        return $new_sign_char_commentary_id;
    }
}


=head2 add_roi($sign_char_id, $roi_shape, $roi_position, $values_set, $exceptional)

Adds a ROI to the given sign_char.

Throws error, if the user may not change data.

=over 1

=item Parameters:   id of the sign char,
                    path ot the ROI shap as GeoJSON object = {"type": "MultiPolygon", "coordinates"}
                    the position matrix as JSON array
                    flag whether the values are deemed as set
                    flag whether the the values are deemed as exceptional

=item Returns the new ROI id

=back

=cut

sub add_roi {
    my ($self, $sign_char_id, $roi_shape, $roi_position, $values_set, $exceptional) = @_;
    my $roi_id;
    if ($self->start_logged_writing) {

        $roi_id = $self->dbh->add_roi($sign_char_id, $roi_shape, $roi_position, $values_set, $exceptional);
        $self->stop_logged_writing;
    }
    return $roi_id;
}

=head2 remove_roi($sign_char_roi_id)

Removes the referenced ROI-data from the connected sign char.

Throws error, if the user may not change data.

=over 1

=item Parameters: id of the sign char ROI

=item Returns nothing

=back

=cut

sub remove_roi {
    my ($self, $sign_char_roi_id) = @_;
    if ($self->start_logged_writing) {

        $self->dbh->remove_roi($sign_char_roi_id);
        $self->stop_logged_writing;
    }

}

sub add_sign_char_variant {
    my ($self, $sign_id, $char, $as_main) =  @_;
    if ($self->start_logged_writing) {

        $self->dbh->new_sign_char_variant($sign_id, $char, $as_main ? 0 : 1);
        $self->stop_logged_writing;
    }
}

sub remove_sign_char {
    my ($self, $sign_char_id) = @_;
    if ($self->start_logged_writing) {

        $self->dbh->remove_sign_char($sign_char_id);
        $self->stop_logged_writing;
    }
}

sub remove_sign {
    my ($self, $sign_id) = @_;
    if ($self->dbh->start_logged_action) {
        $self->dbh->remove_sign($sign_id);
        $self->dbh->stop_logged_action;
    }

}

sub stop_logged_writing {
    $_[0]->dbh->stop_logged_action;
}

sub start_logged_writing {
    my ($self) = @_;
    my ($may, $error_ref) = $self->dbh->start_logged_action;
    if (!$may) {
        $self->throw_error($error_ref);
    } else {
        return 1;
    }
    return 0;
}

sub insert_sign {
    my ($self, $sign, $after, $before, @attributes) = @_;
    my $new_sign_id;
if ($self->start_logged_writing   ) {
        $new_sign_id=$self->dbh->new_sign($sign, $after, $before, undef, @attributes);
        $self->stop_logged_writing;
    return $new_sign_id;
    }


}

1;
