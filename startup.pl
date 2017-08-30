use strict;

use lib qw(/home/perl_libs);

$ENV{MOD_PERL} or die "not running under mod_perl!";



use ModPerl::Registry ();
use LWP::UserAgent    ();
use Apache::DBI       ();
use DBI               ();

use Carp ();
$SIG{'__WARN__'} = \&Carp::cluck;

use CGI ();
CGI->compile(':all');

use SQE_Error ();
use SQE_Restricted ();
use SQE_database ();
use SQE_DBI ();
use SQE_CGI ();


use SQE_API::format_json ();
use SQE_API::format_qwb_html ();
use SQE_API::Queries ();
use SQE_API::Worker ();


my $dsn      = "dbi:mysql:SQE:localhost:3306";
my $username = "SQE";
my $password = 'saAsC4y92';

my %attr = (
    PrintError => 0,    # turn off error reporting via warn()
    RaiseError => 1
);                      # turn on error reporting via die()

Apache::DBI->connect_on_init( $dsn, $username, $password, \%attr );
Apache::DBI->setPingTimeOut( $dsn, 10 );






1;