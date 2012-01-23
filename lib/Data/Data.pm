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
	use Algorithm::MarkovChain;

	my $dbh = connectSQL();
	my $text = join(
			"。",
			@{
					$dbh->selectcol_arrayref(
'SELECT text FROM texts WHERE id >= (SELECT MAX(id) FROM texts) - 20'
					)
			  }
	);
	disconnectSQL($dbh);

	$text = decode_utf8($text);
	$text =~ s/(\@|\/|\:|[0-9A-Za-z_]|\#|)//g;

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
	warn join(",", @$chunks),"\n";

	my $chain = Algorithm::MarkovChain->new;
	$chain->seed(
		symbols => $chunks,
		longest => 8,
	);

	my @scrambled = $chain->spew( 
			length => int(rand(8)),
			strict_start => 1,
	);

	my $scrambled = '';
	foreach my $chunk (@scrambled) {
		$scrambled .= decode_utf8($chunk);
	}

	return $scrambled;
}

sub disconnectSQL {
	my $dbh = shift;
	$dbh->disconnect;
}
1;
