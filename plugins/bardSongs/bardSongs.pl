# bardSongs - ciclo de musicas do Bardo: para cada musica, equipa o instrumento, toca
# e desequipa (a musica para e o efeito fica 20 s em quem estava na area). Assim os
# efeitos de varias musicas ficam ativos ao mesmo tempo no alvo.
#
# No pre-renovacao a musica nao afeta o proprio bardo, entao a condicao e o status do
# alvo. Se o servidor nao informa os status dele, usa um intervalo fixo.
#
# config.txt:
#   bardSongs_target Fulano                  # jogador que recebe as musicas; vazio desliga
#   bardSongs_instrument Violin              # nome do instrumento no inventario (sem [slots])
#   bardSongs_songs Poem of Bragi, Assassin Cross of Sunset
#   bardSongs_maxDist 3                      # so toca com o alvo a esta distancia ou menos
#   bardSongs_minSp 80                       # SP minimo para comecar um ciclo
#   bardSongs_interval 16                    # segundos entre ciclos sem status do alvo
package bardSongs;

use strict;
use Globals qw(%config $char $field $net $playersList);
use Log qw(message warning);
use Utils qw(timeOut blockDistance calcPosFromPathfinding);
use AI;
use Skill;

Plugins::register('bardSongs', 'Ciclo de musicas do Bardo (equipa, toca, desequipa)', \&unload);
my $hooks = Plugins::addHooks(['AI_pre', \&onAI]);

my %status = (
	'Poem of Bragi' => 'EFST_POEMBRAGI',
	'Assassin Cross of Sunset' => 'EFST_ASSASSINCROSS',
);

my (@steps, $stepTime, $lastCycle, $statusKnown, %warned);

sub unload { Plugins::delHooks($hooks) }

sub songs { map { s/^\s+|\s+$//gr } split /,/, $config{bardSongs_songs} // '' }

sub instrument {
	my $name = $config{bardSongs_instrument} or return;
	for my $item (@{$char->inventory->getItems}) {
		return $item if $item->{name} =~ /^\Q$name\E(\s*\[\d+\])?$/i;
	}
	warning "[bardSongs] Instrumento '$name' nao esta no inventario.\n" unless $warned{inst}++;
	return;
}

sub target {
	for my $player (@{$playersList->getItems}) {
		return $player if $player->{name} eq $config{bardSongs_target};
	}
	return;
}

# Precisa de musica se algum efeito falta no alvo; sem status do alvo, por intervalo.
sub needsSongs {
	my ($player) = @_;
	my @handles = map { $status{$_} } songs();
	$statusKnown = 1 if grep { $player->{statuses}{$_} } @handles;
	return timeOut($lastCycle, $config{bardSongs_interval} || 16) unless $statusKnown;
	return grep { !$player->{statuses}{$_} } @handles;
}

sub onAI {
	return unless $config{bardSongs_target};
	return unless $net && $net->getState() == Network::IN_GAME();
	return if $char->{dead} || !$char->inventory->isReady();

	if (@steps) {
		runStep();
		return;
	}

	return if $config{lockMap} && $field->baseName ne $config{lockMap};
	return if $char->{sp} < ($config{bardSongs_minSp} || 0);
	my $player = target() or return;
	my $dist = blockDistance(calcPosFromPathfinding($field, $char), calcPosFromPathfinding($field, $player));
	return if $dist > ($config{bardSongs_maxDist} || 3);
	return unless needsSongs($player);
	instrument() or return;

	for my $song (songs()) {
		my $skill = Skill->new(auto => $song);
		unless ($char->getSkillLevel($skill)) {
			warning "[bardSongs] Skill '$song' nao aprendida.\n" unless $warned{$song}++;
			next;
		}
		push @steps, ['equip'], ['cast', $skill], ['unequip'];
	}
	return unless @steps;
	message "[bardSongs] Tocando: " . join(', ', songs()) . "\n", 'skill';
	$lastCycle = time;
	$stepTime = 0;
}

# Cada passo espera o anterior (equipar/tocar leva um instante); timeout evita travar.
sub nextStep { shift @steps; $stepTime = 0 }

sub runStep {
	my $item = instrument();
	unless ($item) { @steps = (); return }
	my ($action, $skill) = @{$steps[0]};

	if ($action eq 'equip') {
		return nextStep() if $item->{equipped};
		if (timeOut($stepTime, 2)) { $item->equip; $stepTime = time }
	} elsif ($action eq 'cast') {
		return unless $item->{equipped};
		if (!$stepTime) {
			AI::ai_skillUse2($skill, $char->getSkillLevel($skill), 0, 0, $char, 'bardSongs');
			$stepTime = time;
		} elsif (timeOut($stepTime, 1.5) && !AI::inQueue('skill_use')) {
			# Espera a area da musica pegar o alvo antes de cortar.
			nextStep();
		}
	} elsif ($action eq 'unequip') {
		return nextStep() unless $item->{equipped};
		if (timeOut($stepTime, 2)) { $item->unequip; $stepTime = time }
	}
}

1;
