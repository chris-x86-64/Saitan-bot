package SaitanBot::Data;

use strict;
use Encode;
use YAML::Syck;
use DBI;
use utf8;

sub new {
	my $class = shift;

	my $self = bless {
		conf => YAML::Syck::LoadFile('config.yml'),
	}, $class;

	$self->_init_db;
}

sub _init_db {
	my $self = shift;

	$self->{dbh} = DBI->connect(
		"dbi:mysql:$self->conf->{sql}->{dbname}",
		$self->conf->{sql}->{username},
		$self->conf->{sql}->{password},
	);

	$self->{dbh}->{'mysql_enable_utf8'} = 1;
	$self->{dbh}->do('SET NAMES utf8');
}

sub add_data {
	my ($self, $text) = @_;

	return unless ($text);

	$self->{dbh}->do( "INSERT INTO texts(text) VALUES(?)", undef, $text );

	my @result = 
		map { $self->{dbh}->do("INSERT INTO souiu(word) VALUES(?)", undef, $_) }
		grep { $_ } 
		map { $text =~ decode_utf($_) ? $1 : undef } @{ $self->{conf}->{souiu}->{patterns} };

	# foreach my $pattern ( @{ $conf->{souiu}->{patterns} } ) {
	# 	if ( $text =~ decode_utf8($pattern) ) {
	# 		my $match = $1;
	# 		$dbh->do( "INSERT INTO souiu(word) VALUES(?)",
	# 			undef, $match );
	# 	}
	# }
}

sub markov {
	my $self = shift;

	use MeCab;
	use Algorithm::MarkovChain;

	my $text = join(
		"",
		@{ $dbh->selectcol_arrayref(
			'SELECT text FROM texts WHERE id >= (SELECT MAX(id) FROM texts) - 100'
		) }
	);
	$text = decode_utf8($text);

	$self->{dbh}->disconnect;

	my $mecab  = MeCab::Tagger->new;
	my $chunks = [];

	for (
		my $node = $mecab->parseToNode($text) ;
		$node ;
		$node = $node->{next}
	)
	{
		next unless defined $node->{surface};
		push @$chunks, $node->{surface};
	}

	my $chain = Algorithm::MarkovChain->new;
	$chain->seed(
		symbols => $chunks,
		longest => 4,
	);

	my @scrambled = $chain->spew( length => int(rand(20)), );

	my $scrambled = '';
	foreach my $chunk (@scrambled) {
		$scrambled .= decode_utf8($chunk);
	}
	$scrambled =~ s/\@//g;

	return $scrambled;
}

sub DESTROY {
	$self->{dbh}->disconnect;
}

1;
