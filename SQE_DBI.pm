
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

# Returns a  SQE database handler for the SQE database or (undef, error_ref) if no handler can be created
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

=head2 Common Database Functions

Contains all functions which can be used as shortcuts for executing queries

=cut

=head3 Global setting of setters and getters

The following part is run at compile time (and thus, when the server starts) and defines setter- and getter-queries and
a query to remove the current scroll version
for all tables which do have an owner table. The queries are stored in an global anonymous hash with the table name as key and
the global variable $data_tables holding a reference to the hash.

The following Queries are generated

=over 1

=item GET_QUERY: Selects all records from the data table with the given data except the id of the table id

=item SIMPLE_GET_QUERY: Selects the record with the given id

=item SET_QUERY: Creates a new record with the given data.

=item DELETE_QUERY: Removes the owner belonging to the given scroll_version_group from the record with the given id

=item FROM_PARENTS: Selects the ids retrieved by the ids of the parents to which the table provide datas and the current scrollversion

=back




=cut

    our $data_tables = {};

    INIT {
        my ($dbh) = SQE_DBI->get_sqe_dbh;
        my %geom_fields = ( polygon => 1, point => 1 );
        my $sth = $dbh->prepare_cached(SQE_DBI_queries::GET_OWNER_TABLE_NAMES);
        $sth->execute;
        my $owner_table;
        my $field_name;
        $sth->bind_col( 1, \$owner_table );
        while ( $sth->fetch ) {
            my $table = substr( $owner_table, 0, -6 );
            my @field_names = @{
                $dbh->selectall_arrayref( 'DESCRIBE ' . $table,
                    { Columns => [ 1, 2 ] } )
            };

            $data_tables->{$table}->{GET_QUERY} = "
            SELECT * FROM $table
            WHERE "
              . join(
                ' AND ',
                map ( $_->[0]
                      . (
                        $geom_fields{ $_->[1] } ? '=ST_GeomFromText(?)' : '=?'
                      ),
                    grep ( $_->[0] ne "${table}_id", @field_names ) )
              );

            $data_tables->{$table}->{SET_QUERY} = "INSERT INTO $table ("
              . join( ',',
                map ( $_->[0], grep ( $_->[0] ne "${table}_id", @field_names ) )
              )
              . ") VALUES ("
              . join(
                ' , ',
                map ( ( $geom_fields{ $_->[1] } ? 'ST_GeomFromText(?)' : '?' ),
                    grep ( $_->[0] ne "${table}_id", @field_names ) )
              ) . ')';

            $data_tables->{$table}->{DELETE_QUERY} = "
            DELETE ${table}_owner
            FROM ${table}_owner
            JOIN scroll_version USING (scroll_version_id)
            WHERE ${table}_id = ? AND scroll_version_group_id = ?";

            $data_tables->{$table}->{SIMPLE_GET_QUERY} = "
            SELECT *
            FROM $table
            WHERE ${table}_id = ?
             ";

            $data_tables->{$table}->{GET_OWNER_TABLES} = "
        SELECT *
        FROM ${table}_owner
            JOIN scroll_version USING (scroll_version_id)
            WHERE scroll_version_group_id = ?";

            $data_tables->{$table}->{FROM_PARENTS} = "
              SELECT ${table}_id
               FROM ${table}
               JOIN ${table}_owner USING (${table}_id)
              JOIN scroll_version USING (scroll_version_id)
                WHERE "
              . join(
                ' AND ',
                map ( $_->[0] . '=?',
                    grep ( index( $_->[0], '_id' ) != -1
                          && $_->[0] ne "${table}_id",
                        @field_names ) )
              ) . " AND scroll_version_group_id = ?";
        }

        $sth->finish;
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

=head3 start_transaction()

Sets the DB into the transaction mode.

Should be cancelled by stop_transaction

=over 1

=item Parameters: none

=item Returns nothing

=back

=cut

    sub start_transaction {
        $_[0]->{AutoCommit} = 0;
    }

=head3 stop_transaction()

eEnd the transaction mode

=over 1

=item Parameters: none

=item Returns nothing

=back

=cut

    sub stop_transaction {
        my ($self) = @_;
        $self->commit;
        $self->{AutoCommit} = 1;
    }

=head2 User and Scrollversion Management


=head3 set_scrollversion($scroll_version_id)

Sets a new scrollversion and related data as the current one to the current session.

Returns (undef, error_ref) if the scrollversion can't be set for the current user.

=over 1

=item Parameters: id of the new scrollversion

=item Returns scroll version id  || (undef, error_ref)

=back

=cut

    sub set_scrollversion {

        my ( $self, $scroll_version_id ) = @_;

        $scroll_version_id =
          $self->session->set_scrollversion($scroll_version_id);

        if ($scroll_version_id) {
            return $scroll_version_id;
        }
        else {
            return ( undef, SQE_Error::WRONG_SCROLLVERSION );
        }
    }

=head3 scroll_version_id()

Returns the id the current scrollversion

=over 1

=item Parameters: none

=item Returns id of the current scrollversion

=back

=cut

    sub scroll_version_id {
        return $_[0]->{private_SQE_DBI_data}->{SESSION}->{SCROLL_VERSION_ID};

    }

=head3 scroll_version_group_id()

Returns the group id of the current scrollversion

=over 1

=item Parameters: none

=item Returns id of the group of the current scrollversion

=back

=cut

    sub scroll_version_group_id {
        my ($self) = @_;
        return $self->{private_SQE_DBI_data}->{SESSION}
          ->{SCROLL_VERSION_GROUP_ID};
    }

=head3 may_write()

Returns 1 if the user may write to current scroll version

=over 1

=item Parameters:

=item Returns 1 if the user may write, otherwise 0

=back

=cut

    sub may_write {
        return $_[0]->{private_SQE_DBI_data}->{SESSION}->{WRITABLE};
    }

=head3 may_lock()

Returns 1 if the user may lock the writing to all scrillversions in the current group

=over 1

=item Parameters:

=item Returns 1 if the user may lock, otherwise 0

=back

=cut

    sub may_lock {
        return $_[0]->{private_SQE_DBI_data}->{SESSION}->{MAY_LOCK};
    }

=head3 scroll_id()

Returns the current scroll id

=over 1

=item Parameters:

=item Returns id of the current scroll

=back

=cut

    sub scroll_id {
        return $_[0]->{private_SQE_DBI_data}->{SESSION}->{SCROLL_ID};

    }

=head3 set_scroll_version_group_admin($scroll_version_group_id, $user_id)

Sets the given user as administrator for the given scroll version group

=over 1

=item Parameters:   id of the scroll version group
                    id of the user

=item Returns nothing

=back

=cut

    sub set_scroll_version_group_admin {
        my ( $self, $scroll_version_group_id, $user_id ) = @_;
        my $sth = $self
          ->prepare_cached(SQE_DBI_queries::CREATE_SCROLL_VERSION_GROUP_ADMIN);
        $sth->execute( $scroll_version_group_id, $user_id );
        $sth->finish;
    }

=head3 copy_data_to_scroll_version($old_scroll_version_group_id, $new_scroll_version_id)

Copy all data of the old scroll version group to the new scroll version

=over 1

=item Parameters: id of the old scroll version group
                  id of the new scroll version

=item Returns nothing

=back

=cut

    sub copy_data_to_scroll_version {
        my ( $self, $old_scroll_version_group_id, $new_scroll_version_id ) = @_;

        for my $table ( keys %{$data_tables} ) {
            my $query       = SQE_DBI_queries::CLONE_SCROLL_VERSION;
            my $owner_table = $table . '_owner';
            $query =~ s/\*OWNER\*/$owner_table/go;
            $query =~ s/\*TABLE\*/$table/go;
            $query =~ s/\*SVID\*/$new_scroll_version_id/go;
            $query =~ s/\*OLDSVID\*/$old_scroll_version_group_id/go;
            $self->do($query);
        }
    }

=head3 is_scroll_version_group_admin($scroll_version_group_id, $user_id)

Test whether the referenced user is administatormof the referenced scroll version group

=over 1

=item Parameters: id of the scroll version group
                  id of user

=item Returns 1 || undefined

=back

=cut

    sub is_scroll_version_group_admin {
        my ( $self, $scroll_version_group_id, $user_id ) = @_;
        return (
            $self->get_first_row_as_array
              ( SQE_DBI_queries::IS_SCROLL_VERSION_GROUP_ADMIN,
                $scroll_version_group_id, $user_id
              )
        )[0];
    }

=head3 clone_current_scroll()

Creates a writable clone of the current scroll and returns its scroll version id

=over 1

=item Parameters: none

=item Returns new scroll version id

=back

=cut

    sub clone_current_scroll {
        my ($self) = @_;
        $self->start_transaction;
        my $new_scroll_version_group_id =
          $self->create_scroll_version_group( $self->scroll_id, 0,
            $self->user_id );
        my $new_scroll_version_id =
          $self->create_scrollversion_for_group( $self->user_id,
            $new_scroll_version_group_id );
        $self->copy_data_to_scroll_version( $self->scroll_version_group_id,
            $new_scroll_version_id );
        $self->stop_transaction;
        return $new_scroll_version_id;
    }

=head3 create_scroll_version_group($scroll_id, $locked, $admin_id)

Creates a new scroll version group.

If scroll id is defined, the referenced scroll is set as scroll otherwise 0.

If locked is defined the lock status is set accordingly, other to 0 (= unlocked).

If admin_id is set, the referenced user is set as administrator of this scroll version group

=over 1

=item Parameters:

=item Returns id of new scroll version group

=back

=cut

    sub create_scroll_version_group {
        my ( $self, $scroll_id, $locked, $admin_id ) = @_;
        $scroll_id = defined $scroll_id ? $scroll_id : 0;
        $locked    = defined $locked    ? $locked    : 1;
        my $sth =
          $self->prepare_cached(SQE_DBI_queries::NEW_SCROLL_VERSION_GROUP);
        $sth->execute( $scroll_id, $locked );
        my $new_scroll_version_group_id = $self->{mysql_insertid};
        $sth->finish;
        $self->set_scroll_version_group_admin( $new_scroll_version_group_id,
            $admin_id )
          if $admin_id;
        return $new_scroll_version_group_id;

    }

=head3 create_scrollversion_for_group($user_id, $scroll_version_group_id)

Creates a new scroll_version record for the referenced user and adds it to the referenced scroll version group.

Can only be run by an administrator of the group

=over 1

=item Parameters: id of the scroll version group to which the scroll version should belong

=item Returns new scroll version id || (undef, error_ref)
if the current user is not administrator of the scroll version group

=back

=cut

    sub create_scrollversion_for_group {
        my ( $self, $user_id, $scroll_version_group_id ) = @_;

        return ( undef, SQE_Error::NO_SVG_ADMIN )
          if !$self->is_scroll_version_group_admin( $scroll_version_group_id,
            $self->user_id );

        # Create a new scroll_version as member of the new group
        my $sth = $self->prepare_cached(SQE_DBI_queries::NEW_SCROLL_VERSION);
        $sth->execute( $user_id, $scroll_version_group_id );
        my $new_scroll_version_id = $self->{mysql_insertid};
        $sth->finish;

        return $new_scroll_version_id;
    }

=head3 delete_scroll_version($scroll_version_id)

Deletes the referenced scroll version.

If the owner of the scroll_version is the last or only administrator of the connected scroll version group,
all data connected with this group are disconnected and the whole group is deleted and 0 returned,
meaning the current

Otherwise the data of the scroll version are transferred to the scroll version of the administrator using this function.

=over 1

=item Parameters: id of the scroll version to be deleted

=item Returns   -1 (the current scroll version and scroll version group is no more valid)
                || 0 (the current scroll version is no more valid)
                || 1 (the current scroll version is still valid)
                || (undef, error_ref)
if the current user is not administrator of the scroll version group

=back

=cut

    sub delete_scroll_version {
        my ( $self, $scroll_version_id ) = @_;

# First get the user and the scroll version group of the scroll version to be deleted
        my ( $user_id, $scroll_version_group_id ) = (
            $self->get_first_row_as_array(
                SQE_DBI_queries::GET_SCROLLVERSION_DATA,
                $scroll_version_id
            )
        )[ 1 .. 2 ];

        # Test, whether the current user may delete this scroll version
        return ( undef, SQE_Error::NO_SVG_ADMIN )
          if !$self->is_scroll_version_group_admin( $scroll_version_group_id,
            $self->user_id );

        my $new_admin = $self->user_id;

# If (s)he is allowed to do so, test whether (s)he is also the owner of the scroll version to be deleted
        if ( $user_id == $self->user_id ) {

            # Get a different admin
            ($new_admin) =
              $self->get_first_row_as_array
              ( SQE_DBI_queries::GET_DIFFERENT_SCROLL_VERSION_GROUP_ADMIN,
                $scroll_version_group_id, $user_id );

            # If no other admin is found
            if ( !$new_admin ) {

                # Delete the whole scroll_version_group
                $self->_delete_scroll_version_group($scroll_version_group_id);
                return -1;
            }
            else {
                # A different admin is found
                my ($new_scroll_version_id) = $self->get_first_row_as_array(
                    SQE_DBI_queries::GET_SCROLLVERSION_ID,
                    $new_admin, $scroll_version_group_id );
                $self->_move_scroll_version_data( $scroll_version_id,
                    $new_scroll_version_id );
                return 0;
            }

        }
        else {
            $self->_move_scroll_version_data( $scroll_version_id,
                $self->scroll_version_id );
            return 1;
        }

    }

    sub _delete_scroll_version_group {
        my ( $self, $scroll_version_group_id ) = @_;

        $self->start_transaction;
        for my $table ( keys %{$data_tables} ) {
            my $query       = SQE_DBI_queries::DELETE_SCROLLVERSION_FROM_OWNERS;
            my $owner_table = $table . '_owner';
            $query =~ s/\*OWNER\*/$owner_table/go;
            $query =~ s/\*SVID\*/$scroll_version_group_id/go;
            $self->do($query);
        }
##        $self->do( SQE_DBI_queries::DELETE_SCROLLVERSION_FROM_ACTIONS, undef,
        #             $scroll_version_group_id );
        $self->do( SQE_DBI_queries::DELETE_SCROLL_VERSION_GROUP,
            undef, $scroll_version_group_id );
        $self->stop_transaction;

        return 1;
    }

    sub _move_scroll_version_data {
        my ( $self, $old_scroll_version_id, $new_scroll_version_id ) = @_;
        for my $table ( keys %{$data_tables} ) {
            my $query       = SQE_DBI_queries::COPY_SCROLL_VERSION_DATA;
            my $owner_table = $table . '_owner';
            $query =~ s/\*OWNER\*/$owner_table/go;
            $query =~ s/\*TABLE\*/$table/go;
            $query =~ s/\*SVID\*/$new_scroll_version_id/go;
            $query =~ s/\*OLDSVID\*/$old_scroll_version_id/go;
            $self->do($query);
        }

    }

    #@returns SQE_st
    sub _get_prepared_sqe_sth {
        my ( $self, $table, $art, $query ) = @_;
        my $key = $art . '@' . $table;
        my $sth = $self->{private_SQE_DBI_data}->{SQE_STH}->{$key};
        if ( !$sth ) {
            $sth = bless $self->prepare_cached($query), 'SQE_st';
            $sth->set_action( $art, $table );
            $self->{private_SQE_DBI_data}->{SQE_STH}->{$key} = $sth;
        }
        return $sth;
    }

=head2 Writing of Data

Contains all functions to be uesd to write, change, or remive data.

=cut

=head3 start_logged_action()

Starts a set of logged actions and must be stopped with stop_logged_action().

Logged actions must use an SQE_st statement and must be executed by its function logged_exectue().

The function tests whether the user is allowe to writeto this scroll version = may_write in scroll_version is true.
Returns the id of the set if this is the case, otherwise it return (undef, error_ref) and does nit start the set of logged actions

=over 1

=item Parameters: none

=item Returns id of the started set or (undef, error_ref) if the user is not allowed to write to this scrollversion

=back

=cut

    # Starts a set of logged actions
    # Must be ended by stop_logged_action
    # Logged action must use an SQE_st Statement and executed by logged_execute
    sub start_logged_action {
        my $self = shift;

        return ( undef, SQE_Error::MAY_NOT_WRITE ) if !$self->may_write;

        $self->{AutoCommit} = 0;
        my $sth = $self->{private_SQE_DBI_data}->{main_action_sth};
        if ( not $sth ) {
            $sth = $self->prepare_cached(SQE_DBI_queries::NEW_MAIN_ACTION);
            $self->{private_SQE_DBI_data}->{main_action_sth} = $sth;
        }
        $sth->execute( $self->scroll_version_id );
        return $self->{private_SQE_DBI_data}->{main_action_id} =
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

=head3 set_new_data_to_owner($table, @data)

Searches for a record containing the needed data.
If a record is not found a record with the data is
created.

Finally, the current scroll_verion is set as an owner to the retrieved or created record.

=over 1

=item Parameters:   name of the table,
                    array of data

=item Returns  id of the retrieved or created record


=back

=cut

    sub set_new_data_to_owner {
        my ( $self, $table, @data ) = @_;
        my $id = $self->set_new_data( $data_tables->{$table}->{GET_QUERY},
            $data_tables->{$table}->{SET_QUERY}, @data );
        $self->add_owner( $table, $id );
        return $id;
    }

=head3 replace_data($table, @old_data, @new_data)

Removes the record which has the old_data from the current scroll_version_group and adds a record with the new data.

=over 1

=item Parameters: Name of the tabe
                  Reference to array with the old data
                  Reference to array with the new data

=item Returns id of the new data record

=back

=cut

    sub replace_data {
        my ( $self, $table, $old_data_ref, $new_data_ref ) = @_;
        my $get_sth =
          $self->prepare_cached( $data_tables->{$table}->{GET_QUERY} );
        $get_sth->execute( @{$old_data_ref} );
        my $data_id;
        $get_sth->bind_col( 1, \$data_id );
        while ( $get_sth->fetch ) {
            $self->remove_data( $table, $data_id );
        }
        return $self->set_new_data_to_owner( $table, @{$new_data_ref} );

    }

=head3 set_new_data($get_query, $set_query, @data)

Searches for a record containing the needed data using get_query
If a record is not found a record with the data is
created using set_query.

The id of the retrieved or created record is given back

=over 1

=item Parameters:   the query to retrieve the data,
                    the query to set the data,
                    array of data

=item Returns  id of the retrieved or created record

=back

=cut

    sub set_new_data {
        my ( $self, $get_query, $set_query, @data ) = @_;
        my $id;

        my $sth = $self->prepare_cached($get_query);
        $sth->execute(@data);
        if ( my $res_ref = $sth->fetchrow_arrayref ) {
            $id = $res_ref->[0];
            $sth->finish;
        }
        else {
            $sth->finish;
            $sth = $self->prepare_cached($set_query);
            $sth->execute(@data);
            $id = $self->{mysql_insertid};
            $sth->finish;
        }
        return $id;
    }

=head3 add_owner($table, $id)

Adds the current scroll version as owner sto the record referred by id of the table referred to by table

=over 1

=item Parameters:   name of the table the record belongs to
                    id of the record

=item Returns nothing

=back

=cut

    sub add_owner {
        my $self  = shift;
        my $table = shift;
        my $id    = shift;
        my $query =
"INSERT IGNORE INTO ${table}_owner (${table}_id, scroll_version_id) VALUES (?,?)";
        my $sth = $self->_get_prepared_sqe_sth( $table, 'add', $query );
        $sth->logged_execute( $id, $self->scroll_version_id );
        $sth->finish;
    }

=head3 set_sign_char_commentary($sign_char_id, $attribute_id, $text)

Creates a new commentary to a sign char refereing to a certain attribute

=over 1

=item Parameters: id of the sign char
                  id of the attribute
                  commentary text

=item Returns the id of the new commentary

=back

=cut

    sub set_sign_char_commentary {
        my ( $self, $sign_char_id, $attribute_id, $text ) = @_;
        my $new_id =
          $self->set_new_data_to_owner( 'sign_char_commentary', $sign_char_id,
            $attribute_id, $text );
        return $new_id;
    }

    sub remove_sign_char_commentary {
        my ( $self, $sign_char_commentary_id ) = @_;
        $self->remove_data( 'sign_char_commentary', $sign_char_commentary_id );

    }

=head3 set_sign_char_attribute($sign_char_id, $attribute_value_id, $numeric_value)

Set the given attribute_value (and optional the numeric value and/or sequence) to the given sign char
and returns the sign char id (which may have changed)

=over 1

=item Parameters:   id of sign_char,
                    id of attribute value,
                    optional a numeric value
                    optional the sequence number when

=item Returns id of sign char

=back

=cut

    sub set_sign_char_attribute {
        my ( $self, $sign_char_id, $attribute_value_id, $numeric_value,
            $sequence )
          = @_;

        # Define sequence as 0 if undefined
        $sequence = $sequence ? $sequence : 0;

        my $new_sign_char_attribute_id;

        # If also a numeric values needs to be set
        if ($numeric_value) {

     # Let's test, wether already a sign_char_attribute with the all data exist,
            ($new_sign_char_attribute_id) =
              $self->get_first_row_as_array
              ( SQE_DBI_queries::GET_SIGN_CHAR_ATTRIBUTE_NUMERIC,
                $sign_char_id, $attribute_value_id,
                $sequence,     $numeric_value
              );

# If it not exist, create a new sign_char_attribute with the attribute value and sequence
            if ($new_sign_char_attribute_id) {

                my $sth =
                  $self->prepare_cached(
                    $data_tables->{'sign_char_attribute'}->{SET_QUERY} );
                $sth->execute( $sign_char_id, $attribute_value_id, $sequence );
                $new_sign_char_attribute_id = $self->{mysql_insertid};
                $sth->finish;
                $sth =
                  $self->prepare_cached(SQE_DBI_queries::NEW_NUMERIC_VALUE);
                $sth->execute( $new_sign_char_attribute_id, $numeric_value );
                $sth->finish;
            }

     # Finally add the correct sign char attribute to the current scroll version
            $self->add_owner( 'sign_char_attribute',
                $new_sign_char_attribute_id );
        }
        else {
            # No numeric value is set.
            $new_sign_char_attribute_id = $self->set_new_data_to_owner(
                'sign_char_attribute', $sign_char_id,
                $attribute_value_id,   $sequence
            );

        }
        return $new_sign_char_attribute_id;

    }

=head3 delete_sign_char_attributes_for_attribute($sign_char_id, $attribute_value_id)

=over 1

=item Parameters:

=item Returns

=back

=cut

    sub delete_sign_char_attributes_for_attribute {
        my ( $self, $sign_char_id, $attribute_value_id ) = @_;
        my $sth = $self->prepare_cached
          (SQE_DBI_queries::GET_ALL_SIGN_CHAR_ATTRIBUTES_FOR_ATTRIBUTE);
        $sth->execute( $sign_char_id, $self->scroll_version_group_id,
            $attribute_value_id );
        my $sign_char_attribute_id;
        $sth->bind_col( 1, \$sign_char_attribute_id );
        while ( $sth->fetch ) {
            $self->remove_data( 'sign_char_attribute',
                $sign_char_attribute_id );
        }
        $sth->finish;
    }

=head3 set_sign_char_variant_status($sign_char_id, $as_variant, $new_main_id)

Sets the varinat status the sign_char referenced by the given sign_char_id to $as_variant.

Id $as_variant is 0 (= the sign_char should be set as main char sign) and the old status was 1,
$new_main_id must be specified

=over 1

=item Parameters:   id of th sign_char
                    variant flag (1 || 0)
                    optional the id of the sign char which should become the new main sign_char

=item Returns

=back

=cut

    sub set_sign_char_variant_status {
        my ( $self, $sign_char_id, $as_variant, $new_main_id ) = @_;

        my ( $sign_id, $is_variant, $sign ) =
          $self->get_first_row_as_array( SQE_DBI_queries::GET_SIGN_CHAR_DATA,
            $sign_char_id );

        # Return if the sign_char has already the wanted status
        return ($sign_char_id) if $as_variant == $is_variant;

        # If the sign_char should be set as main entrance
        # we have to save the old main entrance to set it a variant reading
        if ( !$as_variant ) {
            my @old_main_data =
              $self
              ->get_first_row_as_array( SQE_DBI_queries::GET_MAIN_SIGN_CHAR,
                $sign_id, $self->scroll_version_id );
            $self->set_new_data_to_owner( 'sign_char', $old_main_data[1], 1,
                $old_main_data[3] );
            $self->remove_data( 'sign_char', $old_main_data[0] );
        }
        else {
            # The sign char should be set as a variant but is the main entrance
            # Create a new main entrance with new_main_id

            return ( undef, SQE_Error::NO_MAIN_CHAR_ENTRANCE ) if !$new_main_id;
            my @new_main_data =
              $self
              ->get_first_row_as_array( SQE_DBI_queries::GET_SIGN_CHAR_DATA,
                $new_main_id );
            $self->set_new_data_to_owner( 'sign_char', $new_main_data[0], 0,
                $new_main_data[2] );
        }

        #Finally set the data for the sign_char
        $self->remove_data( 'sign_char', $sign_char_id );
        $self->set_new_data_to_owner( 'sign_char', $sign_id, $as_variant,
            $sign );

    }

    sub move_line_number {
        my ( $self, $sign_id, $delta ) = @_;

        my $line_end_sth =
          $self->prepare_cached(SQE_DBI_queries::GET_LAST_SIGN_FRAGMENT);
        my $line_sth = $self->prepare_cached(SQE_DBI_queries::GET_REF_DATA);
        $line_sth->execute( $sign_id, $self->scroll_version_group_id );
        my ( $line_name, $line_id, $col_id );
        $line_sth->bind_col( 6, \$line_name );
        $line_sth->bind_col( 5, \$line_id );
        $line_sth->bind_col( 3, \$col_id );
        while ( $line_sth->fetch ) {
            my $new_line_name = $line_name;
            $new_line_name =~
              s/(.*?)([0-9]+)([^0-9]*?)/$1 . ($2+$delta) . $3/oe;
            print $line_name . ' - ' . $new_line_name;
        }
    }

=head3 remove_data($table, $id)

Removes data hold in a table with an owner table from the current scroll version group

=over 1

=item Parameters: name of the table holding the data, id of the record

=item Returns

=back

=cut

    sub remove_data {
        my ( $self, $table, $id ) = @_;
        my $sth =
          $self->_get_prepared_sqe_sth( $table, 'delete',
            $data_tables->{$table}->{DELETE_QUERY} );
        my $result =
          $sth->logged_execute( $id, $self->scroll_version_group_id );
        $sth->finish;
        return $result;
    }

=head3 remove_all_data($sign_char_id, $search_query, $table)

Removes the owner from each data record whose id is retrieved by the given search.

The search query must retrieve as the first value the unique id of the table given in $table,
which must be bind to an _owner table.

The last parameter to be set to the query must be scroll_version_group_id

=over 1

=item Parameters:   query string of the search
                    name of the table
                    array of search data

=item Returns nothing

=back

=cut

    sub remove_all_data {
        my ( $self, $search_query, $table, @search_data ) = @_;
        my $sth = $self->prepare_cached($search_query);
        $sth->execute( @search_data, $self->scroll_version_group_id );
        my $data_id;
        $sth->bind_col( 1, \$data_id );
        while ( $sth->fetch ) {
            $self->remove_data( $table, $data_id );
        }
        $sth->finish;

    }

=head3 remove_sign_char_attribute($sign_char_attribute_id)

Removes the sign char attribute with the given id.

=over 1

=item Parameters: id of the sign_char_attribute to be removed

=item Returns nothing

=back

=cut

    sub remove_sign_char_attribute {
        my ( $self, $sign_char_attribute_id ) = @_;
        $self->remove_data( 'sign_char_attribute', $sign_char_attribute_id );
    }

=head3 remove_sign_char($sign_char_id)

Removes a sign_char from the given scroll_version

=over 1

=item Parameters: id of the sign char to be removed

=item Returns nothing

=back

=cut

    sub remove_sign_char {
        my ( $self, $sign_char_id ) = @_;
        $self->remove_all_data( SQE_DBI_queries::GET_ALL_ATTRIBUTES,
            'sign_char_attribute', $sign_char_id );
        $self->remove_all_data( SQE_DBI_queries::GET_ALL_ROIS, 'sign_char_roi',
            $sign_char_id );
    }

=head3 remove_sign($sign_id)

Removes a sign and all data connected to it from the current scroll version group

=over 1

=item Parameters: id of sign

=item Returns nothing

=back

=cut

#ToDo autonaitsch steuerung bei breaks
    sub remove_sign {
        my ( $self, $sign_id ) = @_;

        my $tmp_id;

        # First remove all sign_chars
        my $sth = $self->prepare_cached(SQE_DBI_queries::GET_ALL_SIGN_CHARS);
        $sth->execute( $sign_id, $self->scroll_version_group_id );
        $sth->bind_col( 1, \$tmp_id );
        while ( $sth->fetch ) {
            $self->remove_sign_char($tmp_id);
        }
        $sth->finish;

        # Then remove the  positions in stream where the sign is main sign_id,
        # but store the next_sign_id's

        my ( $position_in_stream_id, $next_sign_id );
        my @next_sign_ids;
        $sth =
          $self->prepare_cached(SQE_DBI_queries::GET_POSITION_IN_STREAM_DATA);
        $sth->execute( $sign_id, $self->scroll_version_group_id );
        $sth->bind_columns( \$position_in_stream_id, \$next_sign_id );
        while ( $sth->fetch ) {
            push @next_sign_ids, $next_sign_id;
            $self->remove_data( 'position_in_stream', $position_in_stream_id );
        }
        $sth->finish;

        # Then remove the  positions in stream where the sign is next sign,
        # but store the sign_id's of the prev sign
        my @prev_sign_ids;
        my $prev_sign_id;
        $sth =
          $self
          ->prepare_cached(SQE_DBI_queries::GET_PREV_POSITION_IN_STREAM_DATA);
        $sth->execute( $sign_id, $self->scroll_version_group_id );
        $sth->bind_columns( \$position_in_stream_id, \$prev_sign_id );
        while ( $sth->fetch ) {
            push @prev_sign_ids, $prev_sign_id;
            $self->remove_data( 'position_in_stream', $position_in_stream_id );
        }
        $sth->finish;

        #Then create new connections of the now unconnected signs

        for $next_sign_id (@next_sign_ids) {
            for $prev_sign_id (@prev_sign_ids) {
                $self->set_new_data_to_owner( 'position_in_stream',
                    $prev_sign_id, $next_sign_id );
            }
        }

        #Finally remove the connection to the line
        $sth =
          $self->prepare_cached
          ( SQE_DBI_queries::GET_LINE_TO_SIGN_FOR_SCROLL_VERSION_GROUP );
        $sth->execute( $sign_id, $self->scroll_version_group_id );
        $sth->bind_col( 1, \$tmp_id );
        while ( $sth->fetch ) {
            $self->remove_data( 'line_to_sign', $tmp_id );
        }
        $sth->finish;

    }

=head3 add_roi($sign_char_id, $roi_shape, $roi_position, $values_set, $execeptional)

Adds a ROI to a sign char

=over 1

=item Parameters:   id of the sign char
                    path of the ROI as GEoJSON object
                    transformation matrix as JSON array
                    tag vir vaules set
                    tag for execeptional

=item Returns new sign char roi id

=back

=cut

    sub add_roi {
        my (
            $self,         $sign_char_id, $roi_shape,
            $roi_position, $values_set,   $execeptional
        ) = @_;
        my $roi_shape_id     = $self->get_roi_shape_id($roi_shape);
        my $roi_position_id  = $self->get_roi_position_id($roi_position);
        my $sign_char_roi_id = $self->set_new_data_to_owner(
            'sign_char_roi',  $sign_char_id, $roi_shape_id,
            $roi_position_id, $values_set,   $execeptional
        );
        $self->add_owner( 'sign_char_roi', $sign_char_roi_id );

        return $sign_char_roi_id;

    }

    sub set_roi_data {
        my ( $self, $sign_char_roi_id, $new_path, $new_matrix, $new_values_set,
            $new_exceptional )
          = @_;
        my (
            $sign_char_id,   $old_path, $old_matrix,
            $old_values_set, $old_exceptional
        ) = $self->get_roi_data($sign_char_roi_id);
        $new_path       = $new_path       ? $new_path       : $old_path;
        $new_matrix     = $new_matrix     ? $new_matrix     : $old_matrix;
        $new_values_set = $new_values_set ? $new_values_set : $old_values_set;
        $new_exceptional =
          $new_exceptional ? $new_exceptional : $old_exceptional;
        my $new_sign_char_roi_id = $self->add_roi(
            $sign_char_id,   $new_path, $new_matrix,
            $new_values_set, $new_exceptional
        );
        if ( $new_sign_char_roi_id != $sign_char_roi_id ) {
            $self->remove_data( 'sign_char_roi', $sign_char_roi_id );
        }
        return $new_sign_char_roi_id;
    }

=head3 add_artefact($image_id)

Creates a new artefact on the image given image

=over 1

=item Parameters: id of the image

=item Returns id of the artefact

=back

=cut

    sub add_artefact {
        my ( $self, $image_id, $region ) = @_;
        my $create_sth = $self->prepare_cached(SQE_DBI_queries::ADD_ARTEFACT);
        $create_sth->execute();
        my $artefact_id = $self->{mysql_insertid};
        $create_sth->finish;
        $self->set_artefact_shape( $artefact_id, $image_id, $region );
        return $artefact_id;
    }

=head exchange_data_for_parent($table, $parent_id, @data)

Exchange the data in the given data table for the parent referenced by parent_id, which must be in a field
with XXXX_id as name.

This should be only used with data tables which provide only one record for the record in the table,
it's connected with.


=over 1

=item Parameters: name of the data table
                  id of the parent, which must be referenced in the table with an XXX_id field

=item Returns

=back

=cut

    sub exchange_data_for_parent {
        my ( $self, $table, $parent_id, @data ) = @_;
        my $data_id = $self->get_id_from_parent( $table, $parent_id );
        $self->exchange_data( $table, $data_id, $parent_id, @data );
    }

=head exchange_data($table, $data_id, @data)

Exchanges for the current scrollversion the record of ownered table with
referenced by data_id with a new record with the the given data


=over 1

=item Parameters: id of the lod record
                  Array of new data (must be complete!)
=item Returns id of the new record.

=back

=cut

    sub exchange_data {
        my ( $self, $table, $data_id, @data ) = @_;
        my $new_id = $self->set_new_data_to_owner( $table, @data );
        if ($data_id) {
            if ( $new_id != $data_id ) {
                $self->remove_data( $table, $data_id );
            }
        }
        return $new_id;
    }


=head3 set_scroll_name($name)

Sets name as new name for the scroll of the current scrollversion

=over 1

=item Parameters: id of scroll

=item Returns

=back

=cut

    sub set_scroll_name {
        my ($self, $name) = @_;
        $self->exchange_data_for_parent( 'scroll_data', $name, $self->scroll_id);
    }

=head3 set_col_name($col_id, $name)

Sets name as new name for the column of the current scrollversion referenced by col_id

=over 1

=item Parameters: id of col
                  new name of col

=item Returns nothing

=back

=cut

    sub set_col_name {
        my ($self, $col_id, $name) = @_;
        $self->exchange_data_for_parent( 'col_data', $col_id, $name );
    }

=head3 set_line_name($line_id, $name)

Sets name as new name for the line of the current scrollversion referenced by line_id

=over 1

=item Parameters: id of line
                  new name of line

=item Returns nothing

=back

=cut

    sub set_line_name {
        my ($self, $line_id, $name) = @_;
        $self->exchange_data_for_parent( 'line_data', $name, $line_id );
    }

=head3 set_artefact_shape($artefact_id, $image_id, $region)


=over 1

=item Parameters: id of artefact
                  id of image
                  polygon of region as WKT

=item Returns nothing

=back

=cut

    sub set_artefact_shape {
        my ( $self, @data ) = @_;
        $self->exchange_data_for_parent( 'artefact_shape', @data );
    }

=head3 set_artefact_position($artefact_id, $position, $z_index)

Sets the data of the position of an artefact

=over 1

=item Parameters: id of artefact
                  position matrix as String
                  optional z-position as id (if not given, this value is set to 0)

=item Returns nothing

=back

=cut

    sub set_artefact_position {
        my ( $self, @data ) = @_;
        $data[2] = $data[2] ? $data[2] : 0;
        $self->exchange_data_for_parent( 'artefact_position', @data );
    }

=head3 set_artefact_data($artefact_id, $name)

Stes the name of an artefact connectied to the current scrollverison

=over 1

=item Parameters: id of artefact
                  name as string

=item Returns nothing

=back

=cut

    sub set_artefact_data {
        my ( $self, @data ) = @_;
        $self->exchange_data_for_parent( 'artefact_data', @data );
    }

=head3 remove_artefact($artefact_id)

Removes an artefact by removing all referenced data

=over 1

=item Parameters: id of artefact

=item Returns nothing

=back

=cut

    sub remove_artefact {
        my ( $self, $artefact_id ) = @_;
        $self->remove_single_artefact_subdata( 'artefact_data', $artefact_id );
        $self->remove_single_artefact_subdata( 'artefact_position',
            $artefact_id );
        $self->remove_single_artefact_subdata( 'artefact_shape', $artefact_id );
    }

    sub remove_single_artefact_subdata {
        my ( $self, $table, $artefact_id ) = @_;
        if ( my $data_id = $self->get_id_from_parent( $table, $artefact_id ) ) {
            $self->remove_data( $table, $data_id );
        }

    }

=head3 remove_roi($sign_char_roi_id)

Remove the refrenced roi from the sign_char

=over 1

=item Parameters: id of sign char roi

=item Returns nothing

=back

=cut

    sub remove_roi {
        my ( $self, $sign_char_roi_id ) = @_;
        $self->remove_data( 'sign_char_roi', $sign_char_roi_id );
    }

=head3 clone_attributes($source_sign_char_id, $destination_sign_char_id)

Copies all attributes connectect to the source sign char to the destinaton sign char

=over 1

=item Parameters:   id of the souerce sign char,
                    id of the destination sign cahr
                    ref to array with the ids of the new attributes

=item Returns

=back

=cut

    sub clone_attributes {
        my ( $self, $source_sign_char_id, $destination_sign_char_id ) = @_;
        my $sth = $self->prepare_cached(SQE_DBI_queries::GET_ALL_ATTRIBUTES);
        $sth->execute( $source_sign_char_id, $self->scroll_version_group_id );
        my $new_attributes = [];
        while ( my @data = $sth->fetchrow_array ) {
            push @$new_attributes,
              $self->set_sign_char_attribute( $destination_sign_char_id,
                @data[ 2 .. 4 ] );
        }
        $sth->finish;
        return $new_attributes;
    }

=head3 clone_rois($source_sign_char_id, $destination_sign_char_id)

Copies all ROIs connected to the source sign char to the destinaton sign char

=over 1

=item Parameters:   id of the source sign char,
                    id of the destination sign cahr
                    ref to array with the ids of the new ROIs

=item Returns

=back

=cut

    sub clone_rois {
        my ( $self, $source_sign_char_id, $destination_sign_char_id ) = @_;
        my $sth = $self->prepare_cached(SQE_DBI_queries::GET_ALL_ROIS);
        $sth->execute( $source_sign_char_id, $self->scroll_version_group_id );
        my $new_rois = [];
        while ( my @data = $sth->fetchrow_array ) {
            push @$new_rois,
              $self->add_roi( $destination_sign_char_id, @data[ 2 .. 5 ] );
        }
        $sth->finish;
        return $new_rois;
    }

=head3 clone_sign_char($sign_char_id, $sign_id, $as_variant, $sign)

Creates a new sign char with and copies all attributes and ROIs from the sign char with the given
sign char id to the new one

=over 1

=item Parameters:   id of the sign char whose attribtues and ROIs should be used for the new sign char
                    sign_id to be set to the new sign char
                    variant flag to be set to the new sign char
                    sign (char) to be set to the new sign char

=item Returns the id of the new sign char

=back

=cut

    sub clone_sign_char {
        my ( $self, $sign_char_id, $sign_id, $as_variant, $sign ) = @_;
        my $sth = $self->prepare_cached(SQE_DBI_queries::NEW_SIGN_CHAR);
        $sth->execute( $sign_id, $as_variant, $sign );
        my $new_sign_char_id = $self->{mysql_insertid};

   # And add copy the attributes and ROIs from the main char sign to the new one
        $self->clone_attributes( $sign_char_id, $new_sign_char_id );
        $self->clone_rois( $sign_char_id, $new_sign_char_id );

        return $new_sign_char_id;

    }

=head3 new_sign($sign, $after, $before, @attribute_values)

Creates a new sign and sets its attributes.

At least $after or $before must be set.

If both are set, the sign will connect only to those both in the sign stream, if only $afte is given,
the new sign will be connected to this and to all which ortiginal follow the sign before, thus will be inserted between
the sign before and all its followers.

If only before is given, the sign will be inserted between all forrunners of $before and $before.

If no attribute values are given but $after, the sign will inherit all attributes from $after.

If also $after is not given, than an error will be thrown.

The attribute values are to be given in the following way:

Simple values which are not bind to a numeric value or a sequence are just given with there numeric ID.



=over 1

=item Parameters:   the char of the sign, '' if meta sign
                    the id of the sign after which the new sign should be added
                    the id of the sign before the new sign should be added
                    the id of line to which the new sign shoul belong (undef, when taken from the sign before)
                    attributes

=item Returns  the id of the new sign

=back

=cut

    sub new_sign {
        my ( $self, $sign, $after, $before, $line_id, @attribute_values ) = @_;

        if ( !$after ) {
            if ( !@attribute_values ) {
                return ( undef, SQE_Error::NO_ATTRIBUTES );
            }
            elsif ( !$before ) {
                return ( undef, SQE_Error::NO_POSITION );
            }
        }

        # First create a new sign_id
        my $sth = $self->prepare_cached(SQE_DBI_queries::NEW_SIGN);
        $sth->execute;
        my $new_sign_id = $self->{mysql_insertid};
        $sth->finish;

        $sth = $self->prepare_cached(SQE_DBI_queries::NEW_SIGN_CHAR);
        $sth->execute( $new_sign_id, 0, $sign );
        my $new_sign_char_id = $self->{mysql_insertid};
        $sth->finish;

        if (@attribute_values) {
            for my $value (@attribute_values) {
                if ( ref($value) eq 'ARRAY' ) {
                    $self->set_sign_char_attribute( $new_sign_char_id,
                        @$value );
                }
                else {
                    $self->set_sign_char_attribute( $new_sign_char_id, $value );
                }
            }
        }
        elsif ($after) {
            my ($previous_sign_char_id) =
              $self
              ->get_first_row_as_array( SQE_DBI_queries::GET_MAIN_SIGN_CHAR,
                $after, $self->scroll_version_group_id );
            $sth = $self->prepare_cached(SQE_DBI_queries::GET_ALL_ATTRIBUTES);
            $sth->execute( $previous_sign_char_id,
                $self->scroll_version_group_id );
            while ( my @data = $sth->fetchrow_array ) {
                $self->set_sign_char_attribute( $new_sign_char_id,
                    @data[ 2 .. 4 ] );
            }
            $sth->finish;
        }

        # Insert into sign stream

        # We know the sign after which the new sign should appear
        if ($after) {
            if ( !$line_id ) {
                $line_id = $self->get_line_id_for_sign($after);
            }
            if ($before) {

                # We know also the sign before the new sign should appear

# First find the position in stream record which connect the $after with $before
# and remove it
                my ($position_in_stream_id) =
                  $self->get_first_row_as_array
                  ( SQE_DBI_queries::GET_POSITION_IN_STREAM_ID,
                    $after, $before, $self->scroll_version_group_id );
                $self->remove_data( 'position_in_stream',
                    $position_in_stream_id );

   # Create a position in stream record which connects the new sign with $before
                $position_in_stream_id =
                  $self->set_new_data_to_owner( 'position_in_stream',
                    $new_sign_id, $before );

    # Create a position in stream record which connects $after with the new sign
                $position_in_stream_id =
                  $self->set_new_data_to_owner( 'position_in_stream', $after,
                    $new_sign_id );
            }
            else {
# We do not know the sign before the new sign should appear
#We need all records of position in stream which connect the $after with aóther signs
#as next sign
                $sth =
                  $self
                  ->prepare_cached(SQE_DBI_queries::GET_POSITION_IN_STREAM_DATA
                  );
                my ( $prev_pis_id, $prev_next_sign_id );
                $sth->execute( $after, $self->scroll_version_group_id );
                $sth->bind_columns( \$prev_pis_id, \$prev_next_sign_id );

                # Split every connection to $after -> new_sign -> next_sign
                while ( $sth->fetch ) {

                    # Remove the old position in stream record
                    $self->remove_data( 'position_in_stream', $prev_pis_id );

    # Create a position in stream record which connects $after with the new sign
                    my $position_in_stream_id =
                      $self->set_new_data_to_owner( 'position_in_stream',
                        $after, $new_sign_id );

# Create a position in stream record which connects the new sign with rthe next sign
                    $position_in_stream_id =
                      $self->set_new_data_to_owner( 'position_in_stream',
                        $new_sign_id, $prev_next_sign_id );
                }
            }
        }
        else {
            # We only konw the sign before the new sign should appear

            if ( !$line_id ) {
                $line_id = (
                    $self->get_first_row_as_array
                      ( SQE_DBI_queries::GET_LINE_TO_SIGN_FOR_SCROLL_VERSION_GROUP,
                        $before,
                        $self->scroll_version_group_id
                      )
                )[1];
            }

#We need all records of position in stream which connect the $after with aóther signs
#as next sign
            $sth = $self->prepare_cached
              (SQE_DBI_queries::GET_PREV_POSITION_IN_STREAM_DATA);
            my ( $prev_pis_id, $prev_sign_id );
            $sth->execute( $before, $self->scroll_version_group_id );
            $sth->bind_columns( \$prev_pis_id, \$prev_sign_id );

            # Split every connection to previous sign -> new sign -> next sign
            while ( $sth->fetch ) {

                # Remove the old position in stream record
                $self->remove_data( 'position_in_stream', $prev_pis_id );

    # Create a position in stream record which connects $after with the new sign
                my $position_in_stream_id =
                  $self->set_new_data_to_owner( 'position_in_stream',
                    $prev_sign_id, $new_sign_id );

# Create a position in stream record which connects the new sign with rthe next sign
                $position_in_stream_id =
                  $self->set_new_data_to_owner( 'position_in_stream',
                    $new_sign_id, $before );
            }
        }

        $self->set_new_data_to_owner( 'line_to_sign', $new_sign_id, $line_id );

        return $new_sign_id;

    }



=head3 new_line_id()

Creates a new line id

=over 1

=item Parameters: none

=item Returns id of line

=back

=cut
    sub new_line_id {
        my ($self) = @_;
        my $sth=$self->prepare_cached(SQE_DBI_queries::NEW_LINE);
        $sth->execute;
        my $new_line_id= $self->{mysql_insertid};
        $sth->finish;
        return $new_line_id
    }

    sub new_col_id {
        my ($self) = @_;
        my $sth=$self->prepare_cached(SQE_DBI_queries::NEW_LINE);
        $sth->execute;
        my $new_col_id= $self->{mysql_insertid};
        $sth->finish;
        return $new_col_id
    }



=head3 new_line($after, $before, $line_id, $new_line_name)

Creates a new line either after or before a given sign

=over 1

=item Parameters: id of sign, after which the line break should be set (or undef)
                  id of sign, before which the line break should be set (or undef)
                  id of the line of the sign (optional)
                  name of the new line (optional; if not set, lines are automatocally renumbered)


=item Returns   the sign ids of the break and all new line_names with their ids

=back

=cut
    sub new_line {
        my ($self, $after, $before, $new_line_name, $new_col_name) =@_;
        my ($new_first_sign_id, $new_second_sign_id, $new_line_id, $new_col_id);
        my $sign_id = $after ? $after : $before;
        my @attribute_end=(9,11);
        my @attribute_start=(9,10);
        my $sth = $self->prepare_cached(SQE_DBI_queries::GET_REF_DATA);
        my ($scroll_id, $old_col_id, $line_id) =
            ($self->get_first_row_as_array(SQE_DBI_queries::GET_REF_DATA, $sign_id, $self->scroll_version_group_id))[0,2,4];

        if ($new_col_name) {
           $new_col_id = $self->new_col_id;
            $self->set_new_data_to_owner('scroll_to_col', $scroll_id, $new_col_id);
            $self->set_col_name($new_col_id, $new_col_name);
            push @attribute_end, 13;
            push @attribute_start, 12;
        } else {
            $new_col_id = $old_col_id;
        }

        if ($after) {
            $line_id = $self->get_line_id_for_sign($after) if not $line_id;
            $new_first_sign_id=$self->new_sign('', $after, undef, $line_id, @attribute_end);
            $new_line_id = $self->new_line_id;
            $new_second_sign_id=$self->new_sign('', $new_first_sign_id, undef, $line_id, @attribute_start);
            for my $next_sign_id ($self->get_following_sign_ids_in_line($new_second_sign_id)) {
                $self->replace_data('line_to_sign', [$next_sign_id, $line_id],  [$next_sign_id, $new_line_id]);
            }
            $self->replace_data('line_to_sign',  [$new_second_sign_id, $line_id],  [$new_second_sign_id, $new_line_id]);

        } elsif ($before) {
            $line_id = $self->get_line_id_for_sign($before) if not $line_id;
            $new_second_sign_id=$self->new_sign('', undef, $before, $line_id, @attribute_start);
            $line_id = $self->new_line_id;
            $new_first_sign_id=$self->new_sign('', undef, $new_second_sign_id, $new_line_id, @attribute_end);
            for my $next_sign_id ($self->get_following_sign_ids_in_line($before)) {
                $self->set_new_data_to_owner('line_to_sign', $next_sign_id, $new_line_id);
            }
        }

        if (!$new_col_name) {
            $self->set_new_data_to_owner('col_to_line', $new_col_id, $new_line_id);
        } else {
            $self->set_new_data_to_owner('col_to_line', $old_col_id, $new_line_id);

        }


        my $out_text = "{\"new_line_end_id\":$new_first_sign_id,\"new_line_start_id\":$new_second_sign_id,\"new_line_name\":[";

        if ($new_line_name) {
            $self->set_line_name($new_line_id, $new_line_name);
            $out_text.="{\"line_id\":$new_line_id,\"line_name\":\"$new_line_name\"}";

        } else {
            my $sth=$self->prepare_cached(SQE_DBI_queries::GET_NEXT_LINE_IN_SAME_COL);
            $sth->execute($new_line_id, $self->scroll_version_group_id);
            my @data;
            my $run=0;
            while (@data = $sth->fetchrow_array) {
                $new_line_name=$data[1];
                $self->set_line_name($new_line_id, $new_line_name);
                $out_text.="{\"line_id\":$new_line_id,\"line_name\":\"$new_line_name\"},";
                $sth->execute($data[0], $self->scroll_version_group_id);
                $run++;
                if ($new_col_name) {
                    $self->replace_data('col_to_line', [ $old_col_id, $new_line_id ], [ $new_col_id, $new_line_id ]);
                }
                $new_line_id=$data[0];
                $new_line_name=$data[1];
            }
            if ($run>0) {
                $new_line_name =~
                    s/(.*?)([0-9]+)([^0-9]*?)/$1 . ($2+1) . $3/oe;
                $self->set_line_name($new_line_id, $new_line_name);
                $out_text.="{\"line_id\":$new_line_id,\"line_name\":\"$new_line_name\"}";
                if ($new_col_id) {
                    $self->replace_data('col_to_line', [ $old_col_id, $new_line_id ], [ $new_col_id, $new_line_id ]);
                }

            } else {
                $out_text.=s/,$//goe;
            }
        }

        if ($new_col_name) {
            $self->set_new_data_to_owner('col_to_line', $new_col_id, $new_line_id);
            return $out_text . "],\"new_col_id\":$new_col_id,\"new_col_name\":\"$new_col_name\"}";
        } else {
            return $out_text . ']}';
        }
    }



    sub set_line {
        my ($self, $line_id, $new_line_name) = @_;
        my $sth = $self->prepare_cached(SQE_DBI_queries::NEW_LINE);
        $sth->execute();
        my $new_line_id = $self->{mysql_insertid};

    }

=head3 new_sign_char_variant($sign_id, $sign, $as_variant)

Creates a new sign char variant to the sign referenced by sign id with $sign as char.

If as_variant = 0 then the new variant will be set as the main sign_char for this sign and the old main one as variant

=over 1

=item Parameters:   id of the sign to which the new variant should be set
                    sign (char) of the variant
                    variant flag

=item Returns nothing

=back

=cut

    sub new_sign_char_variant {
        my ( $self, $sign_id, $sign, $as_variant ) = @_;

        # Define $as_main as false if undefined
        $as_variant = $as_variant ? 1 : 0;

        # Retrieve the data of current main sign char for the sign
        my ( $main_sign_char_id, $main_sign_id, $main_is_variant, $main_sign )
          = $self->get_first_row_as_array( SQE_DBI_queries::GET_MAIN_SIGN_CHAR,
            $sign_id, $self->scroll_version_group_id );

# Now create a new sign char with these data, but set the variant flag as demanded
        $self->clone_sign_char( $main_sign_char_id, $sign_id, $as_variant,
            $sign );

# If the new one is set also as a main char sign, we have to set the old one as to be a variant
        if ( !$as_variant ) {

            $self->set_sign_char_variant_status( $main_sign_char_id, 1 );

        }

    }

=head2 Retrieve Data

=cut

    sub get_ids_from_parent {
        my ( $self, $table, @data ) = @_;
        my $sth =
          $self->prepare_cached( $data_tables->{$table}->{FROM_PARENTS} );
        $sth->execute( @data, $self->scroll_version_group_id );
        my $res = $sth->fetchall_arrayref;
        $sth->finish;
        return $res;
    }

    sub get_id_from_parent {
        my ( $self, $table, @data ) = @_;
        my $res = $self->get_ids_from_parent( $table, @data );
        if ( $res->[0] ) {
            return $res->[0]->[0];
        }
        return undef;
    }

=head3 get_roi_data($sign_char_roi_id, $as_text)

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
        my ( $self, $sign_char_roi_id, $as_text ) = @_;

        if ($as_text) {
            return
              $self->get_first_row_as_array( SQE_DBI_queries::GET_ROI_DATA_TEXT,
                $sign_char_roi_id );
        }
        else {
            return
              $self
              ->get_first_row_as_array( SQE_DBI_queries::GET_ROI_DATA_GEOJSON,
                $sign_char_roi_id );
        }
    }

=head3 print_formatted_text($query, $id, $format, $start_id)

Retrieves a chunk of text, formats, and print it out.

=over 1

=item Parameters:

=item Returns

=back

=cut

    sub print_formatted_text {
        my ( $self, $query, $id, $format, $start_id ) = @_;
        my $sth     = $self->prepare_cached($query);
        my $sth_out = $self->prepare_cached(SQE_DBI_queries::GET_REF_DATA);
        my $signs   = {};

        if ( $sth->execute( $id, $self->scroll_version_group_id ) ) {
            my SQE_sign $sign     = SQE_sign->new( $sth->fetchrow_arrayref );
            my SQE_sign $old_sign = $sign;

            while ( my $data_ref = $sth->fetchrow_arrayref ) {
                my $sign = $old_sign->add_data($data_ref);
                if ( $sign != $old_sign ) {
                    $signs->{ $old_sign->{sign_id} } = $old_sign;
                    $old_sign = $sign;
                }

            }
            $signs->{ $old_sign->{sign_id} } = $old_sign;
            $format->print( $signs, $start_id, $sth_out,
                $self->scroll_version_group_id );
        }
        $sth->finish;
        $sth_out->finish;
    }





=head3 get_next_signs($sign_id)

Retrieves the sign

=over 1

=item Parameters:

=item Returns

=back

=cut
    sub get_next_signs {
        my ($self, $sign_id) = @_;
        my $sth=$self->prepare_cached(SQE_DBI_queries::GET_NEXT_SIGN_IDS_IN_LINE);
        $sth->execute($sign_id);
        my $erg= $sth->fetchall_arrayref();
        $sth->finish;
        return $erg;
    }

    sub get_next_sign_id {
        my ($self, $sign_id) = @_;
        return ($self->get_next_signs())->[0]->[0];
    }

    sub get_next_line_data {
        my ($self, $line_id, $col_id) = @_;


    }


    sub get_following_sign_ids_in_line {
        my ($self, $start_sign_id) = @_;
        my %found_ids;
        my @to_process=($start_sign_id);
        my ($next_sign_id);
        my $sth = $self->prepare_cached(SQE_DBI_queries::GET_NEXT_SIGN_IDS_IN_LINE);
        while (@to_process) {
            while (my $pr = pop @to_process) {

                $sth->execute($pr, $self->scroll_version_group_id);
                $sth->bind_columns(\$next_sign_id);
                while ($sth->fetch) {
                    if (!$found_ids{$next_sign_id}) {
                        $found_ids{$next_sign_id} = 1;
                        push @to_process, $next_sign_id
                    }

                }

            }
        }
        $sth->finish;
        return keys %found_ids;
    }

=head3 get_text_of_fragment($frag_id, $class)

Retrieves the text of a fragment and print it out formatted according the given format class


=over 1

=item Parameters: id of the fragment, class of the format

=item Returns

=back

=cut

    sub get_text_of_fragment {
        my ( $self, $frag_id, $class ) = @_;
        my @start =
          $self
          ->get_first_row_as_array( SQE_DBI_queries::GET_FIRST_SIGN_IN_COLUMN,
            $frag_id, $self->scroll_version_group_id );
        return ( undef, SQE_Error::FRAGMENT_NOT_FOUND ) if @start == 0;
        $self->print_formatted_text
          ( SQE_DBI_queries::GET_ALL_SIGNS_IN_FRAGMENT_QUERY,
            $frag_id, $class, $start[0] );
    }

=head3 get_line_id_for_sign($sign_id)

Retrieves the line id for the given sign and curretn scrollversion

=over 1

=item Parameters: id of sign

=item Returns id of line

=back

=cut
    sub get_line_id_for_sign {
        my ($self, $sign_id) = @_;
        return ($self->get_first_row_as_array
                ( SQE_DBI_queries::GET_LINE_TO_SIGN_FOR_SCROLL_VERSION_GROUP,
                    $sign_id,
                    $self->scroll_version_group_id
                )
        )[1];
    }

=head3 get_text_of_line($line_id, $class)

Retrieves the text of a line and print it out formatted according the given format class


=over 1

=item Parameters: id of the line, class of the format

=item Returns

=back

=cut

    sub get_text_of_line {
        my ( $self, $line_id, $class ) = @_;
        my @start =
          $self
          ->get_first_row_as_array( SQE_DBI_queries::GET_FIRST_SIGN_IN_LINE,
            $line_id, $self->scroll_version_group_id );
        return ( undef, SQE_Error::LINE_NOT_FOUND ) if @start == 0;
        $self
          ->print_formatted_text( SQE_DBI_queries::GET_ALL_SIGNS_IN_LINE_QUERY,
            $line_id, $class, $start[0] );
    }

=head3 get_roi_shape_id($roi_shape)

Returns the id of a roi_shape record  which contain the given data.

If the record does not exist, it will be created autoamtically.


=over 1

=item Parameters: roi_shape as GEO_JSON

=item Returns id of roi_shape

=back

=cut

    sub get_roi_shape_id {
        my ( $self, $roi_shape ) = @_;
        my ($roi_shape_id) =
          $self->set_new_data( SQE_DBI_queries::GET_ROI_SHAPE_ID,
            SQE_DBI_queries::NEW_ROI_SHAPE_FROM_WKT, $roi_shape );
        return $roi_shape_id;
    }

=head3 get_roi_position_id($roi_position)

Returns the id of a roi_position record  which
contain the given data.

If the record does not exist, it will be created automatically.


=over 1

=item Parameters: roi_position JSON

=item Returns id of roi_position

=back

=cut

    sub get_roi_position_id {
        my ( $self, $roi_position ) = @_;
        my ($roi_position_id) =
          $self->set_new_data( SQE_DBI_queries::GET_ROI_POSITION_ID,
            SQE_DBI_queries::NEW_ROI_POSITION,
            $roi_position
          );
        return $roi_position_id;
    }

=head3 get_sign_char_commentary($sign_char_commentary_id)

Retrieves the text of the referrenced sign char commentary

=over 1

=item Parameters: id of sign char commentary

=item Returns commentary text

=back

=cut

    sub get_sign_char_commentary {
        my ( $self, $sign_char_commentary_id ) = @_;
        return (
            $self->get_first_row_as_array(
                $data_tables->{sign_char_commentary}->{SIMPLE_GET_QUERY},
                $sign_char_commentary_id
            )
        )[3];
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

    #Returns the current SQE-session-id
    sub session_id {
        my ($self) = @_;
        return $self->session->session_id;
    }

    #Sets a new session_id
    #Paramater:
    #    session_id
    sub set_session_id {
        my ( $self, $session_id ) = @_;
        $self->session->set_session_id($session_id);

    }

    #@returns Session
    sub session {
        return $_[0]->{private_SQE_DBI_data}->{SESSION};
    }

=head3 set_session($session)

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
        return $_[0]->{private_SQE_DBI_data}->{SESSION}->{USER_ID};
    }

    # Returns the current version
    #@deprecated
    sub scrollversion {
        return $_[0]->{private_SQE_DBI_data}->{SESSION}->{SCROLL_VERSION_ID};
    }

    # Returns the current action_log_id
    sub action_log_id {
        return $_[0]->{private_SQE_DBI_data}->{main_action_id};
    }

=head2 Deprecated

=cut

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

        REMOVE_USER => <<'MYSQL',
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

        SIGN_CHAR_JOIN         => 'JOIN sign_char USING (sign_char_id)',
        LINE_TO_SIGN_JOIN      => 'JOIN line_to_sign USING (sign_id)',
        COL_TO_LINE_JOIN       => 'JOIN col_to_line USING (line_id)',
        SCROLL_TO_COL_JOIN     => 'JOIN scroll_to_col USING (col_id)',
        ARTEFACT_POSITION_JOIN => 'JOIN artefact_position USING (artefact_id)',

        NEW_SCROLL_VERSION => <<'MYSQL',
INSERT INTO scroll_version
(user_id, scroll_id, version) values (?,?,?)
MYSQL

    };

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
#@deprecated
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

    #@deprecated
    sub change_value {
        my $self  = shift;
        my $table = shift;
        my $id    = shift;
        return ( undef, SQE_Error::QWB_RECORD ) if $self->scrollversion == 1;
        $self->start_logged_action;
        my ( $new_id, $error_ref ) = $self->_add_value( $table, $id, @_ );
        if ( defined $new_id ) {
            if ( $id != $new_id ) {
                $self->remove_data( $table, $id );
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
#@deprecated
    sub remove_entry {
        my ( $self, $table, $id ) = @_;
        return ( undef, SQE_Error::QWB_RECORD ) if $self->scrollversion == 1;
        $self->start_logged_action;
        my $result = $self->remove_data( $table, $id );
        $self->stop_logged_action;
        if ( $result > 0 ) {
            return $result;
        }
        else {
            return ( undef, SQE_Error::RECORD_NOT_FOUND );
        }
    }

=head3 _set_scroll_version($scroll_version_id, $scroll_version_group_id)

Sets the scroll version and scroll version group id into the internal hash

=over 1

=item Parameters: scroll_version_id, scroll_version_group_id

=item Returns

=back

=cut

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

    #@deprecated
    sub _set_scroll_version {
        my ( $self, $scroll_version_id, $scroll_version_group_id ) = @_;
        $self->$self->{private_SQE_DBI_data}->{SESSION}->{SCROLL_VERSION_ID} =
          $scroll_version_id;
        $self->{private_SQE_DBI_data}->{SESSION}->{SCROLL_VERSION_GROUP_ID} =
          $scroll_version_group_id;
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
    #@deprecated
    sub prepare_sqe_with_version_ids {
        my ( $self, $query ) = @_;
        $query =~
          s/_svgi_/$self->{private_SQE_DBI_data}->{SCROLL_VERSION_GROUP_ID}/goe;
        return bless $self->prepare_cached( $query, @_ ), 'SQE_st';
    }

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
#@deprecated
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
        $query =~ s/_scrollversion_/$self->scrollversion/oe;
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
                $self->add_owner( $table, $insert_id );
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
                $self->add_owner( $table, $insert_id );
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

# Internal function to add the current user/version to a table for a whole scroll or part of it
# The adding is not logged, thus to rewind it, one must use remove_user manually
#
# Parameters
#   Name of the data table
#   Array ref with joins to connect the table data with the scroll or part of it
#   Query fragment giving the data (of the part) of scroll
#   The scrollversion of the source
#@deprecated
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
#@deprecated
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

    #@deprecated

# Adds the given column/fragment from a user/version with all its data to the current user/version
# If the user_id of the source is not given, the default QWB text (user_id=0, version =0) is taken
#
# Note: the col/fragment is taken out from its original scroll!
#
# Parameters
#   Id of the column/fragment
#   id of the user_id of the old owner (optional)
#   version from the old user/version (optional)
#@deprecated
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
#@deprecated
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
#@deprecated
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

}

############################################################################################
#   SQE_st
############################################################################################

# A child of DBI::st which adds function for logged actions
{

    package SQE_st;
    use parent -norequire, 'DBI::st';

# Tells the statementhandler which kind of action and table the following executes affect
# Parameters
#   the action ('ADD' or 'DELETE')
#   the affected table
    sub set_action {
        my ( $self, $action_art, $table ) = @_;
        $self->{private_sth}->{ACTION_ART} = $action_art;
        $self->{private_sth}->{TABLE}      = $table;
        $self->{private_sth}->{STH} =
          $self->{Database}->prepare_cached(SQE_DBI_queries::NEW_SINGLE_ACTION);
    }

    # Execute the statement and logs it
    #
    sub logged_execute {
        my ( $self, $id, @data ) = @_;
        my $dbh = $self->{Database};
        my $result = $self->execute( $id, @data );
        $self->{private_sth}->{STH}->execute(
            $dbh->action_log_id,
            $self->{private_sth}->{ACTION_ART},
            $self->{private_sth}->{TABLE}, $id
        ) if $result > 0;
        return $result;

    }

    # Overwriting normal finish
    sub finish {
        my $self = shift;
        $self->{private_sth}->{STH}->finish if $self->{private_sth}->{STH};
        $self->SUPER::finish;
    }
}

1;

