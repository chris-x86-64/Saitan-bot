package SaitanBot;

use strict;
use warnings;
use Encode;
use utf8;
use Net::Twitter::Lite::WithAPIv1_1;
use YAML::Syck;
use AnyEvent;
use lib './lib';
use SaitanBot::Data;

# Read OAuth keys from the (UTF-8) config file
local $YAML::Syck::ImplicitUnicode = 1;

sub new {
	my($class, $opt) = @_;

	my $conf = YAML::Syck::LoadFile('config.yml');

	my $self = bless {
		conf    => $conf,
		
		# Initiate Twitter-API methods
		actions => Net::Twitter::Lite::WithAPIv1_1->new(
			consumer_key        => $conf->{oauth}->{consumer_key},
			consumer_secret     => $conf->{oauth}->{consumer_secret},
			access_token        => $conf->{oauth}->{access_token},
			access_token_secret => $conf->{oauth}->{access_token_secret},
			ssl                 => 1,
			traits              => [qw/API::REST OAuth WrapError/],
		),
	}, $class;

	# Gets user data
	$self->{whoami} = $self->{actions}->verify_credentials;
	$self->{id} = $self->{whoami}->{id};

	return $self;
}

sub is_myself {
	my ($self, $source) = @_;
	return 1 if ($source == $self->{id});
	return undef;
}

# Gives OAuth keys to AnyEvent::Twitter::Stream
sub oauth_keys_stream {
	my $self = shift;

	my $conf = $self->{conf};
	my %oauth = (
		consumer_key    => $conf->{oauth}->{consumer_key},
		consumer_secret => $conf->{oauth}->{consumer_secret},
		token           => $conf->{oauth}->{access_token},
		token_secret    => $conf->{oauth}->{access_token_secret},
	);

	return %oauth;
}

sub wakeup {
	my $self = shift;

	my $status = decode_utf8($self->{conf}->{wakeup});
	$self->_talk( $status, undef );
}

sub shutdown {
	my $self = shift;

	my $status = decode_utf8("またね！");
	$self->_talk( $status, undef );
}

# Detects follow then automatically refollow
sub refollow {
	my ($self, $source) = @_;

# Follow the account which has just followed you
	$self->{actions}->create_friend( {
			user_id => $source
		}
	);

	print "Refollowed $source\n";
}

sub react {
	my ($self, $tweet) = @_;
	
	my $source_user = $tweet->{user}{screen_name};
	
	my $id           = $tweet->{id};
	my $text         = decode_utf8( $tweet->{text} );

	if (&SaitanBot::Data::souiu($text) and rand < $self->{conf}->{souiu}->{prob}) {
		my $match = &SaitanBot::Data::souiu($text);
		my $status = "ああ".$match."ってそういう...";
		$self->_talk(decode_utf8($status), undef);
		return;
	} else {
		my $is_mentioned = $self->_is_mentioned( $tweet, $source_user );
		my $category     = $self->_check_category( $text, $is_mentioned );

		$self->_prepare_reply( $source_user, $id, $category, $is_mentioned );
	}
}

sub add_data {
	my ($self, $tweet) = @_;

	my $text = $tweet->{text};
	$text = $tweet->{retweeted_status}->{text} if ($tweet->{retweeted_status});

	if ($tweet->{entities}->{urls}->[0]) {
		warn "DEBUG: URL detected\n";
		my @urls;
		push (@urls, $_->{url}) foreach @{$tweet->{entities}->{urls}};
		$text =~ s/$_//g foreach @urls;
	}

	&SaitanBot::Data::add_data( decode_utf8($text) );
}

sub _prepare_reply {
	my ( $self, $source_user, $reply_id, $category, $is_mentioned ) = @_;

	my $status = '@' . $source_user . ' ';

	if ( $category eq 'unknown' and $is_mentioned == 0 ) {
		return;
	}
	elsif ( $category eq 'unknown' and $is_mentioned == 1 ) {
		$status .= SaitanBot::Data->random;
	}
	else {
		my $replies = $self->{conf}->{$category}->{replies};

		my $reply_string = $replies->[ int( rand( scalar @$replies ) ) ];
		$status .= $reply_string;
	}
	$self->_talk( $status, $reply_id );
}

