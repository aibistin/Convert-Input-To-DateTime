#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'Convert::Input::To::DateTime' ) || print "Bail out!\n";
}

diag( "Testing Convert::Input::To::DateTime $Convert::Input::To::DateTime::VERSION, Perl $], $^X" );
