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

exit;
my $new_scroll_version_id = $cgi->clone_scrollversion;

$cgi->set_scrollversion($new_scroll_version_id);


print "\n{";

$cgi->get_text_of_line($cgi->{CGIDATA}->{GET_LINE}, 'SQE_Format::JSON');

print "}\n{";


my $com_id=$cgi->set_sign_char_commentary(1,1,'Kommentar');
#$cgi->remove_sign_char_commentary($com_id);

exit;

#my $new=$cgi->set_sign_char_attribute(1,24,300);

#$cgi->remove_sign(1);

my $new_sign= $cgi->insert_sign('C', 1,2,2,3);

 $cgi->get_text_of_line($cgi->{CGIDATA}->{GET_LINE}, 'SQE_Format::JSON');



print "}\n{";


$cgi->remove_sign($new_sign);
$cgi->get_text_of_line($cgi->{CGIDATA}->{GET_LINE}, 'SQE_Format::JSON');



print "}\n";


 $cgi->delete_scrollversion;

print "\n}";

$cgi->get_text_of_line($cgi->{CGIDATA}->{GET_LINE}, 'SQE_Format::JSON');

print "}\n";

#$cgi->remove_sign_char_attribute($new);


#$cgi->get_text_of_line($cgi->{CGIDATA}->{GET_LINE}, 'SQE_Format::JSON');

1;