# fleeMonster - foge andando (sem teleporte) de monstros perigosos.
#
# Quando um monstro listado chega perto, larga ataque/coleta/descanso e anda para
# o lado oposto. Pensado para monstros lentos que o personagem nao consegue matar
# (ex.: Filhote de Hatii / Garm Baby em xmas_dun02).
#
# config.txt:
#   fleeMonster_ids 1515      # IDs (ou nomes) separados por virgula; vazio desliga
#   fleeMonster_dist 10       # foge quando o monstro estiver a esta distancia ou menos
#   fleeMonster_runDist 15    # quantas celulas tentar se afastar
#
# Use junto com "<id> -1 0 0" no mon_control.txt para o bot nunca atacar o monstro.
package fleeMonster;

use strict;
use Globals qw(%config $char $field $net $monstersList);
use Log qw(message warning);
use Utils qw(timeOut blockDistance calcPosition);
use AI;

Plugins::register('fleeMonster', 'Foge andando de monstros perigosos', \&unload);
my $hooks = Plugins::addHooks(['AI_pre', \&onAI]);

my $lastFlee = 0;

sub unload { Plugins::delHooks($hooks) }

sub onAI {
	return unless $config{fleeMonster_ids};
	return unless $net && $net->getState() == Network::IN_GAME();
	return unless $char && $field && !$char->{dead};
	# Replaneja no maximo a cada 1 s para nao ficar trocando de rota a todo tick.
	return unless timeOut($lastFlee, 1);

	my %wanted = map { lc($_) => 1 } grep { length } map { s/^\s+|\s+$//gr } split /,/, $config{fleeMonster_ids};
	my $triggerDist = $config{fleeMonster_dist} || 10;
	my $runDist = $config{fleeMonster_runDist} || 15;

	my $myPos = calcPosition($char);
	my ($danger, $dangerDist);
	for my $monster (@{$monstersList->getItems()}) {
		next unless $wanted{$monster->{nameID}} || $wanted{lc($monster->{name} // '')};
		my $dist = blockDistance($myPos, calcPosition($monster));
		($danger, $dangerDist) = ($monster, $dist) if !defined $dangerDist || $dist < $dangerDist;
	}
	return unless $danger && $dangerDist <= $triggerDist;

	my $spot = fleeSpot($myPos, calcPosition($danger), $runDist) or do {
		warning "[fleeMonster] $danger->{name} a $dangerDist celulas, mas nao achei para onde fugir\n";
		$lastFlee = time;
		return;
	};

	message "[fleeMonster] Fugindo de $danger->{name} (a $dangerDist celulas) para ($spot->{x}, $spot->{y})\n", 'teleport';
	AI::clear(qw(attack route move take items_take items_gather sitAuto sitting));
	AI::stand() if $char->{sitting};
	$char->route($field->baseName, $spot->{x}, $spot->{y}, noMapRoute => 1, maxRouteTime => 8, attackOnRoute => 0, noSitAuto => 1);
	$lastFlee = time;
}

# Ponto andavel a ~$runDist celulas na direcao oposta ao monstro. Tenta primeiro a
# direcao exata e depois desvia em leque (ate 135 graus) caso haja parede.
sub fleeSpot {
	my ($me, $mon, $runDist) = @_;
	my ($dx, $dy) = ($me->{x} - $mon->{x}, $me->{y} - $mon->{y});
	($dx, $dy) = (1, 0) if !$dx && !$dy;
	my $base = atan2($dy, $dx);

	for my $offset (0, 30, -30, 60, -60, 90, -90, 135, -135) {
		my $angle = $base + $offset * 3.14159265 / 180;
		for my $dist (reverse 5 .. $runDist) {
			my $x = int($me->{x} + cos($angle) * $dist + 0.5);
			my $y = int($me->{y} + sin($angle) * $dist + 0.5);
			next if $x < 0 || $y < 0 || $x >= $field->width || $y >= $field->height;
			next unless $field->isWalkable($x, $y);
			# Nao serve se o destino ficar mais perto do monstro do que estamos agora.
			next if blockDistance({x => $x, y => $y}, $mon) <= blockDistance($me, $mon);
			return {x => $x, y => $y};
		}
	}
	return;
}

1;
