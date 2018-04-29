package SQE_DBI_queries;
use strict;
use warnings FATAL => 'all';
use Package::Constants;

use constant {

# Predefined common parts of a query to get the sign data from a sign stream
# Should be combined for a query in the following way
# SIGN_QUERY_START
#    . GET_XXX_FROM
#    . SIGN_JOIN_PART
#    . GET_XXX_WHERE
#    . SIGN_QUERY_END
# while XXX stands for the area of text retrieved (LINE or FRAGMENT for a fragment or column)

# The first part of a query to get the sign data from a sign stream
# Defines the fields retrieved
# Should be followed by a GET_XXXX_FROM part according to the text part looked for
    SIGN_QUERY_START => <<'MYSQL_FRAGMENT',
    SELECT
  /* 0 */   position_in_stream.next_sign_id,
  /* 1 */   position_in_stream.sign_id,
  /* 2 */   sign_char.sign_char_id,
  /* 3 */   sign_char.sign,
  /* 4 */   is_variant,
  /* 5 */   attribute.attribute_id,
  /* 6 */   attribute_value.attribute_value_id,
  /* 7 */   attribute.name,
  /* 8 */   attribute_value.string_value,
  /* 9 */   attribute_numeric.value,
  /* 10 */  line_to_sign.line_id

MYSQL_FRAGMENT

# Defines the common joins of a query to get the sign data from a sign stream
# Should follow a GET_XXXX_FROM part according to the text part looked for
# Should be followed by a GET_XXXX_WHERE part according to the text part looked for
    SIGN_JOIN_PART => <<'MYSQL_FRAGMENT',
        JOIN position_in_stream USING (sign_id)
        JOIN position_in_stream_owner USING (position_in_stream_id)
        JOIN scroll_version as sva ON sva.scroll_version_id=position_in_stream_owner.scroll_version_id

        JOIN sign_char USING (sign_id)
        JOIN sign_char_attribute USING (sign_char_id)
        JOIN sign_char_attribute_owner USING (sign_char_attribute_id)
        JOIN scroll_version as svb on svb.scroll_version_id=sign_char_attribute_owner.scroll_version_id

        LEFT JOIN attribute_numeric USING (sign_char_attribute_id)

        JOIN attribute_value USING (attribute_value_id)
        JOIN attribute USING (attribute_id)

MYSQL_FRAGMENT

# Defines the where part of a query to get the sign data from a sign stream for the scrollverion
# Should follow a GET_XXX_WHERE part according to the text part looked for
    SIGN_QUERY_SCROLLVERSION_PART => <<'MYSQL_FRAGMENT',
        AND sva.scroll_version_group_id = svb.scroll_version_group_id
        AND svb.scroll_version_group_id= ?

MYSQL_FRAGMENT

# The last part of a query to get the sign data from a sign stream
# Should follow a GET_QUERY_SCROLLVERSION part according to the text part looked for
    SIGN_QUERY_END => <<'MYSQL_FRAGMENT',
        ORDER BY sign_char.sign_char_id,
                 sign_char.is_variant,
                 attribute.attribute_id,
                 sign_char_attribute.`sequence`,
                 sign_char_attribute.attribute_value_id
MYSQL_FRAGMENT

   # Predefined special parts of a query to get the sign data from a sign stream

    # Lines

    # Defines the GET_XXX_FROM part for a line
    GET_LINE_FROM => <<'MYSQL_FRAGMENT',
        FROM line_to_sign
MYSQL_FRAGMENT

    # Defines the GET_XXX_WHERE part for a line
    GET_LINE_WHERE => <<'MYSQL_FRAGMENT',
        WHERE line_id =?

MYSQL_FRAGMENT

    # Fragments or columns

    # Defines the GET_XXX_FROM part for a fragment or column
    GET_FRAGMENT_FROM => <<'MYSQL_FRAGMENT',
        FROM col_to_line
        JOIN line_to_sign USING (line_id)

MYSQL_FRAGMENT

    # Defines the GET_XXX_WHERE part for a line
    GET_FRAGMENT_WHERE => <<'MYSQL_FRAGMENT',
        WHERE col_id =?

MYSQL_FRAGMENT

    GET_REF_DATA => << 'MYSQL',
    SELECT  scroll_data.scroll_id,
            scroll_data.name,
            col_data.col_id,
            col_data.name,
            line_data.line_id,
            line_data.name

    FROM line_to_sign

    JOIN line_data USING (line_id)
    JOIN line_data_owner USING (line_data_id)
    JOIN scroll_version as line_sv ON line_data_owner.scroll_version_id = line_sv.scroll_version_id

    JOIN col_to_line USING (line_id)
    JOIN col_data USING (col_id)
    JOIN col_data_owner USING (col_data_id)
    JOIN scroll_version as col_sv ON col_data_owner.scroll_version_id = col_sv.scroll_version_id

    JOIN scroll_to_col USING (col_id)
    JOIN scroll_data USING (scroll_id)
    JOIN scroll_data_owner USING (scroll_data_id)
    JOIN scroll_version as scr_sv ON scroll_data_owner.scroll_version_id = scr_sv.scroll_version_id

    WHERE sign_id = ?
      AND scr_sv.scroll_version_group_id = col_sv.scroll_version_group_id
      AND col_sv.scroll_version_group_id = line_sv.scroll_version_group_id
      AND line_sv.scroll_version_group_id = ?
MYSQL

    CHECK_SCROLLVERSION => << 'MYSQL',
SELECT user_id
FROM scroll_version
WHERE scroll_version_id = ?
MYSQL

    SET_SESSION_SCROLLVERSION => << 'MYSQL',
UPDATE sqe_session
SET scroll_version_id = ?
WHERE sqe_session_id = ?
MYSQL

    GET_ALL_VALUES => << 'MYSQL',
    SELECT _table_.*
    FROM _table_
     JOIN _table__owner USING (_table__id)
    WHERE _table__id = ?
    AND scroll_version_id = _scrollversion_
MYSQL

    GET_SIGN_CHAR_READING_DATA_IDS => << 'MYSQL',
  SELECT sign_char_reading_data_id
      FROM sign_char_reading_data
      JOIN sign_char_reading_data_owner USING (sign_char_reading_data_id)
      WHERE sign_char_id=?
          AND scroll_version_id= _scrollversion_
    
MYSQL

    GET_SCROLLVERSION => <<'MYSQL',
SELECT  scroll_version_id,
    scroll_version_group_id
FROM scroll_version
WHERE user_name like ?  AND scroll_version_id = ?;
MYSQL

    GET_ALL_SIGNS_IN_FRAGMENT => <<'MYSQL',
SELECT
    /* 0 */   position_in_stream.next_sign_id,
    /* 1 */   position_in_stream.sign_id,
    /* 2 */   sign_char.sign, /* 0 */
    /* 3 */   sign_char.sign_type_id,
    /* 4 */   sign_type.type,
    /* 5 */   sign_char.width,
    /* 6 */   sign_char.might_be_wider,
    /* 7 */   sign_char_reading_data.readability,
    /* 8 */   sign_char_reading_data.is_retraced,
    /* 9 */   sign_char_reading_data.is_reconstructed,
    /* 10 */  sign_char_reading_data.correction,
    /* 11 */  sign_char.is_variant,
    /* 12 */  sign_char_reading_data.sign_char_reading_data_id,
    /* 13 */  sign_char.sign_char_id,
    /* 14 */  if(sign_char_reading_data.sign_char_reading_data_id is null
                 or sign_char_reading_data_owner.scroll_version_id = _scrollversion_ , 0,
                 1) as var
FROM col_to_line
    JOIN line_to_sign USING (line_id)
    JOIN position_in_stream USING (sign_id)
    JOIN position_in_stream_owner USING (position_in_stream_id)
    JOIN sign_char USING (sign_id)
    JOIN sign_char_owner USING (sign_char_id)
    JOIN sign_type USING(sign_type_id)
    LEFT JOIN sign_char_reading_data USING (sign_char_id)
    LEFT JOIN sign_char_reading_data_owner USING (sign_char_reading_data_id)
WHERE col_id =?
      AND sign_char_owner.scroll_version_id = _scrollversion_
      AND position_in_stream_owner.scroll_version_id= _scrollversion_
ORDER BY sign_char.sign_char_id, var
MYSQL

    GET_ALL_SIGNS_IN_LINE => <<'MYSQL',
SELECT
    /* 0 */   position_in_stream.next_sign_id,
    /* 1 */   position_in_stream.sign_id,
    /* 2 */   sign_char.sign, /* 0 */
    /* 3 */   sign_char.sign_type_id,
    /* 4 */   sign_type.type,
    /* 5 */   sign_char.width,
    /* 6 */   sign_char.might_be_wider,
    /* 7 */   sign_char_reading_data.readability,
    /* 8 */   sign_char_reading_data.is_retraced,
    /* 9 */   sign_char_reading_data.is_reconstructed,
    /* 10 */  sign_char_reading_data.correction,
    /* 11 */  sign_char.is_variant,
    /* 12 */  sign_char_reading_data.sign_char_reading_data_id,
    /* 13 */  sign_char.sign_char_id,
    /* 14 */     if(sign_char_reading_data.sign_char_reading_data_id is null
                    or sign_char_reading_data_owner.scroll_version_id = _scrollversion_ , 0,
                    1) as var

FROM line_to_sign
    JOIN position_in_stream USING (sign_id)
    JOIN position_in_stream_owner USING (position_in_stream_id)
    JOIN sign_char USING (sign_id)
    JOIN sign_char_owner USING (sign_char_id)
    JOIN sign_type USING(sign_type_id)
    LEFT JOIN sign_char_reading_data USING (sign_char_id)
    LEFT JOIN sign_char_reading_data_owner USING (sign_char_reading_data_id)
WHERE line_id =?
      AND sign_char_owner.scroll_version_id = _scrollversion_
      AND position_in_stream_owner.scroll_version_id= _scrollversion_
ORDER BY sign_char.sign_char_id, var

MYSQL

    NEW_SCROLL_VERSION_GROUP => <<'MYSQL',
      INSERT INTO scroll_version_group
        (scroll_id)
      SELECT scroll_id
      FROM scroll_version
        JOIN scroll_version_group USING (scroll_version_group_id)
      WHERE scroll_version_id = ?
MYSQL

    CREATE_SCROLL_VERSION_GROUP_ADMIN => << 'MYSQL',
      INSERT INTO  scroll_version_group_admin
        (scroll_version_group_id, user_id)
        values (?,?)
MYSQL

    NEW_SCROLL_VERSION => <<'MYSQL',
      INSERT INTO scroll_version
        (user_id, scroll_version_group_id)
        values (?,?)
MYSQL


    GET_OWNER_TABLE_NAMES => <<'MYSQL',
      SELECT TABLE_NAME
      FROM information_schema.TABLES
      WHERE TABLE_NAME like '%_owner'
MYSQL

    DELETE_SCROLLVERSION_FROM_ACTIONS=> <<'MYSQL',
      DELETE FROM main_action
          WHERE scroll_version_id = ?
MYSQL

    DELETE_SCROLLVERSION => <<'MYSQL',
      DELETE FROM scroll_version
          WHERE scroll_version_id = ?
MYSQL

    DELETE_EMPTY_SCROLLVERSION_GROUPS => <<'MYSQL',
      DELETE scroll_version_group
          FROM scroll_version_group
          LEFT JOIN scroll_version USING (scroll_version_group_id)
          WHERE scroll_version_id is null
MYSQL

    CHANGE_SCROLL_NAME => << 'MYSQL',
      UPDATE
MYSQL

    NEW_SINGLE_ACTION => <<'MYSQL',
      INSERT INTO single_action
      (main_action_id, action, `table`, id_in_table)
      VALUES (?, ?, ?, ?)
MYSQL


    GET_SIGN_CHAR_ATTRIBUTE => << 'MYSQL',
      SELECT sign_char_attribute_id, scroll_version_id
      FROM sign_char_attribute
      LEFT JOIN sign_char_attribute_owner USING (sign_char_attribute_id)
      WHERE sign_char_id = ?
        AND attribute_value_id = ?
          AND sequence = ?
MYSQL

    GET_SIGN_CHAR_ATTRIBUTE_NUMERIC => << 'MYSQL',
      SELECT sign_char_attribute_id, scroll_version_id
      FROM sign_char_attribute
      JOIN sign_char_attribute_owner USING (sign_char_attribute_id)
      JOIN attribute_numeric USING (sign_char_attribute_id)
      WHERE sign_char_id = ?
      AND attribute_value_id = ?
          AND sequence = ?
          AND value = ?
MYSQL

    GET_ALL_SIGN_CHAR_ATTRIBUTES_FOR_ATTRIBUTE => << 'MYSQL',
      SELECT sign_char_attribute_id
      FROM sign_char_attribute
        JOIN sign_char_attribute_owner USING (sign_char_attribute_id)
        JOIN attribute_value as a USING (attribute_value_id)
        JOIN attribute_value as b USING (attribute_id)
      WHERE sign_char_id = ?
        AND scroll_version_id = ?
        AND b.attribute_value_id = ?
MYSQL


    NEW_SIGN_CHAR_ATTRIBUTE => << 'MYSQL',
      INSERT INTO sign_char_attribute
      (sign_char_id, attribute_value_id, sequence)
          VALUES (?,?,?)
MYSQL

    NEW_NUMERIC_VALUE => << 'MYSQL',
      INSERT INTO attribute_numeric
      (sign_char_attribute_id, value)
      VALUES (?,?)
MYSQL


    ADD_SIGN_CHAR_ATTRIBUTE => << 'MYSQL',
      INSERT INTO sign_char_attribute_owner
      (sign_char_attribute_id, scroll_version_id)
          VALUES (?,?)

MYSQL

    NEW_MAIN_ACTION => <<'MYSQL',
      INSERT INTO main_action
        (scroll_version_id) VALUES (?)
MYSQL




    CLONE_SCROLL_VERSION => <<'MYSQL_FRAGMENT',
    INSERT INTO *OWNER* (*TABLE*_id, scroll_version_id)
    SELECT *TABLE*_id, *SVID* FROM *OWNER*
    WHERE scroll_version_id = *OLDSVID*
MYSQL_FRAGMENT


    DELETE_SCROLLVERSION_FROM_OWNERS => <<'MYSQL_FRAGMENT',
    DELETE FROM *OWNER*
    WHERE scroll_version_id = *SVID*
MYSQL_FRAGMENT

};

