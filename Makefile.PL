use inc::Module::Install;
name 'DBIx-Handler';
all_from 'lib/DBIx/Handler.pm';

requires 'DBI' => '1.605';
requires 'DBIx::TransactionManager' => '1.09';

test_requires 'Test::More' => '0.94';
test_requires 'Test::SharedFork' => '0.16';
test_requires 'Test::Requires';

tests 't/*.t t/*/*.t';
author_tests('xt');

auto_set_repository;

WriteAll;
