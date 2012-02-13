#!/usr/bin/perl
use warnings;
use strict;
use Test::More 'no_plan';
use Test::Exception;
use Binary;

my $fh = \do {"\0"};
(my $ret, $fh) = Binary::eat_required([$fh], 'C', 0);
is($ret, 0);

$fh = \do {"\0"};
dies_ok( sub {
           (my $ret, $fh) = Binary::eat_required([$fh], 'C', 1, 'foo');
         },
         "foo: expected '1', got '0'"
       );
is($ret, 0);

$fh = \do {"\1"};
($ret, $fh) = Binary::eat_required([$fh], 'C', 1);
is($ret, 1);

$fh = \do {"a"};
($ret, $fh) = Binary::eat_required([$fh], 'a1', 'a');
is($ret, 'a');

