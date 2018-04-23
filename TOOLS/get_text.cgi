#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';
use SQE_CGI qw(:standard);


my ( $cgi, $error_ref ) = SQE_CGI->new;


print '{';

if ($cgi->{CGIDATA}->{GET_LINE}) {
    $cgi->get_text_of_line($cgi->{CGIDATA}->{GET_LINE}, 'SQE_Format::JSON');
} elsif ($cgi->{CGIDATA}->{GET_FRAGMENT}) {
    $cgi->get_text_of_fragment($cgi->{CGIDATA}->{GET_FRAGMENT}, 'SQE_Format::JSON');

}
    print '}';





1;