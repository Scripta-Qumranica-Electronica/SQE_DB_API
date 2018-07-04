#!/usr/bin/perl

use warnings FATAL => 'all';

use strict;

use Data::UUID;



our $test;

use SQE_CGI qw(:standard );
use CGI::Carp;

use SQE_API::Worker;

my ($cgi, $error_ref) = SQE_CGI->new;


my $dbh = $cgi->dbh;

$cgi->start_json_output;



if (! defined $error_ref) {
    $cgi->print_session_id;
    print SQE_API::Worker::process($cgi);
} else {
    $cgi->sent_json_error($error_ref);

}



$cgi->finish_json_output;



