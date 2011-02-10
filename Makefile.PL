use inc::Module::Install;
name 'DBIx-Handler';
all_from 'lib/DBIx/Handler.pm';

#requires '';

test_requires 'Test::More' => '0.94';

tests 't/*.t t/*/*.t';
author_tests('xt');

auto_set_repository;

WriteAll;
