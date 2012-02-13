#!/usr/bin/perl
use warnings;
use strict;
use Test::More 'no_plan';
use Binary;

# Do required to avoid readonlyness.
my $fh = \do {"\1"};
(my $ret, $fh) = Binary::eat_desc([$fh], 'C');
is($ret, 1);
is_deeply($fh, \'');

$fh = \do {"\1\0\2\0\0\0\3"};
($ret, $fh) = Binary::eat_desc([$fh],
                               [
                                a => 'C',
                                b => 'n',
                                c => 'N'
                               ]);

# It is undefined if _context where no context was passed should be undef or not present.
delete $ret->{_context};
is_deeply($ret, {
                 '0.a' => 1,
                 a     => 1, 
                 '1.b' => 2,
                 b     => 2, 
                 '2.c' => 3,
                 c     => 3});

$fh = \do {"\1\2\3\4"};
($ret, $fh) = Binary::eat_desc([$fh], 'C4');
is_deeply($ret, [1, 2, 3, 4]);

$fh = \do {"asdf\0jklsemicolon"};
($ret, $fh) = Binary::eat_desc([$fh], 'Z*');
is_deeply($ret, 'asdf');

$fh = \do {"asdf"};
($ret, $fh) = Binary::eat_desc([$fh], 'a2');
is_deeply($ret, 'as');

$fh = \do {"asdf"};
($ret, $fh) = Binary::eat_desc([$fh], 'a*');
is_deeply($ret, 'asdf');

$fh = \do {"asdf"};
($ret, $fh) = Binary::eat_desc([$fh, 'foo'],
                               [
                                a => 'a1',
                                b => sub {
                                  my ($conv) = @_;
                                  my ($fh, $context) = @$conv;
                                  
                                  is_deeply($fh, \"sdf");
                                  is_deeply($context,
                                            {
                                             '0.a' => 'a',
                                             a => 'a',
                                             _context => 'foo'
                                            }
                                           );
                                  
                                  return 'b';
                                }
                               ]
                              );

is_deeply($ret, {'0.a' => 'a',
                 a=>'a',
                 '1.b' => 'b',
                 b=>'b', 
                 _context => 'foo'});
