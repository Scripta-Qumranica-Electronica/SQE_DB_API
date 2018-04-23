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
        ($self->{DBH}, $error_ref) = $sqe_sessions->get_session_dbh_by_id($self->{CGIDATA}->{SESSION_ID});
        $self->throw_error($error_ref) if !$self->{DBH};
    } else {
        #A new session is required
        ($self->{DBH}, $error_ref) = $sqe_sessions->new_session_dbh($self->{CGIDATA});
        $self->throw_error($error_ref) if !$self->{DBH};
    }

    # At this point, we should have a valid SQE_CGI instance
    return $self;

}

sub DESTROY {
    my $self = shift;
    if ( $self->{DBH} ) {
        $self->{DBH}->do( SQE_CGI_queries::SET_SESSION_END,
            undef, $self->{DBH}->scrollversion,
            $self->session_id
        );
    }
}

# Retrieves the current databse handler
#@returns SQE_db
sub dbh {
    return shift->{DBH};
}

#  the current session id
sub session_id {
    return shift->{DBH}->session_id;
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



sub get_text_of_fragment {
    my ($self, $frag_id, $class) = @_;
    $self->{DBH}->get_text_of_fragment($frag_id, $class);
}

sub get_text_of_line {
    my ($self, $line_id, $class) = @_;
    $self->{DBH}->get_text_of_line($line_id, $class);
}

sub user_id {
    $_[0]->{DBH}->user_id;
}

sub scroll_version_id {
    $_[0]->{DBH}->scroll_version_id;
}




1;
