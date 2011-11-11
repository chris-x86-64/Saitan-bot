package TextData;

use strict;
use Encode;
use YAML::Syck;
use DBI;
use utf8;

my $conf = YAML::Syck::LoadFile('config.yml');

sub db {
		my $dbh = DBI->connect(
				"dbi:mysql:$conf->{sql}->{dbname}",
				$conf->{sql}->{username},
				$conf->{sql}->{password},
		);
		$dbh->{'mysql_enable_utf8'} = 1;
		$dbh->do('SET NAMES utf8');
		return $dbh;
}

sub add_data {
		my $text = shift;
		my $dbh = &db;
		$dbh->do("INSERT INTO texts(text) VALUES(?)", undef, $text) unless (!defined $text);
		$dbh->disconnect;
}

sub markov {
		use MeCab;
		use Algorithm::MarkovChain;

		my $dbh = &db;
		my $text = join ("", @{$dbh->selectcol_arrayref('SELECT text FROM texts WHERE id >= (SELECT MAX(id) FROM texts) - 60')});
		$text = decode_utf8($text);

		$dbh->disconnect;

		my $mecab = MeCab::Tagger->new;
		my $chunks = [];

		for (my $node = $mecab->parseToNode($text); $node; $node = $node->{next}) {
				next unless defined $node->{surface};
				push @$chunks, $node->{surface};
		}

		my $chain = Algorithm::MarkovChain->new;
		$chain->seed(
				symbols => $chunks,
				longest => 4,
		);

		my @scrambled = $chain->spew(
				length => 5,
		);
		
		my $scrambled = '';
		foreach my $chunk (@scrambled) {
				$scrambled .= decode_utf8($chunk);
		}
		$scrambled =~ s/\@//g;
		
		return $scrambled;
}

1;
