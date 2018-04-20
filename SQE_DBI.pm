
=pod

=head1 NAME

SQE_DBI expands the normal DBI package

=head1 VERSION

0.1.0

=head1 DESCRIPTION



=head1 AUTHORS

Ingo Kottsieper

=head1 COPYRIGHT AND LICENSE


=head1 SQE_DBI

A child of DBI which offers some functions for diret login
and to create database-handler of the type SQE_db

=cut

package SQE_DBI;
use strict;
use DBI;
use warnings FATAL => 'all';
use Scalar::Util;
use SQE_Restricted;
use SQE_Error;
use SQE_database_queries;
use SQE_DBI_queries;
use SQE_sign_stream;
use parent 'DBI';

use Ref::Util;

# Returns a  SQE database handler for the SQE database or (undef, error_ref) if no hanlder can be created
#@returns SQE_db
sub get_sqe_dbh {
    my $class = shift;
    my %attr  = (
        PrintError        => 0,    # turn off error reporting via warn()
        RaiseError        => 1,    # turn on error reporting via die()
        mysql_enable_utf8 => 1,
    );
    my $dbh =
      DBI->connect( SQE_Restricted::DSN_SQE, SQE_Restricted::DB_USERNAME,
        SQE_Restricted::DB_PASSWORD,, \%attr );
    if ($dbh) {
        $dbh = bless $dbh, 'SQE_db';
        return $dbh;
    }
    else {
        return undef, SQE_Error::NO_DBH;
    }
}

# Creates a SQE_db databse handler for the SQE-database using the transmitted credential.
# Set's the user id as the default user id for all actions and, if given, also the version.
# The version can be set or altered later by using SQE_db->set_version_id
sub get_login_sqe {
    my ( $class, $user_name, $password, $version ) = @_;

    #Return with error data if either user name or password is missing
    return ( undef, SQE_Error::WRONG_USER_DATA )
      if not( $user_name && $password );

    # Try to get an database handler

    my ( $dbh, $error_ref ) = SQE_DBI->get_sqe_dbh();

    # Return with error data if no database handler is available
    return ( undef, $error_ref ) if not $dbh;

    #Transform into a SQE_db handler and try to login
    $dbh = bless $dbh, 'SQE_db';
    ( my $scrollversion, $error_ref ) =
      $dbh->set_user( $user_name, $password, $version );

    if ( !defined $scrollversion ) {

# The scrollversion does not exist or is not available for the user  - return the error and undef for the handler
        $dbh->disconnect();
        return ( undef, $error_ref );
    }
    else {
        # Otherwise return the handler
        return $dbh;
    }
}

############################################################################################
#   Databasehandler
############################################################################################

