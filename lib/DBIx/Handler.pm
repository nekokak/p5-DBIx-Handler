package DBIx::Handler;
use strict;
use warnings;
our $VERSION = '0.01';

use DBI 1.605;
use DBIx::TransactionManager 1.09;
use Carp ();

sub new {
    my $class = shift;

    my $on_connect_do = scalar(@_) == 5 ? pop @_ : +{};
    bless {
        _connect_info    => [@_],
        _pid             => undef,
        _dbh             => undef,
        on_connect_do    => $on_connect_do->{on_connect_do}    || undef,
        on_disconnect_do => $on_connect_do->{on_disconnect_do} || undef,
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

    my @ret = eval { $coderef->($self->dbh) };

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
sub txn_end      { $_[0]->txn_manager->txn_end      }

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

=item $handler->txn_end

finish transaction.

=item $handler->in_txn

are you in transaction?

=item my @result = $handler->txn($coderef);

execute $coderef in auto transaction scope.

begin transaction before $coderef execute, do $coderef with database handle, after commit or rollback transaciont.

=head1 AUTHOR

Atsushi Kobayashi E<lt>nekokak _at_ gmail _dot_ comE<gt>

=head1 SEE ALSO

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

