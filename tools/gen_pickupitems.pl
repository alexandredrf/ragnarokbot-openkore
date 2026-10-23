#!/usr/bin/perl
# Gera um pickupitems.txt que so coleta cartas, acessorios e os IDs extras informados.
# Fonte: item_db pre-renovacao do rAthena (mesmos IDs do servidor).
#
# Uso:
#   curl -sLO https://raw.githubusercontent.com/rathena/rathena/master/db/pre-re/item_db_equip.yml
#   curl -sLO https://raw.githubusercontent.com/rathena/rathena/master/db/pre-re/item_db_etc.yml
#   perl tools/gen_pickupitems.pl item_db_equip.yml item_db_etc.yml 727 > bots/<nome>/control/pickupitems.txt
#
# Argumentos numericos = IDs extras para coletar (ex.: 727 = Opala).
# --sem-acessorios = so cartas e os IDs extras.
use strict;
use warnings;

my $semAcc = grep { $_ eq '--sem-acessorios' } @ARGV;
my @files = grep { !/^\d+$/ && $_ ne '--sem-acessorios' } @ARGV;
my @extra = grep { /^\d+$/ } @ARGV;
my (%name, @cards, @accs, $cur);

sub flush {
	return unless $cur;
	$name{$cur->{id}} = $cur->{name} // '';
	push @cards, $cur->{id} if ($cur->{type} // '') eq 'Card';
	push @accs, $cur->{id} if $cur->{acc} && ($cur->{type} // '') ne 'Card';
}

for my $file (@files) {
	open my $fh, '<', $file or die "$file: $!\n";
	while (<$fh>) {
		if (/^  - Id:\s*(\d+)/) { flush(); $cur = { id => $1 }; next }
		next unless $cur;
		$cur->{name} = $1 if /^    Name:\s*(.+?)\s*$/;
		$cur->{type} = $1 if /^    Type:\s*(\S+)/;
		$cur->{acc} = 1 if /^      (?:Right|Left|Both)_Accessory:\s*true/;
	}
	flush();
	undef $cur;
}

print "# Gerado por tools/gen_pickupitems.pl - nao edite a mao, rode o script de novo.\n";
print "# Formato: <id> <flag>  (0 = ignora, 2 = pega o mais rapido possivel)\n";
print "all 0\n";
my @sections = (['Extras', \@extra], ['Cartas', \@cards]);
push @sections, ['Acessorios', \@accs] unless $semAcc;
for my $section (@sections) {
	my ($title, $ids) = @$section;
	print "\n# --- $title (", scalar(@$ids), ") ---\n";
	printf "%d 2 # %s\n", $_, $name{$_} // '' for sort { $a <=> $b } @$ids;
}
