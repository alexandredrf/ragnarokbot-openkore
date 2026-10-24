# bardSongs - ciclo de musicas do Bardo: para cada musica, equipa o instrumento, toca
# e desequipa (a musica para e o efeito fica 20 s em quem estava na area). Assim os
# efeitos de varias musicas ficam ativos ao mesmo tempo no alvo.
#
# No pre-renovacao a musica nao afeta o proprio bardo, entao a condicao e o status do
# alvo. Musica cujo status o servidor nao informa no alvo: intervalo fixo. So toca as
# musicas que faltam.
#
# config.txt:
#   bardSongs_target Fulano                  # jogador que recebe as musicas; vazio desliga
#   bardSongs_instrument Violin              # nome do instrumento no inventario (sem [slots])
#   bardSongs_songs Poem of Bragi, Assassin Cross of Sunset
#   bardSongs_maxDist 3                      # so toca com o alvo a esta distancia ou menos
#   bardSongs_minSp 80                       # SP minimo para comecar um ciclo
#   bardSongs_interval 16                    # segundos entre ciclos sem status do alvo
#   bardSongs_sit 1                          # senta perto do alvo parado entre os ciclos (SP)
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

my (@steps, $stepTime, $lastCycle, $lastSit, %seen, %lastCast, %warned);

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

# Musicas que faltam no alvo. Musica cujo status o servidor ja mostrou no alvo: pelo
# status; senao, pelo intervalo desde a ultima vez que foi tocada.
sub missingSongs {
	my ($player) = @_;
	my $interval = $config{bardSongs_interval} || 16;
	return grep {
		my $handle = $status{$_};
		$seen{$_} = 1 if $handle && $player->{statuses}{$handle};
		$seen{$_} ? !$player->{statuses}{$handle} : timeOut($lastCast{$_}, $interval);
	} songs();
}

# Entre um ciclo e outro: senta perto do alvo parado para recuperar SP; levanta quando
# ele se afasta (o follow anda atras dele).
sub restOrFollow {
	my ($player, $dist) = @_;
	return unless $config{bardSongs_sit} && timeOut($lastSit, 2);
	my $still = $player->{pos}{x} == $player->{pos_to}{x} && $player->{pos}{y} == $player->{pos_to}{y};
	if ($char->{sitting} && ($dist > ($config{bardSongs_maxDist} || 3) || !$still)) {
		stand();
		$lastSit = time;
	} elsif (!$char->{sitting} && $still && $dist <= ($config{bardSongs_maxDist} || 3)
		&& $char->{sp} < $char->{sp_max} && (AI::isIdle() || AI::is('follow'))) {
		sit();
		$lastSit = time;
	}
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
	my $player = target() or return;
	my $dist = blockDistance(calcPosFromPathfinding($field, $char), calcPosFromPathfinding($field, $player));
	# Espera os status do alvo chegarem depois de um ciclo.
	my @missing = timeOut($lastCycle, 3) ? missingSongs($player) : ();
	if (!@missing || $dist > ($config{bardSongs_maxDist} || 3) || $char->{sp} < ($config{bardSongs_minSp} || 0)) {
		restOrFollow($player, $dist);
		return;
	}
	instrument() or return;

	for my $song (@missing) {
		my $skill = Skill->new(auto => $song);
		unless ($char->getSkillLevel($skill)) {
			warning "[bardSongs] Skill '$song' nao aprendida.\n" unless $warned{$song}++;
			next;
		}
		push @steps, ['equip'], ['cast', $skill], ['unequip'];
	}
	return unless @steps;
	message "[bardSongs] Tocando: " . join(', ', @missing) . "\n", 'skill';
	$lastCast{$_} = time for @missing;
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
