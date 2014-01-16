requires 'DBI', '1.605';
requires 'DBIx::TransactionManager', '1.09';

on build => sub {
    requires 'ExtUtils::MakeMaker', '6.36';
    requires 'Test::More', '0.94';
    requires 'Test::Requires';
    requires 'Test::SharedFork', '0.16';
};
