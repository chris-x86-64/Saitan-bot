package SaitanBot::Think;

use strict;
use warnings;
use Encode;
use utf8;
use DBIx::Simple;
use SQL::Abstract::Limit;
use MeCab;
use Algorithm::MarkovChain;

sub new {
	my ($class, $opt) = @_;
	my $self = bless {
		dbh => DBIx::Simple->connect('dbi:SQLite:dbname=' . $opt->{dbname}),
		markov => Algorithm::MarkovChain->new;
	}, $class;
	$self->{dbh}->abstract = SQL::Abstract->new;
	$self->{dbh}->{sqlite_unicode} = 1;
	return $self;
}

sub store_tweet {
	my ($self, $text) = @_;
	return unless ($text);

	my $dbh = $self->{dbh};
	$dbh->insert('tweets', { text => $text });

	foreach my $pattern (@{ $souiu_patterns }) {
		if ($text =~ decode_utf8($pattern)) {
			$_ = $1;
			s/、//g;
			$dbh->insert('souiu', { word => $_ });
		}
	}
}

sub create_tweet {
	my $self = shift;
	my $dbh = $self->{dbh};
	$dbh->abstract = SQL::Abstract::Limit->new(limit_dialect => $dbh->{dbh});
	my $data = $dbh->select('tweets', ['text'], undef, ['id'], 20, 0)->arrays;
	return $self->_randomize($self->_tagger($data));
}

sub _tagger {
	my ($self, $data) = @_;
	my $mecab = MeCab::Tagger->new;
	my $text = join("。", @$data);
	my $chunks = [];

	for (my $node = $mecab->parseToNode($text); $node; $node = $node->{next}) {
		push (@$chunks, $node->{surface});
	}

	return $chunks;
}

sub _randomize {
	my ($self, $data) = @_;
	my $chain = $self->{markov};
	$chain->seed(symbols => $data, longest => 4);

	return [$chain->spew(length => 6, stop_at_terminal => 1)];
}

1;