use constant {

# Predefined queries to get the sign data from a sign stream
# Those queries expect two parameters - the id of the area, the text is retrieved from
# meaning a line or column id
# and the scrollversion_group_id

    # Predefined querie to get the sign data from a sign stream from a column
    GET_ALL_SIGNS_IN_FRAGMENT_QUERY => SIGN_QUERY_START
      . GET_FRAGMENT_FROM
      . SIGN_JOIN_PART
      . GET_FRAGMENT_WHERE
      . SIGN_QUERY_SCROLLVERSION_PART
      . SIGN_QUERY_END,

    # Predefined querie to get the sign data from a sign stream from a line
    GET_ALL_SIGNS_IN_LINE_QUERY => SIGN_QUERY_START
      . GET_LINE_FROM
      . SIGN_JOIN_PART
      . GET_LINE_WHERE
      . SIGN_QUERY_SCROLLVERSION_PART
      . SIGN_QUERY_END,

    GET_FIRST_SIGN_IN_COLUMN => 'SELECT sign_id '
      . GET_FRAGMENT_FROM
      . SIGN_JOIN_PART
      . 'where col_id=? '
      . SIGN_QUERY_SCROLLVERSION_PART,

    GET_FIRST_SIGN_IN_LINE => 'SELECT sign_id '
      . GET_FRAGMENT_FROM
      . SIGN_JOIN_PART
      . 'where line_id=? '
      . SIGN_QUERY_SCROLLVERSION_PART

};

use Exporter 'import';
our @EXPORT_OK = Package::Constants->list(__PACKAGE__);

1;
