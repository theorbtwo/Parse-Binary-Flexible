#!/usr/bin/perl
use warnings;
use strict;
use Module::Build;
my $build = Module::Build->new(
                               module_name => 'Binary',
                               license => 'perl',
                               requires => {
                                            perl => '5.10.0'
                                           }
                              );
$build->create_build_script;
