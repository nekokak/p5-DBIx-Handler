package DBIx::Handler;
use strict;
use warnings;
our $VERSION = '0.05';

use DBI 1.605;
use DBIx::TransactionManager 1.09;
use Carp ();

*connect = \&new;
sub new {
    my $class = shift;

    my $opts = scalar(@_) == 5 ? pop @_ : +{};
    bless {
        _connect_info    => [@_],
        _pid             => undef,
        _dbh             => undef,
        trace_query      => $opts->{trace_query}      || 0,
        result_class     => $opts->{result_class}     || undef,
        on_connect_do    => $opts->{on_connect_do}    || undef,
        on_disconnect_do => $opts->{on_disconnect_do} || undef,
    }, $class;
}

sub _connect {
    my $self = shift;

    my $dbh = $self->{_dbh} = DBI->connect(@{$self->{_connect_info}});

    if (DBI->VERSION > 1.613 && (@{$self->{_connect_info}} < 4 || !exists $self->{_connect_info}[3]{AutoInactiveDestroy})) {
        $dbh->STORE(AutoInactiveDestroy => 1);
    }

    if (@{$self->{_connect_info}} < 4 || (!exists $self->{_connect_info}[3]{RaiseError} && !exists $self->{_connect_info}[3]{HandleError})) {
        $dbh->STORE(RaiseError => 1);
    }

    $self->{_pid} = $$;

    $self->_run_on('on_connect_do', $dbh);

    $dbh;
}

sub dbh {
    my $self = shift;
    $self->_seems_connected or $self->_connect;
}

sub _seems_connected {
    my $self = shift;

    my $dbh = $self->{_dbh} or return;

    if ( $self->{_pid} != $$ ) {
        $dbh->STORE(InactiveDestroy => 1);
        $self->_in_txn_check;
        $self->{txn_manager} = undef;
        return;
    }

    unless ($dbh->FETCH('Active') && $dbh->ping) {
        $self->_in_txn_check;
        $self->{txn_manager} = undef;
        return;
    }

    $dbh;
}

sub disconnect {
    my $self = shift;

    my $dbh = $self->_seems_connected or return;

    $self->_run_on('on_disconnect_do', $dbh);
    $dbh->STORE(CachedKids => {});
    $dbh->disconnect;
    $self->{_dbh} = undef;
}

sub _run_on {
    my ($self, $mode, $dbh) = @_;
    if ( my $on_connect_do = $self->{$mode} ) {
        if (not ref($on_connect_do)) {
            $dbh->do($on_connect_do);
        } elsif (ref($on_connect_do) eq 'CODE') {
            $on_connect_do->($dbh);
        } elsif (ref($on_connect_do) eq 'ARRAY') {
            $dbh->do($_) for @$on_connect_do;
        } else {
            Carp::croak("Invalid $mode: ".ref($on_connect_do));
        }
    }
}

sub DESTROY { $_[0]->disconnect }

sub result_class {
    my ($self, $result_class) = @_;
    $self->{result_class} = $result_class if $result_class;
    $self->{result_class};
}

sub trace_query {
    my ($self, $flag) = @_;
    $self->{trace_query} = $flag if defined $flag;
    $self->{trace_query};
}

sub query {
    my ($self, $sql, @args) = @_;

    my $bind;
    if (ref($args[0]) eq 'HASH') {
        ($sql, $bind) = $self->_replace_named_placeholder($sql, $args[0]);
    }
    else {
        $bind = ref($args[0]) eq 'ARRAY' ? $args[0] : \@args;
    }

    if ($self->trace_query) {
        $sql = $self->_trace_query_set_comment($sql);
    }

    my $sth;
    eval {
        $sth = $self->dbh->prepare($sql);
        $sth->execute(@{$bind || []});
    };
    if (my $error = $@) {
        Carp::croak($error);
    }

    my $result_class = $self->result_class;
    $result_class ? $result_class->new($self, $sth) : $sth;
}

sub _replace_named_placeholder {
    my ($self, $sql, $args) = @_;

    my %named_bind = %{$args};
    my @bind;
    $sql =~ s{:(\w+)}{
        Carp::croak("$1 does not exists in hash") if !exists $named_bind{$1};
        if ( ref $named_bind{$1} && ref $named_bind{$1} eq "ARRAY" ) {
            push @bind, @{ $named_bind{$1} };
            my $tmp = join ',', map { '?' } @{ $named_bind{$1} };
            "($tmp)";
        } else {
            push @bind, $named_bind{$1};
            '?'
        }
    }ge;

    return ($sql, \@bind);
}

