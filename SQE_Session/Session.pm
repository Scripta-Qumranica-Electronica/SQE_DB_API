=head1 NAME

Session - Class to hold and organise data belonging to a single SQE_Session

=head1 VERSION

0.1.0

=head1 DESCRIPTION



=head1 AUTHORS

Ingo Kottsieper

=head1 COPYRIGHT AND LICENSE

=head1 Predifined Keys

=over 1

=item DBH = SQE_db databasehandler

Set by the databasehandler itself via set_session()

=item SESSION_ID = Id of the Session

=back



=cut


package Session;
use strict;
use warnings FATAL => 'all';

our $uuid = Data::UUID->new;

use SQE_DBI;
use SQE_Session::Queries;
use SQE_Error;
use SQE_Session::Container;





=head1 Methods

=head2 new($user_name, $password, $scroll_version_id)

Creates a new session for given user credentials.

If a scroll version id is provided, the session sets the
referred scroll version as the one to work on.

=over 1

=item Parameters: user_name, password, scroll version id (optional)

=item Returns SQE_Sesson::Session || (undef, sqe_error)

=back

=cut

sub new {
    my ( $class, $cgi_data ) = @_;

    my $self = {SCROLL_VERSION_ID => 0};
    bless $self, $class;

    # First, let's get an database handler
    my ( $dbh, $error_ref ) = SQE_DBI->get_sqe_dbh();

    # Return with error if no valid database handler
    return ( undef, $error_ref ) if !$dbh;

    # We got an database handler - let's try to login
    my $user_name = $cgi_data->{USER_NAME};
    my $password = $cgi_data->{PASSWORD};
    my $scroll_version_id = $cgi_data->{SCROLL_VERSION_ID};


    ( $self->{USER_ID} ) =
      $dbh->get_first_row_as_array( Queries::LOGIN, $user_name,
        $password );

    # If no user_id is set, than we got wrong credentials
    return ( undef, SQE_Error::WRONG_USER_DATA ) if !defined $self->{USER_ID};

    $dbh->set_session($self);

    #Let's try to set the scrollversion if a scroll_vwersion_id os provided
    return ( undef, SQE_Error::WRONG_SCROLLVERSION )
      if $scroll_version_id && !$self->set_scrollversion($scroll_version_id);

    $self->{SESSION_ID} = $uuid->create_str();
    return $self;
}


=head2 valid_dbh()

Validates the database handler of the session and creates a new one if there is no valid one.

=over 1

=item Parameters: none

=item Returns SQE_db

=back

=cut

#@returns SQE_db
sub valid_dbh {
    my ($self) = @_;
    my SQE_db $dbh = $self->{DBH};
    if ( !$dbh || !$dbh->ping ) {
        ( $dbh, my $error_ref ) = SQE_DBI->get_sqe_dbh();
        return ( undef, $error_ref ) if !$dbh;
        $dbh->set_session($self);
    }
    return $dbh;
}

=head2 set_scrollversion($scroll_version_id)

Set a new scroll version (its id and the id of its group) as the default

=over 1

=item Parameters: Id of the scroll version

=item Returns scroll version id  || (undef, error_ref)

=back

=cut

sub set_scrollversion {
    my ( $self, $scroll_version_id ) = @_;

    # Simply return $scroll_version_id if this scroll version is already set
    return $scroll_version_id if $self->{SCROLL_VERSION_ID} == $scroll_version_id;

    # Otherwise try to retrieve the scroll version from the database
    ( $self->{SCROLL_VERSION_ID}, $self->{SCROLL_VERSION_GROUP_ID} ) =
      $self->{DBH}->get_first_row_as_array( Queries::GET_SCROLLVERSION,
        $self->{USER_ID}, $scroll_version_id );

    # Return the scroll version id if the version could have been retrieved
    # other wise (undef, error_ref)
    return $self->{SCROLL_VERSION_ID} && $self->{SCROLL_VERSION_GROUP_ID}
      ? $self->{SCROLL_VERSION_ID}
      : (undef, SQE_Error::WRONG_SCROLLVERSION);
}

1;
