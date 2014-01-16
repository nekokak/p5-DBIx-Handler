# NAME

DBIx::Handler - fork-safe and easy transaction handling DBI handler

# SYNOPSIS

    use DBIx::Handler;
    my $handler = DBIx::Handler->new($dsn, $user, $pass, $opts);
    my $dbh = $handler->dbh;
    $dbh->do(...);

# DESCRIPTION

DBIx::Handler is fork-safe and easy transaction handling DBI handler.

DBIx::Hanler provide scope base transaction, fork safe dbh handling, simple.

# METHODS

- my $handler = DBIx::Handler->new($dsn, $user, $pass, $opts);

    get database handling instance.

- my $handler = DBIx::Handler->connect($dsn, $user, $pass, $opts);

    connect method is new methos alias.

- my $dbh = $handler->dbh;

    get fork safe DBI handle.

- $handler->disconnect;

    disconnect current database handle.

- my $txn\_guard = $handler->txn\_scope

    Creates a new transaction scope guard object.

        do {
            my $txn_guard = $handler->txn_scope;
                # some process
            $txn_guard->commit;
        }

    If an exception occurs, or the guard object otherwise leaves the scope
    before `$txn->commit` is called, the transaction will be rolled
    back by an explicit ["txn_rollback"](#txn_rollback) call. In essence this is akin to
    using a ["txn_begin"](#txn_begin)/["txn_commit"](#txn_commit) pair, without having to worry
    about calling ["txn_rollback"](#txn_rollback) at the right places. Note that since there
    is no defined code closure, there will be no retries and other magic upon
    database disconnection.

- $txn\_manager = $handler->txn\_manager

    Get the DBIx::TransactionManager instance.

- $handler->txn\_begin

    start new transaction.

- $handler->txn\_commit

    commit transaction.

- $handler->txn\_rollback

    rollback transaction.

- $handler->in\_txn

    are you in transaction?

- my @result = $handler->txn($coderef);

    execute $coderef in auto transaction scope.

    begin transaction before $coderef execute, do $coderef with database handle, after commit or rollback transaciont.

        $handler->txn(sub {
            my $dbh = shift;
            $dbh->do(...);
        });

    equals to:

        $handler->txn_begin;
            my $dbh = $handler->dbh;
            $dbh->do(...);
        $handler->txn_rollback;

- my @result = $handler->run($coderef);

    exexute $coderef.

        my $rs = $handler->run(sub {
            my $dbh = shift;
            $dbh->selectall_arrayref(...);
        });

    or

        my @result = $handler->run(sub {
            my $dbh = shift;
            $dbh->selectrow_array('...');
        });

- my $sth = $handler->query($sql, \[\\@bind | \\%bind\]);

    exexute query. return database statement handler. 

- $handler->result\_class($result\_class\_name);

    set result\_class package name.

    this result\_class use to be create query method response object.

- $handler->trace\_query($flag);

    inject sql comment when trace\_query is true. 

# AUTHOR

Atsushi Kobayashi <nekokak \_at\_ gmail \_dot\_ com>

# SEE ALSO

# LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.
