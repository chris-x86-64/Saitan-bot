package SaitanBot;

use strict;
use warnings;
use Encode;
use utf8;
use lib './lib';
use SaitanBot::Think;

sub new {
	my ($class, $opt) = @_;
	my $self = bless {
		brain => SaitanBot::Think->new({ dbname => $opt->{dbname} })
	}, $class;

	return $self;
}

sub reply {
	my ($self, $target) = @_
	my $status = '@' . $target->{userid} . ' ';

}

sub random {
	my $self = shift;
	return $self->{brain}->create_tweet;
}

1;
