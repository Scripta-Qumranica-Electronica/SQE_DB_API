#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';

use SQE_DBI;

my $dbh = SQE_DBI->get_sqe_dbh;

my $search_scroll_ids = <<"MYSQL";
select scroll_id, scroll_version_id from scroll
join scroll_version_group USING (scroll_id)
join scroll_version USING (scroll_version_group_id)
MYSQL

my $search_cols = <<"MYSQL";
select col_id
from scroll_to_col
join scroll_to_col_owner USING (scroll_to_col_id)
where scroll_id=? and scroll_version_id=?
MYSQL

my $insert_col_seq = <<"MYSQL";
insert into col_sequence
(col_id,position) values (?,?)
MYSQL

my $insert_seq_sth = $dbh->prepare($insert_col_seq);

my $insert_sv = <<"MYSQL";
insert into col_sequence_owner
(col_sequence_id, scroll_version_id) VALUES (?,?);

MYSQL

my $insert_sv_sth = $dbh->prepare($insert_sv);

my $col_sth=$dbh->prepare($search_cols);

my @scroll_ids=$dbh->selectall_array($search_scroll_ids);

foreach my $data (@scroll_ids) {
    my $ind=1;
    my $scrollversion_id=$data->[1];
    $col_sth->execute(@$data);
    my $col_id;
    $col_sth->bind_col(1,\$col_id);
    while ($col_sth->fetch) {
        $insert_seq_sth->execute($col_id, $ind);
        my $id = $dbh->{mysql_insertid};
        $insert_sv_sth->execute($id, $scrollversion_id);
        $ind++;
    }
}



$dbh->disconnect;