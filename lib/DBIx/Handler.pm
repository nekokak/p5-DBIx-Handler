package DBIx::Handler;
use strict;
use warnings;
our $VERSION = '0.01';

use DBI '1.613';
use DBIx::TransactionManager '1.09';

sub new {
    my $class = shift;

    bless {
        _connect_info => [@_],
        _pid          => undef,
        _dbh          => undef,
    }, $class;
}

sub _connect {
    my $self = shift;

    my $dbh = $self->{_dbh} = DBI->connect(@{$self->{_connect_info}});

    if (@{$self->{_connect_info}} < 4 || !exists $self->{_connect_info}[3]{AutoInactiveDestroy}) {
        $dbh->STORE(AutoInactiveDestroy => 1);
    }

    if (@{$self->{_connect_info}} < 4 || (!exists $self->{_connect_info}[3]{RaiseError} && !exists $self->{_connect_info}[3]{HandleError})) {
        $dbh->STORE(RaiseError => 1);
    }

    $self->{_pid} = $$;

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
        $self->in_txn_check;
        $self->{txn_manager} = undef;
        return;
    }

    unless ($dbh->FETCH('Active') && $dbh->ping) {
        $self->in_txn_check;
        $self->{txn_manager} = undef;
        return;
    }

    $dbh;
}

sub disconnect {
    my $self = shift;

    my $dbh = $self->_seems_connected or return;

    $dbh->STORE(CachedKids => {});
    $dbh->disconnect;
    $self->{_dbh} = undef;
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

sub in_txn_check {
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

sub txn_begin    { $_[0]->txn_manager->txn_begin    }
sub txn_rollback { $_[0]->txn_manager->txn_rollback }
sub txn_commit   { $_[0]->txn_manager->txn_commit   }
sub txn_end      { $_[0]->txn_manager->txn_end      }


1;
__END__

=head1 NAME

DBIx::Handler -

=head1 SYNOPSIS

  use DBIx::Handler;

=head1 DESCRIPTION

DBIx::Handler is

=head1 AUTHOR

Atsushi Kobayashi E<lt>nekokak _at_ gmail _dot_ comE<gt>

=head1 SEE ALSO

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

