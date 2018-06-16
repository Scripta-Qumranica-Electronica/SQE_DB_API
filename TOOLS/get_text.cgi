#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';
use SQE_CGI qw(:standard);
use SQE_DBI_queries;


my ( $cgi, $error_ref ) = SQE_CGI->new;


#$cgi->dbh->move_line_number(99888,-10);

#exit;
print '{';

if ($cgi->{CGIDATA}->{GET_LINE}) {
    $cgi->get_text_of_line($cgi->{CGIDATA}->{GET_LINE}, 'SQE_Format::JSON');
} elsif ($cgi->{CGIDATA}->{GET_FRAGMENT}) {
    $cgi->get_text_of_fragment($cgi->{CGIDATA}->{GET_FRAGMENT}, 'SQE_Format::JSON');

}
    print '}';


$cgi->set_scrollversion(1630);

$cgi->add_sign_char_variant(998006,'A');

exit;

#my $new_scroll_version_id = $cgi->clone_scrollversion;



#my $artefact_id=$cgi->add_artefact(2610, '[]');

$cgi->change_artefact_position(3286, 'position');

$cgi->change_artefact_data(3286, 'hurra');

$cgi->change_artefact_shape(3286, 2610, 'POLYGON((1 1,1 2,2 2,2 1, 1 1))');

#$cgi->remove_artefact($artefact_id);

exit;
print "\n{";

$cgi->get_text_of_line($cgi->{CGIDATA}->{GET_LINE}, 'SQE_Format::JSON');

print "}\n{";


my $com_id=$cgi->set_sign_char_commentary(1,1,'Kommentar');
#$cgi->remove_sign_char_commentary($com_id);

print "\n{";

$cgi->get_text_of_line($cgi->{CGIDATA}->{GET_LINE}, 'SQE_Format::JSON');

print "}\n{";

print $cgi->get_sign_char_commentary($com_id);
#my $new=$cgi->set_sign_char_attribute(1,24,300);

#$cgi->remove_sign(1);
print "}\n{";

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