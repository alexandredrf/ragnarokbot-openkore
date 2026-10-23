# attackedBy - condicao de monstro "_attackedBy": so vale para monstros que um dos
# jogadores listados ja acertou (ou errou) - ou seja, o alvo que ele esta batendo.
#
# Funciona em qualquer bloco que use checkMonsterCondition, ex. monsterSkill:
#   monsterSkill Lex Aeterna {
#   	target_attackedBy Matador    # nomes separados por virgula
#   	target_dist 0..9
#   	target_timeout 3
#   }
package attackedBy;

use strict;
use Globals qw(%config $playersList);
use Utils qw(existsInList);

Plugins::register('attackedBy', 'Condicao _attackedBy para monstros', \&unload);
my $hooks = Plugins::addHooks(['checkMonsterCondition', \&onCheck]);

sub unload { Plugins::delHooks($hooks) }

sub onCheck {
	my (undef, $args) = @_;
	my $names = $config{$args->{prefix} . '_attackedBy'} or return;
	my $monster = $args->{monster};

	for my $ID (keys %{$monster->{dmgFromPlayer} || {}}, keys %{$monster->{missedFromPlayer} || {}}) {
		my $player = $playersList->getByID($ID) or next;
		return if existsInList($names, $player->{name});
	}
	$args->{return} = 0;
}

1;