# A child of a normal DBI databasehandler which provides some functions
# to include user ids and versions, to log changes and to retrieve data.
{

=pod

=head1 SQE_db

A child of DBI::db

=cut

    package SQE_db;

    use SQE_sign;

    # All formats defined in SQE_Format (except the Parent) need to be mentioned here
    use SQE_Format::HTML;
    use SQE_Format::JSON;

    use parent -norequire, 'DBI::db';

    use constant {
        SESSION => 'private_session',

        NEW_MAIN_ACTION => <<'MYSQL',
          INSERT INTO main_action
              (scroll_version_id) VALUES (_scrollversion_)
MYSQL

        ADD_USER => <<'MYSQL',
            INSERT IGNORE INTO _table__owner
              (_table__id, scroll_version_id)
    SELECT
        _table__id,
        _scrollversion_
    FROM _table__owner
        JOIN _table_ USING (_table__id)
      _join_
      WHERE _where_
      AND _table__owner.scroll_version_id = _oldscrollversion_
MYSQL

        REMOVE_USER               => <<'MYSQL',
          DELETE _table__owner
          FROM _table__owner
          JOIN _table_ USING (_table__id)
          _join_
          WHERE _where_
          AND _table__owner.scroll_version_id = _scrollversion_

MYSQL

        LOG_CHANGE_USER => <<'MYSQL',
          INSERT INTO single_action
              (main_action_id, action, `table`, id_in_table)
          SELECT _mainid_, '_actionart_', '_table_', _table__id
          FROM _table__owner
          JOIN _table_ USING (_table__id)
          _join_
          WHERE _where_
          AND _table__owner.scroll_version_id = _scrollversion_
MYSQL

        SIGN_CHAR_JOIN            => 'JOIN sign_char USING (sign_char_id)',
        LINE_TO_SIGN_JOIN         => 'JOIN line_to_sign USING (sign_id)',
        COL_TO_LINE_JOIN          => 'JOIN col_to_line USING (line_id)',
        SCROLL_TO_COL_JOIN        => 'JOIN scroll_to_col USING (col_id)',
        ARTEFACT_POSITION_JOIN    => 'JOIN artefact_position USING (artefact_id)',

        NEW_SCROLL_VERSION        => <<'MYSQL',
        INSERT INTO scroll_version
        (user_id, scroll_id, version) values (?,?,?)
MYSQL


    };

=head2 Internal Functions


=head3 _set_scroll_version($scroll_version_id, $scroll_version_group_id)

Sets the scroll version and scroll version group id into the internal hash

=over 1

=item Parameters: scroll_version_id, scroll_version_group_id

=item Returns

=back

=cut

    sub _set_scroll_version {
        my ($self, $scroll_version_id, $scroll_version_group_id) = @_;
        $self->{private_SQE_DBI_data}->{SCROLL_VERSION_ID} =
            $scroll_version_id;
        $self->{private_SQE_DBI_data}->{SCROLL_VERSION_GROUP_ID} =
            $scroll_version_group_id;
    }

=head2 Internal Database Functions

Contains all functions which can be used as shortcuts for executing queries


=head3 start_logged_action()

Starts a set of logged actions and must be stopped with stop_logged_action().

Logged actions must use an SQE_st statement and must be executed by its function logged_exectue().

=over 1

=item Parameters: none

=item Returns nothing

=back

=cut

    # Starts a set of logged actions
    # Must be ended by stop_logged_action
    # Logged action must use an SQE_st Statement and executed by logged_execute
    sub start_logged_action {
        my $self = shift;
        $self->{AutoCommit} = 0;
        my $sth = $self->{private_SQE_DBI_data}->{main_action_sth};
        if ( not $sth ) {
            my $query = NEW_MAIN_ACTION;
            $self->_inject_scroll_version_id( \$query );
            $sth = $self->prepare_cached($query);
            $self->{private_SQE_DBI_data}->{main_action_sth} = $sth;
        }
        $sth->execute();
        $self->{private_SQE_DBI_data}->{main_action_id} =
          $self->{mysql_insertid};
    }

=head3 stop_logged_action()

Stops a set of logged actions started with start_logged_action()

=over 1

=item Parameters: none

=item Returns nothing

=back

=cut

    sub stop_logged_action {
        my $self = shift;
        $self->commit;
        $self->{AutoCommit} = 1;
    }

=head3 prepare_sqe_with_version_ids()

Creates a prepared SQE_st statement handler with injected scroll_version_group_id.

Any instance of _svgi_ will be replaced with the current scroll version group id

=over 1

=item Parameters: query string

=item Returns SQE_st statement

=back

=cut

    #@returns SQE_st
    sub prepare_sqe_with_version_ids {
        my ( $self, $query ) = @_;
        $query =~
          s/_svgi_/$self->{private_SQE_DBI_data}->{SCROLL_VERSION_GROUP_ID}/goe;
        return bless $self->prepare_cached( $query, @_ ), 'SQE_st';
    }

=head3 selectall_hashref_with_key_from_column()

Returns a reference to a hash whose keys are the values given in the key column.

The value of a key is an array containing arrays of the values of each line which has the
key value:

{
key1=>[[values of 1. row with key_column=key1],[values of 2. row with key_column=key1] ...],
key2=>[[values of 1. row with key_column=key2],[values of 2. row with key_column=key2] ...]
}

Thus, the key column needs not to provide uniques keys


=over 1

=item Parameters: query string, integer of the key column, values of the query as array

=item Returns reference to result hash

=back

=cut

    #@deprecated
    sub selectall_hashref_with_key_from_column {
        my ( $self, $query, $column, @query_values ) = @_;
        my $sth = $self->prepare_sqe_with_version_ids($query);
        $sth->execute(@query_values);
        my $key;
        my $out_hash_ref = {};

        $sth->bind_col( $column, \$key );
        while ( my @array = $sth->fetchrow_array ) {
            if ( !defined $out_hash_ref->{$key} ) {
                $out_hash_ref->{$key} = [];
            }
            push @{ $out_hash_ref->{$key} }, \@array;
        }
        $sth->finish;
        return $out_hash_ref;
    }

=head3 get_first_row_as_hash_ref($query, @data)

Execute a query with the given data and returns a reference to a hash containing the
data of the first record

=over 1

=item Parameters: Query as string, data as as array

=item Returns reference to a hash containing the data of the first record

=back

=cut

    sub get_first_row_as_hash_ref {
        my ( $self, $query, @data ) = @_;
        my $sth = $self->prepare_cached($query);
        $sth->execute(@data);
        my $result = $sth->fetchrow_hashref;
        $sth->finish;
        reutrn $result;
    }

=head3 get_first_row_as_array($query, @data)

Execute a query with the given data and returns  the
data of the first record as an array

=over 1

=item Parameters: Query as string, data as as array

=item Returns array containing the data of the first record

=back

=cut

    sub get_first_row_as_array {
        my ( $self, $query, @data ) = @_;
        my $sth = $self->prepare_cached($query);
        $sth->execute(@data);
        my @result = $sth->fetchrow_array;
        $sth->finish;
        return @result;
    }



    sub scroll_version_group_id {
        my ($self) = @_;
        return $self->{private_SQE_DBI_data}->{SESSION}->{SCROLL_VERSION_GROUP_ID};
    }


=head2 Retrieve Text

=cut

=head3 print_formatted_text($query, $id, $format, $start_id)

Retrieves a chunk of text, formats, and print it out.



=over 1

=item Parameters:

=item Returns

=back

=cut

    sub print_formatted_text {
        my ($self, $query, $id, $format, $start_id) = @_;
        my $sth=$self->prepare_cached($query);
        my $sth_out = $self->prepare_cached(SQE_DBI_queries::GET_REF_DATA);
        my $signs={};

        if ( $sth->execute($id, $self->scroll_version_group_id)) {
            my SQE_sign $sign = SQE_sign->new($sth->fetchrow_arrayref);
            my SQE_sign $old_sign = $sign;

            while (my $data_ref = $sth->fetchrow_arrayref) {
                my $sign = $old_sign->add_data($data_ref);
                if ($sign != $old_sign) {
                    $signs->{$old_sign->{sign_id}} = $old_sign;
                    $old_sign=$sign;
                }

            }
            $signs->{$old_sign->{sign_id}} = $old_sign;
            $format->print($signs, $start_id, $sth_out, $self->scroll_version_group_id);
        }
        $sth->finish;
        $sth_out->finish;
    }

    sub get_text_of_fragment {
        my ($self, $frag_id, $class) = @_;
        my @start=$self->get_first_row_as_array(SQE_DBI_queries::GET_FIRST_SIGN_IN_COLUMN, $frag_id, $self->scroll_version_group_id);
        $self->print_formatted_text(SQE_DBI_queries::GET_ALL_SIGNS_IN_FRAGMENT_QUERY, $frag_id, $class, $start[0]);
    }

    sub get_text_of_line {
        my ($self, $line_id, $class) = @_;
        my @start=$self->get_first_row_as_array(SQE_DBI_queries::GET_FIRST_SIGN_IN_LINE, $line_id, $self->scroll_version_group_id);
        $self->print_formatted_text(SQE_DBI_queries::GET_ALL_SIGNS_IN_LINE_QUERY, $line_id, $class, $start[0]);
    }





    # Internal function to add the current user/version to a table for a whole scroll or part of it
# The adding is not logged, thus to rewind it, one must use remove_user manually
#
# Parameters
#   Name of the data table
#   Array ref with joins to connect the table data with the scroll or part of it
#   Query fragment giving the data (of the part) of scroll
#   The scrollversion of the source
    sub _run_add_user_query {
        my ( $self, $table, $joins, $where, $old_scrollversion ) = @_;
        my $query = ADD_USER;
        $query =~ s/_table_/$table/go;
        $query =~ s/_join_/join(" ", @$joins)/oe;
        $query =~ s/_where_/$where/o;
        $query =~ s/_user_/$self->user_id/oe;
        $query =~ s/_scrollversion_/$self->scrollversion/oe;
        $query =~ s/_oldscrollversion_/$old_scrollversion/o;
        $self->do($query);
    }

# Internal function to remove the current user/version to a table for a whole scroll or part of it
# The removal is logged
#
# Parameters
#   Name of the data table
#   Array ref with joins to connect the table data with the scroll or part of it
#   Query fragment giving the data (of the part) of scroll
    sub _run_remove_user_query {
        my ( $self, $table, $joins, $where ) = @_;
        my $query = LOG_CHANGE_USER;
        $query =~ s/_table_/$table/go;
        $query =~ s/_join_/join(" ", @$joins)/oe;
        $query =~ s/_where_/$where/oe;
        $query =~ s/_user_/$self->user_id/oe;
        $query =~ s/_scrollversion_/$self->scrollversion/oe;
        $query =~ s/_mainid_/$self->action_log_id()/oe;
        $query =~ s/_actionart_/DELETE/o;
        $self->do($query);
        $query = REMOVE_USER;
        $query =~ s/_table_/$table/go;
        $query =~ s/_join_/join(" ", @$joins)/oe;
        $query =~ s/_where_/$where/oe;
        $query =~ s/_scrollversion_/$self->scrollversion/oe;
        $self->do($query);
    }

    # Internal function, thats adds an owner/version to a table and logs it
    # Note: this is done as part of a complex action logged as one group
    # thus is should only be called after start_logged_action is called before
    # in a calling function followed later by stop_logged_action
    #
    # Parameters
    #   table-name
    #   id of record to which the owner should be set
    sub _add_owner {
        my $self  = shift;
        my $table = shift;
        my $id    = shift;
        my $query =
"INSERT IGNORE INTO ${table}_owner (${table}_id, scroll_version_id) VALUES (?,_scrollversion_)";
        my $sth = $self->prepare_sqe($query);
        $sth->set_action( 'ADD', $table );
        $sth->logged_execute($id);
        $sth->finish;

    }


    sub set_scroll_version_group_admin {
        my ($self, $scroll_version_group_id, $user_id) = @_;
        my $sth->prepare_cached(SQE_DBI_queries::CREATE_SCROLL_VERSION_GROUP_ADMIN);
        $sth->execute($scroll_version_group_id, $user_id);
        $sth->finish;
    }


    # Creates a new scrollversion for the current user and the given scroll.
    # The new scrollversion can be retrieved by scrollverion
    #
    # Parameters
    #   scroll id
    sub create_new_scrollversion {
        my $self             = shift;
        my $scroll_id        = shift;

        # First create a new scroll_version_group
        my $sth = $self->prepare_cached(SQE_DBI_queries::NEW_SCROLL_VERSION_GROUP);
        $sth->execute( $self->user_id, $scroll_id );
        my $scroll_version_group_id=$self->{mysql_insertid};
        $sth->finish;

        $self->set_scroll_version_group_admin($scroll_version_group_id, $self->user_id);

        # Create a new scroll_version as member of the new group
        $sth->prepare_cached(SQE_DBI_queries::NEW_SCROLL_VERSION);
        $sth->execute($self->user_id, $scroll_version_group_id);
        my $scroll_version_id = $self->{mysql_insertid};
        $sth->finish;

        $self->_set_scroll_version($scroll_version_id, $scroll_version_group_id);


        return $scroll_version_id;
    }

    # Internal function, thats removes an scrollversion from a table and logs it
    # Note: this is done as part of a complex action logged as one group
    # thus is should only be called after start_logged_action is called before
    # in a calling function followed later by stop_logged_action
    #
    # Parameters
    #   table-name
    #   id of record from which the owner should be removed
    sub _remove_owner {
        my $self  = shift;
        my $table = shift;
        my $id    = shift;
        my $query =
"DELETE FROM ${table}_owner WHERE ${table}_id = ?  AND scroll_version_id = _scrollversion_";
        my $sth = $self->prepare_sqe($query);
        $sth->set_action( 'DELETE', $table );
        my $result = $sth->logged_execute($id);
        $sth->finish;
        return $result;
    }

# Internal function which adds a record attributed by the current scrollversion to a table and logs it.
# The new record contains the same values as the one referred by $id except those given
# as an array of [field-name, value, fieldname, ...] which replace the old values.
# The function returns the id of the new record, or the old one if the new values are in fact
# identical with the old one.
#
# Note: if already a different record with the new values exist, the function returns its id and
# transform only the owner/version form the old to the new one
#
# Note: this is done as part of a complex action logged as one group
# thus is should only be called after start_logged_action is called before
# in a calling function followed later by stop_logged_action
#
# Parameters
#   the name of the table (note: there must exist a related owner table!)
#   the id of the source record
#   new values as array of field-name1, value1[, field-name2, value2, ...]
# if the value need to be calculated by a mysql-function the function and its parameters
#
# can be given as an arrray ref with the function name as first value followed by the parameters
# Thus: ['POINT', 0,0] would use the value calculated by POINT(0,0)
# Note: ad the moment no nested function are allowed
    sub _add_value {
        my ( $self, $table, $id, %values ) = @_;

       # Let's set the new id to the old id in case, there won't be a new record
        my $insert_id = $id;

        foreach my $key ( keys %values ) {

            # Search for values to be calculated first by a mysql-function
            # and replace the function by the calculated values
            if ( Ref::Util::is_arrayref( $values{$key} ) ) {
                my $command = shift @{ $values{$key} };
                if ( $command =~ /[^A-Za-z0-9_]/ ) {
                    return ( undef, SQE_Error::FORBIDDEN_FUNCTION );
                }
                my $question_marks =
                  join( ', ', map { '?' } @{ $values{$key} } );
                my $value_query = "SELECT $command($question_marks)";
                my $command_sth = $self->prepare_cached($value_query);
                if ( @{ $values{$key} } == 0 ) {
                    eval { $command_sth->execute };
                }
                else {
                    eval { $command_sth->execute( @{ $values{$key} } ) };
                }
                if ($@) {
                    $command_sth->finish;
                    return ( undef, SQE_Error::UNRECOGNIZED_FUNCTION ) if $@;
                }
                $values{$key} = $command_sth->fetchrow_arrayref->[0];
                $command_sth->finish;
            }
        }

        # get the old record
        my $query = SQE_DBI_queries::GET_ALL_VALUES;
        $query =~ s/_table_/$table/og;
        my $sth = $self->prepare_sqe($query);
        $sth->execute($id);

        # the record had been found
        if ( my $data_ref = $sth->fetchrow_hashref or $id == 0 ) {

            $data_ref = {} if !defined $data_ref;

            # replace the old values by the given new ones
            foreach my $key ( keys %values ) {
                $data_ref->{$key} = $values{$key};
            }

    # get all field-names except the id of the record and create a query to test
    # wether a different record containing the new vaules already exist
            my @keys =
              grep { defined $data_ref->{$_} && $_ ne '' }
              map { $_ if defined $data_ref->{$_} && $_ ne "${table}_id" }
              keys %$data_ref;
            my $fields = join( ' = ? AND ', @keys ) . ' = ?';
            $query = "SELECT ${table}_id from  $table where $fields";
            map { $query .= " AND $_ is null" if !defined $data_ref->{$_} }
              keys %$data_ref;
            my $new_sth = $self->prepare_cached($query);
            $new_sth->execute( map { $data_ref->{$_} } @keys );
            my @id = $new_sth->fetchrow_array;

            # if such a different record exist
            if ( @id > 0 && $insert_id != $id[0] ) {

                # Simply add current user/version as a new owner to it
                $insert_id = $id[0];
                $self->_add_owner( $table, $insert_id );
            }

            # if such a record does not exist
            elsif ( @id == 0 ) {

                # create a new record with the values
                my $question_marks = join( ', ', map { '?' } @keys );
                $query =
                    "INSERT INTO ${table} ("
                  . join( ', ', @keys )
                  . ") VALUES ($question_marks)";
                my $add_sth = $self->prepare_cached($query);
                $add_sth->execute( map { $data_ref->{$_} } @keys );
                $insert_id = $self->{mysql_insertid};
                $add_sth->finish;

                #Add the current user/version to the new record
                $self->_add_owner( $table, $insert_id );
            }
            $new_sth->finish;
        }
        else {
            $sth->finish;
            return ( undef, SQE_Error->RECORD_NOT_FOUND );
        }
        $sth->finish;

  #        if ( $table eq 'sign_char' ) {
  #            my $data_ids_sth = $self
  #              ->prepare_sqe(SQE_DBI_queries::GET_SIGN_CHAR_READING_DATA_IDS);
  #            $data_ids_sth->execute($id);
  #            foreach my $data_id ( $data_ids_sth->fetchrow_array ) {
  #                $self->change_value(
  #                    'sign_char_reading_data', $data_id,
  #                    'sign_char_id',           $insert_id
  #                );
  #            }
  #
  #        }
        return $insert_id;
    }

# Adds  a duplicate of record owned by current user/version with the given id with changed values and logs it.
# If the new values given are identical with the old ones, the record will be not duplicated
# and instead of the new id the old id is returned.
#
#
# Parameters
#   Table-name
#   id of the record to be duplicated
#   new values as array of field-name1, value1[, field-name2, value2, ...]
# if the value need to be calculated by a mysql-function the function and its parameters
#
# can be given as an arrray ref with the function name as first value followed by the parameters
# Thus: ['POINT', 0,0] would use the value calculated by POINT(0,0)
# Note: ad the moment no nested function are allowed
#@method
    sub add_value {
        my $self = shift;
        return ( undef, SQE_Error::QWB_RECORD ) if $self->scrollversion == 1;
        $self->start_logged_action;
        my ( $new_id, $error_ref ) = $self->_add_value(@_);
        $self->stop_logged_action;
        return ( $new_id, $error_ref );

    }

# Changes the record owned by the current user/version with the given id using the given values and logs it.
# If the new values given are identical with the old ones, nothing happens and the old id is returned
# Otherwise the id of the record with the changed value is returned
#
#
# Parameters
#   Table-name
#   id of the record to be changed
#   new values as array of field-name1, value1[, field-name2, value2, ...]
#
# if the value need to be calculated by a mysql-function the function and its parameters
#
# can be given as an arrray ref with the function name as first value followed by the parameters
# Thus: ['POINT', 0,0] would use the value calculated by POINT(0,0)
# Note: ad the moment no nested function are allowed

    sub change_value {
        my $self  = shift;
        my $table = shift;
        my $id    = shift;
        return ( undef, SQE_Error::QWB_RECORD ) if $self->scrollversion == 1;
        $self->start_logged_action;
        my ( $new_id, $error_ref ) = $self->_add_value( $table, $id, @_ );
        if ( defined $new_id ) {
            if ( $id != $new_id ) {
                $self->_remove_owner( $table, $id );
            }
            $self->stop_logged_action;
            return $new_id;
        }
        else {
            $self->stop_logged_action;
            return ( undef, $error_ref );

        }
    }

# Removes a record owned by the current user/version with the given id from user/version and logs it.
#
#
# Parameters
#   Table-name
#   id of the record to be duplicated
    sub remove_entry {
        my ( $self, $table, $id ) = @_;
        return ( undef, SQE_Error::QWB_RECORD ) if $self->scrollversion == 1;
        $self->start_logged_action;
        my $result = $self->_remove_owner( $table, $id );
        $self->stop_logged_action;
        if ( $result > 0 ) {
            return $result;
        }
        else {
            return ( undef, SQE_Error::RECORD_NOT_FOUND );
        }
    }

# Adds the given column/fragment from a user/version with all its data to the current user/version
# If the user_id of the source is not given, the default QWB text (user_id=0, version =0) is taken
#
# Note: the col/fragment is taken out from its original scroll!
#
# Parameters
#   Id of the column/fragment
#   id of the user_id of the old owner (optional)
#   version from the old user/version (optional)
    sub add_owner_to_col {
        my $self              = shift;
        my $id                = shift;
        my $where             = " col_to_line.col_id= $id";
        my $old_scrollversion = shift;

        if ( !defined $old_scrollversion ) {
            $old_scrollversion = 1;
        }

        $self->_run_add_user_query( 'sign_char_reading_data',
            [ SIGN_CHAR_JOIN, LINE_TO_SIGN_JOIN, COL_TO_LINE_JOIN ],
            $where, $old_scrollversion );

        $self->_run_add_user_query( 'sign_char',
            [ LINE_TO_SIGN_JOIN, COL_TO_LINE_JOIN ],
            $where, $old_scrollversion );

        $self->_run_add_user_query( 'sign_relative_position',
            [ LINE_TO_SIGN_JOIN, COL_TO_LINE_JOIN ],
            $where, $old_scrollversion );

        $self->_run_add_user_query( 'real_sign_area',
            [ LINE_TO_SIGN_JOIN, COL_TO_LINE_JOIN ],
            $where, $old_scrollversion );

        $self->_run_add_user_query( 'position_in_stream',
            [ LINE_TO_SIGN_JOIN, COL_TO_LINE_JOIN ],
            $where, $old_scrollversion );

        $self->_run_add_user_query( 'line_to_sign', [COL_TO_LINE_JOIN],
            $where, $old_scrollversion );

        $self->_run_add_user_query( 'line_data', [COL_TO_LINE_JOIN],
            $where, $old_scrollversion );

        $self->_run_add_user_query( 'col_to_line', [], $where,
            $old_scrollversion );

        $self->_run_add_user_query( 'col_data', [], "col_data.col_id=$id",
            $old_scrollversion );

    }

# Adds the given scroll from a user/version with all its data to the current user/version
# If the user_id of the source is not given, the default QWB text (user_id=0, version =0) is taken
#
# Parameters
#   Id of the scroll
#   id of the userversion the old owner (optional)
    sub add_owner_to_scroll {
        my $self            = shift;
        my $scroll_id       = shift;
        my $where           = " scroll_to_col.scroll_id= $scroll_id";
        my $old_userversion = shift;

        if ( !defined $old_userversion ) {
            $old_userversion = 1;
        }

        $self->create_new_scrollversion($scroll_id);

        $self->_run_add_user_query(
            'sign_char_reading_data',
            [
                SIGN_CHAR_JOIN,   LINE_TO_SIGN_JOIN,
                COL_TO_LINE_JOIN, SCROLL_TO_COL_JOIN
            ],
            $where,
            $old_userversion
        );



        $self->_run_add_user_query( 'sign_char',
            [ LINE_TO_SIGN_JOIN, COL_TO_LINE_JOIN, SCROLL_TO_COL_JOIN ],
            $where, $old_userversion );

        $self->_run_add_user_query( 'sign_relative_position',
            [ LINE_TO_SIGN_JOIN, COL_TO_LINE_JOIN, SCROLL_TO_COL_JOIN ],
            $where, $old_userversion );

        $self->_run_add_user_query( 'real_sign_area',
            [ LINE_TO_SIGN_JOIN, COL_TO_LINE_JOIN, SCROLL_TO_COL_JOIN ],
            $where, $old_userversion );

        $self->_run_add_user_query( 'position_in_stream',
            [ LINE_TO_SIGN_JOIN, COL_TO_LINE_JOIN, SCROLL_TO_COL_JOIN ],
            $where, $old_userversion );

        $self->_run_add_user_query( 'line_to_sign',
            [ COL_TO_LINE_JOIN, SCROLL_TO_COL_JOIN ],
            $where, $old_userversion );

        $self->_run_add_user_query( 'line_data',
            [ COL_TO_LINE_JOIN, SCROLL_TO_COL_JOIN ],
            $where, $old_userversion );

        $self->_run_add_user_query( 'col_to_line', [SCROLL_TO_COL_JOIN], $where,
            $old_userversion );

        $self->_run_add_user_query( 'col_data', [SCROLL_TO_COL_JOIN], $where,
            $old_userversion );

        $self->_run_add_user_query( 'scroll_to_col', [], $where,
            $old_userversion );

        $self->_run_add_user_query( 'scroll_data', [],
            "scroll_data.scroll_id=$scroll_id",
            $old_userversion );

        # Added by Bronson for copying artefact data
        $self->_run_add_user_query( 'artefact_position', [],
            "artefact_position.scroll_id=$scroll_id",
            $old_userversion );

        $self->_run_add_user_query( 'artefact', [ARTEFACT_POSITION_JOIN],
            "artefact_position.scroll_id=$scroll_id",
            $old_userversion );

        $self->_run_add_user_query( 'artefact_data', [ARTEFACT_POSITION_JOIN],
            "artefact_position.scroll_id=$scroll_id",
            $old_userversion );

    }

# Removes the given scroll from a user/version with all its data from the current user/version
#
# Parameters
#   Id of the scroll
    sub remove_owner_from_scroll {
        my $self  = shift;
        my $id    = shift;
        my $where = " scroll_to_col.scroll_id= $id";
        $self->start_logged_action;

        $self->_run_remove_user_query(
            'sign_char_reading_data',
            [
                SIGN_CHAR_JOIN,   LINE_TO_SIGN_JOIN,
                COL_TO_LINE_JOIN, SCROLL_TO_COL_JOIN
            ],
            $where
        );

        $self->_run_remove_user_query( 'sign_char',
            [ LINE_TO_SIGN_JOIN, COL_TO_LINE_JOIN, SCROLL_TO_COL_JOIN ],
            $where );

        $self->_run_remove_user_query( 'sign_relative_position',
            [ LINE_TO_SIGN_JOIN, COL_TO_LINE_JOIN, SCROLL_TO_COL_JOIN ],
            $where );

        $self->_run_remove_user_query( 'real_sign_area',
            [ LINE_TO_SIGN_JOIN, COL_TO_LINE_JOIN, SCROLL_TO_COL_JOIN ],
            $where );

        $self->_run_remove_user_query( 'position_in_stream',
            [ LINE_TO_SIGN_JOIN, COL_TO_LINE_JOIN, SCROLL_TO_COL_JOIN ],
            $where );

        $self->_run_remove_user_query( 'line_to_sign',
            [ COL_TO_LINE_JOIN, SCROLL_TO_COL_JOIN ], $where );

        $self->_run_remove_user_query( 'line_data',
            [ COL_TO_LINE_JOIN, SCROLL_TO_COL_JOIN ], $where );

        $self->_run_remove_user_query( 'col_to_line', [SCROLL_TO_COL_JOIN],
            $where, );

        $self->_run_remove_user_query( 'col_data', [SCROLL_TO_COL_JOIN],
            $where );

        $self->_run_remove_user_query( 'scroll_to_col', [], $where );

        $self->_run_remove_user_query( 'scroll_data', [],
            "scroll_data.scroll_id=$id" );

        $self->stop_logged_action;

    }

# Removes the given column/fragment from a user/version with all its data from the current user/version
#
# Parameters
#   Id of the column/fragment
    sub remove_owner_from_col {
        my $self  = shift;
        my $id    = shift;
        my $where = " scroll_to_col.col_id= $id";
        $self->start_logged_action;

        $self->_run_remove_user_query(
            'sign_char_reading_data',
            [
                SIGN_CHAR_JOIN,   LINE_TO_SIGN_JOIN,
                COL_TO_LINE_JOIN, SCROLL_TO_COL_JOIN
            ],
            $where
        );

        $self->_run_remove_user_query( 'sign_char',
            [ LINE_TO_SIGN_JOIN, COL_TO_LINE_JOIN, SCROLL_TO_COL_JOIN ],
            $where );

        $self->_run_remove_user_query( 'sign_relative_position',
            [ LINE_TO_SIGN_JOIN, COL_TO_LINE_JOIN, SCROLL_TO_COL_JOIN ],
            $where );

        $self->_run_remove_user_query( 'real_sign_area',
            [ LINE_TO_SIGN_JOIN, COL_TO_LINE_JOIN, SCROLL_TO_COL_JOIN ],
            $where );

        $self->_run_remove_user_query( 'position_in_stream',
            [ LINE_TO_SIGN_JOIN, COL_TO_LINE_JOIN, SCROLL_TO_COL_JOIN ],
            $where );

        $self->_run_remove_user_query( 'line_to_sign',
            [ COL_TO_LINE_JOIN, SCROLL_TO_COL_JOIN ], $where );

        $self->_run_remove_user_query( 'line_data',
            [ COL_TO_LINE_JOIN, SCROLL_TO_COL_JOIN ], $where );

        $self->_run_remove_user_query( 'col_to_line', [SCROLL_TO_COL_JOIN],
            $where, );

        $self->_run_remove_user_query( 'col_data', [SCROLL_TO_COL_JOIN],
            $where );

        $self->_run_remove_user_query( 'scroll_to_col', [], $where );

        $self->stop_logged_action;

    }

# Sets the user_id for a given user whose credential are provided
# Earlier set id's are overwritten.
# If version is provided, also the version number is set anew otherwise it is set to 0
# Parameters
#   username
#   password
#   version (optional)
# Returns the new scrollversion if ok, otherwise unddef and a ref to the appropriate error array
# #@method
    sub set_user {
        my ( $self, $user_name, $password, $scrollversion ) = @_;
        undef $self->{private_SQE_DBI_data}->{main_action_sth};

        # Try to get the user id
        my $sth = $self->prepare(SQE_database_queries::GET_LOGIN);
        $sth->execute( $user_name, $password );
        if ( ( my $user_data = $sth->fetchrow_arrayref() )
            && not $sth->fetchrow_arrayref() )
        {
            #We got a unique user id - return datbase handler and id
            $sth->finish();
            $self->{private_SQE_DBI_data}->{user_id} = $user_data->[0];

            if ( $self->{private_SQE_DBI_data}->{user_id} == 0 ) {
                $self->_set_scrollversion(1);
                return 1;
            }
            elsif ( defined $scrollversion ) {
                return $self->set_scrollversion($scrollversion);
            }
            else {
                $self->_set_scrollversion(0);
                return 0;
            }

        }
        elsif ($user_data) {

    # We got more than one user ids - return without handler but with error data
            $sth->finish();
            $self->disconnect();
            return ( undef, SQE_Error::NO_UNIQUE_USER );

        }
        else {
            # We got no user id - - return without handler but with error data
            $sth->finish();
            $self->disconnect();
            return ( undef, SQE_Error::WRONG_USER_DATA );
        }

    }




# Sets the scrollversion to be used in sqe_queries
# The function checks, whether the new scrollversion does belong to the user.
# If ok, it returns the new scrollversion, otherwise undef and a ref to the  appropriate error-array
#
# Parameters:
#   new scrollversion
    sub set_scrollversion {

        my ( $self, $scroll_version_id ) = @_;

        ( $scroll_version_id, my $scroll_version_group_id ) =
          $self->get_first_row_as_array( SQE_DBI_queries::GET_SCROLLVERSION,
            $self->user_id, $scroll_version_id );

        # Return the scroll version id if the version could have been retrieved
        # other wise (undef, error_ref)

        if ( $scroll_version_id && $scroll_version_group_id, $scroll_version_group_id ) {
            $self->_set_scroll_version($scroll_version_id,)
        }
        return $self->{SCROLL_VERSION_ID} && $self->{SCROLL_VERSION_GROUP_ID}
          ? $self->{SCROLL_VERSION_ID}
          : ( undef, SQE_Error::WRONG_SCROLLVERSION );

 #        my ( $self, $new_scrollversion ) = @_;
 #
 #        # First check whether the new scrollversion is the global QWB version
 #        if ( $new_scrollversion == 1 ) {
 #            $self->_set_scrollversion(1);
 #            return 1;
 #        }
 #
 #        # If not, check, whether the scrollversion belongs to the current user
 #        my $check_sth =
 #          $self->prepare_cached(SQE_DBI_queries::CHECK_SCROLLVERSION);
 #        $check_sth->execute($new_scrollversion);
 #        my $data_ref = $check_sth->fetchrow_arrayref;
 #        $check_sth->finish;
 #        if ( $data_ref && $data_ref->[0] == $self->user_id ) {
 #            $self->_set_scrollversion($new_scrollversion);
 #            return $new_scrollversion;
 #        }
 #        return ( undef, SQE_Error::WRONG_SCROLLVERSION );
    }



    #Returns the current SQE-session-id
    sub session_id {
        my ($self) = @_;
        return $self->{private_SQE_DBI_data}->{SESSION}->{SESSION_ID};
    }

    #Sets a new session_id
    #Paramater:
    #    session_id
    sub set_session_id {
        my ( $self, $session_id ) = @_;
        $self->{private_SQE_DBI_data}->{session_id} = $session_id;

    }

=head2 set_session($session)

Set the session the database handler works for.
It also stores a reference of the database handler in the session object

=over 1

=item Parameters: SQE_Session::Session

=item Returns nothing

=back

=cut

    sub set_session {
        my ( $self, $session ) = @_;
        $self->{private_SQE_DBI_data}->{SESSION} = $session;
        $session->{DBH} = $self;
    }

    # Returns the current user_id
    sub user_id {
        return $_[0]->{private_SQE_DBI_data}->{user_id};
    }

    # Returns the current version
    sub scrollversion {
        return $_[0]->{private_SQE_DBI_data}->{scrollversion};
    }

    # Returns the current action_log_id
    sub action_log_id {
        return $_[0]->{private_SQE_DBI_data}->{main_action_id};
    }

=head2 Deprecated


=cut


    =head3 get_sign_stream_for_fragment_id($id)

    Creates a SQE_sign_stream for a fragment


=over 1

=item Parameters: the internal id of the fragment

=item Returns SQE_sign_stream

=back

=cut

    #@returns SQE_sign_stream
    #@deprecated
    sub create_sign_stream_for_fragment_id {
        my ( $self, $id ) = @_;
        return SQE_sign_stream->new(
            $self->selectall_hashref_with_key_from_column
                ( SQE_DBI_queries::GET_ALL_SIGNS_IN_FRAGMENT,
                    2, $id
                ),
        );
    }

    #@deprecated
    sub create_sign_stream_for_line_id {
        my ( $self, $id ) = @_;
        return SQE_sign_stream->new(
            $self->selectall_hashref_with_key_from_column
                ( SQE_DBI_queries::GET_ALL_SIGNS_IN_LINE,
                    2, $id
                ),
        );
    }

    # = DBI::db->selectcol_arrayref calles with a query string,
    # but uses injects automatically the current user-id and vesion
    #@deprecated
    sub selectcol_arrayref_sqe {
        my $self = shift;
        my $sth  = $self->prepare_sqe(shift);
        return $self->selectcol_arrayref( $sth, @_ );
    }

    # = DBI::db->selectall_arrayref calles with a query string,
    # but uses injects automatically the current user-id and vesion
    #@deprecated
    sub selectall_arrayref_sqe {
        my $self  = shift;
        my $query = shift;
        $self->_inject_scroll_version_id( \$query );
        return $self->selectall_arrayref( $query, @_ );
    }



    # Prepares a SQE-statement handler with injected user- and version-id.
    # The statement is always cached.
    # Parameters
    #    same as DB->prepare parameters
    #@deprecated
    #@returns SQE_st
    sub prepare_sqe {
        my $self  = shift;
        my $query = shift;
        $self->_inject_scroll_version_id( \$query );
        return bless $self->prepare_cached( $query, @_ ), 'SQE_st';
    }

# Internal function to substitute _user_ and _version_ found in a query with the current user- and version-is
# Parameter:
# Reference to the query string
#@deprecated
    sub _inject_scroll_version_id {
        my $self  = shift;
        my $query = shift;
        $$query =~ s/_scrollversion_/$self->scrollversion/goe;

    }


    # Internal function to sert a new scrollversion without prior checking
    # Parameters
    #   new scrollversion
    #@deprecated
    sub _set_scrollversion {
        my ( $self, $new_scrollversion ) = @_;
        $self->{private_SQE_DBI_data}->{scrollversion} = $new_scrollversion;
        my $set_to_db_sth =
            $self->prepare_cached(SQE_DBI_queries::SET_SESSION_SCROLLVERSION);
        $set_to_db_sth->execute( $new_scrollversion, $self->session_id );
        undef $self->{private_SQE_DBI_data}->{main_action_sth};
    }

}

