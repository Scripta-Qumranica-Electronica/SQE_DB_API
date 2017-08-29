package SQE_DBI_queries;
use strict;
use warnings FATAL => 'all';
use Package::Constants;

use constant {
    CHECK_SCROLLVERSION => << 'HEREDOC',
    SELECT user_id
    FROM scroll_version
    WHERE scroll_version_id = ?
HEREDOC

    GET_ALL_VALUES => << 'HEREDOC',
    SELECT _table_.*
    FROM _table_
     JOIN _table__owner USING (_table__id)
    WHERE _table__id = ?
    AND scroll_version_id = _scrollversion_
HEREDOC


};

use Exporter 'import';
our @EXPORT_OK = Package::Constants->list(__PACKAGE__);

1;