sub _trace_query_set_comment {
    my ($self, $sql) = @_;

    my $i=0;
    while ( my (@caller) = caller($i++) ) {
        next if ( $caller[0]->isa( __PACKAGE__ ) );
        my $comment = "$caller[1] at line $caller[2]";
        $comment =~ s/\*\// /g;
        $sql = "/* $comment */ $sql";
        last;
    }

    $sql;
}

sub run {
    my ($self, $coderef) = @_;
    my $wantarray = wantarray;

    my @ret = eval {
        my $dbh = $self->dbh;
        $wantarray ? $coderef->($dbh) : scalar $coderef->($dbh);
    };
    if (my $error = $@) {
        Carp::croak($error);
    }

    $wantarray ? @ret : $ret[0];
}

# --------------------------------------------------------------------------------
# for transaction
sub txn_manager {
    my $self = shift;

    my $dbh = $self->dbh;
    $self->{txn_manager} ||= DBIx::TransactionManager->new($dbh);
}

sub in_txn {
    my $self = shift;
    return unless $self->{txn_manager};
    return $self->{txn_manager}->in_transaction;
}

sub _in_txn_check {
    my $self = shift;

    my $info = $self->in_txn;
    return unless $info;

    my $caller = $info->{caller};
    my $pid    = $info->{pid};
    Carp::confess("Detected transaction during a connect operation (last known transaction at $caller->[1] line $caller->[2], pid $pid). Refusing to proceed at");
}

sub txn_scope {
    my @caller = caller();
    $_[0]->txn_manager->txn_scope(caller => \@caller);
}

sub txn {
    my ($self, $coderef) = @_;

    my $wantarray = wantarray;
    my $txn = $self->txn_scope;

    my @ret = eval {
        my $dbh = $self->dbh;
        $wantarray ? $coderef->($dbh) : scalar $coderef->($dbh);
    };

    if (my $error = $@) {
        $txn->rollback;
        Carp::croak($error);
    } else {
        eval { $txn->commit };
        Carp::croak($@) if $@;
    }

    $wantarray ? @ret : $ret[0];
}

sub txn_begin    { $_[0]->txn_manager->txn_begin    }
sub txn_rollback { $_[0]->txn_manager->txn_rollback }
sub txn_commit   { $_[0]->txn_manager->txn_commit   }

1;

__END__

=head1 NAME

DBIx::Handler - fork-safe and easy transaction handling DBI handler

=head1 SYNOPSIS

  use DBIx::Handler;
  my $handler = DBIx::Handler->new($dsn, $user, $pass, $opts);
  my $dbh = $handler->dbh;
  $dbh->do(...);

=head1 DESCRIPTION

DBIx::Handler is fork-safe and easy transaction handling DBI handler.

DBIx::Hanler provide scope base transaction, fork safe dbh handling, simple.

=head1 METHODS

=item my $handler = DBIx::Handler->new($dsn, $user, $pass, $opts);

get database handling instance.

=item my $handler = DBIx::Handler->connect($dsn, $user, $pass, $opts);

connect method is new methos alias.

=item my $dbh = $handler->dbh;

get fork safe DBI handle.

=item $handler->disconnect;

disconnect current database handle.

=item my $txn_guard = $handler->txn_scope

Creates a new transaction scope guard object.

    do {
        my $txn_guard = $handler->txn_scope;
            # some process
        $txn_guard->commit;
    }

If an exception occurs, or the guard object otherwise leaves the scope
before C<< $txn->commit >> is called, the transaction will be rolled
back by an explicit L</txn_rollback> call. In essence this is akin to
using a L</txn_begin>/L</txn_commit> pair, without having to worry
about calling L</txn_rollback> at the right places. Note that since there
is no defined code closure, there will be no retries and other magic upon
database disconnection.

=item $txn_manager = $handler->txn_manager

Get the DBIx::TransactionManager instance.

=item $handler->txn_begin

start new transaction.

=item $handler->txn_commit

commit transaction.

=item $handler->txn_rollback

rollback transaction.

=item $handler->in_txn

are you in transaction?

=item my @result = $handler->txn($coderef);

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

=item my @result = $handler->run($coderef);

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

=item my $sth = $handler->query($sql, [\@bind | \%bind]);

exexute query. return database statement handler. 

=item $handler->result_class($result_class_name);

set result_class package name.

this result_class use to be create query method response object.

=item $handler->trace_query($flag);

inject sql comment when trace_query is true. 

=head1 AUTHOR

Atsushi Kobayashi E<lt>nekokak _at_ gmail _dot_ comE<gt>

=head1 SEE ALSO

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

