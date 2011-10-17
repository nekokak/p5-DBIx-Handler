use strict;
use warnings;
use DBIx::Handler;
use Test::More;
use Test::SharedFork;
use Test::Requires 'DBD::SQLite';

unlink './query_test.db';
my $handler = DBIx::Handler->new('dbi:SQLite:./query_test.db','','');
isa_ok $handler, 'DBIx::Handler';
isa_ok $handler->dbh, 'DBI::db';

$handler->dbh->do(q{
    create table query_test (
        name varchar(10) NOT NULL,
        PRIMARY KEY (name)
    );
});

subtest 'query' => sub {
    $handler->query(q{insert into query_test (name) values ('nekokak')});
    my $sth = $handler->query('select * from query_test');
    ok $sth;
    is_deeply $sth->fetchrow_hashref, +{name => 'nekokak'};

    $handler->query(q{insert into query_test (name) values ('zigorou')});
    $sth = $handler->query('select * from query_test');
    ok $sth;
    is_deeply $sth->fetchrow_hashref, +{name => 'nekokak'};
    is_deeply $sth->fetchrow_hashref, +{name => 'zigorou'};

    $sth = $handler->query('select * from query_test where name = :name', +{name => 'nekokak'});
    ok $sth;
    is_deeply $sth->fetchrow_hashref, +{name => 'nekokak'};
    ok not $sth->fetchrow_hashref;
};

unlink './query_test.db';

done_testing;
