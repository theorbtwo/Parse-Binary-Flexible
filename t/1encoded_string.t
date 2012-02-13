#!/usr/bin/perl
use warnings;
use strict;
use Test::More 'no_plan';
use Test::Exception;
use Binary;
use charnames ':full';

binmode \*STDOUT, ':utf8';

my $fh = \do{"asdf\0"};
my $ret;

($ret, $fh) = Binary::eat_encoded_str([$fh], 5, 'ascii', 0);
is($ret, "asdf\0");
is($$fh, "");

$fh = \do{"asdf\0"};
($ret, $fh) = Binary::eat_encoded_str([$fh], 5, 'ascii', 1);
is($ret, "asdf");
is($$fh, "");

$fh = \do {"\2\xc3\xb6?"};
($ret, $fh) = Binary::eat_encoded_str([$fh], 'C', 'utf-8');
is($ret, "\N{LATIN SMALL LETTER O WITH DIAERESIS}");
is($$fh, "?");

$fh = \do {"\xFF\xFF"};
dies_ok(sub {($ret, $fh) = Binary::eat_encoded_str([$fh], 1, 'utf-8')});