sub _check_category {
	my ( $self, $text, $is_mentioned ) = @_;

	my $conf = $self->{conf};
	foreach my $category ( @{ $conf->{categories} } ) {
		foreach my $keyword ( @{ $conf->{$category}->{keywords} } ) {
			if ( $text =~ decode_utf8($keyword) ) {
				return $category;
				last;
			}
		}
	}
	if ( $is_mentioned == 1 ) {
		foreach my $replyonly ( @{ $conf->{replyonly} } ) {
			foreach
			my $keyword ( @{ $conf->{$replyonly}->{keywords} } )
			{
				if ( $text =~ decode_utf8($keyword) ) {
					return $replyonly;
					last;
				}
			}
		}
	}
	return "unknown";
}

sub _is_mentioned {
	my ( $self, $tweet, $source_user ) = @_;

	foreach my $mention ( @{ $tweet->{entities}{user_mentions} } ) {
		if ( $mention->{screen_name} eq $self->{whoami}->{screen_name} ) {
			print "Detected mention from $source_user.\n";
			return 1;
			last;
		}
	}
	return 0;
}

sub fav {
	my ($self, $tweet) = @_;

	my $text = $tweet->{text};
	my $fav_id = $tweet->{id};

	my $conf = $self->{conf};

	foreach my $keyword ( @{ $conf->{fav}->{keywords} } ) {
		if ( $text =~ decode_utf8($keyword) ) {
			eval { $self->{actions}->create_favorite($fav_id); };
			if ($@) {
				if ( $@ =~ /favorite per day/ ) {
					$self->_talk(
						decode_utf8("ふぁぼ規制ﾅｰｰｰｰｰｰｰｰｰｰｰｰｰｰ"),
						undef
					);
					$self->{favlimit} = 1;
					warn "$@\n";
				}
				else {
					$self->_talk(
						decode_utf8("ふぁぼ失敗なう＞＜ 当該ID: $fav_id"),
						undef
					);
					warn "$@\n";
				}
			}
			else {
				&SaitanBot::Data::register_faved($text);
				$self->{favlimit} = 0;
				print "Favorited: $fav_id\n";
				last;
			}
		}
	}
	return;
}

sub _talk {
	#		return if ($limit == 1);
	my ( $self, $status, $reply_id ) = @_;
	eval {
		$self->{actions}->update(
			{
				status                => decode_utf8($status),
				in_reply_to_status_id => $reply_id,
			}
		);
	};
	if ($@) {
		warn "$status ... Could not be posted: $@\n";
		if ( $@ =~ /duplicate/ ) {
			$status .= ' #' . int( rand(256) );
			$self->_talk( $status, $reply_id );
		}
		elsif ( $@ =~ /limit/ ) {
			$self->{limit} = 1;
			$self->_limit;
		}
	}
	else {
		print $status, "\n";
		$self->{limit} = 0;
		return 1;
	}
}

sub talk_randomly {
	my ($self, $wait) = @_;

	$wait = rand( $self->{conf}->{interval} ) unless defined $wait;

	my $cv = AE::cv;
	my $timed;
	$timed = AE::timer(
		$wait, 0,
		sub {
			$self->_talk( SaitanBot::Data->random, undef );
			undef $timed;
			$cv->send;
		},
	);
	$cv->recv;
	$self->talk_randomly( rand( $self->{conf}->{interval} ) );
}

sub _limit {
	my $self = shift;
	
	my $hashtag = ' #' . int( rand(256) );
	my $cv      = AE::cv;
	my $timer;
	$timer = AE::timer(
		600,
		600,
		sub {
			my $status = $self->_talk( decode_utf8("規制解除てす$hashtag"), undef );

			if ( $status == 1 ) {
				$self->{limit} = 0;
				undef $timer;
				$cv->send;
			}
		},
	);
	$cv->recv;
}
1;
