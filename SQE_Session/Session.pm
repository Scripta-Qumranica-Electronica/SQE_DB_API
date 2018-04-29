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


=head1 Internal functions

=cut
    sub _new {
        my ( $class, $cgi_data ) = @_;

        my $self = {SCROLL_VERSION_ID => 0};
        bless $self, $class;

        # First, let's get an database handler
        my ( $dbh, $error_ref ) = SQE_DBI->get_sqe_dbh();

        # Return with error if no valid database handler
        return ( undef, $error_ref ) if !$dbh;

        $dbh->set_session($self);

        return $self;

    }





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
    my ($class, $cgi_data) = @_;
    my ($self, $error_ref) = _new($class);

    return (undef, $error_ref) if !$self;

    my $user_name = $cgi_data->{USER_NAME};
    my $password = $cgi_data->{PASSWORD};
    my $scroll_version_id = $cgi_data->{SCROLL_VERSION_ID};


    ( $self->{USER_ID} ) =
      $self->{DBH}->get_first_row_as_array( Queries::LOGIN, $user_name,
        $password );

    # If no user_id is set, than we got wrong credentials
    if (!defined $self->{USER_ID}) {
    $self->{DBH}->disconnect;
        return ( undef, SQE_Error::WRONG_USER_DATA )
    }



    #Let's try to set the scrollversion if a scroll_vwersion_id os provided
    if ($scroll_version_id && !$self->set_scrollversion($scroll_version_id)) {
        $self->{DBH}->disconnect;
        return(undef, SQE_Error::WRONG_SCROLLVERSION);
    }

    $self->{SESSION_ID} = $uuid->create_str();

    my $sth = $self->{DBH}->prepare_cached(Queries::NEW_SQE_SESSION);
    $sth->execute($self->{SESSION_ID}, $self->{USER_ID}, $self->{SCROLL_VERSION_ID});
    $sth->finish;
    return $self;
}

sub reload {
    my ($class, $session_id, $scroll_version_id) = @_;
    my ($self, $error_ref) = _new($class);

    return (undef, $error_ref) if !$self;


    # We got an database handler - let's try to retrieve old  sessiion data
    ($self->{USER_ID}, my $old_scroll_version_id , $self->{ATTRIBUTES}) =
        $self->{DBH}->get_first_row_as_array( Queries::RELOAD_SESSION, $session_id );

    # If no user_id is set, than we could not reload a session
    if (!$self->{USER_ID}) {
        $self->{DBH}->disconnect;
        return(undef, SQE_Error::WRONG_SESSION_ID);
    }

    $scroll_version_id = $old_scroll_version_id if !$scroll_version_id;

    #Let's try to set the scrollversion to test wether it is still valid
    if ($scroll_version_id && !$self->set_scrollversion($scroll_version_id)) {
        $self->{DBH}->disconnect;
        if ($scroll_version_id != $old_scroll_version_id) {
            return(undef, SQE_Error::WRONG_SCROLLVERSION);
        } else {
            return(undef, SQE_Error::SCROLLVERSION_OUTDATED);
        }
    }

    $self->{SESSION_ID} = $session_id;
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
     ( $scroll_version_id, my $scroll_version_group_id ) =
      $self->{DBH}->get_first_row_as_array( Queries::GET_SCROLLVERSION,
        $self->{USER_ID}, $scroll_version_id );

    # Return the scroll version id if the version could have been retrieved
    # other wise (undef, error_ref)
    if ($scroll_version_id && $scroll_version_group_id) {
        $self->{SCROLL_VERSION_ID} = $scroll_version_id;
        $self->{SCROLL_VERSION_GROUP_ID} = $scroll_version_group_id;
        $self->{DBH}->do(Queries::SET_SCROLLVERSION, undef, $scroll_version_id, $self->{SESSION_ID});
        return $scroll_version_id;
    } else {
        return undef;
    }
}


=head2 finish()

Finish the session and releases all connected ressources. Also deletes the table
entrance of this session in sqe_session

=over 1

=item Parameters: none

=item Returns none

=back

=cut

sub finish {
    my ($self) = @_;
    my $dbh=$self->{DBH};
    my $sth = $dbh->prepare_cached(Queries::REMOVE_SESSION);
    $sth->execute($self->{SESSION_ID});
    $sth->finish;
    $dbh->disconnect;
}

sub session_id {
    return $_[0]->{SESSION_ID};
}

sub set_session_id {
    my ($self, $session_id) = @_;
    $self->{SESSION_ID}= $session_id;
}

1;