############################################################################################
#   SQE_st
############################################################################################

# A child of DBI::st which adds function for logged actions
{

    package SQE_st;
    use parent -norequire, 'DBI::st';

    use constant {
        NEW_SINGLE_ACTION => << 'MYSQL',
        INSERT INTO single_action
        (main_action_id, action, `table`, id_in_table)
        VALUES (?, '_action_art_', '_table_', ?)
MYSQL

    };

# Tells the statementhandler which kind of action and table the following executes affect
# Parameters
#   the action ('ADD' or 'DELETE')
#   the affected table
    sub set_action {
        my ( $self, $action_art, $table ) = @_;
        if ( not $self->{private_sth} ) {
            my $query = NEW_SINGLE_ACTION;
            $query =~ s/_action_art_/$action_art/o;
            $query =~ s/_table_/$table/o;
            $self->{private_sth} = $self->{Database}->prepare_cached($query);
        }
    }

    # Execute the statement and logs it
    #
    sub logged_execute {
        my ( $self, $id ) = @_;
        my $dbh    = $self->{Database};
        my $result = $self->execute($id);
        $self->{private_sth}->execute( $dbh->action_log_id, $id )
          if $result > 0;
        return $result;

    }

    # Overwriting normal finish
    sub finish {
        my $self = shift;
        $self->{private_sth}->finish if $self->{private_sth};
        $self->SUPER::finish;
    }


1;

