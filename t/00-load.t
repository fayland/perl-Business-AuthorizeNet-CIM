#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok('Business::AuthorizeNet::CIM');
}

diag(
"Testing Business::AuthorizeNet::CIM $Business::AuthorizeNet::CIM::VERSION, Perl $], $^X"
);
