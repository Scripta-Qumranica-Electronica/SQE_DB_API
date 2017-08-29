package SQE_CGI;
use strict;
use warnings FATAL => 'all';
use Data::UUID;
use SQE_DBI;
use SQE_CGI_queries;

use parent 'CGI';

our $sqe_sessions;

sub new {
    my ( $class, %args ) = @_;
    # $sqe->sessions should be initialised only once
    $sqe_sessions = {} if !defined $sqe_sessions;
    my $dbh;

    my $self = $class->SUPER::new(%args);
    bless $self, 'SQE_CGI';

    $self->start_output;

    # We don't want get-parameter
        if ($self->url_param) {
            $self->sent_error(SQE_Error::NO_GET_REQUESTS);
            return (undef, SQE_Error::NO_GET_REQUESTS);

        }



    $self->{SQE_SESSION_ID} = $self->param('SESSION_ID');

    # Sessionid is provided
    if ( $self->{SQE_SESSION_ID} ) {
        $dbh = $sqe_sessions->{$self->{SQE_SESSION_ID}};


        # But no Databasehandle
        if ( !defined $dbh ) {

            # Get a new Databasehandler
            ( $dbh, my $error_ref ) = SQE_DBI->get_sqe_dbh();

            # A Databasehandler could not be created
            if ( !defined $dbh ) {
                $self->sent_error($error_ref);
                return ( undef, $error_ref );
            }

            # Otherwise, get the data for the Sessionid
            $dbh = bless $dbh, 'SQE_db';
            $sqe_sessions->{SQE_SESSION_ID} = $dbh;
            my $session_id_sth =
              $dbh->prepare(SQE_CGI_queries::GET_SQE_SESSION);
            $session_id_sth->execute( $self->{SQE_SESSION_ID} );
          #  $self->print($self->{SQE_SESSION_ID});
            # Data are available
            my $result_ref = $session_id_sth->fetchrow_arrayref;

            if (defined $result_ref->[0] ) {
                $dbh->{private_SQE_DBI_data}->{user_id} = $result_ref->[0];
                $dbh->{private_SQE_DBI_data}->{scrollversion} =
                  $result_ref->[1];
                $sqe_sessions->{$self->{SQE_SESSION_ID}}=$dbh;
            }

            # No entry found
            else {
                $dbh->disconnect;
                $self->sent_error(SQE_Error::WRONG_SESSION_ID);
                return ( undef, SQE_Error::WRONG_SESSION_ID );
            }
        }
    }

    # No sessionid given
    # Try to create a new session
    else {

        # Try to get a databasehandler via credentials
        ( $dbh, my $error_ref ) = SQE_DBI->get_login_sqe(
            $self->param('USER_NAME'),
            $self->param('PASSWORD'),
            $self->param('SCROLLVERSION')
        );

        # If no handler could be created
        if ( !defined $dbh ) {
            $self->sent_error($error_ref);
            $self->finish_output;
            return ( undef, $error_ref );
        }

        # We got a handler - let's start a new session
        else {
            my $ug         = Data::UUID->new;
            my $session_id = $ug->to_string( $ug->create );
            $sqe_sessions->{$session_id} = $dbh;
            my $session_sth = $dbh->prepare(SQE_CGI_queries::NEW_SQE_SESSION);
            $session_sth->execute( $session_id, $dbh->user_id,
                $dbh->scrollversion );

            #            $self->{DBH} = $dbh;
            $self->{SQE_SESSION_ID} = $session_id;

        }
    }
    $self->{DBH} = $dbh;
    $self->print( '"SESSION_ID":"' . $self->{SQE_SESSION_ID} . '",' );
    return ($self);
}

sub DESTROY {
    my $self = shift;
    if ( $self->{DBH} ) {
        $self->{DBH}->do( SQE_CGI_queries::SET_SESSION_END,
            undef, $self->{DBH}->scrollversion, $self->{SQE_SESSION_ID} );
    }
}

sub dbh {
    return shift->{DBH};
}

sub session_id {
    return shift->{SQE_SESSION_ID};
}

sub sent_error {
    my ( $self, $error_ref ) = @_;
    $self->print( '"TYPE":"ERROR","ERROR_CODE":'
          . $error_ref->[0]
          . ',"ERROR_TEXT":"'
          . $error_ref->[1]
          . '"' );
    $self->finish_output;
}

sub start_output {
    my $self = shift;
    $self->header('application/json;charset=UTF-8');
    $self->print('{');
}

sub finish_output {
    shift->print('}');
}

1;
