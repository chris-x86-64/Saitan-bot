package SaitanBot::Think;

use strict;
use warnings;
use Encode;
use Data::Dumper;
use utf8;
use Exporter;
use MeCab;
use Algorithm::MarkovChain;

use lib './lib';
use SaitanBot::Database;

my @ISA = qw(Exporter);
my @EXPORT = ();

sub new {
	my ($class, $opt) = @_;
	my $self = bless {
		dbwrapper => SaitanBot::Database->new($opt->{conf}->{sqlite}),
		markov => Algorithm::MarkovChain->new,
	}, $class;
	$self->{conf} = $opt->{conf};
	return $self;
}


sub store_souiu {
	my ($self, $text) = @_;
	my $dbh = $self->{dbh};
	my $souiu_patterns = $self->{conf}->{souiu}->{patterns};
	foreach my $pattern (@{ $souiu_patterns }) {
		if ($text =~ decode_utf8($pattern)) {
			$_ = $1;
			s/、//g;
			$dbh->insert('souiu', { word => $_ }) if ($dbh->select('souiu', 'word', { word => $_ })->rows == 0);
		}
	}
}

sub generate_tweet {
	my $self = shift;
	my $dbh = $self->{dbwrapper};
	return $self->_randomize($self->_tagger($dbh->get_tweets_from_db));
}

sub is_souiu {
	my ($self, $text) = @_;
	my $keywords = $self->{dbwrapper}->get_souiu;

	foreach (@$keywords) {
		my $word = decode_utf8($_);
		if ($text =~ /\Q$word\E/) {
			return $word;
		}
	}
	return undef;
}

sub categorize {
}

sub _tagger {
	my ($self, $data) = @_;
	
	my $text = join(encode_utf8("。\n"), $data->flat);
	my $mecab = MeCab::Tagger->new;

	my $chunks = [];
	for (my $node = $mecab->parseToNode($text); $node; $node = $node->{next}) {
		push (@$chunks, $node->{surface});
	}

	return $chunks;
}

sub _randomize {
	my ($self, $data) = @_;
	my $chain = $self->{markov};
	my $param = rand(20);
	$chain->seed(symbols => $data, longest => $param);

	return join("", $chain->spew(
			length => $param,
			stop_at_terminal => 1,
		)
	);
}

1;
