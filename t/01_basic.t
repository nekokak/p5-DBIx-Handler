use strict;
use warnings;
use DBIx::Handler;
use Test::More;
use Test::SharedFork;
use Test::Requires 'DBD::SQLite';

my $handler = DBIx::Handler->new('dbi:SQLite:','','');
isa_ok $handler, 'DBIx::Handler';
isa_ok $handler->dbh, 'DBI::db';

subtest 'other db handler after disconnect' => sub {
    my $dbh = $handler->dbh;

    $handler->disconnect;

    isnt $dbh, $handler->dbh;
};

subtest 'fork' => sub {
    my $dbh = $handler->dbh;
    if (fork) {
        wait;
        is $dbh, $handler->dbh;
    } else {
        isnt $dbh, $handler->dbh;
        exit;
    }
};

subtest 'no active handle case' => sub {
    my $dbh = $handler->dbh;

    $dbh->{Active} = 0;

    isnt $dbh, $handler->dbh;
};

subtest 'can not ping case' => sub {
    no strict 'refs';
    no warnings 'redefine';

    my $dbh = $handler->dbh;

    my $ping = ref($handler->{_dbh}) . '::ping';
    local *$ping = sub { 0 };

    isnt $dbh, $handler->dbh;
};

done_testing;
