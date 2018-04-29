#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';
use SQE_CGI qw(:standard);
use SQE_DBI_queries;






my ( $cgi, $error_ref ) = SQE_CGI->new;


print '{';

if ($cgi->{CGIDATA}->{GET_LINE}) {
    $cgi->get_text_of_line($cgi->{CGIDATA}->{GET_LINE}, 'SQE_Format::JSON');
} elsif ($cgi->{CGIDATA}->{GET_FRAGMENT}) {
    $cgi->get_text_of_fragment($cgi->{CGIDATA}->{GET_FRAGMENT}, 'SQE_Format::JSON');

}
    print '}';
print "\n";

my $new=$cgi->set_sign_char_attribute(1,24);
$cgi->get_text_of_line($cgi->{CGIDATA}->{GET_LINE}, 'SQE_Format::JSON');

print "\n";

$cgi->remove_sign_char_attribute($new);


$cgi->get_text_of_line($cgi->{CGIDATA}->{GET_LINE}, 'SQE_Format::JSON');

1;