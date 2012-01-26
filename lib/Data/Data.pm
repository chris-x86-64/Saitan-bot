package SaitanBot::Data;

use strict;
use warnings;
use Encode;
use YAML::Syck;
use DBI;
use utf8;
use Data::Dumper;


my $conf = YAML::Syck::LoadFile('config.yml');

sub connectSQL {
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
	my ($text) = @_;

	return unless ($text);

	my $dbh = connectSQL();
	$dbh->do( "INSERT INTO texts(text) VALUES(?)", undef, $text ) or die DBI->errstr;

	foreach my $pattern ( @{ $conf->{souiu}->{patterns} } ) {
		if ( $text =~ decode_utf8($pattern) ) {
			$dbh->do( "INSERT INTO souiu(word) VALUES(?)",
				undef, $1 );
		}
	}

#	my @result = 
#		map { $dbh->do("INSERT INTO souiu(word) VALUES(?)", undef, $_) }
#		grep { $_ } 
#		map { $text =~ /$_/ ? $1 : undef } 
#		map { decode_utf8($_) } @{ $conf->{souiu}->{patterns} };
	disconnectSQL($dbh);

}

sub markov {
	use MeCab;

	my $dbh = connectSQL();
	my $source = $dbh->selectcol_arrayref('SELECT text FROM texts WHERE id >= (SELECT MAX(id) FROM texts) - 20');
	disconnectSQL($dbh);

	my $text = join("。", @$source);
	$text = decode_utf8($text);
	$text =~ s/@[a-zA-Z0-9_]*//g;
	$text =~ s/(QT|RT)//g;

	my @nouns;
	my @verbs;

	my $mecab  = MeCab::Tagger->new;

	for (my $node = $mecab->parseToNode($text); $node; $node = $node->{next}) {
		next unless defined $node->{surface};

		my $surface = $node->{surface};
		my $type = decode_utf8((split(",", $node->{feature}))[0]);

		if ($type eq '名詞') {
			push (@nouns, $surface);
		} elsif ($type eq '動詞') {
			push (@verbs, $surface);
		}
		next;
	}
	undef $text;

	my $struct = decode_utf8($source->[rand(@$source)]);
	my @final;

	for (my $node = $mecab->parseToNode($struct); $node; $node = $node->{next}) {
		next unless defined $node->{surface};

		my $surface = $node->{surface};
		my $type = decode_utf8((split(",", $node->{feature}))[0]);

		if ($type eq '名詞') {
			push (@final, $nouns[rand(@nouns)]);
		} elsif ($type eq '動詞') {
			push (@final, $verbs[rand(@verbs)]);
		} else {
			push (@final, $surface);
		}

		next;
	}

	return decode_utf8(join("", @final));
}

sub disconnectSQL {
	my $dbh = shift;
	$dbh->disconnect;
}

1;
