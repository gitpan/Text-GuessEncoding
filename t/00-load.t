#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'Text::ToAscii' ) || print "Bail out!
";
}

diag( "Testing Text::ToAscii $Text::ToAscii::VERSION, Perl $], $^X" );
