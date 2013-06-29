package SaitanBot::Database;

use strict;
use warnings;
use Encode;
use utf8;
use Exporter;
use DBIx::Simple;
use SQL::Abstract::Limit;

my @ISA = qw(Exporter);
my @EXPORT = ();

sub new {
	my ($class, $opt) = @_;
	my $self = bless {
		dbh => DBIx::Simple->connect('dbi:SQLite:dbname=' . $opt->{dbpath}),
	}, $class;
	$self->{dbh}->abstract = SQL::Abstract->new;
	$self->{dbh}->{sqlite_unicode} = 1;

	return $self;
}

sub store_tweet_to_db {
	my ($self, $tweet, $dbargs) = @_;
	return unless ($tweet->{text});

	my $text = $tweet->{retweeted_status} ? $tweet->{retweeted_status}->{text} : $tweet->{text};
	$text = decode_utf8($text);

	$text =~ s/$_->{url}//g foreach (@{$tweet->{entities}->{urls}});

	my $dbh = $self->{dbh};
	$dbh->insert($dbargs->{table},
		{
			$dbargs->{column} => $text
		}
	);
}

sub get_tweets_from_db {
	my $self = shift;
	my $dbh = $self->{dbh};
	$dbh->abstract = SQL::Abstract::Limit->new(limit_dialect => $dbh->{dbh});
	my $data = $dbh->select('tweets', 'text', undef, 'id desc', 20, 0);
	return $data;
}

sub get_souiu {
	my ($self, $text) = @_;
	my $dbh = $self->{dbh};
	return $dbh->select('souiu', 'word')->array;
}

1;